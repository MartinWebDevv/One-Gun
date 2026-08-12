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

	_check(lobby.MAPS.size() == 4, "shared registry exposes all four playable maps")
	_check(MapRegistry.available_indices().size() == lobby.MAPS.size(),
			"every registered map scene is available")
	_check(lobby._roster_list.get_child_count() == lobby.LOCAL_SLOT_CAP,
			"local roster renders exactly ten slots")
	_check(not lobby._play_button.disabled, "Play is enabled for a valid selected map")
	_check(ResourceLoader.exists(lobby._resolve_map_scene_path()),
			"selected map resolves to a playable scene")
	_check(lobby.get_viewport().gui_get_focus_owner() == lobby._map_dropdown,
			"controller/keyboard focus starts on the map selector")
	_check_preview_is_stripped(lobby, "Whispering Woods", 0)

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
				"%s headless preview resolves the expected map" % map_name)
		return
	_check(preview_map != null, "%s live preview loaded" % map_name)
	if preview_map == null:
		return
	for node_name in STRIPPED_GAMEPLAY_NODES:
		_check(preview_map.get_node_or_null(node_name) == null,
				"%s preview strips %s" % [map_name, node_name])
