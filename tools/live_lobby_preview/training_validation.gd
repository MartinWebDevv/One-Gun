extends RefCounted
const Space = preload("res://tools/live_lobby_preview/training_space.gd")
const PenSpace = preload("res://tools/live_lobby_preview/playpen_space.gd")

func run(lab: Node3D, test: Node) -> void:
	var training: Node=lab.training
	var player: CharacterBody3D=lab.pilot
	var scene := lab.get_tree().current_scene
	lab.playpen.set_sparring_mode("off")
	lab._open("")
	player.position=Vector3(-18,1.12,-19)
	player.velocity=Vector3.ZERO
	player.get_node("AimPivot").rotation=Vector3.ZERO
	await test.settle(4)
	await test.move_for(lab,"move_forward",0.85)
	test.check(player.position.z < -26.5 and lab.nearby.is_empty(),"corner passage remains clear with the Hub reaching the north wall")
	var hub: Node3D=lab.station.find_child("PlayerHubArcade",true,false)
	var dispatch: Node3D=lab.station.find_child("EventsAndParty",true,false)
	var backing: MeshInstance3D=hub.get_node("ServiceBacking")
	var collision: BoxShape3D=backing.get_child(0).get_child(0).shape
	test.check(is_equal_approx(collision.size.x,59.3) and hub.position.x< -26.3,"Hub backing extends fully between north/south wall faces and sits against the west wall")
	test.check(dispatch.position.z< -29.4,"combined Party/Events backing is against the north wall")
	var hub_floor: Node=lab.station.find_child("HubServiceFloor",true,false)
	var party_floor: Node=lab.station.find_child("DispatchServiceFloor",true,false)
	test.check(hub_floor.get_child(1).material_override==party_floor.get_child(1).material_override and hub_floor.get_child(2).material_override==party_floor.get_child(2).material_override,"both wings share the same checker tile materials and grid")
	test.check(not lab.station.find_child("SupplySocket",true,false) and not lab.station.find_child("RangeBorrowStand",true,false),"all old loot podiums and front-hall borrowing stands are removed")
	var grounded := true
	for slot in lab.playpen.slots:
		if not slot.enabled or slot.kind=="power": continue
		var obj: Node3D=slot.stock.get_ref()
		var bottom := INF
		for mesh in obj.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh!=null and mesh.is_visible_in_tree():
				var bounds: AABB=mesh.global_transform*mesh.get_aabb()
				bottom=minf(bottom,bounds.position.y)
		if absf(bottom-(PenSpace.FLOOR_Y+0.025))>=0.035: print("FLOOR ORIGIN: ",slot.kind," / ",slot.identity," / bottom ",bottom," / root ",obj.position)
		grounded=grounded and absf(bottom-(PenSpace.FLOOR_Y+0.025))<0.035
		grounded=grounded and absf(obj.position.x-slot.position.x)<0.01 and absf(obj.position.z-slot.position.z)<0.01
	test.check(grounded,"weapon/item visuals rest on the floor in their original grid coordinates")
	player.position=Vector3(17,1.12,-16)
	player.velocity=Vector3.ZERO
	player.get_node("AimPivot").rotation=Vector3.ZERO
	await test.move_for(lab,"move_forward",1.1)
	test.check(player.position.z < -26 and not player.in_playpen(),"main hall stays open up to the wall-aligned Play Pen doorway")
	test.check(Space.DISTANCES==[5,10,15,25,30,40,50,75,90,100],"target sequence matches all requested distances exactly")
	# Independent distance settings, exact endpoints, and wraparound in every lane.
	for lane in range(3):
		training.set_distance(lane,0)
		var other: Vector3=training.targets[(lane+1)%3].position
		for index in range(Space.DISTANCES.size()):
			test.check(is_equal_approx(training.targets[lane].position.x-Space.FIRING_X,Space.DISTANCES[index]),"lane %d target is at %d metres" % [lane+1,Space.DISTANCES[index]])
			training.cycle_distance(lane)
		test.check(training.range_indices[lane]==0 and training.targets[(lane+1)%3].position==other,"lane distance wraps to 5 metres without moving its neighbor")
	# Walk the actual doorway from the arena to the new range room.
	player.position=Vector3(38,-0.11,-55)
	player.velocity=Vector3.ZERO
	player.get_node("AimPivot").rotation=Vector3(0,-PI/2,0)
	await test.settle(4)
	await test.move_for(lab,"move_forward",1.15)
	test.check(player.position.x>48 and player.in_playpen(),"range side doorway is passable and retains Play Pen membership")
	player.position=Vector3(46.3,-0.11,-39.2)
	player.velocity=Vector3.ZERO
	await test.settle(5)
	test.check(lab.nearby.has("range_0"),"lane console registers the pilot using its physical interaction area")
	var interact := InputEventAction.new()
	interact.action="p1_interact"
	interact.pressed=true
	lab._input(interact)
	test.check(training.range_indices[0]==1,"saved Interact cycles the nearby lane target")
	lab._open("range_settings")
	test.check(lab.ui.page=="range_settings" and not lab.controls_enabled,"distance settings are available from a controller-focusable menu")
	lab._action("range_distance",Vector2i(2,9))
	test.check(training.range_indices[2]==9,"range menu can directly select 100 metres for a chosen lane")
	lab._open("")
	var gun: Node=lab.playpen.slots[0].stock.get_ref()
	player.position=Vector3(52,-0.11,-43)
	await test.settle(3)
	player._manual_pickup_request_active=true
	gun.pick_up(player)
	player._manual_pickup_request_active=false
	player.active_slot="weapon"
	player._update_active_slot_and_visuals()
	training.reset_hits()
	for lane in range(3):
		training.set_distance(lane,0)
		player.position=Vector3(Space.FIRING_X-1,-0.11,Space.LANE_Z[lane])
		player.velocity=Vector3.ZERO
		player.get_node("AimPivot").rotation=Vector3(0,-PI/2,0)
		await test.settle(5)
		await lab.get_tree().create_timer(2.05).timeout
		player.set_physics_process(false)
		var camera: Camera3D=player.get_gameplay_camera()
		var before := camera.global_transform
		camera.look_at(training.targets[lane].position+Vector3.UP*1.5,Vector3.UP)
		gun.try_fire()
		await lab.get_tree().create_timer(0.15).timeout
		test.check(training.hits[lane]==1 and not training.targets[lane].is_eliminated,"real gunfire registers a reusable wooden target hit in lane %d" % (lane+1))
		camera.global_transform=before
		lab._sync_controls()
	# The real projectile can travel the longest lane; do not substitute a ray-hit stub.
	training.set_distance(1,9)
	var bullet: RigidBody3D=load("res://bullet.tscn").instantiate()
	bullet.position=Vector3(Space.FIRING_X,0.3,-55)
	lab.add_child(bullet)
	bullet.launch(Vector3.RIGHT,player)
	await lab.get_tree().create_timer(0.7).timeout
	test.check(training.hits[1]==2 and not is_instance_valid(bullet),"real projectile travels 100 metres inside the range and hits its target")
	lab.playpen.clear_inventory(player)
	# Entering through the finish never starts a run.
	player.position=Vector3(-7,-0.11,-70.75)
	player.velocity=Vector3.ZERO
	player.get_node("AimPivot").rotation=Vector3(0,PI/2,0)
	await test.settle(3)
	await test.move_for(lab,"move_forward",0.65)
	test.check(not training.running and training.last_time<0,"walking backward through the finish door cannot start or complete a trial")
	training.restart_trial()
	await _walk(lab,test,Vector2(-27,-42.25))
	test.check(training.running and training.next_gate==1,"walking through the single start door starts the flow-course clock")
	training._gate_entered(player,6)
	test.check(training.running and training.last_time<0,"finish is rejected until every ordered checkpoint is cleared")
	lab._open("pause")
	var paused: float=training.elapsed
	await lab.get_tree().create_timer(0.2).timeout
	test.check(is_equal_approx(training.elapsed,paused),"time-trial clock pauses while movement is paused in a menu")
	lab._open("")
	await _jump_west(lab,test,1.5)
	test.check(player.position.x < -40 and training.next_gate==2,"normal One Gun jump clears the full-width vault deck")
	var pre_fall: float=training.elapsed
	player.position=Vector3(-50,-2.5,-42.25)
	player.velocity=Vector3.ZERO
	await test.settle(3)
	test.check(training.falls==1 and training.elapsed>=pre_fall+2 and player.position.distance_to(Space.RECOVERY[1])<0.2,"gap fall adds two seconds and recovers the last checkpoint")
	await test.settle(8)
	await _walk(lab,test,Vector2(-43,-42.25))
	await _jump_west(lab,test,1.65)
	test.check(player.position.x < -57 and training.falls==1,"unchanged jump arc clears the eight-metre gap onto its wide landing")
	for at in [Vector2(-68,-42.25),Vector2(-76,-45),Vector2(-82,-51),Vector2(-84,-57),Vector2(-82,-64),Vector2(-76,-70.75),Vector2(-60,-70.75)]: await _walk(lab,test,at)
	test.check(training.next_gate==5,"wide sweep advances the turn and return-straight checkpoints")
	for at in [Vector2(-57,-71.8),Vector2(-48,-70.2),Vector2(-37,-70.75)]: await _walk(lab,test,at)
	test.check(training.next_gate==6,"broad lines around low cover reach the final checkpoint")
	var peak: float=await _walk(lab,test,Vector2(-22,-70.75))
	test.check(peak>0.5,"controller automatically steps over the 0.4 metre flow stairs without a jump input")
	var charges_before: int=player.dash_charges
	Input.action_press("p1_dash")
	await test.move_for(lab,"move_forward",0.25)
	Input.action_release("p1_dash")
	test.check(player.dash_charges<charges_before and player.position.x> -18,"finish runway accommodates a real six-metre dash burst")
	await _walk(lab,test,Vector2(-7,-70.75))
	test.check(not training.running and training.last_time>0 and training.best==training.last_time,"complete controller-driven flow run records its result at the single exit")
	test.check(training.records.personal_best(training.records_bucket(training.assisted),training.viewer_id())==roundi(training.last_time*1000),"actual completed run reaches the current viewer's personal record")
	test.check(player.in_playpen() and lab.get_tree().current_scene==scene,"course and finish remain inside this same Play Pen scene")
	await preload("res://tools/live_lobby_preview/course_records_validation.gd").new().run(lab,test)
	# Leaving through the entrance or resetting cannot submit an incomplete time.
	var best: float=training.best
	training.restart_trial()
	await _walk(lab,test,Vector2(-16,-42.25))
	await _walk(lab,test,Vector2(-7,-42.25))
	test.check(not training.running and training.best==best,"backtracking through the start cancels the run without replacing the best")
	for lane in range(3): training.set_distance(lane,0)
	training.reset_hits()
	lab._reset_position()
	lab.playpen.set_sparring_mode("target")

func _walk(lab: Node3D, test: Node, at: Vector2) -> float:
	var player: CharacterBody3D=lab.pilot
	var deadline := Time.get_ticks_msec()+6000
	var peak: float=player.position.y
	while Vector2(player.position.x,player.position.z).distance_to(at)>0.22 and Time.get_ticks_msec()<deadline:
		var direction := at-Vector2(player.position.x,player.position.z)
		player.get_node("AimPivot").rotation=Vector3(0,atan2(-direction.x,-direction.y),0)
		Input.action_press("p1_move_forward")
		await lab.get_tree().physics_frame
		peak=maxf(peak,player.position.y)
	Input.action_release("p1_move_forward")
	await test.settle(3)
	test.check(Vector2(player.position.x,player.position.z).distance_to(at)<0.5,"course navigation reaches "+str(at))
	return peak

func _jump_west(lab: Node3D, test: Node, duration: float) -> void:
	lab.pilot.get_node("AimPivot").rotation=Vector3(0,PI/2,0)
	Input.action_press("p1_jump")
	await test.move_for(lab,"move_forward",duration)
	Input.action_release("p1_jump")
	await test.settle(3)
