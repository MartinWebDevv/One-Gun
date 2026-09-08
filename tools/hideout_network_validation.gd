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
					_check(HideoutSession.course_lobby_times.is_empty(),"leaving clears previous lobby records")
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
	manager.server_eliminate(client_id,host_actor.actor_id,manager.online_round_epoch)
	_check(scene.scrap.state==scene.scrap.State.RESULT,"one elimination ends the duel")
	if not await _wait_for(func(): return scene.scrap.state==scene.scrap.State.IDLE,"duel reset"): return
	_check(not guest.is_eliminated and not host_actor.holding_gun,"duel returns both players without gear")
	_check(guest.position.distance_to(host_actor.position)>2.0,"fighters return to separate terminal positions")
	_check(get_tree().get_nodes_in_group("online_powerup").all(func(obj): return int(obj.get_meta("scrap_epoch",-1))<0),"duel power spawn retires with the round")
	await _verify_remote("duel_reset")
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
	scene.scrap.leave()
	_check(scene.scrap.state==scene.scrap.State.RESULT,"fighter leave cancels the duel")
	if not await _wait_for(func(): return scene.scrap.state==scene.scrap.State.IDLE,"cancelled duel resets"): return
	await _verify_remote("duel_reset")
	for cycle in range(2):
		print("HIDEOUT_LAUNCH ",cycle)
		NetworkManager.start_game("res://node_3d.tscn")
		if not await _wait_for(_match_ready,"match ready",60000): return
		_check(NetworkManager.peers.size()==2,"both peers survive match launch")
		await _verify_remote("match")
		NetworkManager.host_return_everyone_to_lobby()
		if not await _wait_for(_hideout_ready,"return to shared Hideout",60000): return
		await _verify_remote("return")
		_check(NetworkManager.peers.size()==2,"both peers return to the same session")
		var room:=get_tree().current_scene
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
			"course":
				_check(scene.training.records.lobby_rows(scene.training.movement_key()+"/standard").filter(func(row): return row.time_ms>=1000).size()==2,"shared board contains both runners")
				_check(scene.training.records.personal_best(scene.training.movement_key()+"/standard",str(NetworkManager.local_actor_id()))>=1000,"personal page contains the viewing player record")
			"range": _check(scene.training.range_indices[1]==9 and scene.training.hits[1]==1,"range distance and hit count replicated")
			"course_live":
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
