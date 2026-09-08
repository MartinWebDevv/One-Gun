extends CanvasLayer

# Persistent online-only chat presentation. NetworkManager owns validation and
# delivery; this autoload keeps one UI alive across lobby/match scene changes.

const MAX_HISTORY := 50
const TRANSIENT_SECONDS := 4.0
const FADE_SECONDS := 0.35
const BUBBLE_SECONDS := 4.0
const BUBBLE_HEAD_OFFSET := Vector3(0.0, 2.65, 0.0)
const BUBBLE_WIDTH := 260.0
const BUBBLE_MAX_CHARACTERS := 120
const SCREEN_MARGIN := 12.0
const NOTIFICATION_WIDTH := 280.0
const MAX_ACTIVE_NOTIFICATIONS := 4

var _messages_by_context: Dictionary = {}
var _display_context := ""
var _window_open := false
var _typing := false
var _ui_built := false
var _previous_focus_owner: Control
var _bubbles: Dictionary = {}
var _notifications: Array[Control] = []
var _notification_tweens: Dictionary = {}

var _root: Control
var _bubble_layer: Control
var _notification_stack: VBoxContainer
var _input_blocker: ColorRect
var _panel: PanelContainer
var _header: HBoxContainer
var _title: Label
var _history: RichTextLabel
var _hint: Label
var _input_field: LineEdit


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 220
	NetworkManager.chat_message_received.connect(_on_chat_message_received)
	NetworkManager.chat_session_reset.connect(_on_chat_session_reset)
	NetworkManager.lobby_changed.connect(_on_lobby_changed)
	set_process(false)


func _process(_delta: float) -> void:
	if _bubbles.is_empty():
		set_process(false)
		return
	var now := Time.get_ticks_msec()
	var camera := get_viewport().get_camera_3d()
	var viewport_size := get_viewport().get_visible_rect().size
	var expired_peer_ids: Array[int] = []
	for peer_id_value in _bubbles:
		var peer_id := int(peer_id_value)
		var entry: Dictionary = _bubbles[peer_id_value]
		var panel := entry.get("panel") as PanelContainer
		var tail := entry.get("tail") as Polygon2D
		var expires_msec := int(entry.get("expires_msec", 0))
		if panel == null or not is_instance_valid(panel) or now >= expires_msec:
			if panel != null and is_instance_valid(panel):
				panel.queue_free()
			if tail != null and is_instance_valid(tail):
				tail.queue_free()
			expired_peer_ids.append(peer_id)
			continue
		var actor := NetworkManager.find_net_player(peer_id) as Node3D
		if actor == null or not is_instance_valid(actor) or camera == null:
			panel.visible = false
			if tail != null and is_instance_valid(tail):
				tail.visible = false
			continue
		var head_position := actor.global_position + BUBBLE_HEAD_OFFSET
		if camera.is_position_behind(head_position):
			panel.visible = false
			if tail != null and is_instance_valid(tail):
				tail.visible = false
			continue
		var projected := camera.unproject_position(head_position)
		if projected.x < 0.0 or projected.x > viewport_size.x or projected.y < 0.0 or projected.y > viewport_size.y:
			panel.visible = false
			if tail != null and is_instance_valid(tail):
				tail.visible = false
			continue
		var fade_alpha := clampf(float(expires_msec - now) / (FADE_SECONDS * 1000.0), 0.0, 1.0)
		panel.visible = true
		panel.modulate.a = fade_alpha
		if tail != null and is_instance_valid(tail):
			tail.visible = true
			tail.modulate.a = fade_alpha
		var panel_size := panel.size
		if panel_size.x <= 0.0 or panel_size.y <= 0.0:
			panel_size = Vector2(BUBBLE_WIDTH, panel.get_combined_minimum_size().y)
		var target := projected - Vector2(panel_size.x * 0.5, panel_size.y + 10.0)
		target.x = clampf(target.x, SCREEN_MARGIN, maxf(SCREEN_MARGIN, viewport_size.x - panel_size.x - SCREEN_MARGIN))
		target.y = clampf(target.y, SCREEN_MARGIN, maxf(SCREEN_MARGIN, viewport_size.y - panel_size.y - SCREEN_MARGIN))
		panel.position = target
		if tail != null and is_instance_valid(tail):
			var tail_x := clampf(projected.x, target.x + 14.0, target.x + panel_size.x - 14.0)
			tail.position = Vector2(tail_x, target.y + panel_size.y - 1.0)
	for peer_id in expired_peer_ids:
		_bubbles.erase(peer_id)
	if _bubbles.is_empty():
		set_process(false)


func is_typing() -> bool:
	return _typing and NetworkManager.is_online()


func is_window_open() -> bool:
	return _window_open and NetworkManager.is_online()


func _input(event: InputEvent) -> void:
	# Do not let the persistent chat layer claim Enter/T while a full-screen
	# modal such as the Winners Circle owns input and controller focus.
	if get_tree().get_first_node_in_group("modal_input_owner") != null:
		return
	if not NetworkManager.is_online() or NetworkManager.is_dedicated_server():
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	if _typing:
		# T must remain an ordinary character while composing. Escape only exits
		# composition; T still owns opening/closing the chat window itself.
		if _is_key(key_event, KEY_ESCAPE):
			_finish_typing(false)
			get_viewport().set_input_as_handled()
		return
	if _external_text_field_has_focus():
		return
	if _is_key(key_event, KEY_T):
		if _window_open:
			_close_window()
		else:
			_open_window()
		get_viewport().set_input_as_handled()
		return
	if _window_open and _is_key(key_event, KEY_ENTER):
		_start_typing()
		get_viewport().set_input_as_handled()


func _is_key(event: InputEventKey, key: Key) -> bool:
	return event.keycode == key or event.physical_keycode == key


func _external_text_field_has_focus() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner != null and focus_owner != _input_field \
		and (focus_owner is LineEdit or focus_owner is TextEdit)


func _ensure_ui() -> void:
	if _ui_built:
		return
	_ui_built = true

	_root = Control.new()
	_root.name = "OnlineChatRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_bubble_layer = Control.new()
	_bubble_layer.name = "PlayerChatBubbles"
	_bubble_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bubble_layer)

	_notification_stack = VBoxContainer.new()
	_notification_stack.name = "IncomingMessageStack"
	_notification_stack.anchor_left = 0.02
	_notification_stack.anchor_right = 0.02
	_notification_stack.anchor_top = 0.56
	_notification_stack.anchor_bottom = 0.56
	_notification_stack.offset_right = NOTIFICATION_WIDTH
	_notification_stack.custom_minimum_size.x = NOTIFICATION_WIDTH
	_notification_stack.add_theme_constant_override("separation", 7)
	_notification_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notification_stack.z_index = 25
	_root.add_child(_notification_stack)

	_input_blocker = ColorRect.new()
	_input_blocker.name = "TypingInputBlocker"
	_input_blocker.color = Color.TRANSPARENT
	_input_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_input_blocker.visible = false
	_root.add_child(_input_blocker)

	_panel = PanelContainer.new()
	_panel.name = "ChatPanel"
	_panel.anchor_left = 0.02
	_panel.anchor_right = 0.31
	_panel.anchor_top = 0.69
	_panel.anchor_bottom = 0.96
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.z_index = 30
	var panel_style := OneGunUI.style_box(
		Color(OneGunUI.color("face"), 0.97),
		OneGunUI.color("gold"),
		OneGunUI.RADIUS_CABINET,
		OneGunUI.BORDER_THICK,
		8,
		0,
		Color(0.0, 0.0, 0.0, 0.46)
	)
	_panel.add_theme_stylebox_override("panel", panel_style)
	_panel.visible = false
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	_header = HBoxContainer.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_override("font", OneGunUI.font_bold())
	_title.add_theme_font_size_override("font_size", OneGunUI.TEXT_S)
	_title.add_theme_color_override("font_color", OneGunUI.color("gold"))
	_header.add_child(_title)
	var close_hint := Label.new()
	close_hint.text = "[T] CLOSE"
	close_hint.add_theme_font_size_override("font_size", OneGunUI.TEXT_XS)
	close_hint.add_theme_color_override("font_color", OneGunUI.color("cyan"))
	close_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(close_hint)
	column.add_child(_header)

	_history = RichTextLabel.new()
	_history.name = "History"
	_history.bbcode_enabled = false
	_history.scroll_active = true
	_history.scroll_following = true
	_history.selection_enabled = true
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history.add_theme_font_override("normal_font", OneGunUI.font_med())
	_history.add_theme_font_size_override("normal_font_size", OneGunUI.TEXT_S)
	_history.add_theme_color_override("default_color", OneGunUI.color("text"))
	_history.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_history)

	_hint = Label.new()
	_hint.text = "ENTER TO TYPE  -  T TO CLOSE"
	_hint.add_theme_font_size_override("font_size", OneGunUI.TEXT_XS)
	_hint.add_theme_color_override("font_color", OneGunUI.color("muted"))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_hint)

	_input_field = LineEdit.new()
	_input_field.name = "MessageInput"
	_input_field.max_length = NetworkManager.CHAT_MAX_MESSAGE_LENGTH
	_input_field.placeholder_text = "Type a message..."
	_input_field.add_theme_font_override("font", OneGunUI.font_med())
	_input_field.add_theme_font_size_override("font_size", OneGunUI.TEXT_S)
	_input_field.add_theme_color_override("font_color", OneGunUI.color("text"))
	_input_field.add_theme_color_override("font_placeholder_color", OneGunUI.color("muted"))
	var input_normal := OneGunUI.style_box(
		OneGunUI.color("well"),
		OneGunUI.color("border"),
		OneGunUI.RADIUS_INPUT,
		OneGunUI.BORDER_THIN,
		0,
		8
	)
	_input_field.add_theme_stylebox_override("normal", input_normal)
	_input_field.add_theme_stylebox_override("focus", OneGunUI.focus_ring(input_normal))
	_input_field.text_submitted.connect(_on_text_submitted)
	_input_field.visible = false
	column.add_child(_input_field)


func _open_window() -> void:
	_ensure_ui()
	_clear_notifications()
	_window_open = true
	_display_context = _active_context()
	_refresh_history()
	_panel.visible = true
	_panel.modulate.a = 1.0
	_header.visible = true
	_hint.visible = true
	_input_field.visible = false
	_input_blocker.visible = false


func _close_window() -> void:
	_window_open = false
	if _typing:
		_finish_typing(false)
	_header.visible = false
	_hint.visible = false
	_input_field.visible = false
	_input_blocker.visible = false
	_panel.visible = false
	_panel.modulate.a = 1.0


func _start_typing() -> void:
	_ensure_ui()
	_typing = true
	_previous_focus_owner = get_viewport().gui_get_focus_owner()
	_input_blocker.visible = true
	_input_field.visible = true
	_input_field.editable = true
	_hint.text = "ENTER TO SEND  -  ESC TO CANCEL"
	_input_field.grab_focus()
	_input_field.caret_column = _input_field.text.length()


func _finish_typing(send_message: bool) -> void:
	if not _typing:
		return
	var message := _input_field.text if _input_field != null else ""
	_typing = false
	if send_message and not message.strip_edges().is_empty():
		NetworkManager.send_chat_message(message)
	if _input_field != null:
		_input_field.clear()
		_input_field.release_focus()
		_input_field.visible = false
	if _input_blocker != null:
		_input_blocker.visible = false
	if _hint != null:
		_hint.text = "ENTER TO TYPE  -  T TO CLOSE"
	if _previous_focus_owner != null and is_instance_valid(_previous_focus_owner) \
			and _previous_focus_owner.is_visible_in_tree():
		_previous_focus_owner.grab_focus.call_deferred()
	_previous_focus_owner = null


func _on_text_submitted(_submitted_text: String) -> void:
	_finish_typing(true)


func _on_chat_message_received(sender_peer_id: int, sender_name: String,
		message: String, context: String) -> void:
	var messages: Array = _messages_by_context.get(context, [])
	messages.append({
		"sender_name": sender_name,
		"message": message,
		"received_msec": Time.get_ticks_msec(),
	})
	while messages.size() > MAX_HISTORY:
		messages.pop_front()
	_messages_by_context[context] = messages
	if context != _active_context():
		return
	if context == "match" or context == "playpen":
		_show_actor_bubble(sender_peer_id, sender_name, message)
	_ensure_ui()
	_display_context = context
	_refresh_history()
	if not _window_open:
		_show_notification(sender_name, message)


func _show_actor_bubble(peer_id: int, sender_name: String, message: String) -> void:
	_ensure_ui()
	var entry: Dictionary = _bubbles.get(peer_id, {})
	var panel := entry.get("panel") as PanelContainer
	var tail := entry.get("tail") as Polygon2D
	var name_label := entry.get("name_label") as Label
	var message_label := entry.get("message_label") as Label
	if panel == null or not is_instance_valid(panel):
		panel = PanelContainer.new()
		panel.name = "Peer%dBubble" % peer_id
		panel.custom_minimum_size = Vector2(BUBBLE_WIDTH, 0.0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.z_index = 20
		panel.add_theme_stylebox_override("panel", OneGunUI.style_box(
			Color(OneGunUI.color("well"), 0.97),
			OneGunUI.color("cyan"),
			OneGunUI.RADIUS_SECTION,
			OneGunUI.BORDER_THIN,
			6,
			8,
			Color(0.0, 0.0, 0.0, 0.48)
		))
		var bubble_column := VBoxContainer.new()
		bubble_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble_column.add_theme_constant_override("separation", 2)
		panel.add_child(bubble_column)
		name_label = OneGunUI.make_label("", OneGunUI.TEXT_XS, "gold", true)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble_column.add_child(name_label)
		message_label = OneGunUI.make_label("", OneGunUI.TEXT_S, "text")
		message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message_label.custom_minimum_size.x = BUBBLE_WIDTH - 16.0
		message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble_column.add_child(message_label)
		_bubble_layer.add_child(panel)
		tail = Polygon2D.new()
		tail.name = "BubbleTail"
		tail.polygon = PackedVector2Array([
			Vector2(-9.0, 0.0),
			Vector2(9.0, 0.0),
			Vector2(0.0, 11.0),
		])
		tail.color = OneGunUI.color("cyan")
		tail.z_index = 19
		_bubble_layer.add_child(tail)
	entry = {
		"panel": panel,
		"tail": tail,
		"name_label": name_label,
		"message_label": message_label,
		"expires_msec": Time.get_ticks_msec() + int(BUBBLE_SECONDS * 1000.0),
	}
	var bubble_text := message
	if bubble_text.length() > BUBBLE_MAX_CHARACTERS:
		bubble_text = bubble_text.left(BUBBLE_MAX_CHARACTERS - 3) + "..."
	name_label.text = sender_name.to_upper()
	message_label.text = bubble_text
	panel.visible = false
	panel.call_deferred("reset_size")
	_bubbles[peer_id] = entry
	set_process(true)


func _clear_bubbles() -> void:
	for peer_id in _bubbles:
		var entry: Dictionary = _bubbles[peer_id]
		var panel := entry.get("panel") as PanelContainer
		var tail := entry.get("tail") as Polygon2D
		if panel != null and is_instance_valid(panel):
			panel.queue_free()
		if tail != null and is_instance_valid(tail):
			tail.queue_free()
	_bubbles.clear()
	set_process(false)


func _show_notification(sender_name: String, message: String) -> void:
	_ensure_ui()
	while _notifications.size() >= MAX_ACTIVE_NOTIFICATIONS:
		_remove_notification(_notifications.front())
	var card := PanelContainer.new()
	card.custom_minimum_size.x = NOTIFICATION_WIDTH
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(OneGunUI.color("well"), 0.96),
		OneGunUI.color("cyan"),
		OneGunUI.RADIUS_SECTION,
		OneGunUI.BORDER_THIN,
		5,
		9,
		Color(0.0, 0.0, 0.0, 0.46)
	))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	var name_label := OneGunUI.make_label(
		sender_name.to_upper(), OneGunUI.TEXT_XS, "gold", true)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)
	var message_label := OneGunUI.make_label(message, OneGunUI.TEXT_S, "text")
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(message_label)
	_notification_stack.add_child(card)
	_notifications.append(card)
	card.modulate.a = 0.0
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_notification_tweens[card] = tween
	tween.tween_property(card, "modulate:a", 1.0, 0.12)
	tween.tween_interval(TRANSIENT_SECONDS)
	tween.tween_property(card, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(_remove_notification.bind(card, false))


func _remove_notification(card: Control, stop_tween := true) -> void:
	if stop_tween:
		var tween := _notification_tweens.get(card) as Tween
		if tween != null and tween.is_valid():
			tween.kill()
	_notification_tweens.erase(card)
	_notifications.erase(card)
	if card != null and is_instance_valid(card):
		card.queue_free()


func _clear_notifications() -> void:
	for card in _notifications.duplicate():
		_remove_notification(card)


func _refresh_history() -> void:
	if not _ui_built:
		return
	var context := _active_context()
	_display_context = context
	_title.text = "ONE GUN COMMS  /  %s" % context.to_upper()
	var lines: PackedStringArray = []
	for entry_value in _messages_by_context.get(context, []):
		var entry: Dictionary = entry_value
		lines.append("%s: %s" % [entry.get("sender_name", "Player"), entry.get("message", "")])
	_history.text = "\n".join(lines)
	_history.call_deferred("scroll_to_line", maxi(_history.get_line_count() - 1, 0))


func _active_context() -> String:
	if not NetworkManager.is_online():
		return "lobby"
	var context := NetworkManager.chat_context_for_peer(NetworkManager.local_id())
	return context if context != "" else "lobby"


func _on_lobby_changed() -> void:
	if not NetworkManager.is_online():
		_on_chat_session_reset()
		return
	var context := _active_context()
	if _display_context != "" and context != _display_context:
		_window_open = false
		_clear_bubbles()
		_clear_notifications()
		if _typing:
			_finish_typing(false)
		if _panel != null:
			_panel.visible = false
	_display_context = context
	_refresh_history()


func _on_chat_session_reset() -> void:
	_messages_by_context.clear()
	_clear_bubbles()
	_clear_notifications()
	_display_context = ""
	_window_open = false
	if _typing:
		_finish_typing(false)
	if _panel != null:
		_panel.visible = false
	if _input_blocker != null:
		_input_blocker.visible = false
