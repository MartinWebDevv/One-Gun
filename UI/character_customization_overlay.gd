class_name CharacterCustomizationOverlay
extends Control

signal closed
signal skin_changed(player_slot: int, skin_id: String)

const SkinRegistry = preload("res://player_skin_registry.gd")
const VISUAL_SCENE = preload("res://models/player_v2/player_v2_visual.tscn")
const COLOR_CARD_SCRIPT = preload("res://UI/components/character_color_card.gd")
const BASE_SIZE := Vector2(1600.0, 900.0)
const LEFT_PANEL_RECT := Rect2(64.0, 142.0, 566.0, 638.0)
const RIGHT_PANEL_RECT := Rect2(658.0, 142.0, 878.0, 638.0)

var online_mode := false
var local_player_count := 1

var _canvas: Control
var _preview_pivot: Node3D
var _preview_visual: Node3D
var _player_name_label: Label
var _selected_color_label: Label
var _player_tabs: Array[OneGunButton] = []
var _color_cards: Array = []
var _pending_skin_ids: Dictionary = {}
var _confirmed_skin_ids: Dictionary = {}
var _active_slot := 0
var _dragging_preview := false
var _confirm_button: OneGunButton


func configure(is_online: bool, player_count: int) -> void:
	online_mode = is_online
	local_player_count = 1 if online_mode else clampi(player_count, 1, 2)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_snapshot_confirmed_colors()
	_build_ui()
	_apply_responsive_layout()
	resized.connect(_apply_responsive_layout)
	set_process(true)


func _process(delta: float) -> void:
	if _preview_pivot == null:
		return
	var prefix := "p%d" % (_active_slot + 1)
	var left_action := prefix + "_look_left"
	var right_action := prefix + "_look_right"
	var look_axis := 0.0
	if InputMap.has_action(left_action) and InputMap.has_action(right_action):
		look_axis = Input.get_action_strength(right_action) \
			- Input.get_action_strength(left_action)
	if absf(look_axis) >= 0.08:
		_preview_pivot.rotate_y(-look_axis * delta * 2.2)
	elif not _dragging_preview and not _reduced_motion_enabled():
		_preview_pivot.rotate_y(delta * 0.26)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_cancel()
		return
	var prefix := "p%d" % (_active_slot + 1)
	if event.is_action_pressed(prefix + "_cycle_left"):
		accept_event()
		_cycle_skin(-1)
	elif event.is_action_pressed(prefix + "_cycle_right"):
		accept_event()
		_cycle_skin(1)


func _snapshot_confirmed_colors() -> void:
	_confirmed_skin_ids.clear()
	_pending_skin_ids.clear()
	for slot in local_player_count:
		var skin_id := _stored_skin_for_slot(slot)
		_confirmed_skin_ids[slot] = skin_id
		_pending_skin_ids[slot] = skin_id


func _build_ui() -> void:
	var scrim := ColorRect.new()
	scrim.name = "CustomizationScrim"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.008, 0.014, 0.038, 0.975)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	_canvas = Control.new()
	_canvas.name = "CustomizationCanvas"
	_canvas.size = BASE_SIZE
	add_child(_canvas)
	_build_backdrop()
	_build_header()
	_build_player_tabs()
	_build_preview_panel()
	_build_selection_panel()
	_build_action_bar()
	_refresh_active_player()


func _build_backdrop() -> void:
	var background := ColorRect.new()
	background.name = "NavyBackdrop"
	background.position = Vector2.ZERO
	background.size = BASE_SIZE
	background.color = Color(0.018, 0.030, 0.070)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(background)

	var top_glow := ColorRect.new()
	top_glow.name = "TopGlow"
	top_glow.position = Vector2(0.0, 0.0)
	top_glow.size = Vector2(BASE_SIZE.x, 128.0)
	top_glow.color = Color(0.055, 0.105, 0.20, 0.34)
	top_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(top_glow)

	var bottom_rule := ColorRect.new()
	bottom_rule.position = Vector2(0.0, 896.0)
	bottom_rule.size = Vector2(BASE_SIZE.x, 4.0)
	bottom_rule.color = OneGunUI.color("gold").darkened(0.2)
	bottom_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(bottom_rule)


func _build_header() -> void:
	var title_row := HBoxContainer.new()
	title_row.name = "CustomizationTitleRow"
	title_row.position = Vector2(190.0, 18.0)
	title_row.size = Vector2(1220.0, 52.0)
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 16)
	_canvas.add_child(title_row)

	for index in 3:
		if index != 1:
			var star := OneGunUI.make_heading("★", 32, "gold")
			star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			title_row.add_child(star)
		else:
			var title := OneGunUI.make_heading(
				"CHARACTER CUSTOMIZATION", 42, "text_bright")
			title.name = "CustomizationTitle"
			title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			title_row.add_child(title)

	var subtitle := OneGunUI.make_label(
		"PERSONALIZE YOUR CHARACTER  •  13 COLORS AVAILABLE NOW  •  SKINS COMING SOON",
		17, "muted")
	subtitle.name = "CustomizationSubtitle"
	subtitle.position = Vector2(250.0, 72.0)
	subtitle.size = Vector2(1100.0, 28.0)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_canvas.add_child(subtitle)


func _build_player_tabs() -> void:
	if local_player_count < 2:
		return
	var tab_row := HBoxContainer.new()
	tab_row.name = "LocalPlayerTabs"
	tab_row.position = Vector2(570.0, 103.0)
	tab_row.size = Vector2(460.0, 38.0)
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 10)
	_canvas.add_child(tab_row)
	for slot in local_player_count:
		var tab := OneGunButton.new()
		tab.name = "Player%dTab" % (slot + 1)
		tab.text = "PLAYER %d" % (slot + 1)
		tab.font_size = OneGunUI.TEXT_S
		tab.custom_minimum_size = Vector2(180.0, 36.0)
		tab.pressed.connect(_set_active_slot.bind(slot))
		tab_row.add_child(tab)
		_player_tabs.append(tab)


func _build_preview_panel() -> void:
	var panel := OneGunCabinet.new()
	panel.name = "CharacterPreviewPanel"
	panel.variant = OneGunCabinet.Variant.SECTION
	panel.content_padding = 16
	panel.position = LEFT_PANEL_RECT.position
	panel.size = LEFT_PANEL_RECT.size
	_canvas.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "PreviewColumn"
	column.add_theme_constant_override("separation", 5)
	panel.get_content().add_child(column)

	_player_name_label = OneGunUI.make_heading("PLAYER", 25, "gold")
	_player_name_label.name = "PreviewPlayerName"
	_player_name_label.custom_minimum_size.y = 33.0
	_player_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(_player_name_label)

	var color_row := HBoxContainer.new()
	color_row.alignment = BoxContainer.ALIGNMENT_CENTER
	color_row.add_theme_constant_override("separation", 8)
	column.add_child(color_row)
	var crown := OneGunIcon.new()
	crown.kind = OneGunIcon.Kind.CROWN
	crown.icon_color = OneGunUI.color("gold")
	crown.custom_minimum_size = Vector2(21.0, 21.0)
	color_row.add_child(crown)
	_selected_color_label = OneGunUI.make_label("BLUE", 17, "gold", true)
	_selected_color_label.name = "SelectedColor"
	_selected_color_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	color_row.add_child(_selected_color_label)

	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "CharacterPreview"
	viewport_container.custom_minimum_size = Vector2(0.0, 500.0)
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.stretch = true
	viewport_container.mouse_default_cursor_shape = Control.CURSOR_DRAG
	viewport_container.gui_input.connect(_on_preview_gui_input)
	column.add_child(viewport_container)
	_build_preview_world(viewport_container)

	var rotate_hint := OneGunUI.make_label(
		"↶  DRAG OR USE THE RIGHT STICK TO ROTATE  ↷", 14, "muted", true)
	rotate_hint.name = "RotateHint"
	rotate_hint.custom_minimum_size.y = 27.0
	rotate_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotate_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(rotate_hint)


func _build_preview_world(container: SubViewportContainer) -> void:
	var viewport := SubViewport.new()
	viewport.name = "CharacterViewport"
	viewport.size = Vector2i(640, 640)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	var world := Node3D.new()
	world.name = "PreviewWorld"
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.018, 0.033, 0.075)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.93)
	env.ambient_light_energy = 1.05
	environment.environment = env
	world.add_child(environment)

	_build_preview_podium(world)
	_preview_pivot = Node3D.new()
	_preview_pivot.name = "CharacterPivot"
	# Sink the feet a few centimeters into the top disc to avoid a visible gap
	# from perspective/shadow bias at menu-camera distances.
	_preview_pivot.position.y = 0.30
	world.add_child(_preview_pivot)
	_preview_visual = VISUAL_SCENE.instantiate()
	_preview_visual.name = "PreviewCharacter"
	_preview_visual.set("build_animation_library", false)
	_preview_pivot.add_child(_preview_visual)
	var animation_player := _preview_visual.call("ensure_animations", ["idle"]) as AnimationPlayer
	if animation_player != null and animation_player.has_animation("idle"):
		animation_player.play("idle", 0.0)
		animation_player.advance(0.0)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	key.light_color = Color(1.0, 0.86, 0.68)
	key.light_energy = 2.45
	key.shadow_enabled = true
	world.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(1.8, 2.1, -1.8)
	rim.light_color = Color(0.28, 0.60, 1.0)
	rim.light_energy = 3.2
	rim.omni_range = 6.0
	world.add_child(rim)
	var pedestal_light := OmniLight3D.new()
	pedestal_light.position = Vector3(0.0, 0.45, 0.0)
	pedestal_light.light_color = OneGunUI.color("gold")
	pedestal_light.light_energy = 2.0
	pedestal_light.omni_range = 2.8
	world.add_child(pedestal_light)

	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.fov = 38.0
	camera.look_at_from_position(
		Vector3(-2.65, 1.78, 4.95), Vector3(0.0, 1.27, 0.0), Vector3.UP)
	world.add_child(camera)
	camera.current = true


func _build_preview_podium(world: Node3D) -> void:
	var rings := [
		{"radius": 1.28, "height": 0.15, "y": 0.075,
		 "color": Color(0.035, 0.055, 0.11), "metallic": 0.8, "emission": Color.BLACK},
		{"radius": 1.16, "height": 0.12, "y": 0.19,
		 "color": OneGunUI.color("gold").darkened(0.18), "metallic": 0.75,
		 "emission": Color(OneGunUI.color("gold"), 0.28)},
		{"radius": 1.05, "height": 0.12, "y": 0.27,
		 "color": Color(0.08, 0.14, 0.26), "metallic": 0.55,
		 "emission": Color(0.05, 0.12, 0.24, 0.45)},
	]
	for data in rings:
		var mesh_instance := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = float(data["radius"])
		cylinder.bottom_radius = float(data["radius"])
		cylinder.height = float(data["height"])
		cylinder.radial_segments = 64
		mesh_instance.mesh = cylinder
		mesh_instance.position.y = float(data["y"])
		var material := StandardMaterial3D.new()
		material.albedo_color = data["color"] as Color
		material.metallic = float(data["metallic"])
		material.roughness = 0.24
		var emission := data["emission"] as Color
		if emission != Color.BLACK:
			material.emission_enabled = true
			material.emission = emission
			material.emission_energy_multiplier = 1.35
		mesh_instance.material_override = material
		world.add_child(mesh_instance)


func _build_selection_panel() -> void:
	var panel := OneGunCabinet.new()
	panel.name = "CharacterCustomizationCabinet"
	panel.variant = OneGunCabinet.Variant.CABINET
	panel.content_padding = 16
	panel.position = RIGHT_PANEL_RECT.position
	panel.size = RIGHT_PANEL_RECT.size
	_canvas.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "SelectionColumn"
	column.add_theme_constant_override("separation", 6)
	panel.get_content().add_child(column)

	var category_tabs := HBoxContainer.new()
	category_tabs.name = "CategoryTabs"
	category_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	category_tabs.add_theme_constant_override("separation", 10)
	column.add_child(category_tabs)
	var colors_tab := OneGunButton.new()
	colors_tab.name = "ColorsTab"
	colors_tab.text = "COLORS"
	colors_tab.variant = "gold"
	colors_tab.custom_minimum_size = Vector2(398.0, 52.0)
	category_tabs.add_child(colors_tab)
	var skins_tab := OneGunButton.new()
	skins_tab.name = "SkinsTab"
	skins_tab.text = "SKINS  •  COMING SOON"
	skins_tab.variant = "navy"
	skins_tab.disabled = true
	skins_tab.tooltip_text = "Skins are coming soon"
	skins_tab.custom_minimum_size = Vector2(398.0, 52.0)
	category_tabs.add_child(skins_tab)

	column.add_child(_make_divider_heading("★   CHOOSE A COLOR   ★"))
	var grid := VBoxContainer.new()
	grid.name = "ColorGrid"
	grid.add_theme_constant_override("separation", 10)
	column.add_child(grid)
	var index := 0
	for row_index in 3:
		var row := HBoxContainer.new()
		row.name = "ColorRow%d" % (row_index + 1)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		grid.add_child(row)
		var count := 5 if row_index < 2 else 3
		for _column_index in count:
			var skin_id := SkinRegistry.skin_id_at(index)
			var card = COLOR_CARD_SCRIPT.new()
			card.name = "ColorCard_%s" % skin_id.capitalize()
			card.setup(skin_id)
			card.color_chosen.connect(_select_skin)
			row.add_child(card)
			_color_cards.append(card)
			index += 1

	column.add_child(_make_divider_heading("SKINS  •  COMING SOON"))
	var locked_row := HBoxContainer.new()
	locked_row.name = "LockedSkins"
	locked_row.alignment = BoxContainer.ALIGNMENT_CENTER
	locked_row.add_theme_constant_override("separation", 12)
	column.add_child(locked_row)
	for locked_index in 5:
		locked_row.add_child(_make_locked_skin_card(locked_index + 1))


func _make_divider_heading(text: String) -> Control:
	var holder := HBoxContainer.new()
	holder.custom_minimum_size.y = 28.0
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_theme_constant_override("separation", 12)
	for index in 3:
		if index != 1:
			var line := ColorRect.new()
			line.custom_minimum_size = Vector2(175.0, 1.0)
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.color = Color(OneGunUI.color("gold"), 0.42)
			holder.add_child(line)
		else:
			var label := OneGunUI.make_label(text, 16, "gold")
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			holder.add_child(label)
	return holder


func _make_locked_skin_card(index: int) -> Control:
	var card := PanelContainer.new()
	card.name = "FutureSkin%d" % index
	card.custom_minimum_size = Vector2(138.0, 74.0)
	card.tooltip_text = "Future skin — coming soon"
	card.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(OneGunUI.color("well"), 0.72),
		Color(OneGunUI.color("border"), 0.48), 11, 1))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)
	var lock := OneGunIcon.new()
	lock.kind = OneGunIcon.Kind.LOCK
	lock.icon_color = Color(OneGunUI.color("muted"), 0.72)
	lock.custom_minimum_size = Vector2(31.0, 31.0)
	lock.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(lock)
	var label := OneGunUI.make_label("COMING SOON", 10, "muted", true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	return card


func _build_action_bar() -> void:
	var back := OneGunButton.new()
	back.name = "Back"
	back.text = "BACK"
	back.variant = "navy"
	back.position = Vector2(64.0, 808.0)
	back.size = Vector2(220.0, 60.0)
	back.pressed.connect(_cancel)
	_canvas.add_child(back)

	var randomize := OneGunButton.new()
	randomize.name = "Randomize"
	randomize.text = "RANDOMIZE"
	randomize.variant = "navy"
	randomize.position = Vector2(658.0, 808.0)
	randomize.size = Vector2(210.0, 60.0)
	randomize.pressed.connect(_randomize_active_skin)
	_canvas.add_child(randomize)

	var default_button := OneGunButton.new()
	default_button.name = "Default"
	default_button.text = "DEFAULT"
	default_button.variant = "navy"
	default_button.position = Vector2(884.0, 808.0)
	default_button.size = Vector2(190.0, 60.0)
	default_button.tooltip_text = "Preview the default Blue color"
	default_button.pressed.connect(_default_active_skin)
	_canvas.add_child(default_button)

	_confirm_button = OneGunButton.new()
	_confirm_button.name = "Confirm"
	_confirm_button.text = "CONFIRM"
	_confirm_button.variant = "gold"
	_confirm_button.position = Vector2(1090.0, 808.0)
	_confirm_button.size = Vector2(446.0, 60.0)
	_confirm_button.pressed.connect(_confirm)
	_canvas.add_child(_confirm_button)

	var focus_controls: Array = []
	for card in _color_cards:
		focus_controls.append(card)
	focus_controls.append(randomize)
	focus_controls.append(default_button)
	focus_controls.append(_confirm_button)
	focus_controls.append(back)
	OneGunUI.chain_focus_vertical(focus_controls)
	var selected_card = _card_for_skin(_pending_skin_for_slot(_active_slot))
	if selected_card != null:
		selected_card.grab_focus.call_deferred()


func _apply_responsive_layout() -> void:
	if _canvas == null:
		return
	var available := size
	if available.x <= 0.0 or available.y <= 0.0:
		available = get_viewport_rect().size
	var scale_factor := minf(available.x / BASE_SIZE.x, available.y / BASE_SIZE.y)
	_canvas.scale = Vector2.ONE * scale_factor
	_canvas.position = (available - BASE_SIZE * scale_factor) * 0.5


func _set_active_slot(slot: int) -> void:
	_active_slot = clampi(slot, 0, local_player_count - 1)
	_refresh_active_player()


func _refresh_active_player() -> void:
	if _player_name_label == null:
		return
	_player_name_label.text = _player_name(_active_slot).to_upper()
	var skin_id := _pending_skin_for_slot(_active_slot)
	_selected_color_label.text = SkinRegistry.display_name(skin_id).to_upper()
	if _preview_visual != null and _preview_visual.has_method("set_skin"):
		_preview_visual.call("set_skin", skin_id)
	for card in _color_cards:
		card.set_selected(card.skin_id == skin_id)
	for slot in _player_tabs.size():
		_player_tabs[slot].variant = "gold" if slot == _active_slot else "navy"
	var card = _card_for_skin(skin_id)
	if card != null:
		card.grab_focus.call_deferred()


func _select_skin(skin_id: String) -> void:
	_pending_skin_ids[_active_slot] = SkinRegistry.sanitize_skin_id(skin_id)
	_refresh_active_player()


func _cycle_skin(direction: int) -> void:
	var current := _pending_skin_for_slot(_active_slot)
	_select_skin(SkinRegistry.skin_id_at(SkinRegistry.skin_index(current) + direction))


func _randomize_active_skin() -> void:
	var choices: Array[String] = []
	var current := _pending_skin_for_slot(_active_slot)
	for skin in SkinRegistry.SKINS:
		var skin_id := str(skin["id"])
		if skin_id != current:
			choices.append(skin_id)
	if not choices.is_empty():
		_select_skin(choices.pick_random())


func _default_active_skin() -> void:
	_select_skin(SkinRegistry.DEFAULT_SKIN_ID)


func _confirm() -> void:
	for slot in local_player_count:
		var skin_id := _pending_skin_for_slot(slot)
		if online_mode:
			if not NetworkManager.set_local_skin_id(skin_id):
				return
		elif slot == 1:
			GameConfig.player2_skin_id = skin_id
		else:
			PlayerPrefs.set_setting("character_skin_id", skin_id)
		_confirmed_skin_ids[slot] = skin_id
		skin_changed.emit(slot, skin_id)
	closed.emit()
	queue_free()


func _cancel() -> void:
	# Pending selections only ever touch the isolated preview. Since no stored
	# value is mutated until Confirm, Back/Escape restores the prior selection
	# simply by closing this screen.
	closed.emit()
	queue_free()


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_preview = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging_preview:
		_preview_pivot.rotate_y(-event.relative.x * 0.012)
		accept_event()


func _player_name(slot: int) -> String:
	if online_mode:
		return NetworkManager.local_name()
	if slot == 1:
		return str(GameConfig.player2_name)
	return str(PlayerPrefs.get_setting("player_name"))


func _stored_skin_for_slot(slot: int) -> String:
	if online_mode:
		return NetworkManager.local_skin_id()
	if slot == 1:
		return SkinRegistry.sanitize_skin_id(str(GameConfig.player2_skin_id))
	return SkinRegistry.sanitize_skin_id(str(PlayerPrefs.get_setting("character_skin_id")))


func _pending_skin_for_slot(slot: int) -> String:
	return SkinRegistry.sanitize_skin_id(str(
		_pending_skin_ids.get(slot, SkinRegistry.DEFAULT_SKIN_ID)))


func _card_for_skin(skin_id: String):
	for card in _color_cards:
		if card.skin_id == skin_id:
			return card
	return null


func _reduced_motion_enabled() -> bool:
	return bool(PlayerPrefs.get_setting("reduced_motion"))
