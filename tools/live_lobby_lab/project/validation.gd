extends Node
const Session = preload("res://session.gd")
const Station = preload("res://station.gd")
var failures: Array[String] = []
var checks := 0

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error("LAB FAIL: "+description)
	else:
		print("LAB PASS: "+description)

func settle(frames := 3) -> void:
	for i in range(frames): await get_tree().physics_frame

func run(lab: Node3D) -> void:
	await settle()
	check(lab.multiplayer.multiplayer_peer is OfflineMultiplayerPeer,"engine uses only its default offline peer")
	var autoload_count := 0
	for property in ProjectSettings.get_property_list():
		if str(property.name).begins_with("autoload/"): autoload_count += 1
	check(autoload_count==0,"standalone project registers zero autoloads")
	var forbidden_nodes := 0
	for node in get_tree().root.find_children("*","",true,false):
		if node is HTTPRequest or node is MultiplayerSpawner or node is MultiplayerSynchronizer:
			forbidden_nodes += 1
	check(forbidden_nodes==0,"scene has no HTTP requests or multiplayer replication nodes")
	check(ProjectSettings.get_setting("application/config/custom_user_dir_name")=="OneGunLiveLobbyLab","separate user-data namespace")
	check(lab.station.targets.size()==3,"three local light-trainer targets")
	check(lab.pilot.CAPSULE_HEIGHT==2.3266993 and lab.pilot.CAPSULE_RADIUS==0.495,"player capsule matches live dimensions")
	check(lab.pilot.boom.spring_length==4.0 and lab.pilot.camera.fov==75.0,"normal third-person boom and FOV")
	check(lab.low and is_equal_approx(lab.get_viewport().scaling_3d_scale,0.75),"Low is the default with 75 percent render scale")
	check(not lab.station.environment.glow_enabled and not lab.station.environment.ssao_enabled,"Low disables expensive optional effects")
	for sample in [[6.2,-0.4],[7.0,-0.2],[7.8,0.0],[9.0,0.0]]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(sample[0],4,0),Vector3(sample[0],-2,0),1)
		var floor_hit := lab.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not floor_hit.is_empty() and absf(floor_hit.position.y-sample[1])<0.03,"floor tier at radius %.1f supports height %.1f" % sample)
	lab._action("enter",null)
	await get_tree().create_timer(1.0).timeout
	check(lab.station.doors[0].position.x < -4.7,"arrival doors open before the first movement route")
	Input.action_press("p1_forward")
	await get_tree().create_timer(1.08).timeout
	Input.action_release("p1_forward")
	await settle()
	check(lab.pilot.position.z<5.5,"real capsule can walk from arrival stairs into central pit")
	check(absf(lab.pilot.position.y+0.6)<0.15,"pit floor supports the pilot at minus 0.6 metres")
	Input.action_press("p1_forward")
	await get_tree().create_timer(0.95).timeout
	Input.action_release("p1_forward")
	await settle()
	check(lab.pilot.position.z < -5.8,"pilot can climb concentric steps toward event terminal")
	# Wall collision and dash travel use actual physics, not formula-only tests.
	lab.pilot.position = Vector3(14,0.1,6)
	await settle(8)
	Input.action_press("p1_right")
	await get_tree().create_timer(0.7).timeout
	Input.action_release("p1_right")
	check(lab.pilot.position.x < 16.6,"outer wall blocks real player movement")
	lab.pilot.position = Vector3(0,0.1,0)
	lab.pilot.velocity = Vector3.ZERO
	await settle(15)
	Input.action_press("p1_dash")
	await settle(2)
	Input.action_release("p1_dash")
	await get_tree().create_timer(0.25).timeout
	check(lab.pilot.position.z < -4.5 and lab.pilot.charges[0]>0,"dash moves the player and consumes a charge")
	lab._open("pause")
	var before: Vector3 = lab.pilot.position
	Input.action_press("p1_forward")
	await settle(8)
	Input.action_release("p1_forward")
	check(Vector2(lab.pilot.position.x,lab.pilot.position.z).distance_to(Vector2(before.x,before.z))<0.02,"station overlay suppresses movement")
	lab._open("locker")
	lab._action("preview_mask",Color("58c9db"))
	lab._open("")
	check(lab.pilot.avatar.mask_mat.albedo_color==lab.session.mask_color,"cancelled cosmetic preview rolls back")
	lab._open("locker")
	lab._action("preview_mask",Color("e080b9"))
	lab._action("confirm_mask",null)
	check(lab.session.mask_color==Color("e080b9"),"confirm keeps the mask only in the lab session")
	for i in range(9): lab.session.add_friend()
	check(lab.guests.size()==9 and not lab.session.add_friend(),"one pilot plus nine simulated guests respects ten-actor capacity")
	lab.session.set_local(2,99)
	check(lab.session.local_humans==2 and lab.session.bots==8,"local setup clamps two humans plus eight bots")
	lab.session.start_search()
	check(not lab.session.start_search(),"duplicate queue start is ignored")
	lab.session.tick(8.1)
	lab._open("locker")
	var accept := InputEventKey.new()
	accept.physical_keycode = KEY_R
	accept.pressed = true
	lab._input(accept)
	check(lab.session.phase==Session.Phase.DEPARTING and lab.ui.page.is_empty(),"global ready shortcut accepts from inside locker")
	await get_tree().create_timer(0.9).timeout
	lab.pilot.position = Vector3(13,0.1,0)
	lab.pilot.look.rotation = Vector3(0,-PI/2,0)
	await settle(3)
	Input.action_press("p1_forward")
	await get_tree().create_timer(0.6).timeout
	Input.action_release("p1_forward")
	check(lab.pilot.position.x>17.2,"accepted departure leaves an unobstructed physical tunnel")
	lab.session.tick(4.1)
	check(lab.session.phase==Session.Phase.AWAY and lab.ui.page=="away","departure ends at the local destination rehearsal")
	lab._action("cancel",null)
	check(lab.ui.page=="away","stale cancel input cannot dismiss the required return screen")
	lab._action("return",null)
	check(lab.guests.size()==9 and lab.session.mask_color==Color("e080b9") and lab.session.returns==1,"return preserves party and confirmed mask")
	lab.session.start_search()
	lab.session.cancel()
	lab.session.tick(100)
	check(lab.session.phase==Session.Phase.HOME,"cancelled search cannot fire a late ready check")
	lab.session.start_search()
	lab.session.tick(8.1)
	lab.session.tick(15.1)
	check(lab.session.phase==Session.Phase.HOME,"ready timeout returns safely home")
	lab.session.rehearse("Private event")
	lab.session.accept()
	lab.session.cancel()
	check(lab.session.phase==Session.Phase.HOME,"departure countdown can be cancelled")
	# Aim an actual engine camera at the target; verify ray/physics scoring.
	lab.pilot.position = Vector3(10.5,0.05,-10)
	lab.pilot.velocity = Vector3.ZERO
	lab.pilot.look.rotation = Vector3.ZERO
	await settle(8)
	lab.pilot.camera.look_at(lab.station.targets[1].global_position,Vector3.UP)
	lab._fire_trainer()
	check(lab.session.shots==1 and lab.session.hits==1,"light trainer scores an actual line-of-sight target ray")
	# Stabilize all visitor/target/door tweens before comparing node counts.
	lab._open("pause")
	await get_tree().create_timer(3).timeout
	var home_nodes := get_tree().get_node_count()
	var home_objects := Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in range(40):
		lab.session.rehearse("Local + bots")
		lab.session.accept()
		lab.session.tick(5)
		lab._action("return",null)
		lab._open("pause")
		await settle(2)
	await get_tree().create_timer(1).timeout
	check(get_tree().get_node_count()==home_nodes,"40 departure-return rehearsals retain a stable node count")
	check(Performance.get_monitor(Performance.OBJECT_COUNT)<=home_objects+10,"40 cycles do not retain extra scene objects")
	for i in range(9): lab.session.remove_friend()
	await settle()
	check(lab.guests.is_empty() and lab.visitor_tweens.is_empty(),"all simulated visitors and their tween handles can be removed")
	var base_nodes := get_tree().get_node_count()
	var mem_start := Performance.get_monitor(Performance.MEMORY_STATIC)
	for i in range(5):
		var probe := Station.new()
		add_child(probe)
		await settle(2)
		probe.queue_free()
		await settle(3)
	check(get_tree().get_node_count()==base_nodes,"five station create/free cycles release every scene node")
	var mem_growth := Performance.get_monitor(Performance.MEMORY_STATIC)-mem_start
	check(mem_growth < 4000000,"station create/free memory growth stays below 4 MB after cached resources")
	print("LAB RESULT: %d checks, %d failures; station memory delta %d bytes" % [checks,failures.size(),int(mem_growth)])
	get_tree().quit(0 if failures.is_empty() else 1)
