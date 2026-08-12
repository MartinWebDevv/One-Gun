class_name PlayerSkinRegistry
extends RefCounted

const DEFAULT_SKIN_ID := "blue"

const SKINS: Array[Dictionary] = [
	{"id": "black", "name": "Black", "texture": "res://models/player_v2/colorVariants/OGCatModelV2 color black.png"},
	{"id": "blue", "name": "Blue", "texture": "res://models/player_v2/OGCatModelV2_Rigged_OGcat color blue.png"},
	{"id": "brown", "name": "Brown", "texture": "res://models/player_v2/colorVariants/OGCatModelV2 color brown.png"},
	{"id": "cyan", "name": "Cyan", "texture": "res://models/player_v2/colorVariants/OGCatModelV2 color cyan.png"},
	{"id": "green", "name": "Green", "texture": "res://models/player_v2/colorVariants/OGCatModelV2 color green.png"},
	{"id": "grey", "name": "Grey", "texture": "res://models/player_v2/colorVariants/OGCatModelV2 color grey.png"},
	{"id": "orange", "name": "Orange", "texture": "res://models/player_v2/colorVariants/OGCatModelV2 color orange.png"},
	{"id": "pink", "name": "Pink", "texture": "res://models/player_v2/colorVariants/OGCatModelV2 color pink.png"},
	{"id": "purple", "name": "Purple", "texture": "res://models/player_v2/colorVariants/OGCatModelV2 color purple.png"},
	{"id": "red", "name": "Red", "texture": "res://models/player_v2/colorVariants/OGCatModelV2 color red.png"},
	# The source image was delivered with "salam" in its filename. Keep the
	# path stable while exposing the intended Salmon name everywhere in-game.
	{"id": "salmon", "name": "Salmon", "texture": "res://models/player_v2/colorVariants/OGCatModelV2 color salam.png"},
	{"id": "white", "name": "White", "texture": "res://models/player_v2/colorVariants/OGCatModelV2 color white.png"},
	{"id": "yellow", "name": "Yellow", "texture": "res://models/player_v2/colorVariants/OGCatModelV2 color yellow.png"},
]


static func sanitize_skin_id(requested_id: String) -> String:
	var cleaned := requested_id.strip_edges().to_lower()
	for skin in SKINS:
		if str(skin["id"]) == cleaned:
			return cleaned
	return DEFAULT_SKIN_ID


static func skin_count() -> int:
	return SKINS.size()


static func skin_id_at(index: int) -> String:
	if SKINS.is_empty():
		return DEFAULT_SKIN_ID
	return str(SKINS[posmod(index, SKINS.size())]["id"])


static func skin_index(requested_id: String) -> int:
	var safe_id := sanitize_skin_id(requested_id)
	for index in SKINS.size():
		if str(SKINS[index]["id"]) == safe_id:
			return index
	return 0


static func display_name(requested_id: String) -> String:
	var safe_id := sanitize_skin_id(requested_id)
	for skin in SKINS:
		if str(skin["id"]) == safe_id:
			return str(skin["name"])
	return "Blue"


static func texture_path(requested_id: String) -> String:
	var safe_id := sanitize_skin_id(requested_id)
	for skin in SKINS:
		if str(skin["id"]) == safe_id:
			return str(skin["texture"])
	return str(SKINS[skin_index(DEFAULT_SKIN_ID)]["texture"])


static func load_texture(requested_id: String) -> Texture2D:
	var path := texture_path(requested_id)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func portrait_path(requested_id: String) -> String:
	var safe_id := sanitize_skin_id(requested_id)
	return "res://UI/assets/character_portraits/%s.png" % safe_id


static func load_portrait(requested_id: String) -> Texture2D:
	var path := portrait_path(requested_id)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
