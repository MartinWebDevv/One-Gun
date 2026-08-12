extends Control

# ============================================================
# Local Play lobby (menu redesign Phase 2) with connected Phase 3 settings.
#
# Layout: left cabinet (map/mode/settings/back), full-screen live map
# preview, top map-info banner + stat card, bottom map carousel, right
# roster (up to 10 slots), gold PLAY action.
#
# Local play has NO ready states (locked behavior). Bot count/difficulty
# live in transactional Bot Settings and Match Settings slide-outs.
#
# Online (host-authoritative) reuses this scene until Phase 5: clients get
# locked controls and a "waiting for host" Play action.
# ============================================================

# Map metadata single source of truth (see map_registry.gd). Re-exported so
# existing consumers (menu_map_cycler, lobby_map_preview) keep reading
# game_setup.MAPS unchanged.
const MAPS = preload("res://map_registry.gd").MAPS
const MatchLimitsData = preload("res://match_limits.gd")
const LOBBY_SETTINGS_SLIDEOUT = preload("res://UI/lobby_settings_slideout.gd")
const CONFIRM_BUTTON = preload("res://UI/components/one_gun_confirm_button.gd")

# Order matters: lobby_map_preview.MODE_SPECIFIC assumes SPECIFIC == 1.
enum MapSelectMode { VOTE, SPECIFIC, RANDOM }

const RANDOM_ITEM_ID := 1000
const RANDOM_MAP_SENTINEL := "__random_map_pending__"
const LOCAL_SLOT_CAP := MatchLimitsData.MAX_TOTAL_ACTORS
const ONLINE_SLOT_CAP := NetworkManager.MAX_PEERS

var map_select_mode: int = MapSelectMode.SPECIFIC
var selected_map_index: int = 0

# Live 3D map preview behind the UI (perimeter-orbit camera).
var _map_preview = null

# UI references (built procedurally in _build_lobby_ui).
var _map_dropdown: OptionButton
var _mode_dropdown: OptionButton
var _bot_settings_button: OneGunButton
var _match_settings_button: OneGunButton
var _character_customization_button: OneGunButton
var _player_settings_button: OneGunButton
var _playpen_button: OneGunButton
var _one_of_us_preference_panel: OneGunCabinet
var _one_of_us_resist_buttons: Array[OneGunButton] = []
var _one_of_us_let_in_buttons: Array[OneGunButton] = []
var _back_button: OneGunButton
var _play_button: OneGunButton
var _banner_name: Label
var _banner_desc: Label
var _info_labels := {}          # stat key -> value Label
var _roster_title: Label
var _roster_list: VBoxContainer
var _map_cards: Array = []      # OneGunMapCard per map
var _carousel_prev: OneGunButton
var _carousel_next: OneGunButton
var _thumbnails := {}           # map index -> ImageTexture captured from live preview
var _settings_slideout = null
var _match_settings_popup: PopupPanel # legacy builder retained only for old saved scene compatibility
var _settings_layer: CanvasLayer
var _character_customization_overlay: Control
var _player_settings_overlay: Control
var _settings_target_position := Vector2.ZERO
var _settings_tween: Tween
var _left_cabinet: OneGunCabinet
var _top_strip: HBoxContainer
var _info_card: OneGunCabinet
var _roster_cabinet: OneGunCabinet
var _carousel_cabinet: OneGunCabinet
var _cards_row: HBoxContainer
var _lobby_code_label: Label
var _privacy_dropdown: OptionButton
var _lobby_notice_label: Label

const LAYOUT_MARGIN := 24.0
const LAYOUT_GAP := 20.0
const COMPACT_MARGIN := 16.0
const COMPACT_GAP := 12.0
const LEFT_WIDTH := 360.0
const RIGHT_WIDTH := 440.0
const COMPACT_LEFT_WIDTH := 310.0
const COMPACT_RIGHT_WIDTH := 380.0
const TOP_STRIP_HEIGHT := 190.0
const CAROUSEL_HEIGHT := 148.0
const PLAY_HEIGHT := 84.0


func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_map_preview()
	_build_lobby_ui()
	_setup_online_mode()
	_clamp_bot_count_to_capacity()
	_refresh_roster()
	_update_map_info()
	_sync_carousel()
	_apply_responsive_layout()
	resized.connect(_apply_responsive_layout)
	_configure_focus_navigation.call_deferred()
	_open_capture_state.call_deferred()
	var capture_state := OS.get_environment("ONEGUN_UI_CAPTURE_STATE")
	var capture_name := capture_state if capture_state in ["bot_settings", "match_settings",
		"lobby_host", "lobby_guest", "lobby_customization", "lobby_one_of_us"] else "local_lobby"
	UICapture.maybe_capture(self, capture_name, 2.5)


# ============================================================
# Online (network) integration — host-authoritative lobby.
# ============================================================
func _is_net() -> bool:
	return NetworkManager.is_online()


func _setup_online_mode():
	if not _is_net():
		return
	NetworkManager.lobby_changed.connect(_on_online_lobby_changed)
	NetworkManager.lobby_readiness_changed.connect(_on_lobby_readiness_changed)
	NetworkManager.lobby_notice.connect(_on_lobby_notice)
	NetworkManager.match_config_received.connect(_on_net_config_synced)
	NetworkManager.server_disconnected.connect(_on_net_host_left)
	NetworkManager.prelaunch_countdown_changed.connect(_on_prelaunch_countdown_changed)
	if NetworkManager.is_host():
		_net_broadcast_config()   # seed clients with the starting config/map
	else:
		_apply_client_lock()


func _max_online_bots() -> int:
	return maxi(ONLINE_SLOT_CAP - NetworkManager.peers.size(), 0) if _is_net() else LOCAL_SLOT_CAP - _local_human_count()


func _local_human_count() -> int:
	return 2 if GameConfig.split_screen_enabled else 1


func _planned_actor_count() -> int:
	var human_count := NetworkManager.peers.size() if _is_net() else _local_human_count()
	return human_count + GameConfig.bot_configs.size()


func _clamp_bot_count_to_capacity() -> void:
	# Never let a stale preset or a splitscreen toggle create more actors than
	# the lobby can render/start. Online clients only display host-owned state.
	if _is_net() and not NetworkManager.is_host():
		return
	var capacity := _max_online_bots()
	if GameConfig.bot_configs.size() > capacity:
		GameConfig.set_bot_count(capacity)


func _on_online_lobby_changed() -> void:
	if NetworkManager.is_host() and GameConfig.bot_count > _max_online_bots():
		GameConfig.set_bot_count(_max_online_bots())
		_net_broadcast_config()
	_refresh_roster()
	_refresh_online_session_ui()
	_update_map_info()
	_reset_force_start_confirmation()
	_update_playpen_availability()


func _on_lobby_readiness_changed() -> void:
	_refresh_roster()
	_update_lobby_action()
	_reset_force_start_confirmation()


func _on_lobby_notice(message: String) -> void:
	if _lobby_notice_label != null:
		_lobby_notice_label.text = message


func _net_broadcast_config():
	if _is_net() and NetworkManager.is_host():
		var sync_path := RANDOM_MAP_SENTINEL if map_select_mode == MapSelectMode.RANDOM \
			else _resolve_map_scene_path()
		NetworkManager.broadcast_match_config(GameConfig.snapshot_for_network(), sync_path)


func _on_net_config_synced():
	if _mode_dropdown != null:
		var mode_index := GameConfig.GAME_MODES.find(GameConfig.game_mode)
		_mode_dropdown.select(maxi(mode_index, 0))
	_refresh_one_of_us_preference_panel()
	# Client: reflect the host's map choice in the preview + picker + carousel.
	if NetworkManager.pending_map_path == RANDOM_MAP_SENTINEL:
		map_select_mode = MapSelectMode.RANDOM
		if _map_dropdown != null:
			_map_dropdown.select(MAPS.size())
		if _map_preview != null:
			_map_preview.apply(MapSelectMode.RANDOM, selected_map_index)
		_sync_carousel()
		_update_map_info()
		_refresh_roster()
		return
	var index := MapRegistry.find_index_by_path(NetworkManager.pending_map_path)
	if index >= 0:
		selected_map_index = index
		map_select_mode = MapSelectMode.SPECIFIC
		if _map_dropdown != null:
			_map_dropdown.select(index)
		if _map_preview != null:
			_map_preview.apply(MapSelectMode.SPECIFIC, index)
		_sync_carousel()
		_update_map_info()
	_refresh_roster()


func _apply_client_lock():
	# Clients can't touch host-owned lobby state — host configures for everyone.
	for control in [_map_dropdown, _mode_dropdown, _bot_settings_button,
			_carousel_prev, _carousel_next]:
		if control != null:
			control.disabled = true
	for card in _map_cards:
		card.disabled = true
	_update_lobby_action()


func _on_net_host_left():
	# Host disappeared — bail back to the main menu.
	get_tree().change_scene_to_file("res://main_menu.tscn")


# ============================================================
# Live map preview + carousel thumbnails
# ============================================================
func _build_map_preview():
	_map_preview = preload("res://lobby_map_preview.gd").new()
	add_child(_map_preview)
	_map_preview.setup(self, MAPS)
	# Connect before apply(): the first map load emits map_shown synchronously.
	_map_preview.map_shown.connect(_on_preview_map_shown)
	_map_preview.apply(map_select_mode, selected_map_index)


func _on_preview_map_shown(index: int) -> void:
	if _thumbnails.has(index):
		return
	# Let the freshly loaded map render a few frames before snapshotting.
	await get_tree().create_timer(0.5).timeout
	if _map_preview == null or _map_preview.current_index() != index:
		return
	var image: Image = _map_preview.capture_image()
	if image == null:
		return
	image.resize(320, 180, Image.INTERPOLATE_BILINEAR)
	_thumbnails[index] = ImageTexture.create_from_image(image)
	if index < _map_cards.size():
		_map_cards[index].set_map(index, MAPS[index]["name"], _thumbnails[index], MAPS[index]["tint"])


# ============================================================
# UI construction
# ============================================================
func _build_lobby_ui() -> void:
	# CanvasLayer layer numbers are absolute, even when one CanvasLayer is
	# nested beneath another. The host returns from The Playpen into a lobby
	# overlay on layer 150, so a hard-coded modal layer of 20 would place
	# Settings and Character Customization behind the visible lobby.
	var containing_canvas_layer := 0
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is CanvasLayer:
			containing_canvas_layer = (ancestor as CanvasLayer).layer
			break
		ancestor = ancestor.get_parent()

	_build_left_cabinet()
	_build_top_strip()
	_build_roster_panel()
	_build_carousel()
	_build_play_action()
	_settings_layer = CanvasLayer.new()
	_settings_layer.name = "SettingsSlideoutLayer"
	_settings_layer.layer = containing_canvas_layer + 20
	add_child(_settings_layer)


func _build_left_cabinet() -> void:
	_left_cabinet = OneGunCabinet.new()
	_left_cabinet.name = "LeftCabinet"
	_left_cabinet.variant = OneGunCabinet.Variant.CABINET
	_left_cabinet.anchor_left = 0.0
	_left_cabinet.anchor_top = 0.0
	_left_cabinet.anchor_right = 0.0
	_left_cabinet.anchor_bottom = 1.0
	add_child(_left_cabinet)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	_left_cabinet.get_content().add_child(column)

	var logo := TextureRect.new()
	# The source logo is intentionally padded for the main-menu composition.
	# Crop that transparent staging area here so the lobby gets the large,
	# cabinet-mounted logo from the approved composition.
	var logo_crop := AtlasTexture.new()
	logo_crop.atlas = preload("res://UI/MainMenu/OneGunLogoV1.png")
	logo_crop.region = Rect2(320, 170, 920, 560)
	logo.texture = logo_crop
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 132)
	column.add_child(logo)

	var mode_title := "ONLINE LOBBY" if _is_net() else "LOCAL PLAY"
	var title := OneGunUI.make_heading(mode_title, OneGunUI.TEXT_L)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	if _is_net() and NetworkManager.lobby_name != "":
		var lobby_label := OneGunUI.make_label(NetworkManager.lobby_name, OneGunUI.TEXT_S, "cyan")
		lobby_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(lobby_label)
	if _is_net():
		_build_online_session_controls(column)

	column.add_child(OneGunUI.make_label("MAP", OneGunUI.TEXT_XS, "muted", true))
	_map_dropdown = OneGunUI.make_dropdown()
	for i in MAPS.size():
		_map_dropdown.add_item(str(MAPS[i].get("name", "Unnamed Map")), i)
	if MAPS.is_empty():
		_map_dropdown.add_item("No maps available", -1)
		_map_dropdown.disabled = true
	else:
		_map_dropdown.add_item("Random Map", RANDOM_ITEM_ID)
		_map_dropdown.select(clampi(selected_map_index, 0, MAPS.size() - 1))
	_map_dropdown.item_selected.connect(_on_map_dropdown_selected)
	column.add_child(_map_dropdown)

	column.add_child(OneGunUI.make_label("GAME MODE", OneGunUI.TEXT_XS, "muted", true))
	_mode_dropdown = OneGunUI.make_dropdown(PackedStringArray(["ONE GUN", "ALL GUN", "ONE OF US"]))
	_mode_dropdown.select(maxi(GameConfig.GAME_MODES.find(GameConfig.game_mode), 0))
	_mode_dropdown.item_selected.connect(_on_mode_dropdown_selected)
	_mode_dropdown.tooltip_text = "Choose the rules used for this match."
	column.add_child(_mode_dropdown)
	_build_one_of_us_preference_panel(column)

	_bot_settings_button = null
	_match_settings_button = _make_cabinet_button("SETTINGS")
	_match_settings_button.pressed.connect(_on_match_settings_button_pressed)
	column.add_child(_match_settings_button)
	_character_customization_button = _make_cabinet_button("CHARACTER CUSTOMIZATION")

	_character_customization_button.pressed.connect(_on_character_customization_pressed)
	column.add_child(_character_customization_button)

	_player_settings_button = _make_cabinet_button("PLAYER SETTINGS")
	_player_settings_button.pressed.connect(_on_player_settings_pressed)
	column.add_child(_player_settings_button)
	if _is_net():
		_playpen_button = _make_cabinet_button("THE PLAYPEN")
		_playpen_button.tooltip_text = "Enter the online practice room."
		_playpen_button.pressed.connect(_on_playpen_pressed)
		column.add_child(_playpen_button)
		_update_playpen_availability()

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	_back_button = OneGunButton.new()
	_back_button.variant = "navy"
	_back_button.text = "LEAVE LOBBY" if _is_net() and not NetworkManager.is_host() else "BACK"
	var back_icon := OneGunIcon.new()
	back_icon.kind = OneGunIcon.Kind.CHEVRON_LEFT
	back_icon.icon_color = OneGunUI.color("text")
	back_icon.custom_minimum_size = Vector2(18, 18)
	back_icon.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	back_icon.position = Vector2(14, 0)
	_back_button.add_child(back_icon)
	_back_button.pressed.connect(_on_back_button_pressed)
	column.add_child(_back_button)


func _build_online_session_controls(column: VBoxContainer) -> void:
	var session := OneGunCabinet.new()
	session.variant = OneGunCabinet.Variant.SECTION
	session.content_padding = OneGunUI.SPACE_S
	column.add_child(session)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	session.get_content().add_child(box)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	_lobby_code_label = OneGunUI.make_label("CODE: --", OneGunUI.TEXT_S, "cyan", true)
	_lobby_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(_lobby_code_label)
	var copy := OneGunButton.new()
	copy.variant = "navy"
	copy.text = "COPY"
	copy.custom_minimum_size = Vector2(76, 38)
	copy.pressed.connect(_copy_lobby_code)
	code_row.add_child(copy)
	box.add_child(code_row)

	var invite := OneGunButton.new()
	invite.variant = "navy"
	invite.text = "INVITE UNAVAILABLE"
	invite.disabled = true
	invite.tooltip_text = "Platform invites are not available in this build. Share the lobby code instead."
	box.add_child(invite)

	var privacy_row := HBoxContainer.new()
	privacy_row.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	privacy_row.add_child(OneGunUI.make_label("PRIVACY", OneGunUI.TEXT_XS, "muted", true))
	_privacy_dropdown = OneGunUI.make_dropdown(PackedStringArray(["PUBLIC", "PRIVATE"]))
	_privacy_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_privacy_dropdown.disabled = not NetworkManager.is_host()
	_privacy_dropdown.item_selected.connect(_on_privacy_selected)
	privacy_row.add_child(_privacy_dropdown)
	box.add_child(privacy_row)

	_lobby_notice_label = OneGunUI.make_label("", OneGunUI.TEXT_XS, "muted")
	_lobby_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_lobby_notice_label)
	_refresh_online_session_ui()


func _refresh_online_session_ui() -> void:
	if not _is_net():
		return
	if _lobby_code_label != null:
		_lobby_code_label.text = "CODE: %s" % (NetworkManager.lobby_share_code if NetworkManager.lobby_share_code != "" else "--")
	if _privacy_dropdown != null:
		_privacy_dropdown.select(1 if NetworkManager.lobby_privacy == "private" else 0)
		_privacy_dropdown.disabled = not NetworkManager.is_host()


func _copy_lobby_code() -> void:
	if NetworkManager.lobby_share_code == "":
		return
	DisplayServer.clipboard_set(NetworkManager.lobby_share_code)
	_on_lobby_notice("Lobby code copied")


func _on_privacy_selected(index: int) -> void:
	if not NetworkManager.is_host():
		_refresh_online_session_ui()
		return
	NetworkManager.set_lobby_privacy("private" if index == 1 else "public")


func _build_one_of_us_preference_panel(parent: VBoxContainer) -> void:
	_one_of_us_preference_panel = OneGunCabinet.new()
	_one_of_us_preference_panel.name = "OneOfUsPreference"
	_one_of_us_preference_panel.variant = OneGunCabinet.Variant.SECTION
	_one_of_us_preference_panel.content_padding = OneGunUI.SPACE_S
	parent.add_child(_one_of_us_preference_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", OneGunUI.SPACE_XS)
	_one_of_us_preference_panel.get_content().add_child(column)
	column.add_child(OneGunUI.make_heading("HEAR THE CALL?", OneGunUI.TEXT_S, "gold"))
	var description := OneGunUI.make_label(
		"Privately volunteer for the first THEM draw.", OneGunUI.TEXT_XS, "muted")
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)
	_one_of_us_resist_buttons.clear()
	_one_of_us_let_in_buttons.clear()
	var player_rows := 1 if _is_net() else _local_human_count()
	for player_index in player_rows:
		if player_rows > 1:
			column.add_child(OneGunUI.make_label(
				"PLAYER %d" % (player_index + 1), OneGunUI.TEXT_XS, "cyan", true))
		var choices := HBoxContainer.new()
		choices.add_theme_constant_override("separation", OneGunUI.SPACE_XS)
		column.add_child(choices)
		var resist := OneGunButton.new()
		resist.text = "RESIST"
		resist.custom_minimum_size.y = 36.0
		resist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		resist.tooltip_text = "Do not volunteer; random fallback still applies if nobody volunteers."
		resist.pressed.connect(_set_one_of_us_preference.bind(player_index, false))
		choices.add_child(resist)
		_one_of_us_resist_buttons.append(resist)
		var let_in := OneGunButton.new()
		let_in.text = "LET IT IN"
		let_in.custom_minimum_size.y = 36.0
		let_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		let_in.tooltip_text = "Privately join the pool for first THEM."
		let_in.pressed.connect(_set_one_of_us_preference.bind(player_index, true))
		choices.add_child(let_in)
		_one_of_us_let_in_buttons.append(let_in)
	_refresh_one_of_us_preference_panel()


func _set_one_of_us_preference(player_index: int, volunteer: bool) -> void:
	if NetworkManager._prelaunch_active or NetworkManager.lobby_in_progress:
		return
	if _is_net():
		NetworkManager.set_one_of_us_volunteer(volunteer)
	else:
		while GameConfig.local_one_of_us_volunteers.size() < 2:
			GameConfig.local_one_of_us_volunteers.append(false)
		GameConfig.local_one_of_us_volunteers[player_index] = volunteer
	_refresh_one_of_us_preference_panel()


func _refresh_one_of_us_preference_panel() -> void:
	if _one_of_us_preference_panel == null:
		return
	_one_of_us_preference_panel.visible = GameConfig.game_mode == GameConfig.MODE_ONE_OF_US
	for player_index in _one_of_us_resist_buttons.size():
		var volunteer := NetworkManager.is_one_of_us_volunteer() if _is_net() \
			else bool(GameConfig.local_one_of_us_volunteers[player_index])
		_one_of_us_resist_buttons[player_index].variant = "navy" if volunteer else "blue"
		_one_of_us_let_in_buttons[player_index].variant = "purple" if volunteer else "navy"
		var locked := NetworkManager._prelaunch_active or NetworkManager.lobby_in_progress
		_one_of_us_resist_buttons[player_index].disabled = locked
		_one_of_us_let_in_buttons[player_index].disabled = locked

func _make_cabinet_button(text: String) -> OneGunButton:
	var button := OneGunButton.new()
	button.variant = "navy"
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var chevron := OneGunIcon.new()
	chevron.kind = OneGunIcon.Kind.CHEVRON_RIGHT
	chevron.icon_color = OneGunUI.color("gold")
	chevron.custom_minimum_size = Vector2(16, 16)
	chevron.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	chevron.position = Vector2(-30, 0)
	button.add_child(chevron)
	return button


func _build_top_strip() -> void:
	# Banner + stat card share one anchored strip so narrow viewports shrink
	# the banner instead of letting the two panels overlap.
	_top_strip = HBoxContainer.new()
	_top_strip.name = "TopStrip"
	_top_strip.add_theme_constant_override("separation", 16)
	_top_strip.anchor_left = 0.0
	_top_strip.anchor_right = 1.0
	add_child(_top_strip)

	var banner := OneGunCabinet.new()
	banner.name = "MapBanner"
	banner.variant = OneGunCabinet.Variant.SECTION
	banner.content_padding = OneGunUI.SPACE_M
	banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_top_strip.add_child(banner)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	banner.get_content().add_child(box)
	_banner_name = OneGunUI.make_heading("", OneGunUI.TEXT_XL, "text_bright")
	_banner_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_banner_name)
	_banner_desc = OneGunUI.make_label("", OneGunUI.TEXT_S, "muted")
	_banner_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_banner_desc)

	_info_card = OneGunCabinet.new()
	_info_card.name = "MapInfoCard"
	_info_card.variant = OneGunCabinet.Variant.SECTION
	_info_card.content_padding = OneGunUI.SPACE_M
	_info_card.custom_minimum_size = Vector2(230, 0)
	_info_card.size_flags_horizontal = Control.SIZE_SHRINK_END
	_top_strip.add_child(_info_card)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	_info_card.get_content().add_child(rows)
	for stat in [["size", "SIZE"], ["recommended_players", "RECOMMENDED"],
			["playstyle", "PLAYSTYLE"], ["hazards", "HAZARDS"]]:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		row.add_child(OneGunUI.make_label(stat[1], OneGunUI.TEXT_XS, "muted", true))
		var value := OneGunUI.make_label("", OneGunUI.TEXT_M, "gold", true)
		_info_labels[stat[0]] = value
		row.add_child(value)
		rows.add_child(row)


func _build_roster_panel() -> void:
	_roster_cabinet = OneGunCabinet.new()
	_roster_cabinet.name = "RosterCabinet"
	_roster_cabinet.variant = OneGunCabinet.Variant.CABINET
	_roster_cabinet.content_padding = OneGunUI.SPACE_M
	_roster_cabinet.clip_contents = true
	_roster_cabinet.anchor_left = 1.0
	_roster_cabinet.anchor_top = 0.0
	_roster_cabinet.anchor_right = 1.0
	_roster_cabinet.anchor_bottom = 1.0
	add_child(_roster_cabinet)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	_roster_cabinet.get_content().add_child(column)

	_roster_title = OneGunUI.make_heading("LOCAL ROSTER", OneGunUI.TEXT_M)
	_roster_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_roster_title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)

	_roster_list = VBoxContainer.new()
	_roster_list.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	_roster_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_roster_list)


func _build_carousel() -> void:
	_carousel_cabinet = OneGunCabinet.new()
	_carousel_cabinet.name = "MapCarousel"
	_carousel_cabinet.variant = OneGunCabinet.Variant.SECTION
	_carousel_cabinet.content_padding = OneGunUI.SPACE_S
	_carousel_cabinet.anchor_left = 0.0
	_carousel_cabinet.anchor_top = 1.0
	_carousel_cabinet.anchor_right = 1.0
	_carousel_cabinet.anchor_bottom = 1.0
	add_child(_carousel_cabinet)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_carousel_cabinet.get_content().add_child(row)

	_carousel_prev = _make_chevron_button(OneGunIcon.Kind.CHEVRON_LEFT)
	_carousel_prev.pressed.connect(func(): _step_map(-1))
	_carousel_prev.disabled = MAPS.is_empty()
	row.add_child(_carousel_prev)

	var cards_scroll := ScrollContainer.new()
	cards_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	cards_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_scroll.follow_focus = true
	row.add_child(cards_scroll)

	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_scroll.add_child(_cards_row)

	_map_cards.clear()
	if MAPS.is_empty():
		var empty_state := OneGunStatusPanel.new()
		empty_state.custom_minimum_size = Vector2(360, 104)
		_cards_row.add_child(empty_state)
		empty_state.show_empty.call_deferred("NO MAPS AVAILABLE", "Add a valid map entry to the map registry.")
	else:
		for i in MAPS.size():
			var card := OneGunMapCard.new()
			_cards_row.add_child(card)
			var thumbnail := MapRegistry.load_thumbnail(i)
			if thumbnail != null:
				_thumbnails[i] = thumbnail
			card.set_map(i, str(MAPS[i].get("name", "Unnamed Map")), thumbnail,
					MAPS[i].get("tint", OneGunUI.color("face")))
			card.card_selected.connect(_on_map_card_selected)
			_map_cards.append(card)

	_carousel_next = _make_chevron_button(OneGunIcon.Kind.CHEVRON_RIGHT)
	_carousel_next.pressed.connect(func(): _step_map(1))
	_carousel_next.disabled = MAPS.is_empty()
	row.add_child(_carousel_next)


func _make_chevron_button(icon_kind: OneGunIcon.Kind) -> OneGunButton:
	var button := OneGunButton.new()
	button.variant = "navy"
	button.custom_minimum_size = Vector2(44, 104)
	var icon := OneGunIcon.new()
	icon.kind = icon_kind
	icon.icon_color = OneGunUI.color("gold")
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(icon)
	return button


func _build_play_action() -> void:
	_play_button = CONFIRM_BUTTON.new() if _is_net() and NetworkManager.is_host() else OneGunButton.new()
	_play_button.name = "PlayButton"
	_play_button.set_meta("action_id", "start_match" if _is_net() and NetworkManager.is_host() else "ready")
	_play_button.variant = "gold"
	_play_button.text = "PLAY"
	_play_button.font_size = 30
	_play_button.anchor_left = 1.0
	_play_button.anchor_top = 1.0
	_play_button.anchor_right = 1.0
	_play_button.anchor_bottom = 1.0
	_play_button.offset_left = -(24 + 340)
	_play_button.offset_top = -(24 + 84)
	_play_button.offset_right = -24
	_play_button.offset_bottom = -24
	_play_button.pressed.connect(_on_play_button_pressed)
	if _play_button is OneGunConfirmButton:
		(_play_button as OneGunConfirmButton).confirm_text = "CONFIRM FORCE START"
		(_play_button as OneGunConfirmButton).confirmed.connect(_launch_match)
	add_child(_play_button)
	if _is_net():
		_update_lobby_action()
	_update_play_availability()


func _apply_responsive_layout() -> void:
	if _left_cabinet == null:
		return
	# Always lay out against the viewport. An anchored connected slide-out must
	# never be allowed to feed its own minimum size back into this root Control.
	var layout_size := get_viewport_rect().size
	var safe_width := minf(layout_size.x, layout_size.y * (16.0 / 9.0))
	var safe_left := maxf((layout_size.x - safe_width) * 0.5, 0.0)
	var compact := safe_width < 1500.0
	var margin := COMPACT_MARGIN if compact else LAYOUT_MARGIN
	var gap := COMPACT_GAP if compact else LAYOUT_GAP
	var left_width := COMPACT_LEFT_WIDTH if compact else LEFT_WIDTH
	var right_width := COMPACT_RIGHT_WIDTH if compact else RIGHT_WIDTH
	var left_edge := safe_left + margin
	var right_edge := safe_left + safe_width - margin
	var center_left := left_edge + left_width + gap
	var center_right := right_edge - right_width - gap

	_left_cabinet.offset_left = left_edge
	_left_cabinet.offset_top = margin
	_left_cabinet.offset_right = left_edge + left_width
	_left_cabinet.offset_bottom = -margin
	_left_cabinet.z_index = 20

	if _settings_slideout != null and is_instance_valid(_settings_slideout):
		var slideout_left := left_edge + left_width - 10.0
		var slideout_right := center_right
		var slideout_width := clampf(slideout_right - slideout_left, 540.0, 780.0)
		_settings_slideout.anchor_left = 0.0
		_settings_slideout.anchor_top = 0.0
		_settings_slideout.anchor_right = 0.0
		_settings_slideout.anchor_bottom = 0.0
		_settings_slideout.position = Vector2(slideout_left, margin)
		_settings_slideout.size = Vector2(slideout_width, layout_size.y - margin * 2.0)
		_settings_target_position = _settings_slideout.position

	_top_strip.offset_left = center_left
	_top_strip.offset_top = margin
	_top_strip.offset_right = -(layout_size.x - center_right)
	_top_strip.offset_bottom = margin + TOP_STRIP_HEIGHT
	_top_strip.add_theme_constant_override("separation", gap)
	_info_card.custom_minimum_size.x = 208.0 if compact else 230.0

	_roster_cabinet.offset_left = -(layout_size.x - (right_edge - right_width))
	_roster_cabinet.offset_top = margin
	_roster_cabinet.offset_right = -(layout_size.x - right_edge)
	_roster_cabinet.offset_bottom = -(margin + PLAY_HEIGHT + gap)

	_carousel_cabinet.offset_left = center_left
	_carousel_cabinet.offset_top = -(margin + CAROUSEL_HEIGHT)
	_carousel_cabinet.offset_right = -(layout_size.x - center_right)
	_carousel_cabinet.offset_bottom = -margin

	_play_button.offset_left = -(layout_size.x - (right_edge - right_width))
	_play_button.offset_top = -(margin + PLAY_HEIGHT)
	_play_button.offset_right = -(layout_size.x - right_edge)
	_play_button.offset_bottom = -margin

	if _cards_row != null and not _map_cards.is_empty():
		var center_width := maxf(center_right - center_left, 1.0)
		var outer_space := 176.0 if compact else 152.0
		var card_width := clampf(
			(center_width - outer_space - OneGunUI.SPACE_S * (_map_cards.size() - 1))
				/ float(_map_cards.size()),
			138.0, 240.0)
		_cards_row.add_theme_constant_override("separation", OneGunUI.SPACE_S if compact else OneGunUI.SPACE_M)
		for card in _map_cards:
			card.custom_minimum_size = Vector2(card_width, 112.0)


func _configure_focus_navigation() -> void:
	var left_controls: Array = [_map_dropdown, _mode_dropdown, _match_settings_button,
			_character_customization_button, _player_settings_button, _back_button]
	left_controls = left_controls.filter(func(control): return control != null)
	OneGunUI.chain_focus_vertical(left_controls)
	var carousel_controls: Array = [_carousel_prev]
	carousel_controls.append_array(_map_cards)
	carousel_controls.append(_carousel_next)
	for index in carousel_controls.size():
		var control := carousel_controls[index] as Control
		var previous := carousel_controls[wrapi(index - 1, 0, carousel_controls.size())] as Control
		var next := carousel_controls[wrapi(index + 1, 0, carousel_controls.size())] as Control
		control.focus_neighbor_left = control.get_path_to(previous)
		control.focus_neighbor_right = control.get_path_to(next)
		control.focus_neighbor_top = control.get_path_to(_map_dropdown)
		control.focus_neighbor_bottom = control.get_path_to(_play_button)
	_play_button.focus_neighbor_left = _play_button.get_path_to(_carousel_next)
	_play_button.focus_neighbor_top = _play_button.get_path_to(_carousel_next)
	_back_button.focus_neighbor_right = _back_button.get_path_to(_carousel_prev)
	for control in left_controls:
		if not control.disabled:
			control.grab_focus()
			break


# ============================================================
# Map selection
# ============================================================
func _on_map_dropdown_selected(item_index: int) -> void:
	if MAPS.is_empty():
		return
	var id := _map_dropdown.get_item_id(item_index)
	if id == RANDOM_ITEM_ID:
		map_select_mode = MapSelectMode.RANDOM
	else:
		map_select_mode = MapSelectMode.SPECIFIC
		selected_map_index = id
	if _map_preview != null:
		_map_preview.apply(map_select_mode, selected_map_index)
	_sync_carousel()
	_update_map_info()

func _on_mode_dropdown_selected(item_index: int) -> void:
	if item_index < 0 or item_index >= GameConfig.GAME_MODES.size():
		return
	GameConfig.game_mode = str(GameConfig.GAME_MODES[item_index])
	_refresh_one_of_us_preference_panel()
	_on_settings_changed()


func _on_map_card_selected(map_index: int) -> void:
	if _is_net() and not NetworkManager.is_host():
		return
	if map_index < 0 or map_index >= MAPS.size():
		return
	map_select_mode = MapSelectMode.SPECIFIC
	selected_map_index = map_index
	_map_dropdown.select(map_index)
	if _map_preview != null:
		_map_preview.apply(map_select_mode, selected_map_index)
	_sync_carousel()
	_update_map_info()
	_on_settings_changed()


func _step_map(direction: int) -> void:
	if MAPS.is_empty():
		return
	var next := wrapi(selected_map_index + direction, 0, MAPS.size())
	_on_map_card_selected(next)


func _sync_carousel() -> void:
	for i in _map_cards.size():
		_map_cards[i].set_selected(
			map_select_mode == MapSelectMode.SPECIFIC and i == selected_map_index)


func _update_map_info() -> void:
	if _banner_name == null:
		return
	if MAPS.is_empty():
		_banner_name.text = "NO MAPS AVAILABLE"
		_banner_desc.text = "Add a playable map to the shared map registry."
		for key in _info_labels:
			_info_labels[key].text = "—"
		_update_play_availability()
		return
	if map_select_mode == MapSelectMode.RANDOM:
		_banner_name.text = "RANDOM ROTATION"
		_banner_desc.text = "The battlefield stays hidden until the match begins."
		for key in _info_labels:
			_info_labels[key].text = "—"
		_apply_map_capacity_warning_to_banner()
		_update_play_availability()
		return
	selected_map_index = clampi(selected_map_index, 0, MAPS.size() - 1)
	var map_data: Dictionary = MAPS[selected_map_index]
	_banner_name.text = str(map_data.get("name", "Unnamed Map")).to_upper()
	_banner_desc.text = str(map_data.get("description", "No description is available."))
	_info_labels["size"].text = str(map_data.get("size", "Unknown")).to_upper()
	_info_labels["recommended_players"].text = str(map_data.get("recommended_players", "—")) + " PLAYERS"
	_info_labels["playstyle"].text = str(map_data.get("playstyle", "Unknown")).to_upper()
	var hazards_text := "NONE"
	if bool(map_data.get("hazards", false)):
		hazards_text = "AVAILABLE" if GameConfig.hazards_enabled else "DISABLED"
	_info_labels["hazards"].text = hazards_text
	_apply_map_capacity_warning_to_banner()
	_update_play_availability()


func _apply_map_capacity_warning_to_banner() -> void:
	var unavailable_reason := _selection_unavailable_reason()
	if unavailable_reason != "" and _banner_desc != null:
		_banner_desc.text = unavailable_reason


func _selected_map_available() -> bool:
	return _selection_unavailable_reason() == ""


func _selection_unavailable_reason() -> String:
	if MAPS.is_empty():
		return "No playable maps are registered."
	var team_error := _team_roster_error()
	if team_error != "":
		return team_error
	var actor_count := _planned_actor_count()
	if map_select_mode == MapSelectMode.RANDOM:
		if MapRegistry.available_indices().is_empty():
			return "No playable maps are currently available."
		if MapRegistry.available_indices(actor_count).is_empty():
			return "No available map supports the current %d-player roster." % actor_count
		return ""
	if not MapRegistry.is_scene_available(selected_map_index):
		return "The selected map is unavailable."
	var capacity := MapRegistry.get_player_capacity(selected_map_index)
	if actor_count > capacity:
		var map_name := str(MAPS[selected_map_index].get("name", "Selected map"))
		return "%s supports %d players, but the roster has %d. Remove players or bots, or choose another map." \
			% [map_name, capacity, actor_count]
	return ""


func _team_roster_error() -> String:
	if not GameConfig.teams_enabled:
		return ""
	var represented: Dictionary = {}
	if _is_net():
		for peer_id in NetworkManager.peers:
			if str(NetworkManager.peers[peer_id].get("role", "lobby")) \
					in ["lobby", "playpen", "playpen_loading", "playpen_hosting"]:
				represented[int(NetworkManager.peers[peer_id].get("team_id", -1))] = true
	else:
		for index in _local_human_count():
			represented[int(GameConfig.local_player_teams[index])] = true
	for config in GameConfig.bot_configs:
		represented[int(config.get("team_id", -1))] = true
	represented.erase(-1)
	if represented.size() < 2:
		return "Team matches require players on at least two represented teams."
	return ""


func _update_play_availability() -> void:
	if _play_button == null:
		return
	if _is_net():
		if NetworkManager.is_host():
			_update_lobby_action()
		else:
			_play_button.disabled = false
		return
	var unavailable_reason := _selection_unavailable_reason()
	_play_button.disabled = unavailable_reason != ""
	_play_button.tooltip_text = unavailable_reason


func _resolve_map_scene_path() -> String:
	if MAPS.is_empty():
		return ""
	match map_select_mode:
		MapSelectMode.RANDOM:
			var available := MapRegistry.available_indices(_planned_actor_count())
			if available.is_empty():
				return ""
			return str(MAPS[available.pick_random()].get("scene_path", ""))
		MapSelectMode.VOTE:
			# Voting requires a real lobby/network layer to collect votes from
			# multiple players. Until that exists, vote mode falls back to
			# the host's specific-map pick so the game can still launch.
			return str(MAPS[clampi(selected_map_index, 0, MAPS.size() - 1)].get("scene_path", ""))
		_:
			return str(MAPS[clampi(selected_map_index, 0, MAPS.size() - 1)].get("scene_path", ""))


# ============================================================
# Roster (no ready states in local play — locked behavior)
# ============================================================
func _refresh_roster() -> void:
	if _roster_list == null:
		return
	for child in _roster_list.get_children():
		_roster_list.remove_child(child)
		child.queue_free()

	var slot_cap := ONLINE_SLOT_CAP if _is_net() else LOCAL_SLOT_CAP
	var used := 0

	if _is_net():
		_roster_title.text = "LOBBY ROSTER"
		for id in NetworkManager.peer_ids_sorted():
			var row := OneGunRosterRow.new()
			_roster_list.add_child(row)
			var peer_name := str(NetworkManager.peers[id]["name"])
			var is_me: bool = id == NetworkManager.local_id()
			var ready_state := OneGunRosterRow.ReadyState.NONE
			if id != 1:
				ready_state = OneGunRosterRow.ReadyState.READY if NetworkManager.is_peer_lobby_ready(id) else OneGunRosterRow.ReadyState.NOT_READY
			row.set_human(peer_name, id == 1, is_me, ready_state,
				NetworkManager.peer_skin_id(id))
			if GameConfig.teams_enabled:
				var team_id := int(NetworkManager.peers[id].get("team_id", 0))
				var can_edit_team := NetworkManager.is_host() or is_me
				row.add_team_chip(team_id, _is_team_uneven(team_id), not can_edit_team)
				if can_edit_team:
					var roster_actor_id := int(NetworkManager.peers[id].get("actor_id", -1))
					row.add_trailing(_make_team_dropdown(team_id, _on_online_roster_team_selected.bind(roster_actor_id)))
			if is_me:
				row.enable_name_editing(_on_edit_online_name)
				row.add_trailing(_make_edit_name_button(_on_edit_online_name))
			if NetworkManager.is_host() and id != 1:
				row.add_trailing(_make_kick_button(id, peer_name))
			used += 1
	else:
		_roster_title.text = "LOCAL ROSTER"
		var p1 := OneGunRosterRow.new()
		_roster_list.add_child(p1)
		p1.set_human(str(PlayerPrefs.get_setting("player_name")), true, false,
			OneGunRosterRow.ReadyState.NONE,
			str(PlayerPrefs.get_setting("character_skin_id")))
		if GameConfig.teams_enabled:
			p1.add_team_chip(int(GameConfig.local_player_teams[0]), _is_team_uneven(int(GameConfig.local_player_teams[0])), false)
			p1.add_trailing(_make_team_dropdown(int(GameConfig.local_player_teams[0]), func(value: int):
				GameConfig.local_player_teams[0] = value
				_on_settings_changed()))
		p1.add_trailing(_make_edit_name_button(_on_edit_player1_name))
		used += 1
		if GameConfig.split_screen_enabled:
			var p2 := OneGunRosterRow.new()
			_roster_list.add_child(p2)
			p2.set_human(str(GameConfig.player2_name), false, false,
				OneGunRosterRow.ReadyState.NONE, str(GameConfig.player2_skin_id))
			if GameConfig.teams_enabled:
				p2.add_team_chip(int(GameConfig.local_player_teams[1]), _is_team_uneven(int(GameConfig.local_player_teams[1])), false)
				p2.add_trailing(_make_team_dropdown(int(GameConfig.local_player_teams[1]), func(value: int):
					GameConfig.local_player_teams[1] = value
					_on_settings_changed()))
			p2.add_trailing(_make_edit_name_button(_on_edit_player2_name))
			used += 1

	for i in GameConfig.bot_configs.size():
		if used >= slot_cap:
			break
		var bot_row := OneGunRosterRow.new()
		_roster_list.add_child(bot_row)
		var difficulty := str(GameConfig.bot_configs[i].get("difficulty", "easy"))
		bot_row.set_bot("Bot %d" % (i + 1), difficulty, _is_net())
		if GameConfig.teams_enabled:
			var bot_team := int(GameConfig.bot_configs[i].get("team_id", 0))
			var can_edit_bot_team := not _is_net() or NetworkManager.is_host()
			bot_row.add_team_chip(bot_team, _is_team_uneven(bot_team), not can_edit_bot_team)
			if can_edit_bot_team:
				bot_row.add_trailing(_make_team_dropdown(bot_team, _on_bot_team_selected.bind(i)))
		used += 1

	for slot in range(used + 1, slot_cap + 1):
		var empty_row := OneGunRosterRow.new()
		_roster_list.add_child(empty_row)
		empty_row.set_empty(slot)


func _make_edit_name_button(callback: Callable) -> OneGunButton:
	var button := OneGunButton.new()
	button.variant = "navy"
	button.text = ""
	button.custom_minimum_size = Vector2(40, 36)
	button.tooltip_text = "Edit player name"
	var edit_icon := OneGunIcon.new()
	edit_icon.kind = OneGunIcon.Kind.EDIT
	edit_icon.icon_color = OneGunUI.color("gold")
	edit_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edit_icon.offset_left = 8
	edit_icon.offset_top = 8
	edit_icon.offset_right = -8
	edit_icon.offset_bottom = -8
	button.add_child(edit_icon)
	button.pressed.connect(callback)
	return button


func _make_team_dropdown(team_id: int, callback: Callable) -> OptionButton:
	var dropdown := OneGunUI.make_dropdown()
	dropdown.custom_minimum_size = Vector2(76, 36)
	for index in GameConfig.team_count:
		dropdown.add_item("T%d" % (index + 1), index)
	dropdown.select(clampi(team_id, 0, GameConfig.team_count - 1))
	dropdown.item_selected.connect(callback)
	return dropdown


func _on_online_roster_team_selected(value: int, actor_id: int) -> void:
	if NetworkManager.is_host():
		NetworkManager.set_actor_team(actor_id, value)
	else:
		NetworkManager.request_local_team(value)


func _on_bot_team_selected(value: int, bot_index: int) -> void:
	if bot_index < 0 or bot_index >= GameConfig.bot_configs.size():
		return
	GameConfig.bot_configs[bot_index]["team_id"] = value
	_on_settings_changed()


func _team_counts() -> Dictionary:
	var counts := {}
	if _is_net():
		for peer_id in NetworkManager.peers:
			if str(NetworkManager.peers[peer_id].get("role", "lobby")) \
					in ["lobby", "playpen", "playpen_loading", "playpen_hosting"]:
				var team := int(NetworkManager.peers[peer_id].get("team_id", 0))
				counts[team] = int(counts.get(team, 0)) + 1
	else:
		for index in _local_human_count():
			var team := int(GameConfig.local_player_teams[index])
			counts[team] = int(counts.get(team, 0)) + 1
	for config in GameConfig.bot_configs:
		var team := int(config.get("team_id", 0))
		counts[team] = int(counts.get(team, 0)) + 1
	return counts


func _is_team_uneven(team_id: int) -> bool:
	var counts := _team_counts()
	if counts.size() < 2:
		return false
	var sizes := counts.values()
	return int(sizes.min()) != int(sizes.max()) and int(counts.get(team_id, 0)) != int(sizes.max())


func _make_kick_button(peer_id: int, peer_name: String) -> OneGunConfirmButton:
	var button := OneGunConfirmButton.new()
	button.variant = "navy"
	button.text = "KICK"
	button.confirm_text = "CONFIRM"
	button.custom_minimum_size = Vector2(72, 36)
	button.tooltip_text = "Remove %s from the lobby" % peer_name
	button.confirmed.connect(func(): NetworkManager.kick_peer(peer_id))
	return button


# Settings/roster-affecting change: mark the lobby dirty and (online host)
# push the new config to clients. Local play has no ready states to reset.
func _on_settings_changed() -> void:
	GameConfig.lobby_settings_dirty = true
	_clamp_bot_count_to_capacity()
	_refresh_roster()
	_update_map_info()
	if _is_net() and NetworkManager.is_host():
		NetworkManager.reset_lobby_readiness("Map or match rules changed — ready up again")
	_net_broadcast_config()


# ============================================================
# Connected transactional settings slide-outs (Phase 3)
# ============================================================
func _on_bot_settings_button_pressed() -> void:
	_open_settings_slideout(LOBBY_SETTINGS_SLIDEOUT.Kind.BOT)


func _on_match_settings_button_pressed() -> void:
	_open_settings_slideout(LOBBY_SETTINGS_SLIDEOUT.Kind.MATCH)


func _on_character_customization_pressed() -> void:
	if _character_customization_overlay != null:
		return
	if _settings_slideout != null and is_instance_valid(_settings_slideout):
		_discard_settings_slideout_immediately()
	_character_customization_overlay = preload(
		"res://UI/character_customization_overlay.gd").new()
	_character_customization_overlay.configure(_is_net(), _local_human_count())
	_character_customization_overlay.closed.connect(_on_character_customization_closed)
	_character_customization_overlay.skin_changed.connect(
		func(_slot: int, _skin_id: String): _refresh_roster())
	_settings_layer.add_child(_character_customization_overlay)


func _on_character_customization_closed() -> void:
	_character_customization_overlay = null
	_refresh_roster()
	_configure_focus_navigation.call_deferred()


func _on_player_settings_pressed() -> void:
	if _player_settings_overlay != null:
		return
	if _character_customization_overlay != null:
		_character_customization_overlay.queue_free()
		_character_customization_overlay = null
	if _settings_slideout != null and is_instance_valid(_settings_slideout):
		_discard_settings_slideout_immediately()
	_player_settings_overlay = preload("res://player_settings.tscn").instantiate()
	_player_settings_overlay.is_overlay = true
	_player_settings_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_player_settings_overlay.settings_closed.connect(_on_player_settings_closed)
	_settings_layer.add_child(_player_settings_overlay)


func _on_player_settings_closed() -> void:
	if _player_settings_overlay == null:
		return
	_player_settings_overlay.queue_free()
	_player_settings_overlay = null
	_configure_focus_navigation.call_deferred()


func _close_player_settings_immediately() -> void:
	if _player_settings_overlay != null:
		_player_settings_overlay.queue_free()
		_player_settings_overlay = null


func _open_settings_slideout(kind: int) -> void:
	if _settings_slideout != null and is_instance_valid(_settings_slideout):
		_close_settings_slideout()
		return
	_settings_slideout = LOBBY_SETTINGS_SLIDEOUT.new()
	_settings_slideout.name = "SettingsSlideout"
	_settings_slideout.panel_kind = LOBBY_SETTINGS_SLIDEOUT.Kind.MATCH
	_settings_slideout.initial_tab = 4 if kind == LOBBY_SETTINGS_SLIDEOUT.Kind.BOT else 0
	_settings_slideout.maximum_bots = _max_online_bots()
	_settings_slideout.online_mode = _is_net()
	_settings_slideout.read_only = _is_net() and not NetworkManager.is_host()
	_settings_slideout.z_index = 15
	_settings_slideout.applied.connect(_on_settings_slideout_applied)
	_settings_slideout.closed.connect(_close_settings_slideout)
	_settings_layer.add_child(_settings_slideout)
	_set_settings_button_state(LOBBY_SETTINGS_SLIDEOUT.Kind.MATCH)
	_apply_responsive_layout()
	if not _reduced_motion_enabled():
		_settings_slideout.position = _settings_target_position - Vector2(34.0, 0.0)
		_settings_slideout.modulate.a = 0.0
		_settings_tween = create_tween().set_parallel(true)
		_settings_tween.tween_property(_settings_slideout, "position", _settings_target_position, OneGunUI.TIME_SLIDEOUT).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		_settings_tween.tween_property(_settings_slideout, "modulate:a", 1.0, OneGunUI.TIME_SLIDEOUT * 0.7)
	_settings_slideout.focus_first()
	_constrain_settings_slideout.call_deferred()

func _constrain_settings_slideout() -> void:
	if _settings_slideout == null or not is_instance_valid(_settings_slideout):
		return
	var viewport_size := get_viewport_rect().size
	var margin := COMPACT_MARGIN if minf(viewport_size.x, viewport_size.y * (16.0 / 9.0)) < 1500.0 else LAYOUT_MARGIN
	_settings_slideout.size.y = viewport_size.y - margin * 2.0


func _on_settings_slideout_applied(values: Dictionary) -> void:
	GameConfig.apply_lobby_values(values)
	_on_settings_changed()
	_close_settings_slideout()


func _close_settings_slideout() -> void:
	if _settings_slideout == null or not is_instance_valid(_settings_slideout):
		return
	if _settings_tween != null and _settings_tween.is_valid():
		_settings_tween.kill()
	var closing: Control = _settings_slideout
	_settings_slideout = null
	_set_settings_button_state(-1)
	if _reduced_motion_enabled():
		closing.queue_free()
		_configure_focus_navigation.call_deferred()
		return
	_settings_tween = create_tween().set_parallel(true)
	_settings_tween.tween_property(closing, "position:x", closing.position.x - 34.0, OneGunUI.TIME_SLIDEOUT * 0.65).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	_settings_tween.tween_property(closing, "modulate:a", 0.0, OneGunUI.TIME_SLIDEOUT * 0.55)
	_settings_tween.chain().tween_callback(closing.queue_free)
	_configure_focus_navigation.call_deferred()


func _discard_settings_slideout_immediately() -> void:
	if _settings_tween != null and _settings_tween.is_valid():
		_settings_tween.kill()
	if _settings_slideout != null and is_instance_valid(_settings_slideout):
		_settings_slideout.queue_free()
	_settings_slideout = null
	_set_settings_button_state(-1)


func _set_settings_button_state(kind: int) -> void:
	if _match_settings_button != null:
		_match_settings_button.variant = "purple" if kind == LOBBY_SETTINGS_SLIDEOUT.Kind.MATCH else "navy"


func _open_capture_state() -> void:
	if OS.get_environment("ONEGUN_UI_CAPTURE") == "":
		return
	match OS.get_environment("ONEGUN_UI_CAPTURE_STATE"):
		"bot_settings": _open_settings_slideout(LOBBY_SETTINGS_SLIDEOUT.Kind.BOT)
		"match_settings": _open_settings_slideout(LOBBY_SETTINGS_SLIDEOUT.Kind.MATCH)
		"lobby_customization":
			GameConfig.split_screen_enabled = true
			_refresh_roster()
			_on_character_customization_pressed()
		"lobby_one_of_us":
			GameConfig.game_mode = GameConfig.MODE_ONE_OF_US
			_mode_dropdown.select(GameConfig.GAME_MODES.find(GameConfig.MODE_ONE_OF_US))
			_refresh_one_of_us_preference_panel()


func _reduced_motion_enabled() -> bool:
	var preference = PlayerPrefs.get_setting("reduced_motion")
	return bool(preference) if preference != null else false


# ============================================================
# Bot Settings popup (interim until the Phase 3 slide-out)
# ============================================================
const DIFFICULTY_OPTIONS = ["easy", "medium", "hard", "expert"]

func _legacy_on_bot_settings_button_pressed():
	_build_bot_settings_popup()
	$BotSettingsPopup.popup_centered()


func _on_bot_settings_popup_closed():
	_on_settings_changed()


func _build_bot_settings_popup():
	var popup = $BotSettingsPopup
	for child in popup.get_children():
		child.queue_free()

	var root = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	popup.add_child(root)
	popup.size = Vector2(420, 100 + 48 * max(GameConfig.bot_configs.size(), 1))

	# -- Count adjuster (stepper — locked behavior: never a slider) --
	var count_row = HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 12)
	var count_label = Label.new()
	count_label.text = "Bot Count:"
	var minus_button = Button.new()
	minus_button.text = "-"
	minus_button.custom_minimum_size = Vector2(36, 36)
	var count_value_label = Label.new()
	count_value_label.name = "CountValueLabel"
	count_value_label.text = str(GameConfig.bot_configs.size())
	count_value_label.custom_minimum_size = Vector2(30, 0)
	count_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plus_button = Button.new()
	plus_button.text = "+"
	plus_button.custom_minimum_size = Vector2(36, 36)
	plus_button.disabled = GameConfig.bot_configs.size() >= _max_online_bots()
	minus_button.pressed.connect(func():
		GameConfig.set_bot_count(GameConfig.bot_configs.size() - 1)
		_on_settings_changed()
		await get_tree().process_frame
		_build_bot_settings_popup()
	)
	plus_button.pressed.connect(func():
		GameConfig.set_bot_count(mini(GameConfig.bot_configs.size() + 1, _max_online_bots()))
		_on_settings_changed()
		await get_tree().process_frame
		_build_bot_settings_popup()
	)
	count_row.add_child(count_label)
	count_row.add_child(minus_button)
	count_row.add_child(count_value_label)
	count_row.add_child(plus_button)
	root.add_child(count_row)

	root.add_child(HSeparator.new())

	# -- Per-bot rows --
	for i in GameConfig.bot_configs.size():
		root.add_child(_build_bot_config_row(i))
	_bump_fonts_recursive(root)


func _build_bot_config_row(bot_index: int) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label = Label.new()
	label.text = "Bot " + str(bot_index + 1)
	label.custom_minimum_size = Vector2(70, 0)
	row.add_child(label)

	var difficulty_button = OptionButton.new()
	for d in DIFFICULTY_OPTIONS.size():
		difficulty_button.add_item(DIFFICULTY_OPTIONS[d].capitalize(), d)
	var current_difficulty = GameConfig.bot_configs[bot_index].get("difficulty", "easy")
	var current_index = DIFFICULTY_OPTIONS.find(current_difficulty)
	difficulty_button.select(max(current_index, 0))
	difficulty_button.fit_to_longest_item = true
	difficulty_button.custom_minimum_size = Vector2(120, 36)
	difficulty_button.item_selected.connect(func(idx):
		GameConfig.bot_configs[bot_index]["difficulty"] = DIFFICULTY_OPTIONS[idx]
		_on_settings_changed()
	)
	row.add_child(difficulty_button)
	difficulty_button.get_popup().max_size = Vector2(0, 164)

	if GameConfig.teams_enabled:
		var team_button = OptionButton.new()
		for t in range(GameConfig.team_count):
			team_button.add_item("Team " + str(t + 1), t)
		var current_team := clampi(
			int(GameConfig.bot_configs[bot_index].get("team_id", 0)),
			0, GameConfig.team_count - 1)
		team_button.select(current_team)
		team_button.fit_to_longest_item = true
		team_button.custom_minimum_size = Vector2(120, 36)
		team_button.item_selected.connect(func(idx):
			GameConfig.bot_configs[bot_index]["team_id"] = idx
			_on_settings_changed()
		)
		row.add_child(team_button)
		team_button.get_popup().max_size = Vector2(0, 124)

	return row


# ============================================================
# Match Settings popup (interim until the Phase 3 slide-out).
# Exposes every existing GameConfig rule + the preset slots.
# ============================================================
func _legacy_on_match_settings_button_pressed():
	if _match_settings_popup == null:
		_match_settings_popup = PopupPanel.new()
		_match_settings_popup.name = "MatchSettingsPopup"
		add_child(_match_settings_popup)
	_build_match_settings_popup()
	_match_settings_popup.popup_centered()


func _build_match_settings_popup():
	for child in _match_settings_popup.get_children():
		child.queue_free()
	_match_settings_popup.size = Vector2(800, 560)

	var columns = HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 16)
	_match_settings_popup.add_child(columns)

	# -- Left column: settings, in a scroll box --
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(470, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)

	var settings_list = VBoxContainer.new()
	settings_list.name = "SettingsList"
	settings_list.add_theme_constant_override("separation", 8)
	settings_list.custom_minimum_size = Vector2(450, 0)
	scroll.add_child(settings_list)

	_add_bool_setting(settings_list, "Teams Enabled", GameConfig.teams_enabled, func(v): GameConfig.teams_enabled = v)
	_add_bool_setting(settings_list, "Friendly Fire", GameConfig.friendly_fire_enabled, func(v): GameConfig.friendly_fire_enabled = v)
	_add_bool_setting(settings_list, "Sprinting Enabled", GameConfig.sprinting_enabled, func(v): GameConfig.sprinting_enabled = v)
	_add_bool_setting(settings_list, "Melee Eliminates Gun Holder", GameConfig.melee_eliminates_gunholder, func(v): GameConfig.melee_eliminates_gunholder = v)
	_add_bool_setting(settings_list, "Melee Eliminates Anyone", GameConfig.melee_eliminates_anyone, func(v): GameConfig.melee_eliminates_anyone = v)
	_add_bool_setting(settings_list, "Melee Effects Hit Anyone", GameConfig.melee_effects_hit_anyone, func(v): GameConfig.melee_effects_hit_anyone = v)
	_add_bool_setting(settings_list, "Hazards Enabled", GameConfig.hazards_enabled, func(v): GameConfig.hazards_enabled = v)
	_add_bool_setting(settings_list, "Consumables Enabled", GameConfig.consumables_enabled, func(v): GameConfig.consumables_enabled = v)
	_add_enum_setting(settings_list, "Gun Spawn Mode", ["center", "random"], GameConfig.gun_spawn_mode, func(v): GameConfig.gun_spawn_mode = v)
	_add_float_setting(settings_list, "Disarm Lock Time (s)", GameConfig.disarm_lock_time, 0.0, 10.0, func(v): GameConfig.disarm_lock_time = v)
	_add_float_setting(settings_list, "Melee Spawn Delay (s)", GameConfig.melee_spawn_delay, 0.0, 15.0, func(v): GameConfig.melee_spawn_delay = v)
	_add_float_setting(settings_list, "OT Fire Exposure (s)", GameConfig.overtime_fire_exposure_time, 0.5, 15.0, func(v): GameConfig.overtime_fire_exposure_time = v)
	_add_int_setting(settings_list, "Max Dash Charges", GameConfig.max_dash_charges, 0, 6, func(v): GameConfig.max_dash_charges = v)
	_add_float_setting(settings_list, "Melee Despawn Time (s)", GameConfig.dropped_melee_despawn_time, 0.0, 30.0, func(v): GameConfig.dropped_melee_despawn_time = v)
	_add_bool_setting(settings_list, "Melee Weapon Breaking", GameConfig.melee_weapon_breaking, func(v): GameConfig.melee_weapon_breaking = v)

	settings_list.add_child(HSeparator.new())
	var win_condition_label = Label.new()
	win_condition_label.text = "Win Condition"
	settings_list.add_child(win_condition_label)
	_add_int_setting(settings_list, "Rounds (per Set)", GameConfig.rounds_per_set, 1, 20, func(v): GameConfig.rounds_per_set = v)
	_add_int_setting(settings_list, "Sets (per Match)", GameConfig.sets_per_match, 1, 20, func(v): GameConfig.sets_per_match = v)

	var default_button = Button.new()
	default_button.text = "Default"
	default_button.custom_minimum_size = Vector2(0, 36)
	default_button.pressed.connect(func():
		GameConfig.reset_match_settings_to_defaults()
		_build_match_settings_popup()
		_on_settings_changed()
	)
	settings_list.add_child(default_button)

	# -- Right column: ruleset presets --
	var presets_section = VBoxContainer.new()
	presets_section.name = "PresetsSection"
	presets_section.add_theme_constant_override("separation", 6)
	presets_section.custom_minimum_size = Vector2(280, 0)
	columns.add_child(presets_section)
	_populate_preset_section(presets_section)
	_bump_fonts_recursive(columns)


func _populate_preset_section(section: VBoxContainer):
	for child in section.get_children():
		child.queue_free()

	var title = Label.new()
	title.text = "Ruleset Presets"
	section.add_child(title)

	for i in GameConfig.MAX_PRESET_SLOTS:
		section.add_child(_build_preset_slot_row(i))


func _refresh_preset_section():
	if _match_settings_popup == null or not _match_settings_popup.visible:
		return
	var section = _match_settings_popup.find_child("PresetsSection", true, false)
	if section != null:
		_populate_preset_section(section)
		_bump_fonts_recursive(section)


func _build_preset_slot_row(slot_index: int) -> VBoxContainer:
	var row = VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	if GameConfig.is_preset_slot_empty(slot_index):
		var name_label = Label.new()
		name_label.text = "Slot " + str(slot_index + 1) + ": (empty)"
		row.add_child(name_label)

		var save_button = Button.new()
		save_button.text = "Save"
		save_button.custom_minimum_size = Vector2(0, 32)
		save_button.pressed.connect(func():
			_prompt_save_preset_slot(slot_index)
		)
		row.add_child(save_button)
		row.add_child(HSeparator.new())
		return row

	var name_label = Label.new()
	name_label.text = "Slot " + str(slot_index + 1) + ": " + GameConfig.get_preset_slot_name(slot_index)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name_label)

	var button_row = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 4)
	row.add_child(button_row)

	var load_button = Button.new()
	load_button.text = "Load"
	load_button.custom_minimum_size = Vector2(0, 32)
	load_button.pressed.connect(func():
		GameConfig.load_preset_slot(slot_index)
		_build_match_settings_popup()
		_on_settings_changed()
	)
	button_row.add_child(load_button)

	var edit_button = Button.new()
	edit_button.text = "Edit"
	edit_button.custom_minimum_size = Vector2(0, 32)
	edit_button.pressed.connect(func():
		GameConfig.save_preset_slot(slot_index, GameConfig.get_preset_slot_name(slot_index))
		_refresh_preset_section()
	)
	button_row.add_child(edit_button)

	var delete_button = Button.new()
	delete_button.text = "Delete"
	delete_button.custom_minimum_size = Vector2(0, 32)
	delete_button.pressed.connect(func():
		GameConfig.delete_preset_slot(slot_index)
		_refresh_preset_section()
	)
	button_row.add_child(delete_button)

	return row


func _prompt_save_preset_slot(slot_index: int):
	var dialog = AcceptDialog.new()
	dialog.title = "Save Ruleset Preset"
	dialog.dialog_text = "Enter a name for this preset:"

	var line_edit = LineEdit.new()
	line_edit.text = ""
	line_edit.custom_minimum_size = Vector2(250, 0)
	dialog.add_child(line_edit)
	dialog.register_text_enter(line_edit)

	add_child(dialog)
	dialog.popup_centered()

	dialog.confirmed.connect(func():
		var preset_name = line_edit.text.strip_edges()
		if preset_name == "":
			preset_name = "Preset " + str(slot_index + 1)
		GameConfig.save_preset_slot(slot_index, preset_name)
		_refresh_preset_section()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)


# ============================================================
# Shared setting-row builders (used by the match settings popup)
# ============================================================
const SETTINGS_FONT_SIZE := 18

func _bump_fonts_recursive(node: Node):
	if node is Label or node is Button or node is OptionButton \
			or node is CheckBox or node is LineEdit or node is SpinBox:
		node.add_theme_font_size_override("font_size", SETTINGS_FONT_SIZE)
	for child in node.get_children():
		_bump_fonts_recursive(child)


func _add_bool_setting(parent: VBoxContainer, label_text: String, current_value: bool, on_changed: Callable):
	var row = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220, 0)
	var checkbox = CheckBox.new()
	checkbox.button_pressed = current_value
	checkbox.toggled.connect(func(v):
		on_changed.call(v)
		_on_settings_changed()
	)
	row.add_child(label)
	row.add_child(checkbox)
	parent.add_child(row)


func _add_enum_setting(parent: VBoxContainer, label_text: String, options: Array, current_value: String, on_changed: Callable):
	var row = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220, 0)
	var option_button = OptionButton.new()
	for i in options.size():
		option_button.add_item(options[i], i)
		if options[i] == current_value:
			option_button.select(i)
	option_button.fit_to_longest_item = true
	option_button.custom_minimum_size = Vector2(120, 36)
	option_button.item_selected.connect(func(idx):
		on_changed.call(options[idx])
		_on_settings_changed()
	)
	row.add_child(label)
	row.add_child(option_button)
	parent.add_child(row)
	option_button.get_popup().max_size = Vector2(0, 124)


func _add_float_setting(parent: VBoxContainer, label_text: String, current_value: float, min_value: float, max_value: float, on_changed: Callable):
	var row = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220, 0)
	var spinbox = SpinBox.new()
	spinbox.min_value = min_value
	spinbox.max_value = max_value
	spinbox.step = 0.5
	spinbox.value = current_value
	spinbox.value_changed.connect(func(v):
		on_changed.call(v)
		_on_settings_changed()
	)
	row.add_child(label)
	row.add_child(spinbox)
	parent.add_child(row)


func _add_int_setting(parent: VBoxContainer, label_text: String, current_value: int, min_value: int, max_value: int, on_changed: Callable):
	var row = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220, 0)
	var spinbox = SpinBox.new()
	spinbox.min_value = min_value
	spinbox.max_value = max_value
	spinbox.step = 1
	spinbox.value = current_value
	spinbox.value_changed.connect(func(v):
		on_changed.call(int(v))
		_on_settings_changed()
	)
	row.add_child(label)
	row.add_child(spinbox)
	parent.add_child(row)


# ============================================================
# Name editing
# ============================================================
func _on_edit_player1_name():
	_prompt_edit_name(PlayerPrefs.get_setting("player_name"), func(new_name: String):
		PlayerPrefs.set_setting("player_name", new_name)
		_refresh_roster()
	)


func _on_edit_online_name() -> void:
	_prompt_edit_name(NetworkManager.local_name(), func(new_name: String):
		NetworkManager.set_local_name(new_name)
		_refresh_roster()
	)


func _on_edit_player2_name():
	_prompt_edit_name(GameConfig.player2_name, func(new_name: String):
		GameConfig.player2_name = new_name
		_refresh_roster()
	)


func _prompt_edit_name(current_name: String, on_confirmed: Callable):
	var dialog = AcceptDialog.new()
	dialog.title = "Edit Name"
	dialog.dialog_text = "Enter a new name:"

	var line_edit = LineEdit.new()
	line_edit.text = current_name
	line_edit.custom_minimum_size = Vector2(250, 0)
	line_edit.max_length = 24
	dialog.add_child(line_edit)
	dialog.register_text_enter(line_edit)

	add_child(dialog)
	dialog.popup_centered()

	dialog.confirmed.connect(func():
		var new_name = line_edit.text.strip_edges()
		if new_name == "":
			return
		on_confirmed.call(new_name)
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)


# ============================================================

func _update_playpen_availability() -> void:
	if _playpen_button == null:
		return
	var host_open := NetworkManager.is_playpen_open()
	_playpen_button.disabled = NetworkManager._prelaunch_active \
		or (not NetworkManager.is_host() and not host_open)
	_playpen_button.text = "ENTER THE PLAYPEN"
	if not NetworkManager.is_host() and not host_open:
		_playpen_button.tooltip_text = "The host must open The Playpen first."
	else:
		_playpen_button.tooltip_text = "Practice with the lobby while waiting for the match."


func _on_playpen_pressed() -> void:
	if not _is_net() or NetworkManager.lobby_in_progress:
		return
	if not NetworkManager.is_host() and not NetworkManager.is_playpen_open():
		_on_lobby_notice("The host must open The Playpen first.")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "ENTER THE PLAYPEN"
	dialog.dialog_text = "Are you ready for the match?\n\nYour answer updates your lobby Ready status before entering practice."
	dialog.ok_button_text = "YES"
	dialog.cancel_button_text = "CANCEL"
	dialog.add_button("NO", true, "not_ready")
	add_child(dialog)
	dialog.confirmed.connect(func():
		NetworkManager.request_enter_playpen(true)
		dialog.queue_free())
	dialog.custom_action.connect(func(action: StringName):
		if action == &"not_ready":
			NetworkManager.request_enter_playpen(false)
			dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(520, 250))

# Back / Play
# ============================================================
func _on_back_button_pressed():
	if _player_settings_overlay != null:
		_close_player_settings_immediately()
		return

	if _character_customization_overlay != null:
		_character_customization_overlay.queue_free()
		_character_customization_overlay = null
		return
	if _settings_slideout != null and is_instance_valid(_settings_slideout):
		_close_settings_slideout()
		return
	if NetworkManager.is_online():
		NetworkManager.disconnect_net()
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _on_play_button_pressed():
	if not _is_net():
		_launch_match()
		return
	if NetworkManager.lobby_in_progress and not NetworkManager.is_match_participant(NetworkManager.local_id()):
		NetworkManager.request_spectate_current_match()
		return
	if NetworkManager.is_host():
		if NetworkManager._prelaunch_active:
			NetworkManager.cancel_prelaunch("Host cancelled the start countdown")
			return
		# OneGunConfirmButton handles the two-click FORCE START path. When all
		# guests are ready, this same button launches immediately in one click.
		if NetworkManager.are_all_lobby_guests_ready():
			_launch_match()
		return
	NetworkManager.set_local_lobby_ready(
		not NetworkManager.is_peer_lobby_ready(NetworkManager.local_id()))


func _update_lobby_action() -> void:
	if _play_button == null or not _is_net():
		return
	if NetworkManager.is_host():
		var all_ready := NetworkManager.are_all_lobby_guests_ready()
		if _play_button is OneGunConfirmButton:
			(_play_button as OneGunConfirmButton).set_idle(
				"START MATCH" if all_ready else "FORCE START",
				"gold" if all_ready else "red")
		var unavailable_reason := _selection_unavailable_reason()
		_play_button.disabled = unavailable_reason != ""
		if unavailable_reason != "":
			_play_button.tooltip_text = unavailable_reason
		else:
			_play_button.tooltip_text = "" if all_ready else "One or more guests are not ready. Press twice to force start."
	else:
		if NetworkManager.lobby_in_progress and not NetworkManager.is_match_participant(NetworkManager.local_id()):
			_play_button.text = "SPECTATE MATCH"
			_play_button.variant = "gold"
			_play_button.disabled = false
			_play_button.set_meta("action_id", "spectate_match")
			_play_button.tooltip_text = "Watch the active match until it ends"
			return
		var ready := NetworkManager.is_peer_lobby_ready(NetworkManager.local_id())
		_play_button.text = "READY" if ready else "READY UP"
		_play_button.variant = "green" if ready else "red"
		_play_button.disabled = false
		_play_button.tooltip_text = "Click to mark not ready" if ready else "Click when you are ready to play"


func _on_prelaunch_countdown_changed(active: bool, seconds: int) -> void:
	if active:
		_close_player_settings_immediately()
	if active and _character_customization_overlay != null:
		_character_customization_overlay.queue_free()
		_character_customization_overlay = null
	var controls: Array = [_map_dropdown, _mode_dropdown, _match_settings_button,
		_character_customization_button, _player_settings_button,
		_playpen_button, _carousel_prev, _carousel_next, _back_button]
	for control in controls:
		if control != null:
			control.disabled = active
	for card in _map_cards:
		card.disabled = active or (_is_net() and not NetworkManager.is_host())
	_refresh_one_of_us_preference_panel()
	if not active:
		if _is_net() and not NetworkManager.is_host():
			_apply_client_lock()
		_update_lobby_action()
		return
	_reset_force_start_confirmation()
	if NetworkManager.is_host():
		_play_button.disabled = false
		_play_button.text = "CANCEL — %d" % seconds
		_play_button.variant = "red"
		_play_button.set_meta("action_id", "cancel_start")
	else:
		_play_button.disabled = true
		_play_button.text = "STARTING IN %d" % seconds
		_play_button.variant = "gold"
		_play_button.set_meta("action_id", "starting_countdown")


func _reset_force_start_confirmation() -> void:
	if _play_button is OneGunConfirmButton:
		(_play_button as OneGunConfirmButton).notify_state_changed()


func _launch_match():
	var unavailable_reason := _selection_unavailable_reason()
	if unavailable_reason != "":
		if _lobby_notice_label != null:
			_lobby_notice_label.text = unavailable_reason
		if _banner_desc != null:
			_banner_desc.text = unavailable_reason
		push_warning("GameSetup: cannot start; %s" % unavailable_reason)
		_update_play_availability()
		return
	var map_path := _resolve_map_scene_path()
	if map_path == "" or not ResourceLoader.exists(map_path):
		_update_play_availability()
		push_warning("GameSetup: cannot start; selected map is unavailable: %s" % map_path)
		return
	if _is_net():
		if NetworkManager.is_host():
			NetworkManager.begin_prelaunch(map_path)
			return   # clients never launch directly
	AudioManager.stop_music(0.8)
	get_tree().change_scene_to_file(map_path)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _player_settings_overlay != null:
			_close_player_settings_immediately()
			return

		get_viewport().set_input_as_handled()
		if _character_customization_overlay != null:
			_character_customization_overlay.queue_free()
			_character_customization_overlay = null
		elif _settings_slideout != null and is_instance_valid(_settings_slideout):
			_close_settings_slideout()
		else:
			_on_back_button_pressed()
