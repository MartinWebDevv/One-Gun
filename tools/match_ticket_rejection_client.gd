extends Node

const DEFAULT_TEST_PORT := 24758

var _finished := false


func _ready() -> void:
	NetworkManager.compatibility_rejected.connect(_on_connection_rejected)
	var port := _argument_int("port", DEFAULT_TEST_PORT)
	if not NetworkManager.join_game("127.0.0.1", port, "not-an-assigned-ticket"):
		_fail("could not start ENet client")
		return
	_timeout_after(10.0)


func _on_connection_rejected(reason: String, detail: String) -> void:
	if reason != NetworkManager.REJECTION_MATCH_TICKET_INVALID:
		_fail("unexpected rejection reason '%s'" % reason)
		return
	if not detail.contains("not assigned"):
		_fail("ticket rejection detail was not useful")
		return
	await get_tree().process_frame
	if NetworkManager.is_online():
		_fail("rejected client remained online")
		return
	if not NetworkManager.peers.is_empty():
		_fail("rejected client received a roster")
		return
	_finished = true
	print("MATCH_TICKET_REJECTION_PASS reason=%s" % reason)
	get_tree().quit(0)


func _timeout_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if not _finished:
		_fail("timed out waiting for ticket rejection")


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
	push_error("MATCH_TICKET_REJECTION_FAIL: %s" % message)
	get_tree().quit(1)