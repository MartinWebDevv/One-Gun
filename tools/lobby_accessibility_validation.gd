extends Node
var failures: Array[String] = []
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	PlayerPrefs.settings["ui_scale"] = 1.25
	PlayerPrefs.settings["text_size"] = "large"
	PlayerPrefs.settings["player_name"] = "WWWWWWWWWWWWWWWWWWWWWWWW"
	AccessibilityManager.apply_all()
	GameConfig.split_screen_enabled = true
	GameConfig.teams_enabled = true
	GameConfig.team_count = 4
	GameConfig.set_bot_count(8)
	var lobby := preload("res://game_setup.tscn").instantiate()
	add_child(lobby)
	for _frame in 6: await get_tree().process_frame
	_check(lobby._roster_list.get_child_count() == 10, "ten-player roster missing entries")
	_check(lobby.get_viewport_rect().encloses(lobby._play_button.get_global_rect()), "Play outside viewport")
	_check(lobby._top_strip.vertical and lobby._banner_name.size.x > 200, "map details did not stack at narrow width")
	for row in lobby._roster_list.get_children():
		if row._name_label.text.begins_with("Bot "):
			var label := row._name_label as Label
			var required := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			_check(label.size.x >= required, "short bot name was truncated by status badges")
		row._trailing_box.get_child(0).grab_focus()
		for _frame in 3: await get_tree().process_frame
		_check(lobby._roster_viewport.get_global_rect().grow(0.5).encloses(row._trailing_box.get_child(0).get_global_rect()), "focused roster control was clipped: %s / %s" % [lobby._roster_viewport.get_global_rect(), row._trailing_box.get_child(0).get_global_rect()])
	lobby._back_button.grab_focus()
	for _frame in 3: await get_tree().process_frame
	_check(lobby._left_scroll.get_global_rect().encloses(lobby._back_button.get_global_rect()), "Back remained clipped after controller focus")
	_check(not lobby._roster_cabinet.get_global_rect().intersects(lobby._play_button.get_global_rect()), "roster overlaps Play")
	lobby.queue_free()
	await get_tree().process_frame
	if failures.is_empty(): print("LOBBY_ACCESSIBILITY_VALIDATION: PASS 720p/125%/large/10-actors/focus-scroll")
	else:
		for failure in failures: push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
