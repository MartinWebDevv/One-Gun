extends SceneTree

## Runs against an exported PCK before Butler publication. Dynamic resource
## paths are intentionally represented here because Godot cannot discover all
## of them by following static scene dependencies alone.

const REQUIRED_RESOURCES: Array[Dictionary] = [
	{"path": "res://main_menu.tscn", "type": "PackedScene"},
	{"path": "res://game_setup.tscn", "type": "PackedScene"},
	{"path": "res://player.tscn", "type": "PackedScene"},
	{"path": "res://models/player_v2/player_v2_visual.tscn", "type": "PackedScene"},
	{"path": "res://models/player_v2/femaleOGCat/female_player_v2_visual.tscn", "type": "PackedScene"},
	{"path": "res://models/player_v2/femaleOGCat/femaleOGCatRigged.glb", "type": "PackedScene"},
	{"path": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color black BOOBA corrected.png", "type": "Texture2D"},
	{"path": "res://UI/assets/character_portraits/female/black.png", "type": "Texture2D"},
	{"path": "res://models/player_v2/animations/Idle.fbx", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/victory_moves/podium/backbeat_bounce.fbx", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/victory_moves/podium/champion_canter.fbx", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/victory_moves/podium/fresh_footwork.fbx", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/victory_moves/podium/house_party_heat.fbx", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/victory_moves/podium/midnight_monster.fbx", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/victory_moves/podium/serpent_flow.fbx", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/victory_moves/podium/victory_wave.fbx", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/victory_moves/round/arena_clapline.fbx", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/victory_moves/round/birdie_boogie.fbx", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/victory_moves/round/breakspin_finale.fbx", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/victory_moves/round/floorwork_finish.fbx", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/victory_moves/round/quickstep_shuffle.fbx", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/victory_moves/round/soul_cyclone.fbx", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/victory_moves/round/victory_swing.fbx", "type": "PackedScene"},
	{"path": "res://models/menu/TrophyPedestal.glb", "type": "PackedScene"},
	{"path": "res://audio/ui/winners_circle_ceremony.wav", "type": "AudioStream"},
	{"path": "res://audio/ui/winners_circle_themes/neon_victory.wav", "type": "AudioStream"},
	{"path": "res://audio/ui/winners_circle_themes/western_toybox.wav", "type": "AudioStream"},
	{"path": "res://audio/ui/winners_circle_themes/grand_arena.wav", "type": "AudioStream"},
	{"path": "res://audio/ui/winners_circle_themes/pixel_champion.wav", "type": "AudioStream"},
	{"path": "res://audio/ui/winners_circle_themes/champion_groove.wav", "type": "AudioStream"},
	{"path": "res://audio/ui/winners_circle_themes/deep_orbit.wav", "type": "AudioStream"},
	{"path": "res://UI/MainMenu/OneGunLogoV2.png", "type": "Texture2D"},
	{"path": "res://UI/MainMenu/TaglineRibbon.png", "type": "Texture2D"},
	{"path": "res://UI/assets/character_portraits/green.png", "type": "Texture2D"},
	{"path": "res://UI/map_thumbnails/whispering_woods.png", "type": "Texture2D"},
	{"path": "res://UI/map_thumbnails/western_town.png", "type": "Texture2D"},
	{"path": "res://UI/map_thumbnails/maple_and_3rd.png", "type": "Texture2D"},
	{"path": "res://UI/map_thumbnails/cat_tower.png", "type": "Texture2D"},
	{"path": "res://audio/MainMenu.wav", "type": "AudioStream"},
	{"path": "res://UI/player_hub_overlay.gd", "type": "Script"},
	{"path": "res://UI/themed_locker_overlay.gd", "type": "Script"},
	{"path": "res://UI/progression_capture_fixture.gd", "type": "Script"},
	{"path": "res://UI/progression_road_overlay.gd", "type": "Script"},
	{"path": "res://supabase/one_gun_catalog.gd", "type": "Script"},
	{"path": "res://match_reward_calculator.gd", "type": "Script"},
	{"path": "res://maps/test/ForestMap.tscn", "type": "PackedScene"},
	{"path": "res://maps/test/WesternV2Map.tscn", "type": "PackedScene"},
	{"path": "res://maps/test/CityMap.tscn", "type": "PackedScene"},
	{"path": "res://maps/test/catTower.tscn", "type": "PackedScene"},
	{"path": "res://maps/test/TrippyMountainsMap.tscn", "type": "PackedScene"},
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var failures: Array[String] = []
	for requirement in REQUIRED_RESOURCES:
		var path := str(requirement["path"])
		var expected_type := str(requirement["type"])
		var resource := ResourceLoader.load(
			path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource == null:
			failures.append("%s did not load" % path)
		elif not resource.is_class(expected_type):
			failures.append(
				"%s loaded as %s instead of %s" % [
					path, resource.get_class(), expected_type])

	if not failures.is_empty():
		for failure in failures:
			push_error("CLIENT_PACKAGE_VALIDATION: %s" % failure)
		quit(1)
		return

	print("CLIENT_PACKAGE_VALIDATION_OK resources=%d" % REQUIRED_RESOURCES.size())
	quit(0)
