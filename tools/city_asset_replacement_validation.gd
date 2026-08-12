extends Node

const CITY_SCENE := preload("res://maps/test/CityMap.tscn")
const CAR_TRAFFIC := preload("res://car_traffic.gd")
const OUTPUT_DIR_DEFAULT := "res://.godot"

const REPLACEMENTS := [
	{
		"map_node": "Traffic/CarSedan",
		"scene": "res://models/cityAssets/HatchbackCar.tscn",
		"label": "HATCHBACK",
		"position": Vector3(-4.2, 0.0, 0.0),
	},
	{
		"map_node": "Traffic/CarVan",
		"scene": "res://models/cityAssets/StationwagonCar.tscn",
		"label": "STATION WAGON",
		"position": Vector3(0.0, 0.0, 0.0),
	},
	{
		"map_node": "Traffic/CarTaxi",
		"scene": "res://models/cityAssets/TaxiCar.tscn",
		"label": "TAXI",
		"position": Vector3(4.2, 0.0, 0.0),
	},
]

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _validate_city_references()
	var world := Node3D.new()
	world.name = "CityAssetLab"
	add_child(world)
	_build_environment(world)
	for replacement in REPLACEMENTS:
		var packed := load(str(replacement["scene"])) as PackedScene
		_check(packed != null, "missing replacement scene %s" % replacement["scene"])
		if packed == null:
			continue
		var instance := packed.instantiate() as Node3D
		instance.set_script(CAR_TRAFFIC)
		instance.position = replacement["position"]
		world.add_child(instance)
		await get_tree().process_frame
		instance.set_physics_process(false)
		_validate_car(instance, str(replacement["label"]))
		_add_label(world, str(replacement["label"]),
			instance.position + Vector3.UP * 2.65)

	var light_scene := load(
		"res://models/cityAssets/Streetlight.tscn") as PackedScene
	_check(light_scene != null, "missing normalized Streetlight scene")
	if light_scene != null:
		var streetlight := light_scene.instantiate() as Node3D
		streetlight.position = Vector3(7.4, 0.0, 1.0)
		world.add_child(streetlight)
		var light_bounds := _mesh_bounds(streetlight)
		_check(light_bounds.size.y >= 4.7 and light_bounds.size.y <= 4.9,
			"Streetlight is not normalized to City scale: %s" % light_bounds)
		_check(absf(light_bounds.position.y - streetlight.global_position.y) < 0.02,
			"Streetlight is not grounded: %s" % light_bounds)
		_add_label(world, "STREETLIGHT", Vector3(7.4, 5.2, 1.0))

	await _wait_frames(8)
	await _capture("city_asset_replacements_front.png")
	var camera := world.get_node("ValidationCamera") as Camera3D
	camera.look_at_from_position(
		Vector3(9.0, 5.0, 13.0), Vector3(1.2, 1.6, 0.0), Vector3.UP)
	await _wait_frames(3)
	await _capture("city_asset_replacements_rear.png")

	if failures.is_empty():
		print("CITY_ASSET_REPLACEMENT_VALIDATION: PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("CITY_ASSET_REPLACEMENT_VALIDATION: %s" % failure)
	get_tree().quit(1)


func _validate_city_references() -> void:
	var city := CITY_SCENE.instantiate() as Node3D
	var manager := city.get_node_or_null("RoundManager")
	if manager != null:
		manager.set_script(null)
	city.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(city)
	await get_tree().process_frame
	for replacement in REPLACEMENTS:
		var map_node := city.get_node_or_null(str(replacement["map_node"])) as Node3D
		_check(map_node != null, "City is missing %s" % replacement["map_node"])
		if map_node != null:
			_check(map_node.scene_file_path == str(replacement["scene"]),
				"%s still references %s" % [
					replacement["map_node"], map_node.scene_file_path])
	var lamp_count := 0
	for child in city.get_node("StreetFurniture").get_children():
		if child.name.begins_with("Lamp") and not child.name.begins_with("LampCol"):
			lamp_count += 1
			_check(child.scene_file_path == \
				"res://models/cityAssets/Streetlight.tscn",
				"%s does not use the replacement Streetlight" % child.name)
	_check(lamp_count == 10, "expected 10 replacement streetlights, found %d" % lamp_count)
	for light_name in ["TrafficLight1", "TrafficLight2", "TrafficLight3", "TrafficLight4"]:
		var traffic_light := city.get_node_or_null("StreetFurniture/" + light_name)
		_check(traffic_light != null, "City is missing %s" % light_name)
		if traffic_light != null:
			_check(traffic_light.scene_file_path == \
				"res://models/cityAssets/TrafficLight.glb",
				"%s was changed away from the approved TrafficLight GLB" % light_name)
	city.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _validate_car(car: Node3D, label: String) -> void:
	var bounds := _mesh_bounds(car)
	_check(bounds.size.x >= 2.0 and bounds.size.x <= 2.2,
		"%s width is outside City car scale: %s" % [label, bounds])
	_check(bounds.size.z >= 4.0 and bounds.size.z <= 4.8,
		"%s length is outside City car scale: %s" % [label, bounds])
	_check(absf(bounds.position.y - car.global_position.y) < 0.02,
		"%s is not grounded: %s" % [label, bounds])
	var wheels: Array = car.get("_wheels")
	_check(wheels.size() == 4,
		"%s traffic script found %d wheels instead of 4" % [label, wheels.size()])
	var wheel_rotations: Array[Basis] = []
	for wheel in wheels:
		wheel_rotations.append((wheel as Node3D).basis)
	car.call("_spin_wheels", 6.0, 0.1)
	var moved_wheels := 0
	for wheel_index in wheels.size():
		if not (wheels[wheel_index] as Node3D).basis.is_equal_approx(
				wheel_rotations[wheel_index]):
			moved_wheels += 1
	_check(moved_wheels == 4,
		"%s did not animate all four discovered wheels" % label)
	var visual_root := car.get_node_or_null("Model") as Node3D
	_check(visual_root != null and absf(absf(visual_root.rotation.y) - PI) < 0.01,
		"%s visual forward axis is not corrected for City traffic" % label)
	var hit_zone := car.get_node_or_null("HitZone")
	_check(hit_zone != null and not hit_zone.find_children(
		"*", "CollisionShape3D", true, false).is_empty(),
		"%s is missing its traffic knockback volume" % label)


func _build_environment(world: Node3D) -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.055, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.95)
	env.ambient_light_energy = 1.1
	environment.environment = env
	world.add_child(environment)

	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(22.0, 0.08, 10.0)
	floor.mesh = floor_mesh
	floor.position.y = -0.04
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.12, 0.15, 0.22)
	floor.material_override = floor_material
	world.add_child(floor)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, 28.0, 0.0)
	light.light_energy = 2.2
	light.shadow_enabled = true
	world.add_child(light)

	var camera := Camera3D.new()
	camera.name = "ValidationCamera"
	camera.fov = 48.0
	camera.look_at_from_position(
		Vector3(9.0, 5.0, -13.0), Vector3(1.2, 1.6, 0.0), Vector3.UP)
	camera.current = true
	world.add_child(camera)


func _add_label(world: Node3D, text: String, position: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.font_size = 42
	label.outline_size = 8
	label.modulate = Color(1.0, 0.76, 0.12)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	world.add_child(label)


func _mesh_bounds(root_node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var bounds := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		result = bounds if first else result.merge(bounds)
		first = false
	return result


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var output_dir := OS.get_environment("ONEGUN_CITY_ASSET_OUTPUT")
	if output_dir.is_empty():
		output_dir = ProjectSettings.globalize_path(OUTPUT_DIR_DEFAULT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var path := output_dir.path_join(file_name)
	var error := get_viewport().get_texture().get_image().save_png(path)
	_check(error == OK, "could not save visual capture %s" % path)
	print("CITY_ASSET_REPLACEMENT_CAPTURE ", path)


func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
