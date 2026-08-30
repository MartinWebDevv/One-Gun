class_name SupabaseCosmeticRegistry
extends RefCounted

# Supabase owns cosmetic IDs and loadouts; this registry only answers whether
# an ID currently has a safe local One Gun visual implementation. Database
# entries without art remain purchasable/ownable and never become resource
# paths supplied by the server.

const DEFAULT_CEREMONY_THEME_ID := "wc_theme_ceremony_march"
const DEFAULT_CEREMONY_AUDIO_KEY := "winners_circle_ceremony"
const BASE_GUN_SKIN_ID := "base_one_gun"
const BASE_MELEE_SKIN_ID := "base_arena_melee"
const GOLDFISH_BAG_MAN_ITEM_ID := "character_goldfish_bag_man"
const EYE_WIZARD_ITEM_ID := "character_eye_wizard"
const MR_MUSHROOM_ITEM_ID := "character_mr_mushroom"
const MR_POOP_ITEM_ID := "character_mr_poop"
const MR_SALT_ITEM_ID := "character_mr_salt"
const SPOOKY_WITCH_ITEM_ID := "character_spooky_witch"
const DEVELOPER_GIFT_CHARACTER_ITEM_IDS: Array[String] = [
	GOLDFISH_BAG_MAN_ITEM_ID, EYE_WIZARD_ITEM_ID, MR_MUSHROOM_ITEM_ID,
	MR_POOP_ITEM_ID, MR_SALT_ITEM_ID, SPOOKY_WITCH_ITEM_ID,
]
const CHARACTER_MODEL_IDS := {
	GOLDFISH_BAG_MAN_ITEM_ID: PlayerSkinRegistry.GOLDFISH_BAG_MAN_MODEL_ID,
	EYE_WIZARD_ITEM_ID: PlayerSkinRegistry.EYE_WIZARD_MODEL_ID,
	MR_MUSHROOM_ITEM_ID: PlayerSkinRegistry.MR_MUSHROOM_MODEL_ID,
	MR_POOP_ITEM_ID: PlayerSkinRegistry.MR_POOP_MODEL_ID,
	MR_SALT_ITEM_ID: PlayerSkinRegistry.MR_SALT_MODEL_ID,
	SPOOKY_WITCH_ITEM_ID: PlayerSkinRegistry.SPOOKY_WITCH_MODEL_ID,
}
const HatRegistry = preload("res://models/cosmetics/hats/hat_cosmetic_registry.gd")
const WearableRegistry = preload("res://models/cosmetics/wearable_cosmetic_registry.gd")

const LEGACY_LOADOUT_SLOTS: Array[String] = [
	"character_skin", "hat", "accessory", "gun_skin", "melee_skin", "emote",
]

const PRE_PROGRESSION_LOADOUT_SLOTS: Array[String] = [
	"character_skin", "hat", "accessory", "gun_skin", "melee_skin", "emote",
	"ceremony_theme",
]

const LOADOUT_SLOTS: Array[String] = [
	"character_skin",
	"character_model",
	"hat",
	"shirt",
	"pants",
	"shoes",
	"accessory",
	"gun_skin",
	"melee_skin",
	"emote",
	"round_victory_move",
	"ceremony_theme",
	"profile_badge",
]

# Deployed before character-model entitlements existed. SupabaseManager tries
# this complete schema before falling back to genuinely old seven/six-slot
# layouts, so one newly-added column never hides modern hats or road rewards.
const PRE_CHARACTER_MODEL_LOADOUT_SLOTS: Array[String] = [
	"character_skin", "hat", "shirt", "pants", "shoes", "accessory",
	"gun_skin", "melee_skin", "emote", "round_victory_move",
	"ceremony_theme", "profile_badge",
]

const KNOWN_ART_PENDING := {
	"cowboy_hat": "hat",
	"founder_crown": "hat",
	"golden_gun_skin": "gun_skin",
}

# Stable Supabase item IDs map only to locally shipped animation names. New
# victory moves are added here when their animation assets enter the project;
# backend strings are never treated as resource paths.
const VICTORY_DANCE_ANIMATIONS := {
	"hip_hop_dance": "hip_hop_dance",
	"victory_hip_hop": "hip_hop_dance",
	"swing_dance": "swing_dance",
	"victory_swing": "swing_dance",
	"podium_backbeat_bounce": "podium_backbeat_bounce",
	"podium_champion_canter": "podium_champion_canter",
	"podium_fresh_footwork": "podium_fresh_footwork",
	"podium_house_party_heat": "podium_house_party_heat",
	"podium_serpent_flow": "podium_serpent_flow",
	"podium_midnight_monster": "podium_midnight_monster",
	"podium_victory_wave": "podium_victory_wave",
	"round_breakspin_finale": "round_breakspin_finale",
	"round_floorwork_finish": "round_floorwork_finish",
	"round_birdie_boogie": "round_birdie_boogie",
	"round_arena_clapline": "round_arena_clapline",
	"round_soul_cyclone": "round_soul_cyclone",
	"round_quickstep_shuffle": "round_quickstep_shuffle",
	"round_victory_swing": "round_victory_swing",
}

# Compatibility aliases keep older gameplay and validation callers working
# while both equip slots now share the exact same dance library.
const PODIUM_DANCE_ANIMATIONS := VICTORY_DANCE_ANIMATIONS
const ROUND_VICTORY_MOVE_ANIMATIONS := VICTORY_DANCE_ANIMATIONS

const CEREMONY_THEME_AUDIO_KEYS := {
	"wc_theme_ceremony_march": "winners_circle_ceremony",
	"wc_theme_neon_victory": "winners_circle_neon_victory",
	"wc_theme_western_toybox": "winners_circle_western_toybox",
	"wc_theme_grand_arena": "winners_circle_grand_arena",
	"wc_theme_pixel_champion": "winners_circle_pixel_champion",
	"wc_theme_champion_groove": "winners_circle_champion_groove",
	"wc_theme_deep_orbit": "winners_circle_deep_orbit",
}

const CEREMONY_THEME_DISPLAY_NAMES := {
	"wc_theme_ceremony_march": "Ceremony March",
	"wc_theme_neon_victory": "Neon Victory",
	"wc_theme_western_toybox": "Western Toybox",
	"wc_theme_grand_arena": "Grand Arena",
	"wc_theme_pixel_champion": "Pixel Champion",
	"wc_theme_champion_groove": "Champion Groove",
	"wc_theme_deep_orbit": "Deep Orbit",
}

static var _warned_missing_visuals: Dictionary = {}


static func sanitize_item_id(value: String) -> String:
	var source := value.strip_edges().to_lower().substr(0, 64)
	var cleaned := ""
	for character in source:
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-.":
			cleaned += character
	return cleaned


static func sanitize_slot(value: String) -> String:
	var cleaned := value.strip_edges().to_lower()
	return cleaned if cleaned in LOADOUT_SLOTS else ""


static func sanitize_loadout(raw) -> Dictionary:
	var result := empty_loadout()
	if not raw is Dictionary:
		return result
	for slot in LOADOUT_SLOTS:
		var value = raw.get(slot, "")
		result[slot] = "" if value == null \
			else sanitize_item_id(str(value))
	return result


static func empty_loadout() -> Dictionary:
	var result := {}
	for slot in LOADOUT_SLOTS:
		result[slot] = ""
	return result


static func item_slot(item: Dictionary) -> String:
	var raw_slot := str(item.get("item_type", "")).strip_edges().to_lower()
	return "victory_dance" if raw_slot == "victory_dance" \
		else sanitize_slot(raw_slot)


static func has_local_visual(item_id: String, slot := "") -> bool:
	var safe_id := sanitize_item_id(item_id)
	var safe_slot := str(slot).strip_edges().to_lower()
	if safe_slot == "character_skin":
		return _is_builtin_character_skin(safe_id)
	if safe_slot == "character_model":
		return CHARACTER_MODEL_IDS.has(safe_id)
	if safe_slot in ["victory_dance", "emote", "round_victory_move"]:
		return local_victory_animation(safe_id) != ""
	if safe_slot == "ceremony_theme":
		return local_ceremony_audio_key(safe_id) != ""
	if safe_slot == "gun_skin":
		return safe_id == BASE_GUN_SKIN_ID
	if safe_slot == "melee_skin":
		return safe_id == BASE_MELEE_SKIN_ID
	if safe_slot in WearableRegistry.WEARABLE_SLOTS:
		return WearableRegistry.has_local_visual(safe_id, safe_slot)
	return false


static func local_podium_animation(item_id: String) -> String:
	return local_victory_animation(item_id)


static func local_victory_animation(item_id: String) -> String:
	var safe_id := sanitize_item_id(item_id)
	return str(VICTORY_DANCE_ANIMATIONS.get(safe_id, ""))


static func local_round_victory_animation(item_id: String) -> String:
	return local_victory_animation(item_id)


static func local_ceremony_audio_key(item_id: String) -> String:
	var safe_id := sanitize_item_id(item_id)
	return str(CEREMONY_THEME_AUDIO_KEYS.get(safe_id, ""))


static func resolved_ceremony_audio_key(item_id: String) -> String:
	var mapped := local_ceremony_audio_key(item_id)
	return mapped if mapped != "" else DEFAULT_CEREMONY_AUDIO_KEY


static func apply_gun_skin_to_display(display_root: Node3D,
		item_id: String) -> bool:
	if display_root == null:
		return false
	var safe_id := sanitize_item_id(item_id)
	display_root.set_meta("supabase_gun_skin_id", safe_id)
	# The current project has no gun-skin material renderer. The ceremonial
	# display intentionally keeps the default gun until a safe local mapping is
	# added; ownership/equipment data still survives end to end.
	return safe_id in ["", BASE_GUN_SKIN_ID]


static func local_character_skin_id(item_id: String) -> String:
	var safe_id := sanitize_item_id(item_id)
	return safe_id if _is_builtin_character_skin(safe_id) else ""


static func local_character_model_id(item_id: String) -> String:
	var safe_id := sanitize_item_id(item_id)
	return str(CHARACTER_MODEL_IDS.get(safe_id, ""))


static func known_slot_for_id(item_id: String) -> String:
	var safe_id := sanitize_item_id(item_id)
	if KNOWN_ART_PENDING.has(safe_id):
		return str(KNOWN_ART_PENDING[safe_id])
	if CEREMONY_THEME_AUDIO_KEYS.has(safe_id):
		return "ceremony_theme"
	if VICTORY_DANCE_ANIMATIONS.has(safe_id):
		return "victory_dance"
	if safe_id == BASE_GUN_SKIN_ID:
		return "gun_skin"
	if safe_id == BASE_MELEE_SKIN_ID:
		return "melee_skin"
	if HatRegistry.has_hat(safe_id):
		return "hat"
	var wearable_slot := WearableRegistry.slot_for_id(safe_id)
	if wearable_slot != "":
		return wearable_slot
	if CHARACTER_MODEL_IDS.has(safe_id):
		return "character_model"
	return "character_skin" if _is_builtin_character_skin(safe_id) else ""


static func display_name_fallback(item_id: String) -> String:
	var safe_id := sanitize_item_id(item_id)
	if CHARACTER_MODEL_IDS.has(safe_id):
		return PlayerSkinRegistry.model_display_name(str(
			CHARACTER_MODEL_IDS[safe_id]))
	if CEREMONY_THEME_DISPLAY_NAMES.has(safe_id):
		return str(CEREMONY_THEME_DISPLAY_NAMES[safe_id])
	if HatRegistry.has_hat(safe_id):
		return HatRegistry.display_name(safe_id)
	return safe_id.replace("_", " ").replace("-", " ").capitalize() \
		if safe_id != "" else "Unknown Cosmetic"


static func local_catalog_item(item_id: String) -> Dictionary:
	# Hidden owned items can arrive in inventory before their RLS-gated catalog
	# row finishes loading. Only packaged, trusted IDs receive local metadata;
	# arbitrary server strings never become assets or visible Locker entries.
	var safe_id := sanitize_item_id(item_id)
	if CHARACTER_MODEL_IDS.has(safe_id):
		return {
			"id": safe_id,
			"display_name": PlayerSkinRegistry.model_display_name(str(
				CHARACTER_MODEL_IDS[safe_id])),
			"item_type": "character_model",
			"description": "A special arena competitor granted directly by the One Gun team.",
			"price": 0,
			"rarity": "epic",
			"purchasable": false,
			"shop_visible": false,
			"active": true,
			"category": "character",
			"subcategory": "skins",
			"featured": false,
			"rotation_scope": "none",
			"sort_order": 9000,
		}
	return {}


static func apply_to_player(player: Node, raw_loadout) -> void:
	if player == null:
		return
	var loadout := sanitize_loadout(raw_loadout)
	var character_model := local_character_model_id(
		str(loadout.get("character_model", "")))
	if character_model != "" and player.has_method("set_character_model"):
		player.call("set_character_model", character_model)
	var character_skin := local_character_skin_id(str(loadout["character_skin"]))
	if character_skin != "" and player.has_method("set_character_skin"):
		player.call("set_character_skin", character_skin)
	if player.has_method("set_wearable_cosmetic"):
		for wearable_slot in WearableRegistry.WEARABLE_SLOTS:
			player.call("set_wearable_cosmetic", wearable_slot,
				str(loadout.get(wearable_slot, "")))
	elif player.has_method("set_hat_cosmetic"):
		player.call("set_hat_cosmetic", str(loadout.get("hat", "")))
	for slot in LOADOUT_SLOTS:
		var item_id := str(loadout.get(slot, ""))
		if item_id == "" or has_local_visual(item_id, slot):
			continue
		var warning_key := "%s:%s" % [slot, item_id]
		if _warned_missing_visuals.has(warning_key):
			continue
		_warned_missing_visuals[warning_key] = true
		push_warning(
			"Supabase cosmetic '%s' is equipped in %s, but its local visual is not mapped yet." \
			% [item_id, slot])
	# Unmapped IDs stay on the actor without ever becoming server-controlled
	# resource paths. Locally registered wearables use the skeleton binder above.
	player.set_meta("supabase_cosmetic_loadout", loadout.duplicate(true))


static func apply_to_character_visual(visual: Node3D, raw_loadout) -> void:
	if visual == null:
		return
	var loadout := sanitize_loadout(raw_loadout)
	var character_skin := local_character_skin_id(str(loadout["character_skin"]))
	if character_skin != "" and visual.has_method("set_skin"):
		visual.call("set_skin", character_skin)
	if visual.has_method("set_wearable_cosmetic"):
		for wearable_slot in WearableRegistry.WEARABLE_SLOTS:
			visual.call("set_wearable_cosmetic", wearable_slot,
				str(loadout.get(wearable_slot, "")))
	elif visual.has_method("set_hat_cosmetic"):
		visual.call("set_hat_cosmetic", str(loadout.get("hat", "")))
	# Preserve every sanitized equipped ID on presentation-only characters so
	# future locally mapped wearables can share this same seam.
	visual.set_meta("supabase_cosmetic_loadout", loadout.duplicate(true))


static func _is_builtin_character_skin(item_id: String) -> bool:
	for skin in PlayerSkinRegistry.SKINS:
		if str(skin.get("id", "")) == item_id:
			return true
	return false
