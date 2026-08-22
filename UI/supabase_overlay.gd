class_name SupabaseOverlay
extends Control

signal closed

var _backend
var _account_page: Control
var _store_page: Control
var _inventory_page: Control
var _email_field: LineEdit
var _password_field: LineEdit
var _account_status: Label
var _currency_label: Label
var _feedback_label: Label
var _store_list: VBoxContainer
var _inventory_list: VBoxContainer
var _sign_in_button: OneGunButton
var _create_button: OneGunButton
var _sign_out_button: OneGunButton
var _refresh_button: OneGunButton


func _ready() -> void:
	_backend = get_node("/root/SupabaseManager")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_backend()
	_refresh_all()
	# Keep backend work event-driven: the signed-out catalog is fetched when the
	# player opens this cabinet, not during unrelated game/headless startup.
	if bool(_backend.is_configured()) and _backend.shop_items.is_empty() \
			and str(_backend.login_state) == "logged_out":
		call_deferred("_load_public_store")


func _load_public_store() -> void:
	_set_feedback("LOADING PUBLIC STORE…", false)
	if await _backend.load_shop():
		_set_feedback("PUBLIC STORE LOADED", false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_close()


func _build_ui() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.015, 0.02, 0.06, 0.90)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 32.0
	center.offset_top = 28.0
	center.offset_right = -32.0
	center.offset_bottom = -28.0
	add_child(center)

	var cabinet := OneGunCabinet.new()
	cabinet.name = "SupabaseCabinet"
	cabinet.custom_minimum_size = Vector2(1040.0, 760.0)
	center.add_child(cabinet)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	cabinet.get_content().add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	column.add_child(header)
	var title := OneGunUI.make_heading("ACCOUNT & STORE", OneGunUI.TEXT_TITLE, "gold")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := _make_button("CLOSE", "red")
	close_button.pressed.connect(_close)
	header.add_child(close_button)

	var subtitle := OneGunUI.make_label(
		"Supabase stores identity, Gun Tokens, ownership, and persistent cosmetics. Gameplay networking stays on Godot/ENet.",
		OneGunUI.TEXT_S, "muted")
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(subtitle)

	var tabs := OneGunTabBar.new()
	tabs.tabs = PackedStringArray(["ACCOUNT", "STORE", "INVENTORY"])
	tabs.tab_selected.connect(_show_page)
	column.add_child(tabs)

	var page_holder := MarginContainer.new()
	page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(page_holder)
	_account_page = _build_account_page()
	_store_page = _build_store_page()
	_inventory_page = _build_inventory_page()
	page_holder.add_child(_account_page)
	page_holder.add_child(_store_page)
	page_holder.add_child(_inventory_page)

	_feedback_label = OneGunUI.make_label("", OneGunUI.TEXT_S, "muted")
	_feedback_label.custom_minimum_size.y = 24.0
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_feedback_label)
	_show_page(0)


func _build_account_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	scroll.add_child(column)

	_account_status = OneGunUI.make_heading("SIGNED OUT", OneGunUI.TEXT_XL, "muted")
	column.add_child(_account_status)
	var safety := OneGunUI.make_label(
		"Passwords are sent directly to Supabase Auth and are never saved by One Gun. The local session file stores only the returned session tokens for sign-in restoration.",
		OneGunUI.TEXT_S, "muted")
	safety.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(safety)

	column.add_child(OneGunUI.make_heading("EMAIL", OneGunUI.TEXT_M, "text"))
	_email_field = _make_line_edit("player@example.com")
	_email_field.name = "SupabaseEmail"
	column.add_child(_email_field)
	column.add_child(OneGunUI.make_heading("PASSWORD", OneGunUI.TEXT_M, "text"))
	_password_field = _make_line_edit("Password")
	_password_field.name = "SupabasePassword"
	_password_field.secret = true
	_password_field.secret_character = "•"
	_password_field.text_submitted.connect(func(_value: String) -> void: _on_sign_in())
	column.add_child(_password_field)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	column.add_child(actions)
	_sign_in_button = _make_button("SIGN IN", "gold")
	_sign_in_button.pressed.connect(_on_sign_in)
	actions.add_child(_sign_in_button)
	_create_button = _make_button("CREATE ACCOUNT", "blue")
	_create_button.pressed.connect(_on_create_account)
	actions.add_child(_create_button)
	_sign_out_button = _make_button("SIGN OUT", "red")
	_sign_out_button.pressed.connect(_on_sign_out)
	actions.add_child(_sign_out_button)
	return scroll


func _build_store_page() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	column.add_child(toolbar)
	_currency_label = OneGunUI.make_heading("GUN TOKENS: 0", OneGunUI.TEXT_XL, "gold")
	_currency_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_currency_label)
	_refresh_button = _make_button("REFRESH", "navy")
	_refresh_button.pressed.connect(_on_refresh)
	toolbar.add_child(_refresh_button)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_store_list = VBoxContainer.new()
	_store_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_store_list.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	scroll.add_child(_store_list)
	return column


func _build_inventory_page() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	var explanation := OneGunUI.make_label(
		"Owned cosmetics include grants that are intentionally hidden from the public store. Art-pending items can still be equipped and persisted by the backend; One Gun will keep running with their visual omitted.",
		OneGunUI.TEXT_S, "muted")
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(explanation)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_inventory_list = VBoxContainer.new()
	_inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_list.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	scroll.add_child(_inventory_list)
	return column


func _connect_backend() -> void:
	var connections := [
		[_backend.login_state_changed, _on_login_state_changed],
		[_backend.login_succeeded, _on_login_succeeded],
		[_backend.login_failed, _on_backend_message],
		[_backend.account_created, _on_backend_success_message],
		[_backend.account_creation_failed, _on_backend_message],
		[_backend.logout_completed, _on_logout_completed],
		[_backend.profile_loaded, _on_profile_loaded],
		[_backend.currency_updated, _on_currency_updated],
		[_backend.inventory_updated, _on_inventory_updated],
		[_backend.shop_loaded, _on_shop_loaded],
		[_backend.loadout_updated, _on_loadout_updated],
		[_backend.purchase_succeeded, _on_purchase_succeeded],
		[_backend.purchase_failed, _on_purchase_failed],
		[_backend.equip_succeeded, _on_equip_succeeded],
		[_backend.equip_failed, _on_equip_failed],
		[_backend.backend_error, _on_backend_error],
	]
	for connection in connections:
		var backend_signal: Signal = connection[0]
		var callback: Callable = connection[1]
		if not backend_signal.is_connected(callback):
			backend_signal.connect(callback)


func _show_page(index: int) -> void:
	_account_page.visible = index == 0
	_store_page.visible = index == 1
	_inventory_page.visible = index == 2


func _refresh_all() -> void:
	_refresh_account()
	_refresh_currency()
	_rebuild_store()
	_rebuild_inventory()


func _refresh_account() -> void:
	var authenticated: bool = bool(_backend.is_authenticated())
	var username := str(_backend.profile.get("username", "")).strip_edges()
	if authenticated:
		_account_status.text = "SIGNED IN — %s" % (
			username.to_upper() if username != "" else "CLOUD PROFILE")
		_account_status.add_theme_color_override(
			"font_color", OneGunUI.color("green"))
	else:
		_account_status.text = "SIGNED OUT"
		_account_status.add_theme_color_override(
			"font_color", OneGunUI.color("muted"))
	_email_field.editable = not authenticated
	_password_field.editable = not authenticated
	_sign_in_button.visible = not authenticated
	_create_button.visible = not authenticated
	_sign_out_button.visible = authenticated


func _refresh_currency() -> void:
	_currency_label.text = "GUN TOKENS: %d" % _backend.gun_tokens
	_refresh_button.disabled = not _backend.is_configured()


func _rebuild_store() -> void:
	_clear_children(_store_list)
	if _backend.shop_items.is_empty():
		_store_list.add_child(_empty_label(
			"No active public shop items were returned." if _backend.is_configured() \
			else "Supabase is not configured for this build."))
		return
	for item in _backend.shop_items:
		_store_list.add_child(_make_store_row(item))


func _make_store_row(item: Dictionary) -> Control:
	var item_id := str(item.get("id", ""))
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", OneGunUI.style_box(
		OneGunUI.color("face_raised"), OneGunUI.color("border"),
		OneGunUI.RADIUS_SECTION, OneGunUI.BORDER_THIN, 2, OneGunUI.SPACE_M))
	var horizontal := HBoxContainer.new()
	horizontal.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	row.add_child(horizontal)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	horizontal.add_child(copy)
	var title := OneGunUI.make_heading(
		str(item.get("display_name", SupabaseCosmeticRegistry.display_name_fallback(item_id))).to_upper(),
		OneGunUI.TEXT_L, "text")
	copy.add_child(title)
	var slot := SupabaseCosmeticRegistry.item_slot(item)
	var art_state := "VISUAL READY" if SupabaseCosmeticRegistry.has_local_visual(
		item_id, slot) else "ART PENDING"
	copy.add_child(OneGunUI.make_label("%s • %s • %s" % [
		str(item.get("rarity", "standard")).to_upper(),
		slot.replace("_", " ").to_upper() if slot != "" else "UNKNOWN SLOT",
		art_state], OneGunUI.TEXT_S, "muted"))
	var description := OneGunUI.make_label(str(item.get("description", "")),
		OneGunUI.TEXT_S, "text")
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(description)
	var price := OneGunUI.make_heading("%d TOKENS" % int(item.get("price", 0)),
		OneGunUI.TEXT_L, "gold")
	price.custom_minimum_size.x = 150.0
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	horizontal.add_child(price)
	var authenticated: bool = bool(_backend.is_authenticated())
	var owned: bool = authenticated and bool(_backend.owns_item(item_id))
	var action_text := "OWNED" if owned else ("BUY" if authenticated \
		else "SIGN IN TO BUY")
	var action := _make_button(action_text, "green" if owned else "gold")
	action.custom_minimum_size.x = 132.0
	action.disabled = not authenticated or owned \
		or not bool(item.get("purchasable", false))
	if not owned:
		action.pressed.connect(_on_buy.bind(item_id))
	horizontal.add_child(action)
	return row


func _rebuild_inventory() -> void:
	_clear_children(_inventory_list)
	if not _backend.is_authenticated():
		_inventory_list.add_child(_empty_label("Sign in to load owned cosmetics."))
		return
	if _backend.inventory.is_empty():
		_inventory_list.add_child(_empty_label("No owned cosmetics were returned."))
		return
	for entry in _backend.inventory:
		_inventory_list.add_child(_make_inventory_row(entry))


func _make_inventory_row(entry: Dictionary) -> Control:
	var item_id := str(entry.get("item_id", ""))
	var catalog: Dictionary = _backend.catalog_item(item_id)
	var slot := SupabaseCosmeticRegistry.item_slot(catalog)
	if slot == "":
		slot = SupabaseCosmeticRegistry.known_slot_for_id(item_id)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", OneGunUI.style_box(
		OneGunUI.color("face_raised"), OneGunUI.color("border"),
		OneGunUI.RADIUS_SECTION, OneGunUI.BORDER_THIN, 2, OneGunUI.SPACE_M))
	var horizontal := HBoxContainer.new()
	horizontal.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	row.add_child(horizontal)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	horizontal.add_child(copy)
	var display_name := str(catalog.get("display_name",
		SupabaseCosmeticRegistry.display_name_fallback(item_id)))
	copy.add_child(OneGunUI.make_heading(display_name.to_upper(),
		OneGunUI.TEXT_L, "text"))
	var source := str(entry.get("source", "owned")).replace("_", " ").to_upper()
	var art_state := "VISUAL READY" if SupabaseCosmeticRegistry.has_local_visual(
		item_id, slot) else "ART PENDING"
	copy.add_child(OneGunUI.make_label("%s • %s • %s" % [
		slot.replace("_", " ").to_upper() if slot != "" else "UNKNOWN SLOT",
		source, art_state], OneGunUI.TEXT_S, "muted"))
	var equipped := slot != "" and str(_backend.loadout.get(slot, "")) == item_id
	var action := _make_button(
		"EQUIPPED" if equipped else ("EQUIP" if slot != "" else "DATA ONLY"),
		"green" if equipped else "blue")
	action.custom_minimum_size.x = 150.0
	action.disabled = equipped or slot == ""
	if not action.disabled:
		action.pressed.connect(_on_equip.bind(slot, item_id))
	horizontal.add_child(action)
	return row


func _on_sign_in() -> void:
	_set_feedback("SIGNING IN…", false)
	_set_auth_busy(true)
	await _backend.sign_in(_email_field.text, _password_field.text)
	_set_auth_busy(false)
	_password_field.clear()
	_refresh_all()


func _on_create_account() -> void:
	_set_feedback("CREATING ACCOUNT…", false)
	_set_auth_busy(true)
	await _backend.create_account(_email_field.text, _password_field.text)
	_set_auth_busy(false)
	_password_field.clear()
	_refresh_all()


func _on_sign_out() -> void:
	_set_feedback("SIGNING OUT…", false)
	_set_auth_busy(true)
	await _backend.sign_out()
	_set_auth_busy(false)
	_refresh_all()


func _on_refresh() -> void:
	_set_feedback("REFRESHING CLOUD DATA…" if _backend.is_authenticated() \
		else "REFRESHING PUBLIC STORE…", false)
	_refresh_button.disabled = true
	var success: bool = await _backend.load_all_player_data() \
		if _backend.is_authenticated() else await _backend.load_shop()
	_set_feedback("CLOUD DATA REFRESHED" if success else "SOME CLOUD DATA COULD NOT BE REFRESHED",
		not success)
	_refresh_all()


func _on_buy(item_id: String) -> void:
	_set_feedback("PURCHASING %s…" % item_id.to_upper(), false)
	await _backend.purchase_shop_item(item_id)


func _on_equip(slot: String, item_id: String) -> void:
	_set_feedback("EQUIPPING %s…" % item_id.to_upper(), false)
	await _backend.equip_cosmetic(slot, item_id)


func _on_login_state_changed(_state: String) -> void:
	_refresh_account()


func _on_login_succeeded(_user_id: String) -> void:
	_set_feedback("SIGNED IN — LOADING CLOUD PROFILE…", false)
	_refresh_account()


func _on_logout_completed() -> void:
	_set_feedback("SIGNED OUT", false)
	_refresh_all()


func _on_profile_loaded(_profile: Dictionary) -> void:
	_refresh_account()


func _on_currency_updated(_tokens: int) -> void:
	_refresh_currency()


func _on_inventory_updated(_inventory: Array) -> void:
	_rebuild_store()
	_rebuild_inventory()


func _on_shop_loaded(_items: Array) -> void:
	_rebuild_store()
	_rebuild_inventory()


func _on_loadout_updated(_loadout: Dictionary) -> void:
	_rebuild_inventory()


func _on_purchase_succeeded(item_id: String) -> void:
	_set_feedback("PURCHASED %s" % item_id.to_upper(), false)
	_refresh_all()


func _on_purchase_failed(_item_id: String, message: String) -> void:
	_set_feedback(message, true)


func _on_equip_succeeded(_slot: String, item_id: String) -> void:
	var visual_note := "" if SupabaseCosmeticRegistry.has_local_visual(
		item_id, str(_backend.catalog_item(item_id).get("item_type", ""))) \
		else " — LOCAL ART PENDING"
	_set_feedback("EQUIPPED %s%s" % [item_id.to_upper(), visual_note], false)
	_refresh_all()


func _on_equip_failed(_slot: String, _item_id: String, message: String) -> void:
	_set_feedback(message, true)


func _on_backend_error(operation: String, message: String) -> void:
	_set_feedback("%s: %s" % [operation.to_upper(), message], true)


func _on_backend_success_message(message: String) -> void:
	_set_feedback(message, false)


func _on_backend_message(message: String) -> void:
	_set_feedback(message, true)


func _set_auth_busy(busy: bool) -> void:
	_sign_in_button.disabled = busy
	_create_button.disabled = busy
	_sign_out_button.disabled = busy


func _set_feedback(message: String, is_error: bool) -> void:
	_feedback_label.text = message
	_feedback_label.add_theme_color_override("font_color",
		OneGunUI.color("red") if is_error else OneGunUI.color("green"))


func _make_line_edit(placeholder: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.custom_minimum_size.y = 48.0
	var normal := OneGunUI.style_box(OneGunUI.color("well"),
		OneGunUI.color("border"), OneGunUI.RADIUS_INPUT,
		OneGunUI.BORDER_THIN, 0, OneGunUI.SPACE_M)
	field.add_theme_stylebox_override("normal", normal)
	field.add_theme_stylebox_override("focus", OneGunUI.focus_ring(normal))
	field.add_theme_color_override("font_color", OneGunUI.color("text"))
	field.add_theme_color_override("font_placeholder_color", OneGunUI.color("muted"))
	field.add_theme_font_size_override("font_size", OneGunUI.TEXT_M)
	return field


func _make_button(text: String, variant: String) -> OneGunButton:
	var button := OneGunButton.new()
	button.text = text
	button.variant = variant
	button.custom_minimum_size.y = 48.0
	return button


func _empty_label(text: String) -> Label:
	var label := OneGunUI.make_label(text, OneGunUI.TEXT_M, "muted")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.y = 80.0
	return label


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _close() -> void:
	closed.emit()
	queue_free()
