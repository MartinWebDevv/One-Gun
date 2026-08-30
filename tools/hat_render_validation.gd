extends Node

# GPU-backed contact sheets for visual QA of every Hat on every registered model.
# Run outside --headless; the caller may hide the temporary validation window.

const HatRegistry = preload("res://models/cosmetics/hats/hat_cosmetic_registry.gd")
const SkinRegistry = preload("res://player_skin_registry.gd")

var _world: Node3D
var _camera: Camera3D
var _label: Label
var _output_dir := ""


func _ready() -> void:
	_output_dir = ProjectSettings.globalize_path(
		"res://.godot/hat_render_validation")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	_build_world()
	_run.call_deferred()


func _run() -> void:
	var ids: Array = HatRegistry.HATS.keys()
	ids.sort()
	var model_ids: Array[String] = []
	model_ids.assign(SkinRegistry.MODEL_IDS)
	var requested_model := OS.get_environment(
		"ONEGUN_HAT_RENDER_MODEL").strip_edges().to_lower()
	if requested_model != "":
		if requested_model not in SkinRegistry.MODEL_IDS:
			_fail("unknown requested model %s" % requested_model)
			return
		model_ids = [requested_model]
	for model_id in model_ids:
		var visual_scene := SkinRegistry.load_visual_scene(model_id)
		if visual_scene == null:
			_fail("missing %s visual" % model_id)
			return
		var visual := visual_scene.instantiate() as Node3D
		visual.name = "HatRenderCharacter"
		visual.set("build_animation_library", false)
		_world.add_child(visual)
		visual.call("set_skin", "blue")
		var animation_player := visual.call(
			"ensure_animations", ["idle"]) as AnimationPlayer
		if animation_player != null and animation_player.has_animation("idle"):
			animation_player.play("idle", 0.0)
			animation_player.advance(0.12)
			animation_player.pause()
		var sheet := Image.create(1280, 960, false, Image.FORMAT_RGBA8)
		var top_sheet := Image.create(1280, 960, false, Image.FORMAT_RGBA8)
		# Keep black/dark-brimmed hats readable in the QA artifact.
		sheet.fill(Color(0.045, 0.060, 0.115, 1.0))
		top_sheet.fill(Color(0.045, 0.060, 0.115, 1.0))
		for index in ids.size():
			var item_id := str(ids[index])
			visual.call("set_hat_cosmetic", item_id)
			_label.text = "%s  •  %s" % [
				model_id.to_upper(), HatRegistry.display_name(item_id).to_upper()]
			await _wait_frames(4)
			RenderingServer.force_draw(false)
			await get_tree().process_frame
			var image := get_viewport().get_texture().get_image()
			if image == null or image.is_empty():
				_fail("empty render for %s %s" % [model_id, item_id])
				return
			# D3D12 Forward+ readback may use RGBH/RGBAH while the contact sheet is
			# RGBA8. Normalize before blitting so format mismatches cannot silently
			# produce an empty sheet followed by a false PASS marker.
			image.convert(Image.FORMAT_RGBA8)
			image.resize(320, 320, Image.INTERPOLATE_LANCZOS)
			var tile_position := Vector2i((index % 4) * 320, (index / 4) * 320)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), tile_position)

			# A dedicated overhead contact sheet catches the easy-to-miss case where
			# a hat looks centered from the front but sits forward/backward on the skull.
			_camera.look_at_from_position(
				Vector3(0.0, 5.50, 0.05), Vector3(0.0, 1.90, 0.0),
				Vector3(0.0, 0.0, -1.0))
			await _wait_frames(2)
			RenderingServer.force_draw(false)
			await get_tree().process_frame
			var top_image := get_viewport().get_texture().get_image()
			if top_image == null or top_image.is_empty():
				_fail("empty overhead render for %s %s" % [model_id, item_id])
				return
			top_image.convert(Image.FORMAT_RGBA8)
			top_image.resize(320, 320, Image.INTERPOLATE_LANCZOS)
			top_sheet.blit_rect(top_image,
				Rect2i(Vector2i.ZERO, top_image.get_size()), tile_position)
			_frame_front_camera()
			await _wait_frames(2)
		var output_path := "%s/%s_hat_contact_sheet.png" % [_output_dir, model_id]
		if sheet.save_png(output_path) != OK:
			_fail("could not save %s" % output_path)
			return
		var top_output_path := "%s/%s_hat_top_contact_sheet.png" % [
			_output_dir, model_id]
		if top_sheet.save_png(top_output_path) != OK:
			_fail("could not save %s" % top_output_path)
			return
		visual.queue_free()
		await _wait_frames(3)
	print("HAT_RENDER_VALIDATION: PASS output=%s" % _output_dir)
	get_tree().quit(0)


func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "HatRenderWorld"
	add_child(_world)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.045, 0.060, 0.115)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.48, 0.60, 0.90)
	environment.ambient_light_energy = 0.85
	environment_node.environment = environment
	_world.add_child(environment_node)

	var pedestal := MeshInstance3D.new()
	var pedestal_mesh := CylinderMesh.new()
	pedestal_mesh.top_radius = 1.12
	pedestal_mesh.bottom_radius = 1.22
	pedestal_mesh.height = 0.20
	pedestal_mesh.radial_segments = 48
	pedestal.mesh = pedestal_mesh
	pedestal.position.y = -0.10
	var pedestal_material := StandardMaterial3D.new()
	pedestal_material.albedo_color = Color(0.035, 0.06, 0.13)
	pedestal_material.metallic = 0.7
	pedestal_material.roughness = 0.24
	pedestal.material_override = pedestal_material
	_world.add_child(pedestal)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -30.0, 0.0)
	key.light_color = Color(1.0, 0.84, 0.64)
	key.light_energy = 2.4
	key.shadow_enabled = true
	_world.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(1.8, 2.3, -1.8)
	rim.light_color = Color(0.18, 0.58, 1.0)
	rim.light_energy = 3.2
	rim.omni_range = 6.0
	_world.add_child(rim)

	_camera = Camera3D.new()
	# Frame the animated head/socket rather than the full pedestal. Tall hats can
	# extend more than a body-height above the ears, so the old full-body framing
	# could clip every hat while still producing a plausible-looking test image.
	_camera.fov = 38.0
	_world.add_child(_camera)
	_frame_front_camera()
	_camera.current = true

	_label = OneGunUI.make_heading("HAT VALIDATION", 28, "text_bright")
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_label.offset_left = 24.0
	_label.offset_top = -62.0
	_label.offset_right = -24.0
	_label.offset_bottom = -18.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_label.add_theme_constant_override("outline_size", 7)
	add_child(_label)


func _frame_front_camera() -> void:
	_camera.look_at_from_position(
		Vector3(0.0, 2.25, 5.40), Vector3(0.0, 2.25, 0.0), Vector3.UP)


func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _fail(message: String) -> void:
	push_error("HatRenderValidation: " + message)
	get_tree().quit(1)
