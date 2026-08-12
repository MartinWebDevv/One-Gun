class_name MapRegistry
extends Object

const MatchLimitsData = preload("res://match_limits.gd")

# ============================================================
# MapRegistry — the single metadata source for every playable map
# (packet Phase 2: map info must be data-driven, never hard-coded
# UI strings). game_setup.MAPS re-exports this array, so existing
# consumers (menu_map_cycler, lobby_map_preview) keep working.
#
# Metadata only — map scenes themselves are never touched here.
# "tint" is the placeholder card color used until a live preview
# thumbnail has been captured for that map.
# ============================================================

const MAPS := [
	{
		"name": "Whispering Woods",
		"scene_path": "res://maps/test/ForestMap.tscn",
		"thumbnail_path": "res://UI/map_thumbnails/whispering_woods.png",
		"description": "Quiet paths, hidden routes, and perfect ambushes beneath the pines.",
		"size": "Medium",
		"recommended_players": "4–8",
		"player_capacity": 10,
		"playstyle": "Mixed",
		"hazards": true,
		"tint": Color(0.16, 0.32, 0.20),
	},
	{
		"name": "Western Town",
		"scene_path": "res://maps/test/WesternV2Map.tscn",
		"thumbnail_path": "res://UI/map_thumbnails/western_town.png",
		"description": "Dusty streets and long sightlines — win the draw or find cover fast.",
		"size": "Medium",
		"recommended_players": "2–6",
		"player_capacity": 10,
		"playstyle": "Duels & sightlines",
		"hazards": true,
		"tint": Color(0.35, 0.26, 0.14),
	},
	{
		"name": "Gun Square",
		"scene_path": "res://maps/test/CityMap.tscn",
		"thumbnail_path": "res://UI/map_thumbnails/maple_and_3rd.png",
		"description": "A dense city block with rooftops, alleys, and vertical escapes.",
		"size": "Large",
		"recommended_players": "4–10",
		"player_capacity": 10,
		"playstyle": "Urban & vertical",
		"hazards": true,
		"tint": Color(0.20, 0.22, 0.34),
	},
	{
		"name": "Cat Tower",
		"scene_path": "res://maps/test/catTower.tscn",
		"thumbnail_path": "res://UI/map_thumbnails/cat_tower.png",
		"description": "Tiny fighters scramble through a towering cat playground while giant spectators watch.",
		"size": "Large",
		"recommended_players": "2–8",
		"player_capacity": 10,
		"playstyle": "Vertical scramble",
		"hazards": true,
		"tint": Color(0.34, 0.16, 0.30),
		"preview_center": Vector3(-89.67, 7.69, -126.75),
		"preview_radius": 46.0,
		"preview_angle": 1.62,
		"preview_height_ratio": 0.75,
		"preview_target_height_ratio": 0.06,
	},
]


static func map_count() -> int:
	return MAPS.size()


static func get_map(index: int) -> Dictionary:
	if index < 0 or index >= MAPS.size():
		return {}
	return MAPS[index]


static func find_index_by_path(scene_path: String) -> int:
	for index in MAPS.size():
		if str(MAPS[index].get("scene_path", "")) == scene_path:
			return index
	return -1


static func is_scene_available(index: int) -> bool:
	var map_data := get_map(index)
	if map_data.is_empty():
		return false
	var scene_path := str(map_data.get("scene_path", ""))
	return scene_path != "" and ResourceLoader.exists(scene_path)


static func available_indices(required_actor_count: int = 1) -> Array[int]:
	var result: Array[int] = []
	for index in MAPS.size():
		if is_scene_available(index) and get_player_capacity(index) >= required_actor_count:
			result.append(index)
	return result


static func get_player_capacity(index: int) -> int:
	var map_data := get_map(index)
	if map_data.is_empty() or not is_scene_available(index):
		return 0
	return clampi(
		int(map_data.get("player_capacity", MatchLimitsData.MAX_TOTAL_ACTORS)),
		1, MatchLimitsData.MAX_TOTAL_ACTORS)


static func load_thumbnail(index: int) -> Texture2D:
	var map_data := get_map(index)
	if map_data.is_empty():
		return null
	var thumbnail_path := str(map_data.get("thumbnail_path", ""))
	if thumbnail_path == "" or not ResourceLoader.exists(thumbnail_path):
		return null
	return load(thumbnail_path) as Texture2D
