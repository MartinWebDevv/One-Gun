class_name ProgressionRoadOverlay
extends Control

signal closed

const BASE_SIZE := Vector2(1600.0, 900.0)
const HUB_BACKDROP_SCRIPT = preload("res://UI/components/menu_hub_backdrop.gd")
const PROFILE_BACKDROP = preload("res://UI/assets/menu_hubs/profile_backdrop.png")
const ProgressionCaptureFixture = preload("res://UI/progression_capture_fixture.gd")
const COSMETIC_PREVIEW_SCRIPT = preload(
	"res://UI/components/cosmetic_character_preview.gd")

var _canvas: Control
var _pages: Array[Control] = []
var _level_label: Label
var _xp_label: Label
var _trophy_label: Label
var _prestige_label: Label
var _xp_bar: ProgressBar
var _level_road: HBoxContainer
var _trophy_road: HBoxContainer
var _season_title: Label
var _season_dates: Label
var _season_rules: Label
var _feedback: Label
var _tabs: OneGunTabBar
var _close_button: OneGunButton
var _cosmetic_preview: Control
var _preview_return_focus: Control
var _road_focus_buttons := {"level": [], "trophy": []}


func _ready() -> void:
	var is_capture := OS.get_environment("ONEGUN_UI_CAPTURE") != "" \
		and OS.get_environment("ONEGUN_UI_CAPTURE_STATE") == "progression"
	if is_capture:
		ProgressionCaptureFixture.seed_backend(SupabaseManager)
		ProgressionManager.progression = ProgressionCaptureFixture.snapshot()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	ProgressionManager.progression_updated.connect(_on_progression_updated)
	SupabaseManager.login_state_changed.connect(_on_login_state_changed)
	_refresh()
	resized.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	if not is_capture and SupabaseManager.is_authenticated() \
			and ProgressionManager.progression.is_empty():
		ProgressionManager.load_progression.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		if _cosmetic_preview != null:
			_close_cosmetic_preview()
		else:
			_close()


func _build_ui() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.001, 0.004, 0.014, 1.0)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	_canvas = Control.new()
	_canvas.name = "ProgressionRoadCanvas"
	_canvas.size = BASE_SIZE
	add_child(_canvas)
	var backdrop := HUB_BACKDROP_SCRIPT.new()
	backdrop.position = Vector2.ZERO
	backdrop.size = BASE_SIZE
	backdrop.configure(PROFILE_BACKDROP, MenuHubBackdrop.Variant.PROFILE)
	_canvas.add_child(backdrop)
	var shade := ColorRect.new()
	shade.position = Vector2.ZERO
	shade.size = BASE_SIZE
	shade.color = Color(0.004, 0.009, 0.026, 0.54)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(shade)

	var title := OneGunUI.make_heading("PROGRESSION ROADS", 42, "text_bright")
	title.position = Vector2(64.0, 44.0)
	title.size = Vector2(900.0, 52.0)
	_canvas.add_child(title)
	_close_button = OneGunButton.new()
	_close_button.name = "ProgressionBackButton"
	_close_button.text = "BACK"
	_close_button.variant = "navy"
	_close_button.position = Vector2(64.0, 808.0)
	_close_button.size = Vector2(220.0, 60.0)
	_close_button.pressed.connect(_close)
	_canvas.add_child(_close_button)

	var summary := OneGunCabinet.new()
	summary.variant = OneGunCabinet.Variant.SECTION
	summary.content_padding = 16
	summary.position = Vector2(64.0, 136.0)
	summary.size = Vector2(1472.0, 126.0)
	_canvas.add_child(summary)
	var summary_row := HBoxContainer.new()
	summary_row.add_theme_constant_override("separation", 14)
	summary.get_content().add_child(summary_row)
	var level_tile := _make_summary_tile("SEASON LEVEL / PRESTIGE", "— / P0", "gold")
	var trophy_tile := _make_summary_tile("CLASSIC TROPHIES", "0", "cyan")
	var prestige_tile := _make_summary_tile("CAREER LEVEL / PRESTIGE", "0 / P0", "purple")
	_level_label = level_tile.get_meta("value_label") as Label
	_trophy_label = trophy_tile.get_meta("value_label") as Label
	_prestige_label = prestige_tile.get_meta("value_label") as Label
	summary_row.add_child(level_tile)
	summary_row.add_child(trophy_tile)
	summary_row.add_child(prestige_tile)
	var xp_column := VBoxContainer.new()
	xp_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_column.alignment = BoxContainer.ALIGNMENT_CENTER
	xp_column.add_theme_constant_override("separation", 6)
	summary_row.add_child(xp_column)
	_xp_label = OneGunUI.make_label("0 / 150 XP TO NEXT LEVEL",
		OneGunUI.TEXT_S, "green", true)
	xp_column.add_child(_xp_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(0.0, 28.0)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.add_theme_stylebox_override("background", OneGunUI.style_box(
		Color(0.006, 0.016, 0.04), Color(OneGunUI.color("border"), 0.6), 12, 1))
	_xp_bar.add_theme_stylebox_override("fill", OneGunUI.style_box(
		Color(OneGunUI.color("green"), 0.88), OneGunUI.color("green"), 12, 1))
	xp_column.add_child(_xp_bar)

	var body := OneGunCabinet.new()
	body.name = "ProgressionCabinet"
	body.variant = OneGunCabinet.Variant.CABINET
	body.content_padding = 18
	body.position = Vector2(64.0, 278.0)
	body.size = Vector2(1472.0, 514.0)
	_canvas.add_child(body)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	body.get_content().add_child(column)
	_tabs = OneGunTabBar.new()
	_tabs.tabs = PackedStringArray(["LEVEL ROAD", "TROPHY ROAD", "SEASON RULES"])
	_tabs.tab_selected.connect(_show_page)
	column.add_child(_tabs)
	var holder := MarginContainer.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(holder)
	var level_page := _build_road_page("LEVEL ROAD",
		"Season XP advances this road indefinitely. The first 100 levels carry seasonal prizes; every tenth level after 100 awards 100 Gun Tokens.",
		"level")
	var trophy_page := _build_road_page("TROPHY ROAD",
		"Only first-place Official Classic One Gun victories award a Trophy. Every prize remains owned after the season resets.",
		"trophy")
	var season_page := _build_season_page()
	_pages = [level_page, trophy_page, season_page]
	for page in _pages:
		holder.add_child(page)
	_feedback = OneGunUI.make_label("", OneGunUI.TEXT_S, "muted", true)
	_feedback.position = Vector2(304.0, 822.0)
	_feedback.size = Vector2(1232.0, 34.0)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_canvas.add_child(_feedback)
	_show_page(0)
	_focus_first_tab.call_deferred()


func _make_summary_tile(title: String, value: String, role: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(230.0, 88.0)
	panel.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(0.008, 0.022, 0.052, 0.94), Color(OneGunUI.color(role), 0.48),
		12, 1, 2, 10.0))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)
	var value_label := OneGunUI.make_heading(value, 28, role)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(value_label)
	var title_label := OneGunUI.make_label(title, OneGunUI.TEXT_XS, "muted", true)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title_label)
	panel.set_meta("value_label", value_label)
	return panel


func _build_road_page(title: String, description: String, road: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.add_child(OneGunUI.make_heading(title, OneGunUI.TEXT_XL,
		"gold" if road == "level" else "cyan"))
	var copy := OneGunUI.make_label(description, OneGunUI.TEXT_M, "text")
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(copy)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(cards)
	if road == "level":
		_level_road = cards
	else:
		_trophy_road = cards
	return column


func _build_season_page() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	_season_title = OneGunUI.make_heading("BETA SEASON", 32, "gold")
	column.add_child(_season_title)
	_season_dates = OneGunUI.make_label("THREE-MONTH SEASON", OneGunUI.TEXT_M,
		"cyan", true)
	column.add_child(_season_dates)
	_season_rules = OneGunUI.make_label(
		"Official Classic One Gun FFA • 3+ authenticated humans • no bots • 3-minute rounds • Standard Overtime • first to 3 round wins. Private Tailscale matches count in full during Beta.",
		OneGunUI.TEXT_L, "text")
	_season_rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_season_rules)
	var reset_note := OneGunUI.make_label(
		"Season XP needs 150 at Level 1, then rises by 2 each level. Career levels always need 400 XP. Your first Official Classic victory each UTC day adds 25 Season XP and 100 Gun Tokens. Season progress resets into the Legacy Hall; Career progress, Tokens, and cosmetics stay permanent.",
		OneGunUI.TEXT_M, "green", true)
	reset_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(reset_note)
	return column


func _refresh() -> void:
	var snapshot: Dictionary = ProgressionManager.progression
	var signed_in := SupabaseManager.is_authenticated()
	if not signed_in:
		_feedback.text = "SIGN IN THROUGH PROFILE TO BEGIN YOUR BETA SEASON RECORD"
	elif snapshot.is_empty():
		_feedback.text = "LOADING SEASON RECORD…"
	else:
		_feedback.text = "OFFICIAL MATCH REWARDS UPDATE THESE ROADS AUTOMATICALLY"
	var progress = snapshot.get("progress", {})
	var career = snapshot.get("career", {})
	var season = snapshot.get("season", {})
	if not progress is Dictionary:
		progress = {}
	if not career is Dictionary:
		career = {}
	if not season is Dictionary:
		season = {}
	var season_level := int(progress.get("season_level", 1))
	var career_level := int(career.get(
		"career_level", int(career.get("levels_earned", 0)) + 1))
	_level_label.text = "LVL %d / P%d" % [season_level, (season_level - 1) / 100]
	_trophy_label.text = str(progress.get("trophies", 0))
	_prestige_label.text = "LVL %d / P%d" % [
		career_level, (career_level - 1) / 100]
	var xp := int(progress.get("xp_into_level", 0))
	var required := maxi(int(progress.get("next_level_xp", 150)), 1)
	_xp_label.text = "%d / %d XP TO NEXT LEVEL" % [xp, required]
	_xp_bar.max_value = required
	_xp_bar.value = xp
	_season_title.text = str(season.get("display_name", "BETA SEASON")).to_upper()
	_season_dates.text = "%s  →  %s" % [
		_short_date(str(season.get("starts_at", ""))),
		_short_date(str(season.get("ends_at", "")))]
	_rebuild_road(_level_road, snapshot.get("level_road", []),
		int(progress.get("season_level", 1)), "LEVEL")
	_rebuild_road(_trophy_road, snapshot.get("trophy_road", []),
		int(progress.get("trophies", 0)), "TROPHY")


func _rebuild_road(container: HBoxContainer, values, current: int,
		unit: String) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()
	if not values is Array or values.is_empty():
		container.add_child(_make_empty_road_card(unit))
		_road_focus_buttons[unit.to_lower()] = []
		_configure_controller_focus.call_deferred()
		return
	var buttons: Array[Button] = []
	for value in values:
		if value is Dictionary:
			var card := _make_milestone_card(value, current, unit)
			container.add_child(card)
			if card is Button:
				buttons.append(card as Button)
	_road_focus_buttons[unit.to_lower()] = buttons
	_configure_controller_focus.call_deferred()


func _make_milestone_card(milestone: Dictionary, current: int,
		unit: String) -> Control:
	var threshold := int(milestone.get("threshold", 0))
	var claimed := bool(milestone.get("claimed", false))
	var reached := current >= threshold
	var rarity := str(milestone.get("rarity", "standard"))
	var role := "green" if claimed else ("gold" if reached else _rarity_role(rarity))
	var item_id := SupabaseCosmeticRegistry.sanitize_item_id(
		str(milestone.get("item_id", "")))
	var border := Color(OneGunUI.color(role), 0.62)
	var base_style := OneGunUI.style_box(Color(0.008, 0.021, 0.052, 0.96),
		border, 14, 2 if reached else 1, 3, 14.0)
	var shell: Control
	if item_id != "":
		var button := Button.new()
		button.name = "CosmeticMilestone%s%d" % [unit.capitalize(), threshold]
		button.custom_minimum_size = Vector2(235.0, 280.0)
		button.focus_mode = Control.FOCUS_ALL
		button.text = ""
		button.tooltip_text = "Preview %s" % str(milestone.get(
			"display_name", "cosmetic reward"))
		button.add_theme_stylebox_override("normal", base_style)
		button.add_theme_stylebox_override("hover", OneGunUI.style_box(
			Color(0.016, 0.042, 0.090, 0.98), border.lightened(0.16),
			14, 2, 5, 14.0))
		button.add_theme_stylebox_override("pressed", OneGunUI.style_box(
			Color(0.004, 0.012, 0.030, 0.98), border, 14, 2, 0, 14.0))
		button.add_theme_stylebox_override("focus", OneGunUI.focus_ring(base_style))
		button.mouse_entered.connect(func() -> void: AudioManager.play_hover())
		button.pressed.connect(_open_cosmetic_preview.bind(
			milestone.duplicate(true), unit))
		shell = button
	else:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(235.0, 280.0)
		panel.add_theme_stylebox_override("panel", base_style)
		shell = panel
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if shell is Button:
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.offset_left = 14.0
		column.offset_top = 14.0
		column.offset_right = -14.0
		column.offset_bottom = -14.0
	shell.add_child(column)
	var marker := OneGunUI.make_heading("✓" if claimed else ("★" if reached else "◇"),
		42, role)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(marker)
	var threshold_label := OneGunUI.make_heading("%s %d" % [unit, threshold],
		OneGunUI.TEXT_L, role)
	threshold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(threshold_label)
	var name := OneGunUI.make_label(str(milestone.get("display_name", "REWARD")).to_upper(),
		OneGunUI.TEXT_M, "text_bright", true)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(name)
	var reward := "%d GUN TOKENS" % int(milestone.get("gun_tokens", 0)) \
		if int(milestone.get("gun_tokens", 0)) > 0 else "PERMANENT COSMETIC • VIEW"
	var reward_label := OneGunUI.make_label(reward, OneGunUI.TEXT_S, "cyan", true)
	reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(reward_label)
	var status := "CLAIMED" if claimed else (
		"BANK NEXT MATCH" if reached else "%d TO GO" % maxi(threshold - current, 0))
	var status_label := OneGunUI.make_label(status, OneGunUI.TEXT_S,
		"green" if claimed else "muted", true)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status_label)
	_set_descendants_mouse_filter_ignore(column)
	return shell


func _set_descendants_mouse_filter_ignore(root: Control) -> void:
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in root.get_children():
		if child is Control:
			_set_descendants_mouse_filter_ignore(child as Control)


func _open_cosmetic_preview(milestone: Dictionary, unit: String) -> void:
	var item_id := SupabaseCosmeticRegistry.sanitize_item_id(
		str(milestone.get("item_id", "")))
	if item_id == "":
		return
	_close_cosmetic_preview(false)
	_preview_return_focus = get_viewport().gui_get_focus_owner()
	_cosmetic_preview = COSMETIC_PREVIEW_SCRIPT.new()
	_cosmetic_preview.configure(item_id,
		str(milestone.get("display_name",
			SupabaseCosmeticRegistry.display_name_fallback(item_id))),
		"%s %d  •  %s" % [unit, int(milestone.get("threshold", 0)),
			str(milestone.get("rarity", "standard"))],
		str(milestone.get("rarity", "standard")))
	_cosmetic_preview.close_requested.connect(_close_cosmetic_preview)
	_canvas.add_child(_cosmetic_preview)


func _close_cosmetic_preview(restore_focus := true) -> void:
	if _cosmetic_preview != null and is_instance_valid(_cosmetic_preview):
		_cosmetic_preview.queue_free()
	_cosmetic_preview = null
	if restore_focus and _preview_return_focus != null \
			and is_instance_valid(_preview_return_focus):
		_preview_return_focus.grab_focus.call_deferred()
	_preview_return_focus = null


func _configure_controller_focus() -> void:
	if _tabs == null or not is_instance_valid(_tabs):
		return
	var tab_buttons = _tabs.get("_buttons")
	if not tab_buttons is Array:
		return
	var back_target: Control = null
	for road_index in 2:
		var key := "level" if road_index == 0 else "trophy"
		var buttons: Array = _road_focus_buttons.get(key, [])
		if buttons.is_empty() or road_index >= tab_buttons.size():
			continue
		var tab := tab_buttons[road_index] as Control
		var first := buttons[0] as Control
		tab.focus_neighbor_bottom = tab.get_path_to(first)
		first.focus_neighbor_top = first.get_path_to(tab)
		for index in buttons.size():
			var current := buttons[index] as Control
			if road_index == _tabs.selected and back_target == null:
				back_target = current
			if index > 0:
				current.focus_neighbor_left = current.get_path_to(
					buttons[index - 1] as Control)
			if index + 1 < buttons.size():
				current.focus_neighbor_right = current.get_path_to(
					buttons[index + 1] as Control)
			if _close_button != null:
				current.focus_neighbor_bottom = current.get_path_to(_close_button)
	if _close_button != null and not tab_buttons.is_empty():
		if back_target == null:
			back_target = tab_buttons[clampi(_tabs.selected, 0,
				tab_buttons.size() - 1)] as Control
		_close_button.focus_neighbor_top = _close_button.get_path_to(back_target)
		for tab_value in tab_buttons:
			var tab := tab_value as Control
			if tab.focus_neighbor_bottom.is_empty():
				tab.focus_neighbor_bottom = tab.get_path_to(_close_button)


func _focus_first_tab() -> void:
	if _tabs == null:
		return
	var buttons = _tabs.get("_buttons")
	if buttons is Array and not buttons.is_empty():
		(buttons[0] as Control).grab_focus()


func _make_empty_road_card(unit: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560.0, 240.0)
	panel.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(0.008, 0.018, 0.042), Color(OneGunUI.color("border"), 0.5), 14, 1, 0, 18.0))
	var label := OneGunUI.make_label(
		"SIGN IN TO LOAD THE %s ROAD" % unit, OneGunUI.TEXT_L, "muted", true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


func _rarity_role(rarity: String) -> String:
	match rarity.to_lower():
		"legendary": return "gold"
		"epic": return "purple"
		"rare": return "cyan"
		"uncommon": return "green"
	return "muted"


func _short_date(value: String) -> String:
	return value.substr(0, 10) if value.length() >= 10 else "—"


func _show_page(index: int) -> void:
	for page_index in _pages.size():
		_pages[page_index].visible = page_index == index


func _on_progression_updated(_snapshot: Dictionary) -> void:
	_refresh()


func _on_login_state_changed(_state: String) -> void:
	_refresh()


func _apply_responsive_layout() -> void:
	if _canvas == null:
		return
	var available := size
	if available.x <= 0.0 or available.y <= 0.0:
		available = get_viewport_rect().size
	var factor := minf(available.x / BASE_SIZE.x, available.y / BASE_SIZE.y)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (available - BASE_SIZE * factor) * 0.5


func _close() -> void:
	if _cosmetic_preview != null:
		_close_cosmetic_preview()
		return
	closed.emit()
	queue_free()
