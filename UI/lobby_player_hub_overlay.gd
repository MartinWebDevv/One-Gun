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
	scrim.name="PlayerHubScrim"
	scrim.color=OneGunUI.color("canvas")
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left=32
	center.offset_right=-32
	center.offset_top=32
	center.offset_bottom=-32
	add_child(center)
	var cabinet:=OneGunCabinet.new()
	cabinet.name="LobbyPlayerHubCabinet"
	cabinet.content_padding=24
	cabinet.custom_minimum_size=Vector2(minf(1200,get_viewport_rect().size.x-64),minf(650,get_viewport_rect().size.y-64))
	center.add_child(cabinet)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",18)
	cabinet.get_content().add_child(column)
	column.add_child(OneGunUI.make_heading("PLAYER HUB",38,"text"))
	if _context=="home": column.add_child(_make_account_strip())
	var body:=HBoxContainer.new()
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",18)
	column.add_child(body)
	var identity:=PanelContainer.new()
	identity.name="HubIdentity"
	identity.custom_minimum_size.x=240
	identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	identity.size_flags_stretch_ratio=0.8
	identity.add_theme_stylebox_override("panel",OneGunUI.style_box(OneGunUI.color("well"),OneGunUI.color("border"),8,1,0,14))
	body.add_child(identity)
	var identity_column:=VBoxContainer.new()
	identity.add_child(identity_column)
	var portrait:=preload("res://UI/components/character_portrait.gd").new()
	portrait.name="HubPortrait"
	portrait.set_appearance(str(PlayerPrefs.get_setting("character_skin_id")),str(PlayerPrefs.get_setting("character_model_id")))
	portrait.size_flags_vertical=Control.SIZE_EXPAND_FILL
	portrait.custom_minimum_size.y=230
	identity_column.add_child(portrait)
	var alias_label:=OneGunUI.make_heading(str(PlayerPrefs.get_setting("player_name")),30,"text")
	alias_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	alias_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	identity_column.add_child(alias_label)
	var destinations:=GridContainer.new()
	destinations.name="HubDestinationGrid"
	destinations.columns=2
	destinations.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	destinations.size_flags_stretch_ratio=2.0
	destinations.add_theme_constant_override("h_separation",12)
	destinations.add_theme_constant_override("v_separation",12)
	body.add_child(destinations)
	var definitions: Array=[["locker","Locker","closet_rack"],["prize_counter","Prize Counter","star"],["progression","Progression","steps"]]
	if _context=="home": definitions.push_front(["profile","Profile",""])
	for definition in definitions:
		destinations.add_child(_make_destination_card(definition[0],definition[1],definition[2]))
	var close_button:=OneGunButton.new()
	close_button.name="ClosePlayerHubButton"
	close_button.text="Back"
	close_button.icon=preload("res://UI/menu_icons.gd").get_icon("back")
	close_button.custom_minimum_size=Vector2(180,48)
	close_button.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	close_button.pressed.connect(_close)
	column.add_child(close_button)
	_focus_buttons.append(close_button)
	_connect_focus_loop()

func _make_destination_card(destination: String, title: String, art: String) -> Control:
	var button:=OneGunButton.new()
	button.name="Open%sButton" % title.to_pascal_case().replace(" ","")
	button.custom_minimum_size=Vector2(218,174)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.size_flags_vertical=Control.SIZE_EXPAND_FILL
	button.ready.connect(func():
		button.add_theme_stylebox_override("hover",OneGunUI.style_box(OneGunUI.color("face_raised"),OneGunUI.color("gold"),8,2,0,14)))
	button.tooltip_text=title
	button.accessibility_name=title
	button.pressed.connect(func(): destination_requested.emit(destination))
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,12)
	button.add_child(margin)
	var column:=VBoxContainer.new()
	column.mouse_filter=Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var picture: TextureRect
	if destination=="profile":
		picture=preload("res://UI/components/character_portrait.gd").new()
		picture.set_appearance(str(PlayerPrefs.get_setting("character_skin_id")),str(PlayerPrefs.get_setting("character_model_id")))
	else:
		picture=TextureRect.new()
		picture.texture=load("res://UI/assets/hideout/"+art+".png")
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical=Control.SIZE_EXPAND_FILL
	picture.custom_minimum_size.y=105
	picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	column.add_child(picture)
	var label:=OneGunUI.make_heading(title,26,"text")
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	_focus_buttons.append(button)
	if _first_button==null: _first_button=button
	return button


func _make_account_strip() -> Control:
	var panel := PanelContainer.new()
	panel.name = "PlayerHubAccountStrip"
	panel.add_theme_stylebox_override("panel", OneGunUI.style_box(
		OneGunUI.color("well"), OneGunUI.color("border"),
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


func _connect_focus_loop() -> void:
	var count:=_focus_buttons.size()-1
	var back:=_focus_buttons[-1]
	for i in count:
		var button:=_focus_buttons[i]
		button.focus_neighbor_left=button.get_path_to(_focus_buttons[i-1] if i%2 else button)
		button.focus_neighbor_right=button.get_path_to(_focus_buttons[i+1] if i%2==0 and i+1<count else button)
		button.focus_neighbor_top=button.get_path_to(_focus_buttons[i-2] if i>=2 else button)
		button.focus_neighbor_bottom=button.get_path_to(_focus_buttons[i+2] if i+2<count else back)
	for i in _focus_buttons.size():
		var button:=_focus_buttons[i]
		button.focus_next=button.get_path_to(_focus_buttons[(i+1)%_focus_buttons.size()])
		button.focus_previous=button.get_path_to(_focus_buttons[(i-1+_focus_buttons.size())%_focus_buttons.size()])
	back.focus_neighbor_top=back.get_path_to(_first_button)


func _focus_first() -> void:
	if not _using_pointer and _first_button != null \
			and is_instance_valid(_first_button) \
			and get_viewport().gui_get_focus_owner() == null:
		_first_button.grab_focus()


func _close() -> void:
	closed.emit()
	queue_free()
