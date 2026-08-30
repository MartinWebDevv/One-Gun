extends Node

# Focused headless regression harness for the redesigned local lobby.
# Run with:
#   Godot --headless --path <project> res://tools/menu_phase2_smoke.tscn

const STRIPPED_GAMEPLAY_NODES := [
	"RoundManager", "player1", "player2", "CanvasLayer", "SplitScreenLayer",
	"Gun", "MeleeWeaponSpawn", "MeleeWeaponSpawnp", "Melee Weapons",
	"Power Ups", "Powerups", "Items", "SpawnPoints", "ItemSpawnPoints",
	"gun_spawn_point", "NavigationRegion3D", "ForestAmbience",
]

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
	get_tree().root.size = Vector2i(1920, 1080)
	var original := GameConfig.snapshot_for_preset()

	var lobby := preload("res://game_setup.tscn").instantiate()
	get_tree().root.add_child(lobby)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(lobby.MAPS.size() == 6, "shared registry exposes all six playable maps")
	_check(MapRegistry.available_indices().size() == lobby.MAPS.size(),
			"every registered map scene is available")
	_check(lobby._roster_list.get_child_count() == lobby.LOCAL_SLOT_CAP,
			"local roster renders exactly ten slots")
	_check(not lobby._play_button.disabled, "Play is enabled for a valid selected map")
	_check(ResourceLoader.exists(lobby._resolve_map_scene_path()),
			"selected map resolves to a playable scene")
	_check(lobby.get_viewport().gui_get_focus_owner() == lobby._map_dropdown,
			"controller/keyboard focus starts on the map selector")
	await get_tree().create_timer(0.9).timeout
	_check_preview_is_stripped(lobby, "Cat Tower", 3)

	# The ten-row, four-team roster is the widest real lobby state. It must not
	# force the right cabinet or any row beyond the 1920x1080 safe frame.
	GameConfig.teams_enabled = true
	GameConfig.team_count = 4
	GameConfig.set_bot_count(9)
	for index in GameConfig.bot_configs.size():
		GameConfig.bot_configs[index]["team_id"] = index % GameConfig.team_count
	lobby._on_settings_changed()
	await get_tree().process_frame
	var roster_rect: Rect2 = lobby._roster_cabinet.get_global_rect()
	_check(roster_rect.end.x <= lobby.get_viewport_rect().end.x,
			"roster cabinet stays inside the 1920x1080 frame")
	for row in lobby._roster_list.get_children():
		_check(row.get_global_rect().end.x <= roster_rect.end.x,
				"roster row stays inside the cabinet")

	# Online lobbies add the Friends orb above the roster. Exercise the same
	# responsive layout at every supported menu tier without opening a socket.
	# All ten rows must remain visible and the orb must own separate screen space.
	lobby._build_lobby_friends_quick_access()
	for test_size in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		get_tree().root.size = test_size
		lobby._apply_responsive_layout()
		await get_tree().process_frame
		await get_tree().process_frame
		roster_rect = lobby._roster_cabinet.get_global_rect()
		var orb_rect: Rect2 = lobby._friends_orb.get_global_rect()
		_check(not roster_rect.intersects(orb_rect),
				"Friends orb does not overlap roster at %dx%d" % [
					test_size.x, test_size.y])
		_check(lobby._roster_list.get_child_count() == lobby.LOCAL_SLOT_CAP,
				"all ten roster slots remain built at %dx%d" % [
					test_size.x, test_size.y])
		var roster_list_rect: Rect2 = lobby._roster_list.get_global_rect()
		var roster_viewport_rect: Rect2 = lobby._roster_viewport.get_global_rect()
		var row_heights: Array[float] = []
		for row in lobby._roster_list.get_children():
			var row_rect: Rect2 = row.get_global_rect()
			row_heights.append(row_rect.size.y)
			_check(row_rect.position.y >= roster_rect.position.y - 0.5 \
					and row_rect.end.y <= roster_rect.end.y + 0.5,
					"roster row stays vertically visible at %dx%d" % [
						test_size.x, test_size.y])
		var first_row_rect: Rect2 = lobby._roster_list.get_child(0).get_global_rect()
		var last_row_rect: Rect2 = lobby._roster_list.get_child(
			lobby._roster_list.get_child_count() - 1).get_global_rect()
		_check(absf(roster_list_rect.size.y - roster_viewport_rect.size.y) <= 1.0,
				"roster cards fill the full usable panel height at %dx%d" % [
					test_size.x, test_size.y])
		_check(absf(first_row_rect.position.y - roster_list_rect.position.y) <= 1.0 \
				and absf(last_row_rect.end.y - roster_list_rect.end.y) <= 1.0,
				"first and tenth roster cards reach both panel edges at %dx%d" % [
					test_size.x, test_size.y])
		_check(row_heights.max() - row_heights.min() <= 1.0,
				"all ten roster cards have equal height at %dx%d" % [
					test_size.x, test_size.y])
	get_tree().root.size = Vector2i(1920, 1080)
	lobby._apply_responsive_layout()
	await get_tree().process_frame

	# Random mode must present a mystery, not whichever preview happened to be
	# visible when the host selected Random Rotation.
	lobby._on_map_dropdown_selected(lobby.MAPS.size())
	_check(lobby.map_select_mode == lobby.MapSelectMode.RANDOM,
			"Random Map selects random rotation")
	_check(lobby._map_preview.current_index() == -1,
			"Random Map hides the live map preview")
	_check(lobby._banner_desc.text.contains("hidden"),
			"Random Map explains that the battlefield is hidden")

	# Two selections during one fade must settle on the latest request instead
	# of leaving metadata/card selection ahead of the live preview.
	lobby._on_map_card_selected(1)
	lobby._on_map_card_selected(2)
	await get_tree().create_timer(1.6).timeout
	_check(lobby.selected_map_index == 2, "rapid carousel input keeps the latest selection")
	_check(lobby._map_preview.current_index() == 2,
			"rapid carousel input and live preview remain synchronized")
	_check_preview_is_stripped(lobby, "Maple & 3rd", 2)

	lobby._on_map_card_selected(1)
	await get_tree().create_timer(0.9).timeout
	_check(lobby._map_preview.current_index() == 1, "live preview switches within the fade window")
	_check_preview_is_stripped(lobby, "Western Town", 1)

	# Capacity must remain ten when the second local human is enabled.
	GameConfig.split_screen_enabled = true
	GameConfig.set_bot_count(9)
	lobby._on_settings_changed()
	_check(GameConfig.bot_configs.size() == 8, "splitscreen clamps bots to the eight-slot capacity")
	_check(lobby._roster_list.get_child_count() == lobby.LOCAL_SLOT_CAP,
			"splitscreen plus bots still renders ten total roster slots")

	GameConfig.apply_preset_values(original)
	lobby.queue_free()
	await get_tree().process_frame

	if _failures == 0:
		print("PHASE 2 MENU SMOKE: PASS")
	else:
		push_error("PHASE 2 MENU SMOKE: %d failure(s)" % _failures)
	get_tree().quit(_failures)


func _check_preview_is_stripped(lobby: Control, map_name: String, expected_index: int) -> void:
	var preview_map: Node3D = lobby._map_preview._current_map
	if DisplayServer.get_name() == "headless":
		_check(lobby._map_preview.current_index() == expected_index,
				"%s headless preview resolves the expected map (expected=%d actual=%d)" % [
					map_name, expected_index, lobby._map_preview.current_index()])
		return
	_check(preview_map != null, "%s live preview loaded" % map_name)
	if preview_map == null:
		return
	for node_name in STRIPPED_GAMEPLAY_NODES:
		_check(preview_map.get_node_or_null(node_name) == null,
				"%s preview strips %s" % [map_name, node_name])
