extends Node3D

const SMOKE_SCENE := preload("res://smoke_cloud.tscn")


func _ready() -> void:
	_build_environment()
	var smoke := SMOKE_SCENE.instantiate()
	smoke.name = "ValidationSmoke"
	add_child(smoke)
	smoke.call("_update_radius", smoke.cloud_radius)
	smoke.set_process(false)
	await _wait_frames(24)
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("ONE_GUN_SMOKE_RENDER_OUTPUT")
	if output.is_empty():
		output = ProjectSettings.globalize_path("res://smoke_cloud_validation.png")
	var error := get_viewport().get_texture().get_image().save_png(output)
	if error != OK:
		push_error("SMOKE_RENDER_VALIDATION_FAILED save_error=%d" % error)
		get_tree().quit(1)
		return
	print("SMOKE_RENDER_VALIDATION_OK output=", output)
	get_tree().quit(0)


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.07, 0.11)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.84, 0.94)
	environment.ambient_light_energy = 1.3
	world_environment.environment = environment
	add_child(world_environment)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(28.0, 28.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.18, 0.22, 0.29)
	floor_mesh.material = floor_material
	floor.mesh = floor_mesh
	add_child(floor)

	# High-contrast scenery makes any unwanted view through the cloud obvious.
	for data in [
		[Vector3(-3.2, 1.5, 3.4), Color(0.95, 0.12, 0.08)],
		[Vector3(0.0, 1.5, 4.2), Color(0.08, 0.85, 0.25)],
		[Vector3(3.2, 1.5, 3.4), Color(0.10, 0.35, 1.0)],
	]:
		var block := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.2, 3.0, 1.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = data[1]
		box.material = material
		block.mesh = box
		block.position = data[0]
		add_child(block)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	light.light_energy = 1.4
	add_child(light)

	var camera := Camera3D.new()
	camera.fov = 58.0
	camera.look_at_from_position(
		Vector3(8.5, 3.0, -10.5), Vector3(0.0, 1.05, 0.0), Vector3.UP)
	camera.current = true
	add_child(camera)


func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame
