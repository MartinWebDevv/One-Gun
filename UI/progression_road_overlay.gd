class_name ProgressionRoadOverlay
extends Control

signal closed

const BASE_SIZE := Vector2(1600.0, 900.0)
const HUB_BACKDROP_SCRIPT = preload("res://UI/components/menu_hub_backdrop.gd")
const PROFILE_BACKDROP = preload("res://UI/assets/menu_hubs/profile_backdrop.png")
const ProgressionCaptureFixture = preload("res://UI/progression_capture_fixture.gd")

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

	var kicker := OneGunUI.make_label("ONE GUN  //  SEASON COMMAND",
		OneGunUI.TEXT_S, "cyan", true)
	kicker.position = Vector2(64.0, 20.0)
	kicker.size = Vector2(720.0, 24.0)
	_canvas.add_child(kicker)
	var title := OneGunUI.make_heading("PROGRESSION ROADS", 42, "text_bright")
	title.position = Vector2(64.0, 44.0)
	title.size = Vector2(900.0, 52.0)
	_canvas.add_child(title)
	var subtitle := OneGunUI.make_label(
		"LEVEL UP  •  CLAIM PERMANENT PRIZES  •  BUILD YOUR LEGACY",
		OneGunUI.TEXT_M, "muted", true)
	subtitle.position = Vector2(66.0, 96.0)
	subtitle.size = Vector2(1000.0, 24.0)
	_canvas.add_child(subtitle)
	var close := OneGunButton.new()
	close.text = "BACK TO HOME"
	close.variant = "red"
	close.position = Vector2(1342.0, 42.0)
	close.size = Vector2(194.0, 54.0)
	close.pressed.connect(_close)
	_canvas.add_child(close)

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
	body.size = Vector2(1472.0, 542.0)
	_canvas.add_child(body)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	body.get_content().add_child(column)
	var tabs := OneGunTabBar.new()
	tabs.tabs = PackedStringArray(["LEVEL ROAD", "TROPHY ROAD", "SEASON RULES"])
	tabs.tab_selected.connect(_show_page)
	column.add_child(tabs)
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
	_feedback.position = Vector2(64.0, 836.0)
	_feedback.size = Vector2(1472.0, 34.0)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_canvas.add_child(_feedback)
	_show_page(0)


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
		return
	for value in values:
		if value is Dictionary:
			container.add_child(_make_milestone_card(value, current, unit))


func _make_milestone_card(milestone: Dictionary, current: int,
		unit: String) -> PanelContainer:
	var threshold := int(milestone.get("threshold", 0))
	var claimed := bool(milestone.get("claimed", false))
	var reached := current >= threshold
	var rarity := str(milestone.get("rarity", "standard"))
	var role := "green" if claimed else ("gold" if reached else _rarity_role(rarity))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(235.0, 280.0)
	panel.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(0.008, 0.021, 0.052, 0.96), Color(OneGunUI.color(role), 0.62),
		14, 2 if reached else 1, 3, 14.0))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
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
		if int(milestone.get("gun_tokens", 0)) > 0 else "PERMANENT COSMETIC"
	var reward_label := OneGunUI.make_label(reward, OneGunUI.TEXT_S, "cyan", true)
	reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(reward_label)
	var status := "CLAIMED" if claimed else (
		"BANK NEXT MATCH" if reached else "%d TO GO" % maxi(threshold - current, 0))
	var status_label := OneGunUI.make_label(status, OneGunUI.TEXT_S,
		"green" if claimed else "muted", true)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status_label)
	return panel


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
	closed.emit()
	queue_free()
