extends RefCounted

# Stable development-only data used by the existing ONEGUN_UI_CAPTURE flow.
# It exercises the populated roads/profile layouts without contacting Supabase.


static func seed_backend(backend: Node) -> void:
	backend.access_token = "capture-session"
	backend.refresh_token = "capture-refresh"
	backend.authenticated_user_id = "00000000-0000-0000-0000-000000000077"
	backend.access_token_expires_at = int(Time.get_unix_time_from_system()) + 3600
	backend.login_state = "authenticated"
	backend.profile = {
		"id": backend.authenticated_user_id,
		"username": "Maverick",
		"username_changed_at": "2020-01-01T00:00:00Z",
	}
	backend.gun_tokens = 4321


static func snapshot() -> Dictionary:
	return {
		"season": {
			"id": "beta-season", "display_name": "Beta Season",
			"starts_at": "2026-08-24T00:00:00Z",
			"ends_at": "2026-11-24T00:00:00Z",
			"ruleset_id": "classic_beta_v1",
		},
		"progress": {
			"season_level": 27, "season_prestige": 0,
			"xp_into_level": 190, "next_level_xp": 202,
			"daily_victory_bonus_claimed": true,
			"total_xp": 6235, "trophies": 8, "official_matches": 42,
			"classic_wins": 8, "round_wins": 71, "kills": 186,
			"deaths": 143, "disarms": 94,
		},
		"career": {
			"levels_earned": 227, "career_level": 228, "career_prestige": 2,
			"xp_into_level": 190, "next_level_xp": 400,
			"lifetime_prestige": 2, "lifetime_level": 228,
		},
		"mode_stats": [
			{"mode": "one_gun", "wins": 31, "matches": 128,
				"best_finish": 1, "round_wins": 214, "kills": 692,
				"deaths": 510, "disarms": 337},
			{"mode": "all_guns", "wins": 7, "matches": 46,
				"best_finish": 1, "round_wins": 58, "kills": 209,
				"deaths": 182, "disarms": 76},
		],
		"legacy": [
			{"season_name": "Founders Trial", "final_level": 118,
				"final_prestige": 1, "career_level_snapshot": 104,
				"career_prestige_snapshot": 1, "trophies": 29, "classic_wins": 29},
			{"season_name": "Neon Circuit", "final_level": 104,
				"final_prestige": 1, "career_level_snapshot": 228,
				"career_prestige_snapshot": 2, "trophies": 24, "classic_wins": 24},
		],
		"match_history": [
			{"mode": "one_gun", "map_id": "res://maps/test/CityMap.tscn",
				"placement": 1, "xp_delta": 122, "gun_tokens_delta": 350,
				"trophy_delta": 1},
			{"mode": "one_gun", "map_id": "res://maps/test/ForestMap.tscn",
				"placement": 2, "xp_delta": 59, "gun_tokens_delta": 200,
				"trophy_delta": 0},
			{"mode": "all_guns", "map_id": "res://maps/test/catTower.tscn",
				"placement": 3, "xp_delta": 35, "gun_tokens_delta": 150,
				"trophy_delta": 0},
		],
		"level_road": [
			{"threshold": 5, "display_name": "Starter Stash", "gun_tokens": 50,
				"item_id": "", "rarity": "standard", "claimed": true},
			{"threshold": 10, "display_name": "Beta Trail", "gun_tokens": 0,
				"item_id": "beta_s1_level_10_trail", "rarity": "uncommon", "claimed": true},
			{"threshold": 15, "display_name": "Token Cache", "gun_tokens": 75,
				"item_id": "", "rarity": "standard", "claimed": true},
			{"threshold": 25, "display_name": "Token Cache", "gun_tokens": 75,
				"item_id": "", "rarity": "standard", "claimed": true},
			{"threshold": 30, "display_name": "Beta Banner", "gun_tokens": 0,
				"item_id": "beta_s1_level_30_banner", "rarity": "rare", "claimed": false},
			{"threshold": 35, "display_name": "Token Vault", "gun_tokens": 100,
				"item_id": "", "rarity": "standard", "claimed": false},
		],
		"trophy_road": [
			{"threshold": 1, "display_name": "First Victory Badge", "gun_tokens": 0,
				"item_id": "beta_s1_first_win_badge", "rarity": "uncommon", "claimed": true},
			{"threshold": 3, "display_name": "Bronze Champion Pose", "gun_tokens": 0,
				"item_id": "beta_s1_bronze_pose", "rarity": "rare", "claimed": true},
			{"threshold": 5, "display_name": "Silver Champion Move", "gun_tokens": 0,
				"item_id": "beta_s1_silver_move", "rarity": "epic", "claimed": true},
			{"threshold": 10, "display_name": "Golden Victory Theme", "gun_tokens": 0,
				"item_id": "beta_s1_golden_theme", "rarity": "legendary", "claimed": false},
			{"threshold": 20, "display_name": "Beta Ace Outfit", "gun_tokens": 0,
				"item_id": "beta_s1_ace_outfit", "rarity": "epic", "claimed": false},
		],
	}
