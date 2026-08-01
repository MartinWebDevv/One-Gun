class_name OneGunRosterRow
extends PanelContainer

# Reusable roster row for local and online lobbies (packet Phase 1/2/5).
# Shows a human (with optional HOST crown, YOU tag, ready check/X), a bot
# (with difficulty), or an empty numbered slot. Runtime data only — callers
# must never feed it concept-art names.

enum ReadyState { NONE, NOT_READY, READY }

var _icon: OneGunIcon
var _name_label: Label
var _badge_box: HBoxContainer
var _trailing_box: HBoxContainer
var _idle_style: StyleBoxFlat
var _name_edit_callback := Callable()


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 52.0)
	focus_mode = Control.FOCUS_ALL
	_idle_style = OneGunUI.style_box(
		OneGunUI.color("well"), OneGunUI.color("well").darkened(0.35),
		OneGunUI.RADIUS_INPUT, 1, 0, 0.0)
	_idle_style.content_margin_left = OneGunUI.SPACE_M
	_idle_style.content_margin_right = OneGunUI.SPACE_M
	_idle_style.content_margin_top = OneGunUI.SPACE_S
	_idle_style.content_margin_bottom = OneGunUI.SPACE_S
	add_theme_stylebox_override("panel", _idle_style)
	focus_entered.connect(_on_focus_changed)
	focus_exited.connect(_on_focus_changed)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	add_child(row)

	var icon_frame := PanelContainer.new()
	icon_frame.custom_minimum_size = Vector2(36.0, 36.0)
	icon_frame.add_theme_stylebox_override("panel",
		OneGunUI.style_box(OneGunUI.color("face"), OneGunUI.color("border"), 8, 1))
	_icon = OneGunIcon.new()
	_icon.custom_minimum_size = Vector2(26.0, 26.0)
	icon_frame.add_child(_icon)
	row.add_child(icon_frame)

	_name_label = OneGunUI.make_label("", OneGunUI.TEXT_M, "text", true)
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.gui_input.connect(_on_name_label_gui_input)
	row.add_child(_name_label)

	_badge_box = HBoxContainer.new()
	_badge_box.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	row.add_child(_badge_box)

	_trailing_box = HBoxContainer.new()
	_trailing_box.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	row.add_child(_trailing_box)


func set_human(player_name: String, is_host := false, is_you := false,
		ready_state: ReadyState = ReadyState.NONE) -> void:
	_reset()
	focus_mode = Control.FOCUS_NONE
	_icon.kind = OneGunIcon.Kind.PLAYER
	_icon.icon_color = OneGunUI.color("text")
	_name_label.text = player_name
	tooltip_text = player_name
	_name_label.add_theme_color_override("font_color", OneGunUI.color("text"))
	if is_host:
		var crown := OneGunIcon.new()
		crown.kind = OneGunIcon.Kind.CROWN
		crown.icon_color = OneGunUI.color("gold")
		crown.custom_minimum_size = Vector2(20.0, 20.0)
		crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_badge_box.add_child(crown)
	# The crown already identifies the local host in the host view. Keeping the
	# YOU chip for guests only prevents the host name from collapsing in the
	# ten-slot cabinet at compact widths.
	if is_you and not is_host:
		_badge_box.add_child(_make_chip("YOU", "cyan"))
	match ready_state:
		ReadyState.READY:
			_add_ready_icon(OneGunIcon.Kind.CHECK, OneGunUI.color("green"))
		ReadyState.NOT_READY:
			_add_ready_icon(OneGunIcon.Kind.CROSS, OneGunUI.color("red"))


func set_bot(bot_name: String, difficulty: String, show_ready := false) -> void:
	_reset()
	focus_mode = Control.FOCUS_NONE
	_icon.kind = OneGunIcon.Kind.BOT
	_icon.icon_color = OneGunUI.color("muted")
	_name_label.text = bot_name
	tooltip_text = "%s — %s difficulty" % [bot_name, difficulty.capitalize()]
	_name_label.add_theme_color_override("font_color", OneGunUI.color("text"))
	_badge_box.add_child(_make_chip(difficulty.to_upper(), "blue"))
	if show_ready:
		_add_ready_icon(OneGunIcon.Kind.CHECK, OneGunUI.color("green"))


func set_empty(slot_number: int) -> void:
	_reset()
	focus_mode = Control.FOCUS_NONE
	_icon.kind = OneGunIcon.Kind.PLAYER
	_icon.icon_color = Color(OneGunUI.color("muted"), 0.35)
	_name_label.text = ""
	tooltip_text = "Empty player slot %d" % slot_number
	var slot_label := OneGunUI.make_label(str(slot_number), OneGunUI.TEXT_M, "muted", true)
	slot_label.add_theme_color_override("font_color", Color(OneGunUI.color("muted"), 0.6))
	add_trailing(slot_label)


func add_trailing(control: Control) -> void:
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_trailing_box.add_child(control)


func enable_name_editing(callback: Callable) -> void:
	if not callback.is_valid():
		return
	_name_edit_callback = callback
	_name_label.focus_mode = Control.FOCUS_ALL
	_name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_name_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_name_label.tooltip_text = "Click your name to edit it"
	_name_label.add_theme_color_override("font_color", OneGunUI.color("cyan"))


func _add_ready_icon(icon_kind: OneGunIcon.Kind, tone: Color) -> void:
	var mark := OneGunIcon.new()
	mark.kind = icon_kind
	mark.icon_color = tone
	mark.custom_minimum_size = Vector2(22.0, 22.0)
	add_trailing(mark)


func _make_chip(text: String, color_role: String) -> PanelContainer:
	var chip := PanelContainer.new()
	var accent := OneGunUI.color(color_role)
	var style := OneGunUI.style_box(Color(accent, 0.16), accent.darkened(0.1), OneGunUI.RADIUS_CHIP, 1)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", style)
	var label := OneGunUI.make_label(text, OneGunUI.TEXT_XS, color_role, true)
	chip.add_child(label)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return chip


func _reset() -> void:
	_name_edit_callback = Callable()
	_name_label.focus_mode = Control.FOCUS_NONE
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_name_label.tooltip_text = ""
	for box in [_badge_box, _trailing_box]:
		for child in box.get_children():
			child.queue_free()


func _on_name_label_gui_input(event: InputEvent) -> void:
	if not _name_edit_callback.is_valid():
		return
	var clicked: bool = (event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed)
	var keyboard_activated: bool = (event is InputEventKey and event.pressed
			and not event.echo and event.is_action("ui_accept"))
	if not clicked and not keyboard_activated:
		return
	_name_label.accept_event()
	_name_edit_callback.call()


func _on_focus_changed() -> void:
	if has_focus():
		add_theme_stylebox_override("panel", OneGunUI.focus_ring(_idle_style))
	else:
		add_theme_stylebox_override("panel", _idle_style)
