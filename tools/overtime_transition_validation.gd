extends Node

var failures: Array[String] = []

func _ready() -> void:
	print("OVERTIME TRANSITION VALIDATION: setup")
	var chaos_mode := OS.get_environment("ONEGUN_TEST_CHAOS_OT") == "1"
	var fallback_mode := OS.get_environment(
		"ONEGUN_TEST_EMPTY_NAV_FALLBACK") == "1"
	GameConfig.split_screen_enabled = false
	GameConfig.bot_configs = [{"difficulty": "easy", "team_id": -1}]
	GameConfig.round_time_limit = 999.0
	GameConfig.chaos_overtime_enabled = chaos_mode
	GameConfig.overtime_fire_exposure_time = 5.0

	var arena = load("res://maps/test/CityMap.tscn").instantiate()
	add_child(arena)
	print("OVERTIME TRANSITION VALIDATION: arena loaded")
	var city_navigation := load(
		"res://navigation/CityMapNavigation.tres") as NavigationMesh
	_check(city_navigation != null and city_navigation.get_polygon_count() > 0,
		"CityMap navigation resource is not baked")
	if fallback_mode:
		var navigation_region := arena.find_child(
			"NavigationRegion3D", true, false) as NavigationRegion3D
		_check(navigation_region != null,
			"CityMap has no NavigationRegion3D for fallback validation")
		if navigation_region != null:
			navigation_region.navigation_mesh = NavigationMesh.new()
	var manager = arena.get_node_or_null("RoundManager")
	_check(manager != null, "CityMap did not provide a RoundManager")
	if manager == null:
		_finish(chaos_mode)
		return

	var deadline := Time.get_ticks_msec() + 12000
	while manager.round_state != "live" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	print("OVERTIME TRANSITION VALIDATION: round state %s" % manager.round_state)
	_check(manager.round_state == "live", "round never reached live state")

	var alive: Array = manager.players.filter(
		func(actor): return is_instance_valid(actor) and not actor.is_eliminated)
	_check(alive.size() >= 2, "overtime validation needs at least two survivors")
	var original_guns := get_tree().get_nodes_in_group("gun").filter(
		func(gun): return not bool(gun.get("is_overtime_gun")))
	_check(not original_guns.is_empty(), "CityMap did not provide the original gun")
	if alive.size() < 2 or original_guns.is_empty():
		_finish(chaos_mode)
		return

	var tested_actor = alive[0]
	_check(tested_actor.apply_powerup("sticky_hands", 30.0),
		"could not grant Sticky Hands before overtime")
	_check(tested_actor.apply_powerup("extra_life", 30.0),
		"could not grant Extra Life before overtime")
	_check(tested_actor.apply_powerup("speed_surge", 30.0),
		"could not grant Speed Surge before overtime")
	_check(tested_actor.apply_powerup("extra_dash", 30.0),
		"could not grant Extra Dash before overtime")
	var ground_items := get_tree().get_nodes_in_group("item").filter(
		func(item): return is_instance_valid(item) and not item.is_held and item.visible)
	_check(not ground_items.is_empty(), "CityMap provided no item to test overtime inventory")
	var held_item = ground_items[0] if not ground_items.is_empty() else null
	if held_item != null:
		_check(held_item._do_pickup(tested_actor),
			"could not place a ground item in the survivor's inventory")
	var melee_actor = alive[1]
	var ground_melee := get_tree().get_nodes_in_group("melee").filter(
		func(melee): return is_instance_valid(melee) and not melee.is_held and melee.visible)
	_check(not ground_melee.is_empty(), "CityMap provided no melee to test overtime carryover")
	var held_melee = ground_melee[0] if not ground_melee.is_empty() else null
	if held_melee != null:
		_check(held_melee._local_pickup(melee_actor),
			"could not place a melee weapon in a survivor's hands")

	var original_gun = original_guns[0]
	_check(original_gun._local_pickup(tested_actor), "could not place the original gun in a survivor's hand")
	GameConfig.round_time_limit = 0.01
	manager.round_elapsed = 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	print("OVERTIME TRANSITION VALIDATION: overtime entered=%s" % manager.overtime_active)

	_check(manager.overtime_active, "overtime did not start when the round timer expired")
	_check(manager._storm_wall != null
		and manager._storm_wall.name == "OvertimeFireField",
		"overtime did not create the floor-fire field")
	_check(manager._storm_wall != null
		and manager._storm_wall.get_node_or_null("Flames") == null,
		"overtime still creates a single-height floating flame strip")
	_check(manager._storm_wall != null
		and manager._storm_wall.get_node_or_null("BurningFloor") == null,
		"overtime still creates a flat fire plane that can float above the map")
	var sampled_fire = manager._storm_wall.get_node_or_null("NavigationFireFloor") \
		if manager._storm_wall != null else null
	var flame_particles = manager._storm_wall.get_node_or_null("SurfaceFlameParticles") \
		if manager._storm_wall != null else null
	_check(sampled_fire is MeshInstance3D and sampled_fire.mesh != null,
		"overtime fire did not build its navigation-surface floor covering")
	var expected_surface_source := "fallback" if fallback_mode else "navigation"
	_check(sampled_fire is MeshInstance3D and str(
		sampled_fire.get_meta("surface_source", "")) == expected_surface_source,
		"CityMap overtime fire used the wrong surface source (expected %s)"
		% expected_surface_source)
	_check(flame_particles is CPUParticles3D,
		"overtime fire did not build vertical surface particles")
	_check(not manager._storm_surface_samples.is_empty(),
		"overtime fire found no collidable map surfaces")
	_check(manager._overtime_outer_radius < 80.0,
		"CityMap overtime still uses the oversized legacy opening radius (%.2f units)"
		% manager._overtime_outer_radius)
	var playable_radius := float(manager._overtime_outer_radius)
	var start_radius := float(manager._overtime_start_radius)
	var expected_start_buffer := maxf(
		playable_radius * manager.OVERTIME_START_BUFFER_RATIO,
		manager.OVERTIME_START_BUFFER_MIN)
	_check(start_radius > playable_radius,
		"opening fire does not begin outside the playable edge")
	_check(is_equal_approx(start_radius - playable_radius, expected_start_buffer),
		"opening fire buffer is not the configured map-scaled distance")
	manager.overtime_elapsed = 0.0
	_check(is_equal_approx(manager._current_storm_radius(), start_radius),
		"opening approach does not begin at the outside radius")
	for spawn_marker in manager._arena_markers_in_group("spawn_point"):
		_check(not manager._is_position_in_fire(spawn_marker.global_position),
			"opening fire begins inside authored play-area spawn %s"
			% spawn_marker.name)
	manager.overtime_elapsed = 2.5
	_check(is_equal_approx(
		manager._current_storm_radius(),
		lerpf(start_radius, playable_radius, 0.5)),
		"opening approach is not moving immediately")
	manager.overtime_elapsed = 5.0
	_check(is_equal_approx(manager._current_storm_radius(), playable_radius),
		"fire does not reach the playable edge after five seconds")
	manager.overtime_elapsed = 5.1
	_check(manager._current_storm_radius() < playable_radius,
		"fire pauses after reaching the playable edge")
	_check(is_equal_approx(
		manager.OVERTIME_FULL_ENGULF_TIME, 120.0),
		"continuous fire does not engulf the map in two minutes")
	manager.overtime_elapsed = \
		manager.OVERTIME_OPENING_APPROACH_TIME + manager.OVERTIME_ZONE_DURATION * 0.5
	_check(is_equal_approx(manager._current_storm_radius(), playable_radius * 0.95),
		"continuous fire is not halfway through its first ten-percent closure")
	manager.overtime_elapsed = \
		manager.OVERTIME_OPENING_APPROACH_TIME + manager.OVERTIME_ZONE_DURATION
	_check(is_equal_approx(manager._current_storm_radius(), playable_radius * 0.90),
		"continuous fire does not reach ten percent inside the map on schedule")
	_check(is_equal_approx(manager._current_fire_exposure_limit(), 4.0),
		"zone two does not reduce fire exposure to four seconds")
	manager.overtime_elapsed = manager.OVERTIME_OPENING_APPROACH_TIME \
		+ manager.OVERTIME_ZONE_DURATION * 2.0
	_check(is_equal_approx(manager._current_storm_radius(), playable_radius * 0.80),
		"continuous fire does not reach twenty percent inside the map on schedule")
	_check(is_equal_approx(manager._current_fire_exposure_limit(), 3.0),
		"zone three does not cap fire exposure at three seconds")
	manager.overtime_elapsed = manager.OVERTIME_OPENING_APPROACH_TIME \
		+ manager.OVERTIME_ZONE_DURATION * manager.OVERTIME_MOVEMENT_PHASE_COUNT
	_check(is_zero_approx(manager._current_storm_radius()),
		"continuous fire does not fully engulf the play area")
	_check(manager._is_position_in_fire(manager._overtime_center),
		"the exact map center remains safe after full engulfment")
	manager.overtime_elapsed = 60.0
	manager._update_storm_visual()
	var expected_progress: float = \
		(60.0 - manager.OVERTIME_OPENING_APPROACH_TIME) \
		/ (manager.OVERTIME_ZONE_DURATION * manager.OVERTIME_MOVEMENT_PHASE_COUNT)
	_check(is_equal_approx(
		manager._current_storm_radius(), playable_radius * (1.0 - expected_progress)),
		"CityMap fire radius does not follow the continuous closure schedule")
	if sampled_fire is MeshInstance3D and sampled_fire.mesh != null:
		_check(sampled_fire.mesh.get_surface_count() > 0,
			"overtime fire has no visible navigation surface")
		_check(flame_particles is CPUParticles3D
			and not flame_particles.emission_points.is_empty(),
			"overtime fire particles have no active surface positions")
		var current_extents: Vector2 = manager._current_storm_extents()
		if flame_particles is CPUParticles3D:
			var visual_safe_extents := Vector2(
				maxf(current_extents.x - manager.OVERTIME_FIRE_VISUAL_LEAD, 0.0),
				maxf(current_extents.y - manager.OVERTIME_FIRE_VISUAL_LEAD, 0.0))
			for local_particle_point in flame_particles.emission_points:
				var particle_world: Vector3 = manager._storm_wall.to_global(
					local_particle_point)
				var particle_offset := Vector2(
					particle_world.x - manager._overtime_center.x,
					particle_world.z - manager._overtime_center.z)
				_check(manager._is_offset_in_fire(
					particle_offset, visual_safe_extents),
					"fire emitter contains a point inside the safe center")
		_check(is_equal_approx(
			manager._storm_fire_visual_radius, manager._current_storm_radius()),
			"sampled fire floor did not advance with the damage boundary")
		var safe_sample: Vector3 = manager._overtime_center + Vector3(
			maxf(current_extents.x - 1.0, 0.0), 0.0, 0.0)
		var fire_sample: Vector3 = manager._overtime_center + Vector3(
			current_extents.x + 0.75, 0.0, 0.0)
		_check(not manager._is_position_in_fire(safe_sample)
			and manager._fire_visual_alpha_at_world_position(safe_sample) < 0.05,
			"safe floor sample is rendered as fire")
		_check(manager._is_position_in_fire(fire_sample)
			and manager._fire_visual_alpha_at_world_position(fire_sample) > 0.65,
			"lethal floor sample is not visibly covered by fire")
		fire_sample.y += 75.0
		_check(manager._is_position_in_fire(fire_sample)
			and manager._fire_visual_alpha_at_world_position(fire_sample) > 0.65,
			"elevated fire damage no longer matches the projected floor mask")
	_check(not "." in manager.get_round_timer_text(),
		"round timer still exposes milliseconds during overtime")
	manager.overtime_elapsed = 240.0
	_check(is_equal_approx(manager._current_fire_exposure_limit(), 3.0),
		"late overtime fire exposure is not capped at three seconds")

	var overtime_guns := get_tree().get_nodes_in_group("gun").filter(
		func(gun): return bool(gun.get("is_overtime_gun")))
	for item in get_tree().get_nodes_in_group("item"):
		if item == held_item and not chaos_mode:
			continue
		_check(item.overtime_disabled and not item.visible,
			"overtime left a ground or Chaos inventory item available")
	for powerup in get_tree().get_nodes_in_group("powerup"):
		_check(powerup.overtime_disabled and not powerup.visible,
			"overtime left a ground powerup available")
	var overtime_supply: Array = []
	for melee in get_tree().get_nodes_in_group("melee"):
		if melee == held_melee:
			continue
		if bool(melee.get("overtime_marker_supply")):
			overtime_supply.append(melee)
			_check(not melee.overtime_disabled and melee.visible and not melee.is_held,
				"overtime melee supply is not available on the ground")
		else:
			_check(melee.overtime_disabled and not melee.visible,
				"overtime left a non-supply melee placement available")
	_check(overtime_supply.size() == 1,
		"overtime did not leave exactly one active melee supply marker")
	_check(held_melee == null or (held_melee.is_held
		and held_melee.player_ref == melee_actor
		and not held_melee.overtime_disabled),
		"overtime did not preserve a survivor's held melee weapon")
	if chaos_mode:
		_check(original_gun.overtime_disabled and not original_gun.visible,
			"Chaos OT did not retire the held original gun")
		_check(overtime_guns.size() == alive.size(),
			"Chaos OT did not grant one gun to every survivor")
		_check(held_melee == null or (held_melee.is_held
			and held_melee.player_ref == melee_actor and melee_actor.holding_gun),
			"Chaos OT did not preserve melee while arming its holder")
		_check(held_item == null or (held_item.overtime_disabled and not held_item.visible),
			"Chaos OT preserved a held inventory item")
		_check(not tested_actor.second_wind_ready
			and tested_actor.melee_disarm_shields == 0
			and tested_actor.speed_surge_timer <= 0.0
			and tested_actor.extra_dash_charge == 0,
			"Chaos OT did not clear every carried powerup")
	else:
		_check(original_gun.is_held and original_gun.player_ref == tested_actor,
			"standard overtime did not preserve the current one-gun carrier")
		_check(not original_gun.overtime_disabled,
			"standard overtime disabled the original gun")
		_check(overtime_guns.is_empty(),
			"standard overtime incorrectly granted extra guns")
		_check(held_item == null or (held_item.is_held
			and held_item.player_ref == tested_actor),
			"standard overtime did not preserve the held inventory item")
		_check(not tested_actor.second_wind_ready
			and tested_actor.melee_disarm_shields == 0,
			"standard overtime preserved Extra Life or Sticky Hands")
		_check(tested_actor.speed_surge_timer > 0.0
			and tested_actor.extra_dash_charge == 1,
			"standard overtime did not preserve allowed carried powerups")
	_finish(chaos_mode)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish(chaos_mode: bool) -> void:
	var label := "CHAOS" if chaos_mode else "STANDARD"
	if failures.is_empty():
		print("OVERTIME TRANSITION VALIDATION (%s): PASS" % label)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("OVERTIME TRANSITION VALIDATION (%s): %s" % [label, failure])
	get_tree().quit(1)
