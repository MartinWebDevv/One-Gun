extends Node

# Two-process smoke for the real Phase 4 discovery service boundary.
# User args: --role=host|client --mode=public_browser|private_code

const TEST_PORT := 24748
const TEST_LOBBY := "Phase Four Discovery"
const TEST_CODE := "PHASE4"
const TIMEOUT_MSEC := 15000

var _role := ""
var _mode := "public_browser"
var _list_received := false
var _discovered_lobbies: Array = []


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			_role = argument.trim_prefix("--role=")
		elif argument.begins_with("--mode="):
			_mode = argument.trim_prefix("--mode=")
	if _role not in ["host", "client"] or _mode not in ["public_browser", "private_code"]:
		_fail("invalid role or mode")
		return
	_run.call_deferred()


func _run() -> void:
	if _role == "host":
		await _run_host()
	else:
		await _run_client()


func _run_host() -> void:
	var privacy := "private" if _mode == "private_code" else "public"
	if not NetworkManager.host_game(TEST_PORT, TEST_LOBBY, {
		"privacy": privacy,
		"max_players": 10,
		"share_code": TEST_CODE,
	}):
		_fail("host_game failed")
		return
	if not await _wait_for(func() -> bool: return NetworkManager.peers.size() >= 2):
		_fail("client did not connect")
		return
	print("ONLINE_PHASE4_%s_PASS host" % _mode.to_upper())
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()


func _run_client() -> void:
	if _mode == "public_browser":
		_list_received = false
		_discovered_lobbies.clear()
		if not NetworkManager.lobby_list_updated.is_connected(_on_lobby_list_updated):
			NetworkManager.lobby_list_updated.connect(_on_lobby_list_updated)
		NetworkManager.discover_lobbies()
		if not await _wait_for(func() -> bool: return _list_received):
			_fail("public browser did not finish discovery")
			return
		var selected: Dictionary = {}
		for lobby in _discovered_lobbies:
			if str(lobby.get("name", "")) == TEST_LOBBY:
				selected = lobby
				break
		if selected.is_empty():
			_fail("public lobby was not discovered")
			return
		if str(selected.get("privacy", "")) != "public" or int(selected.get("max_players", 0)) != 10:
			_fail("public browser metadata was incomplete")
			return
		if not NetworkManager.join_discovered_lobby(selected):
			_fail("joining selected browser row did not start")
			return
	else:
		_list_received = false
		_discovered_lobbies.clear()
		if not NetworkManager.lobby_list_updated.is_connected(_on_lobby_list_updated):
			NetworkManager.lobby_list_updated.connect(_on_lobby_list_updated)
		NetworkManager.discover_lobbies()
		if not await _wait_for(func() -> bool: return _list_received):
			_fail("private visibility check did not finish")
			return
		for lobby in _discovered_lobbies:
			if str(lobby.get("name", "")) == TEST_LOBBY:
				_fail("private lobby leaked into public discovery")
				return
		if not NetworkManager.join_lobby_by_code(TEST_CODE):
			_fail("private-code lookup did not start")
			return
	if not await _wait_for(_client_connected):
		_fail("client did not establish the ENet session")
		return
	if NetworkManager.lobby_name != TEST_LOBBY:
		_fail("discovered lobby identity was not retained")
		return
	print("ONLINE_PHASE4_%s_PASS client" % _mode.to_upper())
	await get_tree().create_timer(0.4).timeout
	get_tree().quit()


func _on_lobby_list_updated(lobbies: Array) -> void:
	_list_received = true
	_discovered_lobbies = lobbies.duplicate(true)


func _client_connected() -> bool:
	return NetworkManager.is_online() \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _wait_for(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().create_timer(0.05).timeout
	return false


func _fail(message: String) -> void:
	push_error("ONLINE PHASE 4 SMOKE FAIL (%s/%s): %s" % [_role, _mode, message])
	get_tree().quit(1)
