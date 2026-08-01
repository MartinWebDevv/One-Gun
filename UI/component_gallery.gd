extends Control

# Component gallery / debug scene (packet Phase 1). Shows every shared ONE
# GUN component in every interaction state so visual approval and regression
# checks happen in one place. Not part of any gameplay flow.
#
# Run:  godot --path . res://UI/component_gallery.tscn
# Capture screenshots for review (writes docs/screenshots/menu_redesign/):
#       set ONEGUN_GALLERY_CAPTURE=1, or pass user args: -- --capture

const CAPTURE_DIR := "res://docs/screenshots/menu_redesign/"
const CAPTURE_SIZES := {
	"component_gallery_1920x1080.png": Vector2i(1920, 1080),
	"component_gallery_1280x720.png": Vector2i(1280, 720),
}

var _first_focus: Control = null
var _scroll: ScrollContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = OneGunUI.color("canvas")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, OneGunUI.SPACE_XL)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	margin.add_child(root)

	var title := OneGunUI.make_heading("ONE GUN — UI COMPONENT GALLERY", OneGunUI.TEXT_XL)
	root.add_child(title)
	root.add_child(OneGunUI.make_label(
		"Phase 1 foundation. Tab/arrows walk focus; every control supports mouse, keyboard, and controller.",
		OneGunUI.TEXT_S, "muted"))

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	root.add_child(_scroll)

	var sections := VBoxContainer.new()
	sections.add_theme_constant_override("separation", OneGunUI.SPACE_L)
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(sections)

	_build_buttons_section(sections)
	_build_inputs_section(sections)
	_build_tabs_section(sections)
	_build_cabinet_section(sections)
	_build_icons_section(sections)
	_build_roster_section(sections)
	_build_lobby_section(sections)
	_build_map_cards_section(sections)
	_build_status_section(sections)

	if _first_focus != null:
		_first_focus.grab_focus.call_deferred()

	print("component_gallery ready — user_args=%s capture_env=%s" % [
		OS.get_cmdline_user_args(), OS.get_environment("ONEGUN_GALLERY_CAPTURE")])
	if OS.get_cmdline_user_args().has("--capture") \
			or OS.get_environment("ONEGUN_GALLERY_CAPTURE") == "1":
		_capture_screens.call_deferred()


func _section(parent: Control, heading: String) -> HFlowContainer:
	parent.add_child(OneGunUI.make_heading(heading, OneGunUI.TEXT_L))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", OneGunUI.SPACE_L)
	flow.add_theme_constant_override("v_separation", OneGunUI.SPACE_M)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(flow)
	return flow


func _build_buttons_section(parent: Control) -> void:
	var flow := _section(parent, "ACTION BUTTONS")
	for variant in OneGunButton.VARIANTS:
		var button := OneGunButton.new()
		button.variant = variant
		button.text = variant.to_upper()
		flow.add_child(button)
		if _first_focus == null:
			_first_focus = button
	var disabled := OneGunButton.new()
	disabled.variant = "gold"
	disabled.text = "DISABLED"
	disabled.disabled = true
	flow.add_child(disabled)

	var confirm := OneGunConfirmButton.new()
	confirm.variant = "navy"
	confirm.text = "LEAVE MATCH"
	confirm.confirm_text = "CONFIRM LEAVE"
	flow.add_child(confirm)
	var confirm_note := OneGunUI.make_label("← two-click inline confirm (5 s reset)", OneGunUI.TEXT_S, "muted")
	confirm_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flow.add_child(confirm_note)


func _build_inputs_section(parent: Control) -> void:
	var flow := _section(parent, "TOGGLES, STEPPER, SLIDERS, FIELDS")

	var toggle_on := OneGunToggle.new()
	toggle_on.button_pressed = true
	flow.add_child(toggle_on)
	var toggle_off := OneGunToggle.new()
	flow.add_child(toggle_off)
	var toggle_locked := OneGunToggle.new()
	toggle_locked.button_pressed = true
	toggle_locked.disabled = true
	flow.add_child(toggle_locked)

	var stepper := OneGunStepper.new()
	stepper.min_value = 0
	stepper.max_value = 10
	stepper.value = 3
	flow.add_child(stepper)

	var dropdown := OneGunUI.make_dropdown(PackedStringArray(["Easy", "Medium", "Hard", "Expert"]))
	dropdown.select(1)
	flow.add_child(dropdown)

	var checkbox := OneGunUI.style_checkbox(CheckBox.new())
	checkbox.text = "Checkbox option"
	flow.add_child(checkbox)

	var help := OneGunHelpIcon.new()
	help.tooltip_text = "Help icons explain non-obvious rules."
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flow.add_child(help)

	var slider_column := VBoxContainer.new()
	slider_column.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	slider_column.custom_minimum_size = Vector2(620.0, 0.0)
	var sensitivity := OneGunSliderRow.new()
	sensitivity.label_text = "Mouse Sensitivity"
	sensitivity.help_text = "How fast the camera turns per unit of mouse movement."
	sensitivity.min_value = 0.05
	sensitivity.max_value = 3.0
	sensitivity.step = 0.01
	sensitivity.value = 0.69
	slider_column.add_child(sensitivity)
	var volume := OneGunSliderRow.new()
	volume.label_text = "Master Volume"
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.value = 0.8
	volume.display_format = "%d%%"
	volume.display_scale = 100.0
	slider_column.add_child(volume)
	parent.add_child(slider_column)

	var error_row := VBoxContainer.new()
	error_row.add_theme_constant_override("separation", OneGunUI.SPACE_XS)
	error_row.custom_minimum_size = Vector2(420.0, 0.0)
	error_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var field := LineEdit.new()
	field.placeholder_text = "ENTER LOBBY CODE"
	field.custom_minimum_size = Vector2(300.0, 0.0)
	error_row.add_child(field)
	var inline_error := OneGunInlineError.new()
	error_row.add_child(inline_error)
	var trigger := OneGunButton.new()
	trigger.variant = "navy"
	trigger.font_size = OneGunUI.TEXT_S
	trigger.text = "TRIGGER VALIDATION ERROR"
	trigger.pressed.connect(func() -> void:
		inline_error.show_error("That lobby code is invalid or has expired."))
	error_row.add_child(trigger)
	parent.add_child(error_row)


func _build_tabs_section(parent: Control) -> void:
	var flow := _section(parent, "TABS / SEGMENTED CONTROL")
	var tabs := OneGunTabBar.new()
	tabs.tabs = PackedStringArray(["GENERAL", "COMBAT", "SPAWNS", "PRESETS"])
	flow.add_child(tabs)


func _build_cabinet_section(parent: Control) -> void:
	var flow := _section(parent, "CABINET / SECTION / WELL FRAMES")
	var specs := [
		[OneGunCabinet.Variant.CABINET, "CABINET FRAME", "Gold rim, navy face, bolts."],
		[OneGunCabinet.Variant.SECTION, "SECTION FRAME", "Raised section inside a face."],
		[OneGunCabinet.Variant.WELL, "CONTENT WELL", "Recessed list/preview area."],
	]
	for spec in specs:
		var cabinet := OneGunCabinet.new()
		cabinet.variant = spec[0]
		cabinet.custom_minimum_size = Vector2(300.0, 130.0)
		flow.add_child(cabinet)
		var box := VBoxContainer.new()
		box.add_child(OneGunUI.make_heading(spec[1], OneGunUI.TEXT_M))
		box.add_child(OneGunUI.make_label(spec[2], OneGunUI.TEXT_S, "muted"))
		cabinet.get_content().add_child(box)


func _build_icons_section(parent: Control) -> void:
	var flow := _section(parent, "INDICATOR ICONS")
	for kind_name in OneGunIcon.Kind.keys():
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		var center := CenterContainer.new()
		var icon := OneGunIcon.new()
		icon.kind = OneGunIcon.Kind[kind_name]
		icon.custom_minimum_size = Vector2(28.0, 28.0)
		match icon.kind:
			OneGunIcon.Kind.CROWN:
				icon.icon_color = OneGunUI.color("gold")
			OneGunIcon.Kind.CHECK:
				icon.icon_color = OneGunUI.color("green")
			OneGunIcon.Kind.CROSS, OneGunIcon.Kind.WARNING:
				icon.icon_color = OneGunUI.color("red")
			OneGunIcon.Kind.SPINNER:
				icon.icon_color = OneGunUI.color("cyan")
		center.add_child(icon)
		cell.add_child(center)
		var caption := OneGunUI.make_label(kind_name.capitalize(), OneGunUI.TEXT_XS, "muted")
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(caption)
		flow.add_child(cell)


func _build_roster_section(parent: Control) -> void:
	parent.add_child(OneGunUI.make_heading("ROSTER ROWS", OneGunUI.TEXT_L))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	column.custom_minimum_size = Vector2(520.0, 0.0)
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(column)

	var host_row := OneGunRosterRow.new()
	column.add_child(host_row)
	host_row.set_human.call_deferred("Player 1", true, true, OneGunRosterRow.ReadyState.READY)
	var guest_row := OneGunRosterRow.new()
	column.add_child(guest_row)
	guest_row.set_human.call_deferred("Player 2", false, false, OneGunRosterRow.ReadyState.NOT_READY)
	var bot_row := OneGunRosterRow.new()
	column.add_child(bot_row)
	bot_row.set_bot.call_deferred("Bot 1", "Medium")
	var empty_row := OneGunRosterRow.new()
	column.add_child(empty_row)
	empty_row.set_empty.call_deferred(4)


func _build_lobby_section(parent: Control) -> void:
	parent.add_child(OneGunUI.make_heading("LOBBY BROWSER ROWS", OneGunUI.TEXT_L))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	column.custom_minimum_size = Vector2(680.0, 0.0)
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(column)

	# Gallery-only sample data, clearly labeled — never shown in real menus.
	var samples := [
		["Sample Public Lobby", OneGunLobbyRow.Privacy.PUBLIC, 3, 10, "One Gun", OneGunLobbyRow.Joinability.JOINABLE, true],
		["Sample Friends Lobby", OneGunLobbyRow.Privacy.FRIENDS_ONLY, 6, 10, "One Gun", OneGunLobbyRow.Joinability.IN_PROGRESS, false],
		["Sample Private Lobby", OneGunLobbyRow.Privacy.PRIVATE, 10, 10, "One Gun", OneGunLobbyRow.Joinability.FULL, false],
	]
	for sample in samples:
		var row := OneGunLobbyRow.new()
		column.add_child(row)
		row.set_lobby.call_deferred(sample[0], sample[1], sample[2], sample[3], sample[4], sample[5])
		if sample[6]:
			row.set_deferred("is_selected", true)


func _build_map_cards_section(parent: Control) -> void:
	var flow := _section(parent, "MAP CARDS")
	var tints := [Color(0.16, 0.32, 0.2), Color(0.35, 0.26, 0.14), Color(0.2, 0.22, 0.34)]
	var names := ["Whispering Woods", "Western Town", "Maple & 3rd"]
	for index in names.size():
		var card := OneGunMapCard.new()
		flow.add_child(card)
		card.set_map.call_deferred(index, names[index], null, tints[index])
		if index == 0:
			card.set_selected.call_deferred(true)


func _build_status_section(parent: Control) -> void:
	var flow := _section(parent, "ASYNC / EMPTY / ERROR STATES")
	var states := ["loading", "empty", "error", "unavailable"]
	for state in states:
		var well := OneGunCabinet.new()
		well.variant = OneGunCabinet.Variant.WELL
		well.custom_minimum_size = Vector2(360.0, 190.0)
		flow.add_child(well)
		var panel := OneGunStatusPanel.new()
		well.get_content().add_child(panel)
		match state:
			"loading":
				panel.show_loading.call_deferred("Searching for lobbies…")
			"empty":
				panel.show_empty.call_deferred("NO LOBBIES FOUND", "Host one, or refresh to search again.")
			"error":
				panel.show_error.call_deferred("REFRESH FAILED", "The discovery service did not respond.")
			"unavailable":
				panel.show_unavailable.call_deferred("OFFLINE", "Connect to the network to browse lobbies.")


func _capture_screens() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var dir_path := ProjectSettings.globalize_path(CAPTURE_DIR)
	DirAccess.make_dir_recursive_absolute(dir_path)
	for file_name: String in CAPTURE_SIZES:
		DisplayServer.window_set_size(CAPTURE_SIZES[file_name])
		for scroll_pass in ["top", "bottom"]:
			_scroll.scroll_vertical = 0 if scroll_pass == "top" else 1000000
			await get_tree().process_frame
			await get_tree().create_timer(0.5).timeout
			var image := get_viewport().get_texture().get_image()
			var shot_name := file_name.replace(".png", "_%s.png" % scroll_pass)
			var err := image.save_png(dir_path.path_join(shot_name))
			print("gallery capture %s -> %s" % [shot_name, error_string(err)])
	get_tree().quit()
