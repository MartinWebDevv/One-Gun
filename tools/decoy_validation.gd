extends Node3D

class MockOwner:
	extends CharacterBody3D
	var active_decoy = null
	var team_id := 0
	var holding_gun := false
	var is_eliminated := false
	var is_bot := false
	var actor_id := 41
	var owner_peer_id := 1
	var outline_count := 0

	func get_display_name() -> String:
		return "Test Cat"

	func show_decoy_destroyer_outline(_duration: float, _decoy_owner = null) -> void:
		outline_count += 1


var failures: Array[String] = []
var _owner: MockOwner
var _elimination_events := 0
var _decoy_scene: PackedScene = preload("res://decoy_body.tscn")


func _ready() -> void:
	_build_floor()
	_owner = MockOwner.new()
	_owner.name = "Owner"
	_owner.collision_layer = 0
	_owner.collision_mask = 0
	_owner.position = Vector3(-20.0, 0.0, -20.0)
	add_child(_owner)
	GameEvents.player_eliminated.connect(_on_player_eliminated)
	await get_tree().physics_frame
	print("DECOY TEST: scene contract")
	await _test_scene_contract()
	print("DECOY TEST: item deployment")
	await _test_item_deployment_contract()
	print("DECOY TEST: gait continuity")
	await _test_procedural_gait_continuity()
	print("DECOY TEST: automatic movement")
	await _test_automatic_movement_is_monotonic()
	print("DECOY TEST: scaled-map deployment")
	await _test_scaled_map_deployment()
	print("DECOY TEST: toggle control")
	await _test_toggle_control_is_monotonic()
	print("DECOY TEST: collision stop")
	await _test_collision_stop_has_no_reversal()
	print("DECOY TEST: status and hazards")
	await _test_status_and_hazard_contracts()
	print("DECOY TEST: combat pop")
	await _test_combat_pop_rules()
	print("DECOY TEST: owner/lifetime")
	await _test_single_decoy_owner_death_and_lifetime()
	print("DECOY TEST: bot parity")
	await _test_bot_target_parity()
	print("DECOY TEST: network snapshot")
	await _test_network_snapshot_does_not_extrapolate()
	if failures.is_empty():
		print("DECOY VALIDATION: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("DECOY VALIDATION: " + failure)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _on_player_eliminated(_victim: String, _killer: String, _icon) -> void:
	_elimination_events += 1


func _build_floor() -> void:
	var floor := StaticBody3D.new()
	floor.name = "ValidationFloor"
	floor.collision_layer = 1
	floor.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(120.0, 0.5, 120.0)
	collision.shape = shape
	floor.add_child(collision)
	floor.position.y = -0.25
	add_child(floor)


func _spawn_decoy(at: Vector3, forward: Vector3, lifetime := 8.0):
	var decoy = _decoy_scene.instantiate()
	decoy.owner_player = _owner
	decoy.initial_forward = forward
	decoy.lifetime_seconds = lifetime
	decoy.position = at
	add_child(decoy)
	return decoy


func _test_scene_contract() -> void:
	var decoy = _spawn_decoy(Vector3(0.0, 0.0, -20.0), Vector3.RIGHT)
	_check(decoy is CharacterBody3D, "deployed decoy is not a CharacterBody3D")
	_check(decoy.collision_layer == 2 and decoy.collision_mask == 1,
		"decoy collision is not isolated to combat layer 2 versus map layer 1")
	_check(decoy.is_in_group("combat_target") and decoy.is_in_group("combat_decoy"),
		"decoy did not register as a bot-visible combat target")
	_check(not decoy.is_in_group("player"),
		"decoy incorrectly joined the scoring/player group")
	_check(_owner.active_decoy == decoy, "owner did not register its active decoy")
	_check(is_equal_approx(decoy.lifetime_seconds, 8.0)
		and is_equal_approx(decoy.LIFETIME, 10.0),
		"decoy lifetime default is no longer ten seconds")
	_check(decoy.manages_deployed_lifetime(),
		"decoy no longer owns its authoritative lifetime")
	_check(decoy._animation_player != null \
		and decoy._animation_player.has_animation("idle") \
		and decoy._animation_player.has_animation("standard_run"),
		"V2 decoy did not bind its Idle and Standard Run animations")
	for method_name in ["can_be_affected_by", "pop_from_attack", "apply_slow",
			"apply_launch", "server_online_hit", "apply_online_action"]:
		_check(decoy.has_method(method_name),
			"rebuilt decoy is missing integration method " + method_name)
	var visual: Node3D = decoy.get_node("VisualRoot")
	_check(is_zero_approx(visual.position.x) and is_zero_approx(visual.position.z),
		"visual root starts displaced from the collision body")
	_check(decoy.get_visual_facing_direction().dot(Vector3.RIGHT) > 0.99,
		"decoy visual does not face its deployment direction")
	_check(decoy._animation_player.active,
		"the V2 decoy animation player is inactive")
	decoy.free()
	await get_tree().process_frame


func _test_item_deployment_contract() -> void:
	var item = load("res://decoy.tscn").instantiate()
	item.player_ref = _owner
	item.deployment_forward = Vector3.RIGHT
	item.position = Vector3(-4.0, 0.0, -18.0)
	add_child(item)
	item._spawn_deployed(Vector3(0.0, 0.0, -18.0), -1, -1)
	await get_tree().process_frame
	var deployed = _owner.active_decoy
	_check(deployed != null and is_instance_valid(deployed),
		"decoy item did not create a deployed actor")
	if deployed != null and is_instance_valid(deployed):
		_check(deployed.is_in_group("deployed_trap"),
			"deployed decoy is missing round/overtime cleanup registration")
		_check(deployed.get_visual_facing_direction().dot(Vector3.RIGHT) > 0.99,
			"item throw direction was not transferred to the deployed decoy")
		_check(deployed.manages_deployed_lifetime(),
			"item deployment can race the decoy's lifetime timer")
		_check(is_equal_approx(deployed.lifetime_seconds, item.deployed_lifetime),
			"decoy item lifetime was not transferred to the deployed actor")
		deployed.free()
	item.free()
	await get_tree().process_frame


func _test_procedural_gait_continuity() -> void:
	var decoy = _spawn_decoy(Vector3(0.0, 0.0, -16.0), Vector3.RIGHT)
	decoy.set_physics_process(false)
	decoy._visual_motion_speed = 10.0
	if decoy._animation_player != null:
		decoy._process(1.0 / 60.0)
		_check(decoy._current_visual_animation == "standard_run",
			"moving V2 decoy did not enter Standard Run")
		_check(is_zero_approx(decoy._visual_root.position.x) \
			and is_zero_approx(decoy._visual_root.position.z),
			"V2 run animation translated VisualRoot in X/Z")
		decoy._visual_motion_speed = 0.0
		decoy._process(1.0 / 60.0)
		_check(decoy._current_visual_animation == "idle",
			"stopped V2 decoy did not return to Idle")
		decoy.free()
		await get_tree().process_frame
		return
	var left_leg_index := int(decoy._bone_indices["left_up_leg"])
	var previous: Quaternion = decoy._skeleton.get_bone_pose_rotation(left_leg_index)
	var max_rotation_step := 0.0
	for _sample in 480:
		decoy._process(1.0 / 240.0)
		var current: Quaternion = decoy._skeleton.get_bone_pose_rotation(left_leg_index)
		max_rotation_step = maxf(max_rotation_step, previous.angle_to(current))
		previous = current
		_check(is_zero_approx(decoy._visual_root.position.x)
			and is_zero_approx(decoy._visual_root.position.z),
			"procedural gait translated VisualRoot in X/Z")
	print("DECOY GAIT: max rotation step=", max_rotation_step)
	_check(max_rotation_step < 0.03,
		"procedural gait contains a visible per-frame rotation discontinuity")
	_check(decoy._gait_phase > 0.0 and decoy._gait_blend > 0.99,
		"procedural gait did not advance while moving")
	decoy._visual_motion_speed = 0.0
	for _sample in 240:
		decoy._process(1.0 / 240.0)
	var rest: Quaternion = decoy._bone_rest_rotations[left_leg_index]
	var settled: Quaternion = decoy._skeleton.get_bone_pose_rotation(left_leg_index)
	_check(decoy._gait_blend <= 0.001 and rest.angle_to(settled) < 0.001,
		"procedural gait did not return smoothly to its captured rest pose")
	_check(decoy._visual_root.position.is_equal_approx(Vector3.ZERO),
		"idle gait left VisualRoot offset from the body")
	decoy.free()
	await get_tree().process_frame


func _test_automatic_movement_is_monotonic() -> void:
	var decoy = _spawn_decoy(Vector3(0.0, 0.0, -10.0), Vector3.RIGHT)
	var previous_x: float = decoy.global_position.x
	var start_phase: float = decoy._gait_phase
	for _frame in 100:
		await get_tree().physics_frame
		var current_x: float = decoy.global_position.x
		_check(current_x + 0.0005 >= previous_x,
			"automatic decoy reversed during unobstructed forward movement")
		previous_x = current_x
		_check(is_zero_approx(decoy._visual_root.position.x)
			and is_zero_approx(decoy._visual_root.position.z),
			"automatic gait displaced the rendered decoy from its body")
	_check(decoy.global_position.x > 10.0,
		"automatic decoy did not make meaningful forward progress")
	_check(decoy._current_visual_animation == "standard_run" \
		or decoy._gait_phase != start_phase,
		"automatic movement did not drive the decoy run presentation")
	decoy.free()
	await get_tree().process_frame


func _test_scaled_map_deployment() -> void:
	var map_root := Node3D.new()
	map_root.name = "ScaledMapRoot"
	map_root.scale = Vector3.ONE * 2.0
	add_child(map_root)
	var decoy = _decoy_scene.instantiate()
	decoy.owner_player = _owner
	decoy.initial_forward = Vector3.RIGHT
	decoy.lifetime_seconds = 8.0
	decoy.position = map_root.to_local(Vector3(0.0, 0.0, 12.0))
	map_root.add_child(decoy)
	decoy.global_position = Vector3(0.0, 0.0, 12.0)
	var parent_scale := map_root.global_basis.get_scale()
	decoy.scale = Vector3(1.0 / parent_scale.x,
		1.0 / parent_scale.y, 1.0 / parent_scale.z)
	var previous_x: float = decoy.global_position.x
	for _frame in 60:
		await get_tree().physics_frame
		var current_x: float = decoy.global_position.x
		_check(current_x + 0.0005 >= previous_x,
			"scaled-map deployment reversed during forward movement")
		previous_x = current_x
	var global_scale: Vector3 = decoy.global_basis.get_scale()
	_check(global_scale.is_equal_approx(Vector3.ONE),
		"map-root scale changed decoy collision/visual scale")
	_check(decoy.get_visual_facing_direction().dot(Vector3.RIGHT) > 0.99,
		"scaled-map deployment changed decoy visual facing")
	decoy.free()
	map_root.free()
	await get_tree().process_frame


func _test_toggle_control_is_monotonic() -> void:
	var decoy = _spawn_decoy(Vector3(0.0, 0.0, -5.0), Vector3.RIGHT)
	decoy.request_control_toggle(_owner)
	_check(decoy.control_active and not decoy.command_target.is_finite(),
		"one control press did not latch mirrored control")
	var stranger := MockOwner.new()
	stranger.team_id = 1
	add_child(stranger)
	decoy.request_control_toggle(stranger)
	_check(decoy.control_active,
		"a non-owner changed decoy control state")
	_owner.velocity = Vector3.BACK * 10.0
	var previous_z: float = decoy.global_position.z
	for _frame in 70:
		await get_tree().physics_frame
		var current_z: float = decoy.global_position.z
		_check(current_z + 0.0005 >= previous_z,
			"controlled decoy reversed while mirroring a steady input")
		previous_z = current_z
	_check(decoy.global_position.z > 2.0,
		"controlled decoy did not mirror the owner's direction")
	decoy.request_control_toggle(_owner)
	_check(not decoy.control_active and decoy.command_target.is_finite(),
		"second control press did not resume autonomous forward movement")
	_owner.velocity = Vector3.ZERO
	stranger.free()
	decoy.free()
	await get_tree().process_frame


func _test_collision_stop_has_no_reversal() -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 4.0, 5.0)
	collision.shape = shape
	wall.add_child(collision)
	wall.position = Vector3(3.0, 2.0, 4.0)
	add_child(wall)
	var decoy = _spawn_decoy(Vector3(0.0, 0.0, 4.0), Vector3.RIGHT)
	var previous_x: float = decoy.global_position.x
	for _frame in 100:
		await get_tree().physics_frame
		var current_x: float = decoy.global_position.x
		_check(current_x + 0.0005 >= previous_x,
			"decoy stepped backward while resolving a wall collision")
		previous_x = current_x
	_check(not decoy.command_target.is_finite(),
		"blocked autonomous command did not finish")
	_check(decoy.global_position.x < 2.6,
		"decoy penetrated its blocking wall")
	_check(decoy._visual_motion_speed <= decoy.MIN_MOVING_SPEED,
		"blocked decoy still reports locomotion speed")
	decoy.free()
	wall.free()
	await get_tree().process_frame


func _test_status_and_hazard_contracts() -> void:
	var enemy := MockOwner.new()
	enemy.team_id = 1
	enemy.actor_id = 99
	add_child(enemy)
	var decoy = _spawn_decoy(Vector3(12.0, 0.0, 4.0), Vector3.RIGHT)
	decoy.control_active = true
	_owner.velocity = Vector3.RIGHT * 10.0
	decoy.apply_slow(1.0, 0.5)
	for _frame in 45:
		await get_tree().physics_frame
	_check(decoy._slow_timer > 0.0 and is_equal_approx(decoy._slow_multiplier, 0.5),
		"trap slow did not persist on the decoy")
	_check(decoy._visual_motion_speed < 6.0,
		"procedural gait ignored the decoy's slowed resolved speed")
	decoy.apply_launch(11.0)
	_check(decoy.velocity.y >= 11.0,
		"spring-pad launch did not affect the decoy")
	_owner.velocity = Vector3.ZERO
	decoy.free()
	enemy.free()
	await get_tree().process_frame


func _test_combat_pop_rules() -> void:
	var original_teams: bool = GameConfig.teams_enabled
	var original_friendly_fire: bool = GameConfig.friendly_fire_enabled
	GameConfig.teams_enabled = true
	GameConfig.friendly_fire_enabled = false
	var teammate := MockOwner.new()
	teammate.team_id = _owner.team_id
	teammate.actor_id = 71
	add_child(teammate)
	var enemy := MockOwner.new()
	enemy.team_id = 1
	enemy.actor_id = 72
	add_child(enemy)
	var events_before := _elimination_events
	var decoy = _spawn_decoy(Vector3(20.0, 0.0, 0.0), Vector3.RIGHT)
	decoy.pop_from_attack(_owner, "gun")
	decoy.pop_from_attack(teammate, "gun")
	await get_tree().process_frame
	_check(is_instance_valid(decoy) and not decoy._popped,
		"owner or protected teammate destroyed its decoy")
	var bullet = load("res://bullet.tscn").instantiate()
	bullet.shooter = enemy
	add_child(bullet)
	bullet._on_body_entered(decoy)
	await get_tree().process_frame
	_check(not is_instance_valid(decoy), "enemy bullet did not pop the decoy")
	_check(not is_instance_valid(bullet), "bullet did not stop at its first decoy collision")
	_check(enemy.outline_count == 1,
		"enemy shooter did not receive exactly one 0.5-second reveal request")
	_check(_elimination_events == events_before,
		"decoy pop emitted a player-elimination scoring event")
	var player_source := FileAccess.get_file_as_string("res://character_body_3d.gd")
	var bot_source := FileAccess.get_file_as_string("res://dummy.gd")
	_check(not player_source.contains("mat.grow = true") \
		and not bot_source.contains("mat.grow = true"),
		"decoy shooter reveal still uses the scale-dependent expanded shell")
	_check(player_source.contains("_restore_outline_after_temporary_reveal"),
		"local player decoy reveal has no explicit overlay cleanup")
	var trap_decoy = _spawn_decoy(Vector3(24.0, 0.0, 0.0), Vector3.RIGHT)
	trap_decoy.pop_from_attack(enemy, "bear_trap")
	await get_tree().process_frame
	_check(not is_instance_valid(trap_decoy), "bear trap did not pop the decoy")
	_check(enemy.outline_count == 1,
		"non-gun trap incorrectly revealed its owner")
	teammate.free()
	enemy.free()
	GameConfig.teams_enabled = original_teams
	GameConfig.friendly_fire_enabled = original_friendly_fire


func _test_single_decoy_owner_death_and_lifetime() -> void:
	var first = _spawn_decoy(Vector3(28.0, 0.0, 0.0), Vector3.RIGHT)
	var second = _spawn_decoy(Vector3(30.0, 0.0, 0.0), Vector3.RIGHT)
	await get_tree().process_frame
	_check(not is_instance_valid(first) and _owner.active_decoy == second,
		"deploying a replacement did not remove the owner's old decoy")
	_owner.is_eliminated = true
	await get_tree().physics_frame
	await get_tree().process_frame
	_check(not is_instance_valid(second),
		"decoy survived its owner's elimination")
	_owner.is_eliminated = false
	var short_lived = _spawn_decoy(Vector3(32.0, 0.0, 0.0), Vector3.RIGHT, 0.1)
	await get_tree().create_timer(0.16).timeout
	await get_tree().process_frame
	_check(not is_instance_valid(short_lived),
		"authoritative decoy lifetime did not end in a pop")


func _test_bot_target_parity() -> void:
	var original_teams: bool = GameConfig.teams_enabled
	GameConfig.teams_enabled = false
	var decoy = _spawn_decoy(Vector3(36.0, 0.0, 0.0), Vector3.RIGHT)
	var bot = load("res://DummyModel.tscn").instantiate()
	bot.position = Vector3(35.0, 0.0, 0.0)
	add_child(bot)
	bot.set_physics_process(false)
	bot._update_target(0.0)
	_check(bot.target_player == decoy,
		"bot target selection distinguished the decoy from a player target")
	bot.free()
	decoy.free()
	GameConfig.teams_enabled = original_teams
	await get_tree().process_frame


func _test_network_snapshot_does_not_extrapolate() -> void:
	var decoy = _spawn_decoy(Vector3(40.0, 0.0, 0.0), Vector3.RIGHT)
	decoy.set_physics_process(false)
	var first_target: Transform3D = decoy.global_transform
	first_target.origin.x = 42.0
	decoy._receive_network_snapshot(first_target, Vector3.RIGHT * 10.0)
	var second_target: Transform3D = first_target
	second_target.origin.x = 44.0
	decoy._receive_network_snapshot(second_target, Vector3.RIGHT * 10.0)
	var previous_x: float = decoy.global_position.x
	for _frame in 120:
		decoy._follow_network_snapshot(1.0 / 120.0)
		var current_x: float = decoy.global_position.x
		_check(current_x + 0.0001 >= previous_x,
			"network follower corrected backward toward a snapshot")
		_check(current_x <= second_target.origin.x + 0.0001,
			"network follower extrapolated past the authoritative snapshot")
		previous_x = current_x
	_check(decoy.global_position.x > 43.9,
		"network follower did not converge on the authoritative snapshot")
	var control_before: bool = decoy.control_active
	decoy.apply_online_action("toggle_control", {})
	_check(decoy.control_active != control_before,
		"network action did not toggle decoy control")
	decoy.apply_online_action("slow", {"duration": 2.0, "multiplier": 0.5})
	_check(decoy._slow_timer >= 2.0 and is_equal_approx(decoy._slow_multiplier, 0.5),
		"network action did not apply decoy slow state")
	await get_tree().create_timer(0.4).timeout
	decoy.apply_online_action("launch", {"velocity": 12.0})
	_check(decoy.velocity.y >= 12.0,
		"network action did not apply decoy launch state")
	decoy.apply_online_action("pop", {})
	await get_tree().create_timer(0.7).timeout
	_check(not is_instance_valid(decoy),
		"network pop action did not remove the decoy")
