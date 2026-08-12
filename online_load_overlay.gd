extends CanvasLayer

var _panel: PanelContainer
var _status_list: VBoxContainer
var _hint: Label


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	NetworkManager.match_load_status_changed.connect(_refresh)
	NetworkManager.match_readiness_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if NetworkManager.match_load_status_changed.is_connected(_refresh):
		NetworkManager.match_load_status_changed.disconnect(_refresh)
	if NetworkManager.match_readiness_changed.is_connected(_refresh):
		NetworkManager.match_readiness_changed.disconnect(_refresh)


func _build_ui() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0.025, 0.03, 0.08, 0.86)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -360
	_panel.offset_right = 360
	_panel.offset_top = -270
	_panel.offset_bottom = 270
	_panel.add_theme_stylebox_override("panel", ThemeManager.panel(Color(0.05, 0.06, 0.12, 0.98), ThemeManager.ACCENT_GOLD, 14, 2))
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(OneGunUI.make_heading("LOADING MATCH", OneGunUI.TEXT_TITLE, "gold"))
	var map_index := MapRegistry.find_index_by_path(NetworkManager.pending_map_path)
	column.add_child(OneGunUI.make_label(str(MapRegistry.get_map(map_index).get("name", NetworkManager.pending_map_path)), OneGunUI.TEXT_S, "muted"))
	_status_list = VBoxContainer.new()
	_status_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_status_list)
	_hint = OneGunUI.make_label("Waiting for every active participant to finish loading…", OneGunUI.TEXT_S, "muted")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint)
	if NetworkManager.is_host():
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 10)
		column.add_child(actions)
		var retry := OneGunButton.new()
		retry.text = "RETRY FAILED"
		retry.variant = "gold"
		retry.set_meta("action_id", "retry_load")
		retry.pressed.connect(NetworkManager.retry_failed_match_loads)
		actions.add_child(retry)
		var remove := OneGunButton.new()
		remove.text = "REMOVE & CONTINUE"
		remove.variant = "red"
		remove.set_meta("action_id", "remove_failed_load")
		remove.pressed.connect(_remove_failed)
		actions.add_child(remove)
		var back := OneGunButton.new()
		back.text = "RETURN TO LOBBY"
		back.variant = "navy"
		back.set_meta("action_id", "return_lobby")
		back.pressed.connect(NetworkManager.host_return_everyone_to_lobby)
		actions.add_child(back)


func _refresh() -> void:
	if _status_list == null:
		return
	for child in _status_list.get_children():
		child.queue_free()
	var any_failed := false
	for peer_id in NetworkManager.match_participant_peers:
		var status: Dictionary = NetworkManager.match_load_status.get(peer_id, {"state": "loading", "attempt": 1, "reason": ""})
		var state := str(status.get("state", "loading"))
		any_failed = any_failed or state == "failed"
		var name := NetworkManager.peer_name(int(peer_id))
		var reason := str(status.get("reason", ""))
		var text := "%s  •  %s  •  ATTEMPT %d" % [name, state.to_upper(), int(status.get("attempt", 1))]
		if reason != "":
			text += "\n    %s" % reason
		var label := OneGunUI.make_label(text, OneGunUI.TEXT_S, "red" if state == "failed" else ("green" if state == "ready" else "cyan"), true)
		_status_list.add_child(label)
	_hint.text = "Choose a recovery action." if any_failed and NetworkManager.is_host() else "Waiting for every active participant to finish loading…"
	if NetworkManager.are_all_match_peers_ready():
		queue_free()


func _remove_failed() -> void:
	if not NetworkManager.remove_failed_match_peers_and_continue():
		_hint.text = "Cannot continue: at least two active players and two represented teams (in team mode) must remain."
