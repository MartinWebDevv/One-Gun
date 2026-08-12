class_name OneGunLobbyRow
extends PanelContainer

# Online-browser lobby row (packet Phase 4): privacy icon, name, mode,
# players, joinability status. Selectable with mouse/keyboard/controller;
# double-click or ui_accept activates (join attempt). Populated exclusively
# from real discovery data by the caller.

signal selected
signal activated

enum Privacy { PUBLIC, FRIENDS_ONLY, PRIVATE }
enum Joinability { JOINABLE, FULL, IN_PROGRESS, INCOMPATIBLE, UNKNOWN }

var lobby_name := ""
var privacy: Privacy = Privacy.PUBLIC
var is_selected := false:
	set(value):
		is_selected = value
		_refresh_style()

var _privacy_icon: OneGunIcon
var _name_label: Label
var _mode_label: Label
var _players_label: Label
var _status_chip: PanelContainer
var _status_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 54.0)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_style()
	focus_entered.connect(func() -> void:
		selected.emit()
		_refresh_style())
	focus_exited.connect(_refresh_style)
	mouse_entered.connect(func() -> void:
		AudioManager.play_hover()
		_refresh_style())
	mouse_exited.connect(_refresh_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	add_child(row)

	_privacy_icon = OneGunIcon.new()
	_privacy_icon.custom_minimum_size = Vector2(24.0, 24.0)
	_privacy_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_privacy_icon)

	_name_label = OneGunUI.make_label("", OneGunUI.TEXT_M, "text", true)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_name_label)

	_mode_label = OneGunUI.make_label("", OneGunUI.TEXT_S, "muted")
	_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_mode_label)

	_players_label = OneGunUI.make_label("", OneGunUI.TEXT_M, "text", true)
	_players_label.custom_minimum_size = Vector2(56.0, 0)
	_players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_players_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_players_label)

	_status_chip = PanelContainer.new()
	_status_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_label = OneGunUI.make_label("", OneGunUI.TEXT_XS, "text", true)
	_status_chip.add_child(_status_label)
	row.add_child(_status_chip)


func set_lobby(name_text: String, lobby_privacy: Privacy, current_players: int,
		max_players: int, mode: String, joinability: Joinability = Joinability.UNKNOWN) -> void:
	lobby_name = name_text
	privacy = lobby_privacy
	_name_label.text = name_text
	_mode_label.text = mode.to_upper()
	_players_label.text = "%d/%d" % [current_players, max_players]
	match privacy:
		Privacy.PRIVATE:
			_privacy_icon.kind = OneGunIcon.Kind.LOCK
			_privacy_icon.icon_color = OneGunUI.color("red").lightened(0.15)
		Privacy.FRIENDS_ONLY:
			_privacy_icon.kind = OneGunIcon.Kind.FRIENDS
			_privacy_icon.icon_color = OneGunUI.color("cyan")
		_:
			_privacy_icon.kind = OneGunIcon.Kind.GLOBE
			_privacy_icon.icon_color = OneGunUI.color("green")
	_set_status(joinability)


func _set_status(joinability: Joinability) -> void:
	var text := ""
	var role := "muted"
	match joinability:
		Joinability.JOINABLE:
			text = "JOINABLE"
			role = "green"
		Joinability.FULL:
			text = "FULL"
			role = "red"
		Joinability.IN_PROGRESS:
			text = "IN PROGRESS"
			role = "gold"
		Joinability.INCOMPATIBLE:
			text = "VERSION"
			role = "red"
		_:
			text = "—"
	var accent := OneGunUI.color(role)
	var style := OneGunUI.style_box(Color(accent, 0.14), accent.darkened(0.1), OneGunUI.RADIUS_CHIP, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	_status_chip.add_theme_stylebox_override("panel", style)
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", accent)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		grab_focus()
		if event.double_click:
			activated.emit()
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		activated.emit()
		accept_event()


func _refresh_style() -> void:
	var bg := OneGunUI.color("well")
	var border := OneGunUI.color("well").darkened(0.35)
	var border_width := 1
	if is_selected:
		bg = OneGunUI.color("face_raised")
		border = OneGunUI.color("gold")
		border_width = OneGunUI.BORDER_THIN
	elif get_global_rect().has_point(get_global_mouse_position()):
		bg = OneGunUI.color("well").lightened(0.05)
	var style := OneGunUI.style_box(bg, border, OneGunUI.RADIUS_INPUT, border_width)
	style.content_margin_left = OneGunUI.SPACE_M
	style.content_margin_right = OneGunUI.SPACE_M
	style.content_margin_top = OneGunUI.SPACE_S
	style.content_margin_bottom = OneGunUI.SPACE_S
	if has_focus():
		style = OneGunUI.focus_ring(style)
	add_theme_stylebox_override("panel", style)
