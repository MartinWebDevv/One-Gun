extends SceneTree

# Two-process loopback validation for persistent cosmetic IDs. Launch one
# process with `-- --role=host` and one with `-- --role=client`.

const PORT := 24635
const TIMEOUT := 10.0

class CosmeticTarget:
	extends Node
	var applied_skin := ""

	func set_character_skin(value: String) -> void:
		applied_skin = value


var _role := ""
var _network: Node
var _supabase: Node


func _initialize() -> void:
	_network = root.get_node("NetworkManager")
	_supabase = root.get_node("SupabaseManager")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			_role = argument.trim_prefix("--role=")
	_run.call_deferred()


func _run() -> void:
	if _role == "host":
		await _run_host()
	elif _role == "client":
		await _run_client()
	else:
		_fail("Missing --role=host|client")


func _run_host() -> void:
	if not _network.host_game(PORT, "Cosmetic Sync Test"):
		_fail("Host could not start")
		return
	if not await _wait_until(func() -> bool: return _network.peers.size() == 2):
		_fail("Host never received the client roster")
		return
	var remote_id := -1
	for peer_id in _network.peer_ids_sorted():
		if int(peer_id) != 1:
			remote_id = int(peer_id)
	if remote_id < 0 or not await _wait_until(func() -> bool:
		var cosmetics: Dictionary = _network.peer_cosmetic_loadout(remote_id)
		return str(cosmetics.get("hat", "")) == "cowboy_hat" \
			and str(cosmetics.get("gun_skin", "")) == "golden_gun_skin"
	):
		_fail("Host never received the client's persistent cosmetic IDs")
		return
	var public_entry: Dictionary = _network.peers[remote_id]
	if public_entry.has("access_token") or public_entry.has("refresh_token") \
			or public_entry.has("gun_tokens") or public_entry.has("inventory"):
		_fail("Private Supabase state leaked into the ENet roster")
		return
	print("SUPABASE COSMETIC NETWORK OK: IDs synchronized without tokens or ownership data")
	await create_timer(0.35).timeout
	_network.disconnect_net()
	quit(0)


func _run_client() -> void:
	_seed_test_session()
	_test_local_asset_mapping()
	await create_timer(0.45).timeout
	if not _network.join_game("127.0.0.1", PORT):
		_fail("Client could not join")
		return
	if not await _wait_until(func() -> bool: return _network.peers.size() == 2):
		_fail("Client never received the roster")
		return
	if not await _wait_until(func() -> bool:
		var cosmetics: Dictionary = _network.local_cosmetic_loadout()
		return str(cosmetics.get("hat", "")) == "cowboy_hat" \
			and str(cosmetics.get("gun_skin", "")) == "golden_gun_skin"
	):
		_fail("Client's persistent cosmetic IDs did not reconcile")
		return
	if not await _wait_until(func() -> bool: return not _network.is_online()):
		_fail("Host did not close the validation session")
		return
	print("SUPABASE COSMETIC CLIENT OK: persistent IDs survived roster reconciliation")
	quit(0)


func _seed_test_session() -> void:
	# Runtime-only values: no session file is written and no backend request is
	# made. This lets the network seam be validated independently of credentials.
	_supabase.access_token = "validation-access-token"
	_supabase.refresh_token = "validation-refresh-token"
	_supabase.authenticated_user_id = "00000000-0000-0000-0000-000000000001"
	_supabase.access_token_expires_at = int(Time.get_unix_time_from_system()) + 3600
	_supabase.loadout = SupabaseCosmeticRegistry.sanitize_loadout({
		"hat": "cowboy_hat",
		"gun_skin": "golden_gun_skin",
	})


func _test_local_asset_mapping() -> void:
	var target := CosmeticTarget.new()
	root.add_child(target)
	SupabaseCosmeticRegistry.apply_to_player(target, {
		"character_skin": "purple",
		"hat": "missing_hat_art",
	})
	var stored = target.get_meta("supabase_cosmetic_loadout", {})
	if target.applied_skin != "purple" or not stored is Dictionary \
			or str(stored.get("hat", "")) != "missing_hat_art":
		_fail("Local cosmetic mapping did not apply a supported skin safely")
		target.queue_free()
		return
	target.queue_free()


func _wait_until(predicate: Callable) -> bool:
	var elapsed := 0.0
	while elapsed < TIMEOUT:
		if predicate.call():
			return true
		await create_timer(0.05).timeout
		elapsed += 0.05
	return false


func _fail(message: String) -> void:
	push_error("SUPABASE COSMETIC NETWORK FAILED: %s" % message)
	if _network != null:
		_network.disconnect_net()
	quit(1)
