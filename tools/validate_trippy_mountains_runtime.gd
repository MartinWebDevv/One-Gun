extends SceneTree

## Runtime physics/navigation validation for the generated Trippy Mountains map.
## Loads only the environment and navigation region into the test world so
## gameplay scripts never start while collision clearance is queried.

const MAP_PATH := "res://maps/test/TrippyMountainsMap.tscn"
const PLAYER_CAPSULE_RADIUS := 0.495
const PLAYER_CAPSULE_HEIGHT := 2.3266993
const PICKUP_CLEARANCE_RADIUS := 0.20
const OPEN_SPACE_CLEARANCE_RADIUS := 2.45
const MIN_PLAYER_SEPARATION := 18.0
const MIN_PICKUP_SEPARATION := 9.0
const MIN_CROSS_SEPARATION := 9.0

const CLEARANCE_GROUPS := [
	"spawn_point", "gun_spawn_point", "melee_spawn_point",
	"item_spawn_point", "powerup_spawn_point",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var packed := load(MAP_PATH) as PackedScene
	if packed == null:
		push_error("TRIPPY_RUNTIME_VALIDATION: map did not load")
		quit(1)
		return
	var map_scene := packed.instantiate() as Node3D
	if map_scene == null:
		push_error("TRIPPY_RUNTIME_VALIDATION: map root is not Node3D")
		quit(1)
		return

	var marker_data: Array[Dictionary] = []
	for group_name in CLEARANCE_GROUPS:
		var markers: Array[Node] = []
		_collect_group_nodes(map_scene, group_name, markers)
		for marker in markers:
			if marker is Node3D:
				marker_data.append({
					"name": str(marker.name),
					"group": group_name,
					"position": (marker as Node3D).position,
				})

	var environment := map_scene.get_node_or_null("Environment") as Node3D
	var nav_region := map_scene.get_node_or_null(
		"NavigationRegion3D") as NavigationRegion3D
	if environment == null or nav_region == null:
		push_error("TRIPPY_RUNTIME_VALIDATION: environment/navigation is missing")
		map_scene.free()
		quit(1)
		return
	map_scene.remove_child(environment)
	map_scene.remove_child(nav_region)
	map_scene.free()
	root.add_child(environment)
	root.add_child(nav_region)
	await process_frame
	await physics_frame

	var asset_body := environment.get_node_or_null(
		"PlayAreaAssetCollisions") as StaticBody3D
	var boundary_body := environment.get_node_or_null(
		"PlayArea") as StaticBody3D
	if asset_body == null or boundary_body == null:
		failures.append("asset or PlayArea collision body is missing from the physics world")
	else:
		_validate_physics_registration(environment, asset_body, failures)
		_validate_marker_clearance(
			environment, asset_body, boundary_body, marker_data, failures)
	_validate_marker_spacing(marker_data, failures)
	_validate_marker_navigation(
		nav_region.navigation_mesh, marker_data, failures)
	root.remove_child(nav_region)
	root.remove_child(environment)
	nav_region.free()
	environment.free()

	if not failures.is_empty():
		for failure in failures:
			push_error("TRIPPY_RUNTIME_VALIDATION: %s" % failure)
		quit(1)
		return

	print("TRIPPY_RUNTIME_VALIDATION_OK markers=%d" % marker_data.size())
	quit(0)


func _validate_physics_registration(
		environment: Node3D,
		asset_body: StaticBody3D,
		failures: Array[String]) -> void:
	var collision := asset_body.get_node_or_null(
		"AssetCollision") as CollisionShape3D
	var shape := collision.shape as ConcavePolygonShape3D if collision != null else null
	if shape == null:
		failures.append("asset collision shape is missing at runtime")
		return
	var faces := shape.get_faces()
	var probe_center := Vector3.ZERO
	var found_triangle := false
	for index in range(0, faces.size(), 3):
		var a: Vector3 = faces[index]
		var b: Vector3 = faces[index + 1]
		var c: Vector3 = faces[index + 2]
		if (b - a).cross(c - a).length_squared() > 0.000001:
			probe_center = asset_body.global_transform * ((a + b + c) / 3.0)
			found_triangle = true
			break
	if not found_triangle:
		failures.append("asset collision has no non-degenerate triangles")
		return

	var probe := SphereShape3D.new()
	probe.radius = 0.08
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(Basis.IDENTITY, probe_center)
	query.collision_mask = asset_body.collision_layer
	query.collide_with_bodies = true
	var hits := environment.get_world_3d().direct_space_state.intersect_shape(
		query, 32)
	if not _hits_body(hits, asset_body):
		failures.append("merged asset collision is not registered with physics")


func _validate_marker_clearance(
		environment: Node3D,
		asset_body: StaticBody3D,
		boundary_body: StaticBody3D,
		marker_data: Array[Dictionary],
		failures: Array[String]) -> void:
	var player_shape := CapsuleShape3D.new()
	player_shape.radius = PLAYER_CAPSULE_RADIUS
	player_shape.height = PLAYER_CAPSULE_HEIGHT
	var pickup_shape := SphereShape3D.new()
	pickup_shape.radius = PICKUP_CLEARANCE_RADIUS
	var open_space_shape := SphereShape3D.new()
	open_space_shape.radius = OPEN_SPACE_CLEARANCE_RADIUS
	var space := environment.get_world_3d().direct_space_state
	for marker in marker_data:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = player_shape \
			if str(marker["group"]) == "spawn_point" else pickup_shape
		query.transform = Transform3D(
			Basis.IDENTITY, marker["position"] as Vector3)
		query.collision_mask = \
			asset_body.collision_layer | boundary_body.collision_layer
		query.collide_with_bodies = true
		var hits := space.intersect_shape(query, 64)
		if _hits_either_body(hits, asset_body, boundary_body):
			failures.append("%s overlaps a solid PlayArea asset or barrier" % marker["name"])

		var open_position: Vector3 = marker["position"]
		open_position.y = 1.5
		var open_query := PhysicsShapeQueryParameters3D.new()
		open_query.shape = open_space_shape
		open_query.transform = Transform3D(Basis.IDENTITY, open_position)
		open_query.collision_mask = \
			asset_body.collision_layer | boundary_body.collision_layer
		open_query.collide_with_bodies = true
		var open_hits := space.intersect_shape(open_query, 64)
		if _hits_either_body(open_hits, asset_body, boundary_body):
			failures.append(
				"%s does not have %.2fm of open obstacle clearance" % [
					marker["name"], OPEN_SPACE_CLEARANCE_RADIUS])


func _validate_marker_spacing(
		marker_data: Array[Dictionary],
		failures: Array[String]) -> void:
	var players: Array[Vector3] = []
	var pickups: Array[Vector3] = []
	for marker in marker_data:
		var position: Vector3 = marker["position"]
		if str(marker["group"]) == "spawn_point":
			players.append(position)
		else:
			pickups.append(position)
	var player_min := _minimum_horizontal_separation(players)
	var pickup_min := _minimum_horizontal_separation(pickups)
	var cross_min := _cross_horizontal_separation(players, pickups)
	print("TRIPPY_RUNTIME_SPACING player_min=%.2f pickup_min=%.2f cross_min=%.2f" % [
		player_min, pickup_min, cross_min])
	if player_min < MIN_PLAYER_SEPARATION:
		failures.append("player spawn minimum separation is only %.2fm" % player_min)
	if pickup_min < MIN_PICKUP_SEPARATION:
		failures.append("pickup minimum separation is only %.2fm" % pickup_min)
	if cross_min < MIN_CROSS_SEPARATION:
		failures.append("player-to-pickup minimum separation is only %.2fm" % cross_min)


func _validate_marker_navigation(
		nav_mesh: NavigationMesh,
		marker_data: Array[Dictionary],
		failures: Array[String]) -> void:
	if nav_mesh == null or nav_mesh.get_polygon_count() == 0:
		failures.append("baked navigation mesh is empty")
		return
	var components := _build_polygon_components(nav_mesh)
	var anchor_component := -1
	for marker in marker_data:
		var position: Vector3 = marker["position"]
		var polygon_index := _find_ground_polygon(nav_mesh, position)
		if polygon_index < 0:
			failures.append("%s is not on ground navigation" % marker["name"])
			continue
		var component := components[polygon_index]
		if anchor_component < 0 and str(marker["group"]) == "spawn_point":
			anchor_component = component
		elif anchor_component >= 0 and component != anchor_component:
			failures.append(
				"%s is disconnected from the primary playable ground" % marker["name"])
	if anchor_component < 0:
		failures.append("no navigable player spawn was available as an anchor")


func _find_ground_polygon(
		nav_mesh: NavigationMesh, position: Vector3) -> int:
	var vertices := nav_mesh.vertices
	var point := Vector2(position.x, position.z)
	for polygon_index in nav_mesh.get_polygon_count():
		var polygon := nav_mesh.get_polygon(polygon_index)
		if polygon.size() < 3:
			continue
		var first := vertices[polygon[0]]
		for corner in range(1, polygon.size() - 1):
			var second := vertices[polygon[corner]]
			var third := vertices[polygon[corner + 1]]
			if maxf(first.y, maxf(second.y, third.y)) > 1.0:
				continue
			if _point_in_triangle_2d(
					point, Vector2(first.x, first.z),
					Vector2(second.x, second.z),
					Vector2(third.x, third.z)):
				return polygon_index
	return -1


func _point_in_triangle_2d(
		point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var first := (b - a).cross(point - a)
	var second := (c - b).cross(point - b)
	var third := (a - c).cross(point - c)
	var has_negative := first < -0.001 or second < -0.001 or third < -0.001
	var has_positive := first > 0.001 or second > 0.001 or third > 0.001
	return not (has_negative and has_positive)


func _build_polygon_components(nav_mesh: NavigationMesh) -> Array[int]:
	var polygon_count := nav_mesh.get_polygon_count()
	var parents: Array[int] = []
	parents.resize(polygon_count)
	for polygon_index in polygon_count:
		parents[polygon_index] = polygon_index
	var edge_owner := {}
	for polygon_index in polygon_count:
		var polygon := nav_mesh.get_polygon(polygon_index)
		for corner in polygon.size():
			var first := int(polygon[corner])
			var second := int(polygon[(corner + 1) % polygon.size()])
			var lower := mini(first, second)
			var upper := maxi(first, second)
			var edge_key := "%d:%d" % [lower, upper]
			if edge_owner.has(edge_key):
				_union_components(
					parents, polygon_index, int(edge_owner[edge_key]))
			else:
				edge_owner[edge_key] = polygon_index
	for polygon_index in polygon_count:
		parents[polygon_index] = _component_root(parents, polygon_index)
	return parents


func _union_components(
		parents: Array[int], first: int, second: int) -> void:
	var first_root := _component_root(parents, first)
	var second_root := _component_root(parents, second)
	if first_root != second_root:
		parents[second_root] = first_root


func _component_root(parents: Array[int], index: int) -> int:
	var root_index := index
	while parents[root_index] != root_index:
		root_index = parents[root_index]
	while parents[index] != index:
		var next_index := parents[index]
		parents[index] = root_index
		index = next_index
	return root_index


func _minimum_horizontal_separation(positions: Array[Vector3]) -> float:
	var result := INF
	for first in positions.size():
		for second in range(first + 1, positions.size()):
			result = minf(
				result, _horizontal_distance(positions[first], positions[second]))
	return result


func _cross_horizontal_separation(
		first_set: Array[Vector3], second_set: Array[Vector3]) -> float:
	var result := INF
	for first in first_set:
		for second in second_set:
			result = minf(result, _horizontal_distance(first, second))
	return result


func _horizontal_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x - second.x, first.z - second.z).length()


func _hits_either_body(
		hits: Array[Dictionary],
		first: CollisionObject3D,
		second: CollisionObject3D) -> bool:
	for hit in hits:
		var collider = hit.get("collider")
		if collider == first or collider == second:
			return true
	return false

func _hits_body(hits: Array[Dictionary], body: CollisionObject3D) -> bool:
	for hit in hits:
		if hit.get("collider") == body:
			return true
	return false


func _collect_group_nodes(node: Node, group_name: String, result: Array[Node]) -> void:
	if node.is_in_group(group_name):
		result.append(node)
	for child in node.get_children():
		_collect_group_nodes(child, group_name, result)
