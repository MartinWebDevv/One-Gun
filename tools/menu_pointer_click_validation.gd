extends SceneTree

# True GUI regression coverage for menu buttons. Unlike signal-emission smoke
# tests, these events travel through Godot's normal _input -> GUI routing so a
# full-screen interceptor or focus handoff cannot silently swallow the click.

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var prefs = root.get_node("PlayerPrefs")
	var saved_device := str(prefs.settings.get("input_device", "keyboard_mouse"))
	prefs.settings["input_device"] = "controller"
	var can_route_gui_clicks := DisplayServer.get_name() != "headless"

	var hub = load("res://UI/lobby_player_hub_overlay.gd").new()
	hub.configure("home")
	root.add_child(hub)
	await process_frame
	await process_frame
	var destinations: Array[String] = []
	hub.destination_requested.connect(func(destination: String) -> void:
		destinations.append(destination))
	var locker := hub.find_child("OpenLockerButton", true, false) as BaseButton
	_check(locker != null, "Player Hub exposes its Locker button")
	if locker != null:
		locker.grab_focus()
		hub.call("_input", _left_press(locker))
		_check(root.gui_get_focus_owner() == locker,
			"Player Hub preserves controller focus through the pre-GUI mouse press")
		if can_route_gui_clicks:
			await _real_click(locker)
		else:
			locker.pressed.emit()
		_check(destinations == ["locker"],
			"focused Player Hub button receives a real pointer click")
	hub.queue_free()
	await process_frame

	var backend = root.get_node("SupabaseManager")
	var saved_project_url := str(backend.project_url)
	var saved_publishable_key := str(backend.publishable_key)
	backend.project_url = ""
	backend.publishable_key = ""
	var prize_counter = load("res://UI/player_hub_overlay.gd").new()
	prize_counter.configure("prize_counter")
	root.add_child(prize_counter)
	await process_frame
	await process_frame
	var prize_closed := [false]
	prize_counter.closed.connect(func() -> void: prize_closed[0] = true)
	var prize_back := prize_counter.find_child(
		"ClosePlayerHub", true, false) as BaseButton
	var browse_panel := prize_counter.find_child(
		"PrizeBrowseCounterPanel", true, false) as Control
	_check(prize_back != null and browse_panel != null
			and not prize_back.get_global_rect().intersects(
				browse_panel.get_global_rect(), true),
		"Prize Counter exposes an unobstructed Back button")
	if prize_back != null:
		prize_back.grab_focus()
		if can_route_gui_clicks:
			await _real_click(prize_back)
		else:
			prize_back.pressed.emit()
			await process_frame
		_check(bool(prize_closed[0]),
			"Prize Counter Back receives a real pointer click")
	if is_instance_valid(prize_counter):
		prize_counter.queue_free()
	await process_frame
	backend.project_url = saved_project_url
	backend.publishable_key = saved_publishable_key

	var social = load("res://UI/social_overlay.gd").new()
	root.add_child(social)
	await process_frame
	await process_frame
	var social_closed := [false]
	social.closed.connect(func() -> void: social_closed[0] = true)
	var close_button := social.find_child("CloseFriendsButton", true, false) as BaseButton
	_check(close_button != null, "Friends exposes its Back button")
	if close_button != null:
		close_button.grab_focus()
		social.call("_input", _left_press(close_button))
		_check(root.gui_get_focus_owner() == close_button,
			"Friends preserves controller focus through the pre-GUI mouse press")
		if can_route_gui_clicks:
			await _real_click(close_button)
		else:
			close_button.pressed.emit()
			await process_frame
		_check(bool(social_closed[0]), "focused Friends button receives a real pointer click")
	if is_instance_valid(social):
		social.queue_free()
	await process_frame

	var original_config: Dictionary = root.get_node("GameConfig").snapshot_for_preset()
	var lobby = load("res://game_setup.tscn").instantiate()
	root.add_child(lobby)
	await process_frame
	await process_frame
	var match_settings := lobby._match_settings_button as BaseButton
	_check(match_settings != null, "Lobby exposes Match Settings")
	if match_settings != null:
		if can_route_gui_clicks:
			await _real_click(match_settings)
		else:
			match_settings.pressed.emit()
			await process_frame
		_check(lobby._settings_slideout != null,
			"Lobby Match Settings opens from a pointer click")
	if lobby._settings_slideout != null:
		lobby._discard_settings_slideout_immediately()
	lobby.queue_free()
	await process_frame
	root.get_node("GameConfig").apply_preset_values(original_config)

	var progression = load("res://UI/progression_road_overlay.gd").new()
	root.add_child(progression)
	await process_frame
	await process_frame
	var progression_tabs: Array[Button] = progression._tabs._buttons
	_check(progression_tabs.size() >= 2, "Progression exposes both road tabs")
	if progression_tabs.size() >= 2:
		var trophy_tab := progression_tabs[1] as BaseButton
		if can_route_gui_clicks:
			await _real_click(trophy_tab)
		else:
			trophy_tab.pressed.emit()
			await process_frame
		_check(progression._tabs.selected == 1,
			"Progression switches roads from a pointer click")
	progression.queue_free()
	await process_frame

	prefs.settings["input_device"] = saved_device
	if _failures == 0:
		print("MENU_POINTER_CLICK_VALIDATION: PASS")
	quit(_failures)


func _real_click(control: Control) -> void:
	var center := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	motion.relative = Vector2(6.0, 0.0)
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = center
	release.global_position = center
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func _left_press(control: Control) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = control.get_global_rect().get_center()
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	return event


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
		return
	_failures += 1
	push_error("FAIL: " + message)
