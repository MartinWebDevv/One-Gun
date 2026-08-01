extends Node

# ============================================================
# NetworkManager — Autoload singleton (online multiplayer)
#
# High-level Godot MultiplayerAPI over ENet (UDP). Designed for a
# Tailscale network: peers normally discover a host-chosen lobby name across
# their tailnet; direct 100.x.x.x entry remains available as a fallback.
#
# Phase 1 scope: host/join, a peer roster with display names, host->client
# match-config + map sync, and a coordinated scene load. In-map player
# replication is handled by net_game.gd; combat sync is a later phase.
# ============================================================

const DEFAULT_PORT := 24545
const DISCOVERY_PORT := 24546
const MAX_PEERS := 10
const JOIN_TIMEOUT_SECONDS := 12.0
const DISCOVERY_TIMEOUT_SECONDS := 3.0
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

# peer_id -> { "name": String }
var peers: Dictionary = {}
# peer_id -> bool. The host is always ready because its primary lobby action
# is Start/Force Start; guests explicitly toggle their own state.
var lobby_ready: Dictionary = {}
var pending_map_path: String = ""
var pending_match_id := 0
var _online := false
var _match_ready_peers: Dictionary = {}
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
	lobby_max_players = clampi(int(options.get("max_players", MAX_PEERS)), 2, MAX_PEERS)
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
	peers[1] = {"name": local_name()}   # host is always peer id 1
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
	var maximum_players := clampi(int(payload.get("max_players", MAX_PEERS)), 2, MAX_PEERS)
	var in_progress := bool(payload.get("in_progress", false))
	var joinability := "in_progress" if in_progress else ("full" if current_players >= maximum_players else "joinable")
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
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
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
	reset_lobby_readiness("Returned to lobby — ready up again")
	_net_return_everyone_to_lobby.rpc()

@rpc("authority", "reliable", "call_local")
func _net_return_everyone_to_lobby() -> void:
	lobby_in_progress = false
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
	lobby_ready.clear()
	pending_map_path = ""
	pending_match_id = 0
	_match_ready_peers.clear()
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

func local_id() -> int:
	if not is_online():
		return 1
	return multiplayer.get_unique_id()

func local_name() -> String:
	var n = PlayerPrefs.get_setting("player_name")
	return str(n) if n != null and str(n) != "" else "Player"

func set_local_name(new_name: String) -> bool:
	var cleaned := new_name.strip_edges().substr(0, 24)
	if cleaned == "":
		return false
	PlayerPrefs.set_setting("player_name", cleaned)
	if not is_online():
		return true
	var id := local_id()
	if is_host():
		peers[id] = {"name": cleaned}
		lobby_changed.emit()
		_broadcast_lobby_state()
	else:
		_register_name.rpc_id(1, cleaned)
	return true

func peer_name(peer_id: int) -> String:
	var entry = peers.get(peer_id, {})
	var pname := str(entry.get("name", ""))
	return pname if pname != "" else "Player %d" % peer_id

func peer_ids_sorted() -> Array:
	var ids := peers.keys()
	ids.sort()
	return ids


func is_peer_lobby_ready(peer_id: int) -> bool:
	# The host's start controls replace a separate Ready Up action.
	return peer_id == 1 or bool(lobby_ready.get(peer_id, false))


func are_all_lobby_guests_ready() -> bool:
	if not is_online():
		return false
	for peer_id in peers:
		if int(peer_id) != 1 and not is_peer_lobby_ready(int(peer_id)):
			return false
	return true


func set_local_lobby_ready(ready: bool) -> void:
	if not is_online() or local_id() == 1:
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
		if int(peer_id) != 1:
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

# Find the in-map networked player node for a given peer id (spawned under
# NetPlayers by round_manager). Returns null if not present.
func find_net_player(id: int) -> Node:
	var scene = get_tree().current_scene
	if scene == null:
		return null
	var np = scene.get_node_or_null("NetPlayers")
	if np == null:
		return null
	for c in np.get_children():
		# Human actor IDs are their peer IDs. Bots are also owned by peer 1,
		# so matching owner_peer_id alone could accidentally return a host bot.
		if c.get("actor_id") == id and not ("is_bot" in c and c.is_bot):
			return c
	for c in np.get_children():
		var owner_id = c.get("owner_peer_id")
		if not ("is_bot" in c and c.is_bot) and (owner_id == id or (owner_id == null and c.get("net_authority_id") == id)):
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
	if multiplayer.is_server():
		# Placeholder until the newcomer registers its real name. We do NOT
		# push the roster here — reliable RPCs sent in the first ~1s after
		# connect can be dropped by ENet. The client pulls it instead.
		peers[id] = {"name": "Player %d" % id}
		lobby_ready[id] = false
		lobby_changed.emit()
		lobby_readiness_changed.emit()

func _on_peer_disconnected(id: int) -> void:
	_net_log("peer %d disconnected" % id)
	if peers.has(id):
		peers.erase(id)
		lobby_ready.erase(id)
		lobby_changed.emit()
		lobby_readiness_changed.emit()
		if multiplayer.is_server():
			_broadcast_lobby_state()
	match_readiness_changed.emit()

func _on_connected_to_server() -> void:
	_joining = false
	_net_log("connected to host as peer %d" % multiplayer.get_unique_id())
	connection_succeeded.emit()
	_pull_roster()

func _pull_roster() -> void:
	# Give ENet a moment to settle, then register + pull with retries. RPCs
	# fired in the first frames after connect can be dropped.
	var attempt := _connection_attempt
	await get_tree().create_timer(0.3).timeout
	if not is_online() or attempt != _connection_attempt:
		return
	_register_name.rpc_id(1, local_name())
	for i in 10:
		if not is_online() or attempt != _connection_attempt:
			return
		_request_roster.rpc_id(1)
		await get_tree().create_timer(0.4).timeout
		if peers.size() >= 1:
			return

@rpc("any_peer", "reliable")
func _request_roster() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
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
func _register_name(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var cleaned := pname.strip_edges().substr(0, 24)
	if cleaned == "":
		return
	var sender := multiplayer.get_remote_sender_id()
	peers[sender] = {"name": cleaned}
	if not lobby_ready.has(sender):
		lobby_ready[sender] = false
	lobby_changed.emit()
	_broadcast_lobby_state()   # rebroadcast the updated roster to everyone
	_send_current_match_config(sender)

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
		lobby_max_players = clampi(int(metadata.get("max_players", lobby_max_players)), 2, MAX_PEERS)
		lobby_in_progress = bool(metadata.get("in_progress", lobby_in_progress))
	lobby_changed.emit()
	lobby_readiness_changed.emit()
	if notice != "":
		lobby_notice.emit(notice)


func _lobby_metadata() -> Dictionary:
	return {
		"privacy": lobby_privacy,
		"share_code": lobby_share_code,
		"max_players": lobby_max_players,
		"in_progress": lobby_in_progress,
	}


func _broadcast_lobby_state(notice := "") -> void:
	if not is_host():
		return
	_send_roster.rpc(peers, lobby_name, lobby_ready, _lobby_metadata(), notice)


func _send_current_match_config(peer_id: int) -> void:
	if not is_host() or pending_map_path == "" or not peers.has(peer_id):
		return
	_apply_match_config.rpc_id(peer_id, GameConfig.snapshot_for_preset(), pending_map_path)

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
	GameConfig.apply_preset_values(config)
	pending_map_path = map_path
	match_config_received.emit()

# ------------------------------------------------------------
# Coordinated match start
# ------------------------------------------------------------

func start_game(map_path: String) -> void:
	if not is_host():
		return
	pending_map_path = map_path
	lobby_in_progress = true
	pending_match_id += 1
	_match_ready_peers.clear()
	_net_log("starting match %d on %s for %d peers" % [pending_match_id, map_path, peers.size()])
	_start_game.rpc(map_path, pending_match_id)

@rpc("authority", "reliable", "call_local")
func _start_game(map_path: String, match_id: int) -> void:
	pending_map_path = map_path
	pending_match_id = match_id
	_match_ready_peers.clear()
	set_accepting_new_peers(false)   # no late joins mid-match
	get_tree().change_scene_to_file(map_path)

# Host-only: gate whether new peers may connect. Closed during a match — a
# late joiner would get a roster entry while sitting in the lobby scene, and
# the MultiplayerSpawner would try to replicate players into a scene that has
# no NetPlayers path. Reopened whenever everyone returns to the lobby.
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
	if not is_online() or pending_match_id <= 0:
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
	_net_log("match %d ready peer %d (%d/%d)" % [match_id, peer_id, _match_ready_peers.size(), peers.size()])
	match_readiness_changed.emit()

func are_all_match_peers_ready() -> bool:
	if not is_host() or pending_match_id <= 0 or peers.is_empty():
		return false
	for peer_id in peers:
		if not _match_ready_peers.has(peer_id):
			return false
	return true
