extends Node
var failures := 0
var capture := false
var output := "res://artifacts/hideout_migration"
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	reparent(get_tree().root)
	capture = OS.get_cmdline_user_args().has("--capture-hideout")
	# Test-only in-memory quality. Do not save or replace the user's settings.
	PlayerPrefs.settings["quality_preset"]="low"
	PlayerPrefs.settings["shadow_quality"]="low"
	PlayerPrefs.settings["effects_quality"]="low"
	PlayerPrefs.settings["render_scale"]=0.75
	PlayerPrefs.settings["anti_aliasing"]="off"
	GameConfig.set_bot_count(0)
	get_tree().change_scene_to_file(HideoutSession.SCENE)
	await get_tree().process_frame
	await get_tree().process_frame
	var world:=get_tree().current_scene
	_check(world.scene_file_path==HideoutSession.SCENE and world.activities_ready,"standalone home starts without opening a socket")
	_check(not NetworkManager.is_online(),"home remains private and offline")
	var camera:=Camera3D.new()
	world.add_child(camera)
	camera.position=Vector3(16,8,23)
	camera.look_at(Vector3(-8,2,-16))
	camera.make_current()
	await _capture("home")
	world.pilot.get_gameplay_camera().make_current()
	camera.queue_free()
	for page in ["events","party","private","range_settings","course_board","agility","scrap","pause","confirm_leave","confirm_quit"]:
		world._open(page)
		await get_tree().process_frame
		_check(world.ui.page==page and not world.controls_enabled,"kiosk opens: "+page)
		if page in ["events","course_board"]: await _capture(page)
		world._open("")
	var prefs_before:=PlayerPrefs.settings.duplicate(true)
	HideoutSession.selected_map = MapRegistry.MAPS[1].scene_path
	for page in ["hub","profile","prize_counter","progression","locker","settings","friends","release_notes","match_setup"]:
		world._open_native(page)
		await get_tree().process_frame
		await get_tree().process_frame
		var panel=world.native_overlay
		_check(is_instance_valid(panel) and panel.is_visible_in_tree(),"real menu opens: "+page)
		_check(get_viewport().disable_3d and not world.controls_enabled,"room rendering/input sleeps under "+page)
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
		if page in ["hub","settings","match_setup"]: await _capture(page)
		world._escape()
		await get_tree().create_timer(0.4).timeout
		_check(not is_instance_valid(world.native_overlay),"Back closes "+page)
		_check(not get_viewport().disable_3d and world.controls_enabled,"room resumes after "+page)
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
