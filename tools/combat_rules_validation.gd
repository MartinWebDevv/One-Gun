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

var failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	_test_projectile_and_gun()
	_test_protections_and_timers()
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
	_check(is_equal_approx(gun.projectile_speed, 200.0), "gun and projectile speed defaults differ")
	_check(is_equal_approx(gun.reload_time, 2.0), "reload default changed")
	_check(is_equal_approx(gun.loose_return_time, 5.0), "loose gun return is not five seconds")
	_check(gun.reload_time != gun.loose_return_time, "reload and loose-return tuning are coupled")
	bullet.free()
	gun.free()

func _test_protections_and_timers() -> void:
	var player = load("res://character_body_3d.gd").new()
	_check(player.apply_powerup("sticky_hands", 10.0), "Sticky Hands could not be collected")
	_check(player.apply_powerup("extra_life", 10.0), "Extra Life could not coexist with Sticky Hands")
	_check(not player.apply_powerup("sticky_hands", 10.0), "duplicate Sticky Hands was accepted")
	_check(not player.apply_powerup("extra_life", 10.0), "duplicate Extra Life was accepted")
	_check(player.apply_powerup("speed_surge", 10.0), "Speed Surge could not be collected")
	player.apply_powerup("speed_surge", 10.0)
	_check(is_equal_approx(player.speed_surge_timer, 15.0), "timed duplicate did not add half duration")
	player.apply_powerup("speed_surge", 10.0)
	player.apply_powerup("speed_surge", 10.0)
	_check(is_equal_approx(player.speed_surge_timer, 20.0), "timed powerup exceeded or missed 2x cap")
	_check(player.consume_extra_life(), "Extra Life did not consume")
	_check(is_equal_approx(player.lethal_immunity_timer, 1.0), "Extra Life immunity is not one second")
	player.clear_all_powerups()
	_check(player.melee_disarm_shields == 0 and not player.second_wind_ready,
		"full powerup clear left a protection behind")
	player.free()

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
	_check(decoy._bone_indices.size() == 7,
		"decoy procedural gait did not bind its required bones")
	_check(is_zero_approx(decoy._visual_root.position.x)
		and is_zero_approx(decoy._visual_root.position.z),
		"decoy visual root is displaced from its physics body")
	var imported_players: Array[Node] = decoy.find_children(
		"*", "AnimationPlayer", true, false)
	for node in imported_players:
		_check(not (node as AnimationPlayer).active,
			"an imported animation can still translate the rebuilt decoy")
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
