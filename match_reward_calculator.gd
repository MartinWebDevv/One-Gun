class_name MatchRewardCalculator
extends RefCounted

# Client-side presentation mirror of the database reward formula. Supabase
# independently recalculates every amount before writing a ledger entry; this
# class exists so the Winners Circle can explain a result immediately while
# the majority-confirmed receipt is being verified.

const XP_PARTICIPATION := 20
const XP_ROUND_WIN := 10
const XP_PLACEMENT := {1: 25, 2: 15, 3: 10}
const XP_KILL := 1
const XP_KILL_CAP := 10
const XP_DISARM := 3
const XP_DISARM_CAP := 5

const TOKEN_PLACEMENT := {1: 250, 2: 200, 3: 150}
const TOKEN_NON_PODIUM := 100


static func preview_for_actor(result: Dictionary, actor_id: int) -> Dictionary:
	return for_actor(result, actor_id)


static func for_actor(result: Dictionary, actor_id: int) -> Dictionary:
	var entry := entry_for_actor(result.get("entries", []), actor_id)
	if entry.is_empty():
		return _empty("spectator")
	if not bool(result.get("official", false)) \
			or str(result.get("mode", "")) != GameConfig.MODE_ONE_GUN:
		return _empty("results_only")
	var finished_match := bool(entry.get("finished_match", true))
	var forfeit_winner := bool(entry.get("forfeit_winner", false))
	if not finished_match or (not forfeit_winner \
			and (not bool(entry.get("activity_eligible", false)) \
			or int(entry.get("rounds_participated", 0)) < 2)):
		var ineligible := _empty("ineligible")
		ineligible["persisted"] = false
		return ineligible

	var placement := int(entry.get("placement", 0))
	var round_wins := clampi(int(entry.get("round_wins", 0)), 0, 3)
	var kills := maxi(int(entry.get("kills", 0)), 0)
	var disarms := maxi(int(entry.get("disarms", 0)), 0)
	var xp_breakdown := {
		"participation": XP_PARTICIPATION,
		"round_wins": round_wins * XP_ROUND_WIN,
		"placement": int(XP_PLACEMENT.get(placement, 0)),
		"eliminations": mini(kills, XP_KILL_CAP) * XP_KILL,
		"disarms": mini(disarms, XP_DISARM_CAP) * XP_DISARM,
	}
	var token_breakdown := {
		"placement": int(TOKEN_PLACEMENT.get(placement, TOKEN_NON_PODIUM)),
	}
	var match_xp := _sum_values(xp_breakdown)
	return {
		"state": "verifying",
		"xp_delta": match_xp,
		"season_xp_delta": match_xp,
		"career_xp_delta": match_xp,
		"gun_tokens_delta": _sum_values(token_breakdown),
		"trophy_delta": 1 if placement == 1 else 0,
		"xp_breakdown": xp_breakdown,
		"token_breakdown": token_breakdown,
		"daily_victory_bonus_pending": placement == 1,
		"daily_victory_bonus_awarded": false,
		"daily_victory_bonus_xp": 0,
		"daily_victory_bonus_tokens": 0,
		"level_road_tokens": 0,
		"unlocks": [],
		"persisted": false,
	}


static func season_xp_required_for_level(level: int) -> int:
	var safe_level := maxi(level, 1)
	return 150 + 2 * (safe_level - 1)


static func career_xp_required_for_level(_level: int) -> int:
	return 400


static func xp_required_for_level(level: int) -> int:
	return season_xp_required_for_level(level)


static func merge_receipt(preview: Dictionary, receipt: Dictionary) -> Dictionary:
	return merged_receipt(preview, receipt)


static func merged_receipt(preview: Dictionary, receipt: Dictionary) -> Dictionary:
	var result := preview.duplicate(true)
	for key in receipt:
		result[key] = receipt[key]
	result["state"] = "settled" if bool(receipt.get("persisted", false)) \
		else str(receipt.get("state", "verifying"))
	return result


static func summary_text(reward: Dictionary) -> String:
	match str(reward.get("state", "results_only")):
		"settled":
			return "+%d XP  •  +%d GUN TOKENS%s" % [
				int(reward.get("xp_delta", 0)),
				int(reward.get("gun_tokens_delta", 0)),
				"  •  +1 TROPHY" if int(reward.get("trophy_delta", 0)) > 0 else "",
			]
		"verifying", "pending":
			return "+%d XP  •  +%d GUN TOKENS  •  VERIFYING" % [
				int(reward.get("xp_delta", 0)), int(reward.get("gun_tokens_delta", 0))]
		"ineligible": return "NO REWARD  •  MATCH NOT COMPLETED ACTIVELY"
		"spectator": return "SPECTATING  •  NO PERSONAL REWARD"
	return "CUSTOM MATCH  •  RESULTS ONLY"


static func entry_for_actor(entries: Array, actor_id: int) -> Dictionary:
	for entry_value in entries:
		if entry_value is Dictionary \
				and int(entry_value.get("actor_id", -1)) == actor_id:
			return (entry_value as Dictionary).duplicate(true)
	return {}


static func _empty(state: String) -> Dictionary:
	return {
		"state": state,
		"xp_delta": 0,
		"season_xp_delta": 0,
		"career_xp_delta": 0,
		"gun_tokens_delta": 0,
		"trophy_delta": 0,
		"xp_breakdown": {},
		"token_breakdown": {},
		"daily_victory_bonus_pending": false,
		"daily_victory_bonus_awarded": false,
		"daily_victory_bonus_xp": 0,
		"daily_victory_bonus_tokens": 0,
		"level_road_tokens": 0,
		"unlocks": [],
		"persisted": false,
	}


static func _sum_values(values: Dictionary) -> int:
	var total := 0
	for value in values.values():
		total += int(value)
	return total
