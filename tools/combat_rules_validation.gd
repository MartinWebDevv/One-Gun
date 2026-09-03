extends Node

class MockGunHolder:
	extends Node3D
	var holding_gun := true

class MockDashPlayer:
	extends Node
	var max_dash_charges := 2
	var dash_charges := 0
	var dash_recharge_timer := 1.5
	var dash_recharge_time := 3.0
	var extra_dash_charge := 0

	func get_dash_recharge_progress() -> float:
		return clampf(dash_recharge_timer / dash_recharge_time, 0.0, 1.0)

class MockFireActor:
	extends Node3D
	var is_eliminated := false
	var actor_id := 7001

class MockDecoyOwner:
	extends CharacterBody3D
	var active_decoy = null
	var team_id := -1
	var owner_peer_id := -1
	var holding_gun := false

class MockMeleePlayer:
	extends Node3D
	var holding_gun := false
	var held_melee_weapon = null
	var is_eliminated := false
	var actor_id := 7101
	var stamina := 100.0
	var animation_calls := 0
	var last_animation_duration := 0.0
	var swing_speed_multiplier := 1.0
	var hold_point: Node3D

	func _init() -> void:
		hold_point = Node3D.new()
		hold_point.name = "MeleeHoldPoint"
		add_child(hold_point)

	func get_melee_hold_point() -> Node3D:
		return hold_point

	func has_stamina() -> bool:
		return stamina > 0.0

	func drain_stamina(amount: float) -> void:
		stamina = maxf(stamina - amount, 0.0)

	func play_melee_animation(duration := 0.0) -> void:
		animation_calls += 1
		last_animation_duration = duration

	func melee_swing_speed_multiplier() -> float:
		return swing_speed_multiplier

	func has_active_reach() -> bool:
		return false

	func get_aim_pitch() -> float:
		return 0.0

	func get_aim_direction() -> Vector3:
		return Vector3.FORWARD

class MockManualPickupPlayer:
	extends Node3D
	var pickup_request_active := false
	var holding_gun := false
	var held_melee_weapon = null
	var actor_id := 7201
	var hold_point: Node3D

	func _init() -> void:
		hold_point = Node3D.new()
		add_child(hold_point)


	func is_manual_pickup_request_active() -> bool:
		return pickup_request_active

	func get_hold_point() -> Node3D:
		return hold_point

	func get_display_name() -> String:
		return "Pickup Gate Mock"

class MockAimPlayer:
	extends Node3D
	var camera: Camera3D
	var render_camera: Camera3D
	var actor_id := 7401

	func get_camera() -> Camera3D:
		return camera

	func get_gun_fire_camera() -> Camera3D:
		return render_camera if render_camera != null else camera

	func get_aim_direction() -> Vector3:
		return -camera.global_basis.z

class MockLooseMelee:
	extends Node3D
	var holder = null
	var drop_calls := 0

	func drop() -> void:
		drop_calls += 1
		if holder != null:
			holder.held_melee_weapon = null

var failures: Array[String] = []
class MockBoomerangHolder:
	extends CharacterBody3D
	var held_item = null
	var is_eliminated := false
	var actor_id := 7301
	var hold_point: Node3D

	func _init() -> void:
		hold_point = Node3D.new()
		hold_point.name = "ItemHoldPoint"
		add_child(hold_point)

	func get_item_hold_point() -> Node3D:
		return hold_point

	func can_pick_up_item() -> bool:
		return held_item == null

	func assign_item(item_obj) -> void:
		held_item = item_obj

	func clear_item_slot(item_obj) -> void:
		if held_item == item_obj:
			held_item = null

	func get_active_item():
		return held_item

	func get_aim_direction() -> Vector3:
		return Vector3.FORWARD

	func get_display_name() -> String:
		return "Boomerang Holder"


func _ready() -> void:
	await get_tree().process_frame
	if OS.get_environment("ONE_GUN_FEATURE_PASS_ONLY") == "1":
		_test_protections_and_timers()
		await _test_boomerang_second_throw()
		if failures.is_empty():
			print("FEATURE COMBAT VALIDATION: PASS")
			get_tree().quit(0)
		else:
			for failure in failures:
				push_error("FEATURE COMBAT VALIDATION: " + failure)
			get_tree().quit(1)
		return
	if OS.get_environment("ONE_GUN_MELEE_ONLY") == "1":
		await _test_melee_tuning()
		if failures.is_empty():
			print("MELEE WEAPON VALIDATION: PASS")
			get_tree().quit(0)
		else:
			for failure in failures:
				push_error("MELEE WEAPON VALIDATION: " + failure)
			get_tree().quit(1)
		return
	_test_projectile_and_gun()
	_test_protections_and_timers()
	await _test_boomerang_second_throw()
	await _test_melee_tuning()
	_test_stamina_and_dash()
	_test_overtime_math_and_tiebreak()
	_test_fire_height_and_warning()
	await _test_decoy_deployment_facing()
	_test_held_gun_overtime_detach()
	_test_dash_pip_sequence()
	_test_accessibility_free_safety()
	await get_tree().process_frame
	if failures.is_empty():
		print("COMBAT RULES VALIDATION: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("COMBAT RULES VALIDATION: " + failure)
		get_tree().quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _test_projectile_and_gun() -> void:
	var bullet = load("res://bullet.gd").new()
	_check(is_equal_approx(bullet.projectile_speed, 200.0), "projectile default is not 200")
	_check(is_equal_approx(bullet.emergency_lifetime, 10.0), "projectile emergency lifetime is not 10 seconds")
	var gun = load("res://gun.tscn").instantiate()
	get_tree().current_scene.add_child(gun)
	var bullet_scene: RigidBody3D = (load("res://bullet.tscn") as PackedScene).instantiate()
	var bullet_shape := bullet_scene.get_node("CollisionShape3D").shape as SphereShape3D
	var bullet_mesh := bullet_scene.get_node("MeshInstance3D").mesh as SphereMesh
	_check(is_equal_approx(bullet_shape.radius, 0.025),
		"projectile collision core is not the precise 0.025m radius")
	_check(is_equal_approx(bullet_mesh.radius, 0.1),
		"projectile visible radius changed with its collision core")
	bullet_scene.free()
	_check(is_equal_approx(gun.projectile_speed, 200.0), "gun and projectile speed defaults differ")
	_check(is_equal_approx(gun.reload_time, 2.0), "reload default changed")
	var aim_player := MockAimPlayer.new()
	var source_camera := Camera3D.new()
	var aim_viewport := SubViewport.new()
	aim_viewport.size = Vector2i(800, 900)
	var aim_camera := Camera3D.new()
	aim_player.add_child(source_camera)
	aim_viewport.add_child(aim_camera)
	get_tree().current_scene.add_child(aim_viewport)
	aim_player.camera = source_camera
	aim_player.render_camera = aim_camera
	get_tree().current_scene.add_child(aim_player)
	aim_camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(-0.17, 0.43, 0.0)), Vector3(3.0, 4.0, 7.0))
	# Deliberately make the player's source camera disagree. This catches the
	# exact production regression where the ray used a different viewport camera
	# from the one that rendered the crosshair image.
	source_camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(0.08, -0.31, 0.0)), Vector3(-4.0, 2.0, 1.0))
	gun.player_ref = aim_player
	var fire_ray: Dictionary = gun._calculate_fire_ray()
	var projected_point: Vector2 = aim_camera.unproject_position(
		fire_ray["origin"] + fire_ray["direction"] * 25.0)
	var viewport_center := aim_camera.get_viewport().get_visible_rect().size * 0.5
	_check(projected_point.distance_to(viewport_center) < 0.01,
		"gun projectile ray does not remain on the exact viewport-center crosshair")
	gun.fire()
	var spawned_bullet: RigidBody3D = null
	var bullet_script := load("res://bullet.gd")
	for candidate in get_tree().current_scene.get_children():
		if candidate.get_script() == bullet_script:
			spawned_bullet = candidate as RigidBody3D
			break
	_check(spawned_bullet != null, "gun did not create a projectile")
	if spawned_bullet != null:
		var first_frame_point := aim_camera.unproject_position(
			spawned_bullet.global_position)
		var later_point := aim_camera.unproject_position(
			spawned_bullet.global_position + spawned_bullet.linear_velocity * 0.1)
		_check(first_frame_point.distance_to(viewport_center) < 0.01,
			"bullet's first visible position is not centered on the crosshair")
		_check(later_point.distance_to(viewport_center) < 0.01,
			"bullet trajectory converges toward the crosshair instead of staying centered")
		spawned_bullet.free()
	gun.player_ref = null
	var player := MockManualPickupPlayer.new()
	var old_melee := MockLooseMelee.new()
	get_tree().current_scene.add_child(player)
	get_tree().current_scene.add_child(old_melee)
	old_melee.holder = player
	player.held_melee_weapon = old_melee

	_check(not gun.pick_up(player),
		"gun equipped from proximity without an explicit Interact request")
	_check(not gun.is_held and not player.holding_gun and old_melee.drop_calls == 0,
		"rejected proximity pickup changed held state or dropped the melee weapon")

	player.pickup_request_active = true
	_check(gun.pick_up(player),
		"explicit Interact request did not pick up the gun")
	_check(gun.is_held and player.holding_gun and old_melee.drop_calls == 1,
		"explicit gun pickup did not perform exactly one melee-for-gun swap")
	player.pickup_request_active = false

	_check(is_equal_approx(gun.loose_return_time, 5.0), "loose gun return is not five seconds")
	_check(gun.reload_time != gun.loose_return_time, "reload and loose-return tuning are coupled")
	bullet.free()
	gun.free()
	aim_player.free()
	aim_viewport.free()
	old_melee.free()
	player.free()

func _test_protections_and_timers() -> void:
	var player = load("res://character_body_3d.gd").new()
	_check(player.apply_powerup("sticky_hands", 10.0), "Sticky Hands could not be collected")
	_check(player.melee_disarm_shields == 1, "Sticky Hands did not grant its shield")
	_check(is_equal_approx(player.sticky_hands_timer, GameConfig.STICKY_HANDS_DURATION),
		"Sticky Hands did not start its 30-second duration")
	var sticky_entries: Array = player.get_active_powerups_for_display().filter(
		func(entry): return entry.get("type", "") == "sticky_hands")
	_check(not sticky_entries.is_empty(), "Sticky Hands is missing from the HUD powerup list")
	if not sticky_entries.is_empty():
		_check(bool(sticky_entries[0].get("timed", false)), "Sticky Hands HUD entry is not timed")
	_check(player.apply_powerup("extra_life", 10.0), "Extra Life could not coexist with Sticky Hands")
	_check(not player.apply_powerup("sticky_hands", 10.0), "duplicate Sticky Hands was accepted")
	_check(not player.apply_powerup("extra_life", 10.0), "duplicate Extra Life was accepted")
	_check(player.apply_powerup("speed_surge", 10.0), "Speed Surge could not be collected")
	_check(player.apply_powerup("fast_hands", 99.0), "Fast Hands could not be collected")
	_check(is_equal_approx(player.fast_hands_timer, GameConfig.FAST_HANDS_DURATION),
		"Fast Hands ignored its fixed five-second duration")
	_check(is_equal_approx(player.melee_swing_speed_multiplier(), 1.5),
		"Fast Hands does not expose a 1.5x swing multiplier")
	player.apply_powerup("speed_surge", 10.0)
	_check(is_equal_approx(player.speed_surge_timer, 15.0), "timed duplicate did not add half duration")
	player.apply_powerup("speed_surge", 10.0)
	player.apply_powerup("speed_surge", 10.0)
	_check(is_equal_approx(player.speed_surge_timer, 20.0), "timed powerup exceeded or missed 2x cap")
	_check(player.consume_extra_life(), "Extra Life did not consume")
	_check(is_equal_approx(player.lethal_immunity_timer, 1.0), "Extra Life immunity is not one second")
	player._update_new_powerups(GameConfig.STICKY_HANDS_DURATION - 0.5)
	_check(player.melee_disarm_shields == 1 and not player.can_collect_powerup("sticky_hands"),
		"Sticky Hands expired early or allowed stacking while active")
	player._update_new_powerups(0.5)
	_check(player.melee_disarm_shields == 0, "Sticky Hands did not expire after 30 seconds")
	_check(is_equal_approx(player.sticky_hands_cooldown_timer, GameConfig.STICKY_HANDS_REPICKUP_COOLDOWN),
		"Sticky Hands expiry did not begin its eight-second cooldown")
	_check(not player.can_collect_powerup("sticky_hands"), "Sticky Hands was collectible during cooldown")
	player._update_new_powerups(GameConfig.STICKY_HANDS_REPICKUP_COOLDOWN - 0.1)
	_check(not player.can_collect_powerup("sticky_hands"), "Sticky Hands cooldown ended early")
	player._update_new_powerups(0.1)
	_check(player.can_collect_powerup("sticky_hands"), "Sticky Hands did not unlock after cooldown")
	_check(player.apply_powerup("sticky_hands", 10.0), "Sticky Hands could not be recollected after cooldown")
	_check(player.consume_sticky_hands(), "Sticky Hands did not consume")
	_check(not player.consume_sticky_hands(), "Sticky Hands behaved like it had a hidden second charge")
	_check(is_equal_approx(player.sticky_hands_cooldown_timer, GameConfig.STICKY_HANDS_REPICKUP_COOLDOWN),
		"consumed Sticky Hands did not begin its eight-second cooldown")
	player.clear_all_powerups()
	_check(
		player.melee_disarm_shields == 0
		and player.sticky_hands_timer == 0.0
		and player.sticky_hands_cooldown_timer == 0.0
		and player.fast_hands_timer == 0.0
		and not player.second_wind_ready,
		"full powerup clear left a protection behind")
	player.free()
	var bot = load("res://dummy.gd").new()
	_check(bot.apply_powerup("sticky_hands", 10.0), "bot could not collect Sticky Hands")
	_check(bot.apply_powerup("fast_hands", 10.0)
		and is_equal_approx(bot.melee_swing_speed_multiplier(), 1.5),
		"bot Fast Hands behavior differs from humans")
	_check(is_equal_approx(bot.sticky_hands_timer, GameConfig.STICKY_HANDS_DURATION),
		"bot Sticky Hands duration differs from humans")
	bot._clear_sticky_hands(true)
	_check(
		is_equal_approx(bot.sticky_hands_cooldown_timer, GameConfig.STICKY_HANDS_REPICKUP_COOLDOWN)
		and not bot.can_collect_powerup("sticky_hands"),
		"bot Sticky Hands cooldown differs from humans")
	bot.free()


func _test_boomerang_second_throw() -> void:
	var holder = MockBoomerangHolder.new()
	get_tree().current_scene.add_child(holder)
	var boomerang = load("res://boomerang.tscn").instantiate()
	get_tree().current_scene.add_child(boomerang)
	await get_tree().process_frame
	_check(boomerang._do_pickup(holder), "boomerang could not enter the test inventory")
	boomerang.throw()
	_check(boomerang._throws_used == 1 and boomerang.is_in_flight,
		"boomerang did not record its first throw")
	boomerang._finish_return()
	_check(boomerang.is_held and holder.held_item == boomerang and boomerang._throws_used == 1,
		"missed first boomerang throw was not returned to inventory")
	boomerang.throw()
	_check(boomerang._throws_used == 2 and boomerang.is_in_flight,
		"boomerang did not record its second throw")
	boomerang._finish_return()
	_check(boomerang._consumed and not boomerang.visible and holder.held_item == null,
		"boomerang did not disappear after its second missed return")
	boomerang.queue_free()
	holder.queue_free()
	await get_tree().process_frame

func _test_melee_tuning() -> void:
	var melee_scene := load("res://melee_weapon.tscn") as PackedScene
	var weapon_names := ["Sword", "Baseball Bat", "Stick", "Crowbar", "Frying Pan"]
	var original_mode: String = GameConfig.game_mode
	GameConfig.game_mode = GameConfig.MODE_ONE_GUN
	var frying_pan_data: WeaponData = MeleeWeaponRegistry.get_weapon_data_by_name("Frying Pan")
	for weapon_name in weapon_names:
		var melee = melee_scene.instantiate()
		get_tree().current_scene.add_child(melee)
		var data: WeaponData = MeleeWeaponRegistry.get_weapon_data_by_name(weapon_name)
		melee.apply_weapon_data(data, "normal")
		_validate_shared_melee_hitbox(
			melee, weapon_name, GameConfig.DEFAULT_MELEE_HITBOX_LENGTH)
		_check(not ("tier" in melee), "%s still exposes a tier" % weapon_name)
		_check(is_equal_approx(data.raw_model_length * data.held_scale,
			MeleeWeaponRegistry.HELD_WEAPON_TARGET_LENGTH),
			"%s is not normalized to the shared held length" % weapon_name)
		_check(is_equal_approx(melee.SWING_TIME_MULTIPLIER, 0.85),
			"%s swing phases are not fifteen percent faster" % weapon_name)
		_check(is_equal_approx(data.base_windup_time, frying_pan_data.base_windup_time)
			and is_equal_approx(data.base_active_time, frying_pan_data.base_active_time)
			and is_equal_approx(data.base_recovery_time, frying_pan_data.base_recovery_time),
			"%s does not share the frying-pan swing phases" % weapon_name)
		_check(is_equal_approx(melee.MELEE_HITBOX_RADIUS, 0.45),
			"%s does not use the shared melee width" % weapon_name)
		_check(not melee.get_network_identity().has("tier"),
			"%s still sends a tier over the network" % weapon_name)

		var model: Node3D = melee._model_instance
		var anchored_grip: Vector3 = model.transform * data.held_grip_anchor
		_check(anchored_grip.length() < 0.001,
			"%s is not held from its authored handle base" % weapon_name)

		var holder := MockMeleePlayer.new()
		get_tree().current_scene.add_child(holder)
		_check(melee._local_pickup(holder), "%s could not be picked up" % weapon_name)
		var rest_rotation: Vector3 = melee.rotation
		melee.swing()
		_check(holder.animation_calls == 1,
			"%s did not trigger the character melee animation" % weapon_name)
		var normal_duration: float = (data.base_windup_time + data.base_active_time
			+ data.base_recovery_time) * melee.SWING_TIME_MULTIPLIER
		_check(is_equal_approx(holder.last_animation_duration, normal_duration),
			"%s character animation duration does not match gameplay phases" % weapon_name)
		_check((melee.rotation - rest_rotation).length() < 0.001,
			"%s added weapon-root rotation at swing start" % weapon_name)
		var saw_active_window := false
		var root_rotated := false
		var swing_frames := 0
		while melee.is_swinging and swing_frames < 180:
			await get_tree().physics_frame
			saw_active_window = saw_active_window \
				or melee.get_node("HitBox").monitoring
			root_rotated = root_rotated \
				or (melee.rotation - rest_rotation).length() >= 0.001
			swing_frames += 1
		_check(saw_active_window,
			"%s did not open its physical active hit window" % weapon_name)
		_check(not root_rotated,
			"%s still performs a separate weapon-object swing" % weapon_name)
		_check(not melee.is_swinging and not melee.get_node("HitBox").monitoring,
			"%s did not close its hit window after recovery" % weapon_name)
		melee.drop()
		_check(melee.get_parent() == get_tree().current_scene
			and holder.held_melee_weapon == null,
			"%s did not release cleanly after its swing" % weapon_name)
		_check(melee._local_pickup(holder),
			"%s could not be picked back up after dropping" % weapon_name)
		holder.swing_speed_multiplier = GameConfig.FAST_HANDS_SWING_SPEED_MULTIPLIER
		var stamina_before_fast_hands: float = holder.stamina
		melee.swing()
		_check(is_equal_approx(holder.last_animation_duration,
			normal_duration / GameConfig.FAST_HANDS_SWING_SPEED_MULTIPLIER),
			"%s Fast Hands did not shorten every swing phase by 1.5x" % weapon_name)
		_check(is_equal_approx(stamina_before_fast_hands - holder.stamina,
			data.base_stamina_cost),
			"%s Fast Hands changed stamina usage" % weapon_name)
		while melee.is_swinging:
			await get_tree().physics_frame
		melee.begin_throw_preview()
		var preview: Dictionary = melee.get_throw_preview_data()
		var preview_velocity: Vector3 = preview.get("velocity", Vector3.ZERO)
		_check(not preview.is_empty() and preview_velocity.length() > 0.0,
			"%s did not expose a valid throw preview" % weapon_name)
		melee.release_throw()
		_check(melee.is_in_flight and not melee.is_held
			and melee.get_parent() == get_tree().current_scene
			and holder.held_melee_weapon == null,
			"%s did not enter flight cleanly after preview release" % weapon_name)
		melee.is_in_flight = false
		melee.free()
		holder.free()

	GameConfig.game_mode = GameConfig.MODE_ONE_OF_US
	for weapon_name in weapon_names:
		var melee = melee_scene.instantiate()
		get_tree().current_scene.add_child(melee)
		melee.apply_weapon_data(
			MeleeWeaponRegistry.get_weapon_data_by_name(weapon_name), "normal")
		_validate_shared_melee_hitbox(
			melee, weapon_name, GameConfig.ONE_OF_US_MELEE_HITBOX_LENGTH)
		melee.free()
	GameConfig.game_mode = original_mode

	var player_script = load("res://character_body_3d.gd")
	_check(player_script.should_attempt_interact(true, false),
		"Interact alone does not permit pickup")
	_check(not player_script.should_attempt_interact(true, true),
		"Fire plus Interact still permits pickup")
	_check(not player_script.should_attempt_interact(false, true),
		"Fire alone permits pickup")


func _validate_shared_melee_hitbox(
		melee, weapon_name: String, expected_length: float) -> void:
	var runtime_shape := melee.get_node("HitBox/CollisionShape3D") as CollisionShape3D
	_check(runtime_shape.shape is CapsuleShape3D,
		"%s does not use the shared capsule" % weapon_name)
	if not runtime_shape.shape is CapsuleShape3D:
		return
	var capsule := runtime_shape.shape as CapsuleShape3D
	_check(is_equal_approx(capsule.height, expected_length),
		"%s hitbox is %.2fm instead of %.2fm" % [
			weapon_name, capsule.height, expected_length])
	_check(is_equal_approx(capsule.radius, melee.MELEE_HITBOX_RADIUS),
		"%s does not use the shared capsule radius" % weapon_name)
	_check(runtime_shape.basis.is_equal_approx(Basis.IDENTITY),
		"%s hitbox uses a model-specific orientation" % weapon_name)
	_check(runtime_shape.position.is_equal_approx(
		Vector3(0.0, expected_length * 0.5, 0.0)),
		"%s hitbox is not anchored outward from the paw" % weapon_name)
	melee._apply_powerup_reach(true)
	var reach_shape := runtime_shape.shape as CapsuleShape3D
	_check(is_equal_approx(reach_shape.height,
		melee.POWERUP_MELEE_MAX_HIT_DISTANCE)
		and runtime_shape.position.is_equal_approx(
			Vector3(0.0, melee.POWERUP_MELEE_MAX_HIT_DISTANCE * 0.5, 0.0)),
		"%s Reach hitbox does not extend from the paw to 8m" % weapon_name)
	melee._restore_powerup_reach()
	var restored := runtime_shape.shape as CapsuleShape3D
	_check(is_equal_approx(restored.height, expected_length)
		and runtime_shape.position.is_equal_approx(
			Vector3(0.0, expected_length * 0.5, 0.0)),
		"%s did not restore its normal hitbox after Reach" % weapon_name)

func _test_stamina_and_dash() -> void:
	var player = load("res://character_body_3d.gd").new()
	player.stamina = 2.0
	player.drain_stamina(20.0)
	_check(is_equal_approx(player.stamina, 0.0), "human stamina can go negative")
	player.dash_charges = 1
	player.dash_recharge_timer = 1.5
	player.dash_recharge_time = 3.0
	_check(is_equal_approx(player.get_dash_recharge_progress(), 0.5), "dash pip progress is not continuous")
	player.apply_powerup("extra_dash", 5.0)
	_check(player.extra_dash_charge == 1, "Extra Dash is not a separate charge")
	player.free()
	var bot = load("res://dummy.gd").new()
	bot.stamina = 1.0
	bot.drain_stamina(10.0)
	_check(is_equal_approx(bot.stamina, 0.0), "bot stamina can go negative")
	bot.free()

func _test_overtime_math_and_tiebreak() -> void:
	var manager = load("res://round_manager.gd").new()
	manager.overtime_active = true
	manager._overtime_outer_radius = 100.0
	manager._overtime_outer_extents = Vector2(100.0, 100.0)
	manager._overtime_start_extents = Vector2(105.0, 105.0)
	manager.overtime_elapsed = 0.0
	_check(is_equal_approx(manager._current_storm_radius(), 105.0),
		"opening overtime radius is wrong")
	manager.overtime_elapsed = 20.0
	_check(manager._current_storm_radius() < 100.0,
		"storm pauses instead of closing continuously")
	_check(is_equal_approx(manager.OVERTIME_FULL_ENGULF_TIME, 120.0),
		"storm does not fully close in two minutes")
	manager.overtime_elapsed = 60.0
	var expected_midpoint_zone := floori(
		(60.0 - manager.OVERTIME_OPENING_APPROACH_TIME)
		/ manager.OVERTIME_ZONE_DURATION)
	_check(manager._overtime_zone_index() == expected_midpoint_zone,
		"zone thresholds do not follow the continuous two-minute close")
	manager.overtime_elapsed = 65.432
	_check(manager.get_round_timer_text() == "OT  01:05",
		"OT HUD timer should show minutes and seconds only")
	manager.overtime_elapsed = 240.0
	_check(is_equal_approx(manager._current_fire_exposure_limit(), 3.0),
		"fire exposure limit dropped below three seconds after zone three")
	var original_chaos: bool = GameConfig.chaos_overtime_enabled
	GameConfig.chaos_overtime_enabled = false
	_check(manager._overtime_announcement() == "OVERTIME - ONE GUN",
		"standard overtime announcement does not preserve the one-gun rules")
	GameConfig.chaos_overtime_enabled = true
	_check(manager._overtime_announcement() == "OVERTIME - CHAOS GUNFIGHT",
		"Chaos OT announcement is not selected")
	GameConfig.chaos_overtime_enabled = original_chaos
	_check("chaos_overtime_enabled" in GameConfig.PRESET_FIELDS,
		"Chaos OT is missing from saved and network-synced match settings")
	manager.free()

func _test_fire_height_and_warning() -> void:
	var manager = load("res://round_manager.gd").new()
	manager.overtime_active = true
	manager._overtime_center = Vector3.ZERO
	manager._overtime_outer_radius = 20.0
	manager._overtime_outer_extents = Vector2(20.0, 20.0)
	manager._overtime_start_extents = Vector2(22.0, 22.0)
	manager.overtime_elapsed = manager.OVERTIME_OPENING_APPROACH_TIME
	var ground_actor := MockFireActor.new()
	get_tree().current_scene.add_child(ground_actor)
	ground_actor.global_position = Vector3(21.0, 0.0, 0.0)
	var rooftop_actor := MockFireActor.new()
	get_tree().current_scene.add_child(rooftop_actor)
	rooftop_actor.global_position = Vector3(21.0, 80.0, 0.0)
	_check(manager._is_position_in_fire(ground_actor.global_position)
		and manager._is_position_in_fire(rooftop_actor.global_position),
		"fire damage changed with player height")
	manager._storm_exposure[rooftop_actor] = 1.25
	var warning: Dictionary = manager.get_fire_warning(rooftop_actor)
	_check(bool(warning.get("active", false))
		and is_equal_approx(float(warning.get("remaining", 0.0)), 3.75),
		"player fire warning did not expose the remaining escape time")
	var hud := Control.new()
	hud.set_script(load("res://match_hud.gd"))
	get_tree().current_scene.add_child(hud)
	hud.update_fire_warning(warning)
	var warning_panel = hud.get_node_or_null("FireExposureWarning")
	_check(warning_panel != null and warning_panel.visible
		and bool(warning_panel.get_meta("fire_warning_active", false)),
		"HUD did not display the active fire countdown")
	hud.update_fire_warning({"active": false})
	_check(not warning_panel.visible, "HUD fire countdown stayed visible after reaching safety")
	hud.free()
	var original_split: bool = GameConfig.split_screen_enabled
	GameConfig.split_screen_enabled = true
	var second_hud := Control.new()
	second_hud.set_script(load("res://match_hud.gd"))
	second_hud.set("is_second_screen", true)
	get_tree().current_scene.add_child(second_hud)
	_check(is_equal_approx(second_hud.anchor_left, 0.5)
		and is_equal_approx(second_hud.anchor_right, 1.0),
		"splitscreen P2 fire warning HUD was not scoped to the right viewport")
	second_hud.free()
	GameConfig.split_screen_enabled = original_split
	ground_actor.free()
	rooftop_actor.free()
	manager.free()

func _test_held_gun_overtime_detach() -> void:
	var holder := MockGunHolder.new()
	get_tree().current_scene.add_child(holder)
	var gun = load("res://gun.tscn").instantiate()
	holder.add_child(gun)
	gun.is_held = true
	gun.player_ref = holder
	gun.disable_for_overtime()
	_check(gun.get_parent() == get_tree().current_scene,
		"held gun did not safely reparent to the world when overtime began")
	_check(not holder.holding_gun and not gun.visible,
		"held gun overtime cleanup left ownership or visibility behind")
	gun.free()
	holder.free()

func _test_decoy_deployment_facing() -> void:
	var owner := MockDecoyOwner.new()
	get_tree().current_scene.add_child(owner)
	var decoy = load("res://decoy_body.tscn").instantiate()
	decoy.owner_player = owner
	decoy.initial_forward = Vector3.RIGHT
	get_tree().current_scene.add_child(decoy)
	var movement_forward: Vector3 = -decoy.global_basis.z
	movement_forward.y = 0.0
	_check(movement_forward.normalized().dot(Vector3.RIGHT) > 0.99,
		"deployed decoy did not inherit the throw direction")
	_check(decoy.get_visual_facing_direction().dot(Vector3.RIGHT) > 0.99,
		"decoy model faces backward while moving")
	_check(decoy.is_in_group("combat_target") and decoy.is_in_group("combat_decoy"),
		"decoy did not register for combat and bot targeting")
	_check(not decoy.is_in_group("player"),
		"decoy incorrectly participates in player scoring")
	_check(is_equal_approx(decoy.LIFETIME, 10.0) and decoy.manages_deployed_lifetime(),
		"decoy no longer owns its ten-second lifetime")
	_check(decoy._animation_player != null and decoy._animation_player.active
			and decoy._animation_player.has_animation("idle")
			and decoy._animation_player.has_animation("standard_run"),
		"decoy did not bind the shared idle/run animation library")
	_check(is_zero_approx(decoy._visual_root.position.x)
		and is_zero_approx(decoy._visual_root.position.z),
		"decoy visual root is displaced from its physics body")
	var run_animation: Animation = decoy._animation_player.get_animation("standard_run")
	var root_motion_safe := run_animation != null
	if run_animation != null:
		for track_index in run_animation.get_track_count():
			if run_animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
				continue
			var track_path: NodePath = run_animation.track_get_path(track_index)
			if track_path.get_subname_count() == 0:
				root_motion_safe = false
				continue
			if str(track_path.get_subname(track_path.get_subname_count() - 1)) \
					!= "mixamorig_Hips" or run_animation.track_get_key_count(track_index) < 2:
				continue
			var anchor: Vector3 = run_animation.track_get_key_value(track_index, 0)
			for key_index in run_animation.track_get_key_count(track_index):
				var position: Vector3 = run_animation.track_get_key_value(
					track_index, key_index)
				if not is_equal_approx(position.x, anchor.x) \
						or not is_equal_approx(position.z, anchor.z):
					root_motion_safe = false
	_check(root_motion_safe,
		"retargeted decoy run clip can translate the visual horizontally")
	decoy._visual_motion_speed = decoy.MOVE_SPEED
	decoy._process(0.1)
	_check(decoy._current_visual_animation == "standard_run"
			and is_zero_approx(decoy._visual_root.position.x)
			and is_zero_approx(decoy._visual_root.position.z),
		"moving decoy did not enter its root-motion-safe run animation")
	_check(not decoy.control_active, "decoy control should start released")
	decoy.toggle_control()
	_check(decoy.control_active and not decoy.command_target.is_finite(),
		"one decoy-control press did not latch control on")
	owner.velocity = Vector3.RIGHT * 10.0
	var desired: Vector3 = decoy._desired_horizontal_velocity()
	_check(desired.x > 0.0,
		"controlled decoy did not mirror the owner's movement")
	decoy.toggle_control()
	_check(not decoy.control_active and decoy.command_target.is_finite(),
		"second decoy-control press did not release control and resume forward movement")
	decoy.free()
	owner.free()

func _test_dash_pip_sequence() -> void:
	var dash_player := MockDashPlayer.new()
	var display := HBoxContainer.new()
	display.set_script(load("res://dash_charges.gd"))
	get_tree().current_scene.add_child(display)
	display.set_player(dash_player)
	display._process(0.0)
	_check(is_equal_approx(float(display.get_child(0).get_meta("recharge_fill")), 0.5),
		"left dash pip did not receive the active recharge progress")
	_check(is_zero_approx(float(display.get_child(1).get_meta("recharge_fill"))),
		"second dash pip recharged at the same time as the first")
	dash_player.dash_charges = 1
	dash_player.dash_recharge_timer = 0.75
	display._process(0.0)
	_check(is_equal_approx(float(display.get_child(0).get_meta("recharge_fill")), 1.0),
		"recharged dash pip did not remain visibly loaded")
	_check(is_equal_approx(float(display.get_child(1).get_meta("recharge_fill")), 0.25),
		"second dash pip did not begin after the first locked in")
	dash_player.dash_charges = 2
	display._process(0.0)
	_check(is_equal_approx(float(display.get_child(0).get_meta("recharge_fill")), 1.0)
		and is_equal_approx(float(display.get_child(1).get_meta("recharge_fill")), 1.0),
		"fully recharged dash pips did not stay loaded")
	display.free()
	dash_player.free()

func _test_accessibility_free_safety() -> void:
	var transient := Label.new()
	get_tree().root.add_child(transient)
	transient.queue_free()
