extends SceneTree

# Two-process smoke test for Section 5 host authority. Launch one process with
# `-- --role=host` and a second with `-- --role=client`.

const PORT := 24615
const TIMEOUT := 12.0
var _role := ""
var _network
var _config
var _prefs
var _chat_ui
var _chat_messages: Array = []
var _original_skin_id := ""
var _original_model_id := ""
var _appearance_changed := false


func _initialize() -> void:
	_network = root.get_node("NetworkManager")
	_config = root.get_node("GameConfig")
	_prefs = root.get_node("PlayerPrefs")
	_chat_ui = root.get_node("OnlineChat")
	_network.chat_message_received.connect(_on_chat_message_received)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			_role = argument.trim_prefix("--role=")
	_run.call_deferred()


func _run() -> void:
	if _role == "host": await _run_host()
	elif _role == "client": await _run_client()
	else:
		push_error("Missing --role=host|client")
		quit(2)


func _run_host() -> void:
	if not _network.host_game(PORT, "Authority Test", {"privacy": "public", "share_code": "TEST55"}):
		quit(3)
		return
	_chat_ui._open_window()
	if not _chat_ui.is_window_open():
		_fail("chat window did not open")
		return
	var chat_panel := _chat_ui.get("_panel") as Control
	if chat_panel == null or chat_panel.anchor_right > 0.32 or chat_panel.anchor_top < 0.68:
		_fail("chat panel did not use the compact layout")
		return
	_chat_ui._show_actor_bubble(1, "Host", "Bubble validation")
	var bubbles: Dictionary = _chat_ui.get("_bubbles")
	if not bubbles.has(1) or not is_instance_valid(bubbles[1].get("panel")) \
			or not is_instance_valid(bubbles[1].get("tail")):
		_fail("player chat bubble and pointer did not build")
		return
	_chat_ui._clear_bubbles()
	_chat_ui._start_typing()
	if not _chat_ui.is_typing():
		_fail("chat composition did not capture input")
		return
	_chat_ui._finish_typing(false)
	_chat_ui._close_window()
	_chat_ui._show_notification("Guest", "Notification validation")
	var notifications: Array = _chat_ui.get("_notifications")
	if chat_panel.visible or notifications.size() != 1:
		_fail("closed-chat delivery opened history instead of one notification card")
		return
	_chat_ui._clear_notifications()
	print("LOBBY TEST OK: chat history stayed closed and notification card built")
	_config.set_bot_count(2)
	_network.broadcast_match_config(_config.snapshot_for_preset(), "res://maps/test/ForestMap.tscn")
	if not await _wait_until(func(): return _network.peers.size() == 2):
		_fail("host never received client roster")
		return
	if not await _wait_until(func():
		for peer_id in _network.peer_ids_sorted():
			if int(peer_id) != 1 \
					and _network.peer_skin_id(int(peer_id)) == "purple" \
					and _network.peer_model_id(int(peer_id)) == "female":
				return true
		return false
	):
		_fail("host never received the client's female appearance")
		return
	print("LOBBY TEST OK: female appearance synchronized to host roster")
	if not await _wait_until(func(): return _has_chat_message("Hello from client")):
		_fail("host never received client lobby chat")
		return
	if not _network.send_chat_message("Hello from host"):
		_fail("host lobby chat send was rejected")
		return
	print("LOBBY TEST OK: host received and replied to client chat")
	if not await _wait_until(func(): return _network.are_all_lobby_guests_ready()):
		_fail("host never received authoritative guest readiness")
		return
	print("LOBBY TEST OK: host received guest readiness")
	_network.reset_lobby_readiness("Validation reset")
	if _network.are_all_lobby_guests_ready():
		_fail("host readiness reset failed")
		return
	if not _network.set_lobby_privacy("private"):
		_fail("host privacy authority failed")
		return
	print("LOBBY TEST OK: host reset readiness and changed privacy")
	await create_timer(0.5).timeout
	var ids: Array = _network.peer_ids_sorted()
	var client_id := int(ids[1])
	if not _network.kick_peer(client_id):
		_fail("host kick was rejected")
		return
	if not await _wait_until(func(): return _network.peers.size() == 1):
		_fail("kicked client remained in roster")
		return
	print("LOBBY TEST OK: host kick removed client")
	_network.disconnect_net()
	quit(0)


func _run_client() -> void:
	await create_timer(0.45).timeout
	if not _network.join_game("127.0.0.1", PORT):
		quit(4)
		return
	if not await _wait_until(func(): return _network.peers.size() == 2):
		_fail("client never received roster")
		return
	if not await _wait_until(func(): return int(_config.bot_count) == 2):
		_fail("late-join match config did not synchronize")
		return
	print("LOBBY TEST OK: late-join match config synchronized")
	_original_skin_id = str(_prefs.get_setting("character_skin_id"))
	_original_model_id = str(_prefs.get_setting("character_model_id"))
	if not _network.set_local_appearance("purple", "female"):
		_fail("client female appearance update was rejected")
		return
	_appearance_changed = true
	if not _network.send_chat_message("Hello from client"):
		_fail("client lobby chat send was rejected")
		return
	if not await _wait_until(func(): return _has_chat_message("Hello from host")):
		_fail("client never received host lobby chat")
		return
	print("LOBBY TEST OK: client received host chat reply")
	if _network.set_lobby_privacy("private"):
		_fail("guest changed host-only privacy")
		return
	_network.set_local_lobby_ready(true)
	if not await _wait_until(func(): return _network.is_peer_lobby_ready(_network.local_id())):
		_fail("client readiness did not reconcile")
		return
	if not await _wait_until(func(): return not _network.is_peer_lobby_ready(_network.local_id())):
		_fail("client did not receive readiness reset")
		return
	print("LOBBY TEST OK: guest authority denied and reset received")
	if not await _wait_until(func(): return not _network.is_online()):
		_fail("guest was not disconnected by host kick")
		return
	print("LOBBY TEST OK: guest observed kick disconnect")
	_restore_client_appearance()
	quit(0)


func _wait_until(predicate: Callable) -> bool:
	var elapsed := 0.0
	while elapsed < TIMEOUT:
		if predicate.call(): return true
		await create_timer(0.05).timeout
		elapsed += 0.05
	return false


func _on_chat_message_received(sender_peer_id: int, sender_name: String,
		message: String, context: String) -> void:
	_chat_messages.append({
		"sender_peer_id": sender_peer_id,
		"sender_name": sender_name,
		"message": message,
		"context": context,
	})


func _has_chat_message(message: String) -> bool:
	for entry in _chat_messages:
		if entry.get("message", "") == message and entry.get("context", "") == "lobby":
			return true
	return false


func _restore_client_appearance() -> void:
	if not _appearance_changed:
		return
	var preferences: Dictionary = _prefs.snapshot()
	preferences["character_skin_id"] = _original_skin_id
	preferences["character_model_id"] = _original_model_id
	_prefs.apply_transaction(preferences)
	_appearance_changed = false


func _fail(message: String) -> void:
	push_error("LOBBY TEST FAILED: %s" % message)
	_restore_client_appearance()
	_network.disconnect_net()
	quit(1)
