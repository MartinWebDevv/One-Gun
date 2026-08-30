extends Node

# GPU-backed animation contact sheets for every added fixed-look character.
# Run outside --headless so Forward+ produces real skinned-mesh captures.

const SkinRegistry = preload("res://player_skin_registry.gd")
const NEW_MODELS: Array[String] = [
	"goldfish_bag_man", "eye_wizard", "mr_mushroom", "mr_poop",
	"mr_salt", "spooky_witch",
]
const POSES: Array[Dictionary] = [
	{"animation": "idle", "sample": 0.20, "label": "IDLE"},
	{"animation": "standard_run", "sample": 0.28, "label": "RUN"},
	{"animation": "idle_pistol", "sample": 0.20, "label": "GUN STANCE"},
	{"animation": "melee", "sample": 0.42, "label": "MELEE"},
	{"animation": "throw_object", "sample": 0.42, "label": "THROW"},
	{"animation": "hip_hop_dance", "sample": 0.62, "label": "VICTORY"},
]

var _world: Node3D
var _camera: Camera3D
var _label: Label
var _output_dir := ""


func _ready() -> void:
	_output_dir = ProjectSettings.globalize_path(
		"res://.godot/new_character_render_validation")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	_build_world()
	_run.call_deferred()


func _run() -> void:
	var requested: Array[String] = []
	for pose in POSES:
		requested.append(str(pose["animation"]))
	for model_id in NEW_MODELS:
		var packed := SkinRegistry.load_visual_scene(model_id)
		if packed == null:
			_fail("missing visual scene for %s" % model_id)
			return
		var visual := packed.instantiate() as Node3D
		visual.set("build_animation_library", false)
		_world.add_child(visual)
		var player := visual.call("ensure_animations", requested) as AnimationPlayer
		if player == null:
			_fail("missing animation player for %s" % model_id)
			return
		var sheet := Image.create(960, 640, false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.035, 0.050, 0.095, 1.0))
		for pose_index in POSES.size():
			var pose: Dictionary = POSES[pose_index]
			var animation_name := str(pose["animation"])
			if not player.has_animation(animation_name):
				_fail("%s is missing %s" % [model_id, animation_name])
				return
			var animation := player.get_animation(animation_name)
			var sample_time := minf(
				float(pose["sample"]), maxf(0.0, animation.length * 0.72))
			player.play(animation_name, 0.0)
			player.seek(sample_time, true)
			player.advance(0.0)
			_label.text = "%s  •  %s" % [
				SkinRegistry.model_display_name(model_id).to_upper(),
				str(pose["label"])]
			await _wait_frames(3)
			RenderingServer.force_draw(false)
			await get_tree().process_frame
			var image := get_viewport().get_texture().get_image()
			if image == null or image.is_empty():
				_fail("empty render for %s %s" % [model_id, animation_name])
				return
			image.convert(Image.FORMAT_RGBA8)
			image.resize(320, 320, Image.INTERPOLATE_LANCZOS)
			var tile_position := Vector2i(
				(pose_index % 3) * 320, (pose_index / 3) * 320)
			sheet.blit_rect(image,
				Rect2i(Vector2i.ZERO, image.get_size()), tile_position)
		var output_path := "%s/%s_animation_contact_sheet.png" % [
			_output_dir, model_id]
		if sheet.save_png(output_path) != OK:
			_fail("could not save %s" % output_path)
			return
		visual.queue_free()
		await _wait_frames(3)
	print("NEW_CHARACTER_RENDER_VALIDATION: PASS models=%d poses=%d output=%s" % [
		NEW_MODELS.size(), POSES.size(), _output_dir])
	get_tree().quit(0)


func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "NewCharacterRenderWorld"
	add_child(_world)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.050, 0.095)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.48, 0.60, 0.88)
	environment.ambient_light_energy = 0.90
	environment_node.environment = environment
	_world.add_child(environment_node)

	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(4.2, 0.12, 3.4)
	floor_mesh.mesh = floor_box
	floor_mesh.position.y = -0.08
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.045, 0.085, 0.16)
	floor_material.metallic = 0.35
	floor_material.roughness = 0.34
	floor_mesh.material_override = floor_material
	_world.add_child(floor_mesh)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	key.light_color = Color(1.0, 0.84, 0.66)
	key.light_energy = 2.5
	key.shadow_enabled = true
	_world.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(1.8, 2.2, -1.4)
	rim.light_color = Color(0.20, 0.62, 1.0)
	rim.light_energy = 3.0
	rim.omni_range = 6.0
	_world.add_child(rim)

	_camera = Camera3D.new()
	_camera.fov = 39.0
	_camera.look_at_from_position(
		Vector3(0.0, 1.50, 5.55), Vector3(0.0, 1.42, 0.0), Vector3.UP)
	_camera.current = true
	_world.add_child(_camera)

	_label = OneGunUI.make_heading("CHARACTER ANIMATION QA", 27, "text_bright")
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_label.offset_left = 20.0
	_label.offset_top = -62.0
	_label.offset_right = -20.0
	_label.offset_bottom = -16.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override(
		"font_outline_color", Color(0.0, 0.0, 0.0, 0.96))
	_label.add_theme_constant_override("outline_size", 7)
	add_child(_label)


func _wait_frames(count: int) -> void:
	for _frame in count:
		await get_tree().process_frame


func _fail(message: String) -> void:
	push_error("NewCharacterRenderValidation: " + message)
	get_tree().quit(1)
