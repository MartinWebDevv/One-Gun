extends SceneTree

## Runs against an exported PCK before Butler publication. Dynamic resource
## paths are intentionally represented here because Godot cannot discover all
## of them by following static scene dependencies alone.

const REQUIRED_RESOURCES: Array[Dictionary] = [
	{"path": "res://main_menu.tscn", "type": "PackedScene"},
	{"path": "res://game_setup.tscn", "type": "PackedScene"},
	{"path": "res://player.tscn", "type": "PackedScene"},
	{"path": "res://models/player_v2/player_v2_visual.tscn", "type": "PackedScene"},
	{"path": "res://models/player_v2/animations/Idle.fbx", "type": "PackedScene"},
	{"path": "res://models/menu/TrophyPedestal.glb", "type": "PackedScene"},
	{"path": "res://UI/MainMenu/OneGunLogoV2.png", "type": "Texture2D"},
	{"path": "res://UI/MainMenu/TaglineRibbon.png", "type": "Texture2D"},
	{"path": "res://UI/assets/character_portraits/green.png", "type": "Texture2D"},
	{"path": "res://UI/map_thumbnails/whispering_woods.png", "type": "Texture2D"},
	{"path": "res://UI/map_thumbnails/western_town.png", "type": "Texture2D"},
	{"path": "res://UI/map_thumbnails/maple_and_3rd.png", "type": "Texture2D"},
	{"path": "res://UI/map_thumbnails/cat_tower.png", "type": "Texture2D"},
	{"path": "res://audio/MainMenu.wav", "type": "AudioStream"},
	{"path": "res://maps/test/ForestMap.tscn", "type": "PackedScene"},
	{"path": "res://maps/test/WesternV2Map.tscn", "type": "PackedScene"},
	{"path": "res://maps/test/CityMap.tscn", "type": "PackedScene"},
	{"path": "res://maps/test/catTower.tscn", "type": "PackedScene"},
]


func _initialize() -> void:
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
