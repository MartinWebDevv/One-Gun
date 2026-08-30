extends SceneTree

## Deterministically proposes open, evenly distributed Trippy Mountains marker
## positions from the map's live physics and baked ground navigation.

const MAP_PATH := "res://maps/test/TrippyMountainsMap.tscn"
const OUTPUT_PATH := "res://tools/trippy_mountains_spawn_plan.json"
const ARENA_CENTER := Vector3(68.235, 0.0, -118.369)
const MAP_SCALE := 2.3
const INNER_MIN := Vector2(21.00, -163.64)
const INNER_SIZE := Vector2(94.42, 90.53)
const GRID_STEP := 1.5
const EDGE_MARGIN := 4.0
const REQUIRED_CLEARANCE := 2.5
const PLAYER_COUNT := 10
const PICKUP_SLOT_COUNT := 18


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(MAP_PATH) as PackedScene
	if packed == null:
		push_error("TRIPPY_SPAWN_PLAN: map did not load")
		quit(1)
		return
	var map_scene := packed.instantiate() as Node3D
	var environment := map_scene.get_node_or_null("Environment") as Node3D
	var nav_region := map_scene.get_node_or_null(
		"NavigationRegion3D") as NavigationRegion3D
	if environment == null or nav_region == null:
		push_error("TRIPPY_SPAWN_PLAN: environment/navigation is missing")
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
	var nav_mesh := nav_region.navigation_mesh

	var asset_body := environment.get_node_or_null(
		"PlayAreaAssetCollisions") as StaticBody3D
	var boundary_body := environment.get_node_or_null("PlayArea") as StaticBody3D
	if asset_body == null or boundary_body == null:
		push_error("TRIPPY_SPAWN_PLAN: collision bodies are missing")
		_cleanup(environment, nav_region)
		quit(1)
		return
	var candidates := _generate_candidates(
		environment, nav_mesh, asset_body, boundary_body)
	var players := _select_player_spawns(candidates)
	var pickup_slots := _select_pickup_slots(candidates, players)
	if players.size() != PLAYER_COUNT or pickup_slots.size() != PICKUP_SLOT_COUNT:
		push_error("TRIPPY_SPAWN_PLAN: insufficient candidates players=%d pickups=%d" % [
			players.size(), pickup_slots.size()])
		_cleanup(environment, nav_region)
		quit(1)
		return

	var plan := {
		"map_scale": MAP_SCALE,
		"candidate_count": candidates.size(),
		"player_world": _positions_to_json(players),
		"pickup_slots_world": _positions_to_json(pickup_slots),
		"player_authored": _authored_positions_to_json(players),
		"pickup_slots_authored": _authored_positions_to_json(pickup_slots),
		"player_min_separation": _minimum_separation(players),
		"pickup_min_separation": _minimum_separation(pickup_slots),
		"cross_min_separation": _cross_minimum_separation(players, pickup_slots),
	}
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("TRIPPY_SPAWN_PLAN: could not write %s" % OUTPUT_PATH)
		_cleanup(environment, nav_region)
		quit(1)
		return
	file.store_string(JSON.stringify(plan, "\t"))
	file.close()
	print("TRIPPY_SPAWN_PLAN_OK candidates=%d player_min=%.2f pickup_min=%.2f" % [
		candidates.size(), plan["player_min_separation"],
		plan["pickup_min_separation"]])
	_cleanup(environment, nav_region)
	quit(0)


func _generate_candidates(
		environment: Node3D,
		nav_mesh: NavigationMesh,
		asset_body: StaticBody3D,
		boundary_body: StaticBody3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var grid_count := 0
	var nav_count := 0
	var clearance_count := 0
	var space := environment.get_world_3d().direct_space_state
	var clearance_shape := SphereShape3D.new()
	clearance_shape.radius = REQUIRED_CLEARANCE
	var minimum := INNER_MIN + Vector2.ONE * EDGE_MARGIN
	var maximum := INNER_MIN + INNER_SIZE - Vector2.ONE * EDGE_MARGIN
	var x_count := int(floor((maximum.x - minimum.x) / GRID_STEP)) + 1
	var z_count := int(floor((maximum.y - minimum.y) / GRID_STEP)) + 1
	for x_index in x_count:
		for z_index in z_count:
			grid_count += 1
			var position := Vector3(
				minimum.x + float(x_index) * GRID_STEP,
				1.5,
				minimum.y + float(z_index) * GRID_STEP)
			if not _is_on_ground_navigation(
				nav_mesh, Vector2(position.x, position.z)):
				continue
			nav_count += 1
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = clearance_shape
			query.transform = Transform3D(Basis.IDENTITY, position)
			query.collision_mask = asset_body.collision_layer | boundary_body.collision_layer
			query.collide_with_bodies = true
			var hits := space.intersect_shape(query, 64)
			if _hits_either_body(hits, asset_body, boundary_body):
				continue
			clearance_count += 1
			var normalized := Vector2(
				(position.x - ARENA_CENTER.x) / (INNER_SIZE.x * 0.5),
				(position.z - ARENA_CENTER.z) / (INNER_SIZE.y * 0.5))
			result.append({
				"position": position,
				"normalized_radius": normalized.length(),
				"angle": atan2(normalized.y, normalized.x),
			})
	print("TRIPPY_SPAWN_CANDIDATES grid=%d nav=%d clearance=%d final=%d" % [
		grid_count, nav_count, clearance_count, result.size()])
	return result


func _is_on_ground_navigation(
		nav_mesh: NavigationMesh, point: Vector2) -> bool:
	var vertices := nav_mesh.vertices
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
				Vector2(second.x, second.z), Vector2(third.x, third.z)):
				return true
	return false


func _point_in_triangle_2d(
		point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var first := (b - a).cross(point - a)
	var second := (c - b).cross(point - b)
	var third := (a - c).cross(point - c)
	var has_negative := first < -0.001 or second < -0.001 or third < -0.001
	var has_positive := first > 0.001 or second > 0.001 or third > 0.001
	return not (has_negative and has_positive)


func _select_player_spawns(candidates: Array[Dictionary]) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for sector in PLAYER_COUNT:
		var target_angle := -PI + (float(sector) + 0.5) * TAU / PLAYER_COUNT
		var best_position := Vector3.ZERO
		var best_score := INF
		for candidate in candidates:
			var radial := float(candidate["normalized_radius"])
			if radial < 0.68 or radial > 0.88:
				continue
			var angle_delta := absf(wrapf(
				float(candidate["angle"]) - target_angle, -PI, PI))
			if angle_delta > TAU / PLAYER_COUNT * 0.48:
				continue
			var position: Vector3 = candidate["position"]
			if _nearest_distance(position, result) < 10.0:
				continue
			var score := angle_delta * 30.0 + absf(radial - 0.79) * 20.0
			if score < best_score:
				best_score = score
				best_position = position
		if best_score < INF:
			result.append(best_position)
	return result


func _select_pickup_slots(
		candidates: Array[Dictionary],
		player_spawns: Array[Vector3]) -> Array[Vector3]:
	var eligible: Array[Dictionary] = []
	for candidate in candidates:
		if float(candidate["normalized_radius"]) > 0.72:
			continue
		var position: Vector3 = candidate["position"]
		if _nearest_distance(position, player_spawns) < 6.0:
			continue
		eligible.append(candidate)
	var result: Array[Vector3] = []
	var center_candidate := _nearest_candidate(eligible, ARENA_CENTER)
	if not center_candidate.is_empty():
		result.append(center_candidate["position"] as Vector3)
	while result.size() < PICKUP_SLOT_COUNT:
		var best_position := Vector3.ZERO
		var best_score := -INF
		for candidate in eligible:
			var position: Vector3 = candidate["position"]
			if result.has(position):
				continue
			var distance_to_existing := _nearest_distance(position, result)
			var distance_to_players := _nearest_distance(position, player_spawns)
			var score := minf(distance_to_existing, distance_to_players)
			if score > best_score:
				best_score = score
				best_position = position
		if best_score <= 0.0:
			break
		result.append(best_position)
	return result


func _hits_either_body(
		hits: Array[Dictionary],
		first: CollisionObject3D,
		second: CollisionObject3D) -> bool:
	for hit in hits:
		var collider = hit.get("collider")
		if collider == first or collider == second:
			return true
	return false


func _nearest_candidate(
		candidates: Array[Dictionary], target: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for candidate in candidates:
		var position: Vector3 = candidate["position"]
		var distance := _horizontal_distance(position, target)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


func _nearest_distance(position: Vector3, others: Array[Vector3]) -> float:
	if others.is_empty():
		return INF
	var result := INF
	for other in others:
		result = minf(result, _horizontal_distance(position, other))
	return result


func _horizontal_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x - second.x, first.z - second.z).length()


func _minimum_separation(positions: Array[Vector3]) -> float:
	var result := INF
	for first in positions.size():
		for second in range(first + 1, positions.size()):
			result = minf(result, _horizontal_distance(
				positions[first], positions[second]))
	return result


func _cross_minimum_separation(
		first_set: Array[Vector3], second_set: Array[Vector3]) -> float:
	var result := INF
	for first in first_set:
		for second in second_set:
			result = minf(result, _horizontal_distance(first, second))
	return result


func _positions_to_json(positions: Array[Vector3]) -> Array[Array]:
	var result: Array[Array] = []
	for position in positions:
		result.append([
			snappedf(position.x, 0.01), 1.5,
			snappedf(position.z, 0.01)])
	return result


func _authored_positions_to_json(positions: Array[Vector3]) -> Array[Array]:
	var result: Array[Array] = []
	for position in positions:
		result.append([
			snappedf(ARENA_CENTER.x + (position.x - ARENA_CENTER.x) / MAP_SCALE, 0.001),
			1.5,
			snappedf(ARENA_CENTER.z + (position.z - ARENA_CENTER.z) / MAP_SCALE, 0.001)])
	return result


func _cleanup(environment: Node3D, nav_region: NavigationRegion3D) -> void:
	root.remove_child(nav_region)
	root.remove_child(environment)
	nav_region.free()
	environment.free()
