extends SceneTree

# Two-process smoke test for Section 5 host authority. Launch one process with
# `-- --role=host` and a second with `-- --role=client`.

const PORT := 24615
const TIMEOUT := 12.0
var _role := ""
var _network
var _config


func _initialize() -> void:
	_network = root.get_node("NetworkManager")
	_config = root.get_node("GameConfig")
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
	_config.set_bot_count(2)
	_network.broadcast_match_config(_config.snapshot_for_preset(), "res://maps/test/ForestMap.tscn")
	if not await _wait_until(func(): return _network.peers.size() == 2):
		_fail("host never received client roster")
		return
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
	quit(0)


func _wait_until(predicate: Callable) -> bool:
	var elapsed := 0.0
	while elapsed < TIMEOUT:
		if predicate.call(): return true
		await create_timer(0.05).timeout
		elapsed += 0.05
	return false


func _fail(message: String) -> void:
	push_error("LOBBY TEST FAILED: %s" % message)
	_network.disconnect_net()
	quit(1)
