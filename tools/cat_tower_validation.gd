extends Node

var failures: Array[String] = []

func _ready() -> void:
	GameConfig.split_screen_enabled = false
	GameConfig.bot_configs = [{"difficulty": "easy", "team_id": -1}]
	GameConfig.round_time_limit = 999.0

	var map = load("res://maps/test/catTower.tscn").instantiate()
	add_child(map)
	var floor = map.get_node_or_null("Game Area")
	_check(floor is Node3D, "Game Area playable branch is missing")
	if floor == null:
		_finish()
		return
	_check(floor.scale.x >= 6.0 and floor.scale.is_equal_approx(Vector3.ONE * floor.scale.x),
		"Game Area was not enlarged uniformly for the tiny-player scale")

	var room_floor = map.get_node_or_null("House Floor/CSGCombiner3D")
	_check(room_floor != null and not bool(room_floor.get("use_collision")),
		"decorative room floor still lets players leave the tower arena")
	var cat_spectators := floor.get_node_or_null("BIG KITTYS") as Node3D
	_check(cat_spectators != null and cat_spectators.get_child_count() == 7,
		"Cat Tower does not have all seven giant cat spectators")

	var navigation_region := floor.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	_check(navigation_region != null, "Game Area has no NavigationRegion3D")
	if navigation_region != null:
		_check(navigation_region.navigation_mesh != null
			and navigation_region.navigation_mesh.get_polygon_count() > 0,
			"Cat Tower NavigationMesh is not baked")

	await get_tree().physics_frame
	await get_tree().physics_frame
	var spawn_markers := get_tree().get_nodes_in_group("spawn_point").filter(
		func(marker): return floor.is_ancestor_of(marker))
	_check(spawn_markers.size() == 10, "Cat Tower does not have ten Game Area player spawns")
	for marker in spawn_markers:
		_check(_marker_has_game_floor_below(marker, floor),
			"%s is not positioned over playable Game Area collision" % marker.name)
	if navigation_region != null and navigation_region.navigation_mesh != null:
		var navigation_map := navigation_region.get_navigation_map()
		for frame in 10:
			await get_tree().physics_frame
		var navigation_deadline := Time.get_ticks_msec() + 5000
		while NavigationServer3D.map_get_iteration_id(navigation_map) == 0 \
				and Time.get_ticks_msec() < navigation_deadline:
			await get_tree().physics_frame
		_check(NavigationServer3D.map_get_iteration_id(navigation_map) > 0,
			"Cat Tower navigation map did not synchronize")
		for marker in spawn_markers:
			var nearest_nav_point := NavigationServer3D.map_get_closest_point(
				navigation_map, marker.global_position)
			_check(nearest_nav_point.distance_to(marker.global_position) < 2.0,
				"%s is not reachable by the baked navigation map (spawn=%s nav=%s distance=%.2f)"
				% [marker.name, marker.global_position, nearest_nav_point,
					nearest_nav_point.distance_to(marker.global_position)])
		if spawn_markers.size() >= 2:
			var navigation_path := NavigationServer3D.map_get_path(
				navigation_map,
				spawn_markers[0].global_position,
				spawn_markers[1].global_position,
				true)
			_check(navigation_path.size() >= 2,
				"bots cannot find a path between Cat Tower player spawns")

	var gun_markers := get_tree().get_nodes_in_group("gun_spawn_point").filter(
		func(marker): return floor.is_ancestor_of(marker))
	var item_markers := get_tree().get_nodes_in_group("item_spawn_point").filter(
		func(marker): return floor.is_ancestor_of(marker))
	var powerup_markers := get_tree().get_nodes_in_group("powerup_spawn_point").filter(
		func(marker): return floor.is_ancestor_of(marker))
	_check(gun_markers.size() == 1, "Cat Tower needs exactly one Game Area gun marker")
	_check(item_markers.size() >= 4, "Cat Tower needs at least four Game Area item markers")
	_check(powerup_markers.size() >= 4, "Cat Tower needs at least four Game Area powerup markers")
	for marker in gun_markers + item_markers + powerup_markers:
		_check(_marker_has_game_floor_below(marker, floor),
			"%s is not positioned over playable Game Area collision" % marker.name)
	if navigation_region != null and not spawn_markers.is_empty():
		var navigation_map := navigation_region.get_navigation_map()
		for marker in gun_markers + item_markers + powerup_markers:
			var nearest_nav_point := NavigationServer3D.map_get_closest_point(
				navigation_map, marker.global_position)
			_check(nearest_nav_point.distance_to(marker.global_position) < 2.0,
				"%s is not covered by the Cat Tower navigation map" % marker.name)
			var navigation_path := NavigationServer3D.map_get_path(
				navigation_map,
				spawn_markers[0].global_position,
				marker.global_position,
				true)
			_check(navigation_path.size() >= 2,
				"bots cannot path from a player spawn to %s" % marker.name)

	_check(get_tree().get_nodes_in_group("gun").size() == 1,
		"Cat Tower does not contain exactly one gun")
	_check(get_tree().get_nodes_in_group("melee").size() == 1,
		"Cat Tower does not contain exactly one melee weapon")
	_check(map.get_node_or_null("VoidKillZone") != null
		or floor.get_node_or_null("VoidKillZone") != null,
		"Cat Tower has no fall-elimination volume")

	var manager = map.get_node_or_null("RoundManager")
	_check(manager != null, "Cat Tower has no RoundManager")
	var deadline := Time.get_ticks_msec() + 15000
	while manager != null and manager.round_state != "live" \
			and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(manager != null and manager.round_state == "live",
		"Cat Tower round did not reach live gameplay")
	if manager != null:
		for actor in manager.players:
			if not is_instance_valid(actor):
				continue
			var nearest := INF
			for marker in spawn_markers:
				nearest = minf(nearest, actor.global_position.distance_to(marker.global_position))
			_check(nearest < 1.0, "%s was not assigned to a Cat Tower spawn" % actor.name)
		var bots: Array = manager.players.filter(func(actor): return is_instance_valid(actor) and "is_bot" in actor and actor.is_bot and not actor.is_eliminated)
		if not bots.is_empty() and not gun_markers.is_empty():
			var bot = bots[0]
			var bot_start: Vector3 = bot.global_position
			bot.movement_target_position = gun_markers[0].global_position
			bot.reaction_timer = 0.0
			await get_tree().create_timer(1.5).timeout
			_check(bot.global_position.distance_to(bot_start) > 0.25,
				"Cat Tower bot did not move on the baked navigation map")

	var canvas = map.get_node_or_null("CanvasLayer")
	_check(canvas != null and canvas.get_node_or_null("MatchHUD") != null
		and canvas.get_node_or_null("PlayerUI1/InventorySlots") != null,
		"Cat Tower local combat HUD was not built")
	_check(map.get_node_or_null("SplitScreenLayer/ViewportRow/SubViewportContainer2") != null,
		"Cat Tower split-screen viewport scaffold is missing")

	var map_index := MapRegistry.find_index_by_path("res://maps/test/catTower.tscn")
	_check(map_index >= 0 and MapRegistry.is_scene_available(map_index),
		"Cat Tower is not available through the map registry")
	_check(map_index >= 0 and MapRegistry.load_thumbnail(map_index) != null,
		"Cat Tower carousel thumbnail is missing or cannot be loaded")
	_finish()

func _marker_has_game_floor_below(marker: Marker3D, floor: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		marker.global_position + Vector3.UP * 4.0,
		marker.global_position + Vector3.DOWN * 12.0,
		1)
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider = hit.get("collider")
	return collider == floor or (collider is Node and floor.is_ancestor_of(collider))

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("CAT TOWER VALIDATION: PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("CAT TOWER VALIDATION: " + failure)
	get_tree().quit(1)
