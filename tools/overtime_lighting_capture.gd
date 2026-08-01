extends Node

const OUTPUT_DIR := "res://.godot"


func _ready() -> void:
	var map_index := int(OS.get_environment("ONEGUN_LIGHTING_MAP_INDEX"))
	if map_index < 0 or map_index >= MapRegistry.map_count():
		push_error("Set ONEGUN_LIGHTING_MAP_INDEX to a valid MapRegistry index")
		get_tree().quit(1)
		return

	GameConfig.split_screen_enabled = false
	GameConfig.bot_configs = [{"difficulty": "easy", "team_id": -1}]
	GameConfig.round_time_limit = 999.0
	GameConfig.chaos_overtime_enabled = false

	var map_data := MapRegistry.get_map(map_index)
	var arena := load(str(map_data["scene_path"])).instantiate() as Node3D
	add_child(arena)
	var manager = arena.get_node_or_null("RoundManager")
	if manager == null:
		push_error("OT lighting capture could not find RoundManager for map %d" % map_index)
		get_tree().quit(1)
		return

	var deadline := Time.get_ticks_msec() + 20000
	while manager.round_state != "live" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if manager.round_state != "live":
		push_error("OT lighting capture never reached live play for map %d" % map_index)
		get_tree().quit(1)
		return

	var canvas := arena.get_node_or_null("CanvasLayer") as CanvasLayer
	if canvas != null:
		canvas.visible = false
	var split_layer := arena.get_node_or_null("SplitScreenLayer") as CanvasLayer
	if split_layer != null:
		split_layer.visible = false

	var framing := _map_framing(arena, map_data)
	var center: Vector3 = framing["center"]
	var radius: float = framing["radius"]
	var angle := float(map_data.get("preview_angle", 0.0))
	var height_ratio := float(map_data.get("preview_height_ratio", 0.6))
	var target_height_ratio := float(map_data.get("preview_target_height_ratio", 0.1))
	var camera := Camera3D.new()
	camera.fov = 60.0
	add_child(camera)
	camera.global_position = center + Vector3(
		cos(angle) * radius * 1.2,
		radius * height_ratio,
		sin(angle) * radius * 1.2)
	camera.look_at(center + Vector3.UP * radius * target_height_ratio)
	camera.current = true
	var ground_view := OS.get_environment("ONEGUN_LIGHTING_GROUND_VIEW") == "1"

	await get_tree().create_timer(0.5).timeout
	var normal_path := OUTPUT_DIR.path_join(
		"ot_lighting_%d_normal.png" % map_index)
	var normal_result := _save_viewport(normal_path)

	GameConfig.round_time_limit = 0.01
	manager.round_elapsed = 1.0
	deadline = Time.get_ticks_msec() + 5000
	while not manager.overtime_active and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not manager.overtime_active:
		push_error("OT lighting capture could not enter overtime for map %d" % map_index)
		get_tree().quit(1)
		return
	manager.set_process(false)
	var capture_result := normal_result
	var overtime_paths: Array[String] = []
	for capture_time in _overtime_capture_times():
		manager.overtime_elapsed = capture_time
		manager._update_storm_visual()
		for failure in _surface_alignment_failures(manager):
			push_error("OT SURFACE ALIGNMENT map=%d time=%.1f: %s" % [
				map_index, capture_time, failure])
			capture_result = ERR_INVALID_DATA
		if ground_view:
			_position_ground_view(manager, camera)
		await get_tree().create_timer(0.35).timeout
		var time_label := "%03d" % roundi(capture_time)
		var overtime_path := OUTPUT_DIR.path_join(
			"ot_lighting_%d_overtime_%s%s.png" % [
				map_index, time_label, "_ground" if ground_view else ""])
		var frame_result := _save_viewport(overtime_path)
		if capture_result == OK:
			capture_result = frame_result
		overtime_paths.append(overtime_path)
		print("OT LIGHTING FRAME map=%d time=%.1f playable=%s start=%s current=%s path=%s" % [
			map_index,
			capture_time,
			str(manager._overtime_outer_extents),
			str(manager._overtime_start_extents),
			str(manager._current_storm_extents()),
			overtime_path,
		])

	print("OT LIGHTING CAPTURE map=%d normal=%s overtime=%s" % [
		map_index, normal_path, ",".join(overtime_paths)])
	get_tree().quit(0 if capture_result == OK else 1)


func _overtime_capture_times() -> Array[float]:
	var raw_times := OS.get_environment("ONEGUN_LIGHTING_OT_TIMES").strip_edges()
	if raw_times == "":
		return [120.0]
	var result: Array[float] = []
	for raw_time in raw_times.split(","):
		var value := raw_time.strip_edges()
		if value.is_valid_float():
			result.append(maxf(float(value), 0.0))
	return result if not result.is_empty() else [120.0]


func _position_ground_view(manager, camera: Camera3D) -> void:
	var markers: Array = manager._arena_markers_in_group("spawn_point")
	if markers.is_empty():
		return
	var marker = markers[0]
	var furthest := -1.0
	for candidate in markers:
		var distance: float = Vector2(
			candidate.global_position.x - manager._overtime_center.x,
			candidate.global_position.z - manager._overtime_center.z).length_squared()
		if distance > furthest:
			furthest = distance
			marker = candidate
	var target_position: Vector3 = marker.global_position
	var actors: Array = manager.players.filter(
		func(actor): return is_instance_valid(actor) and not actor.is_eliminated)
	if not actors.is_empty():
		actors[0].global_position = target_position
	var inward: Vector3 = manager._overtime_center - target_position
	inward.y = 0.0
	inward = inward.normalized() if not inward.is_zero_approx() else Vector3.FORWARD
	camera.global_position = target_position + inward * 4.5 + Vector3.UP * 2.4
	camera.look_at(target_position + Vector3.UP * 0.9)


func _surface_alignment_failures(manager) -> Array[String]:
	var result: Array[String] = []
	if manager._storm_floor_mesh == null or manager._storm_floor_mesh.mesh == null:
		result.append("missing navigation-surface floor fire")
	elif manager._storm_floor_mesh.mesh.get_surface_count() <= 0:
		result.append("navigation-surface floor fire has no triangles")
	if manager._storm_flame_particles == null:
		result.append("missing vertical surface flame particles")
	elif manager._storm_flame_particles.emission_points.is_empty():
		result.append("surface flame particles have no emission points")
	else:
		var visual_safe_extents := Vector2(
			maxf(manager._current_storm_extents().x
				- manager.OVERTIME_FIRE_VISUAL_LEAD, 0.0),
			maxf(manager._current_storm_extents().y
				- manager.OVERTIME_FIRE_VISUAL_LEAD, 0.0))
		for local_particle_point in manager._storm_flame_particles.emission_points:
			var particle_world: Vector3 = manager._storm_wall.to_global(
				local_particle_point)
			var particle_offset := Vector2(
				particle_world.x - manager._overtime_center.x,
				particle_world.z - manager._overtime_center.z)
			if not manager._is_offset_in_fire(
					particle_offset, visual_safe_extents):
				result.append("surface particle spawned inside the safe area")
				break
	if manager._storm_surface_samples.is_empty():
		result.append("baked navigation surface provided no fire samples")
	if manager._storm_wall.get_node_or_null("BurningFloor") != null:
		result.append("single-height fire plane returned")
	var boundary_markers: Array = \
		manager._arena_markers_in_group("overtime_boundary_point")
	if boundary_markers.is_empty():
		for group_name in [
			"spawn_point", "item_spawn_point", "powerup_spawn_point",
			"gun_spawn_point",
		]:
			for marker in manager._arena_markers_in_group(group_name):
				if not boundary_markers.has(marker):
					boundary_markers.append(marker)
	if not boundary_markers.is_empty() \
			and manager._arena_markers_in_group("overtime_center_point").is_empty():
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for marker in boundary_markers:
			minimum.x = minf(minimum.x, marker.global_position.x)
			minimum.y = minf(minimum.y, marker.global_position.z)
			maximum.x = maxf(maximum.x, marker.global_position.x)
			maximum.y = maxf(maximum.y, marker.global_position.z)
		var expected_center := (minimum + maximum) * 0.5
		if Vector2(
				manager._overtime_center.x,
				manager._overtime_center.z).distance_to(expected_center) > 0.05:
			result.append("fire is not centered evenly on the gameplay footprint")
	var safe_extents: Vector2 = manager._current_storm_extents()
	if safe_extents.x > 1.0 and safe_extents.y > 1.0:
		var safe_sample: Vector3 = manager._overtime_center
		var fire_sample: Vector3 = manager._overtime_center + Vector3(
			safe_extents.x + 0.75, 0.0, 0.0)
		if manager._is_position_in_fire(safe_sample) \
				or manager._fire_visual_alpha_at_world_position(safe_sample) > 0.05:
			result.append("safe center and projected mask disagree")
		if not manager._is_position_in_fire(fire_sample) \
				or manager._fire_visual_alpha_at_world_position(fire_sample) < 0.65:
			result.append("unsafe floor and projected mask disagree")
		fire_sample.y += 75.0
		if not manager._is_position_in_fire(fire_sample) \
				or manager._fire_visual_alpha_at_world_position(fire_sample) < 0.65:
			result.append("elevated damage and projected mask disagree")
	return result


func _map_framing(arena: Node3D, map_data: Dictionary) -> Dictionary:
	if map_data.has("preview_center") and map_data.has("preview_radius"):
		return {
			"center": map_data["preview_center"],
			"radius": float(map_data["preview_radius"]),
		}
	var ground := arena.get_node_or_null("Ground")
	var bounds := _mesh_aabb(ground if ground != null else arena)
	return {
		"center": bounds.position + bounds.size * 0.5,
		"radius": maxf(maxf(bounds.size.x, bounds.size.z) * 0.5, 8.0),
	}


func _mesh_aabb(node: Node) -> AABB:
	var combined: AABB
	var first := true
	for mesh_instance in _find_meshes(node):
		if mesh_instance.mesh == null:
			continue
		var world_bounds: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		combined = world_bounds if first else combined.merge(world_bounds)
		first = false
	return combined


func _find_meshes(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_meshes(child))
	return result


func _save_viewport(path: String) -> Error:
	var image := get_viewport().get_texture().get_image()
	var absolute_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	return image.save_png(absolute_path)
