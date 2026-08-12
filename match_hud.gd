extends Control

# ============================================================
# MatchHUD — in-match display.
#
# Layout:
#   Top-center:   Round / Set counter (persistent, prominent)
#   Top-center:   Notifications fade in/out below round counter
#   Top-left:     Remaining players count
#   Tab overlay:  Full scoreboard (doesn't pause game)
# ============================================================

@export var is_second_screen := false

# Column widths — shared between header and data rows to guarantee alignment.
# Total: 170+58+70+58+66+74+74+60 = 630px, fits inside -330 to 330 (660px panel).
const COL_PLAYER  = 170
const COL_SETS    = 58
const COL_ROUNDS  = 70
const COL_KILLS   = 58
const COL_DEATHS  = 66
const COL_DISARMS = 74
const COL_PICKUPS = 74
const COL_MELEE   = 60

var _round_label: Label
var _set_label: Label
var _remaining_label: Label
var _notification_label: Label
var _timer_label: Label
var _fire_warning_panel: PanelContainer
var _fire_warning_label: Label
var _fire_warning_active := false
var _scoreboard_overlay: Control
var _scoreboard_content: VBoxContainer
var _pulse_tween: Tween = null
var _notification_tween: Tween = null
var _tab_open := false

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not NetworkManager.is_online():
		if GameConfig.split_screen_enabled:
			anchor_left = 0.5 if is_second_screen else 0.0
			anchor_right = 1.0 if is_second_screen else 0.5
		elif is_second_screen:
			visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# -- Top-center: Round / Set counter on a rounded "plate" --
	var plate = PanelContainer.new()
	plate.anchor_left   = 0.5
	plate.anchor_right  = 0.5
	plate.anchor_top    = 0.0
	plate.anchor_bottom = 0.0
	plate.offset_left   = -160
	plate.offset_right  = 160
	plate.offset_top    = 8
	plate.offset_bottom = 8   # grows to fit content
	var plate_style = ThemeManager.panel(Color(0.06, 0.07, 0.12, 0.85), ThemeManager.ACCENT_GOLD, 12, 2)
	plate_style.content_margin_left = 22
	plate_style.content_margin_right = 22
	plate_style.content_margin_top = 6
	plate_style.content_margin_bottom = 8
	plate.add_theme_stylebox_override("panel", plate_style)
	add_child(plate)

	var center_container = VBoxContainer.new()
	center_container.alignment = BoxContainer.ALIGNMENT_CENTER
	center_container.add_theme_constant_override("separation", 0)
	plate.add_child(center_container)

	_round_label = Label.new()
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.add_theme_font_size_override("font_size", 20)
	_round_label.add_theme_color_override("font_color", ThemeManager.ACCENT_GOLD)
	ThemeManager.embolden(_round_label)
	center_container.add_child(_round_label)

	_set_label = Label.new()
	_set_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_set_label.add_theme_font_size_override("font_size", 12)
	_set_label.modulate = Color(0.75, 0.78, 0.9, 0.9)
	_set_label.visible = false
	center_container.add_child(_set_label)

	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 16)
	_timer_label.add_theme_color_override("font_color", ThemeManager.TEXT_WHITE)
	ThemeManager.embolden(_timer_label)
	center_container.add_child(_timer_label)
	_build_fire_warning()

	# Notification label — sits below the round/set counter, center screen
	_notification_label = Label.new()
	_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_label.anchor_left   = 0.5
	_notification_label.anchor_right  = 0.5
	_notification_label.anchor_top    = 0.0
	_notification_label.anchor_bottom = 0.0
	_notification_label.offset_left   = -320
	_notification_label.offset_right  = 320
	_notification_label.offset_top    = 120
	_notification_label.offset_bottom = 160
	_notification_label.add_theme_font_size_override("font_size", 20)
	_notification_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(_notification_label)

	# -- Top-left: Remaining players --
	_remaining_label = Label.new()
	_remaining_label.anchor_left   = 0.0
	_remaining_label.anchor_right  = 0.0
	_remaining_label.anchor_top    = 0.0
	_remaining_label.anchor_bottom = 0.0
	_remaining_label.offset_left   = 12
	_remaining_label.offset_top    = 12
	_remaining_label.offset_right  = 280
	_remaining_label.offset_bottom = 60
	_remaining_label.add_theme_font_size_override("font_size", 28)
	_remaining_label.modulate = Color.WHITE
	add_child(_remaining_label)

	# -- Tab scoreboard overlay (hidden by default) --
	_build_scoreboard_overlay()

	GameEvents.hud_notification.connect(_on_hud_notification)
	GameEvents.gun_picked_up.connect(_on_gun_picked_up)
	GameEvents.gun_dropped.connect(_on_gun_dropped)

func update_round_timer(text: String, overtime: bool = false) -> void:
	if _timer_label == null:
		return
	_timer_label.text = text
	_timer_label.visible = text != ""
	_timer_label.add_theme_color_override(
		"font_color", ThemeManager.DANGER if overtime else ThemeManager.TEXT_WHITE)

func _build_fire_warning() -> void:
	_fire_warning_panel = PanelContainer.new()
	_fire_warning_panel.name = "FireExposureWarning"
	_fire_warning_panel.anchor_left = 0.5
	_fire_warning_panel.anchor_right = 0.5
	_fire_warning_panel.offset_left = -190.0
	_fire_warning_panel.offset_right = 190.0
	_fire_warning_panel.offset_top = 164.0
	_fire_warning_panel.offset_bottom = 226.0
	_fire_warning_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var warning_style := ThemeManager.panel(
		Color(0.18, 0.015, 0.005, 0.94), Color(1.0, 0.22, 0.02), 12, 3)
	warning_style.content_margin_left = 18.0
	warning_style.content_margin_right = 18.0
	warning_style.content_margin_top = 7.0
	warning_style.content_margin_bottom = 7.0
	_fire_warning_panel.add_theme_stylebox_override("panel", warning_style)
	_fire_warning_panel.visible = false
	add_child(_fire_warning_panel)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	_fire_warning_panel.add_child(column)
	_fire_warning_label = Label.new()
	_fire_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fire_warning_label.add_theme_font_size_override("font_size", 28)
	_fire_warning_label.add_theme_color_override("font_color", Color(1.0, 0.32, 0.05))
	ThemeManager.embolden(_fire_warning_label)
	column.add_child(_fire_warning_label)
	var instruction := Label.new()
	instruction.text = "GET BACK INSIDE THE SAFE AREA"
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 11)
	instruction.add_theme_color_override("font_color", Color(1.0, 0.82, 0.68))
	ThemeManager.embolden(instruction)
	column.add_child(instruction)

func update_fire_warning(state: Dictionary) -> void:
	if _fire_warning_panel == null:
		return
	var active := bool(state.get("active", false))
	_fire_warning_panel.visible = active
	_fire_warning_panel.set_meta("fire_warning_active", active)
	if active:
		var remaining := maxf(float(state.get("remaining", 0.0)), 0.0)
		_fire_warning_label.text = "IN FIRE  -  %.1fs" % remaining
		if not _fire_warning_active:
			ThemeManager.punch(_fire_warning_panel, 1.18, 0.2)
	_fire_warning_active = active

func _build_scoreboard_overlay():
	_scoreboard_overlay = Control.new()
	_scoreboard_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scoreboard_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard_overlay.visible = false
	add_child(_scoreboard_overlay)

	# Kit panel background (rounded, gold border)
	var bg = Panel.new()
	bg.anchor_left   = 0.5
	bg.anchor_right  = 0.5
	bg.anchor_top    = 0.5
	bg.anchor_bottom = 0.5
	bg.offset_left   = -340
	bg.offset_right  = 340
	bg.offset_top    = -260
	bg.offset_bottom = 260
	bg.add_theme_stylebox_override("panel",
		ThemeManager.panel(Color(0.04, 0.05, 0.09, 0.92), ThemeManager.ACCENT_GOLD, 14, 2))
	_scoreboard_overlay.add_child(bg)

	# Title
	var title = ThemeManager.heading("SCOREBOARD", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left   = 0.5
	title.anchor_right  = 0.5
	title.anchor_top    = 0.5
	title.anchor_bottom = 0.5
	title.offset_left   = -320
	title.offset_right  = 320
	title.offset_top    = -248
	title.offset_bottom = -210
	_scoreboard_overlay.add_child(title)

	# Column headers — anchored to match bg panel left edge
	var headers = HBoxContainer.new()
	headers.anchor_left   = 0.5
	headers.anchor_right  = 0.5
	headers.anchor_top    = 0.5
	headers.anchor_bottom = 0.5
	headers.offset_left   = -330
	headers.offset_right  = 330
	headers.offset_top    = -210
	headers.offset_bottom = -184
	headers.add_theme_constant_override("separation", 0)
	_scoreboard_overlay.add_child(headers)
	_add_header_cell(headers, "PLAYER",  COL_PLAYER)
	_add_header_cell(headers, "SETS",    COL_SETS)
	_add_header_cell(headers, "ROUNDS",  COL_ROUNDS)
	_add_header_cell(headers, "KILLS",   COL_KILLS)
	_add_header_cell(headers, "DEATHS",  COL_DEATHS)
	_add_header_cell(headers, "DISARMS", COL_DISARMS)
	_add_header_cell(headers, "PICKUPS", COL_PICKUPS)
	_add_header_cell(headers, "MELEE",   COL_MELEE)

	# Separator
	var sep = HSeparator.new()
	sep.anchor_left   = 0.5
	sep.anchor_right  = 0.5
	sep.anchor_top    = 0.5
	sep.anchor_bottom = 0.5
	sep.offset_left   = -330
	sep.offset_right  = 330
	sep.offset_top    = -184
	sep.offset_bottom = -178
	_scoreboard_overlay.add_child(sep)

	# Content rows
	_scoreboard_content = VBoxContainer.new()
	_scoreboard_content.anchor_left   = 0.5
	_scoreboard_content.anchor_right  = 0.5
	_scoreboard_content.anchor_top    = 0.5
	_scoreboard_content.anchor_bottom = 0.5
	_scoreboard_content.offset_left   = -330
	_scoreboard_content.offset_right  = 330
	_scoreboard_content.offset_top    = -178
	_scoreboard_content.offset_bottom = 240
	_scoreboard_content.add_theme_constant_override("separation", 4)
	_scoreboard_overlay.add_child(_scoreboard_content)

	# Tab hint at bottom
	var hint = Label.new()
	hint.text = "[TAB] Close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_left   = 0.5
	hint.anchor_right  = 0.5
	hint.anchor_top    = 0.5
	hint.anchor_bottom = 0.5
	hint.offset_left   = -320
	hint.offset_right  = 320
	hint.offset_top    = 240
	hint.offset_bottom = 260
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.5, 0.5, 0.5)
	_scoreboard_overlay.add_child(hint)

func _add_header_cell(parent: HBoxContainer, text: String, width: int):
	var label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", ThemeManager.ACCENT_GOLD)
	ThemeManager.embolden(label)
	parent.add_child(label)

func _process(_delta):
	# Hold Tab to show scoreboard, release to hide.
	var tab_held = Input.is_key_pressed(KEY_TAB) or Input.is_action_pressed("ui_focus_next")
	if tab_held and not _tab_open:
		_tab_open = true
		_refresh_scoreboard()
		_scoreboard_overlay.visible = true
	elif not tab_held and _tab_open:
		_tab_open = false
		_scoreboard_overlay.visible = false

func _input(event):
	# Consume Tab input so it doesn't trigger other UI actions.
	if event is InputEventKey and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()

func _refresh_scoreboard():
	for child in _scoreboard_content.get_children():
		child.queue_free()

	var round_manager = get_node_or_null("../../RoundManager")
	if round_manager == null or not round_manager.has_method("get_scoreboard_data"):
		return

	# Online: highlight the row belonging to this machine's player.
	var local_actor_id := -1
	if NetworkManager.is_online():
		var lp = NetworkManager.find_net_player(NetworkManager.local_id())
		if lp != null:
			local_actor_id = int(lp.get("actor_id"))

	var data = round_manager.get_scoreboard_data()
	var current_team := -999
	for i in data.size():
		var entry = data[i]
		var team_id := int(entry.get("team_id", -1))
		if GameConfig.teams_enabled and team_id != current_team:
			current_team = team_id
			var team_heading := Label.new()
			team_heading.text = "TEAM %d   •   %d SETS   •   %d ROUNDS" % [
				team_id + 1, int(entry.get("sets", 0)), int(entry.get("rounds", 0))]
			team_heading.add_theme_font_size_override("font_size", 15)
			team_heading.add_theme_color_override("font_color", [Color(0.25, 0.7, 1.0), Color(1.0, 0.3, 0.3), Color(0.35, 0.9, 0.45), Color(1.0, 0.75, 0.2)][clampi(team_id, 0, 3)])
			_scoreboard_content.add_child(team_heading)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)

		var is_alive = entry["alive"]
		var row_color = Color.WHITE if is_alive else Color(0.5, 0.5, 0.5)
		var rank_colors = [Color(1.0, 0.84, 0.0), Color(0.75, 0.75, 0.75), Color(0.8, 0.5, 0.2)]
		if i < rank_colors.size():
			row_color = rank_colors[i] if is_alive else Color(0.4, 0.4, 0.4)

		_add_row_cell(row, entry["name"],          COL_PLAYER,  row_color, true)
		_add_row_cell(row, str(entry["sets"]),     COL_SETS,    row_color)
		_add_row_cell(row, str(entry["rounds"]),   COL_ROUNDS,  row_color)
		_add_row_cell(row, str(entry["kills"]),    COL_KILLS,   row_color)
		_add_row_cell(row, str(entry["deaths"]),   COL_DEATHS,  row_color)
		_add_row_cell(row, str(entry["disarms"]),  COL_DISARMS, row_color)
		_add_row_cell(row, str(entry["pickups"]),  COL_PICKUPS, row_color)
		_add_row_cell(row, str(entry["melee"]),    COL_MELEE,   row_color)

		# Zebra striping + gold left edge on your own row.
		var row_panel = PanelContainer.new()
		var is_you: bool = local_actor_id >= 0 and int(entry.get("actor_id", -1)) == local_actor_id
		var zebra_bg := Color(1, 1, 1, 0.04) if i % 2 == 0 else Color(0, 0, 0, 0.0)
		var row_style = ThemeManager.panel(zebra_bg, Color.TRANSPARENT, 4, 0)
		row_style.shadow_size = 0
		row_style.content_margin_left = 6
		row_style.content_margin_right = 6
		row_style.content_margin_top = 2
		row_style.content_margin_bottom = 2
		if is_you:
			row_style.border_width_left = 3
			row_style.border_color = ThemeManager.ACCENT_GOLD
			row_style.bg_color = Color(1.0, 0.718, 0.0, 0.08)
		row_panel.add_theme_stylebox_override("panel", row_style)
		row_panel.add_child(row)
		_scoreboard_content.add_child(row_panel)

func _add_row_cell(parent: HBoxContainer, text: String, width: int, color: Color, bold: bool = false):
	var label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.add_theme_font_size_override("font_size", 13 if bold else 12)
	label.modulate = color
	parent.add_child(label)

func update_match_state(round_num: int, set_num: int, alive: int, _total: int, _score_data: Array = []):
	if _round_label == null or _remaining_label == null:
		return
	if NetworkManager.is_online():
		_round_label.text = "ROUND " + str(round_num) + "   •   FIRST TO " + str(int(GameConfig.rounds_per_set))
	else:
		_round_label.text = "ROUND  " + str(round_num) + "  /  " + str(int(GameConfig.rounds_per_set))

	if GameConfig.sets_per_match > 1:
		_set_label.text = "Set " + str(set_num) + " of " + str(int(GameConfig.sets_per_match))
		_set_label.visible = true
	else:
		_set_label.visible = false

	# -- Remaining players --
	# Normal play: top-left, small and unobtrusive.
	# Final 3 / 2 / 1: moves to top-center, larger, pulses for final 2 and 1.
	var remaining_text: String
	var remaining_size: int
	var do_pulse := false
	var is_dramatic := alive <= 3 and alive > 0

	if alive <= 0:
		remaining_text = ""
		remaining_size = 28
	elif alive == 1:
		remaining_text = "LAST ONE STANDING"
		remaining_size = 30
		do_pulse = true
	elif alive == 2:
		remaining_text = "FINAL TWO"
		remaining_size = 36
		do_pulse = true
	elif alive == 3:
		remaining_text = "FINAL THREE"
		remaining_size = 28
	elif alive <= 5:
		remaining_text = str(alive) + " REMAIN"
		remaining_size = 18
	else:
		remaining_text = str(alive) + " PLAYERS REMAIN"
		remaining_size = 16

	_remaining_label.text = remaining_text
	_remaining_label.add_theme_font_size_override("font_size", remaining_size)
	_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if is_dramatic else HORIZONTAL_ALIGNMENT_LEFT

	# Reposition: dramatic = top-center below round counter, normal = top-left
	if is_dramatic:
		_remaining_label.anchor_left   = 0.5
		_remaining_label.anchor_right  = 0.5
		_remaining_label.anchor_top    = 0.0
		_remaining_label.anchor_bottom = 0.0
		_remaining_label.offset_left   = -300
		_remaining_label.offset_right  = 300
		_remaining_label.offset_top    = 70
		_remaining_label.offset_bottom = 120
	else:
		_remaining_label.anchor_left   = 0.0
		_remaining_label.anchor_right  = 0.0
		_remaining_label.anchor_top    = 0.0
		_remaining_label.anchor_bottom = 0.0
		_remaining_label.offset_left   = 12
		_remaining_label.offset_top    = 12
		_remaining_label.offset_right  = 280
		_remaining_label.offset_bottom = 40

	# Pulse for final two / last one standing
	if do_pulse and (_pulse_tween == null or not _pulse_tween.is_valid()):
		_pulse_tween = create_tween().set_loops()
		_pulse_tween.tween_property(_remaining_label, "modulate:a", 0.35, 0.7)
		_pulse_tween.tween_property(_remaining_label, "modulate:a", 1.0, 0.7)
	elif not do_pulse and _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
		_pulse_tween = null
		_remaining_label.modulate.a = 1.0

func _on_hud_notification(message: String):
	_show_notification(message, Color.WHITE)

func _on_gun_picked_up(player_name: String):
	_show_notification(player_name + " picked up the gun!", Color(1.0, 0.85, 0.3))

func _on_gun_dropped():
	_show_notification("THE GUN IS LOOSE!", Color(1.0, 0.5, 0.2))

func _show_notification(message: String, color: Color):
	if _notification_tween != null and _notification_tween.is_valid():
		_notification_tween.kill()

	_notification_label.text = message
	_notification_label.modulate = Color(color.r, color.g, color.b, 0.0)

	_notification_tween = create_tween()
	_notification_tween.tween_property(_notification_label, "modulate:a", 1.0, 0.2)
	_notification_tween.tween_interval(2.5)
	_notification_tween.tween_property(_notification_label, "modulate:a", 0.0, 0.4)
	ThemeManager.punch(_notification_label, 1.2)
