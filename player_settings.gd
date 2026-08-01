extends Control

# Shared Player Settings overlay used by the main menu and every pause menu.
# Pending values are isolated until Apply. Audio and Video may preview live;
# Cancel/close restores the opening snapshot through the same engine applier.

signal settings_closed

@export var is_overlay := false

const APPLIER = preload("res://UI/player_settings_applier.gd")
const CATEGORIES := ["Audio", "Gameplay", "Video", "Controls", "Accessibility"]
const VIDEO_PRESETS := ["low", "medium", "high", "ultra"]
const REBIND_ACTIONS := [
	["MOVEMENT", "Move Forward", "move_forward"],
	["MOVEMENT", "Move Back", "move_back"],
	["MOVEMENT", "Move Left", "move_left"],
	["MOVEMENT", "Move Right", "move_right"],
	["MOVEMENT", "Jump", "jump"],
	["MOVEMENT", "Sprint", "sprint"],
	["MOVEMENT", "Dash", "dash"],
	["COMBAT", "Interact", "interact"],
	["COMBAT", "Fire", "fire"],
	["COMBAT", "Throw / Use", "throw"],
	["COMBAT", "Aim (ADS)", "ads"],
	["COMBAT", "Toggle Decoy Control", "decoy_command"],
	["INVENTORY", "Cycle Left", "cycle_left"],
	["INVENTORY", "Cycle Right", "cycle_right"],
]

var _opening: Dictionary
var _pending: Dictionary
var _category := "Audio"
var _page_host: MarginContainer
var _page_title: Label
var _category_buttons := {}
var _status_label: Label
var _apply_button: OneGunButton
var _quality_dropdown: OptionButton
var _display_recovery_timer: Timer
var _controls_group := "keyboard_mouse"
var _capture_action := ""
var _capture_slot := -1
var _capture_button: OneGunButton
var _pending_conflict: Dictionary = {}
var _accessibility_subpage := "summary"
var _crosshair_tab := "shape"
var _crosshair_preview: OneGunCrosshair


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_opening = PlayerPrefs.snapshot()
	_pending = _opening.duplicate(true)
	var capture_scale := OS.get_environment("ONEGUN_UI_CAPTURE_SCALE")
	if capture_scale.is_valid_float():
		_pending["ui_scale"] = clampf(capture_scale.to_float(), 0.8, 1.25)
		AccessibilityManager.apply_all(_pending)
	_build_shell()
	var capture := OS.get_environment("ONEGUN_UI_CAPTURE_STATE")
	if capture in ["settings_audio", "settings_gameplay", "settings_video", "settings_controls", "settings_accessibility"]:
		_select_category(capture.trim_prefix("settings_").capitalize())
	elif capture.begins_with("crosshair_"):
		_category = "Accessibility"
		_accessibility_subpage = "crosshair"
		_crosshair_tab = capture.trim_prefix("crosshair_")
		_rebuild_page()
	UICapture.maybe_capture(self, capture if capture.begins_with("settings_") or capture.begins_with("crosshair_") else "settings_audio", 2.5)


func _build_shell() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(OneGunUI.color("canvas"), 0.84)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var cabinet := OneGunCabinet.new()
	cabinet.name = "PlayerSettingsCabinet"
	cabinet.variant = OneGunCabinet.Variant.CABINET
	cabinet.content_padding = OneGunUI.SPACE_L
	cabinet.anchor_left = 0.06
	cabinet.anchor_top = 0.06
	cabinet.anchor_right = 0.94
	cabinet.anchor_bottom = 0.94
	add_child(cabinet)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	cabinet.get_content().add_child(shell)

	var header := HBoxContainer.new()
	var heading_box := VBoxContainer.new()
	heading_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_title = OneGunUI.make_heading("PLAYER SETTINGS / AUDIO", OneGunUI.TEXT_TITLE)
	heading_box.add_child(_page_title)
	heading_box.add_child(OneGunUI.make_label(
		"Changes are not saved until applied.", OneGunUI.TEXT_S, "muted"))
	header.add_child(heading_box)
	var close := OneGunButton.new()
	close.variant = "navy"
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(110, 44)
	close.pressed.connect(_cancel_and_close)
	header.add_child(close)
	shell.add_child(header)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", OneGunUI.SPACE_L)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(body)

	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(220, 0)
	nav.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	body.add_child(nav)
	for category in CATEGORIES:
		var button := OneGunButton.new()
		button.text = str(category).to_upper()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 52)
		button.pressed.connect(_select_category.bind(str(category)))
		_category_buttons[category] = button
		nav.add_child(button)

	var page_well := OneGunCabinet.new()
	page_well.variant = OneGunCabinet.Variant.WELL
	page_well.content_padding = OneGunUI.SPACE_L
	page_well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(page_well)
	_page_host = MarginContainer.new()
	_page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_well.get_content().add_child(_page_host)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	_status_label = OneGunUI.make_label("", OneGunUI.TEXT_S, "cyan")
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_status_label)
	var defaults := OneGunButton.new()
	defaults.variant = "navy"
	defaults.text = "DEFAULTS"
	defaults.pressed.connect(_defaults_for_category)
	footer.add_child(defaults)
	var cancel := OneGunButton.new()
	cancel.variant = "navy"
	cancel.text = "CANCEL"
	cancel.pressed.connect(_cancel_and_close)
	footer.add_child(cancel)
	_apply_button = OneGunButton.new()
	_apply_button.variant = "gold"
	_apply_button.text = "APPLY"
	_apply_button.pressed.connect(_apply_and_close)
	footer.add_child(_apply_button)
	shell.add_child(footer)

	_display_recovery_timer = Timer.new()
	_display_recovery_timer.one_shot = true
	_display_recovery_timer.wait_time = 15.0
	_display_recovery_timer.timeout.connect(_recover_display_preview)
	add_child(_display_recovery_timer)
	_rebuild_page()


func _select_category(category: String) -> void:
	_cancel_capture()
	_pending_conflict.clear()
	_category = category
	_rebuild_page()


func _rebuild_page() -> void:
	for child in _page_host.get_children():
		_page_host.remove_child(child)
		child.queue_free()
	_page_title.text = "PLAYER SETTINGS / %s" % _category.to_upper()
	for category in _category_buttons:
		_category_buttons[category].variant = "purple" if category == _category else "navy"
	match _category:
		"Audio": _build_audio_page()
		"Gameplay": _build_gameplay_page()
		"Video": _build_video_page()
		"Controls": _build_controls_page()
		_: _build_accessibility_page()


func _page_column(intro: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	scroll.add_child(column)
	if intro != "":
		var description := OneGunUI.make_label(intro, OneGunUI.TEXT_S, "muted")
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(description)
	return column


func _build_audio_page() -> void:
	var column := _page_column("Three buses, three clear controls. Changes preview live and restore on Cancel.")
	_add_section(column, "VOLUME")
	_add_slider(column, "Master Volume", "master_volume", 0.0, 1.0, 0.01, true, true)
	_add_slider(column, "Music Volume", "music_volume", 0.0, 1.0, 0.01, true, true)
	_add_slider(column, "SFX Volume", "sfx_volume", 0.0, 1.0, 0.01, true, true)


func _build_gameplay_page() -> void:
	var column := _page_column("Personal aiming and sprint behavior. These settings are local and never become lobby rules.")
	_add_section(column, "LOOK SENSITIVITY")
	_add_slider(column, "Mouse Sensitivity", "mouse_sensitivity", 0.1, 5.0, 0.05)
	_add_slider(column, "Gamepad Sensitivity", "gamepad_sensitivity", 1.0, 15.0, 0.1)
	_add_slider(column, "ADS Multiplier", "ads_sensitivity_multiplier", 0.05, 1.0, 0.01)
	_add_slider(column, "Response Curve", "gamepad_response_curve_exponent", 0.5, 4.0, 0.05)
	_add_section(column, "BEHAVIOR")
	_add_toggle(column, "Gamepad Sprint is Toggle", "gamepad_sprint_is_toggle")
	_add_toggle(column, "Mouse / Keyboard Sprint is Toggle", "mouse_keyboard_sprint_is_toggle")
	_add_toggle(column, "Invert Look Y-Axis", "invert_look_y")


func _build_video_page() -> void:
	var column := _page_column("Display changes preview immediately and auto-recover after 15 seconds unless you Apply.")
	_add_section(column, "DISPLAY")
	_add_dropdown(column, "Display Mode", "display_mode", ["windowed", "borderless", "fullscreen"],
		["WINDOWED", "BORDERLESS", "FULLSCREEN"], true)
	_add_resolution_dropdown(column)
	_add_toggle(column, "VSync", "vsync_enabled", true)
	_add_dropdown(column, "Frame Rate Limit", "fps_limit", [0, 30, 60, 120, 144, 240],
		["UNLIMITED", "30", "60", "120", "144", "240"], false)
	_add_section(column, "GRAPHICS")
	_add_dropdown(column, "Quality Preset", "quality_preset",
		["low", "medium", "high", "ultra", "custom"], ["LOW", "MEDIUM", "HIGH", "ULTRA", "CUSTOM"])
	_add_dropdown(column, "Shadow Quality", "shadow_quality",
		["low", "medium", "high", "ultra"], ["LOW", "MEDIUM", "HIGH", "ULTRA"])
	_add_dropdown(column, "Anti-Aliasing", "anti_aliasing",
		["off", "fxaa", "msaa_2x", "msaa_4x"], ["OFF", "FXAA", "MSAA 2X", "MSAA 4X"])
	_add_slider(column, "Render Scale", "render_scale", 0.5, 1.5, 0.05, false, false, true)
	_add_section(column, "CAMERA")
	_add_slider(column, "Field of View", "field_of_view", 60.0, 110.0, 1.0)


func _build_controls_page() -> void:
	var column := _page_column("Choose a slot, then press a key, mouse input, gamepad button, or gamepad axis. Escape cancels capture.")
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	for data in [["KEYBOARD & MOUSE", "keyboard_mouse"], ["GAMEPAD", "gamepad"]]:
		var tab := OneGunButton.new()
		tab.text = data[0]
		tab.variant = "purple" if _controls_group == data[1] else "navy"
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_set_controls_group.bind(str(data[1])))
		tabs.add_child(tab)
	column.add_child(tabs)
	var columns := _setting_row(column, "ACTION")
	for heading in ["PRIMARY", "SECONDARY", "ROW"]:
		var column_label := OneGunUI.make_label(heading, OneGunUI.TEXT_XS, "muted", true)
		column_label.custom_minimum_size = Vector2(190 if heading != "ROW" else 84, 0)
		column_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		columns.add_child(column_label)
	if not _pending_conflict.is_empty():
		_build_conflict_confirmation(column)
	for prefix_data in [["PLAYER 1", "p1"], ["PLAYER 2 (SPLITSCREEN)", "p2"]]:
		_add_section(column, prefix_data[0])
		var current_group := ""
		for entry in REBIND_ACTIONS:
			if entry[0] != current_group:
				current_group = entry[0]
				column.add_child(OneGunUI.make_label(current_group, OneGunUI.TEXT_XS, "cyan", true))
			var action := "%s_%s" % [prefix_data[1], entry[2]]
			if InputMap.has_action(action):
				_add_binding_row(column, entry[1], action)


func _build_accessibility_page() -> void:
	if _accessibility_subpage == "crosshair":
		_build_crosshair_editor()
		return
	var column := _page_column("Readability and motion choices preview immediately, remain local, and restore on Cancel.")
	_add_section(column, "READABILITY")
	_add_slider(column, "UI Scale", "ui_scale", 0.8, 1.25, 0.05, true)
	_add_dropdown(column, "Text Size", "text_size", ["small", "normal", "large", "extra_large"], ["SMALL", "NORMAL", "LARGE", "EXTRA LARGE"])
	_add_dropdown(column, "Colorblind Filter", "colorblind_filter", ["off", "protanopia", "deuteranopia", "tritanopia"], ["OFF", "PROTANOPIA", "DEUTERANOPIA", "TRITANOPIA"])
	_add_toggle(column, "High Contrast UI", "high_contrast_ui")
	_add_section(column, "MOTION & FLASH")
	_add_slider(column, "Screen Shake", "screen_shake_intensity", 0.0, 1.0, 0.05, true)
	_add_slider(column, "Camera Bob", "camera_bob_intensity", 0.0, 1.0, 0.05, true)
	_add_toggle(column, "Reduce Flashing", "reduce_flashing")
	_add_toggle(column, "Reduced Motion", "reduced_motion")
	_add_toggle(column, "Motion Blur", "motion_blur")
	_add_section(column, "PROTECTION ICONS")
	_add_slider(column, "Icon Size", "protection_icon_size", 0.5, 2.0, 0.05, true)
	_add_color_dropdown(column, "Extra Life Color", "extra_life_icon_color")
	_add_color_dropdown(column, "Sticky Hands Color", "sticky_hands_icon_color")
	_add_section(column, "CROSSHAIR")
	var summary := OneGunCabinet.new()
	summary.variant = OneGunCabinet.Variant.SECTION
	summary.content_padding = OneGunUI.SPACE_M
	column.add_child(summary)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	summary.get_content().add_child(row)
	var preview := ColorRect.new()
	preview.color = Color("101725")
	preview.custom_minimum_size = Vector2(180, 100)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(preview)
	_crosshair_preview = OneGunCrosshair.new()
	preview.add_child(_crosshair_preview)
	_crosshair_preview.set_preview_settings(_pending)
	var text := OneGunUI.make_label("%s  •  %d%% SIZE\nLocal visual only — aim and accuracy never change." % [str(_pending["crosshair_style"]).replace("_", " ").to_upper(), roundi(float(_pending["crosshair_size"]) * 100.0)], OneGunUI.TEXT_S, "text")
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(text)
	var edit := OneGunButton.new()
	edit.variant = "gold"
	edit.text = "EDIT"
	edit.custom_minimum_size = Vector2(110, 44)
	edit.pressed.connect(func(): _accessibility_subpage = "crosshair"; _rebuild_page())
	row.add_child(edit)


func _build_crosshair_editor() -> void:
	var column := _page_column("Customize a procedural local HUD visual. These settings never alter aim, spread, hitboxes, or network state.")
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	var back := OneGunButton.new()
	back.variant = "navy"
	back.text = "← ACCESSIBILITY"
	back.pressed.connect(func(): _accessibility_subpage = "summary"; _rebuild_page())
	top.add_child(back)
	for tab_name in ["shape", "behavior", "feedback"]:
		var tab := OneGunButton.new()
		tab.text = tab_name.to_upper()
		tab.variant = "purple" if tab_name == _crosshair_tab else "navy"
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(func(): _crosshair_tab = tab_name; _rebuild_page())
		top.add_child(tab)
	column.add_child(top)
	_add_crosshair_preview(column)
	match _crosshair_tab:
		"behavior": _build_crosshair_behavior(column)
		"feedback": _build_crosshair_feedback(column)
		_: _build_crosshair_shape(column)


func _add_crosshair_preview(column: VBoxContainer) -> void:
	var preview := ColorRect.new()
	var backgrounds := {"dark": Color("101725"), "bright": Color("d8d5bd"), "forest": Color("31543d"), "desert": Color("9e7047"), "neon": Color("34184f")}
	preview.color = backgrounds.get(str(_pending["crosshair_preview_background"]), Color("101725"))
	preview.custom_minimum_size = Vector2(0, 220)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(preview)
	_crosshair_preview = OneGunCrosshair.new()
	preview.add_child(_crosshair_preview)
	_crosshair_preview.set_preview_settings(_pending)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	column.add_child(actions)
	for action in ["fire", "reload", "pickup", "interact"]:
		var button := OneGunButton.new()
		button.variant = "navy"
		button.text = action.to_upper()
		button.pressed.connect(_trigger_crosshair_preview.bind(action))
		actions.add_child(button)
	_add_dropdown(column, "Preview Background", "crosshair_preview_background", ["dark", "bright", "forest", "desert", "neon"], ["DARK", "BRIGHT", "FOREST", "DESERT", "NEON"])


func _build_crosshair_shape(column: VBoxContainer) -> void:
	_add_section(column, "SHAPE & COLOR")
	_add_dropdown(column, "Style", "crosshair_style", ["classic", "dot", "ring", "cross_dot", "brackets", "chevron", "minimal", "hidden"], ["CLASSIC", "DOT", "RING", "CROSS + DOT", "BRACKETS", "CHEVRON", "MINIMAL", "HIDDEN"])
	_add_color_dropdown(column, "Color", "crosshair_color")
	_add_slider(column, "Size", "crosshair_size", 0.5, 2.0, 0.05, true)
	_add_slider(column, "Thickness", "crosshair_thickness", 1.0, 8.0, 0.5)
	_add_slider(column, "Gap", "crosshair_gap", 0.0, 30.0, 1.0)
	_add_slider(column, "Line Length", "crosshair_line_length", 2.0, 30.0, 1.0)
	_add_toggle(column, "Center Dot", "crosshair_center_dot")
	_add_slider(column, "Dot Size", "crosshair_dot_size", 1.0, 10.0, 0.5)
	_add_slider(column, "Opacity", "crosshair_opacity", 0.0, 1.0, 0.05, true)
	_add_toggle(column, "Outline", "crosshair_outline")
	_add_color_dropdown(column, "Outline Color", "crosshair_outline_color")
	_add_slider(column, "Outline Thickness", "crosshair_outline_thickness", 0.0, 6.0, 0.5)
	_add_toggle(column, "Glow", "crosshair_glow")
	_add_slider(column, "Glow Intensity", "crosshair_glow_intensity", 0.0, 1.0, 0.05, true)


func _build_crosshair_behavior(column: VBoxContainer) -> void:
	_add_section(column, "BEHAVIOR")
	_add_dropdown(column, "Mode", "crosshair_behavior_mode", ["static", "movement", "full_dynamic"], ["STATIC", "MOVEMENT", "FULL DYNAMIC"])
	_add_toggle(column, "Movement Expansion", "crosshair_movement_expansion")
	_add_slider(column, "Movement Intensity", "crosshair_movement_intensity", 0.0, 1.0, 0.05, true)
	_add_dropdown(column, "Return Speed", "crosshair_return_speed", ["slow", "normal", "fast"], ["SLOW", "NORMAL", "FAST"])
	_add_toggle(column, "Fire Pulse", "crosshair_fire_pulse")
	_add_toggle(column, "Reload Indicator", "crosshair_reload_indicator")
	_add_toggle(column, "Gun Pickup Feedback", "crosshair_pickup_feedback")
	_add_toggle(column, "Interactable Feedback", "crosshair_interactable_feedback")
	_add_slider(column, "Animation Intensity", "crosshair_animation_intensity", 0.0, 1.0, 0.05, true)
	_add_dropdown(column, "Animation Speed", "crosshair_animation_speed", ["slow", "normal", "fast"], ["SLOW", "NORMAL", "FAST"])
	_add_toggle(column, "Reduce Crosshair Motion", "reduce_crosshair_motion")


func _build_crosshair_feedback(column: VBoxContainer) -> void:
	_add_section(column, "HIT MARKER")
	_add_toggle(column, "Enabled", "hit_marker_enabled")
	_add_dropdown(column, "Style", "hit_marker_style", ["x", "diamond", "ticks"], ["X", "DIAMOND", "TICKS"])
	_add_color_dropdown(column, "Color", "hit_marker_color")
	_add_slider(column, "Size", "hit_marker_size", 0.5, 2.0, 0.05, true)
	_add_slider(column, "Thickness", "hit_marker_thickness", 1.0, 8.0, 0.5)
	_add_slider(column, "Opacity", "hit_marker_opacity", 0.0, 1.0, 0.05, true)
	_add_slider(column, "Duration", "hit_marker_duration", 0.08, 1.5, 0.02)
	_add_toggle(column, "Sound", "hit_marker_sound")
	_add_slider(column, "Sound Volume", "hit_marker_volume", 0.0, 1.0, 0.05, true)
	_add_section(column, "ELIMINATION MARKER")
	_add_toggle(column, "Enabled", "elimination_marker_enabled")
	_add_dropdown(column, "Style", "elimination_marker_style", ["gold_star", "toy_splash", "skull_star", "expanding_ring"], ["GOLD STAR", "TOY SPLASH", "SKULL + STAR", "EXPANDING RING"])
	_add_color_dropdown(column, "Color", "elimination_marker_color")
	_add_slider(column, "Size", "elimination_marker_size", 0.5, 2.0, 0.05, true)
	_add_slider(column, "Opacity", "elimination_marker_opacity", 0.0, 1.0, 0.05, true)
	_add_slider(column, "Duration", "elimination_marker_duration", 0.08, 2.0, 0.02)
	_add_toggle(column, "Sound", "elimination_marker_sound")
	_add_slider(column, "Sound Volume", "elimination_marker_volume", 0.0, 1.0, 0.05, true)


func _add_color_dropdown(parent: VBoxContainer, label_text: String, key: String) -> void:
	var colors := [[0.2, 1.0, 0.12, 1.0], [1.0, 1.0, 1.0, 1.0], [0.2, 0.9, 1.0, 1.0], [1.0, 0.72, 0.16, 1.0], [1.0, 0.28, 0.36, 1.0], [0.02, 0.02, 0.03, 1.0]]
	_add_dropdown(parent, label_text, key, colors, ["BRIGHT GREEN", "WHITE", "CYAN", "GOLD", "RED", "INK"])


func _add_section(parent: VBoxContainer, title: String) -> void:
	var heading := OneGunUI.make_heading(title, OneGunUI.TEXT_M, "gold")
	parent.add_child(heading)
	parent.add_child(HSeparator.new())


func _setting_row(parent: VBoxContainer, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	var label := OneGunUI.make_label(label_text, OneGunUI.TEXT_M, "text")
	label.custom_minimum_size = Vector2(270, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	parent.add_child(row)
	return row


func _add_slider(parent: VBoxContainer, label_text: String, key: String,
		minimum: float, maximum: float, step: float, percent := false,
		audio_preview := false, graphics_custom := false) -> void:
	var row := _setting_row(parent, label_text)
	var slider := OneGunUI.make_slider(minimum, maximum, step, float(_pending[key]))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value := OneGunUI.make_value_box(_format_value(float(_pending[key]), percent), 80)
	row.add_child(value)
	slider.value_changed.connect(func(number: float):
		_pending[key] = number
		value.text = _format_value(number, percent)
		if graphics_custom:
			_pending["quality_preset"] = "custom"
			if _quality_dropdown != null:
				_quality_dropdown.select(4)
		if audio_preview:
			APPLIER.apply_audio(_pending)
		elif key in ["render_scale"]:
			APPLIER.apply_video(_pending, get_tree(), false)
		elif _is_accessibility_key(key):
			if _is_global_accessibility_key(key): _preview_accessibility()
			elif _is_accessibility_policy_key(key): AccessibilityManager.preview_policy(_pending)
			_refresh_crosshair_preview()
	)


func _add_toggle(parent: VBoxContainer, label_text: String, key: String,
		display_preview := false) -> void:
	var row := _setting_row(parent, label_text)
	var toggle := OneGunUI.style_checkbox(CheckBox.new())
	toggle.button_pressed = bool(_pending[key])
	toggle.toggled.connect(func(enabled: bool):
		_pending[key] = enabled
		if display_preview: _preview_display()
		elif _is_accessibility_key(key):
			if _is_global_accessibility_key(key): _preview_accessibility()
			elif _is_accessibility_policy_key(key): AccessibilityManager.preview_policy(_pending)
			_refresh_crosshair_preview()
	)
	row.add_child(toggle)


func _add_dropdown(parent: VBoxContainer, label_text: String, key: String,
		values: Array, labels: Array, display_preview := false) -> void:
	var row := _setting_row(parent, label_text)
	var dropdown := OneGunUI.make_dropdown()
	for label in labels: dropdown.add_item(str(label))
	dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dropdown.select(maxi(values.find(_pending[key]), 0))
	if key == "quality_preset":
		_quality_dropdown = dropdown
	dropdown.item_selected.connect(_on_dropdown_changed.bind(key, values, display_preview))
	row.add_child(dropdown)


func _on_dropdown_changed(index: int, key: String, values: Array,
		display_preview: bool) -> void:
	_pending[key] = values[index]
	if key == "quality_preset" and str(_pending[key]) in VIDEO_PRESETS:
		APPLIER.apply_quality_preset(_pending, str(_pending[key]))
		APPLIER.apply_video(_pending, get_tree(), false)
		_rebuild_page()
	elif key in ["shadow_quality", "anti_aliasing"]:
		_pending["quality_preset"] = "custom"
		APPLIER.apply_video(_pending, get_tree(), false)
		_rebuild_page()
	elif key == "fps_limit":
		APPLIER.apply_video(_pending, get_tree(), false)
	elif display_preview:
		_preview_display()
	elif _is_accessibility_key(key):
		if _is_global_accessibility_key(key): _preview_accessibility()
		if key == "crosshair_preview_background": _rebuild_page()
		else: _refresh_crosshair_preview()


func _add_resolution_dropdown(parent: VBoxContainer) -> void:
	var resolutions := APPLIER.valid_resolutions()
	var values: Array = []
	var labels: Array = []
	for resolution in resolutions:
		values.append([resolution.x, resolution.y])
		labels.append("%d × %d" % [resolution.x, resolution.y])
	var current: Array = _pending["resolution"]
	if current not in values:
		values.append(current.duplicate())
		labels.append("%d × %d" % [int(current[0]), int(current[1])])
	var row := _setting_row(parent, "Resolution")
	var dropdown := OneGunUI.make_dropdown()
	for label in labels:
		dropdown.add_item(str(label))
	dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dropdown.select(maxi(values.find(_pending["resolution"]), 0))
	dropdown.disabled = str(_pending["display_mode"]) != "windowed"
	dropdown.tooltip_text = "Resolution is controlled by the display while fullscreen." if dropdown.disabled else ""
	dropdown.item_selected.connect(_on_dropdown_changed.bind("resolution", values, true))
	row.add_child(dropdown)


func _format_value(value: float, percent: bool) -> String:
	return "%d%%" % roundi(value * 100.0) if percent else ("%.2f" % value)


func _is_accessibility_key(key: String) -> bool:
	return key in ["ui_scale", "text_size", "colorblind_filter", "high_contrast_ui", "screen_shake_intensity", "camera_bob_intensity", "reduce_flashing", "motion_blur", "reduced_motion", "reduce_crosshair_motion"] or key.begins_with("crosshair_") or key.begins_with("hit_marker_") or key.begins_with("elimination_marker_") or key.begins_with("protection_") or key.ends_with("_icon_color")


func _is_global_accessibility_key(key: String) -> bool:
	return key in ["ui_scale", "text_size", "colorblind_filter", "high_contrast_ui", "motion_blur", "reduced_motion"]


func _is_accessibility_policy_key(key: String) -> bool:
	return key in ["screen_shake_intensity", "camera_bob_intensity", "reduce_flashing"]


func _preview_accessibility() -> void:
	AccessibilityManager.apply_all(_pending)


func _refresh_crosshair_preview() -> void:
	if _crosshair_preview != null and is_instance_valid(_crosshair_preview):
		_crosshair_preview.set_preview_settings(_pending)


func _trigger_crosshair_preview(action: String) -> void:
	if _crosshair_preview != null and is_instance_valid(_crosshair_preview):
		_crosshair_preview.trigger_preview(action)


func _preview_display() -> void:
	APPLIER.apply_video(_pending, get_tree(), true)
	_status_label.text = "Display preview active — Apply to keep. Auto-revert in 15 seconds."
	_display_recovery_timer.start()


func _recover_display_preview() -> void:
	APPLIER.apply_video(_opening, get_tree(), true)
	APPLIER.apply_video(_pending, get_tree(), false)
	_status_label.text = "Display preview reverted for safety; pending selection is unchanged."


func _set_controls_group(group: String) -> void:
	_cancel_capture()
	_controls_group = group
	_pending_conflict.clear()
	_rebuild_page()


func _effective_bindings(action: String, group: String) -> Array:
	var overrides = _pending.get("input_overrides", {})
	if overrides is Dictionary and overrides.has(action) and overrides[action] is Dictionary and overrides[action].has(group):
		return (overrides[action][group] as Array).duplicate(true)
	return PlayerPrefs.get_binding_descriptors(action, group)


func _store_bindings(action: String, group: String, bindings: Array) -> void:
	var overrides: Dictionary = _pending.get("input_overrides", {}).duplicate(true)
	var per_action: Dictionary = overrides.get(action, {}).duplicate(true)
	per_action[group] = bindings.duplicate(true)
	overrides[action] = per_action
	_pending["input_overrides"] = overrides


func _add_binding_row(parent: VBoxContainer, label_text: String, action: String) -> void:
	var row := _setting_row(parent, label_text)
	var bindings := _effective_bindings(action, _controls_group)
	for slot in 2:
		var button := OneGunButton.new()
		button.variant = "navy"
		button.text = PlayerPrefs.descriptor_label(bindings[slot]) if slot < bindings.size() else "UNBOUND"
		button.tooltip_text = "Primary binding" if slot == 0 else "Secondary binding"
		button.custom_minimum_size = Vector2(190, 42)
		button.pressed.connect(_start_capture.bind(action, slot, button))
		row.add_child(button)
	var reset := OneGunButton.new()
	reset.variant = "navy"
	reset.text = "RESET"
	reset.custom_minimum_size = Vector2(84, 42)
	reset.pressed.connect(_reset_binding_row.bind(action))
	row.add_child(reset)


func _start_capture(action: String, slot: int, button: OneGunButton) -> void:
	_cancel_capture()
	_capture_action = action
	_capture_slot = slot
	_capture_button = button
	button.variant = "purple"
	button.text = "PRESS INPUT…"
	_status_label.text = "Listening for %s input. Escape cancels." % ("gamepad" if _controls_group == "gamepad" else "keyboard / mouse")


func _cancel_capture() -> void:
	if _capture_action == "": return
	_capture_action = ""
	_capture_slot = -1
	_capture_button = null
	_status_label.text = "Binding capture cancelled."
	if _category == "Controls": _rebuild_page.call_deferred()


func _input(event: InputEvent) -> void:
	if _capture_action == "": return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_capture()
		get_viewport().set_input_as_handled()
		return
	var accepted := false
	if _controls_group == "keyboard_mouse":
		accepted = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed)
	else:
		accepted = (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) >= 0.6)
	if not accepted: return
	var descriptor := PlayerPrefs.event_to_descriptor(event)
	if descriptor.is_empty(): return
	var conflict := _find_conflict(_capture_action, descriptor)
	var target_action := _capture_action
	var target_slot := _capture_slot
	_capture_action = ""
	_capture_slot = -1
	_capture_button = null
	if conflict != "":
		_pending_conflict = {"action": target_action, "slot": target_slot,
			"descriptor": descriptor, "conflict": conflict}
	else:
		_assign_binding(target_action, target_slot, descriptor)
	_status_label.text = ""
	_rebuild_page()
	get_viewport().set_input_as_handled()


func _find_conflict(target_action: String, descriptor: Dictionary) -> String:
	var needle := JSON.stringify(descriptor)
	for prefix in ["p1", "p2"]:
		for entry in REBIND_ACTIONS:
			var action := "%s_%s" % [prefix, entry[2]]
			if action == target_action: continue
			for existing in _effective_bindings(action, _controls_group):
				if JSON.stringify(existing) == needle: return action
	return ""


func _assign_binding(action: String, slot: int, descriptor: Dictionary) -> void:
	var bindings := _effective_bindings(action, _controls_group)
	while bindings.size() <= slot: bindings.append({})
	bindings[slot] = descriptor
	bindings = bindings.filter(func(item): return item is Dictionary and not item.is_empty())
	_store_bindings(action, _controls_group, bindings.slice(0, 2))


func _build_conflict_confirmation(parent: VBoxContainer) -> void:
	var panel := OneGunCabinet.new()
	panel.variant = OneGunCabinet.Variant.SECTION
	panel.content_padding = OneGunUI.SPACE_M
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	panel.get_content().add_child(row)
	var text := OneGunUI.make_label("That input is already bound to %s. Replace it?" % str(_pending_conflict["conflict"]).replace("_", " ").to_upper(), OneGunUI.TEXT_S, "red", true)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var replace := OneGunButton.new()
	replace.variant = "red"
	replace.text = "REPLACE"
	replace.pressed.connect(_confirm_binding_replace)
	row.add_child(replace)
	var cancel := OneGunButton.new()
	cancel.variant = "navy"
	cancel.text = "CANCEL"
	cancel.pressed.connect(func(): _pending_conflict.clear(); _rebuild_page())
	row.add_child(cancel)


func _confirm_binding_replace() -> void:
	var conflict_action := str(_pending_conflict["conflict"])
	var descriptor: Dictionary = _pending_conflict["descriptor"]
	var needle := JSON.stringify(descriptor)
	var conflict_bindings := _effective_bindings(conflict_action, _controls_group)
	conflict_bindings = conflict_bindings.filter(func(item): return JSON.stringify(item) != needle)
	_store_bindings(conflict_action, _controls_group, conflict_bindings)
	_assign_binding(str(_pending_conflict["action"]), int(_pending_conflict["slot"]), descriptor)
	_pending_conflict.clear()
	_rebuild_page()


func _reset_binding_row(action: String) -> void:
	_store_bindings(action, _controls_group,
		PlayerPrefs.get_binding_descriptors(action, _controls_group, true))
	_pending_conflict.clear()
	_rebuild_page()


func _defaults_for_category() -> void:
	match _category:
		"Audio":
			for key in ["master_volume", "music_volume", "sfx_volume"]: _pending[key] = PlayerPrefs.get_default(key)
			APPLIER.apply_audio(_pending)
		"Gameplay":
			for key in ["mouse_sensitivity", "gamepad_sensitivity", "ads_sensitivity_multiplier",
					"gamepad_response_curve_exponent", "gamepad_sprint_is_toggle",
					"mouse_keyboard_sprint_is_toggle", "invert_look_y"]:
				_pending[key] = PlayerPrefs.get_default(key)
		"Video":
			for key in ["display_mode", "resolution", "vsync_enabled", "fps_limit", "quality_preset",
					"shadow_quality", "anti_aliasing", "render_scale", "field_of_view"]:
				_pending[key] = PlayerPrefs.get_default(key)
			APPLIER.apply_video(_pending, get_tree(), true)
			_display_recovery_timer.start()
		"Controls": _pending["input_overrides"] = {}
		"Accessibility":
			for key in PlayerPrefs.DEFAULT_SETTINGS:
				if _is_accessibility_key(str(key)): _pending[key] = PlayerPrefs.get_default(str(key))
			_preview_accessibility()
	_status_label.text = "%s defaults are pending. Apply to save." % _category
	_rebuild_page()


func _apply_and_close() -> void:
	_cancel_capture()
	_display_recovery_timer.stop()
	if not PlayerPrefs.apply_transaction(_pending):
		_status_label.text = "Could not save settings. Nothing was applied."
		return
	APPLIER.apply_all(PlayerPrefs.snapshot(), get_tree(), true)
	AccessibilityManager.apply_all()
	_finish_close()


func _cancel_and_close() -> void:
	_capture_action = ""
	_display_recovery_timer.stop()
	APPLIER.apply_all(_opening, get_tree(), true)
	AccessibilityManager.apply_all(_opening)
	_finish_close()


func _finish_close() -> void:
	AudioManager.play_click()
	if is_overlay:
		settings_closed.emit()
	else:
		get_tree().change_scene_to_file("res://main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _capture_action != "": _cancel_capture()
		else: _cancel_and_close()
