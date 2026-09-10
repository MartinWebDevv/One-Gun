extends Node
var failures := 0
var capture := false
var output := "res://artifacts/hideout_migration"
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	reparent(get_tree().root)
	capture = OS.get_cmdline_user_args().has("--capture-hideout")
	if OS.get_cmdline_user_args().has("--compact-capture"):
		output+="/compact"
		DirAccess.make_dir_recursive_absolute(output)
	# Test-only in-memory quality. Do not save or replace the user's settings.
	PlayerPrefs.settings["quality_preset"]="low"
	PlayerPrefs.settings["shadow_quality"]="low"
	PlayerPrefs.settings["effects_quality"]="low"
	PlayerPrefs.settings["render_scale"]=0.75
	PlayerPrefs.settings["anti_aliasing"]="off"
	PlayerPrefs.settings["display_mode"]="windowed"
	PlayerPrefs.settings["resolution"]=[1280,720] if OS.get_cmdline_user_args().has("--compact-capture") else [1920,1080]
	preload("res://UI/player_settings_applier.gd").apply_video(PlayerPrefs.settings,get_tree())
	GameConfig.set_bot_count(0)
	get_tree().change_scene_to_file(HideoutSession.SCENE)
	await get_tree().process_frame
	await get_tree().process_frame
	var world:=get_tree().current_scene
	_check(world.scene_file_path==HideoutSession.SCENE and world.activities_ready,"standalone home starts without opening a socket")
	_check(not NetworkManager.is_online(),"home remains private and offline")
	_check(world.player_hud.player==world.pilot and world.player_hud.visible,"offline HUD binds the real player")
	world.pilot.stamina=35.0
	world.pilot.dash_charges=1
	await get_tree().create_timer(0.4).timeout
	_check(world.player_hud.stamina_bar.value<70,"HUD reads actual stamina")
	_check(world.player_hud.dash_display.player.dash_charges==world.pilot.dash_charges,"HUD reads actual dash charges")
	_check(world.ui.friends_orb.visible and world.ui.menu_hint.visible,"compact Friends orb and menu hint replace full-width bars")
	var friends_key:=InputEventAction.new()
	friends_key.action="p1_lobby_friends"
	friends_key.pressed=true
	world._input(friends_key)
	_check(world.native_page=="friends","Friends shortcut opens the original social overlay")
	world._escape()
	await get_tree().process_frame
	world.ui.friends_orb.pressed.emit()
	_check(world.native_page=="friends","original Friends orb opens the social overlay")
	world._escape()
	await get_tree().process_frame
	var menu_errors: Array[String]=await preload("res://tools/hideout_menu_validation.gd").run(world)
	_check(menu_errors.is_empty(),"Escape and shortcut movement, cursor, camera and typing: "+str(menu_errors))
	await _check_hub_routes(world)
	await _check_course_buttons(world)
	world.training.show_result=0
	world.ui.toast_left=0
	world.training.hud.hide()
	var camera:=Camera3D.new()
	world.add_child(camera)
	camera.position=Vector3(16,8,23)
	camera.look_at(Vector3(-8,2,-16))
	camera.make_current()
	await _capture("home")
	camera.position=Vector3(13,2.6,17)
	camera.look_at(Vector3(-10,3,-15))
	await _capture("hall_eye_level")
	camera.position=Vector3(20,2.5,-84)
	camera.look_at(Vector3(17,0.7,-97))
	await _capture("scrap_terminal")
	camera.position=Vector3(1.5,3.5,-98)
	camera.look_at(Vector3(1.5,3.5,-85.3))
	await _capture("scrap_wins")
	camera.position=Vector3(3,3,-40.8)
	camera.look_at(Vector3(-10,1,-42.25))
	await _capture("course_buttons")
	camera.position=Vector3(4,3.4,-56.5)
	camera.look_at(Vector3(-9.4,2.2,-56.5))
	var demo_roster: Array=[]
	for i in range(10): demo_roster.append({"id":"capture_"+str(i),"name":"RUNNER %02d" % [i+1]})
	world.training.records.set_members(demo_roster)
	for i in range(10):
		world.training.records.submit_completed_run(world.training.records_bucket(false),"capture_"+str(i),25342+i*713,i%3)
		world.training.records.submit_completed_run(world.training.records_bucket(true),"capture_"+str(i),22230+i*801,i%2)
	await _capture("course_wall")
	world.training.records.lobby_times.clear()
	world.training.records.lobby_details.clear()
	world.training.refresh_roster()
	_check(world.station.find_child("ScrapJoinTerminal",true,false)!=null,"standing arena terminal is baked into the scene")
	_check(world.station.find_child("ScrapJoinBoard",true,false)==null,"old entrance signup sign is removed")
	world.pilot.get_gameplay_camera().make_current()
	camera.queue_free()
	for page in ["events","party","private","range_settings","course_board","agility","scrap","pause","confirm_leave","confirm_quit"]:
		world._open(page)
		await get_tree().process_frame
		_check(world.ui.page==page and world.controls_enabled,"kiosk opens: "+page)
		_check(not world.player_hud.visible,"HUD hides behind "+page)
		if page in ["events","course_board","pause"]: await _capture(page)
		world._open("")
	var prefs_before:=PlayerPrefs.settings.duplicate(true)
	HideoutSession.selected_map = MapRegistry.MAPS[1].scene_path
	for page in ["hub","profile","prize_counter","progression","locker","settings","friends","release_notes","match_setup"]:
		world._open_native(page)
		await get_tree().process_frame
		await get_tree().process_frame
		var panel=world.native_overlay
		_check(is_instance_valid(panel) and panel.is_visible_in_tree(),"real menu opens: "+page)
		_check(get_viewport().disable_3d and world.controls_enabled and world.pilot.menu_movement_only,"room rendering sleeps with locomotion enabled under "+page)
		if page=="match_setup":
			_check(panel.selected_map_index==1,"Game Board restores selected map")
			_check(panel._roster_list.get_child_count()==10,"all local roster slots remain available")
			panel._on_map_dropdown_selected(panel._map_dropdown.get_item_index(2))
			_check(HideoutSession.selected_map==MapRegistry.MAPS[2].scene_path,"Game Board remembers map edits")
			panel._on_match_settings_button_pressed()
			await get_tree().process_frame
			_check(is_instance_valid(panel._settings_slideout),"full match rules remain available")
			panel._on_back_button_pressed()
			await get_tree().create_timer(0.4).timeout
		if page in ["hub","profile","prize_counter","progression","locker","settings","friends","release_notes","match_setup"]: await _capture(page)
		world._escape()
		await get_tree().create_timer(0.4).timeout
		_check(not is_instance_valid(world.native_overlay),"Back closes "+page)
		_check(not get_viewport().disable_3d and world.controls_enabled,"room resumes after "+page)
		_check(world.player_hud.visible and world.player_hud.player==world.pilot,"HUD restores after "+page)
	_check(PlayerPrefs.settings==prefs_before,"opening and cancelling menus preserves personal settings")
	world._open_native("match_setup")
	await get_tree().process_frame
	_check(world.native_overlay.selected_map_index==2,"map choice survives reopening the board")
	world._escape()
	await get_tree().process_frame
	print("HIDEOUT_UI_COMPLETE failures=",failures)
	get_tree().quit(1 if failures else 0)
func _check(value: bool, label: String) -> void:
	if value: print("PASS: ",label)
	else: failures+=1; push_error("HIDEOUT UI CHECK FAILED: "+label)
func _capture(label: String) -> void:
	if not capture: return
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output+"/"+label+".png")
	print("CAPTURE ",label," fps=",Engine.get_frames_per_second()," memory=",Performance.get_monitor(Performance.MEMORY_STATIC))

func _check_course_buttons(world: Node3D) -> void:
	var training=world.training
	for powered in [false,true]:
		world.pilot.position=training.Space.Course.MODE_BUTTONS[1 if powered else 0]+Vector3(1.4,0,0)
		world.pilot.velocity=Vector3.ZERO
		var id: String="course_powerup" if powered else "course_standard"
		var deadline:=Time.get_ticks_msec()+2000
		while not world.nearby.has(id) and Time.get_ticks_msec()<deadline:
			await get_tree().physics_frame
		world.playpen.sync_actor(world.pilot)
		world.pilot.apply_powerup("speed_surge",5.0)
		world.pilot.activate_double_jump_shoes()
		_check(world.nearby.has(id),"physical entrance button has interaction zone: "+id)
		var event:=InputEventAction.new()
		event.action="p1_interact"
		event.pressed=true
		world._input(event)
		_check(training.selected_powerup==powered and world.pilot.speed_surge_timer<=0 and not world.pilot.double_jump_shoes_active,"entrance button selects clean mode: "+id)
		world.pilot.position=training.Space.RECOVERY[0]
		world.playpen.sync_actor(world.pilot)
		world.pilot.apply_powerup("silent_steps",5.0)
		training._gate_entered(world.pilot,0)
		_check(training.running and world.pilot.silent_steps_timer<=0,"starting line strips newly collected powers")
		_check((world.pilot.speed_surge_timer>0)==powered and world.pilot.extra_dash_charge==(1 if powered else 0),"starting line applies only the selected run loadout")
		training.cancel_trial()
		_check(world.pilot.speed_surge_timer<=0,"cancel removes the course bonus")
		training._gate_entered(world.pilot,0)
		_check(training.assisted==powered and (world.pilot.speed_surge_timer>0)==powered,"retry automatically uses the last selected run style")
		training.cancel_trial()
		var color: Color=world.G.ORANGE if powered else world.G.GREEN
		for name in ["CourseStartDoor","CourseFinishDoor"]:
			var door=world.station.find_child(name,true,false)
			_check(door.get_node("Sign/Title").modulate==color and door.get_node("Sign/Rule").material_override.albedo_color==color,"door text and decoration match local selection: "+name)
		_check(world.station.find_child("CourseRules",true,false)==null,"old run/jump/dash wording is removed")
	world._reset_position()

func _check_hub_routes(world: Node3D) -> void:
	for destination in ["profile","locker","prize_counter","progression"]:
		world._open_native("hub")
		await get_tree().process_frame
		await get_tree().process_frame
		var hub=world.native_overlay
		var cabinet: Control=hub.find_child("LobbyPlayerHubCabinet",true,false)
		# Headless has a dummy window size; rendered runs verify real layout bounds.
		if DisplayServer.get_name() != "headless":
			_check(get_viewport().get_visible_rect().encloses(cabinet.get_global_rect()),"Hub fits current viewport")
		var title: String=destination.replace("_"," ").to_pascal_case()
		var button: Button=hub.find_child("Open"+title+"Button",true,false)
		_check(button!=null,"Hub destination is actionable: "+destination)
		button.pressed.emit()
		await get_tree().process_frame
		_check(world.native_page==destination,"Hub tile routes to actual destination: "+destination)
		world._escape()
		await get_tree().create_timer(0.45).timeout
		_check(world.native_page=="hub","destination Back returns to Hub")
		world._escape()
		await get_tree().process_frame
	for icon in ["closet_rack","star","steps"]:
		var texture: Texture2D=load("res://UI/assets/hideout/"+icon+".png")
		_check(texture.get_width()<=512 and texture.get_height()<=512,"destination art respects runtime budget: "+icon)
