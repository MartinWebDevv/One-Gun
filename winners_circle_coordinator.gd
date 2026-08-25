class_name WinnersCircleCoordinator
extends Node

const WinnersCircle = preload("res://UI/winners_circle.gd")
const RewardCalculator = preload("res://match_reward_calculator.gd")

signal local_return_requested

var _overlay: CanvasLayer = null
var _result: Dictionary = {}
var _ready_peers: Dictionary = {}
var _session_generation := 0
var _returning := false
var _presentation_started_msec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not NetworkManager.lobby_changed.is_connected(_on_lobby_changed):
		NetworkManager.lobby_changed.connect(_on_lobby_changed)


func begin_online(result: Dictionary) -> void:
	if not NetworkManager.is_host() or _returning:
		return
	_result = result.duplicate(true)
	_ready_peers.clear()
	_presentation_started_msec = Time.get_ticks_msec()
	_returning = false
	_session_generation += 1
	var generation := _session_generation
	NetworkManager.broadcast_match_rpc(self, &"_net_show", [_result])
	_publish_ready_state()
	_auto_return(generation)


func show_local(result: Dictionary, viewer_actor_ids: Array) -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_result = result.duplicate(true)
	_overlay = WinnersCircle.new()
	get_tree().current_scene.add_child(_overlay)
	_overlay.local_return_requested.connect(func() -> void:
		local_return_requested.emit())
	_overlay.present(_result, viewer_actor_ids, false, true)


@rpc("authority", "reliable", "call_local")
func _net_show(result: Dictionary) -> void:
	if NetworkManager.is_dedicated_server():
		return
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	var local_result := result.duplicate(true)
	local_result["local_peer_id"] = NetworkManager.local_id()
	var viewer_actor_ids: Array[int] = []
	if NetworkManager.local_match_role == "participant":
		var actor_id := NetworkManager.actor_id_for_peer(NetworkManager.local_id())
		if actor_id >= 0:
			viewer_actor_ids.append(actor_id)
	_overlay = WinnersCircle.new()
	get_tree().current_scene.add_child(_overlay)
	_overlay.ready_changed.connect(_on_ready_changed)
	_overlay.force_return_requested.connect(_on_force_return)
	_overlay.present(local_result, viewer_actor_ids, true, NetworkManager.is_host())
	_submit_local_reward.call_deferred(local_result, viewer_actor_ids)


func _submit_local_reward(local_result: Dictionary,
		viewer_actor_ids: Array[int]) -> void:
	if not bool(local_result.get("official", false)) or viewer_actor_ids.is_empty():
		return
	var actor_id := int(viewer_actor_ids[0])
	var secret := RewardIdentityManager.local_claim_secret()
	if secret == "":
		return
	var preview := RewardCalculator.preview_for_actor(local_result, actor_id)
	preview["state"] = "verifying"
	if _overlay != null and _overlay.has_method("set_actor_reward"):
		_overlay.call("set_actor_reward", actor_id, preview)
	var receipt: Dictionary = await ProgressionManager.confirm_official_match(
		local_result, actor_id, secret)
	if _overlay != null and _overlay.has_method("set_actor_reward"):
		_overlay.call("set_actor_reward", actor_id, receipt)


func _on_ready_changed(is_ready: bool) -> void:
	if NetworkManager.is_host():
		_host_set_ready(NetworkManager.local_id(), is_ready)
	elif NetworkManager.is_online():
		_request_ready.rpc_id(1, is_ready)


@rpc("any_peer", "reliable")
func _request_ready(is_ready: bool) -> void:
	if multiplayer.is_server():
		_host_set_ready(multiplayer.get_remote_sender_id(), is_ready)


func _host_set_ready(peer_id: int, is_ready: bool) -> void:
	if not NetworkManager.is_host() or _result.is_empty() or _returning:
		return
	var required := _required_peer_ids()
	if peer_id not in required:
		return
	if is_ready:
		_ready_peers[peer_id] = true
	else:
		_ready_peers.erase(peer_id)
	_publish_ready_state()
	if not required.is_empty() and required.all(func(id):
		return _ready_peers.has(int(id))):
		_schedule_return(_minimum_safe_delay(3.0))


func _required_peer_ids() -> Array:
	var required: Array = []
	for entry_value in _result.get("entries", []):
		var entry: Dictionary = entry_value
		var peer_id := int(entry.get("peer_id", -1))
		if peer_id > 0 and not bool(entry.get("is_bot", false)) \
				and NetworkManager.peers.has(peer_id):
			required.append(peer_id)
	required.sort()
	return required


func _publish_ready_state() -> void:
	if not NetworkManager.is_host() or _result.is_empty():
		return
	for peer_id in _ready_peers.keys():
		if not NetworkManager.peers.has(int(peer_id)):
			_ready_peers.erase(peer_id)
	var ready_ids := _ready_peers.keys()
	ready_ids.sort()
	NetworkManager.broadcast_match_rpc(self, &"_net_apply_ready",
		[ready_ids, _required_peer_ids()])


@rpc("authority", "reliable", "call_local")
func _net_apply_ready(ready_peer_ids: Array, required_peer_ids: Array) -> void:
	if _overlay != null:
		_overlay.set_ready_peers(ready_peer_ids, required_peer_ids)


func _on_force_return() -> void:
	if NetworkManager.is_host():
		_schedule_return(_minimum_safe_delay(0.75))


func _minimum_safe_delay(requested_seconds: float) -> float:
	if _presentation_started_msec <= 0:
		return requested_seconds
	var elapsed := float(Time.get_ticks_msec() - _presentation_started_msec) / 1000.0
	var until_minimum := maxf(WinnersCircle.MINIMUM_VIEW_TIME - elapsed, 0.0)
	return maxf(requested_seconds, until_minimum)


func _schedule_return(seconds: float) -> void:
	if not NetworkManager.is_host() or _returning:
		return
	_returning = true
	NetworkManager.broadcast_match_rpc(self, &"_net_start_return", [seconds])
	await get_tree().create_timer(maxf(seconds, 0.25), true).timeout
	if is_inside_tree() and NetworkManager.is_host():
		NetworkManager.host_return_everyone_to_lobby()


@rpc("authority", "reliable", "call_local")
func _net_start_return(seconds: float) -> void:
	if _overlay != null:
		_overlay.start_return_countdown(seconds)


func _auto_return(generation: int) -> void:
	await get_tree().create_timer(WinnersCircle.AUTO_RETURN_TIME, true).timeout
	if not is_inside_tree() or not NetworkManager.is_host() \
			or generation != _session_generation or _returning:
		return
	_schedule_return(0.75)


func _on_lobby_changed() -> void:
	if NetworkManager.is_host() and not _result.is_empty() and not _returning:
		_publish_ready_state()
