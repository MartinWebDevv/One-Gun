extends RefCounted
const Course = preload("res://maps/hideout/agility_space.gd")

static func run(world: Node3D, check: Callable) -> void:
	await _check_scrap_spectator(world,check)
	var actor=world.pilot
	var training=world.training
	actor.set_physics_process(false)
	training.set_physics_process(false)
	check.call(Course.COURSE_GATES[0].x==Course.COURSE_GATES[-1].x,"start and finish have equal doorway offsets")
	for z in [-35.7,-51.3]:
		check.call(Course.crossed_gate(Vector3(-11,0,z),Vector3(-15,0,z),0),"full-width start accepts a fast wall-hugging crossing")
	for z in [-62.7,-78.3]:
		check.call(Course.crossed_gate(Vector3(-15,0,z),Vector3(-11,0,z),6),"full-width finish accepts a fast wall-hugging crossing")
		check.call(not Course.crossed_gate(Vector3(-11,0,z),Vector3(-15,0,z),6),"reverse entry through finish cannot submit a time")
	training.remember_mode(false)
	for index in range(Course.COURSE_GATES.size()):
		var at: Vector3=Course.COURSE_GATES[index]
		if index>=4: at.z=-78.3
		var direction:=Vector3(0,0,-1) if index==3 else Vector3.RIGHT if index>=4 else Vector3.LEFT
		training.previous_positions[actor.get_instance_id()]=at-direction*2
		actor.position=at+direction*2
		world.playpen.sync_actor(actor)
		if index==6: training.elapsed=12.345
		training._check_crossings(actor)
		check.call((training.running and training.next_gate==index+1) if index<6 else (not training.running and is_equal_approx(training.last_time,12.345)),"swept course checkpoint %d advances once" % index)
	for z in [-42.25,-70.75]:
		actor.position=Vector3(-8,0,z)
		world.playpen.sync_actor(actor)
		var gun=preload("res://gun.tscn").instantiate()
		world.add_child(gun)
		gun._local_pickup(actor)
		actor.apply_powerup("speed_surge",10)
		actor.activate_double_jump_shoes()
		actor.position.x=-10.5
		world.playpen.sync_actor(actor)
		check.call(not actor.holding_gun and gun.is_queued_for_deletion() and actor.speed_surge_timer<=0 and not actor.double_jump_shoes_active,"door strips gun and outside powers at z=%s" % z)
		check.call(not actor.apply_powerup("silent_steps",10) and actor.is_bullet_immune(),"course rejects further pickup grants and bullet damage")
		preload("res://maps/hideout/course_loadout.gd").start(actor,true)
		check.call(actor.speed_surge_timer>0 and actor.extra_dash_charge==1,"only the course can grant its selected starting bonuses")
		actor.position.x=-8
		world.playpen.sync_actor(actor)
		check.call(actor.speed_surge_timer<=0 and actor.extra_dash_charge==0,"leaving either course door clears run bonuses")
		var bullet=preload("res://bullet.tscn").instantiate()
		bullet.position=Vector3(-7,1,z)
		world.add_child(bullet)
		bullet.launch(Vector3.LEFT,null)
		await world.get_tree().create_timer(0.12).timeout
		check.call(not is_instance_valid(bullet) or bullet.is_queued_for_deletion(),"full-speed bullet retires at course door z=%s" % z)
	actor.position=Vector3(17,0,-38)
	world.playpen.sync_actor(actor)
	var reload_gun=preload("res://gun.tscn").instantiate()
	world.add_child(reload_gun)
	reload_gun._local_pickup(actor)
	reload_gun.can_fire=false
	reload_gun.get_node("ReloadTimer").start(0.3)
	reload_gun.force_disarm()
	reload_gun._local_pickup(actor)
	check.call(not reload_gun.get_node("ReloadTimer").is_stopped(),"disarm and re-pick preserve the running reload timer")
	await world.get_tree().create_timer(0.4).timeout
	check.call(reload_gun.can_fire,"disarmed gun becomes fireable after remaining reload")
	var old_model: String=actor.character_model_id
	var old_skin: String=actor.character_skin_id
	reload_gun.can_fire=false
	reload_gun.get_node("ReloadTimer").start(0.3)
	actor.set_character_appearance("male" if old_model!="male" else "female",old_skin)
	check.call(not reload_gun.get_node("ReloadTimer").is_stopped(),"changing character model preserves a held gun reload")
	await world.get_tree().create_timer(0.4).timeout
	check.call(reload_gun.can_fire,"gun completes reload after Locker model change")
	actor.set_character_appearance(old_model,old_skin)
	world.playpen.clear_inventory(actor)
	actor.set_physics_process(true)
	training.set_physics_process(true)
	world._reset_position()
	await world.get_tree().create_timer(0.4).timeout
	world.cursor_released=true
	WindowFocus.set_active(false)
	Input.action_press(actor.input_prefix+"_move_forward")
	var before: Vector3=actor.position
	await world.get_tree().create_timer(0.2).timeout
	check.call(actor.position.distance_to(before)<0.15,"unfocused window rejects gameplay input")
	WindowFocus.set_active(true)
	check.call(not Input.is_action_pressed(actor.input_prefix+"_move_forward") and not world.cursor_released,"focus return releases stale keys and restores normal cursor ownership")
	world._reset_position()

static func _check_scrap_spectator(world: Node3D, check: Callable) -> void:
	var scrap=world.scrap
	check.call(not scrap.transition.visible,"Scrap fade starts hidden for a lobby resident")
	await scrap.transition.fade(1.0,false)
	check.call(not scrap.transition.visible and scrap.transition.veil.color.a==0.0,"nonparticipant cannot activate the Scrap fade")
	check.call(scrap.join_round("watch"),"spectator demo starts")
	scrap._update_coin()
	check.call(not scrap.coin_visual.visible,"spectator watches the coin on the jumbotron without a screen overlay")
	scrap.finish("SPECTATOR RETURN CHECK")
	var peak:=0.0
	var deadline:=Time.get_ticks_msec()+5000
	while scrap.state!=scrap.State.IDLE and Time.get_ticks_msec()<deadline:
		peak=maxf(peak,scrap.transition.veil.color.a)
		await world.get_tree().process_frame
	check.call(scrap.state==scrap.State.IDLE and peak==0.0 and not scrap.transition.visible,"watching a completed duel never fades the spectator screen")
	world._reset_position()
