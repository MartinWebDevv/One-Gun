extends Node

class MockFireActor:
	extends Node3D
	var is_eliminated := false

var failures: Array[String] = []


func _ready() -> void:
	GameConfig.game_mode = GameConfig.MODE_ALL_GUN
	GameConfig.split_screen_enabled = false
	GameConfig.bot_configs = [{"difficulty": "easy", "team_id": -1}]
	GameConfig.round_time_limit = 999.0
	GameConfig.overtime_fire_exposure_time = 5.0
	var arena = load("res://maps/test/CityMap.tscn").instantiate()
	add_child(arena)
	var manager = arena.get_node_or_null("RoundManager")
	_check(manager != null, "CityMap did not provide a RoundManager")
	if manager == null:
		_finish()
		return
	var deadline := Time.get_ticks_msec() + 12000
	while manager.round_state != "live" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(manager.round_state == "live", "All Gun round never became live")
	GameConfig.round_time_limit = 0.01
	manager.round_elapsed = 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	_check(manager.overtime_active, "All Gun did not enter overtime")
	_check(manager._storm_wall != null and is_instance_valid(manager._storm_wall),
		"All Gun overtime did not create its fire field")
	var fire_actor := MockFireActor.new()
	add_child(fire_actor)
	fire_actor.global_position = manager._overtime_center + Vector3(
		manager._overtime_start_extents.x + 1.0, 0.0, 0.0)
	var warning: Dictionary = manager.get_fire_warning(fire_actor)
	_check(bool(warning.get("active", false))
		and is_zero_approx(float(warning.get("limit", -1.0))),
		"All Gun overtime is not immediate sudden death in fire")
	fire_actor.free()
	var opening_radius: float = manager._current_storm_radius()
	manager.overtime_elapsed = 1.0
	var moving_radius: float = manager._current_storm_radius()
	_check(moving_radius < opening_radius,
		"All Gun overtime fire did not start moving immediately")

	# Reproduce the online race: a sudden-death elimination stops combat before
	# the 1.5-second banner timer expires. The stale OT label must still clear.
	manager.online_round_epoch = 77
	manager.online_announcement = "OVERTIME - SUDDEN DEATH"
	manager.online_combat_live = false
	manager._clear_online_overtime_banner()
	await get_tree().create_timer(1.6).timeout
	_check(manager.online_announcement == "",
		"All Gun overtime banner stayed stuck after combat stopped")
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("ALL GUN OVERTIME VALIDATION: PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("ALL GUN OVERTIME VALIDATION: " + failure)
	get_tree().quit(1)
