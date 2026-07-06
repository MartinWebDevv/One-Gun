extends Control

# ============================================================
# Player Settings — volume + sensitivity controls. Auto-saves to
# disk on every change via PlayerPrefs; no presets here (those
# belong to GameConfig's match-rules preset system, surfaced on
# the Game Setup screen instead). Works two ways:
#   - Standalone scene, reached from the main menu (Back button
#     returns to main_menu.tscn via scene change).
#   - Instanced as a child overlay from the in-match pause menu
#     (Back button instead emits `settings_closed` so the pause
#     menu can remove this overlay without touching the match scene).
#
# `is_overlay` controls which of those two behaviors Back uses.
# Set this externally right after instancing, before adding to tree,
# when used as an overlay.
# ============================================================

signal settings_closed

@export var is_overlay := false

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui():
	for child in get_children():
		child.queue_free()

	var background = ColorRect.new()
	background.color = Color(0.102, 0.122, 0.180, 0.96 if is_overlay else 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)

	var root = VBoxContainer.new()
	root.anchor_left = 0.5
	root.anchor_top = 0.0
	root.anchor_right = 0.5
	root.anchor_bottom = 0.0
	root.offset_left = -300
	root.offset_top = 40
	root.offset_right = 300
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	var title = Label.new()
	title.text = "PLAYER SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.718, 0.0))
	root.add_child(title)

	root.add_child(HSeparator.new())

	_add_slider_row(root, "Master Volume", "master_volume", 0.0, 1.0)
	_add_slider_row(root, "Music Volume", "music_volume", 0.0, 1.0)
	_add_slider_row(root, "SFX Volume", "sfx_volume", 0.0, 1.0)

	root.add_child(HSeparator.new())

	_add_slider_row(root, "Mouse Sensitivity", "mouse_sensitivity", 0.1, 5.0)
	_add_slider_row(root, "Gamepad Sensitivity", "gamepad_sensitivity", 1.0, 15.0)
	_add_slider_row(root, "ADS Sensitivity Multiplier", "ads_sensitivity_multiplier", 0.05, 1.0)
	_add_slider_row(root, "Gamepad Response Curve", "gamepad_response_curve_exponent", 0.5, 4.0)

	root.add_child(HSeparator.new())

	_add_bool_row(root, "Gamepad Sprint is Toggle", "gamepad_sprint_is_toggle")
	_add_bool_row(root, "Mouse/Keyboard Sprint is Toggle", "mouse_keyboard_sprint_is_toggle")
	_add_bool_row(root, "Invert Look Y-Axis", "invert_look_y")

	root.add_child(HSeparator.new())

	_add_slider_row(root, "Field of View", "field_of_view", 60.0, 110.0)
	_add_crosshair_color_row(root)

	root.add_child(HSeparator.new())

	var bottom_row = HBoxContainer.new()
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_row.add_theme_constant_override("separation", 16)

	var reset_button = Button.new()
	reset_button.text = "Reset to Defaults"
	reset_button.pressed.connect(func():
		AudioManager.play_click()
		PlayerPrefs.reset_to_defaults()
		_build_ui()
	)
	reset_button.mouse_entered.connect(func(): AudioManager.play_hover())
	bottom_row.add_child(reset_button)

	var back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(120, 40)
	back_button.pressed.connect(_on_back_pressed)
	back_button.mouse_entered.connect(func(): AudioManager.play_hover())
	bottom_row.add_child(back_button)

	root.add_child(bottom_row)

func _add_slider_row(parent: VBoxContainer, label_text: String, pref_key: String, min_value: float, max_value: float):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220, 0)
	row.add_child(label)

	var slider = HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = (max_value - min_value) / 100.0
	slider.value = PlayerPrefs.get_setting(pref_key)
	slider.custom_minimum_size = Vector2(200, 0)
	row.add_child(slider)

	var value_label = Label.new()
	value_label.text = "%.2f" % slider.value
	value_label.custom_minimum_size = Vector2(50, 0)
	value_label.add_theme_color_override("font_color", Color(1.0, 0.718, 0.0))
	row.add_child(value_label)

	slider.value_changed.connect(func(v):
		value_label.text = "%.2f" % v
		PlayerPrefs.set_setting(pref_key, v)
		match pref_key:
			"master_volume":
				AudioServer.set_bus_volume_db(
					AudioServer.get_bus_index("Master"),
					linear_to_db(max(v, 0.0001))
				)
			"music_volume":
				AudioManager.set_music_volume(v)
			"sfx_volume":
				AudioManager.set_sfx_volume(v)
				# Play click sound as live preview so player
				# hears the sfx volume change in real time.
				AudioManager.play_click()
	)

	parent.add_child(row)

func _add_bool_row(parent: VBoxContainer, label_text: String, pref_key: String):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220, 0)
	row.add_child(label)

	var checkbox = CheckBox.new()
	checkbox.button_pressed = PlayerPrefs.get_setting(pref_key)
	checkbox.toggled.connect(func(v):
		PlayerPrefs.set_setting(pref_key, v)
	)
	row.add_child(checkbox)

	parent.add_child(row)

func _add_crosshair_color_row(parent: VBoxContainer):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label = Label.new()
	label.text = "Crosshair Color"
	label.custom_minimum_size = Vector2(220, 0)
	row.add_child(label)

	var color_picker_button = ColorPickerButton.new()
	color_picker_button.color = PlayerPrefs.get_crosshair_color()
	color_picker_button.custom_minimum_size = Vector2(80, 30)
	color_picker_button.color_changed.connect(func(c):
		PlayerPrefs.set_crosshair_color(c)
	)
	row.add_child(color_picker_button)

	parent.add_child(row)

func _on_back_pressed():
	AudioManager.play_click()
	if is_overlay:
		settings_closed.emit()
	else:
		get_tree().change_scene_to_file("res://main_menu.tscn")
