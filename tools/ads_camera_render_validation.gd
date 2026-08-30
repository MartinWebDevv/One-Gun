extends Node3D

# GPU-backed framing check using the real player scene and gameplay camera.

var _output_path := ""


func _ready() -> void:
	GameConfig.split_screen_enabled = false
	GameConfig.bot_configs = []
	_build_world()
	var player = load("res://player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector3.ZERO
	await get_tree().process_frame
	player.set_physics_process(false)
	player.ads_blend = 1.0
	player._update_aiming(0.0)
	var camera := player.get_node("AimPivot/SpringArm3D/Camera3D") as Camera3D
	camera.current = true
	_output_path = ProjectSettings.globalize_path(
		"res://.godot/ads_camera_validation.png")
	_capture.call_deferred(camera, player)


func _capture(camera: Camera3D, player: Node3D) -> void:
	for _index in 8:
		await get_tree().process_frame
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(_output_path) != OK:
		push_error("ADS_CAMERA_RENDER_VALIDATION: capture failed")
		get_tree().quit(1)
		return
	var offset: Vector3 = camera.global_position - player.global_position
	if offset.length() <= 1.0 or camera.fov > 90.0:
		push_error("ADS_CAMERA_RENDER_VALIDATION: unsafe framing %s fov=%.2f" % [
			offset, camera.fov])
		get_tree().quit(1)
		return
	print("ADS_CAMERA_RENDER_VALIDATION: PASS output=%s offset=%s fov=%.2f" % [
		_output_path, offset, camera.fov])
	get_tree().quit(0)


func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.035, 0.075)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.42, 0.56, 0.85)
	environment.ambient_light_energy = 0.85
	environment_node.environment = environment
	add_child(environment_node)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -28.0, 0.0)
	light.light_energy = 2.3
	light.shadow_enabled = true
	add_child(light)

	_add_box("Floor", Vector3(20.0, 0.1, 30.0), Vector3(0.0, -1.05, -8.0),
		Color(0.055, 0.10, 0.19))
	_add_box("CenterTarget", Vector3(1.2, 2.4, 0.25), Vector3(0.0, 0.2, -8.0),
		Color(1.0, 0.38, 0.12))
	_add_box("LeftTarget", Vector3(1.0, 1.8, 0.25), Vector3(-3.0, -0.1, -10.0),
		Color(0.10, 0.75, 1.0))
	_add_box("RightTarget", Vector3(1.0, 1.8, 0.25), Vector3(3.0, -0.1, -10.0),
		Color(0.70, 0.25, 1.0))


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
	material.roughness = 0.45
	mesh_instance.material_override = material
	add_child(mesh_instance)
