extends Node

const MatchLimitsData = preload("res://match_limits.gd")

var _failures: Array[String] = []


func _ready() -> void:
	print("PLAYER CAPACITY VALIDATION: boot")
	var original_split: bool = bool(GameConfig.split_screen_enabled)
	var original_bots: Array = GameConfig.bot_configs.duplicate(true)
	_check(MatchLimitsData.MAX_TOTAL_ACTORS == 10,
		"project actor capacity is not ten")
	_check(NetworkManager.MAX_PEERS == MatchLimitsData.MAX_TOTAL_ACTORS,
		"online peer capacity does not use MatchLimits")
	var setup_source := FileAccess.get_file_as_string("res://game_setup.gd")
	_check(setup_source.contains("const LOCAL_SLOT_CAP := MatchLimitsData.MAX_TOTAL_ACTORS"),
		"local lobby capacity does not use MatchLimits")
	_test_local_bot_caps()
	print("PLAYER CAPACITY VALIDATION: local caps complete")
	_test_map_capacities()
	print("PLAYER CAPACITY VALIDATION: map capacities complete")
	_test_roster_aware_map_selection()
	print("PLAYER CAPACITY VALIDATION: roster selection complete")
	GameConfig.split_screen_enabled = original_split
	GameConfig.bot_configs = original_bots
	if _failures.is_empty():
		print("PLAYER CAPACITY VALIDATION: PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("PLAYER CAPACITY VALIDATION: " + failure)
		get_tree().quit(1)


func _test_local_bot_caps() -> void:
	GameConfig.split_screen_enabled = false
	GameConfig.set_bot_count(99)
	_check(GameConfig.bot_count == 9,
		"solo play did not clamp to one human plus nine bots")
	GameConfig.split_screen_enabled = true
	GameConfig.set_bot_count(99)
	_check(GameConfig.bot_count == 8,
		"splitscreen did not clamp to two humans plus eight bots")
	_check(MatchLimitsData.max_bots_for_humans(10) == 0,
		"a full human lobby still allowed bots")
	_check(MatchLimitsData.max_bots_for_humans(4) == 6,
		"bots did not fill the six spaces after four humans")


func _test_map_capacities() -> void:
	for map_index in MapRegistry.map_count():
		var capacity := MapRegistry.get_player_capacity(map_index)
		_check(capacity == 10, "%s exposes %d usable player spawns instead of ten"
			% [MapRegistry.get_map(map_index).get("name", "Map %d" % map_index), capacity])
		var map_path := str(MapRegistry.get_map(map_index).get("scene_path", ""))
		var scene_source := FileAccess.get_file_as_string(map_path)
		var authored_spawn_count := 0
		for line in scene_source.split("\n"):
			if line.contains('groups=["spawn_point"]'):
				authored_spawn_count += 1
		_check(authored_spawn_count >= capacity,
			"%s declares capacity %d but authors only %d player spawns"
			% [MapRegistry.get_map(map_index).get("name", "Map %d" % map_index),
				capacity, authored_spawn_count])
	_check(MapRegistry.available_indices(10).size() == MapRegistry.map_count(),
		"ten-player rotation excluded a current game-ready map")
	_check(MapRegistry.available_indices(11).is_empty(),
		"map rotation accepted more than the global actor limit")


func _test_roster_aware_map_selection() -> void:
	GameConfig.split_screen_enabled = false
	GameConfig.set_bot_count(4)
	_check(1 + GameConfig.bot_count == 5,
		"local planned roster did not include the human and bots")
	_check(MapRegistry.available_indices(5).size() == MapRegistry.map_count(),
		"a five-actor roster cannot select every current map")
	_check(MapRegistry.available_indices(11).is_empty(),
		"an eleven-actor roster found an eligible map")
	GameConfig.set_bot_count(4)
	_check(not MapRegistry.available_indices(5).is_empty(),
		"random rotation could not select a map that fits the roster")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
