extends Node

const CITY_MAP := "res://maps/test/CityMap.tscn"

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("NEW GAME MODES VALIDATION: " + message)


func _wait_for_manager(timeout_ms := 12000):
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var scene := get_tree().current_scene
		if scene != null:
			var manager = scene.get_node_or_null("RoundManager")
			if manager != null and manager.get("players").size() == 3:
				return manager
		await get_tree().process_frame
	return null


func _wait_for_child(parent: Node, child_name: String, timeout_ms := 3000):
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if not is_instance_valid(parent):
			return null
		var child := parent.get_node_or_null(child_name)
		if child != null:
			return child
		await get_tree().process_frame
	return null


func _human_from(actors: Array):
	for actor in actors:
		if not ("is_bot" in actor and actor.is_bot):
			return actor
	return null


func _actors_with_role(actors: Array, role: String) -> Array:
	return actors.filter(func(actor): return str(actor.get("one_of_us_role")) == role)


func _held_weapon_name(actor) -> String:
	var melee = actor.get("held_melee_weapon")
	if melee == null:
		return ""
	var data = melee.get("weapon_data")
	return str(data.get("weapon_name")) if data != null else ""


func _load_mode(mode: String):
	GameConfig.game_mode = mode
	var error := get_tree().change_scene_to_file(CITY_MAP)
	_check(error == OK, "Could not load the City map for %s" % mode)
	if error != OK:
		return null
	return await _wait_for_manager()


func _validate_one_of_us() -> void:
	GameConfig.local_one_of_us_volunteers = [true, false]
	var manager = await _load_mode(GameConfig.MODE_ONE_OF_US)
	_check(manager != null, "One of Us RoundManager did not initialize")
	if manager == null:
		return
	var actors: Array = manager.get("players")
	var human = _human_from(actors)
	_check(human != null, "One of Us local human was not found")
	if human == null:
		return
	_check(int(manager.get("one_of_us_first_actor_id")) == int(human.get("actor_id")),
		"a sole local volunteer was not selected as the first infected")
	var original_split_screen: bool = GameConfig.split_screen_enabled
	var original_is_player2: bool = bool(human.get("is_player2"))
	GameConfig.split_screen_enabled = true
	human.set("is_player2", false)
	var left_intro_rect: Rect2 = human.get_one_of_us_intro_display_rect()
	human.set("is_player2", true)
	var right_intro_rect: Rect2 = human.get_one_of_us_intro_display_rect()
	human.set("is_player2", original_is_player2)
	GameConfig.split_screen_enabled = original_split_screen
	var viewport_rect: Rect2 = human.get_viewport().get_visible_rect()
	_check(is_equal_approx(left_intro_rect.size.x, viewport_rect.size.x * 0.5)
		and is_equal_approx(left_intro_rect.position.x, viewport_rect.position.x),
		"Player 1 role cinematic was not bounded to the left split-screen view")
	_check(is_equal_approx(right_intro_rect.size.x, viewport_rect.size.x * 0.5)
		and is_equal_approx(right_intro_rect.position.x,
			viewport_rect.position.x + viewport_rect.size.x * 0.5),
		"Player 2 role cinematic was not bounded to the right split-screen view")


	var intro = await _wait_for_child(human, "OneOfUsIntro")
	_check(intro != null, "Role cinematic was not created for the local player")
	_check(not human.is_physics_processing(),
		"Movement was not locked during the role cinematic")
	_check(bool(human.get("_one_of_us_intro_input_locked")),
		"Camera/action input was not locked during the role cinematic")
	if intro != null:
		var target_actor = intro.get("_infected_actor")
		_check(target_actor != null \
			and int(target_actor.get("actor_id")) == int(manager.get("one_of_us_first_actor_id")),
			"Role cinematic did not hunt the selected first infected")
		_check(intro.get("_camera") != null,
			"Role cinematic did not create a temporary 3D camera")

		await get_tree().create_timer(5.55).timeout
		var label = intro.get("_text")
		var first_text := "YOU ARE THE FIRST." \
			if str(human.get("one_of_us_role")) == "them" \
			else "ONE OF THEM HAS TURNED."
		_check(label != null and label.text == first_text,
			"Role cinematic first message did not match the local role")
		await get_tree().create_timer(0.75).timeout
		var second_text := "MAKE THEM ONE OF US." \
			if str(human.get("one_of_us_role")) == "them" else "RUN."
		_check(label != null and label.text == second_text,
			"Role cinematic objective message did not match the local role")

	var them: Array = _actors_with_role(actors, "them")
	var us: Array = _actors_with_role(actors, "us")
	_check(them.size() == 1, "Exactly one first infected was not selected")
	_check(us.size() == 2, "The remaining players were not assigned to Us")
	if them.size() != 1 or us.size() != 2:
		return
	var first_them = them[0]
	_check(_held_weapon_name(first_them) == "Sword",
		"The first infected did not receive a sword")
	var them_melee = first_them.get("held_melee_weapon")
	_check(them_melee != null and int(them_melee.get("tier")) == 3,
		"The first infected sword was not Tier 3")
	_check(int(first_them.get("max_dash_charges")) == GameConfig.ONE_OF_US_THEM_DASH_CHARGES,
		"The first infected did not receive four base dashes")
	var role_visual = first_them.get_node_or_null("OneOfUsRoleVisual")
	_check(role_visual != null and role_visual.visible,
		"The first infected visual marker is missing")
	for survivor in us:
		_check(int(survivor.get("max_dash_charges")) == GameConfig.ONE_OF_US_US_DASH_CHARGES,
			"An Us player did not receive three base dashes")
		_check(bool(survivor.get("holding_gun")),
			"An Us player did not receive a personal gun")

	var live_deadline := Time.get_ticks_msec() + 5000
	while manager.get("round_state") != "live" and Time.get_ticks_msec() < live_deadline:
		await get_tree().process_frame
	_check(manager.get("round_state") == "live",
		"One of Us did not enter live play immediately after its cinematic")
	_check(human.is_physics_processing(),
		"Player control was not restored after the role cinematic")
	_check(not bool(human.get("_one_of_us_intro_input_locked")),
		"Camera/action input stayed locked after the role cinematic")
	_check(not bool(manager.get("overtime_active")),
		"One of Us incorrectly started overtime")
	var world := get_tree().current_scene.find_child(
		"WorldEnvironment", true, false) as WorldEnvironment
	_check(world != null and world.environment != null \
		and world.environment.adjustment_enabled \
		and world.environment.adjustment_brightness <= 0.741,
		"One of Us did not apply its mode-only dingy environment grade")
	for bot in actors.filter(func(actor): return "is_bot" in actor and actor.is_bot):
		bot.call("_update_target", 0.0)
		var bot_target = bot.get("target_player")
		_check(bot_target != null,
			"A One of Us bot did not acquire a role enemy")
		if bot_target != null:
			_check(str(bot.get("one_of_us_role")) != str(bot_target.get("one_of_us_role")),
				"A One of Us bot targeted its own role instead of the opposition")

	var target = us.filter(func(actor): return "is_bot" in actor and actor.is_bot)[0]
	var remaining_us = us.filter(func(actor): return actor != target)[0]
	manager._begin_local_one_of_us_conversion(target, first_them)
	_check(bool(target.get("is_eliminated")),
		"Converted player did not enter the temporary spectator state")
	_check(str(target.get("one_of_us_role")) == "them",
		"Converted player role did not change to Them")
	_check(int(remaining_us.get("extra_dash_charge")) == 1,
		"The final Us player did not receive the one-time bonus dash")
	_check(int(remaining_us.get("max_dash_charges")) + int(remaining_us.get("extra_dash_charge")) == 4,
		"The final Us player does not have four total dashes")
	await get_tree().create_timer(GameConfig.ONE_OF_US_CONVERSION_TIME + 0.25).timeout
	_check(not bool(target.get("is_eliminated")),
		"Converted player did not respawn after 1.5 seconds")
	_check(_held_weapon_name(target) == "Sword",
		"Converted player did not respawn with the Them sword")

	var us_was_eliminated := bool(remaining_us.get("is_eliminated"))
	var handled: bool = manager.try_resolve_local_one_of_us_gun_hit(
		remaining_us, first_them.get_display_name(), int(first_them.get("actor_id")))
	_check(handled and bool(remaining_us.get("is_eliminated")) == us_was_eliminated,
		"Gunfire incorrectly eliminated an Us player")
	manager.try_resolve_local_one_of_us_gun_hit(
		first_them, remaining_us.get_display_name(), int(remaining_us.get("actor_id")))
	_check(bool(first_them.get("is_eliminated")),
		"Shot Them player did not enter the temporary spectator state")
	await get_tree().create_timer(GameConfig.ONE_OF_US_THEM_RESPAWN_TIME + 0.25).timeout
	_check(not bool(first_them.get("is_eliminated")),
		"Shot Them player did not respawn after 2 seconds")
	_check(_held_weapon_name(first_them) == "Sword",
		"Respawned Them player did not recover the Tier 3 sword")
	human.activate_double_jump_shoes()
	_check(bool(human.get("double_jump_shoes_active")),
		"Double Jump Shoes did not arm a charge")
	_check(human.get("_double_jump_shoe_attachments").size() == 2,
		"Double Jump Shoes did not attach one visible shoe to each foot")
	for attachment in human.get("_double_jump_shoe_attachments"):
		var shoe_model = attachment.get_node_or_null("Shoe")
		var meshes: Array = shoe_model.find_children("*", "MeshInstance3D", true, false) \
			if shoe_model != null else []
		_check(not meshes.is_empty(), "A split spring-shoe attachment is missing its real mesh")
		_check(attachment.global_basis.get_scale().length() < 3.0,
			"A Spring Shoe inherited the oversized imported rig scale")
	human.velocity.y = 0.0
	human._perform_double_jump_shoes()
	_check(is_equal_approx(human.velocity.y, human.jump_velocity),
		"Double Jump Shoes did not apply one full normal jump of vertical velocity")
	_check(not bool(human.get("double_jump_shoes_active")),
		"Double Jump Shoes charge did not clear after the air jump")


func _validate_all_gun() -> void:
	var manager = await _load_mode(GameConfig.MODE_ALL_GUN)
	_check(manager != null, "All Gun RoundManager did not initialize")
	if manager == null:
		return
	_check("extra_life" not in GameConfig.enabled_powerup_types(),
		"All Gun still includes Extra Life in its powerup pool")

	var actors: Array = manager.get("players")
	var loadout_deadline := Time.get_ticks_msec() + 4000
	var all_gun_world := get_tree().current_scene.find_child(
		"WorldEnvironment", true, false) as WorldEnvironment
	_check(all_gun_world == null or all_gun_world.environment == null \
		or not all_gun_world.environment.adjustment_enabled \
		or all_gun_world.environment.adjustment_brightness > 0.74,
		"One of Us environment grade leaked into All Gun")
	while Time.get_ticks_msec() < loadout_deadline:
		var ready := actors.all(func(actor): return actor.get("holding_gun") == true \
			and int(actor.get("all_gun_hearts")) == GameConfig.ALL_GUN_MAX_HEARTS)
		if ready:
			break
		await get_tree().process_frame
	for actor in actors:
		_check(bool(actor.get("holding_gun")),
			"An All Gun player did not receive a personal gun")
		_check(int(actor.get("all_gun_hearts")) == GameConfig.ALL_GUN_MAX_HEARTS,
			"An All Gun player did not start with three hearts")
	await get_tree().process_frame
	var heart_labels := get_tree().current_scene.find_children(
		"*AllGunHearts", "Label", true, false)
	var rendered_three_hearts := heart_labels.any(func(label):
		return label.visible and label.text.count("♥") == 3)
	_check(rendered_three_hearts,
		"All Gun HUD did not render three heart pips above the dash display")
	var world_heart_labels := get_tree().current_scene.find_children(
		"*AllGunWorldHearts", "Label3D", true, false)
	var rendered_world_hearts := world_heart_labels.any(func(label):
		return label.visible and label.text.count("\u2665") == GameConfig.ALL_GUN_MAX_HEARTS)
	_check(rendered_world_hearts,
		"All Gun did not render three synchronized world-space hearts over actors")
	var ground_melee := get_tree().get_nodes_in_group("melee").filter(func(melee):
		return not bool(melee.get("personal_mode_melee")))
	_check(ground_melee.is_empty(), "All Gun spawned forbidden ground melee weapons")

	var target = actors.filter(func(actor): return "is_bot" in actor and actor.is_bot)[0]
	target.eliminate("Validation", "GUN", "weapon", 1)
	_check(not bool(target.get("is_eliminated")) and int(target.get("all_gun_hearts")) == 2,
		"First All Gun shot did not consume exactly one heart")
	target.eliminate("Validation", "GUN", "weapon", 1)
	_check(int(target.get("all_gun_hearts")) == 2,
		"All Gun post-hit protection did not block an immediate second hit")
	var live_deadline := Time.get_ticks_msec() + 8000
	while manager.get("round_state") != "live" and Time.get_ticks_msec() < live_deadline:
		await get_tree().process_frame
	_check(manager.get("round_state") == "live",
		"All Gun did not preserve the normal match intro/countdown path")
	var moving_bots := actors.filter(func(actor): return "is_bot" in actor and actor.is_bot)
	var bot_start_positions: Array = moving_bots.map(func(actor): return actor.global_position)
	await get_tree().create_timer(2.0).timeout
	var any_bot_moved := false
	for index in moving_bots.size():
		if moving_bots[index].global_position.distance_to(bot_start_positions[index]) > 0.35:
			any_bot_moved = true
	_check(any_bot_moved, "All Gun bots did not begin navigating toward combat targets")



func _validate_shared_item_packet() -> void:
	_check(GameConfig.SHARED_THROW_FORWARD_SPEED == 15.0,
		"Shared melee/item forward throw speed is not 15.0")
	_check(GameConfig.SHARED_THROW_UPWARD_SPEED == 5.0,
		"Shared melee/item upward throw speed is not 5.0")
	_check(GameConfig.ITEM_SCENES.has("double_jump_shoes"),
		"Double Jump Shoes are missing from the item spawn registry")
	var gum_scene := load("res://bubble_gum_trap.tscn") as PackedScene
	_check(gum_scene != null, "Bubble Gum Trap scene could not load")
	if gum_scene == null:
		return
	var gum = gum_scene.instantiate()
	add_child(gum)
	var collision := gum.get_node("CollisionShape3D") as CollisionShape3D
	var shape := collision.shape as CylinderShape3D
	_check(shape != null and is_equal_approx(shape.radius, 2.25),
		"Bubble Gum gameplay footprint is not 4.5m wide")
	var splat := gum.get_node_or_null("ChewedGumSplat")
	_check(splat != null and splat.get_child_count() == 7,
		"Chewed-gum presentation did not build its irregular seven-piece splat")
	gum.free()


func _validate_melee_throw_release() -> void:
	var manager = await _load_mode(GameConfig.MODE_ONE_GUN)
	_check(manager != null, "One Gun manager did not load for melee throw validation")
	if manager == null:
		return
	var actors: Array = manager.get("players")
	var human = _human_from(actors)
	var loose_melee: Array = []
	var melee_deadline := Time.get_ticks_msec() + 4000
	while loose_melee.is_empty() and Time.get_ticks_msec() < melee_deadline:
		await get_tree().process_frame
		loose_melee = get_tree().get_nodes_in_group("melee").filter(func(melee):
			return not bool(melee.get("is_held")) \
				and not bool(melee.get("is_in_flight")))
	_check(human != null and not loose_melee.is_empty(),
		"A human and loose melee weapon were not available for throw validation")
	if human == null or loose_melee.is_empty():
		return
	var weapon = loose_melee[0]
	_check(weapon._local_pickup(human), "Could not equip melee weapon for throw validation")
	var player_position: Vector3 = human.global_position
	weapon.throw()
	_check(bool(weapon.get("is_in_flight")), "Melee throw did not enter flight")
	var horizontal_release: Vector3 = weapon.global_position - player_position
	horizontal_release.y = 0.0
	_check(horizontal_release.length() >= 1.1,
		"Melee weapon released too close and can still catch on its thrower")
	_check(weapon.linear_velocity.length() >= GameConfig.SHARED_THROW_FORWARD_SPEED,
		"Melee weapon did not receive the shared throw strength")
	_check(weapon.get_collision_exceptions().has(human),
		"Melee thrower collision exception was not active at release")
	await get_tree().create_timer(0.42).timeout
	_check(not weapon.get_collision_exceptions().has(human),
		"Melee thrower collision exception did not clear after launch grace")

func _run() -> void:
	NetworkManager.disconnect_net()
	GameConfig.split_screen_enabled = false
	GameConfig.teams_enabled = false
	GameConfig.set_bot_count(2)
	_validate_shared_item_packet()
	reparent(NetworkManager)
	await _validate_one_of_us()
	await _validate_all_gun()
	await _validate_melee_throw_release()
	GameConfig.game_mode = GameConfig.MODE_ONE_GUN
	GameConfig.local_one_of_us_volunteers = [false, false]
	if failures.is_empty():
		print("NEW GAME MODES VALIDATION PASSED")
	get_tree().quit(0 if failures.is_empty() else 1)
