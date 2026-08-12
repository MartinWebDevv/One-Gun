extends Node

# Focused regression harness for menu redesign Sections 3 and 4.

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	get_tree().root.size = Vector2i(1600, 900)
	var original := GameConfig.snapshot_for_preset()
	var original_dirty: bool = GameConfig.lobby_settings_dirty
	GameConfig.split_screen_enabled = false
	GameConfig.bot_configs = [
		{"difficulty": "hard", "team_id": -1},
		{"difficulty": "expert", "team_id": -1},
	]

	var lobby := preload("res://game_setup.tscn").instantiate()
	get_tree().root.add_child(lobby)
	await get_tree().process_frame
	await get_tree().process_frame

	# Section 3: a connected panel exists and edits a detached transaction.
	lobby._open_settings_slideout(lobby.LOBBY_SETTINGS_SLIDEOUT.Kind.BOT)
	await get_tree().process_frame
	var bot_panel = lobby._settings_slideout
	_check(bot_panel != null and bot_panel.name == "SettingsSlideout",
		"Bot controls open inside the unified connected Settings slide-out")
	_check(bot_panel._selected_tab == 4 and bot_panel._nav_buttons.size() == 7,
		"unified Settings opens directly to Bots and exposes every approved page")
	_check(lobby._bot_settings_button == null and lobby._match_settings_button.text == "SETTINGS",
		"lobby exposes one Settings entry instead of separate Bot and Match buttons")
	_check(bot_panel._apply_button.get_global_rect().end.y <= lobby.get_viewport_rect().end.y,
		"settings transaction footer remains visible inside the safe viewport")
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(bot_panel._apply_button.get_global_rect().end.y <= lobby.get_viewport_rect().end.y,
		"settings transaction footer remains visible at 1280x720")
	get_tree().root.size = Vector2i(1600, 900)
	await get_tree().process_frame
	bot_panel._on_bot_count_changed(3)
	_check(GameConfig.bot_configs.size() == 2,
		"pending bot count does not mutate live GameConfig")
	_check(bot_panel._pending["bot_configs"][0]["difficulty"] == "hard"
		and bot_panel._pending["bot_configs"][1]["difficulty"] == "expert",
		"increasing bot count preserves every existing per-bot difficulty")
	bot_panel._on_apply_pressed()
	await get_tree().process_frame
	_check(GameConfig.bot_configs.size() == 3,
		"Apply commits the pending bot transaction")
	_check(GameConfig.bot_configs[0]["difficulty"] == "hard"
		and GameConfig.bot_configs[1]["difficulty"] == "expert",
		"Apply retains preserved individual bot difficulties")

	var live_round_time: float = GameConfig.round_time_limit
	lobby._open_settings_slideout(lobby.LOBBY_SETTINGS_SLIDEOUT.Kind.MATCH)
	await get_tree().process_frame
	var match_panel = lobby._settings_slideout
	match_panel._pending["round_time_limit"] = 180.0
	match_panel._mark_changed()
	match_panel.close_without_applying()
	await get_tree().process_frame
	_check(GameConfig.round_time_limit == live_round_time,
		"Cancel discards pending match-rule changes")

	lobby._open_settings_slideout(lobby.LOBBY_SETTINGS_SLIDEOUT.Kind.MATCH)
	await get_tree().process_frame
	match_panel = lobby._settings_slideout
	match_panel._pending["round_time_limit"] = 240.0
	match_panel._pending["chaos_overtime_enabled"] = true
	match_panel._pending["item_registry"]["boomerang"]["enabled"] = false
	match_panel._on_reset_pressed()
	_check(float(match_panel._pending["round_time_limit"]) == 300.0,
		"Reset restores round time inside the pending transaction")
	_check(not bool(match_panel._pending["chaos_overtime_enabled"]),
		"Reset restores standard one-gun overtime")
	_check((match_panel._pending["item_registry"] as Dictionary).size()
			== (GameConfig.DEFAULT_VALUES["item_registry"] as Dictionary).size()
		and bool(match_panel._pending["item_registry"]["boomerang"]["enabled"]),
		"Reset restores every implemented item type")
	_check("round_time_limit" in GameConfig.PRESET_FIELDS,
		"preset snapshots include the implemented round timer")
	_check("chaos_overtime_enabled" in GameConfig.PRESET_FIELDS,
		"preset snapshots include the Chaos OT setting")
	match_panel.close_without_applying()
	await get_tree().process_frame

	# Section 4: exercise each cabinet page without inventing lobby rows.
	var overlay := preload("res://UI/online_play_overlay.gd").new()
	overlay.size = Vector2(1100, 760)
	get_tree().root.add_child(overlay)
	await get_tree().process_frame
	overlay.open("host")
	await get_tree().process_frame
	_check(overlay._page == overlay.Page.HOST and overlay._host_name != null,
		"Host Lobby uses the large online cabinet")
	_check(overlay._privacy_buttons["friends"].disabled,
		"Friends Only is honestly unavailable without an identity backend")
	overlay._set_host_privacy("private")
	_check(overlay._private_code_section.visible and overlay._host_code.text.length() == 6,
		"Private hosting exposes a generated share code")
	overlay.open("code")
	await get_tree().process_frame
	_check(overlay._page == overlay.Page.CODE and overlay._code_field != null,
		"Join by Code stays inside the same cabinet")
	overlay.open("")
	await get_tree().process_frame
	overlay._on_lobby_list_updated([])
	_check(overlay._rows_box.get_child_count() == 0 and overlay._browser_state.visible,
		"empty discovery renders an empty state with zero fake lobby rows")

	var hosted := NetworkManager.host_game(24747, "Phase Four Smoke", {
		"privacy": "private", "max_players": 10, "share_code": "ABCD23"})
	_check(hosted, "private metadata host starts on an isolated smoke port")
	if hosted:
		_check(NetworkManager.lobby_privacy == "private"
			and NetworkManager.lobby_max_players == 10
			and NetworkManager.lobby_share_code == "ABCD23",
			"NetworkManager retains real privacy, capacity and share-code metadata")
		var payload: Dictionary = NetworkManager._discovery_payload("smoke")
		NetworkManager.peers[1]["role"] = "participant"
		NetworkManager.set_one_of_us_volunteer(true)
		_check(NetworkManager.one_of_us_volunteer_actor_ids() == [1],
			"host-private One of Us volunteer preference resolves to its actor")
		_check(not NetworkManager.peers[1].has("one_of_us_volunteer"),
			"One of Us volunteer preference is not exposed in the shared roster")
		NetworkManager.peers[1]["role"] = "lobby"
		_check(payload["privacy"] == "private" and int(payload["max_players"]) == 10,
			"discovery payload exposes browser metadata without publishing the secret")
	NetworkManager.disconnect_net()

	overlay.queue_free()
	lobby.queue_free()
	GameConfig.apply_preset_values(original)
	GameConfig.lobby_settings_dirty = original_dirty
	await get_tree().process_frame
	if _failures == 0:
		print("PHASE 3+4 MENU SMOKE: PASS")
	else:
		push_error("PHASE 3+4 MENU SMOKE: %d failure(s)" % _failures)
	get_tree().quit(_failures)
