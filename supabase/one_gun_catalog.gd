class_name OneGunCatalog
extends RefCounted

# One shared taxonomy for the Prize Counter and owned-only Locker. Database
# rows may add presentation metadata, but server strings never become resource
# paths. Legacy rows are inferred from item_type so older catalog content keeps
# landing in a useful aisle after the taxonomy migration.

const PRIMARY_CATEGORIES: Array[String] = [
	"FEATURED", "CHARACTER", "WEAPONS", "VICTORY", "AUDIO",
]

const CATEGORY_SUBCATEGORIES := {
	"FEATURED": ["ALL", "DAILY", "MONTHLY", "SEASONAL STARTER"],
	"CHARACTER": ["ALL", "SKINS", "COLORS", "COSMETICS"],
	"WEAPONS": ["ALL", "GUN SKINS", "MELEE SKINS"],
	"VICTORY": ["ALL", "POSES", "DANCES"],
	"AUDIO": ["ALL", "WINNERS CIRCLE"],
}

const COSMETIC_SUBCATEGORIES: Array[String] = [
	"ALL", "HATS", "SHIRTS", "PANTS", "SHOES", "OUTFITS",
]

const RARITIES: Array[String] = [
	"standard", "common", "uncommon", "rare", "epic", "legendary",
]

const SORT_IDS: Array[String] = [
	"rarity_asc", "rarity_desc", "alphabetical_asc", "alphabetical_desc",
	"most_bought", "most_used", "newest",
]

const SORT_LABELS: Array[String] = [
	"RARITY: LOW TO HIGH", "RARITY: HIGH TO LOW", "ALPHABETICAL: A–Z",
	"ALPHABETICAL: Z–A", "MOST BOUGHT", "MOST USED", "NEWEST",
]


static func normalize_item(value: Dictionary) -> Dictionary:
	var item := value.duplicate(true)
	item["id"] = SupabaseCosmeticRegistry.sanitize_item_id(
		str(item.get("id", item.get("item_id", ""))))
	item["category"] = category(item).to_lower()
	item["subcategory"] = subcategory(item)
	item["rarity"] = str(item.get("rarity", "standard")).to_lower()
	item["rotation_scope"] = str(item.get("rotation_scope",
		item.get("rotation_type", "none"))).to_lower()
	item["purchase_count"] = maxi(int(item.get("purchase_count", 0)), 0)
	item["sort_order"] = int(item.get("sort_order", 0))
	return item


static func category(item: Dictionary) -> String:
	var explicit := str(item.get("category", "")).strip_edges().to_upper()
	if explicit in PRIMARY_CATEGORIES:
		return explicit
	match str(item.get("item_type", "")).to_lower():
		"character_skin", "hat", "shirt", "pants", "shoes", "accessory", "profile_badge", "outfit_bundle":
			return "CHARACTER"
		"gun_skin", "melee_skin":
			return "WEAPONS"
		"emote", "round_victory_move", "victory_dance":
			return "VICTORY"
		"ceremony_theme":
			return "AUDIO"
	return "FEATURED"


static func subcategory(item: Dictionary) -> String:
	# Profile crests are equipped in their own slot, but browse alongside the
	# player's other small Character cosmetics in the shared Locker taxonomy.
	if str(item.get("item_type", "")).to_lower() == "profile_badge":
		return "cosmetics"
	var explicit := str(item.get("subcategory", "")).strip_edges().to_lower()
	if explicit in ["podium_dances", "round_moves"]:
		return "dances"
	if explicit == "podium_poses":
		return "poses"
	if explicit != "":
		return explicit
	match str(item.get("item_type", "")).to_lower():
		"character_skin": return "colors"
		"hat": return "hats"
		"shirt": return "shirts"
		"pants": return "pants"
		"shoes": return "shoes"
		"accessory": return "cosmetics"
		"profile_badge": return "cosmetics"
		"outfit_bundle": return "outfits"
		"gun_skin": return "gun_skins"
		"melee_skin": return "melee_skins"
		"emote", "round_victory_move", "victory_dance": return "dances"
		"ceremony_theme": return "winners_circle"
	return "all"


static func category_subcategories(primary: String) -> Array[String]:
	var result: Array[String] = []
	var values: Array = CATEGORY_SUBCATEGORIES.get(primary.to_upper(), ["ALL"])
	for value in values:
		result.append(str(value))
	return result


static func item_matches(item: Dictionary, primary: String,
		subcategory_filter: String, cosmetic_filter := "ALL") -> bool:
	var safe_primary := primary.to_upper()
	var safe_subcategory := subcategory_filter.to_upper()
	var item_subcategory := subcategory(item)
	if safe_primary == "FEATURED":
		match safe_subcategory:
			"DAILY": return rotation_scope(item) == "daily"
			"MONTHLY": return rotation_scope(item) == "monthly"
			"SEASONAL STARTER": return rotation_scope(item) == "seasonal_starter"
		return bool(item.get("featured", false)) or is_in_live_rotation(item)
	if category(item) != safe_primary:
		return false
	match safe_primary:
		"CHARACTER":
			match safe_subcategory:
				"SKINS": return item_subcategory == "skins"
				"COLORS": return item_subcategory == "colors"
				"COSMETICS":
					var safe_cosmetic := cosmetic_filter.to_lower().replace(" ", "_")
					return item_subcategory in ["cosmetics", "hats", "shirts", "pants", "shoes", "outfits"] \
						and (safe_cosmetic == "all" or item_subcategory == safe_cosmetic)
		"WEAPONS":
			if safe_subcategory == "GUN SKINS": return item_subcategory == "gun_skins"
			if safe_subcategory == "MELEE SKINS": return item_subcategory == "melee_skins"
		"VICTORY":
			if safe_subcategory == "POSES": return item_subcategory == "poses"
			if safe_subcategory == "DANCES": return item_subcategory == "dances"
		"AUDIO":
			if safe_subcategory == "WINNERS CIRCLE": return item_subcategory == "winners_circle"
	return true


static func rarity_rank(value: String) -> int:
	var index := RARITIES.find(value.strip_edges().to_lower())
	return index if index >= 0 else 0


static func sorted_items(source: Array[Dictionary], sort_id: String,
		usage: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in source:
		result.append(value.duplicate(true))
	var safe_sort := sort_id if sort_id in SORT_IDS else "rarity_asc"
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_name := str(a.get("display_name", a.get("id", "")))
		var b_name := str(b.get("display_name", b.get("id", "")))
		var a_id := str(a.get("id", a.get("item_id", "")))
		var b_id := str(b.get("id", b.get("item_id", "")))
		match safe_sort:
			"rarity_asc", "rarity_desc":
				var a_rank := rarity_rank(str(a.get("rarity", "standard")))
				var b_rank := rarity_rank(str(b.get("rarity", "standard")))
				if a_rank != b_rank:
					return a_rank < b_rank if safe_sort == "rarity_asc" else a_rank > b_rank
			"alphabetical_desc":
				return a_name.nocasecmp_to(b_name) > 0
			"most_bought":
				var a_bought := int(a.get("purchase_count", 0))
				var b_bought := int(b.get("purchase_count", 0))
				if a_bought != b_bought:
					return a_bought > b_bought
			"most_used":
				var a_used := int(usage.get(a_id, 0))
				var b_used := int(usage.get(b_id, 0))
				if a_used != b_used:
					return a_used > b_used
			"newest":
				var a_date := str(a.get("obtained_at", a.get("created_at", "")))
				var b_date := str(b.get("obtained_at", b.get("created_at", "")))
				if a_date != b_date:
					return a_date > b_date
		return a_name.nocasecmp_to(b_name) < 0
	)
	return result


static func rotation_scope(item: Dictionary) -> String:
	return str(item.get("rotation_scope", "none")).strip_edges().to_lower()


static func is_in_live_rotation(item: Dictionary) -> bool:
	if not bool(item.get("active", false)) or not bool(item.get("shop_visible", false)):
		return false
	if rotation_scope(item) not in ["daily", "monthly", "seasonal_starter", "seasonal"]:
		return false
	var now_iso := Time.get_datetime_string_from_system(true)
	var starts_at := str(item.get("rotation_starts_at", ""))
	var ends_at := str(item.get("rotation_ends_at", ""))
	return (starts_at == "" or starts_at <= now_iso) and (ends_at == "" or ends_at > now_iso)
