class_name MatchRewardPreview
extends RefCounted

const RewardCalculator = preload("res://match_reward_calculator.gd")

# Compatibility facade kept for the already-polished Winners Circle. The real
# formula now lives in MatchRewardCalculator and is independently recalculated
# by Supabase before any persistent wallet/progression write.


static func for_actor(result: Dictionary, actor_id: int) -> Dictionary:
	return RewardCalculator.for_actor(result, actor_id)


static func summary_text(reward: Dictionary) -> String:
	return RewardCalculator.summary_text(reward)
