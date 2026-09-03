class_name LobbyInviteNotification
extends PanelContainer

signal join_requested(lobby: Dictionary)

var _invite: Dictionary = {}
var _title: Label
var _lobby: Label
var _accept: OneGunButton
var _decline: OneGunButton
var _busy := false


func _ready() -> void:
	name = "LobbyInviteNotification"
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(460.0, 158.0)
	add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(0.012, 0.018, 0.055, 0.985), OneGunUI.color("purple"),
		18, 3, 10, 18.0))
	_build_ui()
	visible = false


func present(invite: Dictionary) -> void:
	if invite.is_empty() or str(invite.get("id", "")) == "":
		return
	_invite = invite.duplicate(true)
	_busy = false
	_accept.disabled = false
	_decline.disabled = false
	_title.text = "%s INVITED YOU" % str(
		_invite.get("username", "A FRIEND")).to_upper()
	_lobby.text = "JOIN %s?" % str(
		_invite.get("lobby_name", "ONE GUN LOBBY")).to_upper()
	visible = true
	modulate.a = 0.0
	position.x += 22.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.18)
	tween.tween_property(self, "position:x", position.x - 22.0, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func dismiss() -> void:
	_invite.clear()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _busy or not event is InputEventJoypadButton \
			or not event.pressed:
		return
	if event.button_index == JOY_BUTTON_Y:
		get_viewport().set_input_as_handled()
		_accept_invite()
	elif event.button_index == JOY_BUTTON_X:
		get_viewport().set_input_as_handled()
		_decline_invite()


func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	add_child(column)
	var kicker := OneGunUI.make_label("LOBBY INVITATION", 12, "purple", true)
	column.add_child(kicker)
	_title = OneGunUI.make_heading("A FRIEND INVITED YOU", 22, "text_bright")
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_title)
	_lobby = OneGunUI.make_label("JOIN THEIR LOBBY?", 14, "cyan", true)
	_lobby.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_lobby)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	_accept = OneGunButton.new()
	_accept.name = "AcceptLobbyInviteToastButton"
	_accept.text = "Y  ACCEPT & JOIN"
	_accept.variant = "green"
	_accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accept.custom_minimum_size.y = 44.0
	_accept.pressed.connect(_accept_invite)
	actions.add_child(_accept)
	_decline = OneGunButton.new()
	_decline.name = "DeclineLobbyInviteToastButton"
	_decline.text = "X  DENY"
	_decline.variant = "red"
	_decline.custom_minimum_size = Vector2(130.0, 44.0)
	_decline.pressed.connect(_decline_invite)
	actions.add_child(_decline)
	_accept.focus_neighbor_right = _accept.get_path_to(_decline)
	_decline.focus_neighbor_left = _decline.get_path_to(_accept)


func _accept_invite() -> void:
	if _busy or _invite.is_empty():
		return
	_busy = true
	_accept.disabled = true
	_decline.disabled = true
	_accept.text = "CONNECTING…"
	var receipt: Dictionary = await SocialManager.respond_lobby_invite(
		str(_invite.get("id", "")), true)
	var endpoint := SocialManager.joinable_endpoint(receipt)
	if endpoint.is_empty():
		_accept.text = "INVITE EXPIRED"
		_decline.disabled = false
		_busy = false
		return
	var stable_endpoint := endpoint.duplicate(true)
	dismiss()
	_emit_join_requested.call_deferred(stable_endpoint)


func _emit_join_requested(endpoint: Dictionary) -> void:
	if is_inside_tree() and not endpoint.is_empty():
		join_requested.emit(endpoint)


func _decline_invite() -> void:
	if _busy or _invite.is_empty():
		return
	_busy = true
	_accept.disabled = true
	_decline.disabled = true
	await SocialManager.respond_lobby_invite(str(_invite.get("id", "")), false)
	dismiss()
