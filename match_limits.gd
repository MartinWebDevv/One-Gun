class_name MatchLimits
extends RefCounted

# One source of truth for roster capacity. Humans and bots share this limit;
# eliminated lobby members keep their slot while spectating.
const MAX_TOTAL_ACTORS := 10
const MIN_ONLINE_HUMANS := 2


static func max_bots_for_humans(human_count: int) -> int:
	return maxi(MAX_TOTAL_ACTORS - maxi(human_count, 0), 0)
