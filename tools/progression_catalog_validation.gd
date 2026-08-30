extends SceneTree

const RewardCalculator = preload("res://match_reward_calculator.gd")
const Catalog = preload("res://supabase/one_gun_catalog.gd")

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var result := {
		"official": true,
		"mode": GameConfig.MODE_ONE_GUN,
		"expected_humans": 3,
		"entries": [
			{"actor_id": 1, "placement": 1, "round_wins": 3,
				"kills": 12, "disarms": 4, "rounds_participated": 3,
				"activity_eligible": true},
			{"actor_id": 2, "placement": 2, "round_wins": 0,
				"kills": 9, "disarms": 5, "rounds_participated": 3,
				"activity_eligible": true},
			{"actor_id": 3, "placement": 3, "round_wins": 0,
				"kills": 2, "disarms": 1, "rounds_participated": 3,
				"activity_eligible": true},
		],
	}
	var winner: Dictionary = RewardCalculator.for_actor(result, 1)
	_check(int(winner.get("xp_delta", -1)) == 97,
		"winner preview must be 97 base match XP")
	_check(bool(winner.get("daily_victory_bonus_pending", false)),
		"winner preview must mark the server-authoritative daily bonus check")
	_check(int(winner.get("gun_tokens_delta", -1)) == 250,
		"winner preview must award 250 placement Gun Tokens")
	_check(int(winner.get("trophy_delta", -1)) == 1,
		"Official Classic winner must receive exactly one Trophy")
	var third: Dictionary = RewardCalculator.for_actor(result, 3)
	_check(int(third.get("gun_tokens_delta", -1)) == 150,
		"third place must award 150 Tokens even with only three humans")
	(result["entries"] as Array).append({
		"actor_id": 4, "placement": 4, "round_wins": 0,
		"kills": 0, "disarms": 0, "rounds_participated": 3,
		"activity_eligible": true,
	})
	var fourth: Dictionary = RewardCalculator.for_actor(result, 4)
	_check(int(fourth.get("gun_tokens_delta", -1)) == 100,
		"every active non-podium finisher must award 100 Tokens")
	var forfeit_result := result.duplicate(true)
	forfeit_result["entries"] = [{
		"actor_id": 9, "placement": 1, "round_wins": 0,
		"kills": 0, "disarms": 0, "rounds_participated": 1,
		"activity_eligible": false, "finished_match": true,
		"forfeit_winner": true,
	}]
	var forfeit: Dictionary = RewardCalculator.for_actor(forfeit_result, 9)
	_check(int(forfeit.get("gun_tokens_delta", -1)) == 250
		and int(forfeit.get("xp_delta", -1)) == 45
		and int(forfeit.get("trophy_delta", -1)) == 1,
		"a sole finisher must receive first-place Tokens, actual XP, and a Trophy")
	var inactive_result := result.duplicate(true)
	inactive_result["entries"] = (result["entries"] as Array).duplicate(true)
	inactive_result["entries"][1] = (inactive_result["entries"][1] as Dictionary).duplicate(true)
	inactive_result["entries"][1]["activity_eligible"] = false
	var inactive: Dictionary = RewardCalculator.for_actor(inactive_result, 2)
	_check(str(inactive.get("state", "")) == "ineligible"
		and int(inactive.get("gun_tokens_delta", -1)) == 0,
		"inactive completion must not persist participation rewards")

	var departed_result := forfeit_result.duplicate(true)
	departed_result["entries"] = (forfeit_result["entries"] as Array).duplicate(true)
	departed_result["entries"][0] = (departed_result["entries"][0] as Dictionary).duplicate(true)
	departed_result["entries"][0]["finished_match"] = false
	var departed: Dictionary = RewardCalculator.for_actor(departed_result, 9)
	_check(str(departed.get("state", "")) == "ineligible",
		"a departed participant must not receive a reward")
	for pair in [[1, 150], [10, 168], [100, 348], [101, 350], [200, 548], [300, 748]]:
		_check(RewardCalculator.xp_required_for_level(int(pair[0])) == int(pair[1]),
			"client Season XP curve must match the server at Level %d" % int(pair[0]))
	for level in [1, 100, 545]:
		_check(RewardCalculator.career_xp_required_for_level(level) == 400,
			"Career XP must remain flat at 400 per level")


	var catalog: Array[Dictionary] = [
		Catalog.normalize_item({"id": "hat", "display_name": "Hat",
			"item_type": "hat", "rarity": "common", "active": true,
			"shop_visible": true, "rotation_scope": "daily",
			"rotation_starts_at": null, "rotation_ends_at": null}),
		Catalog.normalize_item({"id": "theme", "display_name": "Theme",
			"item_type": "ceremony_theme", "rarity": "epic", "active": true,
			"shop_visible": true, "rotation_scope": "monthly"}),
		Catalog.normalize_item({"id": "gun", "display_name": "Gun",
			"item_type": "gun_skin", "rarity": "legendary", "active": true,
			"shop_visible": true, "rotation_scope": "seasonal_starter"}),
		Catalog.normalize_item({"id": "crest", "display_name": "Crest",
			"item_type": "profile_badge", "category": "profile",
			"subcategory": "badges", "rarity": "rare", "active": true,
			"shop_visible": false, "rotation_scope": "reward"}),
		Catalog.normalize_item({"id": "placeholder", "display_name": "Placeholder",
			"item_type": "hat", "rarity": "common", "active": true,
			"shop_visible": true}),
	]
	_check(Catalog.item_matches(catalog[0], "CHARACTER", "COSMETICS", "HATS"),
		"hat must appear in Character > Cosmetics > Hats")
	_check(Catalog.is_in_live_rotation(catalog[0]),
		"SQL-null rotation dates must keep an open-ended Prize Counter hat live")
	_check(Catalog.item_matches(catalog[1], "AUDIO", "WINNERS CIRCLE"),
		"ceremony theme must appear in Audio > Winners Circle")
	_check(Catalog.item_matches(catalog[2], "WEAPONS", "GUN SKINS"),
		"gun skin must appear in Weapons > Gun Skins")
	_check(Catalog.item_matches(catalog[3], "CHARACTER", "COSMETICS", "ALL"),
		"Trophy-road profile crest must appear with Character cosmetics")
	_check(not Catalog.is_in_live_rotation(catalog[4]),
		"unassigned placeholder must not silently enter a live rotation")
	_check(Catalog.is_in_live_rotation(catalog[2]),
		"assigned Seasonal Starter item must enter the live rotation")
	for migrated_hat_id in [
		"hat_chef", "hat_yellow_point", "hat_cowboy_classic",
		"hat_fedora_black", "hat_straw_adventurer", "hat_cowboy_wide",
		"hat_fedora_white", "hat_top", "hat_witch", "hat_crown",
	]:
		var migrated_hat := Catalog.normalize_item({
			"id": migrated_hat_id,
			"item_type": "hat",
			"category": "character",
			"subcategory": "hats",
			"active": true,
			"shop_visible": true,
			"rotation_scope": "daily",
			"rotation_starts_at": null,
			"rotation_ends_at": null,
		})
		_check(Catalog.is_in_live_rotation(migrated_hat)
			and Catalog.item_matches(
				migrated_hat, "CHARACTER", "COSMETICS", "HATS"),
			"migrated Prize Counter hat must remain live and browseable: %s"
				% migrated_hat_id)
	var sorted: Array[Dictionary] = Catalog.sorted_items(catalog, "rarity_asc")
	_check(str(sorted[0].get("id", "")) == "hat"
		and str(sorted[sorted.size() - 1].get("id", "")) == "gun",
		"default catalog order must be rarity low to high")

	if _failed:
		quit(1)
		return
	print("PROGRESSION_CATALOG_VALIDATION_OK")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("PROGRESSION_CATALOG_VALIDATION: %s" % message)
