extends Node3D

# GPU-backed camera QA using the real gameplay player, every character model,
# every shipped Hat fit, and the procedural center-dot crosshair.

const HatRegistry = preload(
	"res://models/cosmetics/hats/hat_cosmetic_registry.gd")
const SkinRegistry = preload("res://player_skin_registry.gd")
const CAPTURE_CASES := [
	{
		"model": "male",
		"hat": "hat_crown",
		"ads": false,
		"file": "non_ads_wide_shoulder_male_crown.png",
	},
	{
		"model": "female",
		"hat": "hat_witch",
		"ads": false,
		"file": "non_ads_wide_shoulder_female_witch.png",
	},
	{
		"model": "male",
		"hat": "hat_crown",
		"ads": true,
		"file": "ads_shoulder_male_crown.png",
	},
	{
		"model": "goldfish_bag_man",
		"hat": "hat_top",
		"ads": false,
		"file": "non_ads_wide_shoulder_goldfish_top_hat.png",
	},
]

var failures: Array[String] = []
var _player = null
var _camera: Camera3D = null
var _caption: Label = null
var _capture_directory := ""


func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	GameConfig.split_screen_enabled = false
	GameConfig.bot_configs = []
	PauseManager._pause_open = false
	_build_world()
	_build_overlay()

	_player = load("res://player.tscn").instantiate()
	add_child(_player)
	_player.global_position = Vector3.ZERO
	await get_tree().process_frame
	_player.set_physics_process(false)
	_player.set_process_input(false)
	_camera = _player.get_gameplay_camera()
	_camera.current = true

	_capture_directory = ProjectSettings.globalize_path(
		"res://artifacts/camera_qa")
	DirAccess.make_dir_recursive_absolute(_capture_directory)

	await _validate_every_hat()
	await _capture_approved_angles()
	_finish()


func _validate_every_hat() -> void:
	var viewport_size := Vector2(get_viewport().get_visible_rect().size)
	var sight_center := viewport_size * 0.5
	var hat_ids: Array = HatRegistry.HATS.keys()
	hat_ids.sort()
	var checked := 0
	for model_id in SkinRegistry.MODEL_IDS:
		_player.set_character_appearance(model_id,
			"Orange" if model_id == "male" else "Purple")
		_play_idle_pose()
		for _settle_frame in 12:
			await get_tree().process_frame
		for hat_id_value in hat_ids:
			var hat_id := str(hat_id_value)
			_player.set_hat_cosmetic(hat_id)
			for _settle_frame in 6:
				await get_tree().process_frame
			for ads_value in [0.0, 1.0]:
				_player.ads_blend = ads_value
				_player._update_aiming(0.0)
				for _settle_frame in 4:
					await get_tree().process_frame
				for _sample in 4:
					await get_tree().process_frame
					var bounds := _hat_screen_bounds()
					var has_visible_bounds := bounds.size.x > 1.0 and bounds.size.y > 1.0
					_check(ads_value > 0.5 or has_visible_bounds,
						"%s/%s did not produce visible screen bounds" % [
							model_id, hat_id])
					# A close ADS shoulder is allowed to move the Hat fully behind the
					# near plane. If any of it remains visible, it must still clear aim.
					if not has_visible_bounds:
						continue
					var sight_margin := maxf(viewport_size.x * 0.008, 0.25)
					var sight_clear := (
						bounds.end.x <= sight_center.x - sight_margin
						or bounds.position.x >= sight_center.x + sight_margin
						or bounds.end.y <= sight_center.y - sight_margin
						or bounds.position.y >= sight_center.y + sight_margin)
					_check(sight_clear,
						"%s/%s covers the center sight lane at ADS %.0f: %s" % [
							model_id, hat_id, ads_value, bounds])
					var edge_margin := maxf(
						minf(viewport_size.x, viewport_size.y) * 0.005, 0.15)
					_check(ads_value > 0.5
						or (bounds.position.x >= edge_margin
							and bounds.end.x <= viewport_size.x - edge_margin
							and bounds.position.y >= edge_margin
							and bounds.end.y <= viewport_size.y - edge_margin),
						"%s/%s clips the gameplay frame at ADS %.0f: %s" % [
							model_id, hat_id, ads_value, bounds])
				checked += 1
	print("GAMEPLAY_HAT_CAMERA_MATRIX: checked=%d hats=%d models=%d modes=2" % [
		checked, hat_ids.size(), SkinRegistry.MODEL_IDS.size()])


func _capture_approved_angles() -> void:
	if RenderingServer.get_rendering_device() == null:
		print("GAMEPLAY_HAT_CAMERA_CAPTURE: skipped on dummy renderer")
		return
	for capture_case in CAPTURE_CASES:
		var model_id := str(capture_case["model"])
		var hat_id := str(capture_case["hat"])
		var ads_enabled := bool(capture_case["ads"])
		_player.set_character_appearance(model_id,
			"Orange" if model_id == "male" else "Purple")
		_player.set_hat_cosmetic(hat_id)
		_play_idle_pose()
		_player.ads_blend = 1.0 if ads_enabled else 0.0
		_player._update_aiming(0.0)
		_caption.text = "%s  /  %s  /  %s" % [
			"ADS" if ads_enabled else "NON-ADS WIDE SHOULDER",
			model_id.to_upper(),
			HatRegistry.display_name(hat_id).to_upper(),
		]
		for _frame in 8:
			await get_tree().process_frame
		RenderingServer.force_draw(false)
		await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		var output_path := _capture_directory.path_join(str(capture_case["file"]))
		_check(image != null and not image.is_empty()
			and image.save_png(output_path) == OK,
			"could not save camera screenshot %s" % output_path)
		print("GAMEPLAY_HAT_CAMERA_CAPTURE: %s" % output_path)


func _play_idle_pose() -> void:
	var visual: Node3D = _player.get_node_or_null("CharacterModel") as Node3D
	if visual == null or not visual.has_method("ensure_animations"):
		return
	var animation_player := visual.call(
		"ensure_animations", ["idle"]) as AnimationPlayer
	if animation_player == null or not animation_player.has_animation("idle"):
		return
	_player.model_anim_player = animation_player
	_player._current_anim = "idle"
	animation_player.play("idle")
	animation_player.advance(0.35)


func _hat_screen_bounds() -> Rect2:
	if _camera == null:
		return Rect2()
	var visual: Node3D = _player.get_node_or_null("CharacterModel") as Node3D
	if visual == null or not visual.has_method("get_headwear_socket"):
		return Rect2()
	var socket: Marker3D = visual.call("get_headwear_socket") as Marker3D
	if socket == null:
		return Rect2()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var found := false
	for node in socket.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or not mesh_instance.is_visible_in_tree():
			continue
		var bounds := mesh_instance.get_aabb()
		for x_value in [bounds.position.x, bounds.end.x]:
			for y_value in [bounds.position.y, bounds.end.y]:
				for z_value in [bounds.position.z, bounds.end.z]:
					var world_point := mesh_instance.to_global(
						Vector3(x_value, y_value, z_value))
					if _camera.is_position_behind(world_point):
						continue
					var screen_point := _camera.unproject_position(world_point)
					minimum = minimum.min(screen_point)
					maximum = maximum.max(screen_point)
					found = true
	return Rect2(minimum, maximum - minimum) if found else Rect2()


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	var crosshair := Control.new()
	crosshair.set_script(load("res://crosshair.gd"))
	crosshair.set_preview_settings({
		"crosshair_style": "dot",
		"crosshair_center_dot": true,
		"crosshair_dot_size": 4.0,
		"crosshair_size": 1.0,
		"crosshair_opacity": 1.0,
		"crosshair_color": [1.0, 1.0, 1.0, 1.0],
		"crosshair_outline": true,
		"crosshair_outline_color": [0.01, 0.01, 0.02, 1.0],
		"crosshair_outline_thickness": 2.0,
	})
	layer.add_child(crosshair)

	_caption = Label.new()
	_caption.position = Vector2(28.0, 24.0)
	_caption.add_theme_font_size_override("font_size", 24)
	_caption.add_theme_color_override("font_color", Color(0.2, 0.9, 1.0))
	layer.add_child(_caption)


func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.018, 0.045)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.32, 0.44, 0.75)
	environment.ambient_light_energy = 0.72
	environment.glow_enabled = true
	environment_node.environment = environment
	add_child(environment_node)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	light.light_energy = 2.6
	light.shadow_enabled = true
	add_child(light)

	_add_box("Floor", Vector3(24.0, 0.12, 36.0),
		Vector3(0.0, -1.07, -9.0), Color(0.025, 0.055, 0.13))
	_add_box("CenterTarget", Vector3(1.2, 2.4, 0.30),
		Vector3(0.0, 0.15, -9.0), Color(1.0, 0.35, 0.08))
	_add_box("LeftTarget", Vector3(1.0, 1.8, 0.30),
		Vector3(-3.2, -0.10, -11.0), Color(0.05, 0.70, 1.0))
	_add_box("RightTarget", Vector3(1.0, 1.8, 0.30),
		Vector3(3.2, -0.10, -11.0), Color(0.72, 0.20, 1.0))
	for x_value in [-6.0, -3.0, 0.0, 3.0, 6.0]:
		_add_box("Lane_%s" % x_value, Vector3(0.07, 0.02, 24.0),
			Vector3(x_value, -0.98, -9.0), Color(0.05, 0.55, 1.0))


func _add_box(node_name: String, size: Vector3, position_value: Vector3,
		color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position_value
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.25
	material.roughness = 0.42
	material.emission_enabled = true
	material.emission = color * 0.24
	mesh_instance.material_override = material
	add_child(mesh_instance)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	PauseManager._pause_open = false
	if failures.is_empty():
		print("GAMEPLAY_HAT_CAMERA_VALIDATION: PASS hats=%d models=%d modes=2 captures=%d" % [
			HatRegistry.HATS.size(), SkinRegistry.MODEL_IDS.size(), CAPTURE_CASES.size()])
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("GAMEPLAY_HAT_CAMERA_VALIDATION: %s" % failure)
	get_tree().quit(1)
