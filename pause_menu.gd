extends Control

# Context-aware pause cabinet. Local play truly pauses the tree; online play is
# a local overlay and leaves simulation/networking alive. Destructive actions
# use the shared inline two-click confirmation, never a modal popup.

var settings_overlay: Control = null
var _armed_button: OneGunConfirmButton = null
var _capture_role := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_capture_role = OS.get_environment("ONEGUN_UI_CAPTURE_STATE")
	visible = false
	_build_ui()
	PauseManager.register_pause_menu(self)
	if _capture_role in ["pause_local", "pause_host", "pause_guest"]:
		visible = true
		UICapture.maybe_capture(self, _capture_role, 2.5)


func _exit_tree() -> void:
	PauseManager.unregister_pause_menu(self)


func _is_online_view() -> bool:
	return NetworkManager.is_online() or _capture_role in ["pause_host", "pause_guest"]


func _is_host_view() -> bool:
	return (_capture_role == "pause_host") or (_capture_role != "pause_guest" and NetworkManager.is_host())


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()
	var veil := ColorRect.new()
	veil.color = Color(OneGunUI.color("canvas"), 0.70 if _is_online_view() else 0.76)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)

	var cabinet := OneGunCabinet.new()
	cabinet.name = "PauseCabinet"
	cabinet.variant = OneGunCabinet.Variant.CABINET
	cabinet.content_padding = OneGunUI.SPACE_L
	cabinet.set_anchors_preset(Control.PRESET_CENTER)
	var height := 470.0 if not _is_online_view() or _is_host_view() else 395.0
	cabinet.offset_left = -285.0
	cabinet.offset_top = -height * 0.5
	cabinet.offset_right = 285.0
	cabinet.offset_bottom = height * 0.5
	add_child(cabinet)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	cabinet.get_content().add_child(column)
	var title := "GAME PAUSED" if not _is_online_view() else "MATCH MENU"
	var heading := OneGunUI.make_heading(title, OneGunUI.TEXT_TITLE)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var status := "LOCAL MATCH PAUSED" if not _is_online_view() else "MATCH STILL IN PROGRESS"
	var status_label := OneGunUI.make_label(status, OneGunUI.TEXT_XS, "gold" if not _is_online_view() else "red", true)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status_label)
	column.add_child(HSeparator.new())

	var metadata := OneGunUI.make_label(_metadata_text(), OneGunUI.TEXT_S, "muted")
	metadata.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(metadata)
	_add_action(column, "RESUME", PauseManager.resume)
	_add_action(column, "PLAYER SETTINGS", _open_settings_overlay)
	if not _is_online_view():
		_add_destructive(column, "RETURN TO LOBBY", "CONFIRM RETURN", "res://game_setup.tscn")
		_add_destructive(column, "RETURN TO MAIN MENU", "CONFIRM LEAVE", "res://main_menu.tscn")
	elif _is_host_view():
		_add_destructive(column, "RETURN TO LOBBY  •  HOST ONLY", "CONFIRM FOR ALL", "res://game_setup.tscn")
		_add_destructive(column, "LEAVE MATCH", "CONFIRM LEAVE", "res://main_menu.tscn")
	else:
		_add_destructive(column, "LEAVE MATCH", "CONFIRM LEAVE", "res://main_menu.tscn")
	column.add_child(HSeparator.new())
	var footer_text := "ESC  RESUME  •  ENTER  SELECT" if not _is_online_view() else "GAMEPLAY CONTINUES ONLINE  •  ESC  RESUME"
	var footer := OneGunUI.make_label(footer_text, OneGunUI.TEXT_XS, "muted", true)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer)


func _metadata_text() -> String:
	var scene_path := get_tree().current_scene.scene_file_path if get_tree().current_scene != null else ""
	if NetworkManager.pending_map_path != "": scene_path = NetworkManager.pending_map_path
	var map_index := MapRegistry.find_index_by_path(scene_path)
	var map_name := str(MapRegistry.get_map(map_index).get("name", "CURRENT ARENA")).to_upper()
	var round_manager := get_tree().current_scene.get_node_or_null("RoundManager") if get_tree().current_scene != null else null
	var round_number := int(round_manager.get("round_number")) if round_manager != null else 1
	var mode := "TEAMS" if GameConfig.teams_enabled else "FREE FOR ALL"
	return "%s  •  ROUND %d  •  %s" % [map_name, round_number, mode]


func _add_action(parent: VBoxContainer, label_text: String, callback: Callable) -> void:
	var button := OneGunButton.new()
	button.variant = "gold" if label_text == "RESUME" else "navy"
	button.text = label_text
	button.custom_minimum_size = Vector2(0, 48)
	button.pressed.connect(callback)
	parent.add_child(button)


func _add_destructive(parent: VBoxContainer, label_text: String, confirm_text: String, target: String) -> void:
	var button := OneGunConfirmButton.new()
	button.variant = "navy"
	button.text = label_text
	button.confirm_text = confirm_text
	button.custom_minimum_size = Vector2(0, 48)
	button.armed_changed.connect(_on_confirm_armed.bind(button))
	button.confirmed.connect(_commit_exit.bind(target))
	parent.add_child(button)


func _on_confirm_armed(armed: bool, button: OneGunConfirmButton) -> void:
	if armed:
		if _armed_button != null and _armed_button != button: _armed_button.reset_confirm()
		_armed_button = button
		PauseManager.set_escape_override(_cancel_armed_confirmation)
	elif _armed_button == button:
		_armed_button = null
		if settings_overlay == null: PauseManager.clear_escape_override()


func _cancel_armed_confirmation() -> void:
	if _armed_button != null: _armed_button.reset_confirm()
	_armed_button = null
	if settings_overlay == null: PauseManager.clear_escape_override()


func _open_settings_overlay() -> void:
	if settings_overlay != null: return
	_cancel_armed_confirmation()
	settings_overlay = load("res://player_settings.tscn").instantiate()
	settings_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	settings_overlay.is_overlay = true
	add_child(settings_overlay)
	settings_overlay.settings_closed.connect(_close_settings_overlay)
	PauseManager.set_escape_override(_close_settings_overlay)


func _close_settings_overlay() -> void:
	if settings_overlay == null: return
	settings_overlay.queue_free()
	settings_overlay = null
	PauseManager.clear_escape_override()


func _commit_exit(target_scene: String) -> void:
	PauseManager.clear_escape_override()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if NetworkManager.is_online():
		if target_scene == "res://game_setup.tscn" and NetworkManager.is_host():
			NetworkManager.host_return_everyone_to_lobby()
		else:
			NetworkManager.leave_online_to_main_menu()
	else:
		PauseManager.reset_pause_state()
		get_tree().change_scene_to_file(target_scene)
