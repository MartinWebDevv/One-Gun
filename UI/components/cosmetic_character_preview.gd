class_name CosmeticCharacterPreview
extends Control

signal close_requested

const SkinRegistry = preload("res://player_skin_registry.gd")

var _item_id := ""
var _display_name := "COSMETIC REWARD"
var _milestone_text := ""
var _rarity := "standard"
var _viewport: SubViewport
var _pivot: Node3D
var _visual: Node3D
var _camera: Camera3D
var _status_label: Label
var _close_button: OneGunButton
var _viewport_container: SubViewportContainer
var _dragging_preview := false


func configure(item_id: String, display_name: String,
		milestone_text: String, rarity: String) -> void:
	_item_id = SupabaseCosmeticRegistry.sanitize_item_id(item_id)
	_display_name = display_name.strip_edges() if display_name.strip_edges() != "" \
		else SupabaseCosmeticRegistry.display_name_fallback(_item_id)
	_milestone_text = milestone_text.strip_edges()
	_rarity = rarity.strip_edges().to_lower()


func _ready() -> void:
	name = "CosmeticMilestonePreview"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_show_cosmetic()
	_close_button.grab_focus.call_deferred()


func _process(delta: float) -> void:
	if _pivot == null or not visible:
		return
	var look_axis := Input.get_axis("p1_look_left", "p1_look_right")
	if absf(look_axis) > 0.18:
		_rotate_preview(look_axis * 1.9 * delta)


func _build_ui() -> void:
	var scrim := ColorRect.new()
	scrim.name = "CosmeticPreviewScrim"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.001, 0.004, 0.014, 0.78)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var window := PanelContainer.new()
	window.name = "CosmeticPreviewWindow"
	window.position = Vector2(500.0, 118.0)
	window.size = Vector2(600.0, 664.0)
	window.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(0.008, 0.018, 0.046, 0.99),
		Color(OneGunUI.color(_rarity_role()), 0.92), 18, 2, 8, 22.0))
	add_child(window)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	window.add_child(column)
	var heading := OneGunUI.make_heading(_display_name.to_upper(), 30,
		_rarity_role())
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var milestone := OneGunUI.make_label(_milestone_text.to_upper(),
		OneGunUI.TEXT_S, "muted", true)
	milestone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(milestone)

	var preview_frame := PanelContainer.new()
	preview_frame.custom_minimum_size = Vector2(0.0, 438.0)
	preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_frame.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(0.004, 0.009, 0.026), Color(OneGunUI.color("border"), 0.72),
		14, 1, 0, 8.0))
	column.add_child(preview_frame)
	var preview_stack := Control.new()
	preview_stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_frame.add_child(preview_stack)
	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "CosmeticPreviewViewportContainer"
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport_container.gui_input.connect(_on_preview_gui_input)
	preview_stack.add_child(_viewport_container)
	_build_preview_world(_viewport_container)

	_status_label = OneGunUI.make_label("", OneGunUI.TEXT_S, "green", true)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	_close_button = OneGunButton.new()
	_close_button.name = "CosmeticPreviewCloseButton"
	_close_button.text = "BACK"
	_close_button.variant = "navy"
	_close_button.custom_minimum_size = Vector2(220.0, 52.0)
	_close_button.pressed.connect(func() -> void: close_requested.emit())
	footer.add_child(_close_button)
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_spacer)


func _build_preview_world(container: SubViewportContainer) -> void:
	_viewport = SubViewport.new()
	_viewport.name = "CosmeticPreviewViewport"
	_viewport.size = Vector2i(512, 384)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(_viewport)
	var world := Node3D.new()
	world.name = "CosmeticPreviewWorld"
	_viewport.add_child(world)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.014, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.62, 0.88)
	env.ambient_light_energy = 1.0
	environment.environment = env
	world.add_child(environment)

	var podium := MeshInstance3D.new()
	podium.name = "CosmeticPreviewPodium"
	var podium_mesh := CylinderMesh.new()
	podium_mesh.top_radius = 1.05
	podium_mesh.bottom_radius = 1.15
	podium_mesh.height = 0.20
	podium_mesh.radial_segments = 32
	podium.mesh = podium_mesh
	podium.position.y = 0.10
	var podium_material := StandardMaterial3D.new()
	podium_material.albedo_color = Color(0.055, 0.085, 0.17)
	podium_material.metallic = 0.72
	podium_material.roughness = 0.25
	podium_material.emission_enabled = true
	podium_material.emission = Color(0.06, 0.16, 0.34)
	podium_material.emission_energy_multiplier = 0.75
	podium.material_override = podium_material
	world.add_child(podium)

	_pivot = Node3D.new()
	_pivot.name = "CosmeticPreviewCharacterPivot"
	_pivot.position.y = 0.20
	world.add_child(_pivot)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	key.light_color = Color(1.0, 0.82, 0.60)
	key.light_energy = 2.0
	key.shadow_enabled = false
	world.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(1.6, 1.9, -1.4)
	rim.light_color = Color(0.24, 0.56, 1.0)
	rim.light_energy = 2.6
	rim.omni_range = 5.0
	rim.shadow_enabled = false
	world.add_child(rim)
	_camera = Camera3D.new()
	_camera.name = "CosmeticPreviewCamera"
	_camera.fov = 36.0
	world.add_child(_camera)
	_camera.look_at_from_position(
		Vector3(0.0, 1.56, 5.95), Vector3(0.0, 1.20, 0.0), Vector3.UP)
	_camera.current = true
	GraphicsQualityManager.apply_subtree(_viewport)


func _show_cosmetic() -> void:
	var model_id := SkinRegistry.sanitize_model_id(
		str(PlayerPrefs.get_setting("character_model_id")))
	var visual_scene := SkinRegistry.load_visual_scene(model_id)
	if visual_scene == null:
		_status_label.text = "CHARACTER PREVIEW UNAVAILABLE"
		return
	_visual = visual_scene.instantiate() as Node3D
	if _visual == null:
		_status_label.text = "CHARACTER PREVIEW UNAVAILABLE"
		return
	_visual.name = "CosmeticPreviewCharacter"
	_visual.set("build_animation_library", false)
	_pivot.add_child(_visual)
	if _visual.has_method("set_skin"):
		_visual.call("set_skin", SkinRegistry.sanitize_skin_id(
			str(PlayerPrefs.get_setting("character_skin_id"))))
	# Every milestone preview has a composed fallback: the selected character is
	# centered on the podium and uses the shared mascot idle even when that reward
	# does not yet have a local cosmetic mesh.
	var idle_player := _visual.call("ensure_animations", ["idle"]) as AnimationPlayer
	var animated := false
	if idle_player != null and idle_player.has_animation("idle"):
		idle_player.play("idle", 0.0)
		idle_player.advance(0.12)
		animated = true
	var slot := SupabaseCosmeticRegistry.known_slot_for_id(_item_id)
	var preview_ready := false
	if slot in ["hat", "shirt", "pants", "shoes", "accessory"] \
			and _visual.has_method("set_wearable_cosmetic"):
		_visual.call("set_wearable_cosmetic", slot, _item_id)
		_frame_hat_safe_full_body()
		preview_ready = SupabaseCosmeticRegistry.has_local_visual(_item_id, slot)
	elif slot == "character_skin" and _visual.has_method("set_skin"):
		var skin_id := SupabaseCosmeticRegistry.local_character_skin_id(_item_id)
		if skin_id != "":
			_visual.call("set_skin", skin_id)
			preview_ready = true
	elif slot in ["victory_dance", "emote", "round_victory_move"]:
		var animation_name := SupabaseCosmeticRegistry.local_victory_animation(_item_id)
		var player := _visual.call("ensure_animations", [animation_name]) as AnimationPlayer
		if animation_name != "" and player != null and player.has_animation(animation_name):
			player.play(animation_name, 0.08)
			player.advance(0.0)
			preview_ready = true
			animated = true
	_status_label.text = "PREVIEWING ON YOUR CURRENT CHARACTER" if preview_ready \
		else "3D ART PREVIEW PENDING — REWARD OWNERSHIP IS STILL PERMANENT"
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if animated \
		else SubViewport.UPDATE_ONCE


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_preview = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging_preview:
		_rotate_preview(event.relative.x * 0.012)
		accept_event()


func _rotate_preview(angle: float) -> void:
	if _pivot == null or is_zero_approx(angle):
		return
	_pivot.rotate_y(angle)
	if _viewport != null and _viewport.render_target_update_mode != \
			SubViewport.UPDATE_ALWAYS:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _frame_hat_safe_full_body() -> void:
	if _camera == null or _visual == null:
		return
	var frame_top := _pivot.global_position.y + 2.80
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null \
				or not mesh_instance.is_visible_in_tree():
			continue
		var world_bounds := mesh_instance.global_transform \
			* mesh_instance.mesh.get_aabb()
		frame_top = maxf(frame_top,
			world_bounds.position.y + world_bounds.size.y)
	var frame_bottom := _pivot.global_position.y - 0.10
	frame_top += 0.16
	var frame_center := (frame_bottom + frame_top) * 0.5
	_camera.look_at_from_position(
		Vector3(0.0, frame_center + 0.36, 5.95),
		Vector3(0.0, frame_center, 0.0), Vector3.UP)


func _rarity_role() -> String:
	match _rarity:
		"legendary": return "gold"
		"epic": return "purple"
		"rare": return "cyan"
		"uncommon": return "green"
	return "muted"
