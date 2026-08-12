extends Node3D

const CITY_SCENE := preload("res://maps/test/CityMap.tscn")
const OUTPUT_DIR_DEFAULT := "res://.godot"
const BUILDING_SPECS := [
	{
		"id": "c",
		"scene": preload("res://models/cityAssets/BuildingC_Enterable.tscn"),
		"scene_path": "res://models/cityAssets/BuildingC_Enterable.tscn",
		"source_mesh": "Exterior/RootNode/building_A",
		"original_scene": "res://models/cityAssets/BuildingC_FacadeShort.tscn",
		"position": Vector3(-8.0, 0.0, 0.0),
		"collider_count": 13,
		"front_door": Vector3(-1.8, 1.3, 0.0),
		"front_window": Vector3(0.91, 1.3, 0.0),
		"side_door": Vector3(0.0, 1.3, 0.0),
		"side_wall": Vector3(0.0, 1.3, 1.08),
		"front_camera": Vector3(8.7, 5.2, 11.5),
		"front_target": Vector3(0.0, 2.15, 0.0),
		"interior_camera": Vector3(-1.8, 1.55, 0.85),
		"interior_target": Vector3(1.2, 1.4, -0.6),
		"side_camera": Vector3(8.5, 3.7, 0.15),
		"side_target": Vector3(1.1, 1.65, 0.0),
	},
	{
		"id": "b",
		"scene": preload("res://models/cityAssets/BuildingB_Enterable.tscn"),
		"scene_path": "res://models/cityAssets/BuildingB_Enterable.tscn",
		"source_mesh": "Exterior/RootNode/building_B",
		"original_scene": "res://models/cityAssets/BuildingB_FacadeMidA.tscn",
		"position": Vector3(8.0, 0.0, 0.0),
		"collider_count": 17,
		"front_door": Vector3(-2.465, 1.45, 0.0),
		"front_window": Vector3(-0.815, 1.45, 0.0),
		"side_door": Vector3(0.0, 1.45, 0.0),
		"side_wall": Vector3(0.0, 1.45, 1.08),
		"front_camera": Vector3(10.0, 7.0, 15.0),
		"front_target": Vector3(0.0, 4.0, 0.0),
		"interior_camera": Vector3(-2.465, 1.7, 0.85),
		"interior_target": Vector3(1.5, 1.55, -0.6),
		"side_camera": Vector3(10.0, 5.0, 0.15),
		"side_target": Vector3(1.2, 2.0, 0.0),
	},
]

var failures: Array[String] = []
var buildings: Dictionary = {}
var camera: Camera3D = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_environment()
	for spec in BUILDING_SPECS:
		var instance := (spec["scene"] as PackedScene).instantiate() as Node3D
		instance.position = spec["position"]
		buildings[spec["id"]] = instance
		add_child(instance)
	await _wait_frames(3)
	await _validate_existing_city_is_untouched()
	_validate_asset_structure()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_validate_collision_openings()
	await _validate_navigation()
	if OS.get_environment("ONEGUN_SKIP_ENTERABLE_CAPTURES") != "1":
		await _capture_views()

	if failures.is_empty():
		print("ENTERABLE_CITY_BUILDINGS_VALIDATION: PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("ENTERABLE_CITY_BUILDINGS_VALIDATION: %s" % failure)
	get_tree().quit(1)


func _validate_existing_city_is_untouched() -> void:
	var city := CITY_SCENE.instantiate() as Node3D
	var manager := city.get_node_or_null("RoundManager")
	if manager != null:
		manager.set_script(null)
	city.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(city)
	await get_tree().process_frame
	var perimeter := city.get_node_or_null("PerimeterFacades")
	_check(perimeter != null, "City map is missing PerimeterFacades")
	if perimeter != null:
		for spec in BUILDING_SPECS:
			var original_count := 0
			var enterable_count := 0
			for child in perimeter.get_children():
				if child.scene_file_path == spec["original_scene"]:
					original_count += 1
				elif child.scene_file_path == spec["scene_path"]:
					enterable_count += 1
			_check(original_count == 6,
				"existing Building %s facade count changed: %d" % [
					str(spec["id"]).to_upper(), original_count])
			_check(enterable_count == 0,
				"an existing City facade was replaced by Building %s Enterable" %
				str(spec["id"]).to_upper())
	city.queue_free()
	await get_tree().process_frame


func _validate_asset_structure() -> void:
	for spec in BUILDING_SPECS:
		var building := buildings[spec["id"]] as Node3D
		_check(building.scene_file_path == spec["scene_path"],
			"Building %s did not instantiate its independent scene" %
			str(spec["id"]).to_upper())
		var source_mesh := building.get_node_or_null(spec["source_mesh"]) as MeshInstance3D
		_check(source_mesh != null,
			"Building %s lost its source exterior mesh" % str(spec["id"]).to_upper())
		if source_mesh != null:
			_check(source_mesh.material_override is ShaderMaterial,
				"Building %s cutout material is not bound" % str(spec["id"]).to_upper())
		var structure := building.get_node_or_null("Structure") as StaticBody3D
		_check(structure != null,
			"Building %s has no static structure" % str(spec["id"]).to_upper())
		if structure != null:
			_check(structure.get_child_count() == int(spec["collider_count"]),
				"Building %s collider count is %d instead of %d" % [
					str(spec["id"]).to_upper(), structure.get_child_count(),
					int(spec["collider_count"])])
			for child in structure.get_children():
				if child is CollisionShape3D:
					_check((child as CollisionShape3D).scale.is_equal_approx(Vector3.ONE),
						"Building %s/%s uses unsafe non-uniform collider scaling" % [
							str(spec["id"]).to_upper(), child.name])
		for marker_name in ["FrontDoorOutside", "FrontDoorInside",
				"SideDoorOutside", "SideDoorInside", "InteriorCenter"]:
			_check(building.has_node("NavigationEntries/" + marker_name),
				"Building %s is missing navigation marker %s" % [
					str(spec["id"]).to_upper(), marker_name])


func _validate_collision_openings() -> void:
	for spec in BUILDING_SPECS:
		var building := buildings[spec["id"]] as Node3D
		var front_door: Vector3 = spec["front_door"]
		_check_ray_clear(building, Vector3(front_door.x, front_door.y, 2.3),
			Vector3(front_door.x, front_door.y, 0.75), "front doorway is blocked")
		var front_window: Vector3 = spec["front_window"]
		_check_ray_hits_structure(building,
			Vector3(front_window.x, front_window.y, 2.3),
			Vector3(front_window.x, front_window.y, 0.75),
			"front window can be walked through")
		var side_door: Vector3 = spec["side_door"]
		_check_ray_clear(building, Vector3(3.8, side_door.y, side_door.z),
			Vector3(2.1, side_door.y, side_door.z), "side doorway is blocked")
		var side_wall: Vector3 = spec["side_wall"]
		_check_ray_hits_structure(building,
			Vector3(3.8, side_wall.y, side_wall.z),
			Vector3(2.1, side_wall.y, side_wall.z),
			"right-side wall has a collision gap")


func _validate_navigation() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.45
	nav_mesh.agent_height = 2.5
	nav_mesh.agent_max_climb = 0.8
	nav_mesh.agent_max_slope = 48.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, self)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	print("ENTERABLE_NAV_BAKE polygons=", nav_mesh.get_polygon_count(), " vertices=", nav_mesh.get_vertices().size())
	_check(nav_mesh.get_polygon_count() > 0, "navigation bake produced no polygons")
	if nav_mesh.get_polygon_count() <= 0:
		return
	var region := NavigationRegion3D.new()
	region.name = "ValidationNavigation"
	add_child(region)
	var navigation_map := get_world_3d().navigation_map
	NavigationServer3D.map_set_active(navigation_map, true)
	NavigationServer3D.region_set_map(region.get_rid(), navigation_map)
	region.navigation_mesh = nav_mesh
	region.enabled = true
	var starting_iteration := NavigationServer3D.map_get_iteration_id(navigation_map)
	var deadline := Time.get_ticks_msec() + 5000
	for frame in 10:
		await get_tree().physics_frame
	while (NavigationServer3D.map_get_iteration_id(navigation_map) == 0 \
			or NavigationServer3D.map_get_iteration_id(navigation_map) <= starting_iteration) \
			and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	_check(NavigationServer3D.map_get_iteration_id(navigation_map) > starting_iteration,
		"navigation map did not synchronize")
	if NavigationServer3D.map_get_iteration_id(navigation_map) <= starting_iteration:
		return
	for spec in BUILDING_SPECS:
		var building := buildings[spec["id"]] as Node3D
		var entries := building.get_node("NavigationEntries")
		var center := (entries.get_node("InteriorCenter") as Marker3D).global_position
		var center_nav := NavigationServer3D.map_get_closest_point(navigation_map, center)
		_check(center_nav.distance_to(center) < 0.65,
			"Building %s interior is not covered by navigation" % str(spec["id"]).to_upper())
		for marker_name in ["FrontDoorOutside", "SideDoorOutside"]:
			var target := (entries.get_node(marker_name) as Marker3D).global_position
			var target_nav := NavigationServer3D.map_get_closest_point(navigation_map, target)
			_check(target_nav.distance_to(target) < 0.65,
				"Building %s/%s is not covered by navigation" % [
					str(spec["id"]).to_upper(), marker_name])
			var path := NavigationServer3D.map_get_path(
				navigation_map, center_nav, target_nav, true)
			_check(path.size() >= 2,
				"bots cannot path between Building %s interior and %s" % [
					str(spec["id"]).to_upper(), marker_name])


func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.025, 0.04, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.8, 0.96)
	env.ambient_light_energy = 0.82
	environment.environment = env
	add_child(environment)

	var floor_body := StaticBody3D.new()
	floor_body.name = "ValidationGround"
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40.0, 0.1, 18.0)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.05
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	var floor_visual := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(40.0, 0.1, 18.0)
	floor_visual.mesh = floor_mesh
	floor_visual.position.y = -0.05
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.16, 0.18, 0.22)
	floor_material.roughness = 0.9
	floor_visual.material_override = floor_material
	add_child(floor_visual)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -34.0, 0.0)
	light.light_energy = 1.55
	light.shadow_enabled = true
	add_child(light)
	camera = Camera3D.new()
	camera.name = "ValidationCamera"
	camera.fov = 50.0
	camera.current = true
	add_child(camera)


func _capture_views() -> void:
	for spec in BUILDING_SPECS:
		for candidate in buildings.values():
			(candidate as Node3D).visible = false
		var building := buildings[spec["id"]] as Node3D
		building.visible = true
		var prefix := "building_%s_enterable" % spec["id"]
		await _set_camera_and_capture(building.position + spec["front_camera"],
			building.position + spec["front_target"], prefix + "_front.png")
		await _set_camera_and_capture(building.position + spec["interior_camera"],
			building.position + spec["interior_target"], prefix + "_interior.png")
		await _set_camera_and_capture(building.position + spec["side_camera"],
			building.position + spec["side_target"], prefix + "_side.png")
	for candidate in buildings.values():
		(candidate as Node3D).visible = true


func _set_camera_and_capture(position: Vector3, target: Vector3,
		file_name: String) -> void:
	camera.look_at_from_position(position, target, Vector3.UP)
	await _wait_frames(4)
	await RenderingServer.frame_post_draw
	var output_dir := OS.get_environment("ONEGUN_ENTERABLE_BUILDINGS_OUTPUT")
	if output_dir.is_empty():
		output_dir = ProjectSettings.globalize_path(OUTPUT_DIR_DEFAULT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var path := output_dir.path_join(file_name)
	var error := get_viewport().get_texture().get_image().save_png(path)
	_check(error == OK, "could not save visual capture %s" % path)
	print("ENTERABLE_BUILDING_CAPTURE ", path)


func _check_ray_clear(building: Node3D, local_from: Vector3, local_to: Vector3,
		message: String) -> void:
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(
			building.to_global(local_from), building.to_global(local_to)))
	if not result.is_empty():
		var collider := result.get("collider") as Node
		_check(collider == null or collider != building.get_node("Structure"),
			"Building %s %s" % [building.name, message])


func _check_ray_hits_structure(building: Node3D, local_from: Vector3,
		local_to: Vector3, message: String) -> void:
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(
			building.to_global(local_from), building.to_global(local_to)))
	var collider := result.get("collider") as Node
	_check(collider != null and collider == building.get_node("Structure"),
		"Building %s %s" % [building.name, message])


func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
