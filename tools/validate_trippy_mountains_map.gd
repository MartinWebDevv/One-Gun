extends SceneTree

const MAP_PATH := "res://maps/test/TrippyMountainsMap.tscn"
const MAP_REGISTRY := preload("res://map_registry.gd")
const EXPECTED_MAP_SCALE := 2.3
const INNER_PLAY_AREA := Rect2(Vector2(21.00, -163.64), Vector2(94.42, 90.53))
const LOCAL_PLAY_AREA := Rect2(Vector2(47.7, -138.05), Vector2(41.05, 39.36))

const EXPECTED_GROUP_COUNTS := {
	"spawn_point": 10,
	"gun_spawn_point": 5,
	"melee_spawn_point": 6,
	"item_spawn_point": 5,
	"powerup_spawn_point": 2,
	"overtime_boundary_point": 4,
	"overtime_center_point": 1,
	"round_intro_camera_point": 1,
}


func _initialize() -> void:
	var failures: Array[String] = []
	var packed := load(MAP_PATH) as PackedScene
	if packed == null:
		push_error("TRIPPY_MAP_VALIDATION: playable scene did not load")
		quit(1)
		return
	var map := packed.instantiate() as Node3D
	if map == null:
		push_error("TRIPPY_MAP_VALIDATION: root is not Node3D")
		quit(1)
		return

	for required_path in [
		"Environment", "Environment/FlatGround/GroundCollision",
		"Environment/PlayArea",
		"Environment/PlayAreaAssetCollisions/AssetCollision",
		"NavigationRegion3D", "Gun", "player1",
		"player2", "CanvasLayer", "RoundManager", "SplitScreenLayer"]:
		if map.get_node_or_null(required_path) == null:
			failures.append("missing %s" % required_path)

	if not is_equal_approx(
			float(map.get_meta("trippy_map_scale", 0.0)), EXPECTED_MAP_SCALE):
		failures.append("map scale metadata is not %.2f" % EXPECTED_MAP_SCALE)
	var environment := map.get_node_or_null("Environment") as Node3D
	if environment != null \
			and not environment.scale.is_equal_approx(Vector3.ONE * EXPECTED_MAP_SCALE):
		failures.append("environment scale is %s instead of %.2fx" % [
			environment.scale, EXPECTED_MAP_SCALE])

	if environment != null:
		_validate_asset_collisions(environment, failures)

	var play_area := map.get_node_or_null("Environment/PlayArea")
	if play_area != null:
		var barrier_count := 0
		for child in play_area.get_children():
			if child is CollisionShape3D and child.shape != null:
				barrier_count += 1
		if barrier_count != 4:
			failures.append("PlayArea has %d collision barriers instead of 4" % barrier_count)

	var nav_region := map.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if nav_region == null or nav_region.navigation_mesh == null:
		failures.append("navigation mesh is missing")
	elif nav_region.navigation_mesh.get_polygon_count() <= 0:
		failures.append("navigation mesh has no polygons")

	for group_name in EXPECTED_GROUP_COUNTS:
		var nodes: Array[Node] = []
		_collect_group_nodes(map, group_name, nodes)
		var expected_count: int = EXPECTED_GROUP_COUNTS[group_name]
		if nodes.size() != expected_count:
			failures.append("%s count is %d instead of %d" % [
				group_name, nodes.size(), expected_count])
		for node in nodes:
			if node is Node3D and group_name != "round_intro_camera_point":
				var point := Vector2(node.position.x, node.position.z)
				if not INNER_PLAY_AREA.has_point(point):
					failures.append("%s is outside PlayArea: %s" % [node.name, point])

	_validate_camera_contracts(map, failures)

	var guns: Array[Node] = []
	_collect_named_nodes(map, "Gun", guns)
	if guns.size() != 1:
		failures.append("map has %d nodes named Gun instead of exactly one" % guns.size())

	if not failures.is_empty():
		for failure in failures:
			push_error("TRIPPY_MAP_VALIDATION: %s" % failure)
		map.free()
		quit(1)
		return

	print("TRIPPY_MAP_VALIDATION_OK nav_polygons=%d markers=%d barriers=4" % [
		nav_region.navigation_mesh.get_polygon_count(),
		_total_expected_markers()])
	map.free()
	quit(0)

func _validate_camera_contracts(
		map: Node3D, failures: Array[String]) -> void:
	var intro_nodes: Array[Node] = []
	_collect_group_nodes(map, "round_intro_camera_point", intro_nodes)
	if intro_nodes.size() != 1 or not (intro_nodes[0] is Node3D):
		return
	var intro := intro_nodes[0] as Node3D
	var intro_point := Vector2(intro.position.x, intro.position.z)
	if not INNER_PLAY_AREA.has_point(intro_point):
		failures.append("intro camera begins outside PlayArea: %s" % intro_point)
	var intro_angle := float(intro.get_meta(
		"intro_orbit_angle_radians", PI))
	if not is_equal_approx(intro_angle, deg_to_rad(40.0)):
		failures.append("intro camera sweep is %.1f degrees instead of 40" % [
			rad_to_deg(intro_angle)])

	var player_spawns: Array[Node] = []
	_collect_group_nodes(map, "spawn_point", player_spawns)
	for spawn in player_spawns:
		if not (spawn is Node3D):
			continue
		var target := (spawn as Node3D).position + Vector3.UP * 1.1
		var start_offset := intro.position - target
		for sample_index in 9:
			var sample_angle := intro_angle * float(sample_index) / 8.0
			var camera_position := target \
				+ Basis(Vector3.UP, sample_angle) * start_offset
			var point := Vector2(camera_position.x, camera_position.z)
			if not INNER_PLAY_AREA.has_point(point):
				failures.append(
					"%s intro sweep leaves PlayArea at %s" % [spawn.name, point])
				break

	var map_index := MAP_REGISTRY.find_index_by_path(MAP_PATH)
	if map_index < 0:
		failures.append("map registry entry is missing")
		return
	var map_data: Dictionary = MAP_REGISTRY.get_map(map_index)
	var thumbnail_path := str(map_data.get("thumbnail_path", ""))
	if thumbnail_path == "" or not FileAccess.file_exists(thumbnail_path):
		failures.append("registered map thumbnail is missing")
	var preview_center: Vector3 = map_data.get(
		"preview_center", Vector3.ZERO)
	var preview_distance := float(map_data.get(
		"preview_camera_distance", INF))
	var preview_angle := float(map_data.get("preview_angle", 0.0))
	var preview_half_arc := float(map_data.get(
		"preview_orbit_half_arc", 0.0))
	if preview_half_arc <= 0.0 or preview_half_arc > 0.35:
		failures.append("preview orbit is not restricted to a narrow interior arc")
	for angle in [
			preview_angle - preview_half_arc,
			preview_angle,
			preview_angle + preview_half_arc,
	]:
		var camera_point := Vector2(
			preview_center.x + cos(angle) * preview_distance,
			preview_center.z + sin(angle) * preview_distance)
		if not INNER_PLAY_AREA.has_point(camera_point):
			failures.append(
				"preview camera arc leaves PlayArea at %s" % camera_point)

func _validate_asset_collisions(
		environment: Node3D,
		failures: Array[String]) -> void:
	var body := environment.get_node_or_null(
		"PlayAreaAssetCollisions") as StaticBody3D
	var collision := environment.get_node_or_null(
		"PlayAreaAssetCollisions/AssetCollision") as CollisionShape3D
	if body == null or collision == null:
		failures.append("merged PlayArea asset collision is missing")
		return
	var shape := collision.shape as ConcavePolygonShape3D
	if shape == null:
		failures.append("asset collision is not a ConcavePolygonShape3D")
		return
	if not shape.backface_collision:
		failures.append("asset collision does not block mesh backfaces")

	var expected_paths := PackedStringArray()
	var flat_ground := environment.get_node_or_null("FlatGround")
	_collect_expected_collision_meshes(
		environment, environment, flat_ground, expected_paths)
	var recorded_paths: PackedStringArray = body.get_meta(
		"source_mesh_paths", PackedStringArray())
	if recorded_paths.size() != expected_paths.size():
		failures.append("asset collision covers %d meshes instead of %d" % [
			recorded_paths.size(), expected_paths.size()])
	for mesh_path in expected_paths:
		if not recorded_paths.has(mesh_path):
			failures.append("asset collision omitted %s" % mesh_path)
	for mesh_path in recorded_paths:
		if not expected_paths.has(mesh_path):
			failures.append("asset collision recorded unexpected mesh %s" % mesh_path)
		if environment.get_node_or_null(NodePath(mesh_path)) == null:
			failures.append("asset collision source path is invalid: %s" % mesh_path)

	var actual_triangles := shape.get_faces().size() / 3
	var recorded_triangles := int(body.get_meta("triangle_count", 0))
	if actual_triangles <= 0 or actual_triangles != recorded_triangles:
		failures.append("asset collision triangle metadata is invalid (%d/%d)" % [
			actual_triangles, recorded_triangles])
	if int(body.get_meta("source_mesh_count", 0)) != recorded_paths.size():
		failures.append("asset collision source-mesh metadata is invalid")


func _collect_expected_collision_meshes(
		node: Node,
		environment: Node3D,
		flat_ground: Node,
		result: PackedStringArray) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var belongs_to_ground := flat_ground != null \
			and (mesh_instance == flat_ground \
			or flat_ground.is_ancestor_of(mesh_instance))
		if not belongs_to_ground \
				and mesh_instance.mesh != null \
				and _is_effectively_visible(mesh_instance, environment):
			var to_environment := _transform_to_ancestor(mesh_instance, environment)
			var local_bounds := _transformed_aabb(
				mesh_instance.get_aabb(), to_environment)
			var footprint := Rect2(
				Vector2(local_bounds.position.x, local_bounds.position.z),
				Vector2(local_bounds.size.x, local_bounds.size.z))
			if local_bounds.end.y >= -0.05 \
					and LOCAL_PLAY_AREA.intersects(footprint, true) \
					and mesh_instance.mesh.get_faces().size() >= 3:
				result.append(str(environment.get_path_to(mesh_instance)))
	for child in node.get_children():
		_collect_expected_collision_meshes(
			child, environment, flat_ground, result)


func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _transformed_aabb(box: AABB, to_space: Transform3D) -> AABB:
	var transformed := AABB(to_space * box.position, Vector3.ZERO)
	var box_end := box.end
	for endpoint_index in 8:
		var point := Vector3(
			box_end.x if (endpoint_index & 1) != 0 else box.position.x,
			box_end.y if (endpoint_index & 2) != 0 else box.position.y,
			box_end.z if (endpoint_index & 4) != 0 else box.position.z)
		transformed = transformed.expand(to_space * point)
	return transformed


func _is_effectively_visible(node: Node3D, stop_at: Node3D) -> bool:
	var current: Node = node
	while current != null:
		if current is Node3D and not (current as Node3D).visible:
			return false
		if current == stop_at:
			return true
		current = current.get_parent()
	return false

func _collect_group_nodes(node: Node, group_name: String, result: Array[Node]) -> void:
	if node.is_in_group(group_name):
		result.append(node)
	for child in node.get_children():
		_collect_group_nodes(child, group_name, result)


func _collect_named_nodes(node: Node, node_name: String, result: Array[Node]) -> void:
	if node.name == node_name:
		result.append(node)
	for child in node.get_children():
		_collect_named_nodes(child, node_name, result)


func _total_expected_markers() -> int:
	var total := 0
	for count in EXPECTED_GROUP_COUNTS.values():
		total += int(count)
	return total
