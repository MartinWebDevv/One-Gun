class_name OneGunArenaMatchboard
extends Control

# Lightweight, glanceable TAB overlay. The match remains live underneath, so
# this screen favors current competition over end-of-match detail.

const CabinetScript = preload("res://UI/components/one_gun_cabinet.gd")

const COL_RANK := 78.0
const COL_PLAYER := 310.0
const COL_ROUNDS := 210.0
const COL_KILLS := 96.0
const COL_DISARMS := 112.0
const COL_STATUS := 142.0
const TABLE_WIDTH := COL_RANK + COL_PLAYER + COL_ROUNDS + COL_KILLS 	+ COL_DISARMS + COL_STATUS
const ROW_HEIGHT := 50.0

var _cabinet: PanelContainer
var _rows: VBoxContainer
var _status_badge: PanelContainer
var _status_badge_label: Label
var _mode_label: Label
var _map_label: Label
var _round_label: Label
var _timer_label: Label
var _open_tween: Tween
var _teams_enabled := false


func _ready() -> void:
	name = "ArenaMatchboardOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_interface()
	visible = false


func present(data: Array, local_actor_id: int, context: Dictionary) -> void:
	var opening := not visible
	_update_context(context)
	_populate_rows(data, local_actor_id, int(context.get(
		"rounds_to_win", 3)))
	visible = true
	if opening:
		_animate_open.call_deferred()


func dismiss() -> void:
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	_open_tween = null
	visible = false


func _build_interface() -> void:
	var scrim := ColorRect.new()
	scrim.name = "MatchboardScrim"
	scrim.color = Color(0.002, 0.005, 0.014, 0.72)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	_add_rail(0.105, Color(OneGunUI.color("gold"), 0.18))
	_add_rail(0.895, Color(OneGunUI.color("cyan"), 0.13))

	var left_mark := OneGunUI.make_heading("OG", 42, "gold")
	left_mark.modulate.a = 0.17
	left_mark.anchor_left = 0.03
	left_mark.anchor_top = 0.5
	left_mark.anchor_bottom = 0.5
	left_mark.offset_top = -28.0
	left_mark.offset_bottom = 28.0
	add_child(left_mark)

	var right_mark := OneGunUI.make_heading("★", 42, "gold")
	right_mark.modulate.a = 0.17
	right_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_mark.anchor_left = 0.90
	right_mark.anchor_right = 0.97
	right_mark.anchor_top = 0.5
	right_mark.anchor_bottom = 0.5
	right_mark.offset_top = -28.0
	right_mark.offset_bottom = 28.0
	add_child(right_mark)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_cabinet = CabinetScript.new()
	_cabinet.name = "ArenaMatchboard"
	_cabinet.variant = CabinetScript.Variant.CABINET
	_cabinet.content_padding = 20
	_cabinet.custom_minimum_size = Vector2(TABLE_WIDTH + 52.0, 650.0)
	_cabinet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_cabinet)

	var column := VBoxContainer.new()
	column.name = "MatchboardLayout"
	column.add_theme_constant_override("separation", 10)
	_cabinet.get_content().add_child(column)

	_build_title_block(column)
	_build_context_rail(column)
	_build_table_header(column)

	var scroll := ScrollContainer.new()
	scroll.name = "MatchboardRowsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.name = "MatchboardRows"
	_rows.custom_minimum_size.x = TABLE_WIDTH
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	scroll.add_child(_rows)

	_build_footer(column)


func _build_title_block(parent: VBoxContainer) -> void:
	var top_line := HBoxContainer.new()
	top_line.alignment = BoxContainer.ALIGNMENT_END
	top_line.add_theme_constant_override("separation", 8)
	parent.add_child(top_line)

	_status_badge = PanelContainer.new()
	_status_badge.name = "MatchStatusBadge"
	_status_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_line.add_child(_status_badge)
	_status_badge_label = OneGunUI.make_label(
		"LIVE MATCH", OneGunUI.TEXT_XS, "gold", true)
	_status_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_badge_label.custom_minimum_size.x = 128.0
	_status_badge.add_child(_status_badge_label)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 14)
	parent.add_child(title_row)
	title_row.add_child(OneGunUI.make_heading("✦", 24, "gold"))
	var title := OneGunUI.make_heading("ARENA MATCHBOARD", 34, "text_bright")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_row.add_child(title)
	title_row.add_child(OneGunUI.make_heading("✦", 24, "gold"))


func _build_context_rail(parent: VBoxContainer) -> void:
	var rail := PanelContainer.new()
	rail.name = "MatchContextRail"
	var rail_style := OneGunUI.style_box(
		Color(OneGunUI.color("well"), 0.92),
		Color(OneGunUI.color("cyan"), 0.28),
		OneGunUI.RADIUS_SECTION, 1, 0, 8.0)
	rail.add_theme_stylebox_override("panel", rail_style)
	parent.add_child(rail)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	rail.add_child(row)
	_mode_label = _make_context_value("CLASSIC ONE GUN", 228.0, "gold")
	row.add_child(_mode_label)
	row.add_child(_make_divider())
	_map_label = _make_context_value("NEON CIRCUIT", 220.0, "cyan")
	row.add_child(_map_label)
	row.add_child(_make_divider())
	_round_label = _make_context_value("ROUND 1  •  FIRST TO 3", 255.0, "text")
	row.add_child(_round_label)
	row.add_child(_make_divider())
	_timer_label = _make_context_value("03:00", 100.0, "text_bright")
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_timer_label)


func _build_table_header(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "MatchboardTableHeader"
	var style := OneGunUI.style_box(
		Color(OneGunUI.color("gold_edge"), 0.34),
		Color(OneGunUI.color("gold"), 0.34),
		8, 1, 0, 0.0)
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	panel.add_child(row)
	_add_header_cell(row, "PLACE", COL_RANK)
	_add_header_cell(row, "COMPETITOR", COL_PLAYER, HORIZONTAL_ALIGNMENT_LEFT)
	_add_header_cell(row, "ROUND SCORE", COL_ROUNDS, HORIZONTAL_ALIGNMENT_LEFT)
	_add_header_cell(row, "KILLS", COL_KILLS)
	_add_header_cell(row, "DISARMS", COL_DISARMS)
	_add_header_cell(row, "STATUS", COL_STATUS)


func _build_footer(parent: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.name = "MatchboardFooter"
	parent.add_child(footer)
	var live := OneGunUI.make_label(
		"●  LIVE STANDINGS", OneGunUI.TEXT_XS, "green", true)
	live.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(live)
	var hint := OneGunUI.make_label(
		"HOLD TAB TO VIEW  •  RELEASE TO RETURN TO ARENA",
		OneGunUI.TEXT_XS, "muted", true)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(hint)


func _update_context(context: Dictionary) -> void:
	_teams_enabled = bool(context.get("teams_enabled", false))
	var official := bool(context.get("official", false))
	var match_kind := str(context.get(
		"match_kind", "OFFICIAL BETA" if official else "CUSTOM MATCH"))
	_status_badge_label.text = match_kind.to_upper()
	var badge_role := "gold" if official else ("cyan" if match_kind != "LOCAL MATCH" else "muted")
	_status_badge_label.add_theme_color_override(
		"font_color", OneGunUI.color(badge_role))
	var badge_color := OneGunUI.color(badge_role)
	_status_badge.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(badge_color, 0.12), Color(badge_color, 0.62),
		OneGunUI.RADIUS_CHIP, 1, 0, 6.0))

	_mode_label.text = str(context.get("mode_name", "CLASSIC ONE GUN")).to_upper()
	_map_label.text = str(context.get("map_name", "UNKNOWN ARENA")).to_upper()
	var round_number := maxi(int(context.get("round_number", 1)), 1)
	var rounds_to_win := maxi(int(context.get(
		"rounds_to_win", 3)), 1)
	_round_label.text = "ROUND %d  •  FIRST TO %d" % [round_number, rounds_to_win]
	var time_text := str(context.get("timer", ""))
	_timer_label.text = time_text if not time_text.is_empty() else "NO LIMIT"


func _populate_rows(data: Array, local_actor_id: int, rounds_to_win: int) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	var displayed := _select_visible_rows(data, local_actor_id)
	var current_team := -999
	for display_index in displayed.size():
		var row_data: Dictionary = displayed[display_index]
		var entry: Dictionary = row_data["entry"]
		var placement_index := int(row_data["placement_index"])
		var rank_jump := bool(row_data["rank_jump"])
		if rank_jump:
			_rows.add_child(_make_rank_jump_divider())
		var team_id := int(entry.get("team_id", -1))
		if _teams_enabled and team_id != current_team:
			current_team = team_id
			_rows.add_child(_make_team_heading(entry, team_id))
		var competitor_row := _make_competitor_row(
			entry, placement_index, display_index, local_actor_id, rounds_to_win)
		competitor_row.set_meta("rank_jump", rank_jump)
		_rows.add_child(competitor_row)


func _select_visible_rows(data: Array, local_actor_id: int) -> Array:
	var displayed: Array = []
	var leading_count := mini(data.size(), 5)
	for placement_index in leading_count:
		displayed.append({
			"entry": data[placement_index],
			"placement_index": placement_index,
			"rank_jump": false,
		})
	if data.size() <= 5:
		return displayed

	var viewer_index := -1
	for placement_index in data.size():
		var entry: Dictionary = data[placement_index]
		if int(entry.get("actor_id", -1)) == local_actor_id:
			viewer_index = placement_index
			break

	var final_index := 5
	if viewer_index >= 5:
		final_index = viewer_index
	displayed.append({
		"entry": data[final_index],
		"placement_index": final_index,
		"rank_jump": final_index > 5,
	})
	return displayed


func _make_rank_jump_divider() -> Control:
	var divider := HBoxContainer.new()
	divider.name = "ViewerPositionDivider"
	divider.custom_minimum_size = Vector2(TABLE_WIDTH, 16.0)
	divider.add_theme_constant_override("separation", 10)
	divider.add_child(_make_rank_jump_line())
	var label := OneGunUI.make_label(
		"YOUR POSITION", 9, "gold", true)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	divider.add_child(label)
	divider.add_child(_make_rank_jump_line())
	return divider


func _make_rank_jump_line() -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size.y = 1.0
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.color = Color(OneGunUI.color("gold"), 0.28)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _make_team_heading(entry: Dictionary, team_id: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(TABLE_WIDTH, 32.0)
	var team_color := _team_color(team_id)
	panel.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(team_color, 0.09), Color(team_color, 0.34), 7, 1, 0, 5.0))
	var heading := OneGunUI.make_label(
		"TEAM %d  //  %d SETS  •  %d ROUNDS" % [
			team_id + 1, int(entry.get("sets", 0)), int(entry.get("rounds", 0))],
		OneGunUI.TEXT_XS, "text", true)
	heading.add_theme_color_override("font_color", team_color)
	panel.add_child(heading)
	return panel


func _make_competitor_row(entry: Dictionary, placement_index: int,
		display_index: int, local_actor_id: int, rounds_to_win: int) -> Control:
	var actor_id := int(entry.get("actor_id", -1))
	var is_you := local_actor_id >= 0 and actor_id == local_actor_id
	var is_alive := bool(entry.get("alive", false))
	var has_gun := bool(entry.get("has_gun", false))
	var accent := _rank_color(placement_index)

	var panel := PanelContainer.new()
	panel.name = "MatchboardRow_%d" % actor_id
	panel.custom_minimum_size = Vector2(TABLE_WIDTH, ROW_HEIGHT)
	panel.set_meta("viewer_row", is_you)
	panel.set_meta("has_one_gun", has_gun)
	panel.set_meta("placement", placement_index + 1)
	var background := Color(0.055, 0.072, 0.13, 0.94) \
		if display_index % 2 == 0 else Color(0.035, 0.047, 0.09, 0.94)
	var border := Color(accent, 0.34) if placement_index < 3 else Color(OneGunUI.color("border"), 0.52)
	var border_width := 1
	if is_you:
		background = Color(OneGunUI.color("gold"), 0.105)
		border = OneGunUI.color("gold")
		border_width = 3
	var style := OneGunUI.style_box(background, border, 8, border_width, 0, 0.0)
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	panel.add_child(row)

	var rank_text := "★  %02d" % (placement_index + 1) \
		if placement_index == 0 else "%02d" % (placement_index + 1)
	_add_value_cell(row, rank_text, COL_RANK, accent, 17, true)
	row.add_child(_make_player_cell(entry, is_you, accent))
	row.add_child(_make_round_cell(
		int(entry.get("rounds", 0)), rounds_to_win))
	_add_value_cell(row, str(int(entry.get("kills", 0))),
		COL_KILLS, OneGunUI.color("text_bright"), 19, true)
	_add_value_cell(row, str(int(entry.get("disarms", 0))),
		COL_DISARMS, OneGunUI.color("text_bright"), 19, true)

	var status_text := "●  ALIVE" if is_alive else "×  OUT"
	var status_color := OneGunUI.color("green") if is_alive else OneGunUI.color("muted")
	_add_value_cell(row, status_text, COL_STATUS, status_color, 13, true)
	return panel


func _make_player_cell(entry: Dictionary, is_you: bool, accent: Color) -> Control:
	var cell := HBoxContainer.new()
	cell.custom_minimum_size.x = COL_PLAYER
	cell.add_theme_constant_override("separation", 9)

	var marker := ColorRect.new()
	marker.custom_minimum_size = Vector2(4.0, 34.0)
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	marker.color = accent
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(marker)

	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", -3)
	cell.add_child(copy)

	var player_name := OneGunUI.make_label(
		str(entry.get("name", "PLAYER")).to_upper(), 17,
		"text_bright" if bool(entry.get("alive", false)) else "muted", true)
	player_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(player_name)

	var tags: Array[String] = []
	if is_you:
		tags.append("YOU")
	if bool(entry.get("is_host", false)):
		tags.append("HOST")
	if bool(entry.get("has_gun", false)):
		tags.append("ONE GUN")
	if tags.is_empty():
		tags.append("ARENA COMPETITOR")
	var tag_role := "gold" if bool(entry.get("has_gun", false)) 		else ("cyan" if is_you else "muted")
	var meta := OneGunUI.make_label(
		"  •  ".join(tags), 10, tag_role, true)
	copy.add_child(meta)
	return cell


func _make_round_cell(rounds: int, rounds_to_win: int) -> Control:
	var cell := HBoxContainer.new()
	cell.name = "RoundScore"
	cell.custom_minimum_size.x = COL_ROUNDS
	cell.add_theme_constant_override("separation", 10)

	var score := OneGunUI.make_heading(
		"%d / %d" % [rounds, rounds_to_win], 20, "gold")
	score.custom_minimum_size.x = 66.0
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cell.add_child(score)

	var pip_text := ""
	if rounds_to_win <= 5:
		for pip_index in rounds_to_win:
			pip_text += "●" if pip_index < rounds else "○"
			if pip_index < rounds_to_win - 1:
				pip_text += " "
	else:
		pip_text = "FIRST TO %d" % rounds_to_win
	var pips := OneGunUI.make_label(
		pip_text, 15 if rounds_to_win <= 5 else 10, "gold", true)
	pips.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_child(pips)
	return cell


func _add_header_cell(parent: HBoxContainer, text: String, width: float,
		alignment := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var label := OneGunUI.make_label(text, 11, "gold", true)
	label.custom_minimum_size.x = width
	label.horizontal_alignment = alignment
	parent.add_child(label)


func _add_value_cell(parent: HBoxContainer, text: String, width: float,
		color: Color, size: int, bold := false) -> void:
	var label := OneGunUI.make_label(text, size, "text", bold)
	label.custom_minimum_size.x = width
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _make_context_value(text: String, width: float, role: String) -> Label:
	var label := OneGunUI.make_label(text, 12, role, true)
	label.custom_minimum_size.x = width
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _make_divider() -> ColorRect:
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(1.0, 20.0)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	divider.color = Color(OneGunUI.color("border"), 0.65)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider


func _add_rail(anchor_y: float, color: Color) -> void:
	var rail := ColorRect.new()
	rail.anchor_left = 0.0
	rail.anchor_right = 1.0
	rail.anchor_top = anchor_y
	rail.anchor_bottom = anchor_y
	rail.offset_bottom = 2.0
	rail.color = color
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rail)


func _animate_open() -> void:
	if not visible or _cabinet == null:
		return
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	var reduced_motion := false
	var player_prefs := get_node_or_null("/root/PlayerPrefs")
	if player_prefs != null:
		reduced_motion = bool(player_prefs.call("get_setting", "reduced_motion"))
	_cabinet.pivot_offset = _cabinet.size * 0.5
	if reduced_motion:
		_cabinet.modulate.a = 1.0
		_cabinet.scale = Vector2.ONE
		return
	_cabinet.modulate.a = 0.0
	_cabinet.scale = Vector2(0.985, 0.985)
	_open_tween = create_tween()
	_open_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_open_tween.set_parallel(true)
	_open_tween.tween_property(
		_cabinet, "modulate:a", 1.0, OneGunUI.TIME_PANEL)
	_open_tween.tween_property(
		_cabinet, "scale", Vector2.ONE, OneGunUI.TIME_PANEL
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _rank_color(index: int) -> Color:
	match index:
		0:
			return OneGunUI.color("gold")
		1:
			return Color(0.78, 0.84, 0.94)
		2:
			return Color(0.88, 0.48, 0.20)
	return OneGunUI.color("cyan").darkened(0.16)


func _team_color(team_id: int) -> Color:
	var colors := [
		Color(0.25, 0.70, 1.0),
		Color(1.0, 0.30, 0.30),
		Color(0.35, 0.90, 0.45),
		Color(1.0, 0.75, 0.20),
	]
	return colors[clampi(team_id, 0, colors.size() - 1)]
