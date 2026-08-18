extends Node

# Two-process headless smoke test for the current online vertical slice.
# Run through tools/run_online_smoke.ps1; this is intentionally narrower than
# human gameplay testing and exists to catch RPC/spawn regressions quickly.

const TEST_PORT := 24646
const DEFAULT_TEST_MAP := "res://node_3d.tscn"
const TIMEOUT_MSEC := 60000

var role := ""
var test_map := DEFAULT_TEST_MAP
var test_mode := "match"
var _lobby_client_complete := false
var _late_spectator_complete := false
const NAMED_TEST_LOBBY := "Codex Smoke Lobby"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		elif arg.begins_with("--map="):
			test_map = arg.trim_prefix("--map=")
		elif arg.begins_with("--mode="):
			test_mode = arg.trim_prefix("--mode=")
	if role not in ["host", "client", "spectator"]:
		_fail("missing --role=host, --role=client, or --role=spectator")
		return
	call_deferred("_detach_and_run")

func _detach_and_run() -> void:
	# Persist across NetworkManager.start_game(), which replaces the bootstrap
	# scene with the real map under test.
	reparent(get_tree().root)
	GameConfig.rounds_per_set = 2
	GameConfig.sets_per_match = 1
	GameConfig.bot_configs = [{"difficulty": "hard", "team_id": -1}] if test_mode == "online_bots" else []
	if test_mode == "one_of_us":
		GameConfig.game_mode = GameConfig.MODE_ONE_OF_US
	if test_mode == "overtime":
		GameConfig.round_time_limit = 0.25
		GameConfig.chaos_overtime_enabled = false
	if test_mode == "join_timeout":
		await _run_join_timeout_smoke()
		return
	if test_mode == "lobby":
		await _run_lobby_smoke()
		return
	if test_mode == "named_lobby":
		await _run_named_lobby_smoke()
		return
	if test_mode == "late_spectator":
		await _run_late_spectator_smoke()
		return
	if test_mode == "playpen" and role == "client":
		await _run_playpen_smoke()
		return
	if role == "host":
		if test_mode == "playpen":
			await _run_playpen_smoke()
			return
		if not NetworkManager.host_game(TEST_PORT):
			_fail("host_game failed")
			return
		var connected := await _wait_for(func(): return NetworkManager.peers.size() >= 2, "client connection")
		if not connected:
			return
		if test_mode == "one_of_us":
			var preference_received := await _wait_for(func():
				return NetworkManager._one_of_us_volunteers.values().any(
					func(value): return value == true)
			, "private One of Us volunteer preference")
			if not preference_received:
				return
		NetworkManager.start_game(test_map)
	else:
		if not NetworkManager.join_game("127.0.0.1", TEST_PORT):
			_fail("join_game failed")
			return
		if test_mode == "one_of_us":
			if not await _wait_for(func(): return NetworkManager.peers.size() >= 2,
					"One of Us lobby roster"):
				return
			NetworkManager.set_one_of_us_volunteer(true)

	if test_mode == "one_of_us":
		await _run_online_one_of_us_checks()
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
	if test_mode == "overtime":
		await _run_online_overtime_checks()
		return
	if role == "host":
		await _run_host_checks()
	else:
		await _run_client_checks()


func _run_online_one_of_us_checks() -> void:
	if not await _wait_for(func():
		var scene := get_tree().current_scene
		if scene == null or scene.scene_file_path != test_map:
			return false
		var net_players := scene.get_node_or_null("NetPlayers")
		var manager := scene.get_node_or_null("RoundManager")
		var local_actor = NetworkManager.find_net_player(NetworkManager.local_id())
		return net_players != null and net_players.get_child_count() == 2 \
			and manager != null and manager.one_of_us_roles.size() == 2 \
			and local_actor != null and local_actor.get_node_or_null("OneOfUsIntro") != null
	, "One of Us synchronized role cinematic"):
		return
	var scene := get_tree().current_scene
	var manager = scene.get_node("RoundManager")
	var local_actor = NetworkManager.find_net_player(NetworkManager.local_id())
	var intro = local_actor.get_node("OneOfUsIntro")
	var expected_role := "them" if int(local_actor.actor_id) == manager.one_of_us_first_actor_id else "us"
	var volunteer_peer_id := -1
	for peer_id_value in NetworkManager.peers:
		if int(peer_id_value) != 1:
			volunteer_peer_id = int(peer_id_value)
			break
	var volunteer_actor_id := NetworkManager.actor_id_for_peer(volunteer_peer_id)
	if manager.one_of_us_first_actor_id != volunteer_actor_id:
		_fail("server did not select the sole private volunteer as first infected")
		return
	for peer_data in NetworkManager.peers.values():
		if (peer_data as Dictionary).has("one_of_us_volunteer"):
			_fail("private volunteer intent leaked into the synchronized roster")
			return
	if str(local_actor.one_of_us_role) != expected_role:
		_fail("local One of Us cinematic role did not match the server selection")
	var cinematic_target = intro.get("_infected_actor")
	if cinematic_target == null \
			or int(cinematic_target.get("actor_id")) != manager.one_of_us_first_actor_id \
			or intro.get("_camera") == null:
		_fail("network cinematic did not target the server-selected first infected")
		return

	if not bool(local_actor.get("_one_of_us_intro_input_locked")) or local_actor.is_physics_processing():
		_fail("One of Us did not lock local controls during the network cinematic")
		return
	await get_tree().create_timer(5.55).timeout
	var label = intro.get("_text") if is_instance_valid(intro) else null
	var expected_text := "YOU ARE THE FIRST." if expected_role == "them" else "ONE OF THEM HAS TURNED."
	if label == null or label.text != expected_text:
		_fail("network role cinematic showed the wrong local-role message")
		return
	if not await _wait_for(func():
		return manager.online_combat_live \
			and not bool(local_actor.get("_one_of_us_intro_input_locked")) \
			and local_actor.is_physics_processing()
	, "One of Us cinematic completion and local control restoration"):
		return
	var them_count := 0
	var us_count := 0
	for actor in scene.get_node("NetPlayers").get_children():
		var actor_role := str(actor.get("one_of_us_role"))
		if actor_role == "them":
			them_count += 1
			if int(actor.get("max_dash_charges")) != GameConfig.ONE_OF_US_THEM_DASH_CHARGES:
				_fail("network Them player did not receive four base dashes")
				return
			var melee = actor.get("held_melee_weapon")
			if melee == null or melee.weapon_data == null \
					or melee.weapon_data.weapon_name != "Frying Pan":
				_fail("network Them player did not receive the Frying Pan")
				return
		else:
			us_count += 1
			if int(actor.get("max_dash_charges")) != GameConfig.ONE_OF_US_US_DASH_CHARGES:
				_fail("network Us player did not receive three base dashes")
				return
			if not bool(actor.get("holding_gun")):
				_fail("network Us player did not receive a personal gun")
				return
	if them_count != 1 or us_count != 1:
		_fail("server did not synchronize exactly one first infected")
		return
	print("ONLINE_ONE_OF_US_PASS " + role)
	await get_tree().create_timer(0.75).timeout
	get_tree().quit()


func _run_playpen_smoke() -> void:
	if role == "host":
		if not NetworkManager.host_game(TEST_PORT):
			_fail("Playpen host setup failed")
			return
		NetworkManager.pending_map_path = test_map
		if not await _wait_for(func(): return NetworkManager.peers.size() >= 2,
				"Playpen client connection"):
			return
		if not await _wait_for(func():
			return (
				NetworkManager.local_match_role == "playpen_hosting"
				and get_tree().current_scene != null
				and get_tree().current_scene.scene_file_path == "res://maps/playpen/playpen.tscn"
			)
		, "guest opening The Playpen without host entry"):
			return
		NetworkManager.request_enter_playpen()
	else:
		if not NetworkManager.join_game("127.0.0.1", TEST_PORT):
			_fail("Playpen client setup failed")
			return
		if not await _wait_for(func():
			return (
				NetworkManager.local_id() != 1
				and NetworkManager.peers.has(NetworkManager.local_id())
			)
		, "Playpen client lobby admission"):
			return
		NetworkManager.request_enter_playpen()
	if not await _wait_for(func():
		var scene := get_tree().current_scene
		var net_players := scene.get_node_or_null("NetPlayers") if scene != null else null
		return scene != null and scene.scene_file_path == "res://maps/playpen/playpen.tscn" \
			and NetworkManager.local_match_role == "playpen" \
			and NetworkManager.playpen_peer_ids().size() == 2 \
			and net_players != null and net_players.get_child_count() == 2
	, "two-peer Playpen readiness"):
		return
	var guns := get_tree().get_nodes_in_group("gun").filter(func(gun):
		return int(gun.get("playpen_spawn_id")) >= 0)
	if guns.size() != 6:
		_fail("The Playpen did not replicate two guns in each armory bay")
		return
	for actor in get_tree().current_scene.get_node("NetPlayers").get_children():
		if "is_bot" in actor and actor.is_bot:
			_fail("The Playpen spawned a bot")
			return
	var net_players := get_tree().current_scene.get_node("NetPlayers")
	var local_actor = net_players.get_node_or_null("NP%d" % NetworkManager.local_actor_id())
	var remote_actor = null
	for candidate in net_players.get_children():
		if candidate != local_actor:
			remote_actor = candidate
			break
	if local_actor == null or remote_actor == null:
		_fail("Playpen replication validation could not find both actors")
		return
	var remote_start: Vector3 = remote_actor.global_position
	if role == "client":
		await get_tree().create_timer(0.5).timeout
		for _movement_frame in 30:
			local_actor.global_position.x += 0.1
			await get_tree().physics_frame
		if not await _wait_for(func():
			return remote_actor.global_position.distance_to(remote_start) > 1.0
		, "host movement replication after Playpen membership refresh"):
			return
	else:
		if not await _wait_for(func():
			return remote_actor.global_position.distance_to(remote_start) > 1.0
		, "guest movement replication after guest-first Playpen entry"):
			return
		for _movement_frame in 30:
			local_actor.global_position.z += 0.1
			await get_tree().physics_frame

	if role == "client":
		await get_tree().create_timer(0.5).timeout
		NetworkManager.request_leave_playpen()
		if not await _wait_for(func():
			return get_tree().current_scene != null \
				and get_tree().current_scene.scene_file_path == "res://game_setup.tscn" \
				and NetworkManager.local_match_role == "lobby"
		, "independent Playpen guest exit"):
			return
		var guest_lobby = get_tree().current_scene
		for property_name in ["_match_settings_button",
				"_character_customization_button", "_player_settings_button",
				"_playpen_button", "_back_button"]:
			var lobby_button = guest_lobby.get(property_name)
			if not lobby_button is BaseButton or lobby_button.disabled:
				_fail("guest lobby button stayed disabled after leaving Playpen: %s" \
					% property_name)
				return
		var settings_button = guest_lobby.get("_match_settings_button")
		settings_button.emit_signal("pressed")
		await get_tree().process_frame
		if guest_lobby.get("_settings_slideout") == null:
			_fail("guest lobby Settings click did nothing after leaving Playpen")
			return
		guest_lobby.call("_discard_settings_slideout_immediately")
		await get_tree().process_frame
		var playpen_button = guest_lobby.get("_playpen_button")
		var local_peer_id := NetworkManager.local_id()
		var ready_before_entry := bool(
			NetworkManager.peers[local_peer_id].get("ready", false))
		playpen_button.emit_signal("pressed")
		var entry_dialogs: Array[Node] = guest_lobby.find_children(
			"*", "ConfirmationDialog", true, false)
		if entry_dialogs.any(func(dialog): return dialog.visible):
			_fail("guest lobby Playpen click still opened a Ready prompt")
			return
		if (bool(NetworkManager.peers[local_peer_id].get("ready", false))
				!= ready_before_entry):
			_fail("guest Playpen entry changed the lobby Ready state")
			return
		if not await _wait_for(func():
			return (
				NetworkManager.local_match_role == "playpen"
				and get_tree().current_scene != null
				and get_tree().current_scene.scene_file_path == "res://maps/playpen/playpen.tscn"
			)
		, "guest free re-entry into The Playpen"):
			return
		NetworkManager.request_leave_playpen()
		if not await _wait_for(func():
			return (
				get_tree().current_scene != null
				and get_tree().current_scene.scene_file_path == "res://game_setup.tscn"
				and NetworkManager.local_match_role == "lobby"
			)
		, "guest completing its second independent Playpen exit"):
			return
		_lobby_test_client_complete.rpc_id(1)
		print("ONLINE_PLAYPEN_PASS client")
		await get_tree().create_timer(0.5).timeout
		NetworkManager.disconnect_net()
		await get_tree().create_timer(0.25).timeout
		get_tree().quit()
		return
	if not await _wait_for(func():
		for peer_id_value in NetworkManager.peers:
			var peer_id := int(peer_id_value)
			if peer_id != 1 and str(NetworkManager.peers[peer_id].get("role", "")) == "lobby":
				var remaining_net_players := get_tree().current_scene.get_node_or_null("NetPlayers")
				return remaining_net_players != null and remaining_net_players.get_child_count() == 1
		return false
	, "host retaining The Playpen after guest exit"):
		return
	if not await _wait_for(func(): return _lobby_client_complete,
			"client returned-lobby button verification"):
		return
	await get_tree().create_timer(0.75).timeout
	print("ONLINE_PLAYPEN_PASS host")
	NetworkManager.disconnect_net()
	await get_tree().create_timer(0.25).timeout
	get_tree().quit()
func _run_late_spectator_smoke() -> void:
	if role == "host":
		if not NetworkManager.host_game(TEST_PORT):
			_fail("late-spectator host setup")
			return
		if not await _wait_for(func(): return NetworkManager.peers.size() >= 2, "initial match client"):
			return
		NetworkManager.start_game(test_map)
		if not await _wait_for(_match_is_ready, "initial late-spectator match readiness"):
			return
		if not await _wait_for(func():
			for entry in NetworkManager.peers.values():
				if str(entry.get("role", "")) == "spectator":
					return true
			return false
		, "late spectator role"):
			return
		print("ONLINE_LATE_SPECTATOR_PASS host")
		if not await _wait_for(func(): return _late_spectator_complete, "late spectator full verification"):
			return
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
		return
	if role == "client":
		if not NetworkManager.join_game("127.0.0.1", TEST_PORT):
			_fail("late-spectator initial client join")
			return
		if not await _wait_for(_match_is_ready, "late-spectator initial client readiness"):
			return
		if not await _wait_for(func():
			for entry in NetworkManager.peers.values():
				if str(entry.get("role", "")) == "spectator":
					return true
			return false
		, "late spectator roster replication"):
			return
		print("ONLINE_LATE_SPECTATOR_PASS client")
		if not await _wait_for(func(): return _late_spectator_complete, "late spectator client completion"):
			return
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
		return

	if not NetworkManager.join_game("127.0.0.1", TEST_PORT):
		_fail("late spectator join")
		return
	if not await _wait_for(func():
		return NetworkManager.peers.has(NetworkManager.local_id()) \
			and NetworkManager.lobby_in_progress \
			and NetworkManager.local_match_role == "waiting"
	, "late spectator waiting-room admission"):
		return
	get_tree().change_scene_to_file("res://game_setup.tscn")
	if not await _wait_for(func(): return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://game_setup.tscn", "late spectator waiting room"):
		return
	# Give the waiting-room scene one complete frame to finish its ready-time UI
	# wiring before sending the autoload RPC that changes scenes again.
	await get_tree().process_frame
	NetworkManager.request_spectate_current_match()
	if not await _wait_for(func():
		return get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path == test_map \
			and NetworkManager.local_match_role == "spectator"
	, "late spectator map entry"):
		return
	if not await _wait_for(func():
		var scene := get_tree().current_scene
		var net_players := scene.get_node_or_null("NetPlayers") if scene != null else null
		var manager := scene.get_node_or_null("RoundManager") if scene != null else null
		return net_players != null and net_players.get_child_count() >= 2 \
			and scene.get_node_or_null("LateSpectatorController") != null \
			and manager != null and manager.online_actor_state.size() >= 2
	, "late spectator replicated actors and camera"):
		return
	print("ONLINE_LATE_SPECTATOR_PASS spectator")
	_late_spectator_test_complete_request.rpc_id(1)
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()


@rpc("any_peer", "reliable")
func _late_spectator_test_complete_request() -> void:
	if not multiplayer.is_server():
		return
	_late_spectator_complete = true
	_late_spectator_test_complete_state.rpc()


@rpc("authority", "call_local", "reliable")
func _late_spectator_test_complete_state() -> void:
	_late_spectator_complete = true

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
	if not await _wait_for(func(): return NetworkManager.peers.size() >= 2, "accepted compatibility roster"):
		return
	# Exchange the names before the extended live-UI soak. A cold headless map
	# preview can render much more slowly than the other peer, and the soak is
	# meant to observe that condition rather than make the faster peer abandon it.
	var renamed := "Smoke Host" if role == "host" else "Smoke Client"
	NetworkManager.set_local_name(renamed)
	if not await _wait_for(func():
		for entry in NetworkManager.peers.values():
			if str(entry.get("name", "")) == renamed:
				return true
		return false
	, "online lobby name update"):
		return
	# Character portraits are derived locally from the synchronized skin ID.
	# Give each peer a distinct confirmed color, then prove both clients render
	# both portraits rather than only updating their own local profile.
	var smoke_skin := "brown" if role == "host" else "purple"
	if not NetworkManager.set_local_skin_id(smoke_skin):
		_fail("online lobby skin update was rejected")
		return
	if not await _wait_for(func():
		var seen := {}
		for entry in NetworkManager.peers.values():
			seen[str(entry.get("skin_id", ""))] = true
		return seen.has("brown") and seen.has("purple")
	, "shared online skin IDs"):
		return
	if not await _wait_for(func():
		var scene := get_tree().current_scene
		if scene == null:
			return false
		var seen := {}
		for portrait in scene.find_children("PlayerPortrait", "", true, false):
			if portrait.visible and portrait.texture != null:
				seen[str(portrait.skin_id)] = true
		return seen.has("brown") and seen.has("purple")
	, "shared online roster portraits"):
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
	# The lobby launch countdown is network-owned, appears as 3/2/1 on every
	# peer, and can be cancelled by the host before any scene load begins.
	if role == "host":
		if not await _wait_for(func():
			for entry in NetworkManager.peers.values():
				if str(entry.get("name", "")) == "Smoke Client":
					return true
			return false
		, "client name before countdown"):
			return
		NetworkManager.begin_prelaunch(test_map)
		if not await _wait_for(func(): return NetworkManager._prelaunch_active and NetworkManager._prelaunch_seconds == 3, "host launch countdown three"):
			return
		if not await _wait_for(func(): return NetworkManager._prelaunch_active and NetworkManager._prelaunch_seconds <= 2, "host launch countdown advance"):
			return
		NetworkManager.cancel_prelaunch("Smoke cancellation")
		if not await _wait_for(func(): return not NetworkManager._prelaunch_active, "host launch countdown cancellation"):
			return
	else:
		if not await _wait_for(func(): return NetworkManager._prelaunch_active and NetworkManager._prelaunch_seconds > 0, "client launch countdown visibility"):
			return
		if not await _wait_for(func(): return not NetworkManager._prelaunch_active, "client launch countdown cancellation"):
			return
	print("ONLINE_LOBBY_PASS " + role)
	if role == "host":
		# A headless peer can spend tens of wall-clock seconds compiling the live
		# carousel previews. Keep the host alive until that client explicitly
		# completes rather than guessing a safe grace period.
		if not await _wait_for(func(): return _lobby_client_complete, "client lobby smoke completion"):
			return
	else:
		_lobby_test_client_complete.rpc_id(1)
		await get_tree().create_timer(0.5).timeout
	get_tree().quit()


@rpc("any_peer", "reliable")
func _lobby_test_client_complete() -> void:
	if multiplayer.is_server():
		_lobby_client_complete = true

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

func _run_online_overtime_checks() -> void:
	var scene := get_tree().current_scene
	var rm = scene.get_node_or_null("RoundManager") if scene != null else null
	if rm == null or not await _wait_for(func(): return rm.overtime_active, "online overtime transition"):
		return
	if rm._storm_wall == null or rm._storm_wall.name != "OvertimeFireField":
		_fail("online overtime did not create the filled fire field")
		return
	var local_actor = NetworkManager.find_net_player(NetworkManager.local_id())
	if local_actor == null:
		_fail("online overtime has no local actor for warning validation")
		return
	local_actor.global_position = rm._overtime_center + Vector3(rm._current_storm_radius() + 2.0, 25.0, 0.0)
	if not await _wait_for(func():
		var warning: Dictionary = rm.get_fire_warning(local_actor)
		return bool(warning.get("active", false))
	, "height-independent online fire warning"):
		return
	var online_hud = scene.get_node_or_null("OnlineHUD")
	var warning_panel = online_hud.match_hud.get_node_or_null("FireExposureWarning") \
		if online_hud != null else null
	if warning_panel == null or not await _wait_for(
			func(): return warning_panel.visible,
			"online HUD local fire countdown"):
		return
	local_actor.global_position = rm._overtime_center
	print("ONLINE_OVERTIME_PASS " + role)
	get_tree().quit()

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
	var client_peer_ids := NetworkManager.peer_ids_sorted().filter(func(id): return int(id) != 1)
	var guns := get_tree().get_nodes_in_group("gun")
	var melee = _active_melee()
	if host_player == null or guns.is_empty() or melee == null or client_peer_ids.is_empty():
		_fail("host player, client actor, gun or melee weapon missing")
		return
	var gun = guns[0]
	var victim = NetworkManager.find_net_player(int(client_peer_ids[0]))
	var client_actor_id := int(victim.actor_id) if victim != null else -1
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
	var melee_markers := get_tree().get_nodes_in_group("melee_spawn_point")
	if melee_weapons.size() != melee_markers.size():
		_fail("online round populated %d of %d melee markers" % [
			melee_weapons.size(), melee_markers.size()])
		return
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
	gun._server_try_pickup(client_actor_id, rm.online_round_epoch)
	# Rendered clients may still be compiling newly introduced item shaders.
	# Leave the client-owned gun visible for long enough that its observation
	# loop can see both the held state and the subsequent disarm transition.
	await get_tree().create_timer(0.8).timeout
	if not gun.is_held or gun.player_ref != victim:
		_fail("melee smoke setup could not give the client the gun")
		return
	host_player.global_position = victim.global_position + Vector3(1.0, 0.0, 0.0)
	melee._server_try_swing(client_actor_id, rm.online_round_epoch)
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
		_fail("authoritative pickup did not replicate locally "
			+ "(distance=%.2f gun=%s player=%s lock_timer=%.2f)" % [
				host_player.global_position.distance_to(gun.global_position),
				gun.global_position,
				host_player.global_position,
				float(gun.disarm_lock_timer),
			])
		return
	host_player.get_node("AimPivot/SpringArm3D").rotation.x = -1.2
	victim.grant_bullet_immunity(5.0)
	var smoke_shot_direction: Vector3 = host_player.get_aim_direction()
	gun._server_try_fire(client_actor_id, smoke_shot_direction, rm.online_round_epoch)
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
	victim = NetworkManager.find_net_player(int(client_peer_ids[0]))
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
	var item_markers := get_tree().get_nodes_in_group("item_spawn_point")
	var powerup_markers := get_tree().get_nodes_in_group("powerup_spawn_point")
	if items.size() != item_markers.size():
		_fail("online round populated %d of %d item markers" % [
			items.size(), item_markers.size()])
		return false
	if powerups.size() != powerup_markers.size():
		_fail("online round populated %d of %d powerup markers" % [
			powerups.size(), powerup_markers.size()])
		return false
	var original = items[0]
	var test_item_id := int(original.online_item_id)
	var test_spawn_id := int(original.online_spawn_id)
	var test_spawn_position: Vector3 = original.spawn_position
	var test_spawn_rotation: Vector3 = original.spawn_rotation
	rm._net_replace_online_item.rpc(test_item_id, "smoke_bomb", test_spawn_position, test_spawn_rotation, test_spawn_id)
	rm._net_respawn_online_powerup.rpc(int(powerups[0].online_powerup_id), "extra_life")
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
	if (is_instance_valid(item) and (item.visible or item.is_in_flight)) \
			or victim.knockback_timer <= 0.0:
		_fail("online boomerang hit/effect/consume did not replicate")
		return false
	var loose_items := get_tree().get_nodes_in_group("online_item").filter(func(candidate): return int(candidate.online_item_id) != test_item_id and candidate.visible and not candidate.is_held)
	if not loose_items.is_empty():
		rm._net_respawn_online_powerup.rpc(int(powerup.online_powerup_id), "reach")
		await get_tree().create_timer(0.15).timeout
		host_player.global_position = powerup.global_position
		rm.server_collect_online_powerup(int(powerup.online_powerup_id), int(host_player.actor_id), rm.online_round_epoch)
		await get_tree().create_timer(0.15).timeout
		var loose_item = loose_items[0]
		var reach_pickup_position: Vector3 = host_player.global_position + Vector3(3.15, 0.0, 0.0)
		rm.broadcast_online_item_move(int(loose_item.online_item_id), reach_pickup_position)
		loose_item._server_try_pickup(1, rm.online_round_epoch)
		await get_tree().create_timer(0.1).timeout
		if host_player.reach_timer <= 0.0 or not loose_item.is_held:
			_fail("Reach did not authorize an extended host-resolved pickup")
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
			saw_second_wind_survival = saw_second_wind_survival or local_player.lethal_immunity_timer > 0.0
			var rm = get_tree().current_scene.get_node_or_null("RoundManager")
			var local_state: Dictionary = rm.online_actor_state.get(int(local_player.actor_id), {}) if rm != null else {}
			if bool(local_state.get("alive", false)) and not local_player.is_eliminated:
				var local_camera: Camera3D = local_player.get_node("AimPivot/SpringArm3D/Camera3D")
				if not local_player.visible or local_player.get("_spectator") != null or not local_camera.current:
					_fail("client actor was authoritative-alive but remained hidden or in spectator camera state")
					return
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
	var found_return_to_lobby := _has_action_id(pause_menu, "return_lobby")
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

func _has_action_id(node: Node, action_id: String) -> bool:
	if node is Button and str(node.get_meta("action_id", "")) == action_id:
		return true
	for child in node.get_children():
		if _has_action_id(child, action_id):
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
