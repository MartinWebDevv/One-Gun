class_name SupabaseCosmeticRegistry
extends RefCounted

# Supabase owns cosmetic IDs and loadouts; this registry only answers whether
# an ID currently has a safe local One Gun visual implementation. Database
# entries without art remain purchasable/ownable and never become resource
# paths supplied by the server.

const LOADOUT_SLOTS: Array[String] = [
	"character_skin",
	"hat",
	"accessory",
	"gun_skin",
	"melee_skin",
	"emote",
]

const KNOWN_ART_PENDING := {
	"cowboy_hat": "hat",
	"founder_crown": "hat",
	"golden_gun_skin": "gun_skin",
}

# Stable Supabase item IDs map only to locally shipped animation names. New
# victory moves are added here when their animation assets enter the project;
# backend strings are never treated as resource paths.
const VICTORY_MOVE_ANIMATIONS := {
	"hip_hop_dance": "hip_hop_dance",
	"victory_hip_hop": "hip_hop_dance",
	"swing_dance": "swing_dance",
	"victory_swing": "swing_dance",
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
	return sanitize_slot(str(item.get("item_type", "")))


static func has_local_visual(item_id: String, slot := "") -> bool:
	var safe_id := sanitize_item_id(item_id)
	var safe_slot := sanitize_slot(slot)
	if safe_slot == "character_skin":
		return _is_builtin_character_skin(safe_id)
	if safe_slot == "emote":
		return local_victory_animation(safe_id) != ""
	return false


static func local_victory_animation(item_id: String) -> String:
	var safe_id := sanitize_item_id(item_id)
	return str(VICTORY_MOVE_ANIMATIONS.get(safe_id, ""))


static func apply_gun_skin_to_display(display_root: Node3D,
		item_id: String) -> bool:
	if display_root == null:
		return false
	var safe_id := sanitize_item_id(item_id)
	display_root.set_meta("supabase_gun_skin_id", safe_id)
	# The current project has no gun-skin material renderer. The ceremonial
	# display intentionally keeps the default gun until a safe local mapping is
	# added; ownership/equipment data still survives end to end.
	return safe_id == ""


static func local_character_skin_id(item_id: String) -> String:
	var safe_id := sanitize_item_id(item_id)
	return safe_id if _is_builtin_character_skin(safe_id) else ""


static func known_slot_for_id(item_id: String) -> String:
	var safe_id := sanitize_item_id(item_id)
	if KNOWN_ART_PENDING.has(safe_id):
		return str(KNOWN_ART_PENDING[safe_id])
	return "character_skin" if _is_builtin_character_skin(safe_id) else ""


static func display_name_fallback(item_id: String) -> String:
	var safe_id := sanitize_item_id(item_id)
	return safe_id.replace("_", " ").replace("-", " ").capitalize() \
		if safe_id != "" else "Unknown Cosmetic"


static func apply_to_player(player: Node, raw_loadout) -> void:
	if player == null:
		return
	var loadout := sanitize_loadout(raw_loadout)
	var character_skin := local_character_skin_id(str(loadout["character_skin"]))
	if character_skin != "" and player.has_method("set_character_skin"):
		player.call("set_character_skin", character_skin)
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
	# Hat/accessory/weapon/emote attachment points do not exist yet. Keep the
	# identifiers on the actor for future local renderers without inventing
	# unsafe server-controlled resource paths.
	player.set_meta("supabase_cosmetic_loadout", loadout.duplicate(true))


static func _is_builtin_character_skin(item_id: String) -> bool:
	for skin in PlayerSkinRegistry.SKINS:
		if str(skin.get("id", "")) == item_id:
			return true
	return false
