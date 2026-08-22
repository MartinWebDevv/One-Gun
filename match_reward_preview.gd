class_name MatchRewardPreview
extends RefCounted

# Presentation boundary for the Winners Circle. The backend economy does not
# exist yet, so this deliberately returns no XP or Gun Token amount and never
# mutates Supabase. A future server-authoritative reward receipt can replace
# these pending fields without changing the podium or results UI contract.


static func for_actor(result: Dictionary, actor_id: int) -> Dictionary:
	var entry := _entry_for_actor(result.get("entries", []), actor_id)
	if entry.is_empty():
		return {
			"state": "spectator",
			"xp_delta": null,
			"gun_tokens_delta": null,
			"trophy_delta": 0,
			"persisted": false,
		}
	var official := bool(result.get("official", false))
	return {
		"state": "economy_pending" if official else "results_only",
		"xp_delta": null,
		"gun_tokens_delta": null,
		"trophy_delta": 1 if official and int(entry.get("placement", 0)) == 1 else 0,
		"persisted": false,
	}


static func summary_text(reward: Dictionary) -> String:
	match str(reward.get("state", "results_only")):
		"economy_pending":
			if int(reward.get("trophy_delta", 0)) > 0:
				return "+1 TROPHY  •  XP AND GUN TOKENS PENDING ECONOMY SETUP"
			return "XP AND GUN TOKENS PENDING ECONOMY SETUP"
		"spectator":
			return "SPECTATING  •  NO PERSONAL REWARD"
	return "CUSTOM MATCH  •  RESULTS ONLY"


static func _entry_for_actor(entries: Array, actor_id: int) -> Dictionary:
	for entry_value in entries:
		var entry: Dictionary = entry_value
		if int(entry.get("actor_id", -1)) == actor_id:
			return entry
	return {}
