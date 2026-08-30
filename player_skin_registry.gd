class_name PlayerSkinRegistry
extends RefCounted

const DEFAULT_SKIN_ID := "blue"
const DEFAULT_MODEL_ID := "male"
const GOLDFISH_BAG_MAN_MODEL_ID := "goldfish_bag_man"
const EYE_WIZARD_MODEL_ID := "eye_wizard"
const MR_MUSHROOM_MODEL_ID := "mr_mushroom"
const MR_POOP_MODEL_ID := "mr_poop"
const MR_SALT_MODEL_ID := "mr_salt"
const SPOOKY_WITCH_MODEL_ID := "spooky_witch"

# Public models are always-available local choices. Entitlement-only characters
# stay in MODEL_IDS so every runtime path supports them without exposing them in
# the base picker.
const PUBLIC_MODEL_IDS: Array[String] = [
	"male", "female",
]
const DEVELOPER_GIFT_MODEL_IDS: Array[String] = [
	GOLDFISH_BAG_MAN_MODEL_ID, EYE_WIZARD_MODEL_ID, MR_MUSHROOM_MODEL_ID,
	MR_POOP_MODEL_ID, MR_SALT_MODEL_ID, SPOOKY_WITCH_MODEL_ID,
]
const MODEL_IDS: Array[String] = PUBLIC_MODEL_IDS + DEVELOPER_GIFT_MODEL_IDS
const FIXED_TEXTURE_MODEL_IDS: Array[String] = [
	GOLDFISH_BAG_MAN_MODEL_ID, EYE_WIZARD_MODEL_ID, MR_MUSHROOM_MODEL_ID,
	MR_POOP_MODEL_ID, MR_SALT_MODEL_ID, SPOOKY_WITCH_MODEL_ID,
]

const MODEL_SCENES := {
	"male": "res://models/player_v2/player_v2_visual.tscn",
	"female": "res://models/player_v2/femaleOGCat/female_player_v2_visual.tscn",
	GOLDFISH_BAG_MAN_MODEL_ID: \
		"res://models/player_v2/characterSkins/goldfish_bag_man_visual.tscn",
	EYE_WIZARD_MODEL_ID: \
		"res://models/player_v2/characterSkins/eye_wizard_visual.tscn",
	MR_MUSHROOM_MODEL_ID: \
		"res://models/player_v2/characterSkins/mr_mushroom_visual.tscn",
	MR_POOP_MODEL_ID: \
		"res://models/player_v2/characterSkins/mr_poop_visual.tscn",
	MR_SALT_MODEL_ID: \
		"res://models/player_v2/characterSkins/mr_salt_visual.tscn",
	SPOOKY_WITCH_MODEL_ID: \
		"res://models/player_v2/characterSkins/spooky_witch_visual.tscn",
}
const FIXED_MODEL_PORTRAIT_PATHS := {
	GOLDFISH_BAG_MAN_MODEL_ID: \
		"res://UI/assets/character_portraits/goldfish_bag_man.png",
	EYE_WIZARD_MODEL_ID: \
		"res://models/player_v2/characterSkins/Eye_Wizard_100Avatars_113_EyeWizard.png",
	MR_MUSHROOM_MODEL_ID: \
		"res://models/player_v2/characterSkins/Mr_Mushroom_100Avatars_025_Mushy.png",
	MR_POOP_MODEL_ID: \
		"res://models/player_v2/characterSkins/Mr_Poop_100Avatars_176_CoolPoo.png",
	MR_SALT_MODEL_ID: \
		"res://models/player_v2/characterSkins/Mr_Salt_100Avatars_132_SaltySalt.png",
	SPOOKY_WITCH_MODEL_ID: \
		"res://models/player_v2/characterSkins/Spooky_Witch_100Avatars_039_Witch.png",
}

# Runtime-skinned idle envelopes measured in the standard player.tscn actor
# space. Presentation cameras use these cheap, trusted boxes instead of import
# AABBs, which do not include Skeleton3D deformation and are especially wrong
# for the Female and fixed-look rigs. Gameplay collision remains the one capsule
# owned by player.tscn; these values never participate in hit detection.
const MODEL_IDLE_ACTOR_BOUNDS := {
	"male": AABB(
		Vector3(-0.905983, -1.138238, -0.786686),
		Vector3(1.620018, 2.859916, 1.882745)),
	"female": AABB(
		Vector3(-1.188729, -1.020815, -1.115990),
		Vector3(2.419612, 2.430753, 1.779222)),
	GOLDFISH_BAG_MAN_MODEL_ID: AABB(
		Vector3(-0.678555, -1.090001, -1.220641),
		Vector3(1.989955, 2.645326, 2.157654)),
	EYE_WIZARD_MODEL_ID: AABB(
		Vector3(-0.832320, -1.090000, -1.649048),
		Vector3(2.500241, 2.645324, 2.860105)),
	MR_MUSHROOM_MODEL_ID: AABB(
		Vector3(-0.436067, -1.090000, -1.374768),
		Vector3(1.873342, 2.645325, 2.129819)),
	MR_POOP_MODEL_ID: AABB(
		Vector3(-1.449689, -1.090000, -1.953700),
		Vector3(3.481275, 2.645324, 3.669706)),
	MR_SALT_MODEL_ID: AABB(
		Vector3(-0.859720, -1.090000, -1.557373),
		Vector3(2.601444, 2.645323, 2.740955)),
	SPOOKY_WITCH_MODEL_ID: AABB(
		Vector3(-0.586478, -1.090000, -1.229976),
		Vector3(1.894192, 2.645324, 2.178293)),
}

# Every registered character must declare how animated headwear is anchored and
# where per-Hat adjustments inherit from when that model has no exact override.
# This is intentionally separate from public/store visibility: entitlement-only
# models use the same runtime Hat contract as the free cats. Validation rejects
# future MODEL_IDS that omit this entry instead of silently shipping bad fits.
const MODEL_HEADWEAR_PROFILES := {
	"male": {
		"fit_fallback": "",
		"height_offset": 0.740,
		"forward_offset": 0.020,
		"socket_height_range": Vector2(1.75, 2.15),
	},
	"female": {
		"fit_fallback": "male",
		"height_offset": 0.715,
		"forward_offset": 0.015,
		"socket_height_range": Vector2(1.75, 2.15),
	},
	GOLDFISH_BAG_MAN_MODEL_ID: {
		"fit_fallback": "male",
		"height_offset": 0.570,
		"forward_offset": 0.015,
		"socket_height_range": Vector2(2.55, 3.05),
	},
	EYE_WIZARD_MODEL_ID: {
		"fit_fallback": GOLDFISH_BAG_MAN_MODEL_ID,
		"height_offset": 0.570,
		"forward_offset": 0.015,
		"socket_height_range": Vector2(2.30, 2.48),
	},
	MR_MUSHROOM_MODEL_ID: {
		# Mr. Mushroom's authored cap is his head silhouette. Seat cosmetics on
		# top of it, but retain the narrower fixed-character fits so broad brims
		# cannot enter the close-ADS center sight lane.
		"fit_fallback": GOLDFISH_BAG_MAN_MODEL_ID,
		"height_offset": 1.500,
		"forward_offset": 0.015,
		"socket_height_range": Vector2(3.15, 3.38),
	},
	MR_POOP_MODEL_ID: {
		"fit_fallback": GOLDFISH_BAG_MAN_MODEL_ID,
		"height_offset": 0.570,
		"forward_offset": 0.015,
		"socket_height_range": Vector2(2.70, 2.92),
	},
	MR_SALT_MODEL_ID: {
		"fit_fallback": GOLDFISH_BAG_MAN_MODEL_ID,
		"height_offset": 0.570,
		"forward_offset": 0.015,
		"socket_height_range": Vector2(2.90, 3.12),
	},
	SPOOKY_WITCH_MODEL_ID: {
		"fit_fallback": GOLDFISH_BAG_MAN_MODEL_ID,
		"height_offset": 0.570,
		"forward_offset": 0.015,
		"socket_height_range": Vector2(2.35, 2.70),
	},
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
	match sanitize_model_id(requested_id):
		"female": return "Female"
		GOLDFISH_BAG_MAN_MODEL_ID: return "Gold Fish Bag Man"
		EYE_WIZARD_MODEL_ID: return "Eye Wizard"
		MR_MUSHROOM_MODEL_ID: return "Mr. Mushroom"
		MR_POOP_MODEL_ID: return "Mr. Poop"
		MR_SALT_MODEL_ID: return "Mr. Salt"
		SPOOKY_WITCH_MODEL_ID: return "Spooky Witch"
	return "Male"


static func model_button_label(requested_id: String) -> String:
	match sanitize_model_id(requested_id):
		"male": return "MALE CAT"
		"female": return "FEMALE CAT"
		EYE_WIZARD_MODEL_ID: return "EYE WIZARD"
		MR_MUSHROOM_MODEL_ID: return "MR. MUSHROOM"
		MR_POOP_MODEL_ID: return "MR. POOP"
		MR_SALT_MODEL_ID: return "MR. SALT"
		SPOOKY_WITCH_MODEL_ID: return "SPOOKY WITCH"
	return model_display_name(requested_id).to_upper()


static func has_headwear_profile(requested_id: String) -> bool:
	var cleaned := requested_id.strip_edges().to_lower()
	return cleaned in MODEL_IDS and MODEL_HEADWEAR_PROFILES.has(cleaned)


static func headwear_fit_model_chain(requested_id: String) -> Array[String]:
	var result: Array[String] = []
	var visited := {}
	var current := sanitize_model_id(requested_id)
	while current != "" and current in MODEL_IDS and not visited.has(current):
		result.append(current)
		visited[current] = true
		var profile = MODEL_HEADWEAR_PROFILES.get(current, {})
		if not profile is Dictionary:
			break
		var fallback := str((profile as Dictionary).get(
			"fit_fallback", "")).strip_edges().to_lower()
		if fallback == "" or fallback not in MODEL_IDS:
			break
		current = fallback
	return result


static func headwear_fit_fallback_model_id(requested_id: String) -> String:
	var chain := headwear_fit_model_chain(requested_id)
	return chain[1] if chain.size() > 1 else ""


static func headwear_socket_height(requested_id: String) -> float:
	return float(_headwear_profile_or_default(requested_id).get(
		"height_offset", 0.740))


static func headwear_socket_forward(requested_id: String) -> float:
	return float(_headwear_profile_or_default(requested_id).get(
		"forward_offset", 0.020))


static func headwear_socket_height_range(requested_id: String) -> Vector2:
	var value = _headwear_profile_or_default(requested_id).get(
		"socket_height_range", Vector2(1.75, 2.15))
	return value if value is Vector2 else Vector2(1.75, 2.15)


static func _headwear_profile_or_default(requested_id: String) -> Dictionary:
	var safe_id := sanitize_model_id(requested_id)
	var profile = MODEL_HEADWEAR_PROFILES.get(safe_id, {})
	if profile is Dictionary and not (profile as Dictionary).is_empty():
		return profile as Dictionary
	return MODEL_HEADWEAR_PROFILES.get(DEFAULT_MODEL_ID, {}) as Dictionary


static func is_public_model_id(requested_id: String) -> bool:
	return sanitize_model_id(requested_id) in PUBLIC_MODEL_IDS


static func sanitize_public_model_id(requested_id: String) -> String:
	var cleaned := requested_id.strip_edges().to_lower()
	return cleaned if cleaned in PUBLIC_MODEL_IDS else DEFAULT_MODEL_ID


static func uses_fixed_texture(model_id: String) -> bool:
	return sanitize_model_id(model_id) in FIXED_TEXTURE_MODEL_IDS


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
	var safe_model := sanitize_model_id(model_id)
	if FIXED_MODEL_PORTRAIT_PATHS.has(safe_model):
		return str(FIXED_MODEL_PORTRAIT_PATHS[safe_model])
	if safe_model == "female":
		return "res://UI/assets/character_portraits/female/%s.png" % safe_id
	if safe_model == "male":
		return "res://UI/assets/character_portraits/%s.png" % safe_id
	return ""


static func idle_actor_bounds(requested_id: String) -> AABB:
	return MODEL_IDLE_ACTOR_BOUNDS.get(
		sanitize_model_id(requested_id), AABB()) as AABB


static func load_portrait(requested_id: String,
		model_id := DEFAULT_MODEL_ID) -> Texture2D:
	var path := portrait_path(requested_id, model_id)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func visual_scene_path(model_id := DEFAULT_MODEL_ID) -> String:
	return str(MODEL_SCENES[sanitize_model_id(model_id)])


static func load_visual_scene(model_id := DEFAULT_MODEL_ID) -> PackedScene:
	var path := visual_scene_path(model_id)
	return load(path) as PackedScene if ResourceLoader.exists(path) else null
