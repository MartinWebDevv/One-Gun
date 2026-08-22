class_name WinnersCircleMatchResult
extends RefCounted

const CosmeticRegistry = preload("res://supabase/supabase_cosmetic_registry.gd")


static func build_online(actor_state: Dictionary, champion_actor_id: int,
		official: bool) -> Dictionary:
	var entries: Array = []
	for actor_id_value in actor_state:
		var actor_id := int(actor_id_value)
		var state: Dictionary = actor_state[actor_id_value]
		entries.append(_entry_from_state(state, actor_id))
	_sort_and_place(entries, champion_actor_id)
	_mark_duplicate_names(entries)
	return {
		"schema": 1,
		"mode": GameConfig.game_mode,
		"mode_name": mode_display_name(GameConfig.game_mode),
		"official": official,
		"champion_actor_id": champion_actor_id,
		"trophy_awarded": official and champion_actor_id >= 0,
		"reward_state": "economy_pending",
		"entries": entries,
	}


static func build_local(players: Array, champion_actor_id: int,
		match_points: Dictionary, stat_round_wins: Dictionary,
		stat_runner_up: Dictionary, stat_third_place: Dictionary,
		stat_kills: Dictionary, stat_deaths: Dictionary,
		stat_disarms: Dictionary, stat_pickups: Dictionary,
		stat_melee: Dictionary) -> Dictionary:
	var entries: Array = []
	for player in players:
		if player == null or not is_instance_valid(player):
			continue
		var actor_id := int(player.get("actor_id"))
		var model_id := PlayerSkinRegistry.DEFAULT_MODEL_ID
		var skin_id := PlayerSkinRegistry.DEFAULT_SKIN_ID
		var cosmetics := CosmeticRegistry.empty_loadout()
		if "character_model_id" in player:
			model_id = PlayerSkinRegistry.sanitize_model_id(
				str(player.get("character_model_id")))
		if "character_skin_id" in player:
			skin_id = PlayerSkinRegistry.sanitize_skin_id(
				str(player.get("character_skin_id")))
		if "cosmetic_loadout" in player:
			cosmetics = CosmeticRegistry.sanitize_loadout(
				player.get("cosmetic_loadout"))
		entries.append({
			"actor_id": actor_id,
			"peer_id": -1,
			"name": str(player.get_display_name()) if player.has_method(
				"get_display_name") else "Player %d" % actor_id,
			"account_handle": "",
			"is_bot": bool(player.get("is_bot")) if "is_bot" in player else false,
			"skin_id": skin_id,
			"model_id": model_id,
			"cosmetics": cosmetics,
			"sets": int(match_points.get(player, 0)),
			"round_wins": int(stat_round_wins.get(player, 0)),
			"runner_up_finishes": int(stat_runner_up.get(player, 0)),
			"third_place_finishes": int(stat_third_place.get(player, 0)),
			"kills": int(stat_kills.get(player, 0)),
			"deaths": int(stat_deaths.get(player, 0)),
			"disarms": int(stat_disarms.get(player, 0)),
			"pickups": int(stat_pickups.get(player, 0)),
			"melee": int(stat_melee.get(player, 0)),
		})
	_sort_and_place(entries, champion_actor_id)
	_mark_duplicate_names(entries)
	return {
		"schema": 1,
		"mode": GameConfig.game_mode,
		"mode_name": mode_display_name(GameConfig.game_mode),
		"official": false,
		"champion_actor_id": champion_actor_id,
		"trophy_awarded": false,
		"reward_state": "local_results_only",
		"entries": entries,
	}


static func mode_display_name(mode: String) -> String:
	match mode:
		GameConfig.MODE_ONE_GUN:
			return "CLASSIC ONE GUN"
		GameConfig.MODE_ALL_GUN:
			return "ALL GUN"
		GameConfig.MODE_ONE_OF_US:
			return "ONE OF US"
	return "ONE GUN"


static func _entry_from_state(state: Dictionary, actor_id: int) -> Dictionary:
	return {
		"actor_id": actor_id,
		"peer_id": int(state.get("owner_peer_id", -1)),
		"name": str(state.get("name", "Player")),
		"account_handle": str(state.get("account_handle", "")),
		"is_bot": actor_id >= 10000,
		"skin_id": PlayerSkinRegistry.sanitize_skin_id(str(
			state.get("skin_id", PlayerSkinRegistry.DEFAULT_SKIN_ID))),
		"model_id": PlayerSkinRegistry.sanitize_model_id(str(
			state.get("model_id", PlayerSkinRegistry.DEFAULT_MODEL_ID))),
		"cosmetics": CosmeticRegistry.sanitize_loadout(state.get("cosmetics", {})),
		"sets": int(state.get("sets", 0)),
		"round_wins": int(state.get("total_round_wins", state.get("rounds", 0))),
		"runner_up_finishes": int(state.get("runner_up_finishes", 0)),
		"third_place_finishes": int(state.get("third_place_finishes", 0)),
		"kills": int(state.get("kills", 0)),
		"deaths": int(state.get("deaths", 0)),
		"disarms": int(state.get("disarms", 0)),
		"pickups": int(state.get("pickups", 0)),
		"melee": int(state.get("melee", 0)),
	}


static func _sort_and_place(entries: Array, champion_actor_id: int) -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_id := int(a.get("actor_id", -1))
		var b_id := int(b.get("actor_id", -1))
		if a_id == champion_actor_id and b_id != champion_actor_id:
			return true
		if b_id == champion_actor_id and a_id != champion_actor_id:
			return false
		for field in ["sets", "round_wins", "runner_up_finishes",
				"third_place_finishes", "kills", "disarms"]:
			var a_value := int(a.get(field, 0))
			var b_value := int(b.get(field, 0))
			if a_value != b_value:
				return a_value > b_value
		return a_id < b_id
	)
	for index in entries.size():
		(entries[index] as Dictionary)["placement"] = index + 1


static func _mark_duplicate_names(entries: Array) -> void:
	var counts := {}
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var name := str(entry.get("name", "Player")).to_lower()
		counts[name] = int(counts.get(name, 0)) + 1
	for entry_value in entries:
		var entry: Dictionary = entry_value
		entry["duplicate_name"] = int(counts.get(
			str(entry.get("name", "Player")).to_lower(), 0)) > 1
