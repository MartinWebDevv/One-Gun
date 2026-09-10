extends Node
var host := false
var port := 24671
var connection_done := false
var checks := 0
var peer_ready := false
var remote_phase := ""
var host_done := false
var effect_seeded := false
var live_list_id := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	reparent(get_tree().root)
	var args := OS.get_cmdline_user_args()
	host = args.has("--hideout-host")
	for arg in args:
		if arg.begins_with("--test-port="): port=int(arg.trim_prefix("--test-port="))
	# Seed only the isolated fixture file for the account active on this test PC.
	var fixture=preload("res://maps/hideout/course_records.gd").new()
	fixture.configure_profile(true)
	var account := SupabaseManager.current_user_id()
	var key := "account:"+account.sha256_text() if not account.is_empty() else "local:profile"
	if not fixture.storage_path.is_empty():
		for bucket in fixture.personal_times:
			if fixture.personal_times[bucket].has("local:profile"):
				fixture.personal_times[bucket][key]=fixture.personal_times[bucket]["local:profile"]
		fixture._save()
	GameConfig.set_bot_count(0)
	GameConfig.teams_enabled=false
	NetworkManager.connection_succeeded.connect(func(): connection_done=true)
	if host: NetworkManager.lobby_changed.connect(_seed_join_effect)
	get_tree().change_scene_to_file("res://maps/hideout/hideout.tscn")
	var load_deadline := Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<load_deadline:
		await get_tree().process_frame
		var world:=get_tree().current_scene
		if world!=null and bool(world.get("activities_ready")): break
	if host:
		if not NetworkManager.host_game(port,"Hideout validation",{"privacy":"private"}):
			_fail("Host could not start"); return
		connection_done=true
		get_tree().current_scene._session_started()
	else: NetworkManager.join_game("127.0.0.1",port)
	var deadline := Time.get_ticks_msec()+20000
	while not connection_done and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	if not connection_done: _fail("Join handshake timed out"); return
	if not host: get_tree().current_scene._session_started()
	deadline=Time.get_ticks_msec()+65000
	var announced := false
	while Time.get_ticks_msec()<deadline:
		var scene:=get_tree().current_scene
		if scene!=null and scene.scene_file_path=="res://maps/hideout/hideout.tscn":
			var actor=scene.get("pilot")
			if host and not announced and is_instance_valid(actor) and actor.is_online:
				announced=true
				_check_unique_player_hud("hosting before guest arrival")
				_check(not scene.playpen.contains_actor(actor),"host arrival hall is safe")
				_teleport(actor.actor_id,Vector3(17,-0.11,-36))
				scene.playpen.sync_actor(actor)
				scene.playpen._online_loose_gun("PlaypenGun1_0")._net_do_pickup(actor.actor_id)
				scene.training.set_distance(2,8)
				print("HIDEOUT_HOST_READY")
			if is_instance_valid(actor) and actor.is_online and scene.has_node("NetPlayers") and NetworkManager.peers.size()==2 and scene.get_node("NetPlayers").get_child_count()==2:
				_check(actor.owner_peer_id==NetworkManager.local_id(),"local camera is bound to the local actor")
				_check(scene.get("activities_ready"),"network activities initialized")
				_check(scene.get_node("RoundManager").snapshot_received,"world state established before interaction")
				if not host: _check(not scene.playpen.contains_actor(actor),"arrival hall is safe")
				_check_unique_player_hud("shared Hideout arrival")
				print("HIDEOUT_NETWORK_READY ", "HOST" if host else "CLIENT")
				if host:
					if not await _wait_for(func(): return peer_ready,"client scene acknowledgement"): return
					await _exercise_host()
				else:
					var existing_host=NetworkManager.find_actor(NetworkManager.actor_id_for_peer(1))
					if not await _wait_for(func(): return existing_host.holding_gun,"late-join held gun"): return
					_check(scene.training.range_indices[2]==8,"late join receives existing range setup")
					_check(existing_host.holding_gun,"late join receives held gear")
					_check(not get_tree().get_nodes_in_group("online_deployed").is_empty(),"late join receives an active deployed item")
					_ready_peer.rpc_id(1)
					if not await _wait_for(func(): return host_done,"host activity/transition checks",180000): return
					NetworkManager.leave_online_to_main_menu()
					if not await _wait_for(_own_home_ready,"guest returns to own home"): return
					_check(HideoutSession.scrap_lobby_wins.is_empty(),"leaving for a new Hideout clears Scrap standings")
					_check(HideoutSession.course_lobby_times.is_empty(),"leaving clears previous lobby records")
					var home=get_tree().current_scene.training
					_check(home.records.personal_best(home.records_bucket(false),home.viewer_id())<42000,"improved personal best survives disconnect and loads in own home")
					_check(home.records.lobby_rows(home.records_bucket(false))[0].time_ms<42000,"fresh home board displays saved personal best without another run")
					_check_unique_player_hud("guest returned to own home")
					print("HIDEOUT_COMPLETE CLIENT")
					get_tree().quit(0)
				return
		await get_tree().process_frame
	_fail("Shared Hideout actors were not established")

func _check(ok: bool, label: String) -> void:
	if not ok: _fail(label)
	else: checks+=1; print("PASS: ",label)

func _fail(message: String) -> void:
	push_error("HIDEOUT CHECK FAILED: "+message)
	get_tree().quit(2)


@rpc("any_peer","reliable")
func _ready_peer() -> void:
	if host: peer_ready=true

func _wait_for(condition: Callable, label: String, duration := 45000) -> bool:
	var until := Time.get_ticks_msec()+duration
	while Time.get_ticks_msec()<until:
		if condition.call(): return true
		await get_tree().process_frame
	_fail("Timed out: "+label)
	return false

func _teleport(id: int, at: Vector3) -> void:
	var manager=get_tree().current_scene.get_node("RoundManager")
	NetworkManager.broadcast_match_rpc(manager,&"_net_recover_playpen_actor",[id,at,0.0])

func _exercise_host() -> void:
	var scene:=get_tree().current_scene
	var manager=scene.playpen
	var client_id:=NetworkManager.actor_id_for_peer(NetworkManager.peer_ids_sorted()[1])
	var host_actor=scene.pilot
	var guest=NetworkManager.find_actor(client_id)
	var bucket: String=scene.training.records_bucket(false)
	if not await _wait_for(func(): return scene.training.records.lobby_times.get(bucket,{}).get(str(client_id),-1)==42000,"guest uploads saved PB on join"): return
	_check(scene.training.records.lobby_times[bucket][str(NetworkManager.local_actor_id())]==45000,"host saved PB appears before running")
	_check(scene.training.records.lobby_times[scene.training.records_bucket(true)][str(client_id)]==30000,"guest Power-Up PB is shared separately")
	_check(scene.training.records.lobby_details.is_empty(),"imported history does not invent session finishes")
	await _verify_remote("saved_bests")
	var menu_errors: Array[String]=await preload("res://tools/hideout_menu_validation.gd").run(scene)
	_check(menu_errors.is_empty(),"host Escape movement and camera: "+str(menu_errors))
	await _verify_remote("pause_movement")
	await _check_live_appearance(scene)
	manager.clear_inventory(host_actor)
	manager.server_eliminate(client_id,host_actor.actor_id,manager.online_round_epoch)
	_check(not guest.is_eliminated,"main hall rejects damage")
	scene.training.set_distance(1,9)
	scene.training.target_hit(1)
	await _verify_remote("range")
	_teleport(host_actor.actor_id,Vector3(17,-0.11,-36))
	await get_tree().create_timer(0.5).timeout
	var gun=manager._online_loose_gun("PlaypenGun0_0")
	_check(gun!=null,"armory contains gun stock")
	gun._net_do_pickup(host_actor.actor_id)
	host_actor.apply_powerup("speed_surge",10.0)
	_check(host_actor.holding_gun,"fixture picked up a practice gun")
	_teleport(host_actor.actor_id,scene.spawn.position)
	await get_tree().create_timer(0.5).timeout
	_check(not host_actor.holding_gun and host_actor.speed_surge_timer<=0,"leaving Play Pen clears gear and powers")
	var training=scene.training
	for actor in [host_actor,guest]:
		training._gate_entered(actor,0)
		training._gate_entered(actor,3)
		_check(training.runners[actor.actor_id].next==1,"course rejects skipped checkpoints")
	await get_tree().create_timer(1.2).timeout
	# The physics test actors are deliberately held in the hall; start new host
	# fixtures now and backdate by 1.2s to test finish/record plumbing only.
	for actor in [host_actor,guest]:
		training._gate_entered(actor,0)
		training.runners[actor.actor_id].start=Time.get_ticks_msec()-1200
		for gate in range(1,training.Space.COURSE_GATES.size()): training._gate_entered(actor,gate)
	_check(training.records.lobby_rows(training.movement_key()+"/standard").filter(func(row): return row.time_ms>=1000).size()==2,"both players receive host-validated course records")
	await _verify_remote("course")
	var best_before: int=training.records.lobby_times[bucket][str(client_id)]
	training._gate_entered(guest,0)
	training.runners[client_id].start=Time.get_ticks_msec()-9000
	for gate in range(1,training.Space.COURSE_GATES.size()): training._gate_entered(guest,gate)
	_check(training.records.lobby_times[bucket][str(client_id)]==best_before,"slower finish never replaces shared personal best")
	await _verify_remote("course")
	await _exercise_course_modes(scene,host_actor,guest)
	_teleport(host_actor.actor_id,scene.scrap.Space.TERMINAL_USE)
	_teleport(client_id,scene.scrap.Space.TERMINAL_USE+Vector3(1,0,0))
	await get_tree().create_timer(0.5).timeout
	scene._open("scrap")
	_press_scrap("JOIN THE SCRAP")
	await _verify_remote("join_duel")
	if not await _wait_for(func(): return scene.scrap.fighter_ids.size()==2 and not scene.scrap.positioning,"two fighters placed"): return
	_check(scene.scrap.fighter_ids.size()==2,"two players registered through the terminal UI")
	# Reproduce an older movement packet arriving after the host's teleport.
	var placed: Vector3=guest.position
	guest.position=scene.scrap.Space.TERMINAL_USE
	scene.scrap._process(0.016)
	_check(scene.scrap.state==scene.scrap.State.CALLING,"pre-teleport movement packet does not cancel signup")
	guest.position=placed
	await _verify_remote("coin_call")
	if not await _wait_for(func(): return is_instance_valid(scene) and scene.scrap.state==scene.scrap.State.ACTIVE,"authoritative coin flip"): return
	_check(scene.scrap.coin_side in ["heads","tails"],"host selected one coin result")
	_check(scene.ui.page.is_empty() and scene.controls_enabled and not host_actor.external_input_blocked,"host signup closes and combat input unlocks")
	_check(scene.player_hud.player==host_actor and scene.player_hud.visible,"host HUD follows the local fighter")
	var duel_guns:=0
	var duel_melee:=0
	for entry in manager.cleanup.objects.values():
		var object=entry.ref.get_ref()
		if not is_instance_valid(object) or int(object.get_meta("scrap_epoch",-1))!=scene.scrap.epoch: continue
		if object.is_in_group("gun"): duel_guns+=1
		if object.is_in_group("melee"): duel_melee+=1
	_check(duel_guns==1 and duel_melee==2,"Scrap Yard provides one gun and two melee weapons")
	await _verify_remote("duel")
	await _check_disarm_reload(scene)
	var result_started:=Time.get_ticks_msec()
	manager.server_eliminate(client_id,host_actor.actor_id,manager.online_round_epoch)
	_check(scene.scrap.state==scene.scrap.State.RESULT,"one elimination ends the duel")
	_check(HideoutSession.scrap_lobby_wins[str(NetworkManager.local_actor_id())].wins==1,"host awards one Scrap win")
	scene.scrap.finish_elimination(client_id)
	_check(HideoutSession.scrap_lobby_wins[str(NetworkManager.local_actor_id())].wins==1,"duplicate elimination cannot award a second win")
	await _verify_remote("scrap_wins")
	if not await _wait_for(func(): return scene.scrap.state==scene.scrap.State.IDLE,"duel reset",6000): return
	_check(Time.get_ticks_msec()-result_started<6000,"victory and acknowledged return complete without timeout delay")
	await get_tree().create_timer(0.35).timeout
	_check(scene.scrap.transition.veil.color.a<0.01,"return fade reveals the room after placement")
	_check(not guest.is_eliminated and not host_actor.holding_gun,"duel returns both players without gear")
	_check(guest.position.distance_to(host_actor.position)>2.0,"fighters return to separate terminal positions")
	_check(get_tree().get_nodes_in_group("online_powerup").all(func(obj): return int(obj.get_meta("scrap_epoch",-1))<0),"duel power spawn retires with the round")
	await _verify_remote("duel_reset")
	await _check_spectator_return(scene)
	await _verify_remote("spectator_return")
	_teleport(host_actor.actor_id,scene.scrap.Space.TERMINAL_USE)
	_teleport(client_id,scene.scrap.Space.TERMINAL_USE+Vector3(1,0,0))
	await get_tree().create_timer(0.4).timeout
	await _verify_remote("join_duel")
	if not await _wait_for(func(): return scene.scrap.fighter_ids.size()==1,"guest joins first"): return
	scene._open("scrap")
	_press_scrap("JOIN THE SCRAP")
	if not await _wait_for(func(): return scene.scrap.can_call(host_actor.actor_id),"host joins second"): return
	_check(not scene.scrap.can_call(client_id),"first player cannot choose the coin")
	_press_scrap("TAILS")
	if not await _wait_for(func(): return scene.scrap.state==scene.scrap.State.ACTIVE,"reverse-order duel starts"): return
	_check(scene.controls_enabled and scene.ui.page.is_empty(),"host can call tails as second fighter and play")
	await _verify_remote("duel")
	await _check_disarm_reload(scene)
	scene.scrap.leave()
	_check(scene.scrap.state==scene.scrap.State.RESULT,"fighter leave cancels the duel")
	_check(HideoutSession.scrap_lobby_wins[str(NetworkManager.local_actor_id())].wins==1,"cancelled duels do not award wins")
	if not await _wait_for(func(): return scene.scrap.state==scene.scrap.State.IDLE,"cancelled duel resets"): return
	await _verify_remote("duel_reset")
	for cycle in range(2):
		print("HIDEOUT_LAUNCH ",cycle)
		NetworkManager.start_game("res://node_3d.tscn")
		if not await _wait_for(_match_ready,"match ready",60000): return
		_check(NetworkManager.peers.size()==2,"both peers survive match launch")
		_check_unique_player_hud("host match HUD")
		await _verify_remote("match")
		NetworkManager.host_return_everyone_to_lobby()
		if not await _wait_for(_hideout_ready,"return to shared Hideout",60000): return
		_check_unique_player_hud("host match return")
		await _verify_remote("return")
		_check(NetworkManager.peers.size()==2,"both peers return to the same session")
		var room:=get_tree().current_scene
		_check(HideoutSession.scrap_lobby_wins[str(NetworkManager.local_actor_id())].wins==1,"Scrap wins survive a normal match return")
		_check(room.training.selected_powerup,"last course choice survives match return")
		_check(room.training.records.lobby_rows(room.training.movement_key()+"/standard").filter(func(row): return row.time_ms>=1000).size()==2,"lobby course records survive a match return")
	var returned:=get_tree().current_scene
	var pen=returned.playpen
	var ids:=NetworkManager.peer_ids_sorted()
	var victim_id:=NetworkManager.actor_id_for_peer(ids[1])
	_teleport(NetworkManager.local_actor_id(),Vector3(17,-0.11,-36))
	_teleport(victim_id,Vector3(20,-0.11,-36))
	await get_tree().create_timer(0.3).timeout
	pen.server_eliminate(victim_id,NetworkManager.local_actor_id(),pen.online_round_epoch)
	_check(NetworkManager.find_actor(victim_id).is_eliminated,"practice death is authoritative")
	# The host's alive flag changes before the owner's new transform arrives.
	# Assert completed recovery, not the intermediate replication frame.
	if not await _wait_for(func(): return not NetworkManager.find_actor(victim_id).is_eliminated and not pen.contains_actor(NetworkManager.find_actor(victim_id)),"practice respawn outside the barrier"): return
	_check(not pen.contains_actor(NetworkManager.find_actor(victim_id)),"practice death respawns outside the barrier")
	_finish.rpc()
	if not await _wait_for(func(): return NetworkManager.peers.size()==1,"guest leaves independently"): return
	_check(NetworkManager.is_online() and get_tree().current_scene.scene_file_path==HideoutSession.SCENE,"guest leaving preserves host session")
	NetworkManager.leave_online_to_main_menu()
	if not await _wait_for(_own_home_ready,"host returns to own home"): return
	_check_unique_player_hud("host returned to own home")
	print("HIDEOUT_COMPLETE HOST")
	get_tree().quit(0)

func _match_ready() -> bool:
	var world:=get_tree().current_scene
	if world==null or world.scene_file_path!="res://node_3d.tscn": return false
	var manager=world.get_node_or_null("RoundManager")
	return manager!=null and bool(manager.get("online_combat_live")) and NetworkManager.are_all_match_peers_ready()

func _hideout_ready() -> bool:
	var world:=get_tree().current_scene
	return world!=null and world.scene_file_path==HideoutSession.SCENE and world.get("activities_ready")==true and world.has_node("NetPlayers") and world.get_node("NetPlayers").get_child_count()==2

func _verify_remote(phase: String) -> void:
	remote_phase=""
	_verify.rpc_id(NetworkManager.peer_ids_sorted()[1],phase)
	await _wait_for(func(): return remote_phase==phase,"client verification: "+phase,60000)

@rpc("authority","reliable")
func _verify(phase: String) -> void:
	if phase=="match":
		if not await _wait_for(func():
			var world:=get_tree().current_scene
			return world!=null and world.scene_file_path=="res://node_3d.tscn" and world.has_node("NetPlayers") and world.get_node("NetPlayers").get_child_count()==2
		,"client match ready",60000): return
	elif phase=="return":
		if not await _wait_for(_hideout_ready,"client Hideout return",60000): return
	else:
		var scene:=get_tree().current_scene
		match phase:
			"spectator_return":
				await _check_spectator_return(scene)
			"appearance":
				for actor in scene.get_node("NetPlayers").get_children():
					_check(actor.character_model_id=="female" and actor.character_skin_id=="blue","roster changes update existing host and guest models")
			"reload_ready":
				var guns=get_tree().get_nodes_in_group("gun").filter(func(gun): return gun.get_meta("scrap_epoch",-1)==scene.scrap.epoch)
				_check(guns.size()==1 and guns[0].can_fire,"guest receives reload completion for the disarmed gun")
			"pause_movement":
				var menu_errors: Array[String]=await preload("res://tools/hideout_menu_validation.gd").run(scene)
				_check(menu_errors.is_empty(),"guest Escape movement and camera: "+str(menu_errors))
			"saved_bests":
				var t=scene.training
				if not await _wait_for(func(): return t.records.lobby_rows(t.records_bucket(false)).filter(func(row): return row.time_ms==42000 or row.time_ms==45000).size()==2,"both historical PBs reach guest board"): return
				_check(t.records.lobby_rows(t.records_bucket(true)).filter(func(row): return row.time_ms==30000 or row.time_ms==33000).size()==2,"guest sees both historical Power-Up PBs")
				_check(t.records.lobby_details.is_empty(),"guest historical times do not count as new finishes")
			"course":
				_check(scene.training.records.lobby_rows(scene.training.movement_key()+"/standard").filter(func(row): return row.time_ms>=1000).size()==2,"shared board contains both runners")
				_check(scene.training.records.personal_best(scene.training.movement_key()+"/standard",str(NetworkManager.local_actor_id()))>=1000,"personal page contains the viewing player record")
				var reloaded=scene.training.Records.new()
				reloaded.configure(scene.training.personal_store.storage_path)
				var saved: int=reloaded.personal_best(scene.training.records_bucket(false),scene.training.personal_key)
				_check(saved>=1000 and saved<42000,"new guest PB is durably saved and slower finishes preserve it")
				_check(scene.training.records.lobby_times[scene.training.records_bucket(false)][str(NetworkManager.local_actor_id())]==saved,"shared PB equals saved personal record")
			"range": _check(scene.training.range_indices[1]==9 and scene.training.hits[1]==1,"range distance and hit count replicated")
			"scrap_wins":
				var winner:=str(NetworkManager.actor_id_for_peer(1))
				_check(HideoutSession.scrap_lobby_wins[winner].wins==1,"guest receives lobby win standings immediately")
				_check("1 WIN" in scene.scrap.wins_board.text,"physical wins board shows the winner")
			"course_live":
				_check(not scene.training.selected_powerup,"host choosing Power-Up does not change guest selection")
				_check(scene.station.find_child("CourseStartDoor",true,false).get_node("Sign/Title").modulate==scene.G.GREEN,"guest doorway stays Standard while host runs Power-Up")
				scene.training.board_assisted=true
				scene._open("course_board")
				await get_tree().create_timer(0.3).timeout
				var list=scene.ui.contents.get_node("CourseLiveRows")
				live_list_id=list.get_instance_id()
				_check(list.get_children().any(func(label): return "RUNNING" in label.text),"guest sees live host run in the open scoreboard")
			"course_finished_live":
				var list=scene.ui.contents.get_node("CourseLiveRows")
				if not await _wait_for(func(): return list.get_children().any(func(label): return "1 FINISHES" in label.text),"live finish update"): return
				_check(list.get_instance_id()==live_list_id,"finish updates player rows without rebuilding the open menu")
				_check("RUNNING" not in scene.training.board_rows.text,"wall board replaces live timer with completed Power-Up record")
				scene._open("")
			"course_choose_power":
				scene.training.select_mode(true)
			"course_guest_grant":
				if not await _wait_for(func(): return scene.pilot.speed_surge_timer>0,"guest receives start loadout"): return
				_check(scene.pilot.extra_dash_charge==1,"owning guest receives its extra dash")
			"course_cancelled":
				if not await _wait_for(func(): return scene.pilot.speed_surge_timer<=0,"cancelled run clears bonuses"): return
			"join_duel":
				scene._open("scrap")
				_press_scrap("JOIN THE SCRAP")
			"coin_call":
				if not await _wait_for(func(): return scene.scrap.can_call(NetworkManager.local_actor_id()),"coin call UI ready"): return
				_check(scene.ui.page=="scrap","second player sees coin controls")
				_press_scrap("HEADS")
			"duel":
				_check(scene.scrap.state==scene.scrap.State.ACTIVE,"client received duel start")
				_check(scene.ui.page.is_empty() and scene.controls_enabled and not scene.pilot.external_input_blocked,"client signup closes and combat input unlocks")
				_check(scene.player_hud.player==scene.pilot and scene.player_hud.visible,"client HUD binds its own fighter")
				var before: Vector3=scene.pilot.position
				Input.action_press("p1_move_forward")
				await get_tree().create_timer(0.25).timeout
				Input.action_release("p1_move_forward")
				_check(scene.pilot.position.distance_to(before)>0.3,"guest can actually move after the coin countdown")
				_check(scene.pilot.holding_gun or is_instance_valid(scene.pilot.held_melee_weapon),"client received its coin-assigned weapon")
			"duel_reset": _check(not scene.pilot.is_eliminated and not scene.pilot.holding_gun and not is_instance_valid(scene.pilot.held_melee_weapon),"client duel reset cleared inventory")
	if phase in ["match","return"]: _check_unique_player_hud("guest " + phase)
	print("PASS: remote ",phase)
	_verified.rpc_id(1,phase)

@rpc("any_peer","reliable")
func _verified(phase: String) -> void:
	if host: remote_phase=phase

@rpc("authority","reliable")
func _finish() -> void:
	host_done=true


func _seed_join_effect() -> void:
	if effect_seeded or NetworkManager.peers.size()!=2: return
	var world:=get_tree().current_scene
	if world==null or not world.has_node("RoundManager"): return
	effect_seeded=true
	var manager=world.playpen
	manager.server_deploy_online_item(10,Vector3(22,-1.2,-38),NetworkManager.local_actor_id(),8.0,manager.online_round_epoch)


func _own_home_ready() -> bool:
	var scene:=get_tree().current_scene
	return not NetworkManager.is_online() and scene!=null and scene.scene_file_path==HideoutSession.SCENE and is_instance_valid(scene.pilot) and not scene.pilot.is_online and scene.activities_ready

func _press_scrap(text: String) -> void:
	var ui=get_tree().current_scene.ui
	for button in ui.contents.find_children("*","Button",true,false):
		if button.text==text:
			button.pressed.emit()
			return
	_fail("Missing Scrap UI button: "+text)

func _exercise_course_modes(scene: Node3D, actor: CharacterBody3D, guest: CharacterBody3D) -> void:
	var t=scene.training
	_teleport(actor.actor_id,t.Space.Course.MODE_BUTTONS[0]+Vector3(1.4,0,0))
	await get_tree().create_timer(0.3).timeout
	actor.apply_powerup("extra_life",5.0)
	actor.apply_powerup("speed_surge",5.0)
	actor.activate_double_jump_shoes()
	t.select_mode(false)
	_check(not actor.second_wind_ready and actor.speed_surge_timer<=0 and not actor.double_jump_shoes_active,"Standard button clears carried powers and activated shoes")
	actor.apply_powerup("speed_surge",5.0)
	_teleport(actor.actor_id,t.Space.RECOVERY[0])
	await get_tree().create_timer(0.3).timeout
	t._gate_entered(actor,0)
	_check(actor.speed_surge_timer<=0 and not t.runners[actor.actor_id].assisted,"Standard starting line clears powers acquired after selection")
	t.cancel_runner(actor.actor_id)
	_teleport(actor.actor_id,t.Space.Course.MODE_BUTTONS[1]+Vector3(1.4,0,0))
	await get_tree().create_timer(0.3).timeout
	t.select_mode(true)
	_check(actor.speed_surge_timer<=0 and actor.extra_dash_charge==0,"Power-Up button arms the run without granting early bonuses")
	_teleport(actor.actor_id,t.Space.RECOVERY[0])
	await get_tree().create_timer(0.3).timeout
	t._gate_entered(actor,0)
	_check(actor.speed_surge_timer>4.5 and actor.speed_surge_timer<=5 and actor.extra_dash_charge==1,"starting line grants normal Speed Surge and Extra Dash")
	await _verify_remote("course_live")
	actor.dash_charges=0
	actor._start_dash()
	_check(actor.extra_dash_charge==0,"course Extra Dash is consumed by the real dash action")
	await get_tree().create_timer(5.2).timeout
	_check(actor.speed_surge_timer<=0 and t.runners[actor.actor_id].assisted,"normal Surge expires while the run stays in Power-Up standings")
	t.board_assisted=true
	t.board_tab="personal"
	scene._open("course_board")
	var personal_label=scene.ui.contents.get_node("PersonalLiveBest")
	for gate in range(1,t.Space.COURSE_GATES.size()): t._gate_entered(actor,gate)
	_check(personal_label.text!="SET YOUR FIRST TIME","host personal best updates in the already-open panel")
	_check(t.records.lobby_details[t.records_bucket(true)][str(actor.actor_id)].finishes==1,"completed run records latest time and finish count")
	await _verify_remote("course_finished_live")
	scene._open("")
	_teleport(guest.actor_id,t.Space.Course.MODE_BUTTONS[1]+Vector3(1.4,0,0))
	await get_tree().create_timer(0.3).timeout
	await _verify_remote("course_choose_power")
	if not await _wait_for(func(): return bool(t.selected_modes.get(guest.actor_id,false)),"guest run selection accepted"): return
	_teleport(guest.actor_id,t.Space.RECOVERY[0])
	await get_tree().create_timer(0.3).timeout
	t._gate_entered(guest,0)
	await _verify_remote("course_guest_grant")
	t.cancel_runner(guest.actor_id)
	await _verify_remote("course_cancelled")

func _check_unique_player_hud(context: String) -> void:
	var world := get_tree().current_scene
	var in_hideout: bool = world.scene_file_path == HideoutSession.SCENE
	var expected_hud := "res://maps/hideout/player_hud.gd" if in_hideout else "res://online_hud.gd"
	var unwanted_hud := "res://online_hud.gd" if in_hideout else "res://maps/hideout/player_hud.gd"
	var counts := {expected_hud: 0, unwanted_hud: 0,
		"res://inventory_slots.gd": 0, "res://stamina_bar.gd": 0, "res://dash_charges.gd": 0}
	var actor = world.pilot if in_hideout else NetworkManager.find_net_player(NetworkManager.local_id())
	var pending: Array[Node] = [world]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		var script = node.get_script()
		if script == null or not counts.has(script.resource_path): continue
		counts[script.resource_path] += 1
		if script.resource_path not in [expected_hud, unwanted_hud]:
			_check(node.player == actor, context + ": widget belongs to local actor: " + node.name)
	for path in counts:
		_check(counts[path] == (0 if path == unwanted_hud else 1), context + ": HUD instance count " + path.get_file() + " = " + str(counts[path]))
	if in_hideout:
		_check(world.player_hud.player == world.pilot, context + ": sole room HUD is bound to pilot")

func _check_disarm_reload(scene: Node3D) -> void:
	var manager=scene.playpen
	var gun=get_tree().get_nodes_in_group("gun").filter(func(obj): return obj.get_meta("scrap_epoch",-1)==scene.scrap.epoch)[0]
	var original: int=gun.player_ref.actor_id
	var recipient: int=scene.scrap.fighter_ids.filter(func(id): return id!=original)[0]
	manager.broadcast_online_gun_action("force_reload",{"holder_actor_id":original})
	gun.net_force_disarm()
	manager.broadcast_online_gun_action("pickup",{"holder_actor_id":recipient,"gun_instance_name":str(gun.name)})
	_check(not gun.can_fire and not gun.get_node("ReloadTimer").is_stopped(),"online disarm transfers the still-reloading gun")
	if not await _wait_for(func(): return gun.can_fire,"reload after disarm",12000): return
	await _verify_remote("reload_ready")

func _check_live_appearance(scene: Node3D) -> void:
	var previous:=NetworkManager.peers.duplicate(true)
	for id in NetworkManager.peers:
		NetworkManager.peers[id]["model_id"]="female"
		NetworkManager.peers[id]["skin_id"]="blue"
	NetworkManager.lobby_changed.emit()
	NetworkManager._broadcast_lobby_state()
	await get_tree().create_timer(0.5).timeout
	for actor in scene.get_node("NetPlayers").get_children():
		_check(actor.character_model_id=="female" and actor.character_skin_id=="blue","host applies appearance changes to existing actors")
	await _verify_remote("appearance")
	for id in previous:
		NetworkManager.peers[id]["model_id"]=previous[id].model_id
		NetworkManager.peers[id]["skin_id"]=previous[id].skin_id
	NetworkManager.lobby_changed.emit()
	NetworkManager._broadcast_lobby_state()

func _check_spectator_return(scene: Node3D) -> void:
	# Present another pair's return to this peer, including a direct stale callback.
	# This exercises the same snapshot receiver for hosts and guests without actors
	# or RPC requests belonging to this local viewer.
	var scrap=scene.scrap
	var saved: Dictionary=scrap._snapshot().duplicate(true)
	var returning: Dictionary=saved.duplicate(true)
	returning.state=scrap.State.RETURNING
	returning.fighters=[90001,90002]
	returning.epoch=int(saved.epoch)+1
	returning.remaining=8.0
	scrap.set_process(false)
	scrap._receive(returning)
	await scrap._fade_for_return(int(returning.epoch))
	await get_tree().create_timer(0.4).timeout
	_check(not scrap.transition.visible and scrap.transition.veil.color.a==0.0,"another pair's return never fades this host/guest spectator")
	_check(scene.controls_enabled,"spectator keeps movement through another pair's return")
	scrap._receive(saved)
	scrap.set_process(true)
