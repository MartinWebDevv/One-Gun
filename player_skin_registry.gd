class_name PlayerSkinRegistry
extends RefCounted

const DEFAULT_SKIN_ID := "blue"
const DEFAULT_MODEL_ID := "male"
const MODEL_IDS: Array[String] = ["male", "female"]

const MODEL_SCENES := {
	"male": "res://models/player_v2/player_v2_visual.tscn",
	"female": "res://models/player_v2/femaleOGCat/female_player_v2_visual.tscn",
}

const SKINS: Array[Dictionary] = [
	{
		"id": "black", "name": "Black",
		"texture": "res://models/player_v2/colorVariants/OGCatModelV2 color black.png",
		"female_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color black BOOBA corrected.png",
		"female_chest_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color black BOOBA.png",
	},
	{
		"id": "blue", "name": "Blue",
		"texture": "res://models/player_v2/OGCatModelV2_Rigged_OGcat color blue.png",
		"female_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color blue BOOBA corrected.png",
		"female_chest_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color blue BOOBA.png",
	},
	{
		"id": "brown", "name": "Brown",
		"texture": "res://models/player_v2/colorVariants/OGCatModelV2 color brown.png",
		"female_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color brown BOOBA corrected.png",
		"female_chest_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color brown BOOBA.png",
	},
	{
		"id": "cyan", "name": "Cyan",
		"texture": "res://models/player_v2/colorVariants/OGCatModelV2 color cyan.png",
		"female_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color cyan BOOBA corrected.png",
		"female_chest_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color cyan BOOBA.png",
	},
	{
		"id": "green", "name": "Green",
		"texture": "res://models/player_v2/colorVariants/OGCatModelV2 color green.png",
		"female_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color green BOOBA corrected.png",
		"female_chest_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color green BOOBA.png",
	},
	{
		"id": "grey", "name": "Grey",
		"texture": "res://models/player_v2/colorVariants/OGCatModelV2 color grey.png",
		"female_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color grey BOOBA corrected.png",
		"female_chest_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color grey BOOBA.png",
	},
	{
		"id": "orange", "name": "Orange",
		"texture": "res://models/player_v2/colorVariants/OGCatModelV2 color orange.png",
		"female_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color orange BOOBA corrected.png",
		"female_chest_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color orange BOOBA.png",
	},
	{
		"id": "pink", "name": "Pink",
		"texture": "res://models/player_v2/colorVariants/OGCatModelV2 color pink.png",
		"female_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color pink BOOBA corrected.png",
		"female_chest_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color pink BOOBA.png",
	},
	{
		"id": "purple", "name": "Purple",
		"texture": "res://models/player_v2/colorVariants/OGCatModelV2 color purple.png",
		"female_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color purple BOOBA corrected.png",
		"female_chest_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color purple BOOBA.png",
	},
	{
		"id": "red", "name": "Red",
		"texture": "res://models/player_v2/colorVariants/OGCatModelV2 color red.png",
		"female_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color red BOOBA corrected.png",
		"female_chest_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color red BOOBA.png",
	},
	# Both delivered source sets use "salam" in the filename. Keep those paths
	# stable while exposing the intended Salmon name everywhere in-game.
	{
		"id": "salmon", "name": "Salmon",
		"texture": "res://models/player_v2/colorVariants/OGCatModelV2 color salam.png",
		"female_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color salam BOOBA corrected.png",
		"female_chest_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color salam BOOBA.png",
	},
	{
		"id": "white", "name": "White",
		"texture": "res://models/player_v2/colorVariants/OGCatModelV2 color white.png",
		"female_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color white BOOBA corrected.png",
		"female_chest_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color white BOOBA.png",
	},
	{
		"id": "yellow", "name": "Yellow",
		"texture": "res://models/player_v2/colorVariants/OGCatModelV2 color yellow.png",
		"female_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color yellow BOOBA corrected.png",
		"female_chest_texture": "res://models/player_v2/femaleOGCat/femaleOGCatCOLORS/OGcat color yellow BOOBA.png",
	},
]


static func sanitize_skin_id(requested_id: String) -> String:
	var cleaned := requested_id.strip_edges().to_lower()
	for skin in SKINS:
		if str(skin["id"]) == cleaned:
			return cleaned
	return DEFAULT_SKIN_ID


static func sanitize_model_id(requested_id: String) -> String:
	var cleaned := requested_id.strip_edges().to_lower()
	return cleaned if cleaned in MODEL_IDS else DEFAULT_MODEL_ID


static func model_display_name(requested_id: String) -> String:
	return "Female" if sanitize_model_id(requested_id) == "female" else "Male"


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


static func texture_path(requested_id: String,
		model_id := DEFAULT_MODEL_ID) -> String:
	var safe_id := sanitize_skin_id(requested_id)
	var texture_key := "female_texture" \
		if sanitize_model_id(model_id) == "female" else "texture"
	for skin in SKINS:
		if str(skin["id"]) == safe_id:
			return str(skin[texture_key])
	return str(SKINS[skin_index(DEFAULT_SKIN_ID)][texture_key])


static func load_texture(requested_id: String,
		model_id := DEFAULT_MODEL_ID) -> Texture2D:
	var path := texture_path(requested_id, model_id)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func load_female_chest_texture(requested_id: String) -> Texture2D:
	var safe_id := sanitize_skin_id(requested_id)
	for skin in SKINS:
		if str(skin["id"]) == safe_id:
			var path := str(skin["female_chest_texture"])
			return load(path) as Texture2D if ResourceLoader.exists(path) else null
	return null


static func portrait_path(requested_id: String,
		model_id := DEFAULT_MODEL_ID) -> String:
	var safe_id := sanitize_skin_id(requested_id)
	if sanitize_model_id(model_id) == "female":
		return "res://UI/assets/character_portraits/female/%s.png" % safe_id
	return "res://UI/assets/character_portraits/%s.png" % safe_id


static func load_portrait(requested_id: String,
		model_id := DEFAULT_MODEL_ID) -> Texture2D:
	var path := portrait_path(requested_id, model_id)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func visual_scene_path(model_id := DEFAULT_MODEL_ID) -> String:
	return str(MODEL_SCENES[sanitize_model_id(model_id)])


static func load_visual_scene(model_id := DEFAULT_MODEL_ID) -> PackedScene:
	var path := visual_scene_path(model_id)
	return load(path) as PackedScene if ResourceLoader.exists(path) else null
