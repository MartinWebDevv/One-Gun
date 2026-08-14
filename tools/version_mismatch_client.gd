extends Node

const BuildInfo = preload("res://build_info.gd")
const DEFAULT_TEST_PORT := 24757

var _finished := false


func _ready() -> void:
	NetworkManager.compatibility_rejected.connect(_on_connection_rejected)
	multiplayer.connected_to_server.connect(_send_mismatched_hello)
	var port := _argument_int("port", DEFAULT_TEST_PORT)
	if not NetworkManager.join_game("127.0.0.1", port):
		_fail("could not start ENet client")
		return
	_timeout_after(10.0)


func _send_mismatched_hello() -> void:
	var payload := BuildInfo.compatibility_payload()
	payload["protocol"] = BuildInfo.NETWORK_PROTOCOL + 1
	NetworkManager._register_client_hello.rpc_id(1, payload, "Mismatch Test", "blue")


func _on_connection_rejected(reason: String, detail: String) -> void:
	if reason != BuildInfo.REJECTION_NETWORK_PROTOCOL:
		_fail("unexpected rejection reason '%s'" % reason)
		return
	if not detail.contains("Host: %d" % BuildInfo.NETWORK_PROTOCOL):
		_fail("rejection detail omits the host protocol")
		return
	await get_tree().process_frame
	if NetworkManager.is_online():
		_fail("rejected client remained online")
		return
	if not NetworkManager.peers.is_empty():
		_fail("rejected client received a lobby roster")
		return
	_finished = true
	print("VERSION_MISMATCH_CLIENT_PASS reason=%s" % reason)
	get_tree().quit(0)


func _timeout_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if not _finished:
		_fail("timed out waiting for protocol rejection")


func _argument_int(key: String, fallback: int) -> int:
	var prefix := "--%s=" % key
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return int(argument.trim_prefix(prefix))
	return fallback


func _fail(message: String) -> void:
	if _finished:
		return
	_finished = true
	push_error("VERSION_MISMATCH_CLIENT_FAIL: %s" % message)
	get_tree().quit(1)
