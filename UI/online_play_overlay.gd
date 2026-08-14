class_name OneGunOnlinePlayOverlay
extends OneGunCabinet

const BuildInfo = preload("res://build_info.gd")

# Phase 4 online entry cabinet. Lobby rows come only from NetworkManager's
# real Tailscale/loopback discovery responder; no sample data is created here.

signal close_requested
signal session_started

enum Page { BROWSER, HOST, CODE }

var _page := Page.BROWSER
var _page_root: VBoxContainer
var _lobbies: Array = []
var _selected_lobby: Dictionary = {}
var _rows: Array[OneGunLobbyRow] = []
var _rows_box: VBoxContainer
var _browser_state: OneGunStatusPanel
var _search_field: LineEdit
var _join_selected_button: OneGunButton
var _selection_label: Label
var _refresh_button: OneGunButton
var _host_name: LineEdit
var _host_error: OneGunInlineError
var _host_privacy := "public"
var _host_max_players := NetworkManager.MAX_PEERS
var _host_code: LineEdit
var _private_code_section: VBoxContainer
var _privacy_buttons: Dictionary = {}
var _code_field: LineEdit
var _code_error: OneGunInlineError
var _busy := false


func _ready() -> void:
	super()
	variant = OneGunCabinet.Variant.CABINET
	content_padding = OneGunUI.SPACE_L
	show_bolts = true
	_connect_network_signals()
	_build_shell()
	_show_browser()


func _exit_tree() -> void:
	_disconnect_network_signals()


func open(capture_state := "") -> void:
	match capture_state:
		"host": _show_host()
		"private":
			_show_host()
			_set_host_privacy("private")
		"code": _show_code()
		_:
			_show_browser()


func handle_cancel() -> void:
	if _page == Page.BROWSER:
		close_requested.emit()
	else:
		_show_browser(false)


func initial_focus() -> Control:
	match _page:
		Page.HOST: return _host_name
		Page.CODE: return _code_field
		_: return _search_field


func _connect_network_signals() -> void:
	if not NetworkManager.lobby_list_updated.is_connected(_on_lobby_list_updated):
		NetworkManager.lobby_list_updated.connect(_on_lobby_list_updated)
	if not NetworkManager.lobby_list_failed.is_connected(_on_lobby_list_failed):
		NetworkManager.lobby_list_failed.connect(_on_lobby_list_failed)
	if not NetworkManager.connection_succeeded.is_connected(_on_connection_succeeded):
		NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	if not NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.connect(_on_connection_failed)
	if not NetworkManager.lobby_discovery_failed.is_connected(_on_discovery_failed):
		NetworkManager.lobby_discovery_failed.connect(_on_discovery_failed)
	if not NetworkManager.server_disconnected.is_connected(_on_server_disconnected):
		NetworkManager.server_disconnected.connect(_on_server_disconnected)
	if not NetworkManager.compatibility_rejected.is_connected(_on_compatibility_rejected):
		NetworkManager.compatibility_rejected.connect(_on_compatibility_rejected)


func _disconnect_network_signals() -> void:
	for pair in [
		[NetworkManager.lobby_list_updated, _on_lobby_list_updated],
		[NetworkManager.lobby_list_failed, _on_lobby_list_failed],
		[NetworkManager.connection_succeeded, _on_connection_succeeded],
		[NetworkManager.connection_failed, _on_connection_failed],
		[NetworkManager.lobby_discovery_failed, _on_discovery_failed],
		[NetworkManager.server_disconnected, _on_server_disconnected],
		[NetworkManager.compatibility_rejected, _on_compatibility_rejected],
	]:
		var network_signal: Signal = pair[0]
		var callback: Callable = pair[1]
		if network_signal.is_connected(callback):
			network_signal.disconnect(callback)


func _build_shell() -> void:
	_page_root = VBoxContainer.new()
	_page_root.name = "OnlinePage"
	_page_root.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	get_content().add_child(_page_root)


func _clear_page() -> void:
	for child in _page_root.get_children():
		child.free()
	_rows.clear()
	_rows_box = null
	_browser_state = null
	_search_field = null
	_join_selected_button = null
	_selection_label = null
	_refresh_button = null
	_host_name = null
	_host_error = null
	_host_code = null
	_private_code_section = null
	_privacy_buttons.clear()
	_code_field = null
	_code_error = null


func _build_header(title: String, badge: String, show_back := false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	_page_root.add_child(row)
	if show_back:
		var back := OneGunButton.new()
		back.variant = "navy"
		back.text = "BACK"
		back.font_size = OneGunUI.TEXT_S
		back.pressed.connect(func() -> void: _show_browser(false))
		row.add_child(back)
	var title_label := OneGunUI.make_heading(title, OneGunUI.TEXT_TITLE, "gold")
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	var badge_panel := PanelContainer.new()
	var badge_style := OneGunUI.style_box(Color(OneGunUI.color("cyan"), 0.14), OneGunUI.color("cyan"), OneGunUI.RADIUS_CHIP, 1)
	badge_style.content_margin_left = 12
	badge_style.content_margin_right = 12
	badge_style.content_margin_top = 5
	badge_style.content_margin_bottom = 5
	badge_panel.add_theme_stylebox_override("panel", badge_style)
	badge_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge_panel.add_child(OneGunUI.make_label(badge, OneGunUI.TEXT_XS, "cyan", true))
	row.add_child(badge_panel)
	var close := OneGunButton.new()
	close.variant = "navy"
	close.text = "CLOSE"
	close.font_size = OneGunUI.TEXT_S
	close.pressed.connect(close_requested.emit)
	row.add_child(close)


func _show_browser(refresh := true) -> void:
	_page = Page.BROWSER
	_busy = false
	_clear_page()
	_build_header("ONLINE PLAY", "TAILSCALE LOBBIES")
	var reachability := NetworkManager.get_tailscale_ip()
	var reachability_text := "TAILSCALE READY — REAL PEER DISCOVERY ENABLED" if reachability != "" else "TAILSCALE NOT DETECTED — LOOPBACK AND DIRECT ADDRESS ONLY"
	var reachability_role := "green" if reachability != "" else "gold"
	_page_root.add_child(OneGunUI.make_label(reachability_text, OneGunUI.TEXT_S, reachability_role, true))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	_page_root.add_child(actions)
	var host := _make_button("HOST LOBBY", "gold", _show_host)
	host.tooltip_text = "Create a public or private One Gun lobby"
	actions.add_child(host)
	var quick := _make_button("QUICK JOIN", "blue", _quick_join)
	quick.tooltip_text = "Join the first available public lobby"
	actions.add_child(quick)
	var code := _make_button("JOIN BY CODE", "purple", _show_code)
	code.tooltip_text = "Find a public or private host using its share code"
	actions.add_child(code)
	var action_spacer := Control.new()
	action_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(action_spacer)
	_refresh_button = _make_button("REFRESH", "navy", _refresh_lobbies)
	actions.add_child(_refresh_button)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	_page_root.add_child(filters)
	_search_field = _make_line_edit("Search real discovered lobbies", 32)
	_search_field.name = "LobbySearch"
	_search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_field.text_changed.connect(func(_value: String) -> void: _render_lobbies())
	filters.add_child(_search_field)
	var privacy_filter := OneGunUI.make_dropdown(PackedStringArray(["ALL DISCOVERABLE", "PUBLIC"]))
	privacy_filter.disabled = true
	privacy_filter.tooltip_text = "Private lobbies are intentionally absent from discovery; use Join by Code."
	filters.add_child(privacy_filter)
	var mode_filter := OneGunUI.make_dropdown(PackedStringArray(["ONE GUN"]))
	mode_filter.disabled = true
	mode_filter.tooltip_text = "One Gun is the only implemented online mode."
	filters.add_child(mode_filter)

	var list_well := OneGunCabinet.new()
	list_well.variant = OneGunCabinet.Variant.WELL
	list_well.content_padding = OneGunUI.SPACE_M
	list_well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_root.add_child(list_well)
	var list_stack := VBoxContainer.new()
	list_stack.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	list_well.get_content().add_child(list_stack)
	var headings := HBoxContainer.new()
	headings.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	list_stack.add_child(headings)
	headings.add_child(_fixed_label("", 24))
	var lobby_heading := OneGunUI.make_label("LOBBY", OneGunUI.TEXT_XS, "muted", true)
	lobby_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headings.add_child(lobby_heading)
	headings.add_child(_fixed_label("MODE", 90))
	headings.add_child(_fixed_label("PLAYERS", 64))
	headings.add_child(_fixed_label("STATUS", 116))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_stack.add_child(scroll)
	var content_stack := VBoxContainer.new()
	content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_stack.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	scroll.add_child(content_stack)
	_browser_state = OneGunStatusPanel.new()
	_browser_state.retry_requested.connect(_refresh_lobbies)
	content_stack.add_child(_browser_state)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	content_stack.add_child(_rows_box)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	_page_root.add_child(footer)
	_selection_label = OneGunUI.make_label("SELECT A LOBBY TO SEE ITS SUMMARY", OneGunUI.TEXT_S, "muted")
	_selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_selection_label)
	_join_selected_button = _make_button("JOIN SELECTED", "green", _join_selected)
	_join_selected_button.disabled = true
	footer.add_child(_join_selected_button)
	if refresh:
		_refresh_lobbies()
	else:
		_render_lobbies()
	_search_field.grab_focus.call_deferred()


func _refresh_lobbies() -> void:
	if _busy:
		return
	_busy = true
	_selected_lobby.clear()
	if _refresh_button != null:
		_refresh_button.disabled = true
	if _browser_state != null:
		_browser_state.visible = true
		_browser_state.show_loading("Probing your Tailscale peers for One Gun hosts…")
	if _rows_box != null:
		_rows_box.visible = false
	NetworkManager.discover_lobbies()


func _on_lobby_list_updated(lobbies: Array) -> void:
	_lobbies = lobbies.duplicate(true)
	_busy = false
	if _page != Page.BROWSER:
		return
	if _refresh_button != null:
		_refresh_button.disabled = false
	_render_lobbies()


func _on_lobby_list_failed(message: String) -> void:
	_busy = false
	if _page != Page.BROWSER or _browser_state == null:
		return
	_refresh_button.disabled = false
	_rows_box.visible = false
	_browser_state.visible = true
	_browser_state.show_error("DISCOVERY UNAVAILABLE", message, true)


func _render_lobbies() -> void:
	if _rows_box == null or _browser_state == null:
		return
	for child in _rows_box.get_children():
		child.free()
	_rows.clear()
	_selected_lobby.clear()
	var query := _search_field.text.strip_edges().to_lower() if _search_field != null else ""
	var visible_lobbies: Array = []
	for lobby in _lobbies:
		if query != "" and not str(lobby.get("name", "")).to_lower().contains(query):
			continue
		visible_lobbies.append(lobby)
	if visible_lobbies.is_empty():
		_rows_box.visible = false
		_browser_state.visible = true
		if _lobbies.is_empty():
			_browser_state.show_empty("NO PUBLIC LOBBIES FOUND", "Host one now, refresh, or use Join by Code for a private lobby.")
		else:
			_browser_state.show_empty("NO MATCHING LOBBIES", "Clear the search field or try a different lobby name.")
	else:
		_browser_state.visible = false
		_rows_box.visible = true
		for lobby in visible_lobbies:
			var row := OneGunLobbyRow.new()
			_rows_box.add_child(row)
			var privacy := OneGunLobbyRow.Privacy.PRIVATE if str(lobby.get("privacy", "public")) == "private" else OneGunLobbyRow.Privacy.PUBLIC
			var joinability := _row_joinability(str(lobby.get("joinability", "unknown")))
			row.set_lobby(str(lobby.get("name", "Lobby")), privacy,
				int(lobby.get("players", 1)), int(lobby.get("max_players", NetworkManager.MAX_PEERS)),
				str(lobby.get("mode", "One Gun")), joinability)
			row.selected.connect(_select_lobby.bind(lobby, row))
			row.activated.connect(_activate_lobby.bind(lobby))
			_rows.append(row)
	_update_selected_footer()


func _select_lobby(lobby: Dictionary, selected_row: OneGunLobbyRow) -> void:
	_selected_lobby = lobby.duplicate(true)
	for row in _rows:
		row.is_selected = row == selected_row
	_update_selected_footer()


func _activate_lobby(lobby: Dictionary) -> void:
	_selected_lobby = lobby.duplicate(true)
	_join_selected()


func _update_selected_footer() -> void:
	if _selection_label == null or _join_selected_button == null:
		return
	if _selected_lobby.is_empty():
		_selection_label.text = "SELECT A LOBBY TO SEE ITS SUMMARY"
		_join_selected_button.disabled = true
		return
	var state := str(_selected_lobby.get("joinability", "unknown"))
	_selection_label.text = "%s  /  %d OF %d PLAYERS  /  %s" % [
		str(_selected_lobby.get("name", "Lobby")).to_upper(),
		int(_selected_lobby.get("players", 1)),
		int(_selected_lobby.get("max_players", NetworkManager.MAX_PEERS)),
		state.replace("_", " ").to_upper()]
	_join_selected_button.disabled = state not in ["joinable", "in_progress"] or _busy
	if state == "incompatible":
		_selection_label.text = str(_selected_lobby.get("compatibility_error", "Incompatible version"))


func _quick_join() -> void:
	for lobby in _lobbies:
		if str(lobby.get("joinability", "")) in ["joinable", "in_progress"]:
			_selected_lobby = lobby.duplicate(true)
			_join_selected()
			return
	if _browser_state != null:
		_browser_state.visible = true
		_rows_box.visible = false
		_browser_state.show_empty("NO JOINABLE LOBBY", "Refresh, host a lobby, or join a private lobby by code.")


func _join_selected() -> void:
	if _selected_lobby.is_empty() or _busy:
		return
	_busy = true
	_set_browser_connecting("CONNECTING TO %s…" % str(_selected_lobby.get("name", "LOBBY")).to_upper())
	if not NetworkManager.join_discovered_lobby(_selected_lobby) and _busy:
		_on_connection_failed()


func _set_browser_connecting(message: String) -> void:
	if _browser_state == null:
		return
	_browser_state.visible = true
	_rows_box.visible = false
	_browser_state.show_loading(message)
	if _join_selected_button != null:
		_join_selected_button.disabled = true


func _show_host() -> void:
	_page = Page.HOST
	_busy = false
	_clear_page()
	_build_header("HOST LOBBY", "ONE GUN", true)
	_add_form_heading("LOBBY IDENTITY", "Your player name seeds a useful default; edit it freely for this session.")
	_host_name = _make_line_edit("Lobby name", 32)
	_host_name.name = "HostLobbyName"
	_host_name.text = "%s's Lobby" % NetworkManager.local_name()
	_page_root.add_child(_host_name)
	_host_error = OneGunInlineError.new()
	_page_root.add_child(_host_error)

	_add_form_heading("PRIVACY", "Public lobbies appear in the browser. Private lobbies answer only to their share code.")
	var privacy_row := HBoxContainer.new()
	privacy_row.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	_page_root.add_child(privacy_row)
	for option in [["public", "PUBLIC"], ["friends", "FRIENDS ONLY"], ["private", "PRIVATE"]]:
		var privacy_button := OneGunButton.new()
		privacy_button.text = option[1]
		privacy_button.variant = "navy"
		privacy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		privacy_button.disabled = option[0] == "friends"
		privacy_button.tooltip_text = "Unavailable until One Gun has a friend identity service." if privacy_button.disabled else "Set lobby privacy to %s" % option[1]
		privacy_button.pressed.connect(_set_host_privacy.bind(option[0]))
		privacy_row.add_child(privacy_button)
		_privacy_buttons[option[0]] = privacy_button

	var capacity_row := HBoxContainer.new()
	capacity_row.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	_page_root.add_child(capacity_row)
	var capacity_labels := VBoxContainer.new()
	capacity_labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	capacity_row.add_child(capacity_labels)
	capacity_labels.add_child(OneGunUI.make_label("MAX PLAYERS", OneGunUI.TEXT_S, "text", true))
	capacity_labels.add_child(OneGunUI.make_label("Host included. Supported range: 2–10.", OneGunUI.TEXT_XS, "muted"))
	var capacity := OneGunStepper.new()
	capacity.min_value = 2
	capacity.max_value = NetworkManager.MAX_PEERS
	capacity.value = _host_max_players
	capacity.value_changed.connect(func(value: int) -> void: _host_max_players = value)
	capacity_row.add_child(capacity)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	_page_root.add_child(mode_row)
	var mode_label := OneGunUI.make_label("GAME MODE", OneGunUI.TEXT_S, "text", true)
	mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(mode_label)
	var mode := OneGunUI.make_dropdown(PackedStringArray(["ONE GUN"]))
	mode.disabled = true
	mode.tooltip_text = "One Gun is the only implemented online mode."
	mode_row.add_child(mode)

	_private_code_section = VBoxContainer.new()
	_private_code_section.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	_page_root.add_child(_private_code_section)
	_private_code_section.add_child(OneGunUI.make_label("PRIVATE SHARE CODE", OneGunUI.TEXT_S, "gold", true))
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	_private_code_section.add_child(code_row)
	_host_code = _make_line_edit("4–12 letters or digits", 12)
	_host_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_code.text_changed.connect(_normalize_host_code)
	code_row.add_child(_host_code)
	var generate := _make_button("GENERATE", "navy", func() -> void: _host_code.text = _random_code())
	code_row.add_child(generate)
	var code_help := OneGunUI.make_label("This gates discovery inside your tailnet. Trusted direct-IP fallback remains available.", OneGunUI.TEXT_XS, "muted")
	code_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_private_code_section.add_child(code_help)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_root.add_child(spacer)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	_page_root.add_child(footer)
	var cancel := _make_button("CANCEL", "navy", func() -> void: _show_browser(false))
	footer.add_child(cancel)
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_spacer)
	var submit := _make_button("HOST LOBBY", "green", _host_lobby)
	footer.add_child(submit)
	_set_host_privacy(_host_privacy)
	_host_name.grab_focus.call_deferred()


func _set_host_privacy(value: String) -> void:
	if value == "friends":
		return
	_host_privacy = value
	for key in _privacy_buttons:
		var button: OneGunButton = _privacy_buttons[key]
		button.variant = "gold" if key == value else "navy"
	if _private_code_section != null:
		_private_code_section.visible = value == "private"
	if value == "private" and _host_code != null and _host_code.text == "":
		_host_code.text = _random_code()


func _normalize_host_code(value: String) -> void:
	var cleaned := _clean_code(value)
	if cleaned != value:
		_host_code.set_text(cleaned)
		_host_code.caret_column = cleaned.length()


func _host_lobby() -> void:
	if _busy:
		return
	_host_error.clear()
	var name_value := _host_name.text.strip_edges()
	if name_value.length() < 2:
		_host_error.show_error("Lobby names must contain at least two characters.")
		_host_name.grab_focus()
		return
	var share_code := _clean_code(_host_code.text) if _host_privacy == "private" else _random_code()
	if _host_privacy == "private" and share_code.length() < 4:
		_host_error.show_error("Private share codes must contain 4–12 supported characters.")
		_host_code.grab_focus()
		return
	_busy = true
	var options := {"privacy": _host_privacy, "max_players": _host_max_players, "share_code": share_code}
	if not NetworkManager.host_game(NetworkManager.DEFAULT_PORT, name_value, options):
		_busy = false
		_host_error.show_error("Could not host on UDP 24545. Check firewall access and whether the port is already in use.")
		return
	if not GameConfig.lobby_settings_dirty:
		GameConfig.reset_match_settings_to_defaults()
	GameConfig.split_screen_enabled = false
	session_started.emit()


func _show_code() -> void:
	_page = Page.CODE
	_busy = false
	_clear_page()
	_build_header("JOIN BY CODE", "PRIVATE ENTRY", true)
	_add_form_heading("LOBBY CODE", "Paste a private code, direct Tailscale address, or server hostname with its public port.")
	_code_field = _make_line_edit("LOBBY CODE OR SERVER:PORT", 128)
	_code_field.name = "JoinByCode"
	_code_field.text_changed.connect(_normalize_join_value)
	_page_root.add_child(_code_field)
	_code_error = OneGunInlineError.new()
	_page_root.add_child(_code_error)
	var utilities := HBoxContainer.new()
	utilities.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	_page_root.add_child(utilities)
	utilities.add_child(_make_button("PASTE", "navy", func() -> void: _code_field.text = DisplayServer.clipboard_get().strip_edges()))
	utilities.add_child(_make_button("CLEAR", "navy", func() -> void: _code_field.clear(); _code_field.grab_focus()))
	var summary := OneGunCabinet.new()
	summary.variant = OneGunCabinet.Variant.WELL
	summary.content_padding = OneGunUI.SPACE_L
	summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_root.add_child(summary)
	var summary_column := VBoxContainer.new()
	summary_column.alignment = BoxContainer.ALIGNMENT_CENTER
	summary_column.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	summary.get_content().add_child(summary_column)
	summary_column.add_child(OneGunUI.make_heading("SECURE DISCOVERY", OneGunUI.TEXT_L, "purple"))
	var explanation := OneGunUI.make_label("The code is sent only in direct probes to peers already inside your Tailscale network. It is not published as a lobby row.", OneGunUI.TEXT_S, "muted")
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_column.add_child(explanation)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	_page_root.add_child(footer)
	footer.add_child(_make_button("BACK", "navy", func() -> void: _show_browser(false)))
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_spacer)
	footer.add_child(_make_button("JOIN LOBBY", "green", _join_by_code))
	_code_field.text_submitted.connect(func(_value: String) -> void: _join_by_code())
	_code_field.grab_focus.call_deferred()


func _normalize_join_value(value: String) -> void:
	if value.contains(".") or value.contains(":"):
		return
	var cleaned := _clean_code(value)
	if cleaned != value:
		_code_field.set_text(cleaned)
		_code_field.caret_column = cleaned.length()


func _join_by_code() -> void:
	if _busy:
		return
	_code_error.clear()
	var value := _code_field.text.strip_edges()
	var endpoint := NetworkManager.parse_direct_endpoint(value)
	if not endpoint.is_empty():
		_busy = true
		_code_field.editable = false
		if not NetworkManager.join_game(str(endpoint["host"]), int(endpoint["port"])):
			_busy = false
			_code_field.editable = true
			_code_error.show_error("The direct connection could not start.")
		return
	if value.contains(".") or value.contains(":"):
		_code_error.show_error("Enter the server as hostname:port, for example server.pr.edgegap.net:31504.")
		_code_field.grab_focus()
		return
	var code := _clean_code(value)
	if code.length() < 4:
		_code_error.show_error("Enter a 4–12 character lobby code or a direct server endpoint.")
		_code_field.grab_focus()
		return
	_busy = true
	_code_field.editable = false
	if not NetworkManager.join_lobby_by_code(code):
		_busy = false
		_code_field.editable = true
		_code_error.show_error("Enter a valid lobby code.")


func _on_connection_succeeded() -> void:
	_busy = false
	GameConfig.split_screen_enabled = false
	session_started.emit()


func _on_compatibility_rejected(reason: String, detail: String) -> void:
	_busy = false
	var is_version_mismatch := BuildInfo.is_version_rejection(reason)
	var title := "VERSION MISMATCH" if is_version_mismatch else "CONNECTION REJECTED"
	var message := BuildInfo.version_mismatch_message(detail) if is_version_mismatch else detail
	if _page == Page.CODE and _code_error != null:
		_code_field.editable = true
		_code_error.show_error("%s\n\n%s" % [title, message])
	if _page == Page.BROWSER and _browser_state != null:
		_browser_state.visible = true
		if _rows_box != null:
			_rows_box.visible = false
		_browser_state.show_error(title, message, true)


func _on_connection_failed() -> void:
	_busy = false
	if _page == Page.CODE and _code_error != null:
		_code_field.editable = true
		_code_error.show_error("Connection failed. Confirm the host is still online and accepting players.")
	elif _page == Page.BROWSER and _browser_state != null:
		_rows_box.visible = false
		_browser_state.visible = true
		_browser_state.show_error("CONNECTION FAILED", "The selected host did not accept the connection.", true)


func _on_discovery_failed(message: String) -> void:
	_busy = false
	if _page == Page.CODE and _code_error != null:
		_code_field.editable = true
		_code_error.show_error(message)
	elif _page == Page.BROWSER and _browser_state != null:
		_rows_box.visible = false
		_browser_state.visible = true
		_browser_state.show_error("LOBBY NOT FOUND", message, true)


func _on_server_disconnected() -> void:
	_busy = false
	if _page == Page.BROWSER and _browser_state != null:
		_rows_box.visible = false
		_browser_state.visible = true
		_browser_state.show_error("DISCONNECTED", "The host ended the online session.", true)


func _add_form_heading(title: String, description: String) -> void:
	_page_root.add_child(OneGunUI.make_heading(title, OneGunUI.TEXT_L, "gold"))
	var label := OneGunUI.make_label(description, OneGunUI.TEXT_S, "muted")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_root.add_child(label)


func _make_button(text: String, variant: String, callback: Callable) -> OneGunButton:
	var button := OneGunButton.new()
	button.variant = variant
	button.text = text
	button.pressed.connect(callback)
	return button


func _make_line_edit(placeholder: String, max_length: int) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = max_length
	field.custom_minimum_size = Vector2(0, 48)
	field.focus_mode = Control.FOCUS_ALL
	field.add_theme_font_size_override("font_size", OneGunUI.TEXT_M)
	field.add_theme_color_override("font_color", OneGunUI.color("text"))
	field.add_theme_color_override("font_placeholder_color", OneGunUI.color("muted"))
	field.add_theme_color_override("caret_color", OneGunUI.color("cyan"))
	var normal := OneGunUI.style_box(OneGunUI.color("well"), OneGunUI.color("border"), OneGunUI.RADIUS_INPUT, OneGunUI.BORDER_THIN, 0, 10)
	field.add_theme_stylebox_override("normal", normal)
	field.add_theme_stylebox_override("focus", OneGunUI.focus_ring(normal))
	return field


func _fixed_label(text: String, width: float) -> Label:
	var label := OneGunUI.make_label(text, OneGunUI.TEXT_XS, "muted", true)
	label.custom_minimum_size.x = width
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _row_joinability(value: String) -> OneGunLobbyRow.Joinability:
	match value:
		"joinable": return OneGunLobbyRow.Joinability.JOINABLE
		"full": return OneGunLobbyRow.Joinability.FULL
		"in_progress": return OneGunLobbyRow.Joinability.IN_PROGRESS
		"incompatible": return OneGunLobbyRow.Joinability.INCOMPATIBLE
		_: return OneGunLobbyRow.Joinability.UNKNOWN


func _clean_code(value: String) -> String:
	var cleaned := ""
	for character in value.strip_edges().to_upper():
		if character in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789":
			cleaned += character
	return cleaned.substr(0, 12)


func _random_code() -> String:
	const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for _index in 6:
		code += ALPHABET[randi_range(0, ALPHABET.length() - 1)]
	return code
