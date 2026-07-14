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
var _scoreboard_overlay: Control
var _scoreboard_content: VBoxContainer
var _pulse_tween: Tween = null
var _notification_tween: Tween = null
var _tab_open := false

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# -- Top-center: Round / Set counter --
	var center_container = VBoxContainer.new()
	center_container.anchor_left   = 0.5
	center_container.anchor_right  = 0.5
	center_container.anchor_top    = 0.0
	center_container.anchor_bottom = 0.0
	center_container.offset_left   = -250
	center_container.offset_right  = 250
	center_container.offset_top    = 10
	center_container.offset_bottom = 80
	center_container.alignment     = BoxContainer.ALIGNMENT_CENTER
	center_container.add_theme_constant_override("separation", 2)
	add_child(center_container)

	_round_label = Label.new()
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.add_theme_font_size_override("font_size", 22)
	_round_label.modulate = Color(1.0, 1.0, 1.0, 0.95)
	center_container.add_child(_round_label)

	_set_label = Label.new()
	_set_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_set_label.add_theme_font_size_override("font_size", 14)
	_set_label.modulate = Color(0.75, 0.75, 0.75, 0.9)
	_set_label.visible = false
	center_container.add_child(_set_label)

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

func _build_scoreboard_overlay():
	_scoreboard_overlay = Control.new()
	_scoreboard_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scoreboard_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard_overlay.visible = false
	add_child(_scoreboard_overlay)

	# Semi-transparent dark background panel
	var bg = ColorRect.new()
	bg.anchor_left   = 0.5
	bg.anchor_right  = 0.5
	bg.anchor_top    = 0.5
	bg.anchor_bottom = 0.5
	bg.offset_left   = -340
	bg.offset_right  = 340
	bg.offset_top    = -260
	bg.offset_bottom = 260
	bg.color = Color(0.05, 0.05, 0.08, 0.88)
	_scoreboard_overlay.add_child(bg)

	# Title
	var title = Label.new()
	title.text = "SCOREBOARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left   = 0.5
	title.anchor_right  = 0.5
	title.anchor_top    = 0.5
	title.anchor_bottom = 0.5
	title.offset_left   = -320
	title.offset_right  = 320
	title.offset_top    = -248
	title.offset_bottom = -210
	title.add_theme_font_size_override("font_size", 18)
	title.modulate = Color(0.9, 0.85, 0.6)
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
	label.modulate = Color(0.6, 0.7, 0.9)
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

	var data = round_manager.get_scoreboard_data()
	for i in data.size():
		var entry = data[i]
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

		_scoreboard_content.add_child(row)

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
