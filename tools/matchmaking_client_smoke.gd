extends Node

const MATCHMAKING_CLIENT_SCRIPT = preload("res://matchmaking/matchmaking_client.gd")
const TIMEOUT_MSEC := 15000

var _finished := false


func _ready() -> void:
	var port := 24810
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
	var client: OneGunMatchmakingClient = MATCHMAKING_CLIENT_SCRIPT.new()
	client.assignment_ready.connect(_on_assignment)
	client.queue_failed.connect(_on_failure)
	add_child(client)
	if not client.start_queue("http://127.0.0.1:%d" % port):
		_fail("queue did not start")
		return
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while not _finished and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not _finished:
		_fail("assignment timed out")


func _on_assignment(host: String, port: int, ticket: String) -> void:
	if host != "validation.pr.edgegap.net" or port != 30937 or ticket != "smoke-ticket-alpha":
		_fail("assignment fields were not preserved")
		return
	_finished = true
	print("MATCHMAKING CLIENT CONTRACT: PASS")
	get_tree().quit(0)


func _on_failure(title: String, message: String) -> void:
	_fail("%s: %s" % [title, message])


func _fail(message: String) -> void:
	_finished = true
	push_error("MATCHMAKING CLIENT CONTRACT: FAIL — %s" % message)
	get_tree().quit(1)
