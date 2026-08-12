extends Node

const CITY_SCENE := preload("res://maps/test/CityMap.tscn")
const HydrantWaterPushScript := preload("res://hydrant_water_push.gd")
const OUTPUT_DIR_DEFAULT := "res://.godot"

const FACADE_SCENES := {
	"7": "res://models/cityAssets/BuildingD_FacadeTall.tscn",
	"8": "res://models/cityAssets/BuildingB_FacadeMidA.tscn",
	"9": "res://models/cityAssets/BuildingC_FacadeShort.tscn",
	"10": "res://models/cityAssets/BuildingA_FacadeMidB.tscn",
}
const GREEN_SCENES := [
	"res://models/cityAssets/Tree2_Medium.tscn",
	"res://models/cityAssets/Tree3_Medium.tscn",
	"res://models/cityAssets/Tree4_Large.tscn",
	"res://models/cityAssets/Tree1_Sapling.tscn",
	"res://models/cityAssets/Bush_New.tscn",
	"res://models/cityAssets/BushWithBerries_New.tscn",
	"res://models/cityAssets/Bush_New.tscn",
	"res://models/cityAssets/BushWithBerries_New.tscn",
	"res://models/cityAssets/Bush_New.tscn",
]

var failures: Array[String] = []
var city: Node3D = null
var camera: Camera3D = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	city = CITY_SCENE.instantiate() as Node3D
	var round_manager := city.get_node_or_null("RoundManager")
	if round_manager != null:
		round_manager.set_script(null)
	city.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(city)
	await _wait_frames(3)
	_disable_existing_cameras()
	_build_review_lighting()
	_validate_references()
	_validate_physics_layout()
	_validate_hydrant_push()
	await _validate_hydrant_jump_activation()
	_validate_grounding()
	_validate_hoop_rim()
	await _capture_views()

	if failures.is_empty():
		print("CITY_ENVIRONMENT_MAP_VALIDATION: PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("CITY_ENVIRONMENT_MAP_VALIDATION: %s" % failure)
	get_tree().quit(1)


func _validate_references() -> void:
	var perimeter := city.get_node("PerimeterFacades")
	var facade_count := 0
	var skyline_count := 0
	for child in perimeter.get_children():
		if child.name.begins_with("Fac") and not "Col" in child.name:
			facade_count += 1
			_check(child.scene_file_path in FACADE_SCENES.values(),
				"%s uses unexpected facade %s" % [child.name, child.scene_file_path])
		elif child.name.begins_with("Sky"):
			skyline_count += 1
			_check("Background_Skyline" in child.scene_file_path,
				"%s still uses an old skyline" % child.name)
	_check(facade_count == 22, "expected 22 replacement facades, found %d" % facade_count)
	_check(skyline_count == 8, "expected 8 replacement skyline buildings, found %d" % skyline_count)

	var park := city.get_node("Park")
	for index in GREEN_SCENES.size():
		var green := park.get_node_or_null("Green%d" % index)
		_check(green != null, "missing Green%d" % index)
		if green != null:
			_check(green.scene_file_path == GREEN_SCENES[index],
				"Green%d uses %s" % [index, green.scene_file_path])
	_check(park.get_node("Bench1").scene_file_path == \
		"res://models/cityAssets/Bench_New.tscn", "Bench1 was not replaced")
	_check(park.get_node("Bench2").scene_file_path == \
		"res://models/cityAssets/ParkBench_New.tscn", "Bench2 was not replaced")
	_check(park.get_node("Bench3PicnicTable").scene_file_path == \
		"res://models/cityAssets/Bench2_PicnicTable.tscn", "picnic table is missing")
	_check(park.get_node("Hoop").scene_file_path == \
		"res://models/cityAssets/BasketballHoop.glb", "fixed hoop is not assigned")

	var furniture := city.get_node("StreetFurniture")
	for hydrant_name in ["Hydrant10", "Hydrant11"]:
		_check(furniture.get_node(hydrant_name).scene_file_path == \
			"res://models/cityAssets/FireHydrant_New.tscn",
			"%s was not replaced" % hydrant_name)
	_check(furniture.get_node("Mailbox").scene_file_path == \
		"res://models/cityAssets/Mailbox_New.tscn", "mailbox was not normalized")


func _validate_physics_layout() -> void:
	var perimeter := city.get_node("PerimeterFacades")
	var facade_colliders := 0
	for child in perimeter.get_children():
		if child is StaticBody3D and child.name.begins_with("Fac") and "Col" in child.name:
			facade_colliders += 1
	_check(facade_colliders == 22,
		"facade physics changed: expected 22 bodies, found %d" % facade_colliders)

	var park := city.get_node("Park")
	var fence_visuals := 0
	var fence_colliders := 0
	var tree_colliders := 0
	for child in park.get_children():
		if child.name.begins_with("Fence") and not "Col" in child.name:
			fence_visuals += 1
			_check(child.scene_file_path.ends_with("FencePiece_New.tscn") or \
				child.scene_file_path.ends_with("FenceEnd_New.tscn"),
				"%s still uses the old fence" % child.name)
		elif child is StaticBody3D and child.name.begins_with("Fence"):
			fence_colliders += 1
		elif child is StaticBody3D and child.name.begins_with("TreeCol"):
			tree_colliders += 1
	_check(fence_visuals == 10 and fence_colliders == 10,
		"fence visual/physics count changed: %d/%d" % [fence_visuals, fence_colliders])
	_check(tree_colliders == 3,
		"tree physics changed: expected 3 trunks, found %d" % tree_colliders)
	_check(park.has_node("HoopCol"), "hoop collider was removed")

	var furniture := city.get_node("StreetFurniture")
	var hydrant_colliders := 0
	for child in furniture.get_children():
		if child is StaticBody3D and child.name.begins_with("HydrantCol"):
			hydrant_colliders += 1
	_check(hydrant_colliders == 2, "hydrant physics changed")
	_check(furniture.has_node("MailboxCol"), "mailbox collider was removed")


func _validate_hydrant_push() -> void:
	var jet := city.get_node_or_null("Effects/HydrantJet") as GPUParticles3D
	var push_area := city.get_node_or_null("Effects/HydrantWaterPush") as Area3D
	_check(jet != null, "hydrant water particle jet is missing")
	_check(push_area != null, "hydrant water push area is missing")
	if jet == null or push_area == null:
		return
	var collision := push_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var launch_target := push_area.get_node_or_null("LaunchDirection") as Marker3D
	_check(collision != null and collision.shape is BoxShape3D,
		"hydrant water push volume has no box shape")
	_check(launch_target != null, "hydrant launch direction marker is missing")
	_check(push_area.get_collision_mask_value(2),
		"hydrant water push no longer detects player bodies")
	_check(is_equal_approx(float(push_area.get("push_speed")), 15.0),
		"hydrant water push speed is not the approved 15m/s")
	var push_direction: Vector3 = push_area.call("get_push_direction")
	var expected_direction := Vector3.ZERO
	if launch_target != null:
		expected_direction = HydrantWaterPushScript.direction_between_points(
			push_area.global_position, launch_target.global_position)
	_check(push_direction.is_equal_approx(expected_direction),
		"hydrant gameplay push does not match its authored launch direction")
	_check(push_direction.y > 0.7 \
		and Vector2(push_direction.x, push_direction.z).length() > 0.3,
		"hydrant water push lost its upward or directional component")
	var horizontal := Vector3(push_direction.x, 0.0, push_direction.z).normalized()
	_check(horizontal.dot(Vector3.FORWARD) > 0.99,
		"hydrant launch no longer travels straight away from the nozzle")
	if collision != null and collision.shape is BoxShape3D:
		_check((collision.shape as BoxShape3D).size.is_equal_approx(
			Vector3(0.6968994, 2.6, 1.6160644)),
			"the authored hydrant collision box size was overwritten")
		_check(collision.position.is_equal_approx(Vector3(0.009094238, 0.0, -0.65031767)),
			"the authored hydrant collision box position was overwritten")


func _validate_hydrant_jump_activation() -> void:
	var push_area := city.get_node("Effects/HydrantWaterPush") as Area3D
	var player := city.get_node("player1") as CharacterBody3D
	var collision := push_area.get_node("CollisionShape3D") as CollisionShape3D
	var direction: Vector3 = push_area.call("get_push_direction")
	# Reproduce the requested case: stand immediately in front of the nozzle,
	# provide only ordinary upward jump velocity, then let the Area resolve it.
	push_area.process_mode = Node.PROCESS_MODE_ALWAYS
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.set_physics_process(false)
	player.global_position = collision.to_global(Vector3(0.0, 0.95, 0.0))
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(bool(push_area.call("is_body_in_activation_zone", player)),
		"a player standing directly in front of the hydrant is outside the launch zone")
	player.velocity = Vector3.UP * 7.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var expected_velocity := direction * float(push_area.get("push_speed"))
	_check(player.velocity.is_equal_approx(expected_velocity),
		"a stationary player's jump did not receive the hydrant's full water arc")
	var horizontal_velocity := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_check(horizontal_velocity.normalized().dot(Vector3.FORWARD) > 0.99,
		"the hydrant pushed the player sideways instead of forward")
	push_area.process_mode = Node.PROCESS_MODE_DISABLED
	player.visible = false


func _validate_grounding() -> void:
	var park := city.get_node("Park")
	for name in ["Green0", "Green1", "Green2", "Green3", "Green4", "Green5",
			"Green6", "Green7", "Green8", "Bench1", "Bench2", "Bench3PicnicTable", "Hoop"]:
		var bounds := _mesh_bounds(park.get_node(name))
		_check(bounds.size != Vector3.ZERO, "%s has no renderable mesh" % name)
		_check(absf(bounds.position.y) <= 0.08,
			"%s is floating or buried: %s" % [name, bounds])
	var furniture := city.get_node("StreetFurniture")
	for name in ["Hydrant10", "Hydrant11", "Mailbox"]:
		var bounds := _mesh_bounds(furniture.get_node(name))
		_check(absf(bounds.position.y) <= 0.08,
			"%s is floating or buried: %s" % [name, bounds])


func _validate_hoop_rim() -> void:
	var hoop := city.get_node("Park/Hoop")
	var rim_bounds := AABB()
	var board_bounds := AABB()
	var found_rim := false
	var found_board := false
	for child in hoop.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		for surface_index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(surface_index)
			var surface_bounds := _surface_bounds(mesh_instance.mesh, surface_index)
			if material != null and material.resource_name == "C_hyd":
				rim_bounds = surface_bounds
				found_rim = true
			elif material != null and material.resource_name == "C_trim":
				board_bounds = surface_bounds
				found_board = true
	_check(found_rim and found_board, "could not identify hoop rim/backboard surfaces")
	if found_rim and found_board:
		_check(rim_bounds.position.z < board_bounds.position.z - 0.3,
			"rim remains on the pole side: rim=%s board=%s" % [rim_bounds, board_bounds])
		_check(absf(rim_bounds.end.z - board_bounds.end.z) < 0.03,
			"rim no longer meets the backboard: rim=%s board=%s" % [rim_bounds, board_bounds])


func _capture_views() -> void:
	camera = Camera3D.new()
	camera.name = "CityEnvironmentValidationCamera"
	camera.fov = 56.0
	camera.current = true
	add_child(camera)
	await _set_camera_and_capture(
		Vector3(-1.0, 12.0, -2.0), Vector3(-14.0, 2.3, 10.5),
		"city_environment_park.png")
	await _set_camera_and_capture(
		Vector3(-11.2, 3.5, 10.5), Vector3(-14.5, 2.4, 15.2),
		"city_environment_hoop.png")
	await _set_camera_and_capture(
		Vector3(0.0, 7.5, 5.0), Vector3(0.0, 6.0, -24.0),
		"city_environment_north_facades.png")
	await _set_camera_and_capture(
		Vector3(0.0, 52.0, 44.0), Vector3(0.0, 0.0, 0.0),
		"city_environment_overview.png")
	await _capture_hydrant_trigger()
	await _capture_isolated_hoop()


func _capture_hydrant_trigger() -> void:
	var push_area := city.get_node("Effects/HydrantWaterPush") as Area3D
	var collision := push_area.get_node("CollisionShape3D") as CollisionShape3D
	var debug_volume := MeshInstance3D.new()
	var debug_mesh := BoxMesh.new()
	debug_mesh.size = (collision.shape as BoxShape3D).size
	var debug_material := StandardMaterial3D.new()
	debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_material.albedo_color = Color(0.05, 0.9, 1.0, 0.18)
	debug_material.no_depth_test = true
	debug_mesh.material = debug_material
	debug_volume.mesh = debug_mesh
	debug_volume.global_transform = collision.global_transform
	add_child(debug_volume)
	var direction: Vector3 = push_area.call("get_push_direction")
	var horizontal := Vector3(direction.x, 0.0, direction.z).normalized()
	var side := Vector3.UP.cross(horizontal).normalized()
	var origin := push_area.global_position
	await _set_camera_and_capture(
		origin - horizontal * 4.0 + side * 4.0 + Vector3.UP * 2.8,
		origin + horizontal * 2.1 + Vector3.UP * 1.25,
		"city_environment_hydrant_trigger.png")
	debug_volume.queue_free()


func _capture_isolated_hoop() -> void:
	city.visible = false
	var hoop_scene := load(
		"res://models/cityAssets/BasketballHoop.glb") as PackedScene
	var hoop := hoop_scene.instantiate() as Node3D
	add_child(hoop)
	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(8.0, 0.08, 8.0)
	floor.mesh = floor_mesh
	floor.position.y = -0.04
	add_child(floor)
	await _set_camera_and_capture(
		Vector3(3.4, 3.2, -5.5), Vector3(0.0, 2.25, -0.7),
		"city_environment_hoop_isolated.png")
	hoop.queue_free()
	floor.queue_free()
	city.visible = true


func _set_camera_and_capture(position: Vector3, target: Vector3, file_name: String) -> void:
	camera.look_at_from_position(position, target, Vector3.UP)
	await _wait_frames(4)
	await RenderingServer.frame_post_draw
	var output_dir := OS.get_environment("ONEGUN_CITY_ENV_OUTPUT")
	if output_dir.is_empty():
		output_dir = ProjectSettings.globalize_path(OUTPUT_DIR_DEFAULT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var path := output_dir.path_join(file_name)
	var error := get_viewport().get_texture().get_image().save_png(path)
	_check(error == OK, "could not save %s" % path)
	print("CITY_ENVIRONMENT_CAPTURE ", path)


func _disable_existing_cameras() -> void:
	for child in city.find_children("*", "Camera3D", true, false):
		(child as Camera3D).current = false
	var canvas_layer := city.get_node_or_null("CanvasLayer") as CanvasLayer
	if canvas_layer != null:
		canvas_layer.visible = false
	var split_layer := city.get_node_or_null("SplitScreenLayer") as CanvasLayer
	if split_layer != null:
		split_layer.visible = false


func _build_review_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	light.light_energy = 1.3
	light.shadow_enabled = true
	add_child(light)


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


func _surface_bounds(mesh: Mesh, surface_index: int) -> AABB:
	var arrays := mesh.surface_get_arrays(surface_index)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return AABB()
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices:
		bounds = bounds.expand(vertex)
	return bounds


func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
