extends Node

const MatchLimitsData = preload("res://match_limits.gd")
const BuildInfo = preload("res://build_info.gd")

# ============================================================
# NetworkManager — Autoload singleton (online multiplayer)
#
# High-level Godot MultiplayerAPI over ENet (UDP). Designed for a
# Tailscale network: peers normally discover a host-chosen lobby name across
# their tailnet; direct 100.x.x.x entry remains available as a fallback.
#
# Transport-neutral online session coordinator. It owns ENet/Tailscale host
# and join flow today, plus the roster, actor identity, compatibility gate,
# lobby readiness, late-spectator roles, config/map sync, and scene readiness.
# Match authority and gameplay RPC routing remain in round_manager.gd.
# ============================================================

const DEFAULT_PORT := 24545
const DISCOVERY_PORT := 24546
const MAX_PEERS := MatchLimitsData.MAX_TOTAL_ACTORS
const JOIN_TIMEOUT_SECONDS := 12.0
const COMPATIBILITY_TIMEOUT_SECONDS := 5.0
const MATCH_LOAD_TIMEOUT_SECONDS := 30.0
const TEST_MATCH_LOAD_TIMEOUT_SECONDS := 2.0
const DISCOVERY_TIMEOUT_SECONDS := 3.0
const PLAYPEN_SCENE := "res://maps/playpen/playpen.tscn"
const DISCOVERY_REQUEST_PREFIX := "ONEGUN_DISCOVER:"
const DISCOVERY_RESPONSE_PREFIX := "ONEGUN_LOBBY:"

signal lobby_changed                     # roster added/removed/renamed
signal lobby_readiness_changed           # host-authoritative pre-match ready state
signal lobby_notice(message: String)     # readiness reset / lobby status explanation
signal connection_succeeded              # client connected to host
signal connection_failed                 # client couldn't connect
signal server_disconnected               # host went away
signal match_config_received             # client got host's settings/map
signal match_readiness_changed            # a peer finished building the match scene
signal lobby_discovery_failed(message: String)
signal lobby_list_updated(lobbies: Array)
signal lobby_list_failed(message: String)
signal compatibility_rejected(message: String)
signal prelaunch_countdown_changed(active: bool, seconds: int)
signal match_load_status_changed
signal spectator_state_changed
signal playpen_members_changed
signal one_of_us_preference_changed

# peer_id -> { "name": String }
var peers: Dictionary = {}
var _provisional_peers: Dictionary = {}
var _one_of_us_volunteers: Dictionary = {}
var _next_human_actor_id := 2
# peer_id -> bool. The host is always ready because its primary lobby action
# is Start/Force Start; guests explicitly toggle their own state.
var lobby_ready: Dictionary = {}
var pending_map_path: String = ""
var pending_match_id := 0
var _online := false
var _match_ready_peers: Dictionary = {}
var _playpen_ready_peers: Dictionary = {}
var match_participant_peers: Array = []
var match_load_status: Dictionary = {}
var _match_load_watch_generation := 0
var local_match_role := "lobby"
var _prelaunch_active := false
var _prelaunch_seconds := 0
var _prelaunch_generation := 0
var _joining := false
var _connection_attempt := 0
var lobby_name := ""
var lobby_privacy := "public"
var lobby_share_code := ""
var lobby_max_players := MAX_PEERS
var lobby_in_progress := false
var _discovery_responder: PacketPeerUDP = null
var _discovery_attempt := 0
var _host_port := DEFAULT_PORT
var local_one_of_us_volunteer := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(_delta: float) -> void:
	if _discovery_responder == null or not is_host():
		return
	while _discovery_responder.get_available_packet_count() > 0:
		var packet_text := _discovery_responder.get_packet().get_string_from_utf8()
		var sender_ip := _discovery_responder.get_packet_ip()
		var sender_port := _discovery_responder.get_packet_port()
		if not packet_text.begins_with(DISCOVERY_REQUEST_PREFIX):
			continue
		var request_body := packet_text.trim_prefix(DISCOVERY_REQUEST_PREFIX)
		var request = JSON.parse_string(request_body) if request_body.begins_with("{") else null
		var nonce := request_body
		var request_kind := "name"
		var requested_code := ""
		if request is Dictionary:
			nonce = str(request.get("nonce", ""))
			request_kind = str(request.get("kind", "list"))
			requested_code = _clean_share_code(str(request.get("code", "")))
		if nonce == "":
			continue
		var should_respond := false
		match request_kind:
			"list":
				should_respond = lobby_privacy == "public"
			"code":
				should_respond = requested_code != "" and requested_code == lobby_share_code
			_:
				should_respond = lobby_privacy == "public"
		if not should_respond:
			continue
		var payload := JSON.stringify(_discovery_payload(nonce))
		_discovery_responder.set_dest_address(sender_ip, sender_port)
		_discovery_responder.put_packet((DISCOVERY_RESPONSE_PREFIX + payload).to_utf8_buffer())

# ------------------------------------------------------------
# Hosting / joining
# ------------------------------------------------------------

func host_game(port: int = DEFAULT_PORT, requested_lobby_name: String = "",
		options: Dictionary = {}) -> bool:
	_reset_session(false)
	lobby_privacy = str(options.get("privacy", "public")).to_lower()
	if lobby_privacy not in ["public", "private"]:
		lobby_privacy = "public"
	lobby_max_players = clampi(int(options.get("max_players", MAX_PEERS)),
		MatchLimitsData.MIN_ONLINE_HUMANS, MAX_PEERS)
	lobby_share_code = _clean_share_code(str(options.get("share_code", "")))
	if lobby_share_code == "":
		lobby_share_code = _generate_share_code()
	lobby_in_progress = false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, lobby_max_players - 1)
	if err != OK:
		_net_log("host failed on UDP %d (error %d)" % [port, err])
		push_warning("NetworkManager: create_server failed (%d)" % err)
		return false
	multiplayer.multiplayer_peer = peer
	_online = true
	_joining = false
	_host_port = port
	peers.clear()
	peers[1] = {
		"name": local_name(),
		"skin_id": local_skin_id(),
		"actor_id": 1,
		"team_id": 0,
		"role": "lobby",
	}
	_one_of_us_volunteers[1] = false
	_next_human_actor_id = 2
	lobby_ready.clear()
	lobby_ready[1] = true
	lobby_name = _clean_lobby_name(requested_lobby_name)
	if lobby_name == "":
		lobby_name = "%s's Lobby" % local_name()
	_start_discovery_responder()
	_net_log("hosting '%s' on UDP %d as '%s'" % [lobby_name, port, local_name()])
	lobby_changed.emit()
	return true

func join_lobby_by_name(requested_name: String) -> bool:
	var cleaned := _clean_lobby_name(requested_name)
	if cleaned == "":
		return false
	_discovery_attempt += 1
	_discover_lobby_and_join(cleaned, _discovery_attempt)
	return true


func join_lobby_by_code(requested_code: String) -> bool:
	var cleaned := _clean_share_code(requested_code)
	if cleaned == "":
		return false
	_discovery_attempt += 1
	_discover_code_and_join(cleaned, _discovery_attempt)
	return true


func join_discovered_lobby(lobby: Dictionary) -> bool:
	var incompatibility := BuildInfo.compatibility_error(lobby)
	if incompatibility != "":
		compatibility_rejected.emit(incompatibility)
		return false
	var address := str(lobby.get("address", ""))
	var port := int(lobby.get("port", DEFAULT_PORT))
	if address == "":
		return false
	var selected_name := _clean_lobby_name(str(lobby.get("name", "")))
	if not join_game(address, port):
		return false
	lobby_name = selected_name
	return true


func discover_lobbies() -> void:
	_discovery_attempt += 1
	_discover_lobby_list(_discovery_attempt)

func _discover_lobby_and_join(requested_name: String, attempt: int) -> void:
	# Tailscale's CLI can occasionally take a few seconds to answer on Windows;
	# keep it off the main thread so the menu and searching status stay live.
	var lookup_thread := Thread.new()
	var targets: Array = []
	if lookup_thread.start(_tailscale_peer_ips) == OK:
		while lookup_thread.is_alive() and attempt == _discovery_attempt:
			await get_tree().process_frame
		targets = lookup_thread.wait_to_finish()
	else:
		targets = _tailscale_peer_ips()
	if not targets.has("127.0.0.1"):
		targets.append("127.0.0.1")
	if targets.is_empty():
		lobby_discovery_failed.emit("Tailscale peer list is unavailable. Use the host's 100.x address as a fallback.")
		return
	var socket := PacketPeerUDP.new()
	if socket.bind(0, "*") != OK:
		lobby_discovery_failed.emit("Could not open the lobby discovery socket.")
		return
	var nonce := "%d-%d" % [Time.get_ticks_msec(), randi()]
	var request := (DISCOVERY_REQUEST_PREFIX + nonce).to_utf8_buffer()
	var deadline := Time.get_ticks_msec() + int(DISCOVERY_TIMEOUT_SECONDS * 1000.0)
	var next_probe_time := 0
	while Time.get_ticks_msec() < deadline and attempt == _discovery_attempt:
		if Time.get_ticks_msec() >= next_probe_time:
			for target in targets:
				socket.set_dest_address(str(target), DISCOVERY_PORT)
				socket.put_packet(request)
			next_probe_time = Time.get_ticks_msec() + 500
		while socket.get_available_packet_count() > 0:
			var response_text := socket.get_packet().get_string_from_utf8()
			var response_ip := socket.get_packet_ip()
			if not response_text.begins_with(DISCOVERY_RESPONSE_PREFIX):
				continue
			var payload = JSON.parse_string(response_text.trim_prefix(DISCOVERY_RESPONSE_PREFIX))
			if not (payload is Dictionary) or str(payload.get("nonce", "")) != nonce:
				continue
			if str(payload.get("name", "")).nocasecmp_to(requested_name) == 0:
				var port := int(payload.get("port", DEFAULT_PORT))
				socket.close()
				if join_game(response_ip, port):
					lobby_name = requested_name
				return
		await get_tree().create_timer(0.05).timeout
	socket.close()
	if attempt == _discovery_attempt:
		lobby_discovery_failed.emit("No Tailscale lobby named '%s' was found." % requested_name)


func _discover_code_and_join(requested_code: String, attempt: int) -> void:
	var targets := await _discovery_targets(attempt)
	if attempt != _discovery_attempt:
		return
	var socket := PacketPeerUDP.new()
	if socket.bind(0, "*") != OK:
		lobby_discovery_failed.emit("Could not open the lobby discovery socket.")
		return
	var nonce := "%d-%d" % [Time.get_ticks_msec(), randi()]
	var request_body := JSON.stringify({"nonce": nonce, "kind": "code", "code": requested_code})
	var request := (DISCOVERY_REQUEST_PREFIX + request_body).to_utf8_buffer()
	var result := await _probe_for_first_lobby(socket, targets, request, nonce, attempt)
	socket.close()
	if attempt != _discovery_attempt:
		return
	if not result.is_empty():
		if join_discovered_lobby(result):
			return
		lobby_discovery_failed.emit("The lobby answered, but the connection could not start.")
		return
	lobby_discovery_failed.emit("No Tailscale lobby accepted code '%s'." % requested_code)


func _discover_lobby_list(attempt: int) -> void:
	var targets := await _discovery_targets(attempt)
	if attempt != _discovery_attempt:
		return
	var socket := PacketPeerUDP.new()
	if socket.bind(0, "*") != OK:
		lobby_list_failed.emit("Could not open the lobby discovery socket.")
		return
	var nonce := "%d-%d" % [Time.get_ticks_msec(), randi()]
	var request_body := JSON.stringify({"nonce": nonce, "kind": "list"})
	var request := (DISCOVERY_REQUEST_PREFIX + request_body).to_utf8_buffer()
	var deadline := Time.get_ticks_msec() + int(DISCOVERY_TIMEOUT_SECONDS * 1000.0)
	var next_probe_time := 0
	var found: Dictionary = {}
	while Time.get_ticks_msec() < deadline and attempt == _discovery_attempt:
		if Time.get_ticks_msec() >= next_probe_time:
			for target in targets:
				socket.set_dest_address(str(target), DISCOVERY_PORT)
				socket.put_packet(request)
			next_probe_time = Time.get_ticks_msec() + 500
		while socket.get_available_packet_count() > 0:
			var response_text := socket.get_packet().get_string_from_utf8()
			var response_ip := socket.get_packet_ip()
			var lobby := _parse_discovery_response(response_text, response_ip, nonce)
			if lobby.is_empty():
				continue
			found["%s:%d" % [response_ip, int(lobby.get("port", DEFAULT_PORT))]] = lobby
		await get_tree().create_timer(0.05).timeout
	socket.close()
	if attempt != _discovery_attempt:
		return
	var lobbies: Array = found.values()
	lobbies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0)
	lobby_list_updated.emit(lobbies)


func _discovery_targets(attempt: int) -> Array:
	var lookup_thread := Thread.new()
	var targets: Array = []
	if lookup_thread.start(_tailscale_peer_ips) == OK:
		while lookup_thread.is_alive() and attempt == _discovery_attempt:
			await get_tree().process_frame
		targets = lookup_thread.wait_to_finish()
	else:
		targets = _tailscale_peer_ips()
	if not targets.has("127.0.0.1"):
		targets.append("127.0.0.1")
	return targets


func _probe_for_first_lobby(socket: PacketPeerUDP, targets: Array, request: PackedByteArray,
		nonce: String, attempt: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(DISCOVERY_TIMEOUT_SECONDS * 1000.0)
	var next_probe_time := 0
	while Time.get_ticks_msec() < deadline and attempt == _discovery_attempt:
		if Time.get_ticks_msec() >= next_probe_time:
			for target in targets:
				socket.set_dest_address(str(target), DISCOVERY_PORT)
				socket.put_packet(request)
			next_probe_time = Time.get_ticks_msec() + 500
		while socket.get_available_packet_count() > 0:
			var response_text := socket.get_packet().get_string_from_utf8()
			var response_ip := socket.get_packet_ip()
			var lobby := _parse_discovery_response(response_text, response_ip, nonce)
			if not lobby.is_empty():
				return lobby
		await get_tree().create_timer(0.05).timeout
	return {}


func _parse_discovery_response(response_text: String, response_ip: String,
		nonce: String) -> Dictionary:
	if not response_text.begins_with(DISCOVERY_RESPONSE_PREFIX):
		return {}
	var payload = JSON.parse_string(response_text.trim_prefix(DISCOVERY_RESPONSE_PREFIX))
	if not (payload is Dictionary) or str(payload.get("nonce", "")) != nonce:
		return {}
	var current_players := maxi(int(payload.get("players", 1)), 1)
	var maximum_players := clampi(int(payload.get("max_players", MAX_PEERS)),
		MatchLimitsData.MIN_ONLINE_HUMANS, MAX_PEERS)
	var in_progress := bool(payload.get("in_progress", false))
	var build_payload := {
		"game_version": str(payload.get("game_version", payload.get("version", "unknown"))),
		"protocol": int(payload.get("protocol", -1)),
	}
	var incompatibility := BuildInfo.compatibility_error(build_payload)
	var joinability := "incompatible" if incompatibility != "" else ("full" if current_players >= maximum_players else ("in_progress" if in_progress else "joinable"))
	return {
		"address": response_ip,
		"port": int(payload.get("port", DEFAULT_PORT)),
		"name": _clean_lobby_name(str(payload.get("name", "Lobby"))),
		"privacy": str(payload.get("privacy", "public")),
		"players": current_players,
		"max_players": maximum_players,
		"mode": str(payload.get("mode", "One Gun")),
		"in_progress": in_progress,
		"joinability": joinability,
		"game_version": build_payload["game_version"],
		"protocol": build_payload["protocol"],
		"compatibility_error": incompatibility,
	}


func _discovery_payload(nonce: String) -> Dictionary:
	return {
		"nonce": nonce,
		"name": lobby_name,
		"port": _host_port,
		"privacy": lobby_privacy,
		"players": peers.size(),
		"max_players": lobby_max_players,
		"mode": "One Gun",
		"in_progress": lobby_in_progress,
		"version": BuildInfo.GAME_VERSION,
		"game_version": BuildInfo.GAME_VERSION,
		"protocol": BuildInfo.NETWORK_PROTOCOL,
	}

func _start_discovery_responder() -> void:
	if _discovery_responder != null:
		_discovery_responder.close()
	_discovery_responder = PacketPeerUDP.new()
	var err := _discovery_responder.bind(DISCOVERY_PORT, "*")
	if err != OK:
		push_warning("NetworkManager: lobby discovery port %d unavailable (error %d)" % [DISCOVERY_PORT, err])
		_discovery_responder = null

func _clean_lobby_name(value: String) -> String:
	return value.strip_edges().replace("|", "").substr(0, 32)


func _clean_share_code(value: String) -> String:
	var cleaned := ""
	for character in value.strip_edges().to_upper():
		if character in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789":
			cleaned += character
	return cleaned.substr(0, 12)


func _generate_share_code() -> String:
	const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for _index in 6:
		code += ALPHABET[randi_range(0, ALPHABET.length() - 1)]
	return code

func _tailscale_peer_ips() -> Array:
	var executable := "tailscale"
	var installed_path := "C:/Program Files/Tailscale/tailscale.exe"
	if FileAccess.file_exists(installed_path):
		executable = installed_path
	var output: Array = []
	var exit_code := OS.execute(executable, ["status", "--json"], output, true, false)
	if exit_code != 0 or output.is_empty():
		return []
	var status = JSON.parse_string("\n".join(output))
	if status == null:
		return []
	var addresses: Array = []
	_collect_tailscale_addresses(status, addresses)
	return addresses

func _collect_tailscale_addresses(value, addresses: Array) -> void:
	if value is Dictionary:
		for child in value.values():
			_collect_tailscale_addresses(child, addresses)
	elif value is Array:
		for child in value:
			_collect_tailscale_addresses(child, addresses)
	elif value is String and _is_tailscale_ipv4(value) and not addresses.has(value):
		addresses.append(value)

func _is_tailscale_ipv4(address: String) -> bool:
	var parts := address.split(".")
	if parts.size() != 4 or parts[0] != "100":
		return false
	var second := int(parts[1])
	return second >= 64 and second <= 127

func join_game(ip: String, port: int = DEFAULT_PORT) -> bool:
	_reset_session(false)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		_net_log("join setup failed for %s:%d (error %d)" % [ip, port, err])
		push_warning("NetworkManager: create_client failed (%d)" % err)
		return false
	multiplayer.multiplayer_peer = peer
	_online = true
	_joining = true
	_connection_attempt += 1
	var attempt := _connection_attempt
	_net_log("joining %s:%d (attempt %d)" % [ip, port, attempt])
	_join_timeout(attempt)
	return true

func disconnect_net() -> void:
	_net_log("disconnect requested")
	_reset_session(true)

func host_return_everyone_to_lobby() -> void:
	if not is_host():
		return
	for peer_id in peers:
		peers[peer_id]["role"] = "lobby"
	match_participant_peers.clear()
	match_load_status.clear()
	_match_load_watch_generation += 1
	reset_lobby_readiness("Returned to lobby — ready up again")
	_net_return_everyone_to_lobby.rpc()

@rpc("authority", "reliable", "call_local")
func _net_return_everyone_to_lobby() -> void:
	lobby_in_progress = false
	local_match_role = "lobby"
	set_accepting_new_peers(true)
	PauseManager.reset_pause_state()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManager.stop_music(0.5)
	get_tree().change_scene_to_file("res://game_setup.tscn")

func leave_online_to_main_menu() -> void:
	if not is_online():
		PauseManager.reset_pause_state()
		get_tree().change_scene_to_file("res://main_menu.tscn")
		return
	if is_host():
		# Tell clients first, then give the reliable packet a brief opportunity to
		# flush before closing the host peer. Host-process termination still falls
		# back to the existing server_disconnected path on every client.
		_net_client_return_to_main_menu.rpc()
		_finish_host_return_to_main_menu()
	else:
		_return_local_to_main_menu()

func _finish_host_return_to_main_menu() -> void:
	await get_tree().create_timer(0.15).timeout
	_return_local_to_main_menu()

@rpc("authority", "reliable")
func _net_client_return_to_main_menu() -> void:
	_return_local_to_main_menu()

func _return_local_to_main_menu() -> void:
	PauseManager.reset_pause_state()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManager.stop_music(0.5)
	_reset_session(true)
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _reset_session(emit_change: bool) -> void:
	_connection_attempt += 1
	_discovery_attempt += 1
	_joining = false
	_online = false
	var old_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = null
	if old_peer != null:
		old_peer.close()
	peers.clear()
	_provisional_peers.clear()
	_one_of_us_volunteers.clear()
	local_one_of_us_volunteer = false
	lobby_ready.clear()
	pending_map_path = ""
	pending_match_id = 0
	_match_ready_peers.clear()
	_playpen_ready_peers.clear()
	match_participant_peers.clear()
	match_load_status.clear()
	_match_load_watch_generation += 1
	local_match_role = "lobby"
	_prelaunch_active = false
	_prelaunch_seconds = 0
	_prelaunch_generation += 1
	_next_human_actor_id = 2
	lobby_name = ""
	lobby_privacy = "public"
	lobby_share_code = ""
	lobby_max_players = MAX_PEERS
	lobby_in_progress = false
	_host_port = DEFAULT_PORT
	if _discovery_responder != null:
		_discovery_responder.close()
		_discovery_responder = null
	if emit_change:
		lobby_changed.emit()

func _join_timeout(attempt: int) -> void:
	await get_tree().create_timer(JOIN_TIMEOUT_SECONDS).timeout
	if attempt != _connection_attempt or not _joining:
		return
	_net_log("join attempt %d timed out after %.0fs" % [attempt, JOIN_TIMEOUT_SECONDS])
	_reset_session(true)
	connection_failed.emit()

func _net_log(message: String) -> void:
	if OS.is_debug_build():
		print("[ONLINE %d] %s" % [Time.get_ticks_msec(), message])

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

func is_online() -> bool:
	return _online and multiplayer.multiplayer_peer != null

func is_host() -> bool:
	return is_online() and multiplayer.is_server()


func set_one_of_us_volunteer(active: bool) -> void:
	if lobby_in_progress:
		return
	local_one_of_us_volunteer = active
	if is_host():
		_one_of_us_volunteers[1] = active
	elif is_online():
		_request_one_of_us_volunteer.rpc_id(1, active)
	one_of_us_preference_changed.emit()


func is_one_of_us_volunteer() -> bool:
	return local_one_of_us_volunteer


func one_of_us_volunteer_actor_ids() -> Array[int]:
	var result: Array[int] = []
	if not is_host():
		return result
	for peer_id_value in _one_of_us_volunteers:
		var peer_id := int(peer_id_value)
		if not bool(_one_of_us_volunteers[peer_id_value]) or not peers.has(peer_id):
			continue
		if str(peers[peer_id].get("role", "")) != "participant":
			continue
		result.append(actor_id_for_peer(peer_id))
	return result


@rpc("any_peer", "reliable")
func _request_one_of_us_volunteer(active: bool) -> void:
	if not multiplayer.is_server() or lobby_in_progress:
		return
	var sender := multiplayer.get_remote_sender_id()
	if peers.has(sender):
		_one_of_us_volunteers[sender] = active
func local_id() -> int:
	if not is_online():
		return 1
	return multiplayer.get_unique_id()


func local_actor_id() -> int:
	return actor_id_for_peer(local_id())


func actor_id_for_peer(peer_id: int) -> int:
	return int(peers.get(peer_id, {}).get("actor_id", -1))


func peer_id_for_actor(actor_id: int) -> int:
	for peer_id in peers:
		if int(peers[peer_id].get("actor_id", -1)) == actor_id:
			return int(peer_id)
	return -1

func local_name() -> String:
	var n = PlayerPrefs.get_setting("player_name")
	return str(n) if n != null and str(n) != "" else "Player"


func local_skin_id() -> String:
	if is_online() and peers.has(local_id()):
		return PlayerSkinRegistry.sanitize_skin_id(
			str(peers[local_id()].get("skin_id", PlayerSkinRegistry.DEFAULT_SKIN_ID)))
	return PlayerSkinRegistry.sanitize_skin_id(
		str(PlayerPrefs.get_setting("character_skin_id")))


func peer_skin_id(peer_id: int) -> String:
	return PlayerSkinRegistry.sanitize_skin_id(str(
		peers.get(peer_id, {}).get("skin_id", PlayerSkinRegistry.DEFAULT_SKIN_ID)))


func set_local_skin_id(requested_id: String) -> bool:
	var safe_id := PlayerSkinRegistry.sanitize_skin_id(requested_id)
	PlayerPrefs.set_setting("character_skin_id", safe_id)
	if not is_online():
		return true
	if lobby_in_progress:
		return false
	var id := local_id()
	if is_host():
		peers[id]["skin_id"] = safe_id
		lobby_changed.emit()
		_broadcast_lobby_state()
	else:
		# Keep rapid local scrolling responsive while the host validates and
		# echoes the authoritative roster state.
		if peers.has(id):
			peers[id]["skin_id"] = safe_id
			lobby_changed.emit()
		_request_skin_change.rpc_id(1, safe_id)
	return true

func set_local_name(new_name: String) -> bool:
	var cleaned := new_name.strip_edges().substr(0, 24)
	if cleaned == "":
		return false
	PlayerPrefs.set_setting("player_name", cleaned)
	if not is_online():
		return true
	if lobby_in_progress:
		return false
	var id := local_id()
	if is_host():
		peers[id]["name"] = cleaned
		lobby_changed.emit()
		_broadcast_lobby_state()
	else:
		_request_name_change.rpc_id(1, cleaned)
	return true

func peer_name(peer_id: int) -> String:
	var entry = peers.get(peer_id, {})
	var pname := str(entry.get("name", ""))
	return pname if pname != "" else "Player %d" % peer_id

func peer_ids_sorted() -> Array:
	var ids := peers.keys()
	ids.sort_custom(func(a, b): return actor_id_for_peer(int(a)) < actor_id_for_peer(int(b)))
	return ids


func participant_peer_ids() -> Array:
	return match_participant_peers.duplicate()


func is_match_participant(peer_id: int) -> bool:
	return match_participant_peers.has(peer_id)


func set_actor_team(actor_id: int, team_id: int) -> bool:
	if not is_host() or lobby_in_progress:
		return false
	for peer_id in peers:
		if int(peers[peer_id].get("actor_id", -1)) == actor_id:
			peers[peer_id]["team_id"] = clampi(team_id, 0, maxi(GameConfig.team_count - 1, 0))
			reset_lobby_readiness("Team assignments changed — ready up again")
			return true
	return false


func request_local_team(team_id: int) -> void:
	if not is_online() or lobby_in_progress:
		return
	if is_host():
		set_actor_team(local_actor_id(), team_id)
	else:
		_request_actor_team.rpc_id(1, team_id)


@rpc("any_peer", "reliable")
func _request_actor_team(team_id: int) -> void:
	if not multiplayer.is_server() or lobby_in_progress:
		return
	var sender := multiplayer.get_remote_sender_id()
	if peers.has(sender):
		set_actor_team(int(peers[sender].get("actor_id", -1)), team_id)



func playpen_peer_ids() -> Array:
	var result: Array = []
	for peer_id_value in peers:
		var peer_id := int(peer_id_value)
		if str(peers[peer_id].get("role", "lobby")) == "playpen":
			result.append(peer_id)
	result.sort()
	return result


func is_peer_in_playpen(peer_id: int) -> bool:
	return peers.has(peer_id) \
		and str(peers[peer_id].get("role", "lobby")) == "playpen"


func is_playpen_open() -> bool:
	return peers.has(1) and str(peers[1].get("role", "lobby")) \
		in ["playpen", "playpen_loading", "playpen_hosting"]



func request_enter_playpen(ready_choice: bool) -> void:
	if not is_online() or lobby_in_progress or _prelaunch_active:
		return
	var peer_id := local_id()
	lobby_ready[peer_id] = ready_choice if peer_id != 1 else true
	if is_host():
		peers[peer_id]["role"] = "playpen"
		local_match_role = "playpen"
		_playpen_ready_peers[peer_id] = true
		_broadcast_lobby_state("The Playpen is open")
		playpen_members_changed.emit()
		var current_scene := get_tree().current_scene
		var manager = current_scene.get_node_or_null("RoundManager") \
			if current_scene != null else null
		if manager != null and manager.has_method("restore_host_to_playpen"):
			manager.restore_host_to_playpen()
		else:
			get_tree().change_scene_to_file(PLAYPEN_SCENE)
		return
	_request_enter_playpen.rpc_id(1, ready_choice)


@rpc("any_peer", "reliable")
func _request_enter_playpen(ready_choice: bool) -> void:
	if not multiplayer.is_server() or lobby_in_progress:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not peers.has(sender):
		return
	if not is_playpen_open():
		_lobby_notice_target.rpc_id(sender,
			"The host must open The Playpen before guests can enter.")
		return
	peers[sender]["role"] = "playpen_loading"
	lobby_ready[sender] = ready_choice
	_broadcast_lobby_state()
	_net_enter_playpen.rpc_id(sender)


@rpc("authority", "reliable")
func _net_enter_playpen() -> void:
	local_match_role = "playpen_loading"
	get_tree().change_scene_to_file(PLAYPEN_SCENE)


func report_playpen_scene_ready() -> void:
	if not is_online():
		return
	if is_host():
		_mark_playpen_scene_ready(1)
	else:
		_report_playpen_scene_ready.rpc_id(1)


@rpc("any_peer", "reliable")
func _report_playpen_scene_ready() -> void:
	if multiplayer.is_server():
		_mark_playpen_scene_ready(multiplayer.get_remote_sender_id())


func _mark_playpen_scene_ready(peer_id: int) -> void:
	if not is_host() or not peers.has(peer_id):
		return
	var role := str(peers[peer_id].get("role", "lobby"))
	if role not in ["playpen", "playpen_loading"]:
		return
	peers[peer_id]["role"] = "playpen"
	_playpen_ready_peers[peer_id] = true
	if peer_id == 1:
		local_match_role = "playpen"
	_broadcast_lobby_state()
	playpen_members_changed.emit()


func request_leave_playpen() -> void:
	if not is_online() or local_match_role not in ["playpen", "playpen_loading"]:
		return
	if is_host():
		# Keep the authoritative practice scene alive for guests while the host
		# independently returns to the lobby UI. Their actor is removed from the
		# room, but the same process continues serving Playpen replication.
		peers[1]["role"] = "playpen_hosting"
		local_match_role = "playpen_hosting"
		_playpen_ready_peers.erase(1)
		_broadcast_lobby_state("The host returned to the lobby")
		playpen_members_changed.emit()
		var manager = get_tree().current_scene.get_node_or_null("RoundManager") \
			if get_tree().current_scene != null else null
		if manager != null and manager.has_method("show_host_lobby_overlay"):
			manager.show_host_lobby_overlay()
	else:
		_request_leave_playpen.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_leave_playpen() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not peers.has(sender):
		return
	peers[sender]["role"] = "lobby"
	_playpen_ready_peers.erase(sender)
	_broadcast_lobby_state()
	playpen_members_changed.emit()
	_net_leave_playpen.rpc_id(sender)


func _close_playpen_for_everyone() -> void:
	if not is_host():
		return
	for peer_id_value in peers:
		var peer_id := int(peer_id_value)
		if peer_id == 1:
			continue
		if str(peers[peer_id].get("role", "lobby")) in ["playpen", "playpen_loading"]:
			peers[peer_id]["role"] = "lobby"
			_net_leave_playpen.rpc_id(peer_id)
	_playpen_ready_peers.clear()
	peers[1]["role"] = "lobby"
	local_match_role = "lobby"
	_broadcast_lobby_state("The Playpen was closed by the host")
	playpen_members_changed.emit()
	get_tree().change_scene_to_file("res://game_setup.tscn")


@rpc("authority", "reliable")
func _net_leave_playpen() -> void:
	local_match_role = "lobby"
	# Let any reliable MultiplayerSpawner despawn sent just before this RPC land
	# while the Playpen replication nodes still exist on the departing peer.
	await get_tree().create_timer(0.12).timeout
	if local_match_role == "lobby":
		get_tree().change_scene_to_file("res://game_setup.tscn")


@rpc("authority", "reliable")
func _lobby_notice_target(message: String) -> void:
	lobby_notice.emit(message)

func is_peer_lobby_ready(peer_id: int) -> bool:
	# The host's start controls replace a separate Ready Up action.
	return peer_id == 1 or bool(lobby_ready.get(peer_id, false))


func are_all_lobby_guests_ready() -> bool:
	if not is_online():
		return false
	for peer_id in peers:
		if str(peers[peer_id].get("role", "lobby")) \
				not in ["lobby", "playpen", "playpen_loading", "playpen_hosting"]:
			continue
		if int(peer_id) != 1 and not is_peer_lobby_ready(int(peer_id)):
			return false
	return true


func set_local_lobby_ready(ready: bool) -> void:
	if not is_online() or local_id() == 1 or lobby_in_progress or _prelaunch_active:
		return
	var id := local_id()
	# Optimistic local feedback is reconciled by the host's authoritative
	# broadcast immediately after it validates the sender.
	lobby_ready[id] = ready
	lobby_readiness_changed.emit()
	_set_lobby_ready.rpc_id(1, ready)


@rpc("any_peer", "reliable")
func _set_lobby_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 1 or not peers.has(sender):
		return
	lobby_ready[sender] = ready
	lobby_readiness_changed.emit()
	_broadcast_lobby_state()


func reset_lobby_readiness(reason: String = "Lobby settings changed") -> void:
	if not is_host():
		return
	lobby_ready.clear()
	lobby_ready[1] = true
	for peer_id in peers:
		if int(peer_id) != 1 and str(peers[peer_id].get("role", "lobby")) \
				in ["lobby", "playpen", "playpen_loading", "playpen_hosting"]:
			lobby_ready[peer_id] = false
	lobby_readiness_changed.emit()
	if reason != "":
		lobby_notice.emit(reason)
	_broadcast_lobby_state(reason)


func set_lobby_privacy(privacy: String) -> bool:
	if not is_host():
		return false
	var cleaned := privacy.to_lower()
	if cleaned not in ["public", "private"]:
		return false
	if cleaned == lobby_privacy:
		return true
	lobby_privacy = cleaned
	lobby_changed.emit()
	_broadcast_lobby_state("Lobby privacy changed")
	return true


func kick_peer(peer_id: int) -> bool:
	if not is_host() or peer_id == 1 or not peers.has(peer_id):
		return false
	var peer = multiplayer.multiplayer_peer
	if not peer is ENetMultiplayerPeer:
		return false
	peer.disconnect_peer(peer_id)
	return true

# Find the in-map human controlled by a transport peer. Gameplay systems that
# already have a match actor ID must call find_actor() instead.
func find_net_player(peer_id: int) -> Node:
	var scene = get_tree().current_scene
	if scene == null:
		return null
	var np = scene.get_node_or_null("NetPlayers")
	if np == null:
		return null
	for c in np.get_children():
		var owner_id = c.get("owner_peer_id")
		if not ("is_bot" in c and c.is_bot) and (owner_id == peer_id or (owner_id == null and c.get("net_authority_id") == peer_id)):
			return c
	return null

func find_actor(id: int) -> Node:
	var scene = get_tree().current_scene
	if scene == null:
		return null
	var np = scene.get_node_or_null("NetPlayers")
	if np == null:
		return null
	for c in np.get_children():
		if c.get("actor_id") == id:
			return c
	return null

# First address in Tailscale's 100.64.0.0/10 CGNAT range, for display/sharing.
func get_tailscale_ip() -> String:
	for addr in IP.get_local_addresses():
		if not (addr is String) or not addr.contains("."):
			continue
		var parts := addr.split(".")
		if parts.size() != 4:
			continue
		if parts[0] == "100":
			var second := int(parts[1])
			if second >= 64 and second <= 127:
				return addr
	return ""

# ------------------------------------------------------------
# Roster (name exchange)
# ------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	_net_log("peer %d connected" % id)
	# Existing match actors must not be replicated to a newcomer while that
	# peer is still in the waiting-room scene.  Every synchronizer authority
	# sees this connection event, so refresh its visibility filter immediately
	# rather than waiting for the compatibility/roster handshake to finish.
	_refresh_gameplay_replication_visibility(id)
	if multiplayer.is_server():
		# Placeholder until the newcomer registers its real name. We do NOT
		# push the roster here — reliable RPCs sent in the first ~1s after
		# connect can be dropped by ENet. The client pulls it instead.
		_provisional_peers[id] = Time.get_ticks_msec() + int(COMPATIBILITY_TIMEOUT_SECONDS * 1000.0)
		_expire_provisional_peer(id)

func _on_peer_disconnected(id: int) -> void:
	_net_log("peer %d disconnected" % id)
	_provisional_peers.erase(id)
	_one_of_us_volunteers.erase(id)
	if _prelaunch_active:
		cancel_prelaunch("Roster changed — start countdown cancelled")
	if peers.has(id):
		peers.erase(id)
		lobby_ready.erase(id)
		_playpen_ready_peers.erase(id)
		match_participant_peers.erase(id)
		match_load_status.erase(id)
		lobby_changed.emit()
		lobby_readiness_changed.emit()
		playpen_members_changed.emit()
		if multiplayer.is_server():
			_broadcast_lobby_state()
	match_readiness_changed.emit()

func _on_connected_to_server() -> void:
	_net_log("connected to host as peer %d" % multiplayer.get_unique_id())
	_pull_roster()

func _pull_roster() -> void:
	# Give ENet a moment to settle, then register + pull with retries. RPCs
	# fired in the first frames after connect can be dropped.
	var attempt := _connection_attempt
	await get_tree().create_timer(0.3).timeout
	if not is_online() or attempt != _connection_attempt:
		return
	for i in 10:
		if not is_online() or attempt != _connection_attempt:
			return
		_register_client_hello.rpc_id(
			1, BuildInfo.compatibility_payload(), local_name(), local_skin_id())
		_request_roster.rpc_id(1)
		await get_tree().create_timer(0.4).timeout
		if peers.size() >= 1:
			return

@rpc("any_peer", "reliable")
func _request_roster() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not peers.has(sender):
		return
	_send_roster.rpc_id(sender, peers, lobby_name,
		lobby_ready, _lobby_metadata(), "")
	_send_current_match_config(sender)

func _on_connection_failed() -> void:
	if not _joining:
		return
	_net_log("ENet reported connection failure")
	_reset_session(true)
	connection_failed.emit()

func _on_server_disconnected() -> void:
	if not _online:
		return
	_net_log("host disconnected")
	_reset_session(true)
	PauseManager.reset_pause_state()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	server_disconnected.emit()

@rpc("any_peer", "reliable")
func _register_client_hello(
		compatibility: Dictionary, pname: String, requested_skin_id := "blue") -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if peers.has(sender):
		return
	var error := BuildInfo.host_compatibility_error(compatibility)
	if error == "" and peers.size() >= lobby_max_players:
		error = "This lobby is full."
	if error != "":
		_reject_provisional_peer.rpc_id(sender, error)
		_disconnect_rejected_peer(sender)
		return
	var cleaned := pname.strip_edges().substr(0, 24)
	if cleaned == "":
		cleaned = "Player"
	var role := "waiting" if lobby_in_progress else "lobby"
	peers[sender] = {
		"name": cleaned,
		"skin_id": PlayerSkinRegistry.sanitize_skin_id(requested_skin_id),
		"actor_id": _next_human_actor_id,
		"team_id": _least_populated_team(),
		"role": role,
	}
	_one_of_us_volunteers[sender] = false
	_next_human_actor_id += 1
	_provisional_peers.erase(sender)
	lobby_ready[sender] = false
	if _prelaunch_active:
		cancel_prelaunch("Roster changed — start countdown cancelled")
	lobby_changed.emit()
	_broadcast_lobby_state()   # rebroadcast the updated roster to everyone
	_send_current_match_config(sender)
	if lobby_in_progress:
		_set_peer_actor_replication.call_deferred(sender, false)


@rpc("any_peer", "reliable")
func _request_name_change(pname: String) -> void:
	if not multiplayer.is_server() or lobby_in_progress:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not peers.has(sender):
		return
	var cleaned := pname.strip_edges().substr(0, 24)
	if cleaned == "":
		return
	peers[sender]["name"] = cleaned
	_net_log("peer %d renamed to '%s'" % [sender, cleaned])
	lobby_changed.emit()
	_broadcast_lobby_state()


@rpc("any_peer", "reliable")
func _request_skin_change(requested_id: String) -> void:
	if not multiplayer.is_server() or lobby_in_progress:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not peers.has(sender):
		return
	peers[sender]["skin_id"] = PlayerSkinRegistry.sanitize_skin_id(requested_id)
	lobby_changed.emit()
	_broadcast_lobby_state()


@rpc("authority", "reliable")
func _reject_provisional_peer(message: String) -> void:
	compatibility_rejected.emit(message)
	_reset_session(true)


func _disconnect_rejected_peer(peer_id: int) -> void:
	await get_tree().create_timer(0.15).timeout
	var peer = multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		peer.disconnect_peer(peer_id)


func _expire_provisional_peer(peer_id: int) -> void:
	await get_tree().create_timer(COMPATIBILITY_TIMEOUT_SECONDS).timeout
	if not is_host() or not _provisional_peers.has(peer_id) or peers.has(peer_id):
		return
	_reject_provisional_peer.rpc_id(peer_id, "Compatibility handshake timed out after 5 seconds.")
	_disconnect_rejected_peer(peer_id)


func _least_populated_team() -> int:
	var counts := []
	counts.resize(clampi(GameConfig.team_count, 2, 4))
	counts.fill(0)
	for entry in peers.values():
		var team := int(entry.get("team_id", -1))
		if team >= 0 and team < counts.size():
			counts[team] += 1
	var result := 0
	for index in range(1, counts.size()):
		if counts[index] < counts[result]:
			result = index
	return result

@rpc("authority", "reliable")
func _send_roster(roster: Dictionary, session_name: String = "",
		ready_state: Dictionary = {}, metadata: Dictionary = {}, notice := "") -> void:
	peers = roster.duplicate(true)
	lobby_ready = ready_state.duplicate(true)
	if session_name != "":
		lobby_name = session_name
	if not metadata.is_empty():
		lobby_privacy = str(metadata.get("privacy", lobby_privacy))
		lobby_share_code = str(metadata.get("share_code", lobby_share_code))
		lobby_max_players = clampi(int(metadata.get("max_players", lobby_max_players)),
			MatchLimitsData.MIN_ONLINE_HUMANS, MAX_PEERS)
		lobby_in_progress = bool(metadata.get("in_progress", lobby_in_progress))
		match_participant_peers = metadata.get("participants", match_participant_peers).duplicate()
	if peers.has(local_id()):
		local_match_role = str(peers[local_id()].get("role", "lobby"))
		if _joining:
			_joining = false
			connection_succeeded.emit()
	lobby_changed.emit()
	lobby_readiness_changed.emit()
	_refresh_gameplay_replication_visibility.call_deferred()
	if notice != "":
		lobby_notice.emit(notice)


# MultiplayerSynchronizer visibility is also the MultiplayerSpawner's spawn
# visibility for the synchronizer root.  During an active match, provisional
# peers and waiting-room peers must remain invisible until they have loaded the
# map and completed the spectator-ready handshake.
func is_gameplay_replication_visible_to_peer(peer_id: int) -> bool:
	if not lobby_in_progress:
		if local_match_role in ["playpen", "playpen_loading", "playpen_hosting"]:
			return peers.has(peer_id) \
				and str(peers[peer_id].get("role", "lobby")) == "playpen"
		return true
	if not peers.has(peer_id):
		return false
	return str(peers[peer_id].get("role", "waiting")) in ["participant", "spectator"]


func active_match_peer_ids() -> Array:
	var result: Array = []
	for peer_key in peers:
		var peer_id := int(peer_key)
		if not lobby_in_progress and local_match_role in ["playpen", "playpen_loading", "playpen_hosting"]:
			if str(peers[peer_id].get("role", "lobby")) == "playpen":
				result.append(peer_id)
			continue
		if str(peers[peer_id].get("role", "waiting")) in ["participant", "spectator"]:
			result.append(peer_id)
	result.sort()
	return result


# Scene-bound gameplay RPCs cannot be broadcast to peers still sitting in the
# lobby scene: their scene tree has no matching node path and Godot will reject
# (and potentially poison the cache for) later packets. The host calls this for
# match traffic; autoload roster/config RPCs continue to include every peer.
func broadcast_match_rpc(source: Node, method: StringName, args: Array = [],
		invoke_local := true) -> void:
	if not is_host() or source == null:
		return
	# Queue remote packets before call_local: some gameplay handlers reparent
	# their source node (notably the gun). Resolving the RPC path after that
	# mutation would address a path the remote peer has not applied yet.
	for peer_id in active_match_peer_ids():
		if peer_id == local_id():
			continue
		var rpc_args: Array = [peer_id, method]
		rpc_args.append_array(args)
		source.callv("rpc_id", rpc_args)
	if invoke_local:
		source.callv(method, args)


func _refresh_gameplay_replication_visibility(peer_id: int = 0) -> void:
	var scene := get_tree().current_scene
	var net_players := scene.get_node_or_null("NetPlayers") if scene != null else null
	if net_players == null:
		return
	for actor in net_players.get_children():
		for sync_name in ["SpawnVisibility", "NetSync"]:
			var synchronizer := actor.get_node_or_null(sync_name) as MultiplayerSynchronizer
			if synchronizer == null or not synchronizer.is_multiplayer_authority():
				continue
			if peer_id > 0:
				var actor_visible := is_gameplay_replication_visible_to_peer(peer_id)
				synchronizer.set_visibility_for(peer_id, actor_visible)
				synchronizer.update_visibility(peer_id)
			else:
				for connected_peer in multiplayer.get_peers():
					var connected_id := int(connected_peer)
					synchronizer.set_visibility_for(connected_id,
						is_gameplay_replication_visible_to_peer(connected_id))
					synchronizer.update_visibility(connected_id)


func _lobby_metadata() -> Dictionary:
	return {
		"privacy": lobby_privacy,
		"share_code": lobby_share_code,
		"max_players": lobby_max_players,
		"in_progress": lobby_in_progress,
		"participants": match_participant_peers.duplicate(),
	}


func _broadcast_lobby_state(notice := "") -> void:
	if not is_host():
		return
	_send_roster.rpc(peers, lobby_name, lobby_ready, _lobby_metadata(), notice)


func _send_current_match_config(peer_id: int) -> void:
	if not is_host() or pending_map_path == "" or not peers.has(peer_id):
		return
	_apply_match_config.rpc_id(peer_id, GameConfig.snapshot_for_network(), pending_map_path)

# ------------------------------------------------------------
# Match config + map sync (host -> clients)
# ------------------------------------------------------------

func broadcast_match_config(config: Dictionary, map_path: String) -> void:
	if not is_host():
		return
	pending_map_path = map_path
	_apply_match_config.rpc(config, map_path)

@rpc("authority", "reliable", "call_local")
func _apply_match_config(config: Dictionary, map_path: String) -> void:
	GameConfig.apply_network_values(config)
	pending_map_path = map_path
	match_config_received.emit()

# ------------------------------------------------------------
# Coordinated match start
# ------------------------------------------------------------

func begin_prelaunch(map_path: String) -> void:
	if not is_host() or _prelaunch_active or lobby_in_progress:
		return
	_prelaunch_active = true
	_prelaunch_generation += 1
	_run_prelaunch(map_path, _prelaunch_generation)


func _run_prelaunch(map_path: String, generation: int) -> void:
	for seconds in range(3, 0, -1):
		if generation != _prelaunch_generation or not _prelaunch_active:
			return
		_prelaunch_seconds = seconds
		_net_prelaunch_state.rpc(true, seconds, "")
		await get_tree().create_timer(1.0).timeout
	if generation != _prelaunch_generation or not _prelaunch_active:
		return
	_prelaunch_active = false
	_net_prelaunch_state.rpc(false, 0, "")
	start_game(map_path)


func cancel_prelaunch(reason := "Start countdown cancelled") -> void:
	if not is_host() or not _prelaunch_active:
		return
	_prelaunch_active = false
	_prelaunch_generation += 1
	_net_prelaunch_state.rpc(false, 0, reason)


@rpc("authority", "reliable", "call_local")
func _net_prelaunch_state(active: bool, seconds: int, reason: String) -> void:
	_prelaunch_active = active
	_prelaunch_seconds = seconds
	prelaunch_countdown_changed.emit(active, seconds)
	if reason != "":
		lobby_notice.emit(reason)


func start_game(map_path: String) -> void:
	if not is_host():
		return
	pending_map_path = map_path
	lobby_in_progress = true
	pending_match_id += 1
	_match_ready_peers.clear()
	match_participant_peers = peer_ids_sorted()
	match_load_status.clear()
	for peer_id in match_participant_peers:
		peers[peer_id]["role"] = "participant"
		match_load_status[peer_id] = {"state": "loading", "attempt": 1, "reason": ""}
	local_match_role = "participant"
	_broadcast_lobby_state()
	_match_load_watch_generation += 1
	_watch_match_load(pending_match_id, _match_load_watch_generation)
	_net_log("starting match %d on %s for %d peers" % [pending_match_id, map_path, peers.size()])
	_start_game.rpc(map_path, pending_match_id, false)

@rpc("authority", "reliable", "call_local")
func _start_game(map_path: String, match_id: int, spectator: bool = false) -> void:
	# Spectator admission retries the start packet because a waiting-room scene
	# transition can briefly drop an RPC. Once the first packet has claimed this
	# match, later retries must not reload the map and invalidate the spawner/RPC
	# path cache that the first load just registered.
	if spectator and local_match_role == "spectator" and pending_match_id == match_id:
		_net_log("ignored duplicate spectator start for match %d" % match_id)
		return
	_net_log("received match scene start (match=%d, spectator=%s, map=%s)" % [
		match_id, spectator, map_path])
	pending_map_path = map_path
	pending_match_id = match_id
	if not spectator:
		_match_ready_peers.clear()
	local_match_role = "spectator" if spectator else "participant"
	set_accepting_new_peers(true)
	var error := get_tree().change_scene_to_file(map_path)
	if error != OK:
		_ensure_load_recovery_overlay()
		report_match_scene_failed("Could not load map resource (error %d)." % error, spectator)

# Host-only ENet admission gate. Matches currently keep this open because late
# peers enter the waiting role; visibility and match-RPC recipient filtering
# keep gameplay state away until spectator readiness.
func set_accepting_new_peers(accepting: bool) -> void:
	if not is_host():
		return
	var peer = multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		peer.refuse_new_connections = not accepting

# Each peer reports readiness only after its map has created the same
# MultiplayerSpawner path. This replaces the old fixed delay, which could
# spawn too early on a slower machine and silently lose replicated players.
func report_match_scene_ready() -> void:
	if not is_online() or pending_match_id <= 0 or local_match_role != "participant":
		return
	if is_host():
		_mark_match_scene_ready(1, pending_match_id)
	else:
		_net_log("reporting match %d scene ready" % pending_match_id)
		_report_match_scene_ready.rpc_id(1, pending_match_id)

@rpc("any_peer", "reliable")
func _report_match_scene_ready(match_id: int) -> void:
	if not multiplayer.is_server():
		return
	_mark_match_scene_ready(multiplayer.get_remote_sender_id(), match_id)

func _mark_match_scene_ready(peer_id: int, match_id: int) -> void:
	if not is_host() or match_id != pending_match_id or not peers.has(peer_id):
		return
	_match_ready_peers[peer_id] = true
	match_load_status[peer_id] = {
		"state": "ready",
		"attempt": int(match_load_status.get(peer_id, {}).get("attempt", 1)),
		"reason": "",
	}
	_net_log("match %d ready peer %d (%d/%d)" % [match_id, peer_id, _match_ready_peers.size(), match_participant_peers.size()])
	match_readiness_changed.emit()
	match_load_status_changed.emit()
	_broadcast_match_load_status()

func are_all_match_peers_ready() -> bool:
	if pending_match_id <= 0 or match_participant_peers.is_empty():
		return false
	for peer_id in match_participant_peers:
		if is_host():
			if not _match_ready_peers.has(peer_id):
				return false
		elif str(match_load_status.get(peer_id, {}).get("state", "loading")) != "ready":
			return false
	return true


func report_match_scene_failed(reason: String, spectator := false) -> void:
	if not is_online():
		return
	if spectator:
		local_match_role = "waiting"
		spectator_state_changed.emit()
		return
	if is_host():
		_mark_match_scene_failed(1, pending_match_id, reason)
	else:
		_report_match_scene_failed.rpc_id(1, pending_match_id, reason)


@rpc("any_peer", "reliable")
func _report_match_scene_failed(match_id: int, reason: String) -> void:
	if multiplayer.is_server():
		_mark_match_scene_failed(multiplayer.get_remote_sender_id(), match_id, reason)


func _mark_match_scene_failed(peer_id: int, match_id: int, reason: String) -> void:
	if not is_host() or match_id != pending_match_id or not match_participant_peers.has(peer_id):
		return
	var attempt := int(match_load_status.get(peer_id, {}).get("attempt", 1))
	match_load_status[peer_id] = {"state": "failed", "attempt": attempt, "reason": reason}
	match_load_status_changed.emit()
	_broadcast_match_load_status()


func _watch_match_load(match_id: int, watch_generation: int) -> void:
	var timeout := TEST_MATCH_LOAD_TIMEOUT_SECONDS if OS.get_environment("ONEGUN_TEST_SHORT_LOAD_TIMEOUT") == "1" else MATCH_LOAD_TIMEOUT_SECONDS
	await get_tree().create_timer(timeout).timeout
	if not is_host() or match_id != pending_match_id or watch_generation != _match_load_watch_generation:
		return
	for peer_id in match_participant_peers:
		if not _match_ready_peers.has(peer_id):
			_mark_match_scene_failed(peer_id, match_id, "Scene-ready handshake timed out after %.0f seconds." % timeout)


func retry_failed_match_loads() -> void:
	if not is_host():
		return
	for peer_id in match_participant_peers:
		if str(match_load_status.get(peer_id, {}).get("state", "loading")) != "ready":
			var attempt := int(match_load_status.get(peer_id, {}).get("attempt", 1)) + 1
			match_load_status[peer_id] = {"state": "loading", "attempt": attempt, "reason": ""}
			_match_ready_peers.erase(peer_id)
			_retry_match_load.rpc_id(peer_id, pending_map_path, pending_match_id)
	_broadcast_match_load_status()
	_match_load_watch_generation += 1
	_watch_match_load(pending_match_id, _match_load_watch_generation)


@rpc("authority", "reliable", "call_local")
func _retry_match_load(map_path: String, match_id: int) -> void:
	pending_map_path = map_path
	pending_match_id = match_id
	local_match_role = "participant"
	var error := get_tree().change_scene_to_file(map_path)
	if error != OK:
		_ensure_load_recovery_overlay()
		report_match_scene_failed("Retry could not load map resource (error %d)." % error)


func _ensure_load_recovery_overlay() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.get_node_or_null("OnlineLoadOverlay") != null:
		return
	var overlay = load("res://online_load_overlay.gd").new()
	overlay.name = "OnlineLoadOverlay"
	scene.add_child(overlay)


func remove_failed_match_peers_and_continue() -> bool:
	if not is_host():
		return false
	var failed: Array = []
	for peer_id in match_participant_peers:
		if str(match_load_status.get(peer_id, {}).get("state", "loading")) != "ready":
			failed.append(peer_id)
	var remaining := match_participant_peers.filter(func(id): return not failed.has(id))
	if failed.has(1) or not _remaining_match_is_valid(remaining):
		return false
	for peer_id in failed:
		_remove_from_active_match.rpc_id(peer_id, "Removed because the match scene did not load.")
		match_participant_peers.erase(peer_id)
		match_load_status.erase(peer_id)
		if peers.has(peer_id):
			peers[peer_id]["role"] = "waiting"
	_broadcast_lobby_state()
	match_readiness_changed.emit()
	return true


func _remaining_match_is_valid(remaining_human_peers: Array) -> bool:
	if remaining_human_peers.size() + GameConfig.bot_configs.size() < MatchLimitsData.MIN_ONLINE_HUMANS:
		return false
	if not GameConfig.teams_enabled:
		return true
	var represented := _represented_teams(remaining_human_peers)
	for bot_config in GameConfig.bot_configs:
		var bot_team := int(bot_config.get("team_id", -1))
		if bot_team >= 0 and not represented.has(bot_team):
			represented.append(bot_team)
	return represented.size() >= 2


@rpc("authority", "reliable")
func _remove_from_active_match(reason: String) -> void:
	local_match_role = "waiting"
	lobby_notice.emit(reason)
	get_tree().change_scene_to_file("res://game_setup.tscn")


func request_spectate_current_match() -> void:
	if not is_online() or not lobby_in_progress or local_match_role not in ["waiting", "lobby"] or is_host():
		_net_log("spectate request ignored (online=%s, in_progress=%s, role=%s, host=%s)" % [
			is_online(), lobby_in_progress, local_match_role, is_host()])
		return
	_net_log("requesting spectator entry for match %d" % pending_match_id)
	_request_spectate_current_match.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_spectate_current_match() -> void:
	if not multiplayer.is_server() or not lobby_in_progress:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not peers.has(sender) or match_participant_peers.has(sender):
		_net_log("rejected spectator request from peer %d" % sender)
		return
	_net_log("accepted spectator request from peer %d for match %d" % [sender, pending_match_id])
	peers[sender]["role"] = "spectator_loading"
	_set_peer_actor_replication(sender, false)
	_broadcast_lobby_state()
	_send_spectator_match_start(sender, pending_map_path, pending_match_id)


func _send_spectator_match_start(peer_id: int, map_path: String, match_id: int) -> void:
	# Roster admission and a scene switch may happen in the same network frame.
	# Let the client finish its waiting-room transition, then retry the idempotent
	# start message until its scene-ready acknowledgement changes the role.
	await get_tree().create_timer(0.15).timeout
	for attempt in 3:
		if not is_host() or not peers.has(peer_id) \
				or str(peers[peer_id].get("role", "")) != "spectator_loading":
			return
		_start_game.rpc_id(peer_id, map_path, match_id, true)
		_net_log("spectator start sent to peer %d attempt %d" % [
			peer_id, attempt + 1])
		await get_tree().create_timer(0.6).timeout


func report_spectator_scene_ready() -> void:
	if not is_online() or local_match_role != "spectator":
		return
	_net_log("reporting spectator scene ready for match %d" % pending_match_id)
	if is_host():
		_mark_spectator_scene_ready(1, pending_match_id)
	else:
		_report_spectator_scene_ready.rpc_id(1, pending_match_id)


@rpc("any_peer", "reliable")
func _report_spectator_scene_ready(match_id: int) -> void:
	if multiplayer.is_server():
		_mark_spectator_scene_ready(multiplayer.get_remote_sender_id(), match_id)


func _mark_spectator_scene_ready(peer_id: int, match_id: int) -> void:
	if not is_host() or match_id != pending_match_id or not peers.has(peer_id):
		return
	if str(peers[peer_id].get("role", "")) != "spectator_loading":
		return
	_net_log("spectator peer %d ready for match %d" % [peer_id, match_id])
	peers[peer_id]["role"] = "spectator"
	_set_peer_actor_replication(peer_id, true)
	_broadcast_lobby_state()
	var scene := get_tree().current_scene
	var manager := scene.get_node_or_null("RoundManager") if scene != null else null
	if manager != null and manager.has_method("server_sync_late_spectator"):
		manager.server_sync_late_spectator(peer_id)


func _set_peer_actor_replication(peer_id: int, visible: bool) -> void:
	var scene := get_tree().current_scene
	var manager := scene.get_node_or_null("RoundManager") if scene != null else null
	if manager != null and manager.has_method("server_set_peer_actor_visibility"):
		manager.server_set_peer_actor_visibility(peer_id, visible)


func return_spectator_to_waiting_room() -> void:
	if not is_online() or local_match_role != "spectator":
		return
	local_match_role = "waiting"
	if not is_host():
		_set_waiting_role.rpc_id(1)
	get_tree().change_scene_to_file("res://game_setup.tscn")


@rpc("any_peer", "reliable")
func _set_waiting_role() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if peers.has(sender) and not match_participant_peers.has(sender):
		peers[sender]["role"] = "waiting"
		_broadcast_lobby_state()


func _represented_teams(peer_ids: Array) -> Array:
	var represented: Array = []
	for peer_id in peer_ids:
		var team := int(peers.get(peer_id, {}).get("team_id", -1))
		if team >= 0 and not represented.has(team):
			represented.append(team)
	return represented


func _broadcast_match_load_status() -> void:
	if is_host():
		_apply_match_load_status.rpc(match_load_status)


@rpc("authority", "reliable", "call_local")
func _apply_match_load_status(status: Dictionary) -> void:
	match_load_status = status.duplicate(true)
	match_load_status_changed.emit()
