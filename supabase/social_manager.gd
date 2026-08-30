extends Node

# Authenticated social boundary. Supabase owns stable friendships and limits
# presence/endpoints to accepted friends; NetworkManager remains the only ENet
# and Tailscale transport owner.

const SNAPSHOT_INTERVAL_SECONDS := 15.0
const FOREGROUND_SNAPSHOT_INTERVAL_SECONDS := 4.0
const PRESENCE_INTERVAL_SECONDS := 30.0

signal social_updated(snapshot: Dictionary)
signal invite_received(invite: Dictionary)
signal operation_succeeded(operation: String, message: String)
signal operation_failed(operation: String, message: String)

var snapshot: Dictionary = _empty_snapshot()
var _backend: Node
var _snapshot_elapsed := SNAPSHOT_INTERVAL_SECONDS
var _presence_elapsed := PRESENCE_INTERVAL_SECONDS
var _refreshing := false
var _presence_updating := false
var _known_invite_ids: Dictionary = {}
var _has_loaded_snapshot := false
var _foreground_ui_active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("dedicated_server"):
		return
	_backend = get_node_or_null("/root/SupabaseManager")
	if _backend == null:
		return
	_backend.login_state_changed.connect(_on_login_state_changed)
	for connection in [
		[NetworkManager.lobby_changed, _mark_presence_dirty],
		[NetworkManager.connection_succeeded, _mark_presence_dirty],
		[NetworkManager.server_disconnected, _mark_presence_dirty],
		[NetworkManager.playpen_members_changed, _mark_presence_dirty],
		[NetworkManager.prelaunch_countdown_changed, _on_prelaunch_changed],
	]:
		var signal_value: Signal = connection[0]
		var callback: Callable = connection[1]
		if not signal_value.is_connected(callback):
			signal_value.connect(callback)
	if _backend.is_authenticated():
		_refresh_now.call_deferred()


func _process(delta: float) -> void:
	if not is_ready():
		return
	_snapshot_elapsed += delta
	_presence_elapsed += delta
	if _presence_elapsed >= PRESENCE_INTERVAL_SECONDS:
		_presence_elapsed = 0.0
		publish_presence()
	var snapshot_interval := FOREGROUND_SNAPSHOT_INTERVAL_SECONDS \
		if _foreground_ui_active else SNAPSHOT_INTERVAL_SECONDS
	if _snapshot_elapsed >= snapshot_interval:
		_snapshot_elapsed = 0.0
		refresh_snapshot()


func is_ready() -> bool:
	if _backend == null or not _backend.is_authenticated():
		return false
	if _backend.has_method("has_valid_access_token_shape") \
			and not bool(_backend.call("has_valid_access_token_shape")):
		return false
	return not _backend.has_method("is_configured") or _backend.is_configured()


func friends() -> Array:
	return snapshot.get("friends", [])


func incoming_requests() -> Array:
	return snapshot.get("incoming_requests", [])


func outgoing_requests() -> Array:
	return snapshot.get("outgoing_requests", [])


func invites() -> Array:
	return snapshot.get("invites", [])


func online_friend_count() -> int:
	var count := 0
	for value in friends():
		if value is Dictionary and bool(value.get("online", false)):
			count += 1
	return count


func can_invite_from_current_lobby() -> bool:
	return is_ready() and not NetworkManager.social_lobby_endpoint().is_empty()


func set_foreground_ui_active(active: bool) -> void:
	_foreground_ui_active = active
	if active:
		_snapshot_elapsed = FOREGROUND_SNAPSHOT_INTERVAL_SECONDS


func refresh_snapshot() -> bool:
	if _refreshing or not is_ready():
		return false
	_refreshing = true
	var response: Dictionary = await _rpc("get_social_snapshot")
	_refreshing = false
	if not bool(response.get("ok", false)):
		_fail("refresh", _message(response, "Could not refresh friends."))
		return false
	var previous_invites := _known_invite_ids.duplicate()
	snapshot = normalized_snapshot(_response_object(response))
	_known_invite_ids.clear()
	for value in invites():
		if not value is Dictionary:
			continue
		var invite_id := str(value.get("id", ""))
		if invite_id == "":
			continue
		_known_invite_ids[invite_id] = true
		if _has_loaded_snapshot and not previous_invites.has(invite_id):
			invite_received.emit(value.duplicate(true))
	_has_loaded_snapshot = true
	social_updated.emit(snapshot.duplicate(true))
	return true


func publish_presence() -> bool:
	if _presence_updating or not is_ready():
		return false
	_presence_updating = true
	var endpoint := NetworkManager.social_lobby_endpoint()
	var activity := _current_activity()
	var response: Dictionary = await _rpc("set_social_presence", {
		"p_activity": activity,
		"p_lobby_name": str(endpoint.get("name", "")) if not endpoint.is_empty() else null,
		"p_lobby_address": str(endpoint.get("address", "")) if not endpoint.is_empty() else null,
		"p_lobby_port": int(endpoint.get("port", 0)) if not endpoint.is_empty() else null,
		"p_joinable": not endpoint.is_empty(),
	})
	_presence_updating = false
	if not bool(response.get("ok", false)):
		_fail("presence", _message(response, "Could not update online presence."), false)
		return false
	return true


func clear_presence() -> bool:
	if not is_ready():
		return false
	var response: Dictionary = await _rpc("clear_social_presence")
	return bool(response.get("ok", false))


func send_friend_request(account_name: String) -> bool:
	var cleaned := account_name.strip_edges()
	if cleaned.length() < 3:
		_fail("friend_request", "Enter the player's exact Account Name.")
		return false
	var response: Dictionary = await _rpc("send_friend_request",
		{"p_account_name": cleaned})
	if not bool(response.get("ok", false)):
		_fail("friend_request", _message(response, "Could not send the friend request."))
		return false
	var receipt := _response_object(response)
	_success("friend_request", str(receipt.get("message", "Friend request sent.")))
	await refresh_snapshot()
	return true


func respond_friend_request(requester_id: String, accept: bool) -> bool:
	var response: Dictionary = await _rpc("respond_friend_request", {
		"p_requester_id": requester_id,
		"p_accept": accept,
	})
	if not bool(response.get("ok", false)):
		_fail("friend_response", _message(response, "Could not answer the friend request."))
		return false
	_success("friend_response", "Friend request accepted." if accept else "Friend request denied.")
	await refresh_snapshot()
	return true


func remove_friend(friend_id: String) -> bool:
	var response: Dictionary = await _rpc("remove_friend", {"p_friend_id": friend_id})
	if not bool(response.get("ok", false)):
		_fail("remove_friend", _message(response, "Could not remove that friend."))
		return false
	_success("remove_friend", "Friend removed.")
	await refresh_snapshot()
	return true


func send_lobby_invite(friend_id: String) -> bool:
	if not can_invite_from_current_lobby():
		_fail("invite", "Enter a joinable online lobby before inviting friends.")
		return false
	# Ensure the backend has the current lobby endpoint before it creates the
	# invitation from trusted presence data.
	if not await publish_presence():
		return false
	var response: Dictionary = await _rpc("send_lobby_invite",
		{"p_receiver_id": friend_id})
	if not bool(response.get("ok", false)):
		_fail("invite", _message(response, "Could not send the lobby invitation."))
		return false
	_success("invite", "Lobby invitation sent.")
	return true


func respond_lobby_invite(invite_id: String, accept: bool) -> Dictionary:
	var response: Dictionary = await _rpc("respond_lobby_invite", {
		"p_invite_id": invite_id,
		"p_accept": accept,
	})
	if not bool(response.get("ok", false)):
		_fail("invite_response", _message(response, "Could not answer the lobby invitation."))
		return {}
	var receipt := _response_object(response)
	_success("invite_response", "Joining lobby…" if accept else "Lobby invitation declined.")
	await refresh_snapshot()
	return receipt


func joinable_endpoint(record: Dictionary) -> Dictionary:
	if not bool(record.get("joinable", true)):
		return {}
	var address := str(record.get("lobby_address", "")).strip_edges()
	var port := int(record.get("lobby_port", 0))
	if not is_valid_join_endpoint(address, port):
		return {}
	return {
		"name": str(record.get("lobby_name", "Lobby")),
		"address": address,
		"port": port,
	}


static func is_valid_join_endpoint(address: String, port: int) -> bool:
	if port < 1 or port > 65535 or not address.is_valid_ip_address():
		return false
	if address.begins_with("127."):
		return true
	var parts := address.split(".")
	return parts.size() == 4 and parts[0] == "100" \
		and int(parts[1]) >= 64 and int(parts[1]) <= 127


static func normalized_snapshot(value: Dictionary) -> Dictionary:
	var result := _empty_snapshot()
	for key in ["friends", "incoming_requests", "outgoing_requests", "invites"]:
		var source = value.get(key, [])
		if not source is Array:
			continue
		for item in source:
			if item is Dictionary:
				result[key].append(item.duplicate(true))
	result["server_time"] = str(value.get("server_time", ""))
	return result


static func _empty_snapshot() -> Dictionary:
	return {
		"friends": [],
		"incoming_requests": [],
		"outgoing_requests": [],
		"invites": [],
		"server_time": "",
	}


func _current_activity() -> String:
	if not NetworkManager.is_online():
		return "home"
	if NetworkManager.local_match_role in ["playpen", "playpen_hosting"]:
		return "playpen"
	if NetworkManager.lobby_in_progress \
			or NetworkManager.local_match_role in ["participant", "spectator"]:
		return "match"
	return "lobby"


func _mark_presence_dirty() -> void:
	_presence_elapsed = PRESENCE_INTERVAL_SECONDS
	_snapshot_elapsed = SNAPSHOT_INTERVAL_SECONDS


func _on_prelaunch_changed(_active: bool, _seconds: int) -> void:
	_mark_presence_dirty()


func _refresh_now() -> void:
	_presence_elapsed = 0.0
	_snapshot_elapsed = 0.0
	publish_presence()
	refresh_snapshot()


func _on_login_state_changed(state: String) -> void:
	if state == "authenticated":
		_refresh_now.call_deferred()
	elif state == "logged_out":
		snapshot = _empty_snapshot()
		_known_invite_ids.clear()
		_has_loaded_snapshot = false
		social_updated.emit(snapshot.duplicate(true))


func _rpc(function_name: String, payload: Dictionary = {}) -> Dictionary:
	if not is_ready():
		return {"ok": false, "status": 401, "message": "Sign in to use Friends."}
	return await _backend._authenticated_request(
		"/rest/v1/rpc/%s" % function_name, HTTPClient.METHOD_POST, payload)


func _response_object(response: Dictionary) -> Dictionary:
	var data = response.get("data", {})
	if data is Dictionary:
		return data.duplicate(true)
	if data is Array and not data.is_empty() and data[0] is Dictionary:
		return data[0].duplicate(true)
	return {}


func _message(response: Dictionary, fallback: String) -> String:
	if _backend != null and _backend.has_method("_response_message"):
		return str(_backend._response_message(response, fallback))
	return str(response.get("message", fallback))


func _success(operation: String, message: String) -> void:
	operation_succeeded.emit(operation, message)


func _fail(operation: String, message: String, report := true) -> void:
	operation_failed.emit(operation, message)
	if report:
		push_warning("SocialManager %s: %s" % [operation, message])
