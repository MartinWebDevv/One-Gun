class_name SocialOverlay
extends Control

signal closed
signal join_requested(lobby: Dictionary)

var _account_name_field: LineEdit
var _add_button: OneGunButton
var _tabs: OneGunTabBar
var _pages: Array[Control] = []
var _friends_list: VBoxContainer
var _requests_list: VBoxContainer
var _invites_list: VBoxContainer
var _status_label: Label
var _online_label: Label
var _refresh_button: OneGunButton
var _close_button: OneGunButton
var _using_pointer := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_using_pointer = not PlayerPrefs.is_using_controller("p1")
	_build_ui()
	if not SocialManager.social_updated.is_connected(_on_social_updated):
		SocialManager.social_updated.connect(_on_social_updated)
	if not SocialManager.operation_succeeded.is_connected(_on_operation_succeeded):
		SocialManager.operation_succeeded.connect(_on_operation_succeeded)
	if not SocialManager.operation_failed.is_connected(_on_operation_failed):
		SocialManager.operation_failed.connect(_on_operation_failed)
	_refresh()
	if SocialManager.is_ready():
		SocialManager.refresh_snapshot()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.relative.length_squared() <= 4.0 \
				or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			return
		_using_pointer = true
		var owner := get_viewport().gui_get_focus_owner()
		if owner is BaseButton and is_ancestor_of(owner):
			owner.release_focus()
		return
	if event is InputEventMouseButton:
		# Keep the focused control intact until Godot's GUI phase completes the
		# pointer click. Releasing here made controller-focused menus unclickable.
		_using_pointer = true
		return
	var navigation_input := false
	if event is InputEventKey:
		navigation_input = event.pressed and event.keycode in [
			KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_TAB, KEY_ENTER, KEY_SPACE]
	elif event is InputEventJoypadButton:
		navigation_input = event.pressed
	elif event is InputEventJoypadMotion:
		navigation_input = absf(event.axis_value) >= 0.45
	if navigation_input:
		_using_pointer = false
		_configure_controller_focus()


func _exit_tree() -> void:
	for connection in [
		[SocialManager.social_updated, _on_social_updated],
		[SocialManager.operation_succeeded, _on_operation_succeeded],
		[SocialManager.operation_failed, _on_operation_failed],
	]:
		var signal_value: Signal = connection[0]
		var callback: Callable = connection[1]
		if signal_value.is_connected(callback):
			signal_value.disconnect(callback)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_close()


func _build_ui() -> void:
	var scrim := ColorRect.new()
	scrim.name = "SocialScrim"
	scrim.color = Color(OneGunUI.color("canvas"),0.96)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 32.0
	center.offset_top = 28.0
	center.offset_right = -32.0
	center.offset_bottom = -28.0
	add_child(center)
	var cabinet := OneGunCabinet.new()
	cabinet.name = "FriendsCabinet"
	cabinet.variant = OneGunCabinet.Variant.CABINET
	cabinet.content_padding = 22
	cabinet.custom_minimum_size = Vector2(1120.0, 740.0)
	center.add_child(cabinet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	cabinet.get_content().add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	var title := OneGunUI.make_heading("FRIENDS", 38, "gold")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_online_label = OneGunUI.make_label("0 ONLINE", 13, "green", true)
	_online_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_online_label)
	_refresh_button = OneGunButton.new()
	_refresh_button.name = "RefreshFriendsButton"
	_refresh_button.text = "REFRESH"
	_refresh_button.variant = "navy"
	_refresh_button.custom_minimum_size = Vector2(130.0, 48.0)
	_refresh_button.pressed.connect(func() -> void: SocialManager.refresh_snapshot())
	header.add_child(_refresh_button)

	var explanation := OneGunUI.make_label(
		"Add players by their exact Account Name. Only accepted friends can see your online activity or receive a private Tailscale lobby endpoint.",
		13, "muted")
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(explanation)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 10)
	column.add_child(add_row)
	_account_name_field = LineEdit.new()
	_account_name_field.name = "FriendAccountName"
	_account_name_field.placeholder_text = "Exact Account Name"
	_account_name_field.max_length = 20
	_account_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_account_name_field.custom_minimum_size.y = 48.0
	_account_name_field.text_submitted.connect(func(_value: String) -> void:
		_send_friend_request())
	add_row.add_child(_account_name_field)
	_add_button = OneGunButton.new()
	_add_button.name = "AddFriendButton"
	_add_button.text = "SEND FRIEND REQUEST"
	_add_button.variant = "gold"
	_add_button.custom_minimum_size = Vector2(245.0, 48.0)
	_add_button.pressed.connect(_send_friend_request)
	add_row.add_child(_add_button)

	_tabs = OneGunTabBar.new()
	_tabs.name = "SocialTabs"
	_tabs.tabs = PackedStringArray(["FRIENDS", "REQUESTS", "LOBBY INVITES"])
	_tabs.tab_selected.connect(_show_page)
	column.add_child(_tabs)
	var holder := MarginContainer.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(holder)
	_friends_list = _make_scroll_page(holder)
	_requests_list = _make_scroll_page(holder)
	_invites_list = _make_scroll_page(holder)
	_pages = [_friends_list.get_parent(), _requests_list.get_parent(),
		_invites_list.get_parent()]
	_show_page(0)

	_status_label = OneGunUI.make_label("", 12, "muted", true)
	_status_label.name = "SocialStatus"
	_status_label.custom_minimum_size.y = 24.0
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	_close_button = OneGunButton.new()
	_close_button.name = "CloseFriendsButton"
	_close_button.text = "BACK"
	_close_button.variant = "navy"
	_close_button.custom_minimum_size = Vector2(220.0, 60.0)
	_close_button.pressed.connect(_close)
	footer.add_child(_close_button)
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_spacer)


func _make_scroll_page(holder: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	holder.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	return list


func _show_page(index: int) -> void:
	for page_index in _pages.size():
		_pages[page_index].visible = page_index == index
	_configure_controller_focus.call_deferred()


func _refresh() -> void:
	var signed_in := SocialManager.is_ready()
	_account_name_field.editable = signed_in
	_add_button.disabled = not signed_in
	_online_label.text = "%d ONLINE" % SocialManager.online_friend_count()
	_rebuild_friends(signed_in)
	_rebuild_requests(signed_in)
	_rebuild_invites(signed_in)
	_configure_controller_focus.call_deferred()
	if not signed_in:
		_set_status("SIGN IN THROUGH PROFILE TO USE FRIENDS", true)
	elif SocialManager.snapshot.get("server_time", "") == "":
		_set_status("LOADING FRIENDS…", false)


func _configure_controller_focus() -> void:
	if not is_inside_tree():
		return
	var controls: Array = []
	for node in find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not control.is_visible_in_tree() \
				or control.focus_mode == Control.FOCUS_NONE:
			continue
		if control is BaseButton and (control as BaseButton).disabled:
			continue
		controls.append(control)
	if not controls.is_empty():
		OneGunUI.chain_focus_vertical(controls)
	var owner := get_viewport().gui_get_focus_owner()
	if not _using_pointer and (owner == null or not is_ancestor_of(owner)):
		var tab_buttons := _tabs.find_children("*", "Button", false, false)
		if not tab_buttons.is_empty():
			(tab_buttons[clampi(_tabs.selected, 0,
				tab_buttons.size() - 1)] as Control).grab_focus()
		elif not controls.is_empty():
			(controls[0] as Control).grab_focus()


func _rebuild_friends(signed_in: bool) -> void:
	_clear(_friends_list)
	if not signed_in:
		_friends_list.add_child(_empty("SIGN IN TO SEE FRIENDS"))
		return
	var values := SocialManager.friends()
	if values.is_empty():
		_friends_list.add_child(_empty("NO FRIENDS YET — SEND A REQUEST BY ACCOUNT NAME"))
		return
	for value in values:
		if value is Dictionary:
			_friends_list.add_child(_make_friend_row(value))


func _make_friend_row(friend: Dictionary) -> Control:
	var online := bool(friend.get("online", false))
	var panel := _row_panel("green" if online else "border")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var status := OneGunUI.make_heading("●", 18, "green" if online else "muted")
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(status)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(identity)
	identity.add_child(OneGunUI.make_heading(
		str(friend.get("username", "PLAYER")).to_upper(), 18, "text_bright"))
	var activity := "OFFLINE"
	if online:
		activity = str(friend.get("activity", "home")).to_upper()
		var lobby_name := str(friend.get("lobby_name", ""))
		if lobby_name != "":
			activity += "  •  %s" % lobby_name.to_upper()
	identity.add_child(OneGunUI.make_label(activity, 11,
		"green" if online else "muted", true))
	var endpoint := SocialManager.joinable_endpoint(friend)
	if not endpoint.is_empty():
		var join_button := _action_button("JOIN", "green")
		join_button.name = "JoinFriendButton"
		join_button.pressed.connect(
			_request_join.bind(endpoint.duplicate(true)))
		row.add_child(join_button)
	var invite_button := _action_button("INVITE", "gold")
	invite_button.name = "InviteFriendButton"
	invite_button.disabled = not SocialManager.can_invite_from_current_lobby()
	invite_button.tooltip_text = "Enter an online lobby to invite this friend." \
		if invite_button.disabled else "Invite this friend to your current lobby."
	invite_button.pressed.connect(func() -> void:
		SocialManager.send_lobby_invite(str(friend.get("user_id", ""))))
	row.add_child(invite_button)
	var remove_button := OneGunConfirmButton.new()
	remove_button.text = "REMOVE"
	remove_button.confirm_text = "CONFIRM"
	remove_button.variant = "navy"
	remove_button.custom_minimum_size = Vector2(105.0, 42.0)
	remove_button.confirmed.connect(func() -> void:
		SocialManager.remove_friend(str(friend.get("user_id", ""))))
	row.add_child(remove_button)
	return panel


func _rebuild_requests(signed_in: bool) -> void:
	_clear(_requests_list)
	if not signed_in:
		_requests_list.add_child(_empty("SIGN IN TO MANAGE REQUESTS"))
		return
	var incoming := SocialManager.incoming_requests()
	var outgoing := SocialManager.outgoing_requests()
	_requests_list.add_child(OneGunUI.make_heading(
		"INCOMING  (%d)" % incoming.size(), 16, "gold"))
	if incoming.is_empty():
		_requests_list.add_child(_empty("NO INCOMING REQUESTS"))
	for value in incoming:
		if value is Dictionary:
			_requests_list.add_child(_make_request_row(value, true))
	_requests_list.add_child(OneGunUI.make_heading(
		"SENT  (%d)" % outgoing.size(), 16, "cyan"))
	if outgoing.is_empty():
		_requests_list.add_child(_empty("NO SENT REQUESTS"))
	for value in outgoing:
		if value is Dictionary:
			_requests_list.add_child(_make_request_row(value, false))


func _make_request_row(request: Dictionary, incoming: bool) -> Control:
	var panel := _row_panel("gold" if incoming else "border")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var name := OneGunUI.make_heading(
		str(request.get("username", "PLAYER")).to_upper(), 17, "text_bright")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name)
	if incoming:
		var accept := _action_button("ACCEPT", "green")
		accept.name = "AcceptFriendButton"
		accept.pressed.connect(func() -> void: SocialManager.respond_friend_request(
			str(request.get("user_id", "")), true))
		row.add_child(accept)
		var deny := _action_button("DENY", "red")
		deny.name = "DenyFriendButton"
		deny.pressed.connect(func() -> void: SocialManager.respond_friend_request(
			str(request.get("user_id", "")), false))
		row.add_child(deny)
	else:
		row.add_child(OneGunUI.make_label("REQUEST PENDING", 12, "muted", true))
	return panel


func _rebuild_invites(signed_in: bool) -> void:
	_clear(_invites_list)
	if not signed_in:
		_invites_list.add_child(_empty("SIGN IN TO RECEIVE LOBBY INVITES"))
		return
	var values := SocialManager.invites()
	if values.is_empty():
		_invites_list.add_child(_empty("NO ACTIVE LOBBY INVITATIONS"))
		return
	for value in values:
		if value is Dictionary:
			_invites_list.add_child(_make_invite_row(value))


func _make_invite_row(invite: Dictionary) -> Control:
	var panel := _row_panel("purple")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	copy.add_child(OneGunUI.make_heading("%s INVITED YOU" %
		str(invite.get("username", "PLAYER")).to_upper(), 17, "text_bright"))
	copy.add_child(OneGunUI.make_label(
		str(invite.get("lobby_name", "LOBBY")).to_upper(), 12, "purple", true))
	var accept := _action_button("ACCEPT & JOIN", "green", 155.0)
	accept.name = "AcceptLobbyInviteButton"
	accept.pressed.connect(_accept_invite.bind(invite.duplicate(true)))
	row.add_child(accept)
	var deny := _action_button("DENY", "red")
	deny.name = "DenyLobbyInviteButton"
	deny.pressed.connect(_deny_invite.bind(invite))
	row.add_child(deny)
	return panel


func _send_friend_request() -> void:
	if not SocialManager.is_ready():
		return
	var account_name := _account_name_field.text.strip_edges()
	if await SocialManager.send_friend_request(account_name):
		_account_name_field.clear()


func _accept_invite(invite: Dictionary) -> void:
	var receipt: Dictionary = await SocialManager.respond_lobby_invite(
		str(invite.get("id", "")), true)
	var endpoint := SocialManager.joinable_endpoint(receipt)
	if endpoint.is_empty():
		_set_status("THE INVITATION ENDPOINT IS NO LONGER VALID", true)
		return
	_request_join(endpoint)


func _request_join(endpoint: Dictionary) -> void:
	# Network peer replacement and scene changes must not run inside the GUI
	# button signal (or an invite coroutine resumed by a social refresh).
	_emit_join_requested.call_deferred(endpoint.duplicate(true))


func _emit_join_requested(endpoint: Dictionary) -> void:
	if is_inside_tree() and not endpoint.is_empty():
		join_requested.emit(endpoint)


func _deny_invite(invite: Dictionary) -> void:
	await SocialManager.respond_lobby_invite(str(invite.get("id", "")), false)


func _action_button(text: String, variant: String, width := 105.0) -> OneGunButton:
	var button := OneGunButton.new()
	button.text = text
	button.variant = variant
	button.custom_minimum_size = Vector2(width, 42.0)
	return button


func _row_panel(role: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 66.0
	panel.add_theme_stylebox_override("panel", OneGunUI.style_box(
		OneGunUI.color("well"), Color(OneGunUI.color(role), 0.75), 9, 1, 0, 10.0))
	return panel


func _empty(text: String) -> Label:
	var label := OneGunUI.make_label(text, 13, "muted", true)
	label.custom_minimum_size.y = 60.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _clear(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _on_social_updated(_snapshot: Dictionary) -> void:
	_refresh()


func _on_operation_succeeded(_operation: String, message: String) -> void:
	_set_status(message.to_upper(), false)


func _on_operation_failed(_operation: String, message: String) -> void:
	_set_status(message.to_upper(), true)


func _set_status(message: String, error: bool) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.add_theme_color_override("font_color",
		OneGunUI.color("red" if error else "green"))


func _close() -> void:
	closed.emit()
	queue_free()
