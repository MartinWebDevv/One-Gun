extends Node
const Session = preload("res://tools/live_lobby_preview/session.gd")
var failures: Array[String] = []
var checks := 0

func check(value: bool, description: String) -> void:
	checks += 1
	if value: print("PREVIEW PASS: "+description)
	else:
		failures.append(description)
		push_error("PREVIEW FAIL: "+description)

func settle(frames := 3) -> void:
	for i in range(frames): await get_tree().physics_frame

func move_for(lab: Node3D, suffix: String, seconds: float) -> void:
	var action: String = lab.pilot.input_prefix+"_"+suffix
	Input.action_press(action)
	# Advance actual physics steps, independent of headless render-frame timing.
	for i in range(roundi(seconds*Engine.physics_ticks_per_second)):
		# Account hydration may rebuild InputMap; keep supplying the simulated held device.
		Input.action_press(action)
		await get_tree().physics_frame
	print("PREVIEW MOVE: ",suffix," at ",lab.pilot.position," held ",Input.is_action_pressed(action)," enabled ",lab.controls_enabled)
	Input.action_release(action)
	await settle()

func run(lab: Node3D) -> void:
	var settings := PlayerPrefs.snapshot()
	var rules := GameConfig.snapshot_for_lobby()
	var current: Node = get_tree().current_scene
	await settle()
	if OS.get_cmdline_user_args().has("--hideout-only"):
		await preload("res://tools/live_lobby_preview/hideout_validation.gd").new().run(lab,self)
		check(PlayerPrefs.snapshot()==settings and GameConfig.snapshot_for_lobby()==rules,"focused Hideout checks preserve preferences and live match rules")
		check(not NetworkManager.is_online(),"focused Hideout checks remain offline")
		print("FOCUSED HIDEOUT VALIDATION: "+JSON.stringify({"checks":checks,"failures":failures}))
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	check(lab.pilot.scene_file_path=="res://player.tscn","scene uses the unchanged real player.tscn")
	check(lab.pilot.character_model_id==str(settings.character_model_id) and lab.pilot.character_skin_id==str(settings.character_skin_id),"saved character and skin load on F6")
	check(lab.pilot.cosmetic_loadout==SupabaseManager.equipped_cosmetics(),"saved cosmetic loadout reaches the walking character")
	check(not lab.pilot.is_online and not NetworkManager.is_online(),"F6 does not open an online session")
	check(lab.multiplayer.multiplayer_peer is OfflineMultiplayerPeer,"multiplayer peer remains offline")
	check(lab.find_children("*","MultiplayerSpawner",true,false).is_empty() and lab.find_children("*","MultiplayerSynchronizer",true,false).is_empty(),"preview creates no replication nodes")
	check(lab.playpen != null,"contained Play Pen owns the preview combat supplies")
	check(ProjectSettings.get_setting("application/run/main_scene")=="res://app_bootstrap.tscn","normal project startup remains app_bootstrap")
	for sample in [[0.0,-0.6],[7.6,-0.4],[8.6,-0.2],[9.6,0.0],[12.0,0.0],[24.0,0.0]]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(sample[0],4,3),Vector3(sample[0],-2,3),1)
		# Use z=0 for radial tiers, avoiding the pilot at arrivals.
		query.from.z = 0
		query.to.z = 0
		var hit := lab.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and absf(hit.position.y-sample[1])<0.035,"supporting floor at radius %.1f / y %.1f" % sample)
	check(lab.pilot.position.z>30 and is_equal_approx(lab.station.doors[0].position.z,30),"pilot starts inside the recessed hallway behind wall-mounted doors")
	await move_for(lab,"move_forward",0.65)
	check(lab.pilot.position.z>30.3,"closed arrival doors hold the pilot in the hallway")
	await get_tree().create_timer(1.8).timeout
	await move_for(lab,"move_forward",3.2)
	check(lab.pilot.position.z<2 and lab.pilot.position.z> -7,"real controller walks from arrivals down the stairs into the pit")
	check(absf(lab.pilot.position.y-0.49)<0.2,"normal capsule stands on the sunken floor")
	await move_for(lab,"move_forward",1.0)
	check(lab.pilot.position.z < -9.6,"real controller climbs the concentric steps")
	lab.pilot.position = Vector3(23,1.12,5)
	lab.pilot.velocity = Vector3.ZERO
	await move_for(lab,"move_right",0.8)
	check(lab.pilot.position.x<26.3,"outer wall blocks the real controller")
	lab.pilot.position = Vector3(0,0.52,3)
	lab.pilot.velocity = Vector3.ZERO
	await settle(12)
	var charges: int = lab.pilot.dash_charges
	await move_for(lab,"dash",0.25)
	check(lab.pilot.dash_charges<charges and lab.pilot.position.z<0,"saved controller dash consumes a charge and moves")
	lab.session.rehearse("Private event")
	lab.session.accept()
	lab.session.simulate_confirmations()
	lab.session.start_match()
	await get_tree().create_timer(0.9).timeout
	lab.pilot.position = Vector3(23,1.12,0)
	lab.pilot.get_node("AimPivot").rotation = Vector3(0,-PI/2,0)
	await move_for(lab,"move_forward",0.5)
	check(lab.pilot.position.x>27.3,"open departure doorway admits the real player")
	lab.session.cancel()
	lab._reset_position()
	lab._open("pause")
	var before: Vector3 = lab.pilot.position
	await move_for(lab,"move_forward",0.15)
	check(lab.pilot.position.distance_to(before)<0.01,"preview menu suppresses gameplay movement")
	lab._open("")
	for model_id in PlayerSkinRegistry.MODEL_IDS:
		lab.pilot.set_character_appearance(model_id,"red")
		await settle(2)
		check(lab.pilot.character_model_id==model_id and lab.pilot.model_anim_player!=null,"real character rig and animations: "+model_id)
	lab.pilot.set_character_appearance("female","pink")
	check(lab.pilot.character_skin_id=="pink","public character color variants work")
	lab.pilot.set_character_appearance(str(settings.character_model_id),str(settings.character_skin_id))
	# Walk the entire front lane with the actual controller. No service should
	# capture a passer-by or require detouring around a console.
	lab.pilot.position = Vector3(-16.5,1.12,27)
	lab.pilot.velocity = Vector3.ZERO
	lab.pilot.get_node("AimPivot").rotation = Vector3.ZERO
	await settle(5)
	await move_for(lab,"move_forward",4.4)
	check(lab.pilot.position.z < -16 and absf(lab.pilot.position.x+16.5)<0.1,"west arcade has an uninterrupted full-length walking lane")
	check(lab.nearby.is_empty(),"passing the arcade does not enter service or party zones")
	for service in ["locker","prize_counter","profile","progression"]:
		var marker: Marker3D = lab.station.get_node(service.to_pascal_case()+"Approach")
		lab.pilot.position = Vector3(-18,1.12,marker.position.z)
		lab.pilot.velocity = Vector3.ZERO
		lab.pilot.get_node("AimPivot").rotation = Vector3(0,PI/2,0)
		await settle(4)
		await move_for(lab,"move_forward",0.38)
		check(lab.pilot.position.x < -20.9 and lab.nearby == [service],"walking into "+service+" selects only that service")
		var boom: SpringArm3D = lab.pilot.get_node("AimPivot/SpringArm3D")
		check(boom.get_hit_length()>3.8,"full gameplay camera boom fits at "+service)
		lab.station.set_active_service(service)
		check(lab.station.service_status[service].text=="INTERACT","nearby "+service+" receives an interaction cue")
		var position_before: Vector3 = lab.pilot.position
		var look_before: Vector3 = lab.pilot.get_node("AimPivot").rotation
		var interact := InputEventAction.new()
		interact.action = lab.pilot.input_prefix+"_interact"
		interact.pressed = true
		lab._input(interact)
		await settle(3)
		check(lab.native_page==service and is_instance_valid(lab.native_overlay),"saved Interact opens the physical "+service+" bay")
		lab._escape()
		await settle(4)
		check(lab.controls_enabled and lab.pilot.position.distance_to(position_before)<0.05 and lab.pilot.get_node("AimPivot").rotation.is_equal_approx(look_before),"closing "+service+" preserves position and view")
	# Party now lives beside Events; the two desks remain distinct destinations.
	lab.pilot.position = Vector3(-12.0,1.12,-22.2)
	lab.pilot.velocity = Vector3.ZERO
	lab.pilot.get_node("AimPivot").rotation = Vector3.ZERO
	await settle(4)
	await move_for(lab,"move_forward",0.15)
	check(lab.nearby==["party"],"relocated Party desk has a distinct interaction area beside Events")
	var party_interact := InputEventAction.new()
	party_interact.action = lab.pilot.input_prefix+"_interact"
	party_interact.pressed = true
	lab._input(party_interact)
	await settle(3)
	check(lab.ui.page=="party" and not lab.controls_enabled,"Party desk opens the simulated party controls")
	lab._escape()
	await settle(3)
	check(lab.ui.page.is_empty() and lab.controls_enabled,"closing Party returns control beside Events")
	# A wide/tall existing skin uses the same collision and camera paths.
	lab.pilot.set_character_appearance("eye_wizard","blue")
	lab.pilot.position = Vector3(-18,1.12,21)
	lab.pilot.velocity = Vector3.ZERO
	lab.pilot.get_node("AimPivot").rotation = Vector3(0,PI/2,0)
	await settle(4)
	await move_for(lab,"move_forward",0.55)
	check(lab.pilot.position.x < -22.1 and lab.nearby==["locker"],"larger existing character reaches the recessed Locker bay")
	lab.pilot.set_character_appearance(str(settings.character_model_id),str(settings.character_skin_id))
	lab.station.set_profile_identity("PREVIEW", "eye_wizard", "blue")
	check(_same_portrait(lab.station.identity_portrait.material_override.albedo_texture,PlayerSkinRegistry.load_portrait("blue","eye_wizard")),"Profile display supports the existing fixed-look character portrait")
	lab._update_identity()
	check(_same_portrait(lab.station.identity_portrait.material_override.albedo_texture,PlayerSkinRegistry.load_portrait(str(settings.character_skin_id),str(settings.character_model_id))),"Profile display restores the saved character without a preference write")
	lab.station.set_active_service("")
	check(lab.station.service_status.values().all(func(label): return label.text.is_empty()),"service cues clear when leaving the bays")
	for page in ["profile","prize_counter","progression","locker"]:
		lab._open(page)
		await settle(3)
		check(is_instance_valid(lab.native_overlay) and lab.native_page==page and not lab.controls_enabled,"physical kiosk opens existing "+page+" screen")
		lab._escape()
		await settle(3)
		check(not is_instance_valid(lab.native_overlay) and lab.controls_enabled,"closing "+page+" returns control to the room")
	lab._open("hub")
	lab._hub_destination("locker")
	await settle(3)
	lab._escape()
	await settle(3)
	check(lab.native_page=="hub","Locker opened from H returns to the Player Hub")
	lab._escape()
	await settle(3)
	var closed_overlays: Array[WeakRef]=[]
	for i in range(4):
		lab._open("locker")
		closed_overlays.append(weakref(lab.native_overlay))
		await settle(2)
		lab._escape()
		await settle(3)
	check(closed_overlays.all(func(ref): return ref.get_ref()==null) and lab.hub_layer.get_child_count()==0 and lab.find_children("*","SubViewport",true,false).is_empty(),"repeated native Locker open/cancel frees owned overlays and preview viewports")
	lab.session.start_search()
	check(not lab.session.start_search(),"duplicate rehearsal search is rejected")
	lab._open("locker")
	lab.session.tick(8.1)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_R
	event.pressed = true
	lab._input(event)
	check(lab.session.phase==Session.Phase.FOUND and lab.session.local_ready and lab.native_page=="locker","ready works over Locker without automatically launching or discarding selections")
	lab.session.start_match()
	lab.session.tick(4.1)
	check(lab.ui.page=="away" and lab.native_page=="locker","rehearsal completion keeps the real Locker until it closes")
	lab._escape()
	await settle(3)
	check(lab.ui.page=="away" and not lab.controls_enabled,"closing Locker reveals the return screen")
	lab._action("cancel",null)
	check(lab.ui.page=="away","stale cancel cannot dismiss the return screen")
	lab._action("return",null)
	for i in range(9): lab.session.add_friend()
	check(lab.guests.size()==9 and not lab.session.add_friend(),"ten demo party members with real character visuals")
	await get_tree().create_timer(3.8).timeout
	for guest in lab.guests:
		check(guest.find_child("Skeleton3D",true,false)!=null,"visitor uses an existing character rig")
	lab.session.set_local(2,99)
	check(lab.session.bots==0,"full lobby leaves no capacity for bots")
	for i in range(15):
		lab.session.start_search()
		lab.session.tick(8.1)
		lab.session.accept()
		lab.session.simulate_confirmations()
		lab.session.start_match()
		lab.session.tick(4.1)
		lab._action("return",null)
	check(lab.guests.size()==9 and lab.session.returns==16,"repeated simulated departures retain the same party")
	check(get_tree().current_scene==current,"no preview departure changes the scene")
	for i in range(9): lab.session.remove_friend()
	await settle(5)
	check(lab.guests.is_empty() and lab.visitor_tweens.is_empty(),"visitor removal releases nodes and animation tweens")
	await preload("res://tools/live_lobby_preview/playpen_validation.gd").new().run(lab,self)
	await preload("res://tools/live_lobby_preview/training_validation.gd").new().run(lab,self)
	await preload("res://tools/live_lobby_preview/hideout_validation.gd").new().run(lab,self)
	check(PlayerPrefs.snapshot()==settings,"automated previews and cancellation do not change saved preferences")
	check(GameConfig.snapshot_for_lobby()==rules,"rehearsals do not change live match rules")
	check(not NetworkManager.is_online(),"all kiosk/rehearsal tests leave networking offline")
	lab.low = true
	lab.apply_quality()
	check(is_equal_approx(lab.get_viewport().scaling_3d_scale,0.75) and not lab.station.environment.ssao_enabled,"Low preview scales the scene without saving settings")
	if OS.get_cmdline_user_args().has("--record-proof") and failures.is_empty():
		await capture_record_proof(lab)
	var report := {"checks":checks,"failures":failures,"scope":"Native F6 scene, real controller/skins, shared menus, contained local Play Pen combat and rehearsal lifecycle. No account transactions or live matches tested."}
	var file := FileAccess.open("res://tools/live_lobby_preview/artifacts/validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PREVIEW VALIDATION: "+JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

func _same_portrait(actual: Texture2D, expected: Texture2D) -> bool:
	if actual==null or expected==null or actual.get_size()!=expected.get_size(): return false
	var displayed := actual.get_image()
	var reference := expected.get_image()
	if displayed==null or reference==null: return false
	if displayed.is_compressed(): displayed.decompress()
	if reference.is_compressed(): reference.decompress()
	displayed.convert(Image.FORMAT_RGBA8)
	reference.convert(Image.FORMAT_RGBA8)
	return displayed.get_data()==reference.get_data()

func capture_record_proof(lab: Node3D) -> void:
	var capture: Node=load("res://tools/live_lobby_preview/capture.gd").new()
	add_child(capture)
	capture.output=ProjectSettings.globalize_path("res://tools/live_lobby_preview/artifacts/rendered_checks")
	DirAccess.make_dir_recursive_absolute(capture.output)
	lab.low=false
	lab.apply_quality()
	lab.playpen.set_sparring_mode("off")
	capture.place(lab,Vector3(-1,-0.11,-56.5),Vector3(-0.06,PI/2,0))
	await capture.snap(lab,"39_completed_run_wall_board")
	lab.training.board_tab="lobby"
	lab._open("course_board")
	await capture.snap(lab,"40_completed_run_lobby")
	lab._action("course_tab","personal")
	await capture.snap(lab,"41_completed_run_personal")
	lab._open("")
