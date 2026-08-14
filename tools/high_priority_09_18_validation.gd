extends Node

const BuildInfo = preload("res://build_info.gd")
const MatchLimitsData = preload("res://match_limits.gd")
const SmokeCloud = preload("res://smoke_cloud.gd")
const HitMarker = preload("res://hit_marker.gd")
const RoundManagerScript = preload("res://round_manager.gd")
const GameSetupScript = preload("res://game_setup.gd")
const PowerupScene = preload("res://powerup.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_validate_capacity_and_teams()
	_validate_authored_maps()
	_validate_identity_and_feedback()
	_validate_smoke_rules()
	_validate_build_metadata()
	_validate_stable_actions()
	_validate_pickup_supply_and_random_map()
	if _failures.is_empty():
		print("HIGH PRIORITY 09-18 VALIDATION: PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("HIGH PRIORITY 09-18 VALIDATION: " + failure)
		get_tree().quit(1)


func _validate_capacity_and_teams() -> void:
	_check(MatchLimitsData.MAX_TOTAL_ACTORS == 10, "global actor limit is not ten")
	_check(GameConfig.team_count >= 2 and GameConfig.team_count <= 4, "team count escaped the two-to-four range")
	_check(GameConfig.local_player_teams.size() >= 2, "local players do not have independent team assignments")
	_check(not GameConfig.sprinting_enabled, "sprinting is enabled by default")
	var fields: Array = GameConfig.PRESET_FIELDS
	for required in ["teams_enabled", "friendly_fire_enabled", "team_count", "local_player_teams", "gun_spawn_mode", "sprinting_enabled"]:
		_check(required in fields, "preset data omits %s" % required)


func _validate_authored_maps() -> void:
	for map_index in MapRegistry.map_count():
		var map_data: Dictionary = MapRegistry.get_map(map_index)
		var source := FileAccess.get_file_as_string(str(map_data.get("scene_path", "")))
		var player_spawns := source.count('groups=["spawn_point"]')
		var gun_spawns := source.count('groups=["gun_spawn_point"]')
		var melee_spawns := source.count('groups=["melee_spawn_point"]')
		var item_spawns := source.count('groups=["item_spawn_point"]')
		var powerup_spawns := source.count('groups=["powerup_spawn_point"]')
		var map_name := str(map_data.get("name", "Map %d" % map_index))
		_check(player_spawns >= 10, "%s has only %d player spawn markers" % [map_name, player_spawns])
		_check(gun_spawns >= 5, "%s has only %d random gun markers" % [map_name, gun_spawns])
		_check(melee_spawns >= 1, "%s has no melee spawn markers" % map_name)
		_check(item_spawns >= 1, "%s has no item spawn markers" % map_name)
		_check(powerup_spawns >= 1, "%s has no powerup spawn markers" % map_name)


func _validate_identity_and_feedback() -> void:
	_check(GameEvents.has_signal("actor_eliminated"), "actor-keyed elimination signal is missing")
	_check(GameEvents.has_signal("actor_disarmed"), "actor-keyed disarm signal is missing")
	_check(GameEvents.has_signal("actor_gun_picked_up"), "actor-keyed pickup signal is missing")
	_check(GameEvents.has_signal("actor_melee_hit_landed"), "actor-keyed melee signal is missing")
	_check(GameEvents.has_signal("actor_combat_feedback"), "actor-keyed hit feedback signal is missing")
	var marker = HitMarker.new()
	marker.filter_actor_id = 7
	_check(marker.filter_actor_id == 7, "hit markers cannot filter duplicate names by actor ID")
	marker.free()


func _validate_smoke_rules() -> void:
	var cloud = SmokeCloud.new()
	cloud.position = Vector3.ZERO
	add_child(cloud)
	cloud.current_radius = 5.0
	_check(is_equal_approx(cloud.cloud_radius, 5.0), "smoke full radius is not five units")
	_check(is_equal_approx(cloud.cloud_half_height, 4.2), "smoke cover is not using the raised vertical profile")
	_check(is_equal_approx(cloud.expand_time, 1.5), "smoke expansion is not 1.5 seconds")
	_check(is_equal_approx(cloud.collapse_time, 1.5), "smoke collapse is not 1.5 seconds")
	_check(cloud.blocks_segment(Vector3(-5, 0, 0), Vector3(5, 0, 0)), "smoke does not block a sight line through its center")
	_check(cloud.blocks_segment(Vector3(-4, 4.0, 0), Vector3(4, 4.0, 0)), "smoke does not conceal across its raised profile")
	_check(not cloud.blocks_segment(Vector3(-4, 4.5, 0), Vector3(4, 4.5, 0)), "smoke concealment extends above its raised profile")
	_check(not cloud.blocks_segment(Vector3(-5, 6, 0), Vector3(5, 6, 0)), "smoke blocks a sight line outside its radius")
	cloud.free()


func _validate_build_metadata() -> void:
	_check(BuildInfo.GAME_VERSION == "0.0.4", "build metadata does not match the current release")
	_check(BuildInfo.NETWORK_PROTOCOL > 0, "network protocol has no explicit version")
	_check(BuildInfo.build_id() != "", "build identifier is empty")
	_check(BuildInfo.compatibility_payload().get("build_id", "") == BuildInfo.build_id(),
		"compatibility payload omits the build identifier")
	_check(BuildInfo.summary().contains(BuildInfo.build_id()),
		"server summary omits the build identifier")
	_check(BuildInfo.footer_text().contains(BuildInfo.build_id()),
		"client footer omits the build identifier")
	_check(BuildInfo.compatibility_error(BuildInfo.compatibility_payload()) == "", "matching builds reject each other")
	_check(BuildInfo.host_compatibility_error(BuildInfo.compatibility_payload()) == "", "host rejects a matching client build")
	var mismatch := BuildInfo.compatibility_payload()
	mismatch["protocol"] = BuildInfo.NETWORK_PROTOCOL + 1
	var rejection := BuildInfo.compatibility_rejection(mismatch)
	_check(str(rejection.get("reason", "")) == BuildInfo.REJECTION_NETWORK_PROTOCOL,
		"protocol mismatch does not return a structured rejection reason")
	_check(BuildInfo.compatibility_error(mismatch) != "", "protocol mismatch is accepted")
	var host_error := BuildInfo.host_compatibility_error(mismatch)
	_check(host_error.contains("Host: %d" % BuildInfo.NETWORK_PROTOCOL), "host-side rejection swaps the host and client protocol labels")
	var version_mismatch := BuildInfo.compatibility_payload()
	version_mismatch["game_version"] = "0.0.0-test"
	_check(str(BuildInfo.compatibility_rejection(version_mismatch).get("reason", "")) == BuildInfo.REJECTION_GAME_VERSION,
		"game-version mismatch does not return a structured rejection reason")
	var player_message := BuildInfo.version_mismatch_message(host_error)
	_check(player_message.contains("Restart the game to download the newest update."),
		"version mismatch omits the player update instruction")
	var different_build := BuildInfo.compatibility_payload()
	different_build["build_id"] = "dev-different"
	_check(BuildInfo.compatibility_error(different_build) == "",
		"commit build IDs are incorrectly treated as network incompatibility")
	var notes := BuildInfo.load_latest_release()
	_check(str(notes.get("version", "")) == BuildInfo.GAME_VERSION, "release notes version does not match the game")
	var categories: Dictionary = notes.get("categories", {})
	for category in ["Added", "Improved", "Fixed", "Removed", "Misc"]:
		_check(categories.has(category), "release notes omit %s" % category)


func _validate_stable_actions() -> void:
	var pause_source := FileAccess.get_file_as_string("res://pause_menu.gd")
	var lobby_source := FileAccess.get_file_as_string("res://game_setup.gd")
	var recovery_source := FileAccess.get_file_as_string("res://online_load_overlay.gd")
	var bot_source := FileAccess.get_file_as_string("res://dummy.gd")
	for action_id in ["resume", "player_settings", "return_lobby", "leave_match", "return_waiting_room"]:
		_check(pause_source.contains('"%s"' % action_id), "pause menu omits stable action %s" % action_id)
	for action_id in ["start_match", "ready", "spectate_match", "cancel_start", "starting_countdown"]:
		_check(lobby_source.contains('"%s"' % action_id), "lobby omits stable action %s" % action_id)
	for action_id in ["retry_load", "remove_failed_load", "return_lobby"]:
		_check(recovery_source.contains('"%s"' % action_id), "load recovery omits stable action %s" % action_id)
	_check(bot_source.contains("item_throw_decision_timer"), "bot item decisions are still tied to render frames")


func _validate_pickup_supply_and_random_map() -> void:
	_check(GameEvents.has_signal("melee_marker_refill_requested"),
		"local melee refill request is missing from the event bus")
	_check(GameEvents.has_signal("item_marker_refill_requested"),
		"local item refill request is missing from the event bus")
	_check(is_equal_approx(RoundManagerScript.MELEE_MARKER_REFILL_TIME, 5.0),
		"melee marker refill is not five seconds")
	_check(is_equal_approx(RoundManagerScript.PICKUP_MARKER_REFILL_TIME, 8.0),
		"item/powerup marker refill is not eight seconds")
	var round_source := FileAccess.get_file_as_string("res://round_manager.gd").replace("\r\n", "\n")
	_check(round_source.contains("for marker in markers:\n\t\t_spawn_local_melee_at"),
		"local rounds do not populate every melee marker")
	_check(round_source.contains("for i in markers.size():\n\t\tvar marker = markers[i]"),
		"online rounds do not build one melee assignment per marker")
	_check(round_source.contains('for marker in get_tree().get_nodes_in_group("item_spawn_point")'),
		"local rounds do not populate every item marker")
	_check(round_source.contains('for m in get_tree().get_nodes_in_group("powerup_spawn_point")'),
		"local rounds do not populate every powerup marker")
	var powerup = PowerupScene.instantiate()
	_check(is_equal_approx(powerup.respawn_time, 8.0),
		"powerup scene does not use the eight-second refill")
	powerup.free()
	_check(GameSetupScript.RANDOM_MAP_SENTINEL != "",
		"online random-map selection has no hidden lobby sentinel")
	_check(GameSetupScript.RIGHT_WIDTH >= 400.0,
		"full-size lobby roster is still too narrow for team controls")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
