extends Node

# Two-process headless smoke test for the current online vertical slice.
# Run through tools/run_online_smoke.ps1; this is intentionally narrower than
# human gameplay testing and exists to catch RPC/spawn regressions quickly.

const TEST_PORT := 24646
const DEFAULT_TEST_MAP := "res://node_3d.tscn"
const TIMEOUT_MSEC := 20000

var role := ""
var test_map := DEFAULT_TEST_MAP
var test_mode := "match"
const NAMED_TEST_LOBBY := "Codex Smoke Lobby"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		elif arg.begins_with("--map="):
			test_map = arg.trim_prefix("--map=")
		elif arg.begins_with("--mode="):
			test_mode = arg.trim_prefix("--mode=")
	if role not in ["host", "client"]:
		_fail("missing --role=host or --role=client")
		return
	call_deferred("_detach_and_run")

func _detach_and_run() -> void:
	# Persist across NetworkManager.start_game(), which replaces the bootstrap
	# scene with the real map under test.
	reparent(get_tree().root)
	GameConfig.rounds_per_set = 2
	GameConfig.sets_per_match = 1
	GameConfig.bot_configs = [{"difficulty": "hard", "team_id": -1}] if test_mode == "online_bots" else []
	if test_mode == "join_timeout":
		await _run_join_timeout_smoke()
		return
	if test_mode == "lobby":
		await _run_lobby_smoke()
		return
	if test_mode == "named_lobby":
		await _run_named_lobby_smoke()
		return
	if role == "host":
		if not NetworkManager.host_game(TEST_PORT):
			_fail("host_game failed")
			return
		var connected := await _wait_for(func(): return NetworkManager.peers.size() >= 2, "client connection")
		if not connected:
			return
		NetworkManager.start_game(test_map)
	else:
		if not NetworkManager.join_game("127.0.0.1", TEST_PORT):
			_fail("join_game failed")
			return

	var ready := await _wait_for(_match_is_ready, "network players/combat readiness")
	if not ready:
		return
	if test_mode == "exit_flow":
		await _run_host_exit_flow()
		return
	if test_mode == "client_exit":
		await _run_client_exit_flow()
		return
	if test_mode == "online_bots":
		await _run_online_bot_checks()
		return
	if role == "host":
		await _run_host_checks()
	else:
		await _run_client_checks()

func _run_join_timeout_smoke() -> void:
	if role != "client":
		_fail("join timeout smoke only supports the client role")
		return
	var state := {"failed": false}
	NetworkManager.connection_failed.connect(func(): state.failed = true, CONNECT_ONE_SHOT)
	if not NetworkManager.join_game("127.0.0.1", TEST_PORT + 1):
		_fail("join timeout setup failed")
		return
	if not await _wait_for(func(): return state.failed, "join failure/timeout"):
		return
	if NetworkManager.is_online():
		_fail("failed join retained an online session")
		return
	print("ONLINE_JOIN_TIMEOUT_PASS client")
	get_tree().quit()

func _run_lobby_smoke() -> void:
	if role == "host":
		if not NetworkManager.host_game(TEST_PORT):
			_fail("lobby host_game failed")
			return
		if not await _wait_for(func(): return NetworkManager.peers.size() >= 2, "lobby client connection"):
			return
	else:
		if not NetworkManager.join_game("127.0.0.1", TEST_PORT):
			_fail("lobby join_game failed")
			return
		if not await _wait_for(func():
			return NetworkManager.is_online() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		, "lobby ENet connection"):
			return
	get_tree().change_scene_to_file("res://game_setup.tscn")
	if not await _wait_for(func():
		return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://game_setup.tscn"
	, "online lobby scene"):
		return
	# Keep the real preview/UI/network roster alive long enough to catch render
	# stalls, runaway config callbacks, or disconnects after a peer arrives.
	await get_tree().create_timer(10.0).timeout
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != "res://game_setup.tscn":
		_fail("online lobby changed scenes unexpectedly")
		return
	if not NetworkManager.is_online():
		_fail("online lobby lost its ENet session")
		return
	var renamed := "Smoke Host" if role == "host" else "Smoke Client"
	NetworkManager.set_local_name(renamed)
	if not await _wait_for(func():
		for entry in NetworkManager.peers.values():
			if str(entry.get("name", "")) == renamed:
				return true
		return false
	, "online lobby name update"):
		return
	print("ONLINE_LOBBY_PASS " + role)
	if role == "host":
		await get_tree().create_timer(2.0).timeout
	get_tree().quit()

func _run_named_lobby_smoke() -> void:
	if role == "host":
		if not NetworkManager.host_game(TEST_PORT, NAMED_TEST_LOBBY):
			_fail("named lobby host_game failed")
			return
		if not await _wait_for(func(): return NetworkManager.peers.size() >= 2, "named lobby client connection"):
			return
	else:
		if not NetworkManager.join_lobby_by_name(NAMED_TEST_LOBBY):
			_fail("named lobby discovery did not start")
			return
		if not await _wait_for(func():
			return NetworkManager.is_online() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		, "named lobby ENet connection"):
			return
	if NetworkManager.lobby_name != NAMED_TEST_LOBBY:
		_fail("named lobby identity was not retained after connection")
		return
	print("ONLINE_NAMED_LOBBY_PASS " + role)
	# Keep the newly connected peer alive long enough for the host's roster
	# callback and the client's delayed name registration to complete.
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

func _run_host_exit_flow() -> void:
	if role == "host":
		NetworkManager.host_return_everyone_to_lobby()
	if not await _wait_for(func():
		return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://game_setup.tscn" and NetworkManager.is_online()
	, "host-coordinated lobby return"):
		return
	if role == "host":
		await get_tree().create_timer(0.3).timeout
		NetworkManager.leave_online_to_main_menu()
	if not await _wait_for(func():
		return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://main_menu.tscn" and not NetworkManager.is_online()
	, "host-coordinated main-menu return"):
		return
	print("ONLINE_EXIT_FLOW_PASS " + role)
	get_tree().quit()

func _run_client_exit_flow() -> void:
	if role == "client":
		NetworkManager.leave_online_to_main_menu()
		if not await _wait_for(func():
			return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://main_menu.tscn" and not NetworkManager.is_online()
		, "client-only main-menu return"):
			return
	else:
		if not await _wait_for(func():
			return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == test_map and NetworkManager.is_online() and NetworkManager.peers.size() == 1
		, "host remaining after client exit"):
			return
	print("ONLINE_CLIENT_EXIT_PASS " + role)
	get_tree().quit()

func _match_is_ready() -> bool:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != test_map:
		return false
	var net_players := scene.get_node_or_null("NetPlayers")
	var rm := scene.get_node_or_null("RoundManager")
	var expected_actors := 3 if test_mode == "online_bots" else 2
	return net_players != null and net_players.get_child_count() == expected_actors and rm != null and rm.online_combat_live

func _online_bot():
	var scene := get_tree().current_scene
	var net_players = scene.get_node_or_null("NetPlayers") if scene != null else null
	if net_players == null:
		return null
	for actor in net_players.get_children():
		if "is_bot" in actor and actor.is_bot:
			return actor
	return null

func _run_online_bot_checks() -> void:
	var bot = _online_bot()
	var rm = get_tree().current_scene.get_node_or_null("RoundManager")
	if bot == null or rm == null or int(bot.actor_id) < 10000 or bot.get_display_name() != "Bot 1":
		_fail("network bot actor metadata was not created consistently")
		return
	if bot.get_node_or_null("OnlineNameTag") == null or not rm.online_actor_state.has(int(bot.actor_id)):
		_fail("bot name tag or synchronized scoreboard state is missing")
		return
	if role == "client":
		if bot.is_multiplayer_authority():
			_fail("client incorrectly owns host bot AI")
			return
		if not await _wait_for(func(): return _online_bot() != null and _online_bot().global_position.distance_to(Vector3(123.0, 3.0, 123.0)) < 1.0, "replicated bot movement"):
			return
		if not await _wait_for(func():
			var guns := get_tree().get_nodes_in_group("gun")
			return not guns.is_empty() and (guns[0].player_ref == _online_bot() or not guns[0].can_fire)
		, "replicated bot gun combat"):
			return
		if not await _wait_for(func():
			for melee in get_tree().get_nodes_in_group("melee"):
				if bool(melee.get("online_active")) and melee.is_held and melee.player_ref == _online_bot():
					return true
			return false
		, "replicated bot melee pickup"):
			return
		if not get_tree().get_nodes_in_group("online_item").is_empty():
			if not await _wait_for(func():
				for online_item in get_tree().get_nodes_in_group("online_item"):
					if online_item.is_held and online_item.player_ref == _online_bot():
						return true
				return false
			, "replicated bot item pickup"):
				return
		print("ONLINE_BOTS_PASS client")
		get_tree().quit()
		return
	if not bot.is_multiplayer_authority():
		_fail("host does not own bot AI")
		return
	rm.countdown_time = 1
	rm.round_end_display_time = 0.2
	bot.set_physics_process(false)
	bot.global_position = Vector3(123.0, 3.0, 123.0)
	await get_tree().create_timer(0.8).timeout
	var guns := get_tree().get_nodes_in_group("gun")
	if guns.is_empty():
		_fail("bot smoke gun missing")
		return
	var gun = guns[0]
	bot.global_position = gun.global_position
	gun._server_try_pickup(int(bot.actor_id), rm.online_round_epoch)
	await get_tree().create_timer(0.25).timeout
	if not gun.is_held or gun.player_ref != bot:
		_fail("host bot could not pick up the replicated gun")
		return
	gun._server_try_fire(int(bot.actor_id), bot.get_aim_direction(), rm.online_round_epoch)
	await get_tree().create_timer(0.25).timeout
	if gun.can_fire:
		_fail("host bot could not fire an authoritative bullet")
		return
	gun._server_try_drop(int(bot.actor_id), rm.online_round_epoch)
	await get_tree().create_timer(0.2).timeout
	var melee = _active_melee()
	if melee == null:
		_fail("bot smoke melee missing")
		return
	bot.global_position = melee.global_position
	melee._server_try_pickup(int(bot.actor_id), rm.online_round_epoch)
	await get_tree().create_timer(0.2).timeout
	if not melee.is_held or melee.player_ref != bot:
		_fail("host bot could not pick up replicated melee")
		return
	melee._server_try_swing(int(bot.actor_id), rm.online_round_epoch)
	await get_tree().create_timer(0.05).timeout
	if not melee.is_swinging:
		_fail("host bot could not start an authoritative melee swing")
		return
	var items := get_tree().get_nodes_in_group("online_item")
	if not items.is_empty():
		var item = items[0]
		bot.global_position = item.global_position
		item._server_try_pickup(int(bot.actor_id), rm.online_round_epoch)
		await get_tree().create_timer(0.2).timeout
		if not item.is_held or item.player_ref != bot:
			_fail("host bot could not pick up a replicated item")
			return
	var first_epoch: int = rm.online_round_epoch
	var human_actor_ids: Array = []
	for state_actor_id in rm.online_actor_state:
		if int(state_actor_id) != int(bot.actor_id):
			human_actor_ids.append(int(state_actor_id))
	for human_actor_id in human_actor_ids:
		if rm.online_actor_state.has(human_actor_id):
			rm.server_eliminate(human_actor_id, int(bot.actor_id), rm.online_round_epoch)
	if not await _wait_for(func(): return is_instance_valid(rm) and rm.online_round_epoch > first_epoch and not bot.is_eliminated, "bot round win/reset"):
		return
	var bot_state: Dictionary = rm.online_actor_state.get(int(bot.actor_id), {})
	if int(bot_state.get("rounds", 0)) != 1 or int(bot_state.get("kills", 0)) < 1:
		_fail("bot round win was not included in synchronized scoring")
		return
	print("ONLINE_BOTS_PASS host")
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()

func _active_melee():
	for melee in get_tree().get_nodes_in_group("melee"):
		if bool(melee.get("online_active")):
			return melee
	return null

func _run_host_checks() -> void:
	var scene := get_tree().current_scene
	var rm = scene.get_node("RoundManager")
	rm.countdown_time = 1
	rm.round_end_display_time = 0.4
	rm.set_end_display_time = 0.4
	rm.match_end_display_time = 0.6
	var host_player = NetworkManager.find_net_player(1)
	var client_ids := NetworkManager.peer_ids_sorted().filter(func(id): return int(id) != 1)
	var guns := get_tree().get_nodes_in_group("gun")
	var melee = _active_melee()
	if host_player == null or guns.is_empty() or melee == null or client_ids.is_empty():
		_fail("host player, client actor, gun or melee weapon missing")
		return
	var gun = guns[0]
	var victim = NetworkManager.find_net_player(int(client_ids[0]))
	if not await _verify_online_pause_menu(true):
		return
	# The server copy of a client-owned actor must keep ticking authoritative
	# bullet immunity; otherwise a normal short post-melee window lasts forever.
	victim.bullet_immune_timer = 0.1
	await get_tree().create_timer(0.2).timeout
	if victim.is_bullet_immune():
		_fail("client-owned bullet immunity did not expire on the host")
		return
	victim.melee_disarm_shields = 1
	if victim.is_bullet_immune():
		_fail("disarm shield incorrectly granted bullet immunity")
		return
	# A bullet must pass straight through the melee-only shield. Give the victim
	# Second Wind solely as a non-destructive witness that the authoritative
	# bullet reached the elimination path; the melee shield must remain intact.
	victim.second_wind_ready = true
	var shield_test_bullet = preload("res://bullet.tscn").instantiate()
	shield_test_bullet.is_server_bullet = true
	shield_test_bullet.net_shooter_id = int(host_player.actor_id)
	shield_test_bullet.net_round_epoch = rm.online_round_epoch
	scene.add_child(shield_test_bullet)
	shield_test_bullet._on_hit_online(victim)
	await get_tree().create_timer(0.1).timeout
	if victim.second_wind_ready or victim.melee_disarm_shields != 1 or victim.is_eliminated:
		_fail("bullet did not bypass the melee-only disarm shield")
		return
	victim.bullet_immune_timer = 0.0
	victim.melee_disarm_shields = 0
	var hud = scene.get_node_or_null("OnlineHUD")
	if hud == null or hud.player != host_player:
		_fail("online HUD did not bind to the host player")
		return
	var melee_weapons := get_tree().get_nodes_in_group("melee")
	var melee_ids: Dictionary = {}
	for authored_melee in melee_weapons:
		if not bool(authored_melee.get("online_active")) or authored_melee.get("weapon_data") == null:
			_fail("an authored melee placement was not activated and rolled online")
			return
		var candidate_id := int(authored_melee.get("online_candidate_id"))
		if melee_ids.has(candidate_id):
			_fail("online melee candidate IDs were not unique")
			return
		melee_ids[candidate_id] = true
	if not get_tree().get_nodes_in_group("online_item").is_empty():
		if not await _run_host_item_powerup_checks(rm, host_player, victim):
			return
	# Phase 2c: host-authoritative melee pickup, swing, and gun disarm.
	host_player.global_position = melee.global_position + Vector3(10.0, 0.0, 0.0)
	melee._server_try_pickup(1, rm.online_round_epoch)
	if melee.is_held:
		_fail("out-of-range melee pickup was accepted")
		return
	host_player.global_position = melee.global_position
	for i in 5:
		await get_tree().process_frame
	melee._server_try_pickup(1, rm.online_round_epoch)
	await get_tree().create_timer(0.8).timeout
	if not melee.is_held or melee.player_ref != host_player:
		_fail("authoritative melee pickup did not replicate locally")
		return
	victim.global_position = gun.global_position
	gun._server_try_pickup(int(client_ids[0]), rm.online_round_epoch)
	# Rendered clients may still be compiling newly introduced item shaders.
	# Leave the client-owned gun visible for long enough that its observation
	# loop can see both the held state and the subsequent disarm transition.
	await get_tree().create_timer(0.8).timeout
	if not gun.is_held or gun.player_ref != victim:
		_fail("melee smoke setup could not give the client the gun")
		return
	host_player.global_position = victim.global_position + Vector3(1.0, 0.0, 0.0)
	melee._server_try_swing(int(client_ids[0]), rm.online_round_epoch)
	melee._server_try_swing(1, rm.online_round_epoch + 1)
	if melee.is_swinging:
		_fail("wrong-owner or stale-round melee swing was accepted")
		return
	melee._server_try_swing(1, rm.online_round_epoch)
	await get_tree().create_timer(0.05).timeout
	if not melee.is_swinging:
		_fail("authoritative melee swing did not replicate")
		return
	melee._server_resolve_hit(victim, false)
	await get_tree().create_timer(0.6).timeout
	var melee_score: Dictionary = rm.online_actor_state.get(host_player.actor_id, {})
	if gun.is_held or int(melee_score.get("disarms", 0)) < 1 or int(melee_score.get("melee", 0)) < 1:
		_fail("authoritative melee hit/disarm or stats did not replicate")
		return
	var swing_finished := await _wait_for(func(): return not melee.is_swinging, "melee swing recovery")
	if not swing_finished:
		return
	melee._server_try_throw(1, rm.online_round_epoch)
	await get_tree().process_frame
	if melee.is_held:
		_fail("authoritative melee throw did not release the weapon")
		return
	await get_tree().create_timer(0.1).timeout
	rm.broadcast_online_melee_action(int(melee.online_candidate_id), "land", {"position": melee.global_position, "rotation": melee.global_rotation})
	await get_tree().create_timer(0.1).timeout
	if melee.is_in_flight:
		_fail("authoritative melee landing did not replicate")
		return
	host_player.global_position = gun.global_position + Vector3(10.0, 0.0, 0.0)
	for i in 3:
		await get_tree().process_frame
	gun._server_try_pickup(1, rm.online_round_epoch)
	if gun.is_held:
		_fail("out-of-range pickup was accepted")
		return
	host_player.global_position = gun.global_position
	for i in 5:
		await get_tree().process_frame
	gun._server_try_pickup(1, rm.online_round_epoch)
	await get_tree().create_timer(0.35).timeout
	if not gun.is_held or gun.player_ref != host_player:
		_fail("authoritative pickup did not replicate locally")
		return
	host_player.get_node("AimPivot/SpringArm3D").rotation.x = -1.2
	victim.grant_bullet_immunity(5.0)
	var smoke_shot_direction: Vector3 = host_player.get_aim_direction()
	gun._server_try_fire(int(client_ids[0]), smoke_shot_direction, rm.online_round_epoch)
	gun._server_try_fire(1, smoke_shot_direction, rm.online_round_epoch + 1)
	if not gun.can_fire:
		_fail("wrong-owner or stale-round fire request was accepted")
		return
	# Exercise the replicated bullet/reload event at a guaranteed-empty test
	# origin. Actual player-origin firing is covered by the ownership validation
	# above and the human gameplay test; this avoids scoring an accidental hit.
	gun._net_spawn_bullet.rpc(Vector3(0.0, 10000.0, 0.0), Vector3.UP, host_player.actor_id, rm.online_round_epoch)
	await get_tree().create_timer(0.05).timeout
	for bullet in get_tree().get_nodes_in_group("online_bullet"):
		bullet.collision_mask = 0
		bullet.contact_monitor = false
		bullet.queue_free()
	await get_tree().create_timer(0.2).timeout
	if gun.can_fire:
		_fail("host reload did not start")
		return
	await get_tree().create_timer(2.1).timeout
	if not gun.can_fire:
		_fail("host reload completion did not arrive")
		return
	var first_epoch: int = int(rm.online_round_epoch)
	if victim != null and not victim.is_eliminated:
		rm.server_eliminate(victim.actor_id, host_player.actor_id, rm.online_round_epoch)
	var elimination_recorded := await _wait_for(func():
		var entry: Dictionary = rm.online_actor_state.get(victim.actor_id, {})
		return int(entry.get("deaths", 0)) >= 1
	, "first authoritative elimination")
	if not elimination_recorded:
		return
	var next_round := await _wait_for(func():
		return is_instance_valid(rm) and rm.online_combat_live and rm.online_round_epoch > first_epoch
	, "second scored round")
	if not next_round:
		return
	host_player = NetworkManager.find_net_player(1)
	victim = NetworkManager.find_net_player(int(client_ids[0]))
	gun = get_tree().get_nodes_in_group("gun")[0]
	var host_score: Dictionary = rm.online_actor_state.get(host_player.actor_id, {})
	if int(host_score.get("rounds", -1)) != 1 or not bool(host_score.get("alive", false)):
		_fail("round score or respawn state did not synchronize")
		return
	melee = _active_melee()
	if gun.is_held or melee.is_held or not gun.can_fire or victim == null or victim.is_eliminated:
		_fail("round reset did not restore gun, melee weapon, and players")
		return
	# Finish the match through the optional melee-eliminates-anyone rule so the
	# melee elimination/icon path is covered as well as the default disarm path.
	GameConfig.melee_eliminates_anyone = true
	host_player.global_position = melee.global_position
	melee._server_try_pickup(1, rm.online_round_epoch)
	await get_tree().create_timer(0.2).timeout
	host_player.global_position = victim.global_position + Vector3(1.0, 0.0, 0.0)
	melee._server_try_swing(1, rm.online_round_epoch)
	await get_tree().create_timer(0.05).timeout
	melee._server_resolve_hit(victim, false)
	var match_finished := await _wait_for(func(): return is_instance_valid(rm) and rm.online_match_over, "match winner")
	if not match_finished:
		return
	host_score = rm.online_actor_state.get(host_player.actor_id, {})
	if int(host_score.get("sets", -1)) != 1 or int(host_score.get("kills", -1)) < 2:
		_fail("set/match score did not synchronize")
		return
	var lobby_returned := await _wait_for(func():
		return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://game_setup.tscn"
	, "coordinated lobby return")
	if not lobby_returned:
		return
	print("ONLINE_SMOKE_PASS host")
	# Rendered scene transitions can spend a couple seconds compiling/freeing
	# map shaders. Keep the host alive long enough for the client to finish its
	# coordinated lobby transition before the server socket disappears.
	await get_tree().create_timer(4.0).timeout
	get_tree().quit()

func _run_host_item_powerup_checks(rm, host_player, victim) -> bool:
	var items := get_tree().get_nodes_in_group("online_item")
	var powerups := get_tree().get_nodes_in_group("online_powerup")
	if items.is_empty() or powerups.is_empty():
		_fail("Phase 2d marker pickups did not spawn")
		return false
	var original = items[0]
	var test_item_id := int(original.online_item_id)
	var test_spawn_id := int(original.online_spawn_id)
	var test_spawn_position: Vector3 = original.spawn_position
	var test_spawn_rotation: Vector3 = original.spawn_rotation
	rm._net_replace_online_item.rpc(test_item_id, "smoke_bomb", test_spawn_position, test_spawn_rotation, test_spawn_id)
	rm._net_respawn_online_powerup.rpc(int(powerups[0].online_powerup_id), "second_wind")
	await get_tree().create_timer(0.2).timeout
	var item = rm._online_item(test_item_id)
	var powerup = rm._online_powerup(int(powerups[0].online_powerup_id))
	if item == null or powerup == null:
		_fail("Phase 2d deterministic test pickup replacement failed")
		return false
	host_player.global_position = item.global_position + Vector3(10.0, 0.0, 0.0)
	item._server_try_pickup(1, rm.online_round_epoch)
	if item.is_held:
		_fail("out-of-range online item pickup was accepted")
		return false
	host_player.global_position = item.global_position
	item._server_try_pickup(1, rm.online_round_epoch)
	await get_tree().create_timer(0.2).timeout
	if not item.is_held or item.player_ref != host_player:
		_fail("authoritative online item pickup did not replicate")
		return false
	item._server_try_throw(1, rm.online_round_epoch, host_player.get_aim_direction())
	await get_tree().create_timer(0.15).timeout
	if not item.is_in_flight:
		_fail("authoritative online item throw did not start")
		return false
	if not await _wait_for(func(): return not get_tree().get_nodes_in_group("online_deployed").is_empty(), "replicated item deployment"):
		return false
	victim.global_position = powerup.global_position
	rm.server_collect_online_powerup(int(powerup.online_powerup_id), int(victim.actor_id), rm.online_round_epoch)
	await get_tree().create_timer(0.2).timeout
	if not powerup.collected or not victim.second_wind_ready:
		_fail("authoritative powerup collection/effect did not apply")
		return false
	rm.server_eliminate(int(victim.actor_id), int(host_player.actor_id), rm.online_round_epoch)
	await get_tree().create_timer(0.2).timeout
	if victim.is_eliminated or not bool(rm.online_actor_state[int(victim.actor_id)].get("alive", false)) or victim.second_wind_ready:
		_fail("Second Wind did not authoritatively prevent elimination")
		return false
	rm._net_replace_online_item.rpc(test_item_id, "boomerang", test_spawn_position, test_spawn_rotation, test_spawn_id)
	await get_tree().create_timer(0.2).timeout
	item = rm._online_item(test_item_id)
	host_player.global_position = item.global_position
	item._server_try_pickup(1, rm.online_round_epoch)
	await get_tree().create_timer(0.15).timeout
	item._server_try_throw(1, rm.online_round_epoch, host_player.get_aim_direction())
	await get_tree().create_timer(0.15).timeout
	if not item.is_in_flight:
		_fail("online boomerang throw did not start")
		return false
	rm.server_online_boomerang_hit(test_item_id, int(host_player.actor_id), int(victim.actor_id), rm.online_round_epoch)
	await get_tree().create_timer(0.2).timeout
	if item.visible or item.is_in_flight or victim.knockback_timer <= 0.0:
		_fail("online boomerang hit/effect/consume did not replicate")
		return false
	var loose_items := get_tree().get_nodes_in_group("online_item").filter(func(candidate): return int(candidate.online_item_id) != test_item_id and candidate.visible and not candidate.is_held)
	if not loose_items.is_empty():
		rm._net_respawn_online_powerup.rpc(int(powerup.online_powerup_id), "magnet_hands")
		await get_tree().create_timer(0.15).timeout
		host_player.global_position = powerup.global_position
		rm.server_collect_online_powerup(int(powerup.online_powerup_id), int(host_player.actor_id), rm.online_round_epoch)
		await get_tree().create_timer(0.15).timeout
		var loose_item = loose_items[0]
		var magnet_start: Vector3 = host_player.global_position + Vector3(3.0, 0.0, 0.0)
		rm.broadcast_online_item_action(int(loose_item.online_item_id), "move", {"position": magnet_start})
		var before_distance: float = loose_item.global_position.distance_to(host_player.global_position)
		rm._server_online_magnet_pull(1, int(host_player.actor_id))
		await get_tree().process_frame
		if host_player.magnet_timer <= 0.0 or loose_item.global_position.distance_to(host_player.global_position) >= before_distance:
			_fail("Magnet Hands did not move a loose item host-authoritatively")
			return false
	return true

func _run_client_checks() -> void:
	if not await _verify_online_pause_menu(false):
		return
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	var saw_pickup := false
	var saw_reload := false
	var saw_melee_pickup := false
	var saw_gun_disarm := false
	var local_had_gun := false
	var saw_first_death := false
	var saw_round_reset := false
	var first_epoch := -1
	var expects_phase2d := not get_tree().get_nodes_in_group("online_item").is_empty()
	var saw_item_pickup := false
	var saw_item_throw := false
	var saw_deployed_item := false
	var saw_powerup_collect := false
	var saw_second_wind_survival := false
	while Time.get_ticks_msec() < deadline:
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path == "res://game_setup.tscn":
			if not saw_pickup or not saw_reload or not saw_melee_pickup or not saw_gun_disarm or not saw_first_death or not saw_round_reset or (expects_phase2d and (not saw_item_pickup or not saw_item_throw or not saw_deployed_item or not saw_powerup_collect or not saw_second_wind_survival)):
				_fail("client missed state: gun_pickup=%s reload=%s melee_pickup=%s disarm=%s death=%s reset=%s item_pickup=%s item_throw=%s deployed=%s powerup=%s second_wind=%s" % [saw_pickup, saw_reload, saw_melee_pickup, saw_gun_disarm, saw_first_death, saw_round_reset, saw_item_pickup, saw_item_throw, saw_deployed_item, saw_powerup_collect, saw_second_wind_survival])
				return
			print("ONLINE_SMOKE_PASS client")
			get_tree().quit()
			return
		var guns := get_tree().get_nodes_in_group("gun")
		if not guns.is_empty():
			saw_pickup = saw_pickup or guns[0].is_held
			saw_reload = saw_reload or not guns[0].can_fire
			var local_player_for_gun = NetworkManager.find_net_player(NetworkManager.local_id())
			if guns[0].is_held and guns[0].player_ref == local_player_for_gun:
				local_had_gun = true
			elif local_had_gun and not guns[0].is_held:
				saw_gun_disarm = true
		var melee_weapons := get_tree().get_nodes_in_group("melee")
		for melee in melee_weapons:
			if bool(melee.get("online_active")) and melee.is_held:
				saw_melee_pickup = saw_melee_pickup or melee.is_held
				break
		if expects_phase2d:
			for online_item in get_tree().get_nodes_in_group("online_item"):
				saw_item_pickup = saw_item_pickup or online_item.is_held
				saw_item_throw = saw_item_throw or online_item.is_in_flight
			saw_deployed_item = saw_deployed_item or not get_tree().get_nodes_in_group("online_deployed").is_empty()
			for online_powerup in get_tree().get_nodes_in_group("online_powerup"):
				saw_powerup_collect = saw_powerup_collect or online_powerup.collected
		var local_player = NetworkManager.find_net_player(NetworkManager.local_id())
		if local_player != null:
			saw_second_wind_survival = saw_second_wind_survival or local_player.bullet_immune_timer > 1.0
		if local_player != null and scene != null and scene.scene_file_path == test_map:
			var hud = scene.get_node_or_null("OnlineHUD")
			if hud == null or hud.player != local_player:
				_fail("online HUD did not bind to the client player")
				return
		if local_player != null and local_player.is_eliminated:
			if not saw_first_death:
				saw_first_death = true
				var rm = get_tree().current_scene.get_node_or_null("RoundManager")
				first_epoch = rm.online_round_epoch if rm != null else -1
		elif saw_first_death and local_player != null:
			var rm = get_tree().current_scene.get_node_or_null("RoundManager")
			if rm != null and rm.online_round_epoch > first_epoch and local_player.is_eliminated == false:
				saw_round_reset = true
		await get_tree().process_frame
	_fail("client match completion")

func _verify_online_pause_menu(expect_return_to_lobby: bool) -> bool:
	var scene := get_tree().current_scene
	var pause_menu = scene.get_node_or_null("OnlineHUD/PauseMenu") if scene != null else null
	if pause_menu == null:
		_fail("online pause menu was not created")
		return false
	var found_return_to_lobby := _has_button_text(pause_menu, "Return to Lobby")
	if found_return_to_lobby != expect_return_to_lobby:
		_fail("online pause lobby ownership controls were incorrect")
		return false
	PauseManager.pause()
	await get_tree().process_frame
	if not pause_menu.visible or get_tree().paused:
		_fail("online pause did not remain a local, unpaused overlay")
		return false
	PauseManager.resume()
	return true

func _has_button_text(node: Node, button_text: String) -> bool:
	if node is Button and node.text == button_text:
		return true
	for child in node.get_children():
		if _has_button_text(child, button_text):
			return true
	return false

func _wait_for(predicate: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	_fail("timeout waiting for " + label)
	return false

func _fail(message: String) -> void:
	push_error("ONLINE_SMOKE_FAIL %s: %s" % [role, message])
	get_tree().quit(1)
