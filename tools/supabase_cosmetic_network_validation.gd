extends SceneTree

# Two-process loopback validation for persistent cosmetic IDs. Launch one
# process with `-- --role=host` and one with `-- --role=client`. The fixture
# publishes through NetworkManager's normal public loadout seam after admission
# so a developer's saved Supabase session cannot overwrite the test data.

const PORT := 24635
const TIMEOUT := 10.0
const TEST_HAT_ID := "hat_cowboy_classic"
const TEST_GUN_ID := "golden_gun_skin"
const TEST_THEME_ID := "wc_theme_deep_orbit"
const TEST_CHARACTER_MODEL_ID := "character_goldfish_bag_man"

class CosmeticTarget:
	extends Node
	var applied_skin := ""
	var applied_model := ""

	func set_character_skin(value: String) -> void:
		applied_skin = value

	func set_character_model(value: String) -> void:
		applied_model = value


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
		return str(cosmetics.get("hat", "")) == TEST_HAT_ID \
			and str(cosmetics.get("gun_skin", "")) == TEST_GUN_ID \
			and str(cosmetics.get("ceremony_theme", "")) == TEST_THEME_ID \
			and str(cosmetics.get("character_model", "")) == TEST_CHARACTER_MODEL_ID
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
	_test_local_asset_mapping()
	await create_timer(0.45).timeout
	if not _network.join_game("127.0.0.1", PORT):
		_fail("Client could not join")
		return
	if not await _wait_until(func() -> bool: return _network.peers.size() == 2):
		_fail("Client never received the roster")
		return
	# Let the admission RPC unwind before issuing the client-owned loadout RPC.
	# ENet can otherwise discard a same-frame nested request on slower runners.
	await create_timer(0.25).timeout
	var fixture_loadout := SupabaseCosmeticRegistry.sanitize_loadout({
		"character_model": TEST_CHARACTER_MODEL_ID,
		"hat": TEST_HAT_ID,
		"gun_skin": TEST_GUN_ID,
		"ceremony_theme": TEST_THEME_ID,
	})
	# Keep automatic post-roster reconciliation on the same runtime-only fixture.
	# This process exits without saving or requesting anything from Supabase.
	_supabase.loadout = fixture_loadout.duplicate(true)
	if not _network.set_local_cosmetic_loadout(fixture_loadout):
		_fail("Client could not publish its persistent cosmetic IDs")
		return
	if not await _wait_until(func() -> bool:
		var cosmetics: Dictionary = _network.local_cosmetic_loadout()
		return str(cosmetics.get("hat", "")) == TEST_HAT_ID \
			and str(cosmetics.get("gun_skin", "")) == TEST_GUN_ID \
			and str(cosmetics.get("ceremony_theme", "")) == TEST_THEME_ID \
			and str(cosmetics.get("character_model", "")) == TEST_CHARACTER_MODEL_ID
	):
		_fail("Client's persistent cosmetic IDs did not reconcile")
		return
	if not await _wait_until(func() -> bool: return not _network.is_online()):
		_fail("Host did not close the validation session")
		return
	print("SUPABASE COSMETIC CLIENT OK: persistent IDs survived roster reconciliation")
	quit(0)


func _test_local_asset_mapping() -> void:
	var target := CosmeticTarget.new()
	root.add_child(target)
	SupabaseCosmeticRegistry.apply_to_player(target, {
		"character_model": TEST_CHARACTER_MODEL_ID,
		"character_skin": "purple",
		"hat": "missing_hat_art",
	})
	var stored = target.get_meta("supabase_cosmetic_loadout", {})
	if target.applied_model != "goldfish_bag_man" \
			or target.applied_skin != "purple" or not stored is Dictionary \
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
