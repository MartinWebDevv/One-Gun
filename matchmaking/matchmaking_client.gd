class_name OneGunMatchmakingClient
extends Node

const BuildInfo = preload("res://build_info.gd")
const CONFIG_PATH := "res://matchmaking/coordinator_config.json"
const REQUEST_TIMEOUT_SECONDS := 15.0
const QUEUE_TIMEOUT_MSEC := 360000

signal progress_changed(message: String)
signal assignment_ready(host: String, port: int, ticket: String)
signal queue_failed(title: String, message: String)

var _http: HTTPRequest
var _poll_timer: Timer
var _base_url := ""
var _queue_token := ""
var _operation := ""
var _active := false
var _deadline_msec := 0
var _client_nonce := ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT_SECONDS
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)
	_poll_timer = Timer.new()
	_poll_timer.one_shot = true
	_poll_timer.timeout.connect(_poll_assignment)
	add_child(_poll_timer)
	_base_url = _configured_url()


func is_configured() -> bool:
	return _is_allowed_base_url(_base_url)


func coordinator_url() -> String:
	return _base_url


func start_queue(base_url_override := "") -> bool:
	if _active:
		return false
	var requested_url := base_url_override.strip_edges().trim_suffix("/")
	if requested_url != "":
		_base_url = requested_url
	if not _is_allowed_base_url(_base_url):
		queue_failed.emit("MATCHMAKING UNAVAILABLE",
			"The development coordinator has not been configured for this build.")
		return false
	_active = true
	_queue_token = ""
	_client_nonce = _random_nonce()
	_deadline_msec = Time.get_ticks_msec() + QUEUE_TIMEOUT_MSEC
	progress_changed.emit("JOINING THE DEVELOPMENT QUEUE…")
	var compatibility := BuildInfo.compatibility_payload()
	return _post("/v1/queue", {
		"schema": 1,
		"client_nonce": _client_nonce,
		"game_version": str(compatibility["game_version"]),
		"protocol": int(compatibility["protocol"]),
		"build_id": str(compatibility["build_id"]),
	}, "create")


func cancel_queue() -> void:
	_poll_timer.stop()
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
	var token := _queue_token
	_active = false
	_queue_token = ""
	_operation = ""
	if token != "" and _is_allowed_base_url(_base_url):
		_post("/v1/queue/cancel", {"schema": 1, "queue_token": token}, "cancel")


func _poll_assignment() -> void:
	if not _active:
		return
	if Time.get_ticks_msec() >= _deadline_msec:
		_fail("MATCHMAKING TIMED OUT",
			"No server became ready. Try again, or use Join by Code with a direct endpoint.")
		return
	_post("/v1/queue/status", {"schema": 1, "queue_token": _queue_token}, "status")


func _post(path: String, payload: Dictionary, operation: String) -> bool:
	_operation = operation
	var headers := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	var error := _http.request(_base_url + path, headers, HTTPClient.METHOD_POST,
		JSON.stringify(payload))
	if error != OK:
		if operation != "cancel":
			_fail("COORDINATOR UNAVAILABLE", "The matchmaking request could not be started.")
		return false
	return true


func _on_request_completed(result: int, response_code: int,
		_response_headers: PackedStringArray, body: PackedByteArray) -> void:
	var operation := _operation
	_operation = ""
	if operation == "cancel":
		return
	if not _active:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("COORDINATOR UNAVAILABLE", "The matchmaking coordinator did not respond.")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed is not Dictionary:
		_fail("INVALID COORDINATOR RESPONSE", "The coordinator returned unreadable data.")
		return
	var response: Dictionary = parsed
	if response_code < 200 or response_code >= 300:
		_fail(str(response.get("title", "MATCHMAKING FAILED")),
			str(response.get("message", "The development queue rejected this request.")))
		return
	match operation:
		"create": _handle_created(response)
		"status": _handle_status(response)


func _handle_created(response: Dictionary) -> void:
	_queue_token = str(response.get("queue_token", "")).strip_edges()
	if _queue_token.length() < 24:
		_fail("INVALID COORDINATOR RESPONSE", "The queue capability was missing.")
		return
	progress_changed.emit("SEARCHING FOR ANOTHER PLAYER…")
	_schedule_poll(int(response.get("retry_after_ms", 2500)))


func _handle_status(response: Dictionary) -> void:
	var state := str(response.get("state", "failed")).to_lower()
	match state:
		"queued", "searching":
			progress_changed.emit("SEARCHING FOR ANOTHER PLAYER…")
			_schedule_poll(int(response.get("retry_after_ms", 2500)))
		"deploying", "match_found":
			progress_changed.emit("MATCH FOUND — STARTING YOUR SERVER…")
			_schedule_poll(int(response.get("retry_after_ms", 2500)))
		"ready":
			var endpoint = response.get("endpoint", {})
			var host := str(endpoint.get("host", "")).strip_edges() if endpoint is Dictionary else ""
			var port := int(endpoint.get("port", 0)) if endpoint is Dictionary else 0
			var ticket := str(response.get("ticket", "")).strip_edges()
			if not _valid_host(host) or port < 1 or port > 65535 or ticket.length() < 4:
				_fail("INVALID SERVER ASSIGNMENT", "The assigned UDP endpoint or ticket was invalid.")
				return
			_active = false
			_poll_timer.stop()
			_queue_token = ""
			assignment_ready.emit(host, port, ticket)
		_:
			_fail("MATCHMAKING FAILED",
				str(response.get("message", "The queue ended before a server was assigned.")))


func _schedule_poll(delay_msec: int) -> void:
	_poll_timer.start(clampf(float(delay_msec) / 1000.0, 1.0, 10.0))


func _fail(title: String, message: String) -> void:
	_poll_timer.stop()
	_active = false
	queue_failed.emit(title.to_upper(), message)


func _configured_url() -> String:
	var environment_url := OS.get_environment("ONEGUN_COORDINATOR_URL").strip_edges()
	if environment_url != "":
		return environment_url.trim_suffix("/")
	if not FileAccess.file_exists(CONFIG_PATH):
		return ""
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if parsed is not Dictionary or int(parsed.get("schema", 0)) != 1 \
			or not bool(parsed.get("enabled", false)):
		return ""
	return str(parsed.get("coordinator_url", "")).strip_edges().trim_suffix("/")


func _is_allowed_base_url(value: String) -> bool:
	if value.begins_with("https://"):
		return value.length() > 12 and not value.contains(" ")
	return value.begins_with("http://127.0.0.1:") or value.begins_with("http://localhost:")


func _valid_host(value: String) -> bool:
	if value.is_valid_ip_address():
		return true
	if value.length() > 253 or not value.contains(".") or value.begins_with(".") \
			or value.ends_with("."):
		return false
	for character in value:
		if not character in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-":
			return false
	return true


func _random_nonce() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	return bytes.hex_encode()
