extends Node

const MATCHMAKING_CLIENT_SCRIPT = preload("res://matchmaking/matchmaking_client.gd")
const DEFAULT_COORDINATOR_URL := \
	"https://one-gun-match-coordinator-dev.one-gun-dev.workers.dev"
const EXPECTED_MAP := "res://maps/test/ForestMap.tscn"
const TIMEOUT_MSEC := 240000

var role := ""
var coordinator_url := DEFAULT_COORDINATOR_URL
var deadline_msec := 0
var assignment_host := ""
var assignment_port := 0
var _finished := false
var _matchmaking: OneGunMatchmakingClient


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--url="):
			coordinator_url = argument.trim_prefix("--url=").strip_edges().trim_suffix("/")
	if role not in ["controller", "guest"]:
		_fail("missing --role=controller|guest")
		return
	call_deferred("_detach_and_run")


func _detach_and_run() -> void:
	reparent(get_tree().root)
	deadline_msec = Time.get_ticks_msec() + TIMEOUT_MSEC
	_matchmaking = MATCHMAKING_CLIENT_SCRIPT.new()
	_matchmaking.progress_changed.connect(_on_matchmaking_progress)
	_matchmaking.assignment_ready.connect(_on_assignment_ready)
	_matchmaking.queue_failed.connect(_on_queue_failed)
	add_child(_matchmaking)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.compatibility_rejected.connect(_on_compatibility_rejected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	print("[LIVE MATCHMAKING %s] Starting public coordinator queue" % role)
	if not _matchmaking.start_queue(coordinator_url):
		_fail("queue did not start")
		return
	while not _finished and Time.get_ticks_msec() < deadline_msec:
		if _live_match_ready():
			await get_tree().create_timer(1.5).timeout
			if not _live_match_ready():
				_fail("live match became unavailable before verification completed")
				return
			_finished = true
			print("LIVE_MATCHMAKING_HEADLESS_PASS %s endpoint=%s:%d" % [
				role, assignment_host, assignment_port])
			NetworkManager.disconnect_net()
			await get_tree().create_timer(0.25).timeout
			if _matchmaking != null:
				_matchmaking.queue_free()
				_matchmaking = null
			await get_tree().process_frame
			get_tree().quit(0)
			return
		await get_tree().process_frame
	if not _finished:
		_fail("timed out before two assigned clients reached the live Forest match")


func _on_matchmaking_progress(message: String) -> void:
	print("[LIVE MATCHMAKING %s] %s" % [role, message])


func _on_assignment_ready(host: String, port: int, ticket: String) -> void:
	assignment_host = host
	assignment_port = port
	print("[LIVE MATCHMAKING %s] Assigned endpoint %s:%d" % [role, host, port])
	if not NetworkManager.join_game(host, port, ticket):
		_fail("assigned ENet connection could not start")


func _on_queue_failed(title: String, message: String) -> void:
	_fail("%s: %s" % [title, message])


func _on_connection_failed() -> void:
	_fail("assigned server connection failed")


func _on_compatibility_rejected(reason: String, detail: String) -> void:
	_fail("server rejected compatibility (%s): %s" % [reason, detail])


func _on_server_disconnected() -> void:
	if not _finished:
		_fail("assigned server disconnected before the live-match gate")


func _live_match_ready() -> bool:
	if assignment_host == "" or not NetworkManager.is_online() \
			or not NetworkManager.is_dedicated_session() \
			or not NetworkManager.match_server_mode:
		return false
	if NetworkManager.peers.size() != 2 \
			or NetworkManager.participant_peer_ids().size() != 2:
		return false
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != EXPECTED_MAP:
		return false
	var players := scene.get_node_or_null("NetPlayers")
	var manager := scene.get_node_or_null("RoundManager")
	return players != null and players.get_child_count() == 2 \
		and manager != null and bool(manager.get("online_combat_live"))


func _fail(message: String) -> void:
	if _finished:
		return
	_finished = true
	if _matchmaking != null:
		_matchmaking.cancel_queue()
	if NetworkManager.is_online():
		NetworkManager.disconnect_net()
	push_error("LIVE_MATCHMAKING_HEADLESS_FAIL %s: %s" % [role, message])
	get_tree().quit(1)
