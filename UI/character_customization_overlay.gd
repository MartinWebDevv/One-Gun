class_name CharacterCustomizationOverlay
extends Control

signal closed
signal skin_changed(player_slot: int, skin_id: String)

const SkinRegistry = preload("res://player_skin_registry.gd")
const COLOR_CARD_SCRIPT = preload("res://UI/components/character_color_card.gd")
const Catalog = preload("res://supabase/one_gun_catalog.gd")
const BASE_SIZE := Vector2(1600.0, 900.0)
const LEFT_PANEL_RECT := Rect2(64.0, 142.0, 566.0, 638.0)
const RIGHT_PANEL_RECT := Rect2(658.0, 142.0, 878.0, 638.0)

var online_mode := false
var local_player_count := 1

var _canvas: Control
var _backend
var _preview_pivot: Node3D
var _preview_visual: Node3D
var _player_name_label: Label
var _selected_color_label: Label
var _player_tabs: Array[OneGunButton] = []
var _color_cards: Array = []
var _pending_skin_ids: Dictionary = {}
var _confirmed_skin_ids: Dictionary = {}
var _pending_model_ids: Dictionary = {}
var _confirmed_model_ids: Dictionary = {}
var _model_buttons: Dictionary = {}
var _active_slot := 0
var _dragging_preview := false
var _confirm_button: OneGunButton
var _randomize_button: OneGunButton
var _default_button: OneGunButton
var _reset_loadout_button: OneGunButton
var _reset_loadout_armed := false
var _reset_loadout_generation := 0
var _character_content: Control
var _color_content: Control
var _owned_content: Control
var _owned_list: VBoxContainer
var _locker_feedback: Label
var _locker_category := "character"
var _character_owned_gear := false
var _character_locker_section := "colors"
var _locker_subcategory := "ALL"
var _locker_cosmetic_filter := "ALL"
var _locker_sort_id := "rarity_asc"
var _locker_favorites_only := false
var _locker_subcategory_option: OptionButton
var _locker_cosmetic_option: OptionButton
var _locker_sort_option: OptionButton


func configure(is_online: bool, player_count: int) -> void:
	online_mode = is_online
	local_player_count = 1 if online_mode else clampi(player_count, 1, 2)


func _ready() -> void:
	_backend = get_node("/root/SupabaseManager")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_snapshot_confirmed_colors()
	_build_ui()
	_connect_locker_backend()
	_apply_responsive_layout()
	resized.connect(_apply_responsive_layout)
	set_process(false)


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
	_confirmed_model_ids.clear()
	_pending_model_ids.clear()
	for slot in local_player_count:
		var skin_id := _stored_skin_for_slot(slot)
		var model_id := _stored_model_for_slot(slot)
		_confirmed_skin_ids[slot] = skin_id
		_pending_skin_ids[slot] = skin_id
		_confirmed_model_ids[slot] = model_id
		_pending_model_ids[slot] = model_id


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
				"LOCKER", 42, "text_bright")
			title.name = "CustomizationTitle"
			title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			title_row.add_child(title)

	var subtitle := OneGunUI.make_label(
		"EQUIP WHAT YOU OWN  •  CHARACTER  •  WEAPONS  •  MOVES  •  MUSIC",
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
	viewport_container.custom_minimum_size = Vector2(0.0, 440.0)
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.stretch = true
	viewport_container.mouse_default_cursor_shape = Control.CURSOR_DRAG
	viewport_container.gui_input.connect(_on_preview_gui_input)
	column.add_child(viewport_container)
	_build_preview_world(viewport_container)

	var model_row := HBoxContainer.new()
	model_row.name = "ModelButtons"
	model_row.alignment = BoxContainer.ALIGNMENT_CENTER
	model_row.add_theme_constant_override("separation", 12)
	column.add_child(model_row)
	for model_id in SkinRegistry.MODEL_IDS:
		var model_button := OneGunButton.new()
		model_button.name = ("%sModel" % SkinRegistry.model_display_name(model_id))
		model_button.text = "M" if model_id == "male" else "F"
		model_button.font_size = OneGunUI.TEXT_M
		model_button.custom_minimum_size = Vector2(76.0, 38.0)
		model_button.tooltip_text = "Use the %s character model" % \
			SkinRegistry.model_display_name(model_id)
		model_button.pressed.connect(_select_model.bind(model_id))
		model_row.add_child(model_button)
		_model_buttons[model_id] = model_button
	var male_button: Control = _model_buttons.get("male")
	var female_button: Control = _model_buttons.get("female")
	if male_button != null and female_button != null:
		male_button.focus_neighbor_right = male_button.get_path_to(female_button)
		female_button.focus_neighbor_left = female_button.get_path_to(male_button)

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
	_replace_preview_visual(SkinRegistry.DEFAULT_MODEL_ID)

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


func _replace_preview_visual(model_id: String) -> void:
	var safe_model_id := SkinRegistry.sanitize_model_id(model_id)
	if _preview_visual != null and is_instance_valid(_preview_visual):
		var current_id := SkinRegistry.sanitize_model_id(
			str(_preview_visual.get("model_id")))
		if current_id == safe_model_id:
			return
	var visual_scene := SkinRegistry.load_visual_scene(safe_model_id)
	if visual_scene == null:
		push_warning("Character customization could not load the selected model.")
		return
	var replacement := visual_scene.instantiate() as Node3D
	if replacement == null:
		return
	replacement.name = "PreviewCharacter"
	replacement.set("build_animation_library", false)
	if _preview_visual != null and is_instance_valid(_preview_visual):
		_preview_visual.free()
	_preview_visual = replacement
	_preview_pivot.add_child(_preview_visual)
	var animation_player := _preview_visual.call(
		"ensure_animations", ["idle"]) as AnimationPlayer
	if animation_player != null and animation_player.has_animation("idle"):
		animation_player.play("idle", 0.0)
		animation_player.advance(0.0)


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
	panel.name = "LockerCabinet"
	panel.variant = OneGunCabinet.Variant.CABINET
	panel.content_padding = 16
	panel.position = RIGHT_PANEL_RECT.position
	panel.size = RIGHT_PANEL_RECT.size
	_canvas.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "SelectionColumn"
	column.add_theme_constant_override("separation", 6)
	panel.get_content().add_child(column)

	var category_tabs := OneGunTabBar.new()
	category_tabs.name = "LockerCategoryTabs"
	category_tabs.tabs = PackedStringArray([
		"CHARACTER", "WEAPONS", "VICTORY", "AUDIO"])
	category_tabs.tab_selected.connect(_show_locker_category)
	column.add_child(category_tabs)

	_character_content = VBoxContainer.new()
	(_character_content as VBoxContainer).add_theme_constant_override(
		"separation", 6)
	column.add_child(_character_content)
	var character_tabs := OneGunTabBar.new()
	character_tabs.name = "CharacterLockerTabs"
	character_tabs.tabs = PackedStringArray(["SKINS", "COLORS", "COSMETICS"])
	character_tabs.selected = 1
	character_tabs.tab_selected.connect(_show_character_subcategory)
	_character_content.add_child(character_tabs)

	_color_content = VBoxContainer.new()
	(_color_content as VBoxContainer).add_theme_constant_override("separation", 6)
	_character_content.add_child(_color_content)
	_color_content.add_child(_make_divider_heading("★   CHOOSE A COLOR   ★"))
	var grid := VBoxContainer.new()
	grid.name = "ColorGrid"
	grid.add_theme_constant_override("separation", 10)
	_color_content.add_child(grid)
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

	_owned_content = VBoxContainer.new()
	_owned_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_owned_content as VBoxContainer).add_theme_constant_override("separation", 6)
	column.add_child(_owned_content)
	var filters := HBoxContainer.new()
	filters.name = "LockerCatalogFilters"
	filters.add_theme_constant_override("separation", 6)
	_owned_content.add_child(filters)
	_locker_subcategory_option = OptionButton.new()
	_locker_subcategory_option.name = "LockerSubcategoryFilter"
	_locker_subcategory_option.custom_minimum_size = Vector2(170.0, 38.0)
	_locker_subcategory_option.item_selected.connect(_on_locker_subcategory_selected)
	filters.add_child(_locker_subcategory_option)
	_locker_cosmetic_option = OptionButton.new()
	_locker_cosmetic_option.name = "LockerCosmeticFilter"
	_locker_cosmetic_option.custom_minimum_size = Vector2(150.0, 38.0)
	for option in Catalog.COSMETIC_SUBCATEGORIES:
		_locker_cosmetic_option.add_item(option)
	_locker_cosmetic_option.item_selected.connect(_on_locker_cosmetic_selected)
	filters.add_child(_locker_cosmetic_option)
	_locker_sort_option = OptionButton.new()
	_locker_sort_option.name = "LockerSortOrder"
	_locker_sort_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locker_sort_option.custom_minimum_size.y = 38.0
	for label in Catalog.SORT_LABELS:
		_locker_sort_option.add_item(label)
	_locker_sort_option.item_selected.connect(_on_locker_sort_selected)
	filters.add_child(_locker_sort_option)
	var favorites := OneGunButton.new()
	favorites.name = "LockerFavoritesFilter"
	favorites.text = "★"
	favorites.tooltip_text = "Show only Favorites"
	favorites.variant = "navy"
	favorites.toggle_mode = true
	favorites.custom_minimum_size = Vector2(52.0, 38.0)
	favorites.toggled.connect(func(value: bool) -> void:
		_locker_favorites_only = value
		favorites.variant = "gold" if value else "navy"
		_rebuild_owned_locker())
	filters.add_child(favorites)
	_locker_feedback = OneGunUI.make_label("", OneGunUI.TEXT_S, "muted")
	_locker_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_owned_content.add_child(_locker_feedback)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_owned_content.add_child(scroll)
	_owned_list = VBoxContainer.new()
	_owned_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_owned_list.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	scroll.add_child(_owned_list)
	_show_locker_category(0)
	_show_character_subcategory(1)


func _connect_locker_backend() -> void:
	var connections := [
		[_backend.inventory_updated, _on_locker_data_updated],
		[_backend.shop_loaded, _on_locker_data_updated],
		[_backend.loadout_updated, _on_locker_data_updated],
		[_backend.login_state_changed, _on_locker_data_updated],
		[_backend.equip_succeeded, _on_locker_equip_succeeded],
		[_backend.equip_failed, _on_locker_equip_failed],
		[_backend.unequip_succeeded, _on_locker_unequip_succeeded],
		[_backend.unequip_failed, _on_locker_unequip_failed],
		[_backend.loadout_reset_succeeded, _on_locker_reset_succeeded],
		[_backend.loadout_reset_failed, _on_locker_reset_failed],
		[ProgressionManager.catalog_updated, _on_locker_data_updated],
		[ProgressionManager.favorites_updated, _on_locker_data_updated],
		[ProgressionManager.usage_updated, _on_locker_data_updated],
	]
	for connection in connections:
		var backend_signal: Signal = connection[0]
		var callback: Callable = connection[1]
		if not backend_signal.is_connected(callback):
			backend_signal.connect(callback)


func _show_locker_category(index: int) -> void:
	var categories := ["character", "weapons", "victory", "audio"]
	_locker_category = categories[clampi(index, 0, categories.size() - 1)]
	_character_content.visible = _locker_category == "character"
	if _locker_category == "character":
		_color_content.visible = _character_locker_section == "colors"
		_owned_content.visible = _character_locker_section != "colors"
	if _locker_category != "character":
		_owned_content.visible = true
		_locker_subcategory = "ALL"
		_locker_cosmetic_filter = "ALL"
		_configure_locker_filters()
		_rebuild_owned_locker()
	if _locker_category != "audio":
		AudioManager.stop_ceremony_preview()
	_update_locker_action_bar()


func _show_character_subcategory(index: int) -> void:
	_character_locker_section = ["skins", "colors", "cosmetics"][clampi(index, 0, 2)]
	var show_colors := _character_locker_section == "colors"
	_character_owned_gear = not show_colors
	_color_content.visible = show_colors
	_owned_content.visible = not show_colors
	if not show_colors:
		_locker_subcategory = "SKINS" if _character_locker_section == "skins" \
			else "COSMETICS"
		_locker_cosmetic_filter = "ALL"
		_configure_locker_filters()
		_rebuild_owned_locker()
	_update_locker_action_bar()


func _configure_locker_filters() -> void:
	if _locker_subcategory_option == null:
		return
	_locker_subcategory_option.clear()
	var primary := _locker_category.to_upper()
	var options := Catalog.category_subcategories(primary)
	if primary == "CHARACTER" and _character_locker_section == "skins":
		options.assign(["SKINS"])
	elif primary == "CHARACTER" and _character_locker_section == "cosmetics":
		options.assign(["COSMETICS"])
	for option in options:
		_locker_subcategory_option.add_item(option)
	_locker_subcategory_option.select(0)
	_locker_subcategory = str(options[0]) if not options.is_empty() else "ALL"
	_locker_cosmetic_option.select(0)
	_locker_cosmetic_option.visible = primary == "CHARACTER" \
		and _locker_subcategory == "COSMETICS"


func _on_locker_subcategory_selected(index: int) -> void:
	_locker_subcategory = _locker_subcategory_option.get_item_text(index)
	_locker_cosmetic_filter = "ALL"
	_locker_cosmetic_option.select(0)
	_locker_cosmetic_option.visible = _locker_category == "character" \
		and _locker_subcategory == "COSMETICS"
	_rebuild_owned_locker()


func _on_locker_cosmetic_selected(index: int) -> void:
	_locker_cosmetic_filter = _locker_cosmetic_option.get_item_text(index)
	_rebuild_owned_locker()


func _on_locker_sort_selected(index: int) -> void:
	_locker_sort_id = Catalog.SORT_IDS[clampi(
		index, 0, Catalog.SORT_IDS.size() - 1)]
	_rebuild_owned_locker()


func _locker_catalog(item_id: String) -> Dictionary:
	var extended := ProgressionManager.item(item_id)
	return extended if not extended.is_empty() else _backend.catalog_item(item_id)


func _locker_primary_category() -> String:
	match _locker_category:
		"character": return "CHARACTER"
		"weapons": return "WEAPONS"
		"victory": return "VICTORY"
		"audio": return "AUDIO"
	return "FEATURED"


func _locker_usage_counts() -> Dictionary:
	var counts := {}
	for item_id in ProgressionManager.usage:
		counts[item_id] = ProgressionManager.usage_count(str(item_id))
	return counts


func _rebuild_owned_locker() -> void:
	for child in _owned_list.get_children():
		child.queue_free()
	if local_player_count > 1 and _active_slot == 1:
		_locker_feedback.text = \
			"Cloud-owned items belong to Player 1. Player 2 can still choose a base character and color."
		_owned_list.add_child(_locker_empty_label("SELECT PLAYER 1 TO EQUIP OWNED ITEMS"))
		return
	if not _backend.is_authenticated():
		_locker_feedback.text = "Sign in through Profile to load cloud-owned items."
		_owned_list.add_child(_locker_empty_label("PROFILE SIGN-IN REQUIRED"))
		return
	_locker_feedback.text = _locker_category_description()
	var matching: Array[Dictionary] = []
	for entry in _backend.inventory:
		var item_id := str(entry.get("item_id", ""))
		var catalog := Catalog.normalize_item(_locker_catalog(item_id))
		if catalog.is_empty():
			continue
		if not Catalog.item_matches(catalog, _locker_primary_category(),
				_locker_subcategory, _locker_cosmetic_filter):
			continue
		if _locker_favorites_only and not ProgressionManager.is_favorite(item_id):
			continue
		var owned := catalog.duplicate(true)
		owned["item_id"] = item_id
		owned["source"] = entry.get("source", "owned")
		owned["obtained_at"] = entry.get("obtained_at", "")
		matching.append(owned)
	matching = Catalog.sorted_items(
		matching, _locker_sort_id, _locker_usage_counts())
	if matching.is_empty():
		_owned_list.add_child(_locker_empty_label(
			"NO OWNED %s ITEMS YET" % _locker_category.to_upper()))
		return
	for entry in matching:
		_owned_list.add_child(_make_owned_locker_row(entry))


func _locker_slot_matches(slot: String) -> bool:
	match _locker_category:
		"character":
			return slot in ["character_skin", "hat", "shirt", "pants", "shoes", "accessory", "outfit_bundle"]
		"weapons":
			return slot in ["gun_skin", "melee_skin"]
		"victory":
			return slot in ["emote", "round_victory_move", "victory_dance"]
		"audio":
			return slot == "ceremony_theme"
	return false


func _locker_category_description() -> String:
	match _locker_category:
		"character": return "OWNED SKINS, COLORS, COSMETICS, AND MIXABLE OUTFIT PIECES"
		"weapons": return "OWNED GUN AND MELEE SKINS"
		"victory": return "OWNED POSES AND DANCES • ASSIGN ANY DANCE TO EITHER CELEBRATION"
		"audio": return "OWNED WINNERS CIRCLE THEMES • PREVIEW USES CEREMONY VOLUME"
	return "OWNED ITEMS"


func _make_owned_locker_row(entry: Dictionary) -> Control:
	var item_id := str(entry.get("item_id", ""))
	var catalog: Dictionary = _locker_catalog(item_id)
	var slot := SupabaseCosmeticRegistry.item_slot(catalog)
	if slot == "":
		slot = str(catalog.get("item_type",
			SupabaseCosmeticRegistry.known_slot_for_id(item_id)))
	var is_dance := slot == "victory_dance" or (
		Catalog.subcategory(catalog) == "dances"
		and SupabaseCosmeticRegistry.local_victory_animation(item_id) != "")
	var visual_slot := "victory_dance" if is_dance else slot
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", OneGunUI.style_box(
		OneGunUI.color("face_raised"), OneGunUI.color("border"),
		OneGunUI.RADIUS_SECTION, OneGunUI.BORDER_THIN, 2, OneGunUI.SPACE_M))
	var horizontal := HBoxContainer.new()
	horizontal.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	row.add_child(horizontal)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	horizontal.add_child(copy)
	copy.add_child(OneGunUI.make_heading(str(catalog.get("display_name",
		SupabaseCosmeticRegistry.display_name_fallback(item_id))).to_upper(),
		OneGunUI.TEXT_M, "text"))
	var art_state := "READY" if SupabaseCosmeticRegistry.has_local_visual(
		item_id, visual_slot) else "ART PENDING"
	copy.add_child(OneGunUI.make_label("%s • %s" % [
		_locker_slot_display_name(visual_slot), art_state], OneGunUI.TEXT_S, "muted"))
	if slot == "ceremony_theme":
		var preview := OneGunButton.new()
		preview.text = "PREVIEW"
		preview.variant = "blue"
		preview.custom_minimum_size = Vector2(116.0, 46.0)
		preview.pressed.connect(_preview_locker_theme.bind(item_id))
		horizontal.add_child(preview)
	elif is_dance:
		var preview := OneGunButton.new()
		preview.text = "PREVIEW"
		preview.variant = "blue"
		preview.custom_minimum_size = Vector2(116.0, 46.0)
		preview.pressed.connect(_preview_locker_move.bind(item_id))
		horizontal.add_child(preview)
	if is_dance:
		horizontal.add_child(_make_locker_slot_button(
			"emote", item_id, "EQUIP PODIUM"))
		horizontal.add_child(_make_locker_slot_button(
			"round_victory_move", item_id, "EQUIP ROUND"))
		return row
	var equipped := str(_backend.loadout.get(slot, "")) == item_id
	if slot == "outfit_bundle":
		equipped = ProgressionManager.components_for(item_id).all(func(component_id):
			var component := _locker_catalog(str(component_id))
			var component_slot := SupabaseCosmeticRegistry.item_slot(component)
			return str(_backend.loadout.get(component_slot, "")) == str(component_id))
	var equip := OneGunButton.new()
	equip.text = "UNEQUIP" if equipped else "EQUIP"
	equip.variant = "green" if equipped else "gold"
	equip.custom_minimum_size = Vector2(132.0, 46.0)
	equip.disabled = slot == ""
	if not equip.disabled:
		if equipped and slot == "outfit_bundle":
			equip.pressed.connect(_unequip_locker_outfit.bind(item_id))
		elif equipped:
			equip.pressed.connect(_unequip_locker_item.bind(slot, item_id))
		elif slot == "outfit_bundle":
			equip.pressed.connect(_equip_locker_outfit.bind(item_id))
		else:
			equip.pressed.connect(_equip_locker_item.bind(slot, item_id))
	horizontal.add_child(equip)
	return row


func _make_locker_slot_button(slot: String, item_id: String,
		equip_label: String) -> OneGunButton:
	var button := OneGunButton.new()
	var equipped := str(_backend.loadout.get(slot, "")) == item_id
	button.text = "UNEQUIP" if equipped else equip_label
	button.variant = "green" if equipped else "gold"
	button.custom_minimum_size = Vector2(142.0, 46.0)
	button.tooltip_text = "%s slot" % _locker_slot_display_name(slot).capitalize()
	if equipped:
		button.pressed.connect(_unequip_locker_item.bind(slot, item_id))
	else:
		button.pressed.connect(_equip_locker_item.bind(slot, item_id))
	return button


func _locker_slot_display_name(slot: String) -> String:
	if slot == "emote":
		return "PODIUM POSE"
	if slot in ["victory_dance", "round_victory_move"]:
		return "VICTORY DANCE"
	if slot == "ceremony_theme":
		return "WINNERS CIRCLE MUSIC"
	return slot.replace("_", " ").to_upper()


func _locker_empty_label(text: String) -> Label:
	var label := OneGunUI.make_label(text, OneGunUI.TEXT_M, "muted")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.y = 90.0
	return label


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

	_randomize_button = OneGunButton.new()
	_randomize_button.name = "Randomize"
	_randomize_button.text = "RANDOMIZE"
	_randomize_button.variant = "navy"
	_randomize_button.position = Vector2(658.0, 808.0)
	_randomize_button.size = Vector2(210.0, 60.0)
	_randomize_button.pressed.connect(_randomize_active_skin)
	_canvas.add_child(_randomize_button)

	_default_button = OneGunButton.new()
	_default_button.name = "Default"
	_default_button.text = "DEFAULT"
	_default_button.variant = "navy"
	_default_button.position = Vector2(884.0, 808.0)
	_default_button.size = Vector2(190.0, 60.0)
	_default_button.tooltip_text = "Preview the default Blue color"
	_default_button.pressed.connect(_default_active_skin)
	_canvas.add_child(_default_button)

	_reset_loadout_button = OneGunButton.new()
	_reset_loadout_button.name = "ResetLoadout"
	_reset_loadout_button.text = "RESET LOADOUT"
	_reset_loadout_button.variant = "navy"
	_reset_loadout_button.position = Vector2(658.0, 808.0)
	_reset_loadout_button.size = Vector2(416.0, 60.0)
	_reset_loadout_button.pressed.connect(_on_reset_loadout_pressed)
	_canvas.add_child(_reset_loadout_button)

	_confirm_button = OneGunButton.new()
	_confirm_button.name = "Confirm"
	_confirm_button.text = "SAVE & CLOSE"
	_confirm_button.variant = "gold"
	_confirm_button.position = Vector2(1090.0, 808.0)
	_confirm_button.size = Vector2(446.0, 60.0)
	_confirm_button.pressed.connect(_confirm)
	_canvas.add_child(_confirm_button)

	var focus_controls: Array = []
	for card in _color_cards:
		focus_controls.append(card)
	focus_controls.append(_randomize_button)
	focus_controls.append(_default_button)
	focus_controls.append(_reset_loadout_button)
	focus_controls.append(_confirm_button)
	focus_controls.append(back)
	OneGunUI.chain_focus_vertical(focus_controls)
	_update_locker_action_bar()
	var selected_card = _card_for_skin(_pending_skin_for_slot(_active_slot))
	if selected_card != null:
		selected_card.grab_focus.call_deferred()


func _update_locker_action_bar() -> void:
	if _randomize_button == null or _default_button == null \
			or _reset_loadout_button == null:
		return
	var colors_visible := _locker_category == "character" \
		and _color_content != null and _color_content.visible
	_randomize_button.visible = colors_visible
	_default_button.visible = colors_visible
	_reset_loadout_button.visible = not colors_visible
	_reset_loadout_button.disabled = not _backend.is_authenticated()
	if colors_visible:
		_clear_reset_loadout_confirmation()


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
	if _owned_content != null and _owned_content.visible:
		_rebuild_owned_locker()


func _refresh_active_player() -> void:
	if _player_name_label == null:
		return
	_player_name_label.text = _player_name(_active_slot).to_upper()
	var skin_id := _pending_skin_for_slot(_active_slot)
	var model_id := _pending_model_for_slot(_active_slot)
	_selected_color_label.text = SkinRegistry.display_name(skin_id).to_upper()
	_replace_preview_visual(model_id)
	if _preview_visual != null and _preview_visual.has_method("set_skin"):
		_preview_visual.call("set_skin", skin_id)
	for card in _color_cards:
		card.set_model(model_id)
		card.set_selected(card.skin_id == skin_id)
	for button_model_id in _model_buttons:
		var button: OneGunButton = _model_buttons[button_model_id]
		button.variant = "gold" if button_model_id == model_id else "navy"
	for slot in _player_tabs.size():
		_player_tabs[slot].variant = "gold" if slot == _active_slot else "navy"
	var card = _card_for_skin(skin_id)
	if card != null:
		card.grab_focus.call_deferred()


func _select_skin(skin_id: String) -> void:
	_pending_skin_ids[_active_slot] = SkinRegistry.sanitize_skin_id(skin_id)
	_refresh_active_player()


func _select_model(model_id: String) -> void:
	_pending_model_ids[_active_slot] = SkinRegistry.sanitize_model_id(model_id)
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
		var model_id := _pending_model_for_slot(slot)
		if online_mode:
			if not NetworkManager.set_local_appearance(skin_id, model_id):
				return
		elif slot == 1:
			GameConfig.player2_skin_id = skin_id
			GameConfig.player2_model_id = model_id
		else:
			var next_preferences := PlayerPrefs.snapshot()
			next_preferences["character_skin_id"] = skin_id
			next_preferences["character_model_id"] = model_id
			if not PlayerPrefs.apply_transaction(next_preferences):
				return
		_confirmed_skin_ids[slot] = skin_id
		_confirmed_model_ids[slot] = model_id
		skin_changed.emit(slot, skin_id)
	AudioManager.stop_ceremony_preview()
	closed.emit()
	queue_free()


func _cancel() -> void:
	# Pending selections only ever touch the isolated preview. Since no stored
	# value is mutated until Confirm, Back/Escape restores the prior selection
	# simply by closing this screen.
	AudioManager.stop_ceremony_preview()
	closed.emit()
	queue_free()


func _preview_locker_theme(item_id: String) -> void:
	var audio_key := SupabaseCosmeticRegistry.local_ceremony_audio_key(item_id)
	if audio_key == "" or not AudioManager.play_ceremony_preview(audio_key, 0.78):
		_locker_feedback.text = "THIS WINNERS CIRCLE THEME IS NOT INSTALLED"
		_locker_feedback.add_theme_color_override("font_color", OneGunUI.color("red"))
		return
	_locker_feedback.text = "PREVIEWING %s — MENU MUSIC PAUSED" % \
		SupabaseCosmeticRegistry.display_name_fallback(item_id).to_upper()
	_locker_feedback.add_theme_color_override("font_color", OneGunUI.color("green"))


func _preview_locker_move(item_id: String) -> void:
	var animation_name := SupabaseCosmeticRegistry.local_victory_animation(item_id)
	if animation_name == "" or _preview_visual == null:
		_locker_feedback.text = "THIS VICTORY MOVE IS NOT INSTALLED"
		_locker_feedback.add_theme_color_override(
			"font_color", OneGunUI.color("red"))
		return
	var animation_player := _preview_visual.call(
		"ensure_animations", [animation_name]) as AnimationPlayer
	if animation_player == null or not animation_player.has_animation(animation_name):
		_locker_feedback.text = "THIS VICTORY MOVE COULD NOT BE PREVIEWED"
		_locker_feedback.add_theme_color_override(
			"font_color", OneGunUI.color("red"))
		return
	AudioManager.stop_ceremony_preview()
	animation_player.play(animation_name, 0.12)
	var catalog := _locker_catalog(item_id)
	_locker_feedback.text = "PREVIEWING %s" % str(catalog.get(
		"display_name", SupabaseCosmeticRegistry.display_name_fallback(item_id))).to_upper()
	_locker_feedback.add_theme_color_override("font_color", OneGunUI.color("green"))


func _equip_locker_item(slot: String, item_id: String) -> void:
	_locker_feedback.text = "EQUIPPING %s…" % \
		SupabaseCosmeticRegistry.display_name_fallback(item_id).to_upper()
	await _backend.equip_cosmetic(slot, item_id)


func _unequip_locker_item(slot: String, item_id: String) -> void:
	_locker_feedback.text = "UNEQUIPPING %s…" % \
		SupabaseCosmeticRegistry.display_name_fallback(item_id).to_upper()
	await _backend.unequip_cosmetic(slot)


func _unequip_locker_outfit(item_id: String) -> void:
	_locker_feedback.text = "REMOVING FULL %s SET…" % \
		SupabaseCosmeticRegistry.display_name_fallback(item_id).to_upper()
	if await ProgressionManager.unequip_outfit(item_id):
		_locker_feedback.text = "OUTFIT UNEQUIPPED"
		_locker_feedback.add_theme_color_override(
			"font_color", OneGunUI.color("green"))
		_rebuild_owned_locker()
	else:
		_locker_feedback.text = "THIS OUTFIT COULD NOT BE UNEQUIPPED"
		_locker_feedback.add_theme_color_override(
			"font_color", OneGunUI.color("red"))


func _equip_locker_outfit(item_id: String) -> void:
	_locker_feedback.text = "EQUIPPING FULL %s SET…" % \
		SupabaseCosmeticRegistry.display_name_fallback(item_id).to_upper()
	if await ProgressionManager.equip_outfit(item_id):
		_locker_feedback.text = "FULL OUTFIT EQUIPPED — EACH PIECE REMAINS MIXABLE"
		_locker_feedback.add_theme_color_override("font_color", OneGunUI.color("green"))
		_rebuild_owned_locker()


func _on_locker_data_updated(_value = null, _extra = null) -> void:
	if _owned_list != null and _owned_content.visible:
		_rebuild_owned_locker()


func _on_locker_equip_succeeded(_slot: String, item_id: String) -> void:
	_locker_feedback.text = "EQUIPPED %s" % \
		SupabaseCosmeticRegistry.display_name_fallback(item_id).to_upper()
	_locker_feedback.add_theme_color_override("font_color", OneGunUI.color("green"))
	_rebuild_owned_locker()


func _on_locker_equip_failed(_slot: String, _item_id: String, message: String) -> void:
	_locker_feedback.text = message
	_locker_feedback.add_theme_color_override("font_color", OneGunUI.color("red"))


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_preview = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging_preview:
		_preview_pivot.rotate_y(event.relative.x * 0.012)
		accept_event()

func _on_locker_unequip_succeeded(slot: String) -> void:
	_locker_feedback.text = "%s RETURNED TO ITS BASE SETTING" % \
		_locker_slot_display_name(slot)
	_locker_feedback.add_theme_color_override("font_color", OneGunUI.color("green"))
	_rebuild_owned_locker()


func _on_locker_unequip_failed(_slot: String, message: String) -> void:
	_locker_feedback.text = message
	_locker_feedback.add_theme_color_override("font_color", OneGunUI.color("red"))


func _on_reset_loadout_pressed() -> void:
	if not _backend.is_authenticated():
		_locker_feedback.text = "SIGN IN THROUGH PROFILE TO RESET YOUR LOADOUT"
		_locker_feedback.add_theme_color_override("font_color", OneGunUI.color("red"))
		return
	if not _reset_loadout_armed:
		_reset_loadout_armed = true
		_reset_loadout_generation += 1
		var generation := _reset_loadout_generation
		_reset_loadout_button.text = "CONFIRM RESET"
		_reset_loadout_button.variant = "red"
		_locker_feedback.text = \
			"PRESS CONFIRM RESET WITHIN 5 SECONDS • MODEL AND COLOR WILL BE PRESERVED"
		_locker_feedback.add_theme_color_override("font_color", OneGunUI.color("gold"))
		_expire_reset_loadout_confirmation(generation)
		return
	_clear_reset_loadout_confirmation()
	_reset_loadout_button.disabled = true
	_locker_feedback.text = "RESTORING THE BASE ONE GUN LOADOUT…"
	if not await ProgressionManager.reset_loadout():
		_reset_loadout_button.disabled = false


func _expire_reset_loadout_confirmation(generation: int) -> void:
	await get_tree().create_timer(5.0, true).timeout
	if generation == _reset_loadout_generation:
		_clear_reset_loadout_confirmation()


func _clear_reset_loadout_confirmation() -> void:
	_reset_loadout_armed = false
	_reset_loadout_generation += 1
	if _reset_loadout_button == null:
		return
	_reset_loadout_button.text = "RESET LOADOUT"
	_reset_loadout_button.variant = "navy"
	_reset_loadout_button.disabled = not _backend.is_authenticated()


func _on_locker_reset_succeeded() -> void:
	_clear_reset_loadout_confirmation()
	_locker_feedback.text = \
		"BASE LOADOUT RESTORED • CHARACTER MODEL AND COLOR PRESERVED"
	_locker_feedback.add_theme_color_override("font_color", OneGunUI.color("green"))
	_rebuild_owned_locker()


func _on_locker_reset_failed(message: String) -> void:
	_clear_reset_loadout_confirmation()
	_locker_feedback.text = message
	_locker_feedback.add_theme_color_override("font_color", OneGunUI.color("red"))




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


func _stored_model_for_slot(slot: int) -> String:
	if online_mode:
		return NetworkManager.local_model_id()
	if slot == 1:
		return SkinRegistry.sanitize_model_id(str(GameConfig.player2_model_id))
	return SkinRegistry.sanitize_model_id(str(
		PlayerPrefs.get_setting("character_model_id")))


func _pending_skin_for_slot(slot: int) -> String:
	return SkinRegistry.sanitize_skin_id(str(
		_pending_skin_ids.get(slot, SkinRegistry.DEFAULT_SKIN_ID)))


func _pending_model_for_slot(slot: int) -> String:
	return SkinRegistry.sanitize_model_id(str(
		_pending_model_ids.get(slot, SkinRegistry.DEFAULT_MODEL_ID)))


func _card_for_skin(skin_id: String):
	for card in _color_cards:
		if card.skin_id == skin_id:
			return card
	return null


func _reduced_motion_enabled() -> bool:
	return bool(PlayerPrefs.get_setting("reduced_motion"))
