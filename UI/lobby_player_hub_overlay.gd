class_name LobbyPlayerHubOverlay
extends Control

# Shared launcher for persistent player destinations. The lobby uses the
# original Locker / Prize Counter / Progression layout, while the title screen
# adds Profile and home-specific copy. Destination screens retain their own
# ownership/backend contracts; this is a controller-friendly navigation shell.

signal closed
signal destination_requested(destination: String)

var _first_button: Button
var _focus_buttons: Array[Button] = []
var _context := "lobby"
var _using_pointer := true


func configure(context: String) -> void:
	_context = "home" if context.strip_edges().to_lower() == "home" else "lobby"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_using_pointer = not PlayerPrefs.is_using_controller("p1")
	_build_ui()
	_focus_first.call_deferred()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.relative.length_squared() <= 4.0 \
				or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			return
		_using_pointer = true
		var owner := get_viewport().gui_get_focus_owner()
		if owner is BaseButton and is_ancestor_of(owner):
			owner.release_focus()
		return
	if event is InputEventMouseButton:
		# A mouse press reaches _input before BaseButton receives its GUI event.
		# Never release focus here: doing so can cancel the button's native
		# press/release transaction when a controller had focused it first.
		_using_pointer = true
		return
	var navigation_input := false
	if event is InputEventKey:
		navigation_input = event.pressed and event.keycode in [
			KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_TAB, KEY_ENTER, KEY_SPACE]
	elif event is InputEventJoypadButton:
		navigation_input = event.pressed
	elif event is InputEventJoypadMotion:
		navigation_input = absf(event.axis_value) >= 0.45
	if navigation_input:
		_using_pointer = false
		_focus_first()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_close()


func _build_ui() -> void:
	var scrim := ColorRect.new()
	scrim.name = "PlayerHubScrim"
	scrim.color = Color(0.001, 0.006, 0.018, 0.955)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	var atmosphere := TextureRect.new()
	atmosphere.name = "PlayerHubAtmosphere"
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var atmosphere_gradient := Gradient.new()
	atmosphere_gradient.set_color(0, Color(0.03, 0.42, 0.55, 0.22))
	atmosphere_gradient.set_color(1, Color(0.78, 0.48, 0.03, 0.04))
	var atmosphere_texture := GradientTexture2D.new()
	atmosphere_texture.gradient = atmosphere_gradient
	atmosphere_texture.fill = GradientTexture2D.FILL_LINEAR
	atmosphere_texture.fill_from = Vector2(0.0, 0.0)
	atmosphere_texture.fill_to = Vector2(1.0, 1.0)
	atmosphere.texture = atmosphere_texture
	atmosphere.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	atmosphere.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(atmosphere)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 36.0
	center.offset_top = 36.0
	center.offset_right = -36.0
	center.offset_bottom = -36.0
	add_child(center)

	var cabinet := OneGunCabinet.new()
	cabinet.name = "LobbyPlayerHubCabinet"
	cabinet.variant = OneGunCabinet.Variant.CABINET
	cabinet.content_padding = 28 if _context == "home" else 24
	var available := get_viewport_rect().size - Vector2(72.0, 72.0)
	cabinet.custom_minimum_size = Vector2(
		minf(1260.0 if _context == "home" else 1060.0, available.x),
		minf(650.0 if _context == "home" else 520.0, available.y))
	center.add_child(cabinet)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	cabinet.get_content().add_child(column)
	var title := OneGunUI.make_heading("PLAYER HUB", 38, "gold")
	column.add_child(title)

	if _context == "home":
		column.add_child(_make_account_strip())

	var destinations := HBoxContainer.new()
	destinations.size_flags_vertical = Control.SIZE_EXPAND_FILL
	destinations.add_theme_constant_override("separation", 14)
	column.add_child(destinations)
	var definitions: Array = [
		["locker", "LOCKER", "Choose your cat, colors, and owned cosmetics. Changes update the online roster."],
		["prize_counter", "PRIZE COUNTER", "Browse rotating rewards, bundles, and your Gun Token balance."],
		["progression", "PROGRESSION", "Review Season XP, Trophy Road milestones, Career levels, and rewards."],
	]
	if _context == "home":
		definitions.push_front([
			"profile", "PROFILE", "Manage your account identity and review official stats, Match History, and Legacy Hall."])
	for definition in definitions:
		var card := _make_destination_card(str(definition[0]), str(definition[1]),
			str(definition[2]))
		destinations.add_child(card)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	var close_button := OneGunButton.new()
	close_button.name = "ClosePlayerHubButton"
	close_button.text = "BACK"
	close_button.variant = "navy"
	close_button.custom_minimum_size = Vector2(220.0, 60.0)
	close_button.pressed.connect(_close)
	footer.add_child(close_button)
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_spacer)
	_focus_buttons.append(close_button)
	_connect_focus_loop()


func _make_destination_card(destination: String, title: String,
		description: String) -> Control:
	var accent := _destination_color(destination)
	var panel := PanelContainer.new()
	panel.name = "%sCard" % title.to_pascal_case().replace(" ", "")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(0.008, 0.025, 0.052), Color(accent, 0.82),
		14, 2, 0, 16.0))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var eyebrow := OneGunUI.make_label(_destination_eyebrow(destination), 11, "muted", true)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(eyebrow)
	var heading := OneGunUI.make_heading(title, 24, _destination_role(destination))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var copy := OneGunUI.make_label(description, 14, "text")
	copy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(copy)
	var button := OneGunButton.new()
	button.name = "Open%sButton" % title.to_pascal_case().replace(" ", "")
	button.text = "OPEN %s" % title
	button.variant = _destination_variant(destination)
	button.custom_minimum_size = Vector2(0.0, 54.0)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(func() -> void:
		destination_requested.emit(destination))
	column.add_child(button)
	_focus_buttons.append(button)
	if _first_button == null:
		_first_button = button
	return panel


func _make_account_strip() -> Control:
	var panel := PanelContainer.new()
	panel.name = "PlayerHubAccountStrip"
	panel.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(0.006, 0.018, 0.038, 0.96), Color(OneGunUI.color("cyan"), 0.55),
		10, 1, 0, 12.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var identity := "LOCAL PROFILE"
	if SupabaseManager.is_authenticated():
		var account_name := SupabaseManager.current_account_name().strip_edges()
		identity = "SIGNED IN — %s" % (
			account_name.to_upper() if account_name != "" else "CLOUD PROFILE")
	var identity_label := OneGunUI.make_heading(identity, 18,
		"positive" if SupabaseManager.is_authenticated() else "text")
	identity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(identity_label)
	row.add_child(_make_status_chip("%d GUN TOKENS" % SupabaseManager.gun_tokens, "gold"))
	var progress: Dictionary = ProgressionManager.progression.get("progress", {}) \
		if ProgressionManager.progression.get("progress", {}) is Dictionary else {}
	row.add_child(_make_status_chip("%d TROPHIES" % int(progress.get("trophies", 0)), "cyan"))
	return panel


func _make_status_chip(text: String, role: String) -> Control:
	var chip := PanelContainer.new()
	var accent := OneGunUI.color(role)
	chip.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(accent, 0.12), Color(accent, 0.72), 14, 1, 0, 9.0))
	var label := OneGunUI.make_label(text, 11, role, true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(label)
	return chip


func _destination_role(destination: String) -> String:
	match destination:
		"profile": return "cyan"
		"locker": return "gold"
		"prize_counter": return "cyan"
		_: return "green"


func _destination_variant(destination: String) -> String:
	match destination:
		"profile", "prize_counter": return "navy"
		"locker": return "gold"
		_: return "green"


func _destination_color(destination: String) -> Color:
	return OneGunUI.color(_destination_role(destination))


func _destination_eyebrow(destination: String) -> String:
	match destination:
		"profile": return "IDENTITY & CAREER"
		"locker": return "OWNED LOADOUT"
		"prize_counter": return "SHOP & REWARDS"
		_: return "SEASON & CAREER"


func _connect_focus_loop() -> void:
	if _focus_buttons.is_empty():
		return
	var back_button := _focus_buttons[-1]
	for index in _focus_buttons.size():
		var button := _focus_buttons[index]
		var previous := _focus_buttons[(index - 1 + _focus_buttons.size()) % _focus_buttons.size()]
		var next := _focus_buttons[(index + 1) % _focus_buttons.size()]
		button.focus_previous = button.get_path_to(previous)
		button.focus_next = button.get_path_to(next)
		if button != back_button:
			button.focus_neighbor_bottom = button.get_path_to(back_button)
			if index > 0:
				button.focus_neighbor_left = button.get_path_to(
					_focus_buttons[index - 1])
			if index + 1 < _focus_buttons.size() - 1:
				button.focus_neighbor_right = button.get_path_to(
					_focus_buttons[index + 1])
	if _first_button != null and back_button != null:
		back_button.focus_neighbor_top = back_button.get_path_to(_first_button)


func _focus_first() -> void:
	if not _using_pointer and _first_button != null \
			and is_instance_valid(_first_button) \
			and get_viewport().gui_get_focus_owner() == null:
		_first_button.grab_focus()


func _close() -> void:
	closed.emit()
	queue_free()
