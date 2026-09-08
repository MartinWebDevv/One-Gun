extends Node
## Screenshots use player.tscn's gameplay camera, with its normal saved FOV/boom.
var output: String

func run(lab: Node3D) -> void:
	output = ProjectSettings.globalize_path("res://tools/live_lobby_preview/artifacts")
	if OS.get_cmdline_user_args().has("--saved"): output += "/saved_quality"
	DirAccess.make_dir_recursive_absolute(output)
	lab.get_window().mode = Window.MODE_WINDOWED
	lab.get_window().size = Vector2i(1920,1080)
	lab.low = not OS.get_cmdline_user_args().has("--saved")
	lab.apply_quality()
	await get_tree().create_timer(1.2).timeout
	if OS.get_cmdline_user_args().has("--scrap-size-only"):
		await scrap_size_views(lab)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--hideout-profile-only"):
		await hideout_lifetimes(lab)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--hideout-revision"):
		await hideout_revision(lab)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--range-menu-only"):
		await range_menu_only(lab)
		return
	if OS.get_cmdline_user_args().has("--flow-only"):
		await flow_views(lab)
		get_tree().quit()
		return
	lab.pilot.set_physics_process(false)
	await arrival_views(lab)
	place(lab,Vector3(0,0.49,5),Vector3(-0.12,0,0))
	await snap(lab,"02_central_pit")
	place(lab,Vector3(2.0,0.49,0),Vector3(-0.12,PI/2,0))
	await snap(lab,"03_service_arcade")
	place(lab,Vector3(-20.7,1.09,21),Vector3(-0.1,PI/2,0))
	await snap(lab,"04_locker_bay")
	place(lab,Vector3(-20.7,1.09,7),Vector3(-0.1,PI/2,0))
	await snap(lab,"05_prize_counter")
	place(lab,Vector3(-20.7,1.09,-7),Vector3(-0.1,PI/2,0))
	await snap(lab,"14_profile_bay")
	place(lab,Vector3(-20.7,1.09,-21),Vector3(-0.1,PI/2,0))
	await snap(lab,"15_progression_bay")
	lab._open("hub")
	await snap(lab,"06_player_hub")
	lab._hub_destination("locker")
	await snap(lab,"07_real_locker")
	lab.session.start_search()
	lab.session.tick(8.1)
	await snap(lab,"08_ready_in_locker")
	lab.session.cancel()
	lab._escape()
	lab._escape()
	lab.pilot.set_physics_process(false)
	for i in range(9): lab.session.add_friend()
	await get_tree().create_timer(4.0).timeout
	place(lab,Vector3(0,1.09,14),Vector3(-0.12,0,0))
	await snap(lab,"09_full_party")
	await profile(lab)
	place(lab,Vector3(2.0,0.49,0),Vector3(-0.12,PI/2,0))
	await snap(lab,"16_occupied_arcade")
	await profile(lab,"_arcade")
	# Fixed-look character support is exercised in memory, without equipping or granting inventory.
	lab.pilot.set_character_appearance("eye_wizard","blue")
	place(lab,Vector3(-20.7,1.09,21),Vector3(-0.1,PI/2,0))
	await snap(lab,"10_existing_character_skin")
	lab.pilot.set_character_appearance(str(PlayerPrefs.get_setting("character_model_id")),str(PlayerPrefs.get_setting("character_skin_id")))
	place(lab,Vector3(19,1.09,3),Vector3(-0.08,-1.3,0))
	lab.session.rehearse("Private event")
	lab.session.accept()
	lab.session.simulate_confirmations()
	lab.session.start_match()
	await get_tree().create_timer(1.0).timeout
	await snap(lab,"11_departures")
	lab.session.cancel()
	place(lab,Vector3(-6,1.09,-16),Vector3(-0.08,0,0))
	await snap(lab,"17_party_and_events")
	place(lab,Vector3(17,1.09,-18),Vector3(-0.08,0,0))
	await snap(lab,"12_playpen_entry")
	place(lab,Vector3(17,1.09,-27),Vector3(-0.06,0,0))
	await snap(lab,"18_playpen_hall")
	place(lab,Vector3(17,-0.11,-41),Vector3(-0.03,0,0))
	await snap(lab,"19_playpen_arena")
	await profile(lab,"_playpen")
	place(lab,Vector3(-0.5,-0.11,-64),Vector3(-0.1,0,0))
	await snap(lab,"20_playpen_armory")
	place(lab,Vector3(53,-0.11,-55),Vector3(-0.07,-PI/2,0))
	lab.playpen.sync_actor(lab.pilot)
	var range_gun: Node=lab.playpen.slots[23].stock.get_ref()
	lab.pilot._manual_pickup_request_active=true
	range_gun.pick_up(lab.pilot)
	lab.pilot._manual_pickup_request_active=false
	lab.pilot.active_slot="weapon"
	lab.pilot._update_active_slot_and_visuals()
	lab.pilot._play_anim("idle_pistol",true)
	await snap(lab,"21_firing_range_with_gun")
	await profile(lab,"_range")
	lab.training.set_distance(1,9)
	await snap(lab,"24_range_100_metres")
	lab.training.set_distance(1,0)
	lab._open("range_settings")
	await snap(lab,"25_range_controls")
	lab._open("")
	place(lab,Vector3(-14,1.09,-15),Vector3(-0.1,0.56,0))
	await snap(lab,"22_clear_kiosk_corner")
	place(lab,Vector3(48,-0.11,-39),Vector3(-0.06,-1.2,0))
	await snap(lab,"23_range_rear_walkway")
	place(lab,Vector3(-3,-0.11,-42.25),Vector3(-0.08,PI/2,0))
	await snap(lab,"26_agility_start_door")
	place(lab,Vector3(-18,-0.11,-42.25),Vector3(-0.1,PI/2,0))
	lab.training.start_trial()
	await snap(lab,"27_agility_launch")
	await profile(lab,"_agility")
	place(lab,Vector3(-62,-0.11,-70.75),Vector3(-0.13,-PI/2,0))
	await snap(lab,"28_agility_corner_cuts")
	lab.training.cancel_trial()
	place(lab,Vector3(-3,-0.11,-70.75),Vector3(-0.08,PI/2,0))
	await snap(lab,"29_agility_exit")
	await flow_views(lab,false)
	lab.playpen.clear_inventory(lab.pilot)
	place(lab,Vector3(0,0.49,5),Vector3(-0.12,0,0))
	lab._open("local")
	lab.get_window().size = Vector2i(1280,720)
	await snap(lab,"13_setup_720p")
	get_tree().quit()

func place(lab: Node3D, position: Vector3, look: Vector3) -> void:
	lab.pilot.set_physics_process(false)
	lab.pilot.position = position
	lab.pilot.velocity = Vector3.ZERO
	lab.pilot.get_node("AimPivot").rotation = look
	lab.pilot.get_node("CharacterModel").rotation.y = look.y+PI

func snap(lab: Node3D, filename: String) -> void:
	lab.ui.toast_left = 0
	lab.ui.toast.visible = false
	await get_tree().create_timer(1.1).timeout
	for i in range(4): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := lab.get_viewport().get_texture().get_image()
	var result := img.save_png(output+"/"+filename+".png")
	assert(result==OK,"Screenshot save failed")
	print("PREVIEW CAPTURE: "+filename)

func profile(lab: Node3D, suffix := "") -> void:
	await get_tree().create_timer(1).timeout
	var frame_times: Array[float] = []
	var worst_frame: Dictionary={}
	var worst_ms:=0.0
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec()-start<6000000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var ms: float=(now-previous)/1000.0
		frame_times.append(ms)
		if ms>worst_ms:
			worst_ms=ms
			worst_frame={"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0}
		previous = now
	frame_times.sort()
	var report := {
		"view":{"":"Occupied central pit","_arcade":"Service arcade","_playpen":"Play Pen","_range":"Firing range","_agility":"Agility course"}.get(suffix,suffix),
		"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),
		"preset":"Low preview" if lab.low else "Saved quality",
		"window_pixels":str(lab.get_window().size),
		"render_scale":lab.get_viewport().scaling_3d_scale,
		"character_nodes":1+lab.guests.size()+lab.resident_visuals.size()+lab.scrap.fighters.filter(func(actor):return actor!=lab.pilot).size()+1,
		"scrap_state":lab.scrap.state,
		"active_3d_views":lab.scrap.split_views.size() if lab.scrap.split_layer else 1,
		"practice_supplies":lab.playpen.slots.size(),
		"range_targets":3,
		"sample_seconds":6,
		"frames":frame_times.size(),
		"frame_ms_median":frame_times[frame_times.size()/2],
		"frame_ms_p95":frame_times[int(frame_times.size()*0.95)],
		"frame_ms_max":frame_times.back(),
		"worst_frame_cpu":worst_frame,
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),
		"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"nodes":get_tree().get_node_count(),
		"scope":"Six-second development GPU sample of the stated view and roster. Does not establish weaker-laptop, sustained combat, live-network or full map-transition performance."
	}
	var file := FileAccess.open(output+"/render_profile"+suffix+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PREVIEW RENDER PROFILE: "+JSON.stringify(report))

func range_menu_only(lab: Node3D) -> void:
	place(lab,Vector3(53,-0.11,-55),Vector3(-0.07,-PI/2,0))
	lab.playpen.sync_actor(lab.pilot)
	lab.training.start_trial()
	lab._open("range_settings")
	await snap(lab,"25_range_controls")
	assert(not lab.playpen.hud.visible,"Inventory HUD overlaps range menu")
	assert(not lab.training.hud.visible,"Trial HUD overlaps range menu")
	lab._open("")
	await get_tree().create_timer(0.3).timeout
	assert(lab.playpen.hud.visible,"Inventory HUD not restored after menu")
	assert(lab.training.hud.visible,"Trial HUD not restored after menu")
	print("PREVIEW MENU HUD: hidden during menu, restored on close")
	get_tree().quit()

func arrival_views(lab: Node3D) -> void:
	place(lab,Vector3(0,2.29,35.5),Vector3(-0.08,0,0))
	if lab.station.arrival_tween: lab.station.arrival_tween.kill()
	for i in range(2): lab.station.doors[i].position.x=-2.15+i*4.3
	lab.station.open_arrivals(2.5)
	await snap(lab,"00_arrival_waiting")
	lab.station.open_arrivals(0)
	await snap(lab,"01_arrivals")

func flow_views(lab: Node3D, include_arrivals := true) -> void:
	lab.training.cancel_trial()
	lab.playpen.clear_inventory(lab.pilot)
	if include_arrivals: await arrival_views(lab)
	place(lab,Vector3(0,1.09,21),Vector3(-0.06,PI,0))
	await snap(lab,"30_arrival_wall_threshold")
	place(lab,Vector3(-18.6,1.09,-22),Vector3(-0.25,0.5,0))
	await snap(lab,"31_corner_wall_joint")
	place(lab,Vector3(10,1.09,0),Vector3(-0.06,PI/2,0))
	await snap(lab,"32_wall_to_wall_hub")
	place(lab,Vector3(-43,-0.11,-42.25),Vector3(-0.13,PI/2,0))
	await snap(lab,"33_jump_landing")
	place(lab,Vector3(-74,-0.11,-43),Vector3(-0.08,0.65,0))
	await snap(lab,"34_sweeping_turn")
	place(lab,Vector3(-62,-0.11,-70.75),Vector3(-0.1,-PI/2,0))
	await snap(lab,"28_agility_corner_cuts")
	place(lab,Vector3(-1,-0.11,-56.5),Vector3(-0.06,PI/2,0))
	await snap(lab,"35_lobby_record_board")
	lab.training.board_tab="lobby"
	lab._open("course_board")
	await snap(lab,"36_lobby_times_page")
	lab._action("course_tab","personal")
	await snap(lab,"37_personal_best_page")
	lab._action("course_tab","world")
	await snap(lab,"38_world_times_page")
	lab._open("")

func hideout_revision(lab: Node3D) -> void:
	place(lab,Vector3(0,1.09,17),Vector3(-0.08,0.25,0))
	await snap(lab,"50_warm_hideout")
	lab._open("events")
	await snap(lab,"51_game_board")
	lab._open("private")
	await snap(lab,"52_private_by_default")
	lab._open("")
	for i in range(2): lab.session.add_friend()
	lab._open("join")
	await snap(lab,"53_join_together")
	lab._open("")
	place(lab,Vector3(17,-0.11,-68),Vector3(-0.06,0,0))
	await snap(lab,"54_scrap_yard_entrance")
	place(lab,Vector3(17,-0.11,-87.5),Vector3(-0.08,0,0))
	await snap(lab,"55_scrap_yard_stands")
	lab.scrap.join_round("solo")
	await snap(lab,"56_coin_call")
	lab.scrap.choose("heads",lab.pilot.actor_id)
	await snap(lab,"57_coin_flip")
	await get_tree().create_timer(3.0).timeout
	await snap(lab,"58_scrap_round")
	lab.scrap.leave()
	lab.scrap.join_round("local")
	await snap(lab,"59_local_split_screen")
	lab.scrap.choose("tails",lab.scrap.fighters[1].actor_id)
	await snap(lab,"61_shared_coin")
	await get_tree().create_timer(4.0).timeout
	await snap(lab,"62_split_combat")
	await profile(lab,"_scrap_split")
	lab.scrap.leave()
	place(lab,Vector3(1,0.49,5),Vector3(-0.1,-0.25,0))
	await snap(lab,"60_trickshot_toss")
	for i in range(7): lab.session.add_friend()
	await get_tree().create_timer(4).timeout
	place(lab,Vector3(0,1.09,16),Vector3(-0.1,0.3,0))
	await profile(lab,"_hideout_revision")
	lab.scrap.join_round("watch")
	await get_tree().create_timer(5.2).timeout
	place(lab,Vector3(-0.1,-0.11,-99),Vector3(-0.08,-0.65,0))
	await profile(lab,"_scrap_spectating")
	lab.scrap.leave()

func hideout_lifetimes(lab: Node3D) -> void:
	for i in range(9): lab.session.add_friend()
	await get_tree().create_timer(5).timeout
	place(lab,Vector3(0,1.09,16),Vector3(-0.1,0.3,0))
	await profile(lab,"_low_repeat")
	var checkpoints: Array[Dictionary]=[]
	for i in range(6):
		lab.scrap.join_round("local")
		lab.scrap.choose("heads",lab.scrap.fighters[1].actor_id)
		lab.scrap.time_left=0; lab.scrap._process(0.01)
		lab.scrap.time_left=0; lab.scrap._process(0.01)
		await get_tree().create_timer(0.7).timeout
		lab.scrap.leave()
		await get_tree().create_timer(0.7).timeout
		checkpoints.append({"cycle":i+1,"nodes":get_tree().get_node_count(),"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)})
	var file:=FileAccess.open(output+"/scrap_lifetime_profile.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(checkpoints,"\t"))
	file.close()
	print("SCRAP LIFETIME PROFILE: "+JSON.stringify(checkpoints))
	place(lab,Vector3(0,1.09,16),Vector3(-0.1,0.3,0))
	await get_tree().create_timer(10.5).timeout # Allow already-queued projectile lifetime timers to expire.
	await profile(lab,"_low_after_cycles")

func scrap_size_views(lab: Node3D) -> void:
	place(lab,Vector3(17,-0.11,-91),Vector3(-0.035,0,0))
	await snap(lab,"63_larger_scrap_room")
	place(lab,Vector3(-5.0,0.69,-100),Vector3(-0.12,-0.9,0))
	await snap(lab,"64_larger_scrap_stands")
	lab.scrap.join_round("local")
	lab.scrap.choose("heads",lab.scrap.fighters[1].actor_id)
	await get_tree().create_timer(5.2).timeout
	await snap(lab,"65_larger_scrap_ring")
	await profile(lab,"_larger_scrap_split")
	lab.scrap.leave()
