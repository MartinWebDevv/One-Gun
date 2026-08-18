extends Node

# Fast, deterministic contract checks for the 2026-08-06 gameplay packet.
# Feel/composition still require a rendered playtest, but these assertions catch
# accidental tuning, registry, map-marker, and serialization regressions.

const PlayerScript = preload("res://character_body_3d.gd")
const MeleeScript = preload("res://melee_weapon.gd")
const GrenadeBlast = preload("res://grenade_explosion.gd")
const SmokeCloud = preload("res://smoke_cloud.gd")
const SpringPad = preload("res://spring_pad_deployed.gd")
const HydrantWaterPushScript = preload("res://hydrant_water_push.gd")
const FlashCamera = preload("res://flash_camera.gd")
const FlashBlindOverlayScript = preload("res://flash_blind_overlay.gd")
const DummyScript = preload("res://dummy.gd")
const RoundManagerScript = preload("res://round_manager.gd")
const SpectatorScript = preload("res://spectator_controller.gd")
const OnlineHUDScript = preload("res://online_hud.gd")
const PlayerHUDScript = preload("res://player_ui_container.gd")
const CombatPopScript = preload("res://combat_pop.gd")
const CrosshairScript = preload("res://UI/crosshair_renderer.gd")
const LobbySettingsScript = preload("res://UI/lobby_settings_slideout.gd")

var _failures: Array[String] = []

func _ready() -> void:
	_validate_config_and_reach()
	_validate_movement_and_flash_presentation()
	_validate_items()
	_validate_maps_and_view_scoping()
	_validate_spectator_bot_hud()
	_validate_reach_and_spawn_pools()
	if _failures.is_empty():
		print("GAMEPLAY PACKET VALIDATION: PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("GAMEPLAY PACKET VALIDATION: " + failure)
		get_tree().quit(1)

func _validate_config_and_reach() -> void:
	_check(not ("visible_hitboxes" in GameConfig.PRESET_FIELDS),
		"testing hitboxes leaked into disk preset fields")
	_check(GameConfig.snapshot_for_lobby().has("visible_hitboxes"),
		"testing hitboxes are missing from lobby/network snapshots")
	_check(GameConfig.ITEM_SCENES.get("flash_camera", "") == "res://flash_camera.tscn",
		"Flash Camera is missing from the item scene registry")
	_check(is_equal_approx(GameConfig.REACH_POWERUP_DISTANCE, 7.0),
		"shared Reach powerup distance is not 7m")
	_check(is_equal_approx(PlayerScript.REACH_PICKUP_RADIUS, 7.0),
		"human Reach pickup radius is not 7m")
	_check(is_equal_approx(DummyScript.REACH_PICKUP_RADIUS, 7.0),
		"bot Reach pickup radius is not 7m")
	_check(is_equal_approx(MeleeScript.POWERUP_MELEE_MAX_HIT_DISTANCE, 7.0),
		"Reach melee hit limit is not 7m")
	_check(is_equal_approx(MeleeScript.DEFAULT_MELEE_HITBOX_LENGTH, 5.2),
		"universal melee hit limit is not 5.2m")
	_check(is_equal_approx(MeleeScript.ONE_OF_US_MELEE_HITBOX_LENGTH, 5.2),
		"One of Us did not inherit the universal 5.2m melee limit")
	_check(is_equal_approx(PlayerScript.SPRING_AIR_CONTROL, 0.60),
		"human spring air steering is not 60 percent")
	_check(is_equal_approx(DummyScript.SPRING_AIR_CONTROL, 0.60),
		"bot spring air steering is not 60 percent")
	for path in ["res://gun.gd", "res://melee_weapon.gd", "res://item.gd", "res://round_manager.gd"]:
		_check(FileAccess.get_file_as_string(path).contains("GameConfig.REACH_POWERUP_DISTANCE"),
			"%s does not use the shared authoritative Reach distance" % path)
	var player_source := FileAccess.get_file_as_string("res://character_body_3d.gd")
	_check(not player_source.contains("jump_landing_cooldown") \
		and not player_source.contains("_jump_cooldown_remaining"),
		"human jumping still contains a post-landing timer gate")

func _validate_movement_and_flash_presentation() -> void:
	var player = PlayerScript.new()
	player._spring_air_active = true
	player._spring_direction_window = 0.8
	player._spring_boost_committed = true
	player.velocity = Vector3(3.0, 13.0, -2.0)
	player._cancel_spring_launch_for_dash()
	_check(player.velocity.is_zero_approx(),
		"human spring-to-dash transition leaves pad momentum active")
	_check(not player._spring_air_active and not player._spring_boost_committed,
		"human spring-to-dash transition does not clear pad state")
	var water_velocity := Vector3(0.0, 12.0, -8.0)
	player.velocity = Vector3(0.0, 7.0, 10.0)
	player.apply_directional_launch(water_velocity)
	_check(player.velocity.is_equal_approx(Vector3(0.0, 12.0, -5.5)) \
		and player._spring_air_active and player._spring_boost_committed,
		"human head-on water launch does not reverse opposing momentum")
	player.velocity = Vector3(6.0, 7.0, 0.0)
	player.apply_directional_launch(water_velocity)
	_check(player.velocity.is_equal_approx(Vector3(6.0, 12.0, -8.0)),
		"human cross-stream water launch does not preserve lateral momentum")
	player.velocity = Vector3(0.0, 7.0, -10.0)
	player.apply_directional_launch(water_velocity)
	_check(player.velocity.is_equal_approx(Vector3(0.0, 12.0, -18.0)),
		"human with-stream water launch does not retain forward momentum")
	player.velocity = Vector3(6.0, 12.0, 4.0)
	player._enforce_directional_launch_minimum()
	_check(player.velocity.is_equal_approx(Vector3(6.0, 12.0, -3.2)),
		"human opposing air input can erase the minimum hydrant push")
	player.apply_flash_blind(6.0)
	var overlay = FlashBlindOverlayScript.new()
	overlay.set_player(player)
	_check(overlay.visible and is_equal_approx(overlay.color.a, 1.0),
		"Flash Camera does not start fully opaque")
	player.flash_blind_timer = 4.0
	overlay._update_from_player()
	_check(is_equal_approx(overlay.color.a, 1.0),
		"Flash Camera is not solid white for its first two seconds")
	player.flash_blind_timer = 2.0
	overlay._update_from_player()
	_check(is_equal_approx(overlay.color.a, 0.5),
		"Flash Camera does not fade over the post-white duration")
	overlay.free()
	player.free()

	var bot = DummyScript.new()
	bot._spring_air_active = true
	bot.velocity = Vector3(-3.0, 13.0, 2.0)
	bot._cancel_spring_launch_for_dash()
	_check(bot.velocity.is_zero_approx() and not bot._spring_air_active,
		"bot spring-to-dash transition leaves pad momentum active")
	bot.velocity = Vector3(0.0, 7.0, 10.0)
	bot.apply_directional_launch(water_velocity)
	_check(bot.velocity.is_equal_approx(Vector3(0.0, 12.0, -5.5)) \
		and bot._spring_air_active and bot._spring_boost_committed,
		"bot head-on water launch does not reverse opposing momentum")
	bot.velocity = Vector3(6.0, 7.0, 0.0)
	bot.apply_directional_launch(water_velocity)
	_check(bot.velocity.is_equal_approx(Vector3(6.0, 12.0, -8.0)),
		"bot cross-stream water launch does not preserve lateral momentum")
	bot.velocity = Vector3(6.0, 12.0, 4.0)
	bot._enforce_directional_launch_minimum()
	_check(bot.velocity.is_equal_approx(Vector3(6.0, 12.0, -3.2)),
		"bot opposing movement can erase the minimum hydrant push")
	bot.apply_flash_blind(3.0)
	_check(is_equal_approx(bot._flash_blind_total, 3.0),
		"bot spectator flash HUD does not retain the full flash duration")
	bot.free()

	var player_source := FileAccess.get_file_as_string("res://character_body_3d.gd")
	_check(player_source.contains(
		"lerpf(velocity.x, direction.x * current_speed, SPRING_AIR_CONTROL)"),
		"human spring steering is not applying the configured 60 percent blend")
	_check(player_source.contains(
		"_dash_cancelled_spring_momentum = _spring_air_active and not is_on_floor()"),
		"human dash start is not bound to spring momentum cancellation")
	var bot_source := FileAccess.get_file_as_string("res://dummy.gd")
	_check(bot_source.contains(
		"_dash_cancelled_spring_momentum = _spring_air_active and not is_on_floor()"),
		"bot dash start is not bound to spring momentum cancellation")

	var melee = (load("res://melee_weapon.tscn") as PackedScene).instantiate()
	var shape_node: CollisionShape3D = melee.get_node("HitBox/CollisionShape3D")
	melee._apply_powerup_reach(true)
	var powered_depth := (shape_node.shape as BoxShape3D).size.z
	var powered_axis := shape_node.transform.basis.z.normalized()
	var powered_center := absf(shape_node.position.dot(powered_axis))
	_check(is_equal_approx(powered_depth, MeleeScript.POWERUP_MELEE_MAX_HIT_DISTANCE)
			and is_equal_approx(powered_center, MeleeScript.POWERUP_MELEE_MAX_HIT_DISTANCE * 0.5),
		"Reach does not stretch the physical melee hitbox to its powered distance")
	melee.free()

func _validate_items() -> void:
	var grenade = (load("res://grenade.tscn") as PackedScene).instantiate()
	_check(is_equal_approx(float(grenade.get("fuse_time")), 3.0),
		"grenade fuse is not three seconds")
	grenade.free()
	var blast = GrenadeBlast.new()
	_check(is_equal_approx(blast.radius, 7.5), "grenade blast radius is not 7.5m")
	blast.free()
	var smoke = SmokeCloud.new()
	_check(is_equal_approx(smoke.cloud_radius, 5.0), "smoke radius is not 5m")
	_check(is_equal_approx(smoke.cloud_half_height, 4.2), "smoke vertical profile is not 4.2m")
	smoke.free()
	var spring = SpringPad.new()
	_check(is_equal_approx(spring.launch_velocity, 13.0), "spring launch is not 13m/s")
	_check(is_equal_approx(spring.horizontal_boost, 4.0), "spring horizontal boost is not 4m/s")
	_check(is_equal_approx(spring.direction_window, 1.0), "spring direction window is not one second")
	spring.free()
	var launch_origin := Vector3(2.0, 0.0, 3.0)
	var launch_target := Vector3(2.0, 1.71, 2.0)
	var expected_jet_direction := (launch_target - launch_origin).normalized()
	_check(HydrantWaterPushScript.direction_between_points(
		launch_origin, launch_target).is_equal_approx(expected_jet_direction),
		"hydrant push does not follow its authored launch target")
	_check(is_equal_approx(FlashCamera.MAX_FLASH_DISTANCE, 30.0), "Flash Camera range is not 30m")
	_check(is_equal_approx(FlashCamera.MAX_CAMERA_CONE_DEGREES, 60.0), "Flash Camera cone is not 60 degrees")

func _validate_maps_and_view_scoping() -> void:
	for map_index in MapRegistry.map_count():
		var data: Dictionary = MapRegistry.get_map(map_index)
		var source := FileAccess.get_file_as_string(str(data.get("scene_path", "")))
		_check(source.contains('groups=["round_intro_camera_point"]'),
			"%s has no authored first-round intro point" % str(data.get("name", map_index)))
	var split_source := FileAccess.get_file_as_string("res://splitscreen_manager.gd")
	_check(split_source.contains("viewport_camera.cull_mask = source_camera.cull_mask"),
		"splitscreen does not preserve owner-only render layers")
	var local_hud_source := FileAccess.get_file_as_string("res://player_ui_container.gd")
	_check(local_hud_source.contains("FlashBlindOverlay.new()"),
		"flash blindness is not scoped to each local HUD viewport")

func _validate_spectator_bot_hud() -> void:
	# Bots intentionally do not expose the human-only `is_player2` property.
	# This reproduces the spectator HUD binding contract without starting a match.
	var bot_like := Node.new()
	var crosshair = CrosshairScript.new()
	crosshair.set_player(bot_like)
	_check(crosshair.player == bot_like, "spectator crosshair cannot bind to a bot")
	crosshair.free()
	bot_like.free()

func _validate_reach_and_spawn_pools() -> void:
	var player_source := FileAccess.get_file_as_string("res://character_body_3d.gd")
	var bot_source := FileAccess.get_file_as_string("res://dummy.gd")
	_check(not player_source.contains('bool(candidate.get("is_held"))'),
		"human Reach scan still converts missing pickup state through bool(null)")
	_check(not bot_source.contains('bool(candidate.get("is_held"))'),
		"bot Reach scan still converts missing pickup state through bool(null)")
	for field in ["powerups_enabled", "powerup_registry", "melee_weapon_registry"]:
		_check(field in GameConfig.PRESET_FIELDS,
			"spawn-pool field %s is missing from presets/network snapshots" % field)
	_check(GameConfig.POWERUP_TYPES.size() == 7,
		"collectible powerup registry does not cover all seven powerups")
	_check(GameConfig.MELEE_WEAPON_NAMES.size() == 5,
		"melee spawn registry does not cover all five weapons")
	var original := GameConfig.snapshot_for_lobby()
	var malformed := GameConfig.default_match_settings()
	for weapon_id in GameConfig.MELEE_WEAPON_NAMES:
		malformed["melee_weapon_registry"][weapon_id]["enabled"] = false
	GameConfig.apply_preset_values(malformed)
	_check(GameConfig.enabled_melee_weapon_count() == 1,
		"an empty melee pool was not repaired to the minimum of one")
	_check(MeleeWeaponRegistry.get_random_weapon_data().weapon_name == "Sword",
		"the repaired minimum melee pool did not constrain registry rolls")
	GameConfig.apply_lobby_values(original)
	var settings_source := FileAccess.get_file_as_string(
		"res://UI/lobby_settings_slideout.gd")
	for section_id in ["items", "powerups", "melee"]:
		_check(settings_source.contains('_add_spawn_pool_section("%s"' % section_id),
			"Spawns tab is missing the %s dropdown section" % section_id)
	var settings = LobbySettingsScript.new()
	settings.panel_kind = LobbySettingsScript.Kind.MATCH
	add_child(settings)
	settings._selected_tab = 2
	for section_id in settings._expanded_spawn_sections:
		settings._expanded_spawn_sections[section_id] = true
	settings._rebuild_body()
	for section_id in ["items", "powerups", "melee"]:
		_check(settings.find_child("SpawnPool_%s" % section_id, true, false) != null,
			"Spawns tab could not build its %s dropdown" % section_id)
	_check(settings.find_child("Master_items", true, false) != null,
		"Items dropdown has no master toggle")
	_check(settings.find_child("Master_powerups", true, false) != null,
		"Power Ups dropdown has no master toggle")
	_check(settings.find_child("Master_melee", true, false) == null,
		"Melee dropdown incorrectly received a pool master toggle")
	var items_section := settings.find_child("SpawnPool_items", true, false)
	var powerups_section := settings.find_child("SpawnPool_powerups", true, false)
	for item_type in GameConfig.ITEM_SCENES:
		var item_toggle := settings.find_child("Item_" + str(item_type), true, false)
		_check(item_toggle != null and items_section.is_ancestor_of(item_toggle),
			"Item %s is not inside the Items dropdown" % item_type)
		_check(settings.find_child("Powerup_" + str(item_type), true, false) == null,
			"Item %s leaked into the Power Ups dropdown" % item_type)
	for power_type in GameConfig.POWERUP_TYPES:
		var powerup_toggle := settings.find_child("Powerup_" + str(power_type), true, false)
		_check(powerup_toggle != null and powerups_section.is_ancestor_of(powerup_toggle),
			"Collectible powerup %s is not inside the Power Ups dropdown" % power_type)
	settings._pending["hazards_enabled"] = true
	settings._pending["consumables_enabled"] = true
	(settings.find_child("Master_items", true, false) as OneGunToggle).toggled.emit(false)
	_check(not bool(settings._pending["hazards_enabled"]) \
		and not bool(settings._pending["consumables_enabled"]),
		"Items master does not gate both legacy item categories")
	settings._pending["consumables_enabled"] = true
	settings._pending["powerups_enabled"] = true
	(settings.find_child("Master_powerups", true, false) as OneGunToggle).toggled.emit(false)
	_check(not bool(settings._pending["powerups_enabled"]) \
		and bool(settings._pending["consumables_enabled"]),
		"Power Ups master still changes consumable item state")
	settings.free()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
