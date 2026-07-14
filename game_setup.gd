extends Control

# ============================================================
# Map list — extend this array when new maps are wired in.
# ============================================================
const MAPS = [
	#{"name": "Coliseum", "scene_path": "res://node_3d.tscn"},
	#{"name": "Explosion Town", "scene_path": "res://maps/test/NukeTownMap.tscn"},
	{"name": "Whispering Woods", "scene_path": "res://maps/test/ForestMap.tscn"},
	{"name": "Western Town", "scene_path": "res://maps/test/WesternV2Map.tscn"},
	{"name": "Maple & 3rd", "scene_path": "res://maps/test/CityMap.tscn"},
]

enum MapSelectMode { VOTE, SPECIFIC, RANDOM }

var map_select_mode: int = MapSelectMode.SPECIFIC
var selected_map_index: int = 0

# ============================================================
# Lobby / ready state (local-only for now; not yet a separate
# autoload since there's no networked session to share it with).
# ============================================================
var player1_ready := false
var player2_ready := false

func _ready():
	_setup_layout()
	_setup_back_button()
	_build_map_selection_ui()
	_build_bots_toggle_ui()
	_build_settings_dropdown()
	_setup_ready_buttons()
	_refresh_lobby_list()
	_refresh_ready_ui()
	$BotSettingsPopup.hide()
	$CustomizeCharacterPopup.hide()
	$BotSettingsPopup.popup_hide.connect(_on_bot_settings_popup_closed)
	$CustomizeCharacterPopup.popup_hide.connect(_on_customize_popup_closed)
	if not $CustomizeButton.pressed.is_connected(_on_customize_button_pressed):
		$CustomizeButton.pressed.connect(_on_customize_button_pressed)
	_build_map_preview()
	_setup_online_mode()

# ============================================================
# Online (network) integration — host-authoritative lobby.
# ============================================================
func _is_net() -> bool:
	return NetworkManager.is_online()

func _setup_online_mode():
	if not _is_net():
		return
	# Phase 2b scoring is free-for-all. Online team assignment does not exist
	# yet, so keep team rules visibly unavailable instead of silently scoring a
	# team-configured lobby as FFA.
	GameConfig.teams_enabled = false
	GameConfig.friendly_fire_enabled = false
	NetworkManager.lobby_changed.connect(_on_online_lobby_changed)
	NetworkManager.match_config_received.connect(_on_net_config_synced)
	NetworkManager.server_disconnected.connect(_on_net_host_left)
	# Bots are host-configured online. Clients see the synchronized values but
	# the normal client settings lock prevents them from editing those values.
	var bot_btn = get_node_or_null("Settings Panel/BotSettingsButton")
	if bot_btn: bot_btn.visible = GameConfig.bot_count > 0
	var bots_row = get_node_or_null("Settings Panel/BotsToggleRow")
	if bots_row: bots_row.visible = true
	var force_play = get_node_or_null("ReadyBar/ForcePlayButton")
	if force_play: force_play.visible = false
	if NetworkManager.is_host():
		_net_broadcast_config()   # seed clients with the starting config/map
	else:
		_apply_client_lock()
	_refresh_lobby_list()

func _max_online_bots() -> int:
	return maxi(8 - NetworkManager.peers.size(), 0) if _is_net() else 7

func _on_online_lobby_changed() -> void:
	if NetworkManager.is_host() and GameConfig.bot_count > _max_online_bots():
		GameConfig.set_bot_count(_max_online_bots())
		_net_broadcast_config()
	_build_bots_toggle_ui()
	_refresh_lobby_list()

func _net_broadcast_config():
	if _is_net() and NetworkManager.is_host():
		NetworkManager.broadcast_match_config(GameConfig.snapshot_for_preset(), _resolve_map_scene_path())

func _on_net_config_synced():
	# Client: reflect the host's map choice in the preview + picker.
	var path = NetworkManager.pending_map_path
	for i in MAPS.size():
		if MAPS[i]["scene_path"] == path:
			selected_map_index = i
			var picker = get_node_or_null("Settings Panel/MapSelectionRow/MapPicker")
			if picker: picker.select(i)
			if _map_preview != null:
				_map_preview.apply(MapSelectMode.SPECIFIC, i)
			break
	_build_bots_toggle_ui()
	_refresh_lobby_list()

func _apply_client_lock():
	# Clients can't touch settings — host configures for everyone.
	var panel = get_node_or_null("Settings Panel")
	if panel: _disable_controls(panel)
	var play = get_node_or_null("ReadyBar/PlayButton")
	if play:
		play.text = "Waiting for host…"
		play.disabled = true
	var p1_ready = get_node_or_null("ReadyBar/ReadyButton")
	if p1_ready: p1_ready.visible = false

func _disable_controls(node: Node):
	for c in node.get_children():
		if c is BaseButton:
			c.disabled = true
		elif c is LineEdit or c is SpinBox or c is Slider:
			c.editable = false
		_disable_controls(c)

func _on_net_host_left():
	# Host disappeared — bail back to the main menu.
	get_tree().change_scene_to_file("res://main_menu.tscn")

# Live 3D map preview behind the UI (perimeter-orbit camera).
var _map_preview = null

func _build_map_preview():
	_map_preview = preload("res://lobby_map_preview.gd").new()
	add_child(_map_preview)
	_map_preview.setup(self, MAPS)
	_map_preview.apply(map_select_mode, selected_map_index)

func _setup_back_button():
	var existing = get_node_or_null("BackButton")
	var back_button: Button
	if existing == null:
		back_button = Button.new()
		back_button.name = "BackButton"
		add_child(back_button)
	else:
		back_button = existing
	back_button.text = "← Back"
	back_button.anchor_left = 0.0
	back_button.anchor_top = 1.0
	back_button.anchor_right = 0.0
	back_button.anchor_bottom = 1.0
	back_button.offset_left = 40
	back_button.offset_top = -76
	back_button.offset_right = 40 + 100
	back_button.offset_bottom = -40
	back_button.custom_minimum_size = Vector2(100, 36)
	if not back_button.pressed.is_connected(_on_back_button_pressed):
		back_button.pressed.connect(_on_back_button_pressed)
	if not back_button.mouse_entered.is_connected(func(): AudioManager.play_hover()):
		back_button.mouse_entered.connect(func(): AudioManager.play_hover())

func _on_back_button_pressed():
	AudioManager.play_click()
	if NetworkManager.is_online():
		NetworkManager.disconnect_net()
	get_tree().change_scene_to_file("res://main_menu.tscn")

# ------------------------------------------------------------
# Layout — anchors/offsets for every top-level panel, plus
# spacing inside the containers that hold dynamically-built rows.
# ------------------------------------------------------------
func _setup_layout():
	# Make sure this whole screen fills the viewport, not just its default size.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var settings_panel = $"Settings Panel"
	settings_panel.anchor_left = 0.0
	settings_panel.anchor_top = 0.0
	settings_panel.anchor_right = 0.0
	settings_panel.anchor_bottom = 0.0
	settings_panel.offset_left = 16
	settings_panel.offset_top = 16
	settings_panel.offset_right = 16 + 700
	settings_panel.offset_bottom = -140

	# Settings Panel is a plain Control, not a layout container, so it has
	# no automatic child-stacking. Each child's vertical position is set
	# explicitly here, in order, with a consistent gap between rows.
	var next_y := 0
	var row_gap := 16

	for row_name in ["MapSelectionRow", "BotsToggleRow"]:
		var row = settings_panel.get_node(row_name)
		row.add_theme_constant_override("separation", 12)
		row.anchor_left = 0.0
		row.anchor_top = 0.0
		row.anchor_right = 1.0
		row.anchor_bottom = 0.0
		row.offset_left = 0
		row.offset_right = 0
		row.offset_top = next_y
		row.custom_minimum_size = Vector2(0, 36)
		row.offset_bottom = next_y + 36
		next_y += 36 + row_gap

	var bot_settings_button = $"Settings Panel/BotSettingsButton"
	bot_settings_button.anchor_left = 0.0
	bot_settings_button.anchor_top = 0.0
	bot_settings_button.anchor_right = 0.0
	bot_settings_button.anchor_bottom = 0.0
	bot_settings_button.offset_left = 0
	bot_settings_button.offset_top = next_y
	bot_settings_button.custom_minimum_size = Vector2(180, 36)
	bot_settings_button.offset_right = 180
	bot_settings_button.offset_bottom = next_y + 36
	next_y += 36 + row_gap

	var toggle_dropdown = settings_panel.get_node("ToggleDropdown")
	toggle_dropdown.add_theme_constant_override("separation", 8)
	toggle_dropdown.anchor_left = 0.0
	toggle_dropdown.anchor_top = 0.0
	toggle_dropdown.anchor_right = 1.0
	toggle_dropdown.anchor_bottom = 0.0
	toggle_dropdown.offset_left = 0
	toggle_dropdown.offset_right = 0
	toggle_dropdown.offset_top = next_y
	toggle_dropdown.offset_bottom = next_y + 320  # fixed height; settings column scrolls within it
	next_y += 320 + row_gap

	var lobby_panel = $LobbyQueuePanel
	lobby_panel.anchor_left = 1.0
	lobby_panel.anchor_top = 0.0
	lobby_panel.anchor_right = 1.0
	lobby_panel.anchor_bottom = 0.0
	lobby_panel.offset_left = -420
	lobby_panel.offset_top = 16
	lobby_panel.offset_right = -16
	lobby_panel.offset_bottom = 376
	var lobby_list = $LobbyQueuePanel/LobbyList
	lobby_list.add_theme_constant_override("separation", 10)
	lobby_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var customize_button = $CustomizeButton
	customize_button.anchor_left = 0.0
	customize_button.anchor_top = 0.0
	customize_button.anchor_right = 0.0
	customize_button.anchor_bottom = 0.0
	customize_button.offset_left = 40
	customize_button.offset_top = -180
	customize_button.offset_right = 40 + 240
	customize_button.offset_bottom = -180 + 44
	customize_button.text = "Customize Your Character"

	var ready_bar = $ReadyBar
	ready_bar.anchor_left = 0.0
	ready_bar.anchor_top = 1.0
	ready_bar.anchor_right = 1.0
	ready_bar.anchor_bottom = 1.0
	ready_bar.offset_left = 40
	ready_bar.offset_top = -100
	ready_bar.offset_right = -40
	ready_bar.offset_bottom = -40
	ready_bar.add_theme_constant_override("separation", 20)
	ready_bar.alignment = BoxContainer.ALIGNMENT_END
	for button_path in ["ReadyButton", "PlayButton", "ForcePlayButton"]:
		var button = ready_bar.get_node(button_path)
		button.custom_minimum_size = Vector2(200, 50)

# ------------------------------------------------------------
# Map selection
# ------------------------------------------------------------
func _build_map_selection_ui():
	var row = $"Settings Panel/MapSelectionRow"
	for child in row.get_children():
		child.queue_free()

	var label = Label.new()
	label.text = "Map:"
	row.add_child(label)

	var mode_button = OptionButton.new()
	mode_button.add_item("Vote", MapSelectMode.VOTE)
	mode_button.add_item("Specific Map", MapSelectMode.SPECIFIC)
	mode_button.add_item("Random", MapSelectMode.RANDOM)
	mode_button.select(map_select_mode)
	mode_button.item_selected.connect(_on_map_mode_selected)
	mode_button.custom_minimum_size = Vector2(160, 36)
	mode_button.fit_to_longest_item = true
	row.add_child(mode_button)
	mode_button.get_popup().max_size = Vector2(0, 124)
	mode_button.get_popup().about_to_popup.connect(func():
		mode_button.get_popup().max_size = Vector2(mode_button.size.x, 124)
	)

	var map_picker = OptionButton.new()
	map_picker.name = "MapPicker"
	for i in MAPS.size():
		map_picker.add_item(MAPS[i]["name"], i)
	map_picker.select(selected_map_index)
	map_picker.item_selected.connect(_on_map_picked)
	map_picker.visible = (map_select_mode == MapSelectMode.SPECIFIC)
	map_picker.custom_minimum_size = Vector2(180, 36)
	map_picker.fit_to_longest_item = true
	row.add_child(map_picker)
	map_picker.get_popup().max_size = Vector2(0, 124)
	map_picker.get_popup().about_to_popup.connect(func():
		map_picker.get_popup().max_size = Vector2(map_picker.size.x, 124)
	)

func _on_map_mode_selected(index: int):
	map_select_mode = index
	var map_picker = $"Settings Panel/MapSelectionRow/MapPicker"
	map_picker.visible = (map_select_mode == MapSelectMode.SPECIFIC)
	if _map_preview != null:
		_map_preview.apply(map_select_mode, selected_map_index)
	_reset_all_ready()

func _on_map_picked(index: int):
	selected_map_index = index
	if _map_preview != null:
		_map_preview.apply(map_select_mode, index)
	_reset_all_ready()

func _resolve_map_scene_path() -> String:
	match map_select_mode:
		MapSelectMode.RANDOM:
			return MAPS[randi() % MAPS.size()]["scene_path"]
		MapSelectMode.VOTE:
			# Voting requires a real lobby/network layer to collect votes from
			# multiple players. Until that exists, vote mode falls back to
			# the host's specific-map pick so the game can still launch.
			return MAPS[selected_map_index]["scene_path"]
		_:
			return MAPS[selected_map_index]["scene_path"]

# ------------------------------------------------------------
# Bots toggle + Bot Settings popup launcher
# ------------------------------------------------------------
func _build_bots_toggle_ui():
	var row = $"Settings Panel/BotsToggleRow"
	for child in row.get_children():
		child.queue_free()

	var label = Label.new()
	label.text = "Bots:"
	row.add_child(label)

	var checkbox = CheckBox.new()
	checkbox.name = "BotsEnabledCheck"
	checkbox.button_pressed = GameConfig.bot_count > 0
	checkbox.disabled = _is_net() and not NetworkManager.is_host()
	checkbox.toggled.connect(_on_bots_toggled)
	row.add_child(checkbox)

	_update_bot_settings_button_visibility()

func _on_bots_toggled(enabled: bool):
	if not enabled:
		GameConfig.bot_count = 0
	elif GameConfig.bot_count == 0 and (not _is_net() or _max_online_bots() > 0):
		GameConfig.bot_count = 1
	if _is_net() and GameConfig.bot_count > _max_online_bots():
		GameConfig.set_bot_count(_max_online_bots())
	_update_bot_settings_button_visibility()
	_reset_all_ready()

func _update_bot_settings_button_visibility():
	var button = $"Settings Panel/BotSettingsButton"
	button.text = "Bot Settings"
	button.visible = GameConfig.bot_count > 0
	if not button.pressed.is_connected(_on_bot_settings_button_pressed):
		button.pressed.connect(_on_bot_settings_button_pressed)

func _on_bot_settings_button_pressed():
	AudioManager.play_click()
	_build_bot_settings_popup()
	$BotSettingsPopup.popup_centered()
	_reset_all_ready()

func _on_bot_settings_popup_closed():
	_build_bots_toggle_ui()

const DIFFICULTY_OPTIONS = ["easy", "medium", "hard", "expert"]

func _build_bot_settings_popup():
	var popup = $BotSettingsPopup
	for child in popup.get_children():
		child.queue_free()

	var root = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	popup.add_child(root)
	popup.size = Vector2(420, 80 + 48 * max(GameConfig.bot_configs.size(), 1))

	# -- Count adjuster --
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
	plus_button.disabled = _is_net() and GameConfig.bot_configs.size() >= _max_online_bots()
	minus_button.pressed.connect(func():
		GameConfig.set_bot_count(GameConfig.bot_configs.size() - 1)
		_reset_all_ready()
		await get_tree().process_frame
		_build_bot_settings_popup()
		_update_bot_settings_button_visibility()
	)
	plus_button.pressed.connect(func():
		var requested := GameConfig.bot_configs.size() + 1
		if _is_net():
			requested = mini(requested, _max_online_bots())
		GameConfig.set_bot_count(requested)
		_reset_all_ready()
		await get_tree().process_frame
		_build_bot_settings_popup()
		_update_bot_settings_button_visibility()
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
		_reset_all_ready()
	)
	row.add_child(difficulty_button)
	difficulty_button.get_popup().max_size = Vector2(0, 164)

	if GameConfig.teams_enabled:
		var team_button = OptionButton.new()
		team_button.add_item("No Team", 0)
		for t in range(4):
			team_button.add_item("Team " + str(t + 1), t + 1)
		var current_team = GameConfig.bot_configs[bot_index].get("team_id", -1)
		team_button.select(current_team + 1)
		team_button.fit_to_longest_item = true
		team_button.custom_minimum_size = Vector2(120, 36)
		team_button.item_selected.connect(func(idx):
			GameConfig.bot_configs[bot_index]["team_id"] = idx - 1
		)
		row.add_child(team_button)
		team_button.get_popup().max_size = Vector2(0, 124)

	return row

# ------------------------------------------------------------
# Collapsible gameplay/match settings dropdown
# ------------------------------------------------------------
var _dropdown_expanded := false

func _build_settings_dropdown():
	var container = $"Settings Panel/ToggleDropdown"
	for child in container.get_children():
		child.queue_free()

	var header_button = Button.new()
	header_button.name = "DropdownHeader"
	header_button.text = "▶ Match Settings"
	header_button.toggle_mode = true
	header_button.button_pressed = _dropdown_expanded
	header_button.toggled.connect(_on_dropdown_header_toggled)
	container.add_child(header_button)

	var columns = HBoxContainer.new()
	columns.name = "DropdownContent"
	columns.visible = _dropdown_expanded
	columns.add_theme_constant_override("separation", 16)
	container.add_child(columns)

	# -- Left column: settings, in a fixed-height scroll box --
	var scroll = ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.custom_minimum_size = Vector2(420, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)

	var settings_list = VBoxContainer.new()
	settings_list.name = "SettingsList"
	settings_list.add_theme_constant_override("separation", 8)
	settings_list.custom_minimum_size = Vector2(400, 0)
	scroll.add_child(settings_list)

	_add_bool_setting(settings_list, "Teams Enabled", GameConfig.teams_enabled, func(v): GameConfig.teams_enabled = v)
	_add_bool_setting(settings_list, "Friendly Fire", GameConfig.friendly_fire_enabled, func(v): GameConfig.friendly_fire_enabled = v)
	_add_bool_setting(settings_list, "Melee Eliminates Gun Holder", GameConfig.melee_eliminates_gunholder, func(v): GameConfig.melee_eliminates_gunholder = v)
	_add_bool_setting(settings_list, "Melee Eliminates Anyone", GameConfig.melee_eliminates_anyone, func(v): GameConfig.melee_eliminates_anyone = v)
	_add_bool_setting(settings_list, "Melee Effects Hit Anyone", GameConfig.melee_effects_hit_anyone, func(v): GameConfig.melee_effects_hit_anyone = v)
	_add_bool_setting(settings_list, "Hazards Enabled", GameConfig.hazards_enabled, func(v): GameConfig.hazards_enabled = v)
	_add_bool_setting(settings_list, "Consumables Enabled", GameConfig.consumables_enabled, func(v): GameConfig.consumables_enabled = v)
	_add_enum_setting(settings_list, "Gun Spawn Mode", ["center", "random"], GameConfig.gun_spawn_mode, func(v): GameConfig.gun_spawn_mode = v)
	_add_float_setting(settings_list, "Disarm Lock Time (s)", GameConfig.disarm_lock_time, 0.0, 10.0, func(v): GameConfig.disarm_lock_time = v)
	_add_float_setting(settings_list, "Melee Spawn Delay (s)", GameConfig.melee_spawn_delay, 0.0, 15.0, func(v): GameConfig.melee_spawn_delay = v)
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
		_build_bots_toggle_ui()
		_build_settings_dropdown()
		_dropdown_expanded = true
		_on_dropdown_header_toggled(true)
		_reset_all_ready()
	)
	settings_list.add_child(default_button)

	# -- Right column: ruleset presets --
	var presets_section = VBoxContainer.new()
	presets_section.name = "PresetsSection"
	presets_section.add_theme_constant_override("separation", 6)
	presets_section.custom_minimum_size = Vector2(260, 0)
	columns.add_child(presets_section)
	_populate_preset_section(presets_section)

func _populate_preset_section(section: VBoxContainer):
	for child in section.get_children():
		child.queue_free()

	var title = Label.new()
	title.text = "Ruleset Presets"
	section.add_child(title)

	for i in GameConfig.MAX_PRESET_SLOTS:
		section.add_child(_build_preset_slot_row(i))

func _refresh_preset_section():
	if not _dropdown_expanded:
		return
	var section = $"Settings Panel/ToggleDropdown".get_node_or_null("DropdownContent/PresetsSection")
	if section != null:
		_populate_preset_section(section)

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
		_build_bots_toggle_ui()
		_build_settings_dropdown()
		_reset_all_ready()
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

func _on_dropdown_header_toggled(expanded: bool):
	_dropdown_expanded = expanded
	var header = $"Settings Panel/ToggleDropdown".get_node_or_null("DropdownHeader")
	if header != null:
		header.text = ("▼ " if expanded else "▶ ") + "Match Settings"
	var content = $"Settings Panel/ToggleDropdown".get_node_or_null("DropdownContent")
	if content != null:
		content.visible = expanded

func _add_bool_setting(parent: VBoxContainer, label_text: String, current_value: bool, on_changed: Callable):
	var row = HBoxContainer.new()
	var label = Label.new()
	var online_forced_off := _is_net() and label_text in ["Teams Enabled", "Friendly Fire"]
	label.text = label_text + (" (offline only)" if online_forced_off else "")
	label.custom_minimum_size = Vector2(220, 0)
	var checkbox = CheckBox.new()
	checkbox.button_pressed = false if online_forced_off else current_value
	checkbox.disabled = online_forced_off
	checkbox.toggled.connect(func(v):
		on_changed.call(v)
		_reset_all_ready()
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
		_reset_all_ready()
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
		_reset_all_ready()
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
		_reset_all_ready()
	)
	row.add_child(label)
	row.add_child(spinbox)
	parent.add_child(row)

# ------------------------------------------------------------
# Lobby queue
# ------------------------------------------------------------
func _refresh_lobby_list():
	var list = $LobbyQueuePanel/LobbyList
	for child in list.get_children():
		child.queue_free()

	if _is_net():
		if NetworkManager.lobby_name != "":
			var lobby_heading := Label.new()
			lobby_heading.text = "Lobby: %s" % NetworkManager.lobby_name
			lobby_heading.add_theme_font_size_override("font_size", 22)
			list.add_child(lobby_heading)
		for id in NetworkManager.peer_ids_sorted():
			var nm = str(NetworkManager.peers[id]["name"])
			var is_me = (id == NetworkManager.local_id())
			var row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var label = Label.new()
			label.text = nm + (" (Host)" if id == 1 else "") + ("  ← you" if is_me else "")
			row.add_child(label)
			if is_me:
				var edit_button := Button.new()
				edit_button.text = "Edit Name"
				edit_button.pressed.connect(_on_edit_online_name)
				row.add_child(edit_button)
			list.add_child(row)
		return

	_add_lobby_entry(list, PlayerPrefs.get_setting("player_name"), player1_ready, true, _on_edit_player1_name)
	if GameConfig.split_screen_enabled:
		_add_lobby_entry(list, GameConfig.player2_name, player2_ready, false, _on_edit_player2_name)

func _add_lobby_entry(list: VBoxContainer, player_name: String, is_ready: bool, is_host: bool, on_edit_name: Callable):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label = Label.new()
	label.text = player_name + (" (Host)" if is_host else "")
	row.add_child(label)

	var status = Label.new()
	status.text = "Ready" if is_ready else "Not Ready"
	status.modulate = Color.GREEN if is_ready else Color(0.6, 0.6, 0.6)
	row.add_child(status)

	# Edit Name is only meaningful for your own entry. Locally, both seats
	# at this screen are "yours" (you control both controllers), so both
	# get the button. Once online play exists, this should only show next
	# to the entry that belongs to the player actually viewing this screen.
	var edit_button = Button.new()
	edit_button.text = "Edit Name"
	edit_button.pressed.connect(on_edit_name)
	row.add_child(edit_button)

	list.add_child(row)

func _on_edit_player1_name():
	_prompt_edit_name(PlayerPrefs.get_setting("player_name"), func(new_name: String):
		PlayerPrefs.set_setting("player_name", new_name)
		_refresh_lobby_list()
	)

func _on_edit_online_name() -> void:
	_prompt_edit_name(NetworkManager.local_name(), func(new_name: String):
		NetworkManager.set_local_name(new_name)
		_refresh_lobby_list()
	)

func _on_edit_player2_name():
	_prompt_edit_name(GameConfig.player2_name, func(new_name: String):
		GameConfig.player2_name = new_name
		_refresh_lobby_list()
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

# ------------------------------------------------------------
# Customize Character popup launcher
# ------------------------------------------------------------
func _on_customize_button_pressed():
	AudioManager.play_click()
	$CustomizeCharacterPopup.popup_centered()
	_reset_all_ready()

func _on_customize_popup_closed():
	pass

# ------------------------------------------------------------
# Ready / Play / Force Play
# ------------------------------------------------------------
func _setup_ready_buttons():
	var ready_bar = $ReadyBar
	var player1_button: Button = ready_bar.get_node("ReadyButton")
	player1_button.text = "Player 1 Ready"
	if not player1_button.pressed.is_connected(_on_player1_ready_pressed):
		player1_button.pressed.connect(_on_player1_ready_pressed)

	var play_button: Button = ready_bar.get_node("PlayButton")
	play_button.text = "Play"
	if not play_button.pressed.is_connected(_on_play_button_pressed):
		play_button.pressed.connect(_on_play_button_pressed)

	var force_play_button: Button = ready_bar.get_node("ForcePlayButton")
	force_play_button.text = "Force Play"
	if not force_play_button.pressed.is_connected(_on_force_play_button_pressed):
		force_play_button.pressed.connect(_on_force_play_button_pressed)

	var existing_p2_button = ready_bar.get_node_or_null("Player2ReadyButton")
	if GameConfig.split_screen_enabled:
		if existing_p2_button == null:
			var p2_button = Button.new()
			p2_button.name = "Player2ReadyButton"
			p2_button.text = "Player 2 Ready"
			p2_button.custom_minimum_size = Vector2(200, 50)
			p2_button.pressed.connect(_on_player2_ready_pressed)
			ready_bar.add_child(p2_button)
			ready_bar.move_child(p2_button, player1_button.get_index() + 1)
	elif existing_p2_button != null:
		existing_p2_button.queue_free()

func _on_player1_ready_pressed():
	AudioManager.play_click()
	player1_ready = not player1_ready
	_refresh_lobby_list()
	_refresh_ready_ui()

func _on_player2_ready_pressed():
	AudioManager.play_click()
	player2_ready = not player2_ready
	_refresh_lobby_list()
	_refresh_ready_ui()

func _reset_all_ready():
	GameConfig.lobby_settings_dirty = true
	player1_ready = false
	player2_ready = false
	_refresh_lobby_list()
	_refresh_ready_ui()
	_net_broadcast_config()   # host: push settings/map changes to clients

func _all_players_ready() -> bool:
	if GameConfig.split_screen_enabled:
		return player1_ready and player2_ready
	return player1_ready

func _refresh_ready_ui():
	var ready_bar = $ReadyBar
	var play_button: Button = ready_bar.get_node("PlayButton")
	var force_play_button: Button = ready_bar.get_node("ForcePlayButton")

	# Online: host can always start; clients wait.
	if _is_net():
		force_play_button.visible = false
		if NetworkManager.is_host():
			play_button.text = "Start Match"
			play_button.disabled = false
			play_button.modulate = Color.GREEN
		else:
			play_button.text = "Waiting for host…"
			play_button.disabled = true
			play_button.modulate = Color.WHITE
		return

	var is_solo = not GameConfig.split_screen_enabled
	force_play_button.visible = not is_solo
	force_play_button.modulate = Color(1.0, 0.35, 0.35)

	var all_ready = _all_players_ready()
	play_button.modulate = Color.GREEN if all_ready else Color.WHITE
	play_button.disabled = not all_ready and not is_solo

	var p1_button: Button = ready_bar.get_node("ReadyButton")
	p1_button.modulate = Color.GREEN if player1_ready else Color.WHITE
	var p2_button = ready_bar.get_node_or_null("Player2ReadyButton")
	if p2_button != null:
		p2_button.modulate = Color.GREEN if player2_ready else Color.WHITE

func _on_play_button_pressed():
	if GameConfig.split_screen_enabled and not _all_players_ready():
		return
	AudioManager.play_click()
	_launch_match()

func _on_force_play_button_pressed():
	AudioManager.play_click()
	_launch_match()

func _launch_match():
	if _is_net():
		if NetworkManager.is_host():
			AudioManager.stop_music(0.8)
			NetworkManager.start_game(_resolve_map_scene_path())
		return   # clients never launch directly
	AudioManager.stop_music(0.8)
	get_tree().change_scene_to_file(_resolve_map_scene_path())
