class_name ThemedLockerOverlay
extends "res://UI/character_customization_overlay.gd"

# Visual specialization of the existing Locker contract. Character selection,
# cloud ownership, equip behavior, local P1/P2 handling, and preview input stay
# in the base script; this layer supplies the armory atmosphere and richer
# owned-item presentation.

const HUB_BACKDROP_SCRIPT = preload("res://UI/components/menu_hub_backdrop.gd")
const LOCKER_BACKDROP = preload("res://UI/assets/menu_hubs/locker_backdrop.png")

var _loadout_summary_label: Label


func _ready() -> void:
	super._ready()
	if not _is_visual_capture():
		return
	# Automated screenshots should show the authored three-quarter pose without
	# a stale mouse tooltip or four seconds of idle rotation changing the frame.
	if _preview_pivot != null:
		_preview_pivot.rotation.y = 0.0
	for card in _color_cards:
		card.tooltip_text = ""
	Input.warp_mouse(Vector2(18.0, 18.0))


func _process(delta: float) -> void:
	# Retain the still-by-default presentation while allowing intentional
	# right-stick rotation supplied by the shared Locker behavior.
	super._process(delta)


func _build_backdrop() -> void:
	var atmosphere := HUB_BACKDROP_SCRIPT.new()
	atmosphere.name = "LockerArmoryAtmosphere"
	atmosphere.position = Vector2.ZERO
	atmosphere.size = BASE_SIZE
	atmosphere.configure(LOCKER_BACKDROP, HUB_BACKDROP_SCRIPT.Variant.LOCKER)
	_canvas.add_child(atmosphere)

	var inner_grade := ColorRect.new()
	inner_grade.name = "LockerReadabilityGrade"
	inner_grade.position = Vector2.ZERO
	inner_grade.size = BASE_SIZE
	inner_grade.color = Color(0.004, 0.012, 0.036, 0.30)
	inner_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(inner_grade)

	var bottom_rule := ColorRect.new()
	bottom_rule.position = Vector2(0.0, 896.0)
	bottom_rule.size = Vector2(BASE_SIZE.x, 4.0)
	bottom_rule.color = OneGunUI.color("cyan").darkened(0.18)
	bottom_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(bottom_rule)


func _build_header() -> void:
	var title_row := HBoxContainer.new()
	title_row.name = "CustomizationTitleRow"
	title_row.position = Vector2(430.0, 20.0)
	title_row.size = Vector2(740.0, 54.0)
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 18)
	_canvas.add_child(title_row)
	var left_star := OneGunUI.make_heading("✦", 30, "cyan")
	title_row.add_child(left_star)
	var title := OneGunUI.make_heading("THE LOCKER", 42, "text_bright")
	title.name = "CustomizationTitle"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(title)
	var right_star := OneGunUI.make_heading("✦", 30, "cyan")
	title_row.add_child(right_star)

	var rule := ColorRect.new()
	rule.position = Vector2(64.0, 112.0)
	rule.size = Vector2(1472.0, 2.0)
	rule.color = Color(OneGunUI.color("cyan"), 0.42)
	_canvas.add_child(rule)


func _build_preview_panel() -> void:
	super._build_preview_panel()
	var panel := _canvas.get_node_or_null("CharacterPreviewPanel") as Control
	if panel != null:
		panel.position = Vector2(64.0, 142.0)
		panel.size = Vector2(620.0, 638.0)


func _build_selection_panel() -> void:
	super._build_selection_panel()
	var panel := _canvas.get_node_or_null("LockerCabinet") as Control
	if panel != null:
		panel.position = Vector2(712.0, 142.0)
		panel.size = Vector2(824.0, 638.0)
	var selection_column := _canvas.find_child("SelectionColumn", true, false) as VBoxContainer
	if selection_column == null:
		return
	var loadout_panel := PanelContainer.new()
	loadout_panel.name = "ActiveLoadoutStrip"
	loadout_panel.custom_minimum_size.y = 48.0
	loadout_panel.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(0.008, 0.036, 0.075, 0.92), Color(OneGunUI.color("cyan"), 0.42),
		10, 1, 0, 10.0))
	_loadout_summary_label = OneGunUI.make_label("ACTIVE LOADOUT", OneGunUI.TEXT_S, "cyan", true)
	_loadout_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loadout_panel.add_child(_loadout_summary_label)
	selection_column.add_child(loadout_panel)
	selection_column.move_child(loadout_panel, 1)
	_update_loadout_summary()


func _build_preview_world(container: SubViewportContainer) -> void:
	super._build_preview_world(container)
	var viewport := container.get_node_or_null("CharacterViewport") as SubViewport
	if viewport == null:
		return
	var world := viewport.get_node_or_null("PreviewWorld") as Node3D
	if world == null:
		return
	var environment := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if environment != null and environment.environment != null:
		environment.environment.background_color = Color(0.004, 0.018, 0.055)
		environment.environment.ambient_light_color = Color(0.30, 0.50, 0.92)
		environment.environment.ambient_light_energy = 0.72
	_build_armory_preview_set(world)


func _build_armory_preview_set(world: Node3D) -> void:
	var back_wall := MeshInstance3D.new()
	back_wall.name = "ArmoryPreviewWall"
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(6.8, 5.4, 0.18)
	back_wall.mesh = wall_mesh
	back_wall.position = Vector3(0.0, 2.7, -1.85)
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.012, 0.035, 0.095)
	wall_material.metallic = 0.62
	wall_material.roughness = 0.30
	back_wall.material_override = wall_material
	world.add_child(back_wall)

	for x in [-2.4, -1.2, 0.0, 1.2, 2.4]:
		var strip := MeshInstance3D.new()
		var strip_mesh := BoxMesh.new()
		strip_mesh.size = Vector3(0.035, 4.8, 0.04)
		strip.mesh = strip_mesh
		strip.position = Vector3(x, 2.7, -1.72)
		var strip_material := StandardMaterial3D.new()
		strip_material.albedo_color = Color(0.02, 0.22, 0.72)
		strip_material.emission_enabled = true
		strip_material.emission = Color(0.01, 0.24, 0.95)
		strip_material.emission_energy_multiplier = 1.8
		strip.material_override = strip_material
		world.add_child(strip)


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
	row.custom_minimum_size.y = 102.0
	row.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(0.012, 0.026, 0.065, 0.96), Color(OneGunUI.color("cyan"), 0.30),
		12, 1, 3, 12.0))
	var horizontal := HBoxContainer.new()
	horizontal.add_theme_constant_override("separation", 10)
	row.add_child(horizontal)

	var character_model_id := SupabaseCosmeticRegistry.local_character_model_id(
		item_id) if slot == "character_model" else ""
	if character_model_id != "":
		horizontal.add_child(_make_character_model_portrait(
			character_model_id,
			"CharacterModelPortrait_%s" % item_id))
	else:
		var icon_panel := PanelContainer.new()
		icon_panel.custom_minimum_size = Vector2(64.0, 68.0)
		icon_panel.add_theme_stylebox_override("panel", OneGunUI.style_box(
			Color(0.01, 0.04, 0.10), Color(OneGunUI.color("gold"), 0.48), 10, 1))
		horizontal.add_child(icon_panel)
		var icon := OneGunUI.make_heading(_locker_icon_for_slot(visual_slot), 29,
			"cyan" if slot == "ceremony_theme" else "gold")
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_panel.add_child(icon)

	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	horizontal.add_child(copy)
	var item_name := OneGunUI.make_heading(str(catalog.get("display_name",
		SupabaseCosmeticRegistry.display_name_fallback(item_id))).to_upper(),
		OneGunUI.TEXT_M, "text_bright")
	item_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(item_name)
	var art_state := "READY" if SupabaseCosmeticRegistry.has_local_visual(
		item_id, visual_slot) else "ART PENDING"
	copy.add_child(OneGunUI.make_label("%s  •  %s" % [
		_locker_slot_display_name(visual_slot), art_state], OneGunUI.TEXT_S, "muted", true))
	var source := str(entry.get("source", "owned")).strip_edges().to_lower()
	if source not in ["base_game", "starter_unlock"]:
		copy.add_child(OneGunUI.make_label("ACQUIRED: %s" % \
			source.replace("_", " ").to_upper(), OneGunUI.TEXT_XS, "cyan"))

	if slot == "ceremony_theme":
		var preview := OneGunButton.new()
		preview.text = "PREVIEW"
		preview.variant = "blue"
		preview.custom_minimum_size = Vector2(104.0, 46.0)
		preview.pressed.connect(_preview_locker_theme.bind(item_id))
		horizontal.add_child(preview)
	elif is_dance:
		var preview := OneGunButton.new()
		preview.text = "PREVIEW"
		preview.variant = "blue"
		preview.custom_minimum_size = Vector2(104.0, 46.0)
		preview.pressed.connect(_preview_locker_move.bind(item_id))
		horizontal.add_child(preview)
	elif slot == "hat":
		var preview := OneGunButton.new()
		preview.text = "PREVIEW"
		preview.variant = "blue"
		preview.custom_minimum_size = Vector2(104.0, 46.0)
		preview.pressed.connect(_preview_locker_hat.bind(item_id))
		horizontal.add_child(preview)
	elif slot == "character_model":
		var preview := OneGunButton.new()
		preview.text = "PREVIEW"
		preview.variant = "blue"
		preview.custom_minimum_size = Vector2(104.0, 46.0)
		preview.pressed.connect(_preview_locker_character_model.bind(item_id))
		horizontal.add_child(preview)
	if is_dance:
		var podium_button := _make_locker_slot_button(
			"emote", item_id, "EQUIP PODIUM")
		podium_button.custom_minimum_size.x = 132.0
		horizontal.add_child(podium_button)
		var round_button := _make_locker_slot_button(
			"round_victory_move", item_id, "EQUIP ROUND")
		round_button.custom_minimum_size.x = 132.0
		horizontal.add_child(round_button)
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

func _refresh_active_player() -> void:
	super._refresh_active_player()
	_update_loadout_summary()


func _on_locker_data_updated(_value = null, _extra = null) -> void:
	super._on_locker_data_updated(_value, _extra)
	_update_loadout_summary()


func _on_locker_equip_succeeded(slot: String, item_id: String) -> void:
	super._on_locker_equip_succeeded(slot, item_id)
	_update_loadout_summary()


func _update_loadout_summary() -> void:
	if _loadout_summary_label == null:
		return
	var skin_name := SkinRegistry.display_name(_pending_skin_for_slot(_active_slot)).to_upper()
	var model_name := SkinRegistry.model_display_name(
		_pending_model_for_slot(_active_slot)).to_upper()
	var ceremony_id := str(_backend.loadout.get("ceremony_theme", "")) \
		if _backend != null else ""
	var ceremony_name := "DEFAULT CEREMONY"
	if ceremony_id != "":
		ceremony_name = SupabaseCosmeticRegistry.display_name_fallback(ceremony_id).to_upper()
	_loadout_summary_label.text = "ACTIVE LOADOUT  •  %s %s  •  %s" % [
		model_name, skin_name, ceremony_name]


func _locker_icon_for_slot(slot: String) -> String:
	match slot:
		"ceremony_theme": return "♫"
		"emote", "victory_dance", "round_victory_move": return "★"
		"gun_skin", "melee_skin": return "OG"
		"outfit_bundle": return "✦"
		"hat", "shirt", "pants", "shoes", "accessory", "character_skin": return "◆"
	return "OG"


func _is_visual_capture() -> bool:
	return OS.get_environment("ONEGUN_UI_CAPTURE") != "" \
		and OS.get_environment("ONEGUN_UI_CAPTURE_STATE") == "character_customization"
