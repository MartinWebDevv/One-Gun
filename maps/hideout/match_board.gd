extends "res://game_setup.gd"
## The same map, roster and settings UI, opened inside the Hideout.
signal closed

func _ready() -> void:
	var path := NetworkManager.pending_map_path if NetworkManager.is_online() else HideoutSession.selected_map
	if path == "": path = HideoutSession.selected_map
	super._ready()
	var index := MapRegistry.find_index_by_path(path)
	if path == RANDOM_MAP_SENTINEL:
		map_select_mode = MapSelectMode.RANDOM
	elif index >= 0:
		map_select_mode = MapSelectMode.SPECIFIC
		selected_map_index = index
	_select_map_dropdown_id(RANDOM_ITEM_ID if map_select_mode == MapSelectMode.RANDOM else selected_map_index)
	_sync_carousel()
	_update_map_info()
	if _map_preview != null: _map_preview.apply(map_select_mode, selected_map_index)
	_back_button.text = "BACK TO HIDEOUT"
	if _playpen_button != null:
		_playpen_button.text = "BACK TO THE ROOM"
		_playpen_button.disabled = false
	if not NetworkManager.is_online() or NetworkManager.can_manage_lobby(): _remember_selection()

func _setup_online_mode() -> void:
	# Opening a kiosk must never seed a default map over the current selection.
	if not _is_net(): return
	NetworkManager.lobby_changed.connect(_on_online_lobby_changed)
	NetworkManager.lobby_readiness_changed.connect(_on_lobby_readiness_changed)
	NetworkManager.lobby_notice.connect(_on_lobby_notice)
	NetworkManager.match_config_received.connect(_on_net_config_synced)
	NetworkManager.prelaunch_countdown_changed.connect(_on_prelaunch_countdown_changed)
	if not NetworkManager.can_manage_lobby(): _apply_client_lock()

func _on_settings_changed() -> void:
	_remember_selection()
	super._on_settings_changed()

func _on_map_dropdown_selected(index: int) -> void:
	super._on_map_dropdown_selected(index)
	_select_map_dropdown_id(RANDOM_ITEM_ID if map_select_mode == MapSelectMode.RANDOM else selected_map_index)
	_on_settings_changed()

func _remember_selection() -> void:
	if MAPS.is_empty(): return
	HideoutSession.selected_map = RANDOM_MAP_SENTINEL if map_select_mode == MapSelectMode.RANDOM else str(MAPS[selected_map_index].get("scene_path", ""))

func _on_back_button_pressed() -> void:
	if _player_settings_overlay != null or _lobby_player_hub_overlay != null or _prize_counter_overlay != null or _progression_overlay != null or _social_overlay != null or _character_customization_overlay != null or is_instance_valid(_settings_slideout):
		super._on_back_button_pressed()
		return
	closed.emit()
	queue_free()

func _on_playpen_pressed() -> void:
	_on_back_button_pressed()

func _on_net_host_left() -> void:
	closed.emit()
	queue_free()


func _update_playpen_availability() -> void:
	if _playpen_button != null:
		_playpen_button.text = "BACK TO THE ROOM"
		_playpen_button.tooltip_text = "Close the Game Board and return to your Hideout."
		_playpen_button.disabled = NetworkManager._prelaunch_active

func _on_social_join_requested(lobby: Dictionary) -> void:
	var hideout := get_tree().current_scene
	if hideout.has_method("_join_friend"): hideout._join_friend(lobby)
