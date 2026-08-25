class_name SupabaseOverlay
extends Control

signal closed

var _backend
var _account_page: Control
var _store_page: Control
var _inventory_page: Control
var _main_tabs: OneGunTabBar
var _email_field: LineEdit
var _password_field: LineEdit
var _account_name_field: LineEdit
var _account_name_caption: Control
var _account_name_hint: Control
var _rename_field: LineEdit
var _display_name_field: LineEdit
var _account_status: Label
var _rename_cooldown_label: Label
var _currency_label: Label
var _feedback_label: Label
var _store_list: VBoxContainer
var _inventory_list: VBoxContainer
var _sign_in_button: OneGunButton
var _create_button: OneGunButton
var _sign_out_button: OneGunButton
var _rename_button: OneGunButton
var _refresh_button: OneGunButton
var _signed_out_content: Control
var _signed_in_content: Control
var _profile_pages: Array[Control] = []
var _auth_mode := 0
var _active_store_category := "FEATURED"
var _initial_page := "profile"


func configure(initial_page: String) -> void:
	_initial_page = "prize_counter" if initial_page == "prize_counter" else "profile"


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
	var cabinet_space := get_viewport_rect().size - Vector2(64.0, 56.0)
	cabinet.custom_minimum_size = Vector2(
		minf(1040.0, cabinet_space.x), minf(760.0, cabinet_space.y))
	center.add_child(cabinet)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	cabinet.get_content().add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	column.add_child(header)
	var title := OneGunUI.make_heading("PLAYER HUB", OneGunUI.TEXT_TITLE, "gold")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := _make_button("CLOSE", "red")
	close_button.pressed.connect(_close)
	header.add_child(close_button)

	var subtitle := OneGunUI.make_label(
		"Manage your public player identity or browse the rotating Prize Counter. Gameplay networking remains on Godot/ENet.",
		OneGunUI.TEXT_S, "muted")
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(subtitle)

	_main_tabs = OneGunTabBar.new()
	_main_tabs.tabs = PackedStringArray(["PROFILE", "PRIZE COUNTER"])
	_main_tabs.selected = 1 if _initial_page == "prize_counter" else 0
	_main_tabs.tab_selected.connect(_show_page)
	column.add_child(_main_tabs)

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
	_show_page(_main_tabs.selected)


func _build_account_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "ProfileScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	scroll.add_child(column)

	_account_status = OneGunUI.make_heading("SIGNED OUT", OneGunUI.TEXT_XL, "muted")
	column.add_child(_account_status)

	_signed_out_content = VBoxContainer.new()
	(_signed_out_content as VBoxContainer).add_theme_constant_override(
		"separation", OneGunUI.SPACE_M)
	column.add_child(_signed_out_content)
	var safety := OneGunUI.make_label(
		"Passwords are sent directly to Supabase Auth and are never saved by One Gun. The local session file stores only the returned session tokens for sign-in restoration.",
		OneGunUI.TEXT_S, "muted")
	safety.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_signed_out_content.add_child(safety)

	var auth_tabs := OneGunTabBar.new()
	auth_tabs.name = "AuthenticationModeTabs"
	auth_tabs.tabs = PackedStringArray(["SIGN IN", "CREATE ACCOUNT"])
	auth_tabs.tab_selected.connect(_show_auth_mode)
	_signed_out_content.add_child(auth_tabs)

	_signed_out_content.add_child(OneGunUI.make_heading("EMAIL", OneGunUI.TEXT_M, "text"))
	_email_field = _make_line_edit("player@example.com")
	_email_field.name = "SupabaseEmail"
	_signed_out_content.add_child(_email_field)
	_signed_out_content.add_child(OneGunUI.make_heading("PASSWORD", OneGunUI.TEXT_M, "text"))
	_password_field = _make_line_edit("Password")
	_password_field.name = "SupabasePassword"
	_password_field.secret = true
	_password_field.secret_character = "•"
	_password_field.text_submitted.connect(func(_value: String) -> void:
		if _auth_mode == 0:
			_on_sign_in()
		else:
			_on_create_account())
	_signed_out_content.add_child(_password_field)

	_account_name_caption = OneGunUI.make_heading(
		"ACCOUNT NAME", OneGunUI.TEXT_M, "text")
	_signed_out_content.add_child(_account_name_caption)
	_account_name_field = _make_line_edit("Unique Account Name")
	_account_name_field.name = "SupabaseAccountName"
	_account_name_field.max_length = _backend.ACCOUNT_NAME_MAX_LENGTH
	_account_name_field.tooltip_text = \
		"3–20 characters. Letters, numbers, and underscores only."
	_signed_out_content.add_child(_account_name_field)
	_account_name_hint = OneGunUI.make_label(
		"This unique Account Name is separate from the Display Name used in matches.",
		OneGunUI.TEXT_S, "muted")
	(_account_name_hint as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_signed_out_content.add_child(_account_name_hint)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	_signed_out_content.add_child(actions)
	_sign_in_button = _make_button("SIGN IN", "gold")
	_sign_in_button.pressed.connect(_on_sign_in)
	actions.add_child(_sign_in_button)
	_create_button = _make_button("CREATE ACCOUNT", "blue")
	_create_button.pressed.connect(_on_create_account)
	actions.add_child(_create_button)

	_signed_in_content = VBoxContainer.new()
	(_signed_in_content as VBoxContainer).add_theme_constant_override(
		"separation", OneGunUI.SPACE_M)
	column.add_child(_signed_in_content)
	var profile_tabs := OneGunTabBar.new()
	profile_tabs.name = "ProfileSectionTabs"
	profile_tabs.tabs = PackedStringArray([
		"OVERVIEW", "STATS", "LEGACY HALL", "MATCH HISTORY"])
	profile_tabs.tab_selected.connect(_show_profile_section)
	_signed_in_content.add_child(profile_tabs)

	var overview := VBoxContainer.new()
	overview.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	overview.add_child(OneGunUI.make_heading(
		"CURRENT SEASON — BETA SEASON", OneGunUI.TEXT_L, "gold"))
	var season_copy := OneGunUI.make_label(
		"Level, XP, Prestige, and Classic Trophies will appear here when the server-authoritative progression and reward migration is activated.",
		OneGunUI.TEXT_M, "muted")
	season_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overview.add_child(season_copy)
	overview.add_child(OneGunUI.make_heading(
		"IN-GAME DISPLAY NAME", OneGunUI.TEXT_M, "text"))
	var display_name_row := HBoxContainer.new()
	display_name_row.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	overview.add_child(display_name_row)
	_display_name_field = _make_line_edit("Name shown during matches")
	_display_name_field.name = "ProfileDisplayName"
	_display_name_field.max_length = 24
	_display_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display_name_row.add_child(_display_name_field)
	var save_display_name := _make_button("SAVE DISPLAY NAME", "blue")
	save_display_name.pressed.connect(_on_save_display_name)
	display_name_row.add_child(save_display_name)
	overview.add_child(OneGunUI.make_heading(
		"ACCOUNT SETTINGS", OneGunUI.TEXT_M, "text"))
	var rename_row := HBoxContainer.new()
	rename_row.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	overview.add_child(rename_row)
	_rename_field = _make_line_edit("New Account Name")
	_rename_field.name = "ProfileAccountRename"
	_rename_field.max_length = _backend.ACCOUNT_NAME_MAX_LENGTH
	_rename_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_row.add_child(_rename_field)
	_rename_button = _make_button("RENAME ACCOUNT", "gold")
	_rename_button.pressed.connect(_on_rename_account)
	rename_row.add_child(_rename_button)
	_rename_cooldown_label = OneGunUI.make_label("", OneGunUI.TEXT_S, "muted")
	overview.add_child(_rename_cooldown_label)
	_sign_out_button = _make_button("SIGN OUT", "red")
	_sign_out_button.pressed.connect(_on_sign_out)
	overview.add_child(_sign_out_button)
	_profile_pages.append(overview)
	_signed_in_content.add_child(overview)

	_profile_pages.append(_make_profile_placeholder(
		"CAREER STATS",
		"Classic One Gun will be selected by default, with Current Season and Career views for every game mode."))
	_profile_pages.append(_make_profile_placeholder(
		"LEGACY HALL",
		"Completed seasons will archive final Level, Prestige, Trophies, mode wins, and reward-road milestones here."))
	_profile_pages.append(_make_profile_placeholder(
		"MATCH HISTORY",
		"Recent official match placements, combat stats, XP, Gun Tokens, and Trophy results will appear after persistent match rewards are enabled."))
	for page_index in range(1, _profile_pages.size()):
		_signed_in_content.add_child(_profile_pages[page_index])
	_show_auth_mode(0)
	_show_profile_section(0)
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
	var category_tabs := OneGunTabBar.new()
	category_tabs.name = "PrizeCounterCategories"
	category_tabs.tabs = PackedStringArray([
		"FEATURED", "CHARACTER", "WEAPONS", "MOVES", "MUSIC"])
	category_tabs.tab_selected.connect(_on_store_category_selected)
	column.add_child(category_tabs)
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
		[_backend.account_name_changed, _on_account_name_changed],
		[_backend.account_name_change_failed, _on_backend_message],
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
	if index != 1:
		AudioManager.stop_ceremony_preview()
	_account_page.visible = index == 0
	_store_page.visible = index == 1
	_inventory_page.visible = false


func _refresh_all() -> void:
	_refresh_account()
	_refresh_currency()
	_rebuild_store()


func _refresh_account() -> void:
	var authenticated: bool = bool(_backend.is_authenticated())
	var username := str(_backend.current_account_name())
	if authenticated:
		_account_status.text = "SIGNED IN — %s" % (
			username.to_upper() if username != "" else "CLOUD PROFILE")
		_account_status.add_theme_color_override(
			"font_color", OneGunUI.color("green"))
	else:
		_account_status.text = "SIGNED OUT"
		_account_status.add_theme_color_override(
			"font_color", OneGunUI.color("muted"))
	_signed_out_content.visible = not authenticated
	_signed_in_content.visible = authenticated
	if authenticated:
		if not _display_name_field.has_focus():
			_display_name_field.text = str(PlayerPrefs.get_setting("player_name"))
		if not _rename_field.has_focus():
			_rename_field.text = username
		_refresh_rename_cooldown()


func _refresh_currency() -> void:
	_currency_label.text = "GUN TOKENS: %d" % _backend.gun_tokens
	_refresh_button.disabled = not _backend.is_configured()


func _rebuild_store() -> void:
	_clear_children(_store_list)
	var filtered_items: Array[Dictionary] = []
	for item in _backend.shop_items:
		if _store_category_for_item(item) == _active_store_category \
				or _active_store_category == "FEATURED":
			filtered_items.append(item)
	if _backend.shop_items.is_empty():
		_store_list.add_child(_empty_label(
			"No active public shop items were returned." if _backend.is_configured() \
			else "Supabase is not configured for this build."))
		return
	if filtered_items.is_empty():
		_store_list.add_child(_empty_label(
			"No %s items are in the current rotation." % \
			_active_store_category.to_lower()))
		return
	filtered_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_owned := bool(_backend.owns_item(str(a.get("id", ""))))
		var b_owned := bool(_backend.owns_item(str(b.get("id", ""))))
		if a_owned != b_owned:
			return not a_owned
		return str(a.get("display_name", "")).nocasecmp_to(
			str(b.get("display_name", ""))) < 0)
	for item in filtered_items:
		_store_list.add_child(_make_store_row(item))


func _store_category_for_item(item: Dictionary) -> String:
	var slot := SupabaseCosmeticRegistry.item_slot(item)
	if slot in ["character_skin", "hat", "accessory"]:
		return "CHARACTER"
	if slot in ["gun_skin", "melee_skin"]:
		return "WEAPONS"
	if slot == "emote":
		return "MOVES"
	if slot == "ceremony_theme":
		return "MUSIC"
	return "FEATURED"


func _on_store_category_selected(index: int) -> void:
	var categories := ["FEATURED", "CHARACTER", "WEAPONS", "MOVES", "MUSIC"]
	_active_store_category = categories[clampi(index, 0, categories.size() - 1)]
	if _active_store_category != "MUSIC":
		AudioManager.stop_ceremony_preview()
	_rebuild_store()


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
	if slot == "ceremony_theme":
		var preview := _make_button("PREVIEW", "blue")
		preview.custom_minimum_size.x = 116.0
		preview.pressed.connect(_on_preview_theme.bind(item_id))
		horizontal.add_child(preview)
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
	if slot == "ceremony_theme":
		var preview := _make_button("PREVIEW", "blue")
		preview.custom_minimum_size.x = 116.0
		preview.pressed.connect(_on_preview_theme.bind(item_id))
		horizontal.add_child(preview)
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
	await _backend.create_account(
		_email_field.text, _password_field.text, _account_name_field.text)
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


func _on_preview_theme(item_id: String) -> void:
	var audio_key := SupabaseCosmeticRegistry.local_ceremony_audio_key(item_id)
	if audio_key == "":
		_set_feedback("THIS CEREMONY THEME IS NOT INSTALLED", true)
		return
	var started := AudioManager.play_ceremony_preview(audio_key, 0.78)
	_set_feedback(("PREVIEWING " if started else "COULD NOT PREVIEW ") \
		+ SupabaseCosmeticRegistry.display_name_fallback(
		item_id).to_upper(), false)


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


func _on_account_name_changed(username: String) -> void:
	_set_feedback("ACCOUNT NAME CHANGED TO %s" % username.to_upper(), false)
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
	var catalog: Dictionary = _backend.catalog_item(item_id)
	var item_slot := SupabaseCosmeticRegistry.item_slot(catalog)
	if item_slot == "":
		item_slot = SupabaseCosmeticRegistry.known_slot_for_id(item_id)
	var visual_note := "" if SupabaseCosmeticRegistry.has_local_visual(
		item_id, item_slot) \
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
	if busy:
		_rename_button.disabled = true
	elif _backend != null and _backend.is_authenticated():
		_refresh_rename_cooldown()


func _show_auth_mode(index: int) -> void:
	_auth_mode = clampi(index, 0, 1)
	var creating := _auth_mode == 1
	_account_name_caption.visible = creating
	_account_name_field.visible = creating
	_account_name_hint.visible = creating
	_sign_in_button.visible = not creating
	_create_button.visible = creating


func _show_profile_section(index: int) -> void:
	for page_index in _profile_pages.size():
		_profile_pages[page_index].visible = page_index == index


func _make_profile_placeholder(title: String, body: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	column.add_child(OneGunUI.make_heading(title, OneGunUI.TEXT_L, "gold"))
	var copy := OneGunUI.make_label(body, OneGunUI.TEXT_M, "muted")
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(copy)
	return column


func _on_save_display_name() -> void:
	var display_name := _display_name_field.text.strip_edges().substr(0, 24)
	if display_name == "":
		_set_feedback("DISPLAY NAME CANNOT BE EMPTY", true)
		return
	PlayerPrefs.set_setting("player_name", display_name)
	_display_name_field.text = str(PlayerPrefs.get_setting("player_name"))
	_set_feedback("IN-GAME DISPLAY NAME UPDATED", false)


func _on_rename_account() -> void:
	_set_feedback("CHECKING ACCOUNT NAME…", false)
	_rename_button.disabled = true
	await _backend.rename_account_name(_rename_field.text)
	_refresh_rename_cooldown()


func _refresh_rename_cooldown() -> void:
	if _backend.current_account_name() == "":
		_rename_button.text = "SET ACCOUNT NAME"
		_rename_button.disabled = false
		_rename_cooldown_label.text = \
			"Choose your unique Account Name. The 14-day rename cooldown starts after it is set."
		_rename_cooldown_label.add_theme_color_override(
			"font_color", OneGunUI.color("cyan"))
		return
	_rename_button.text = "RENAME ACCOUNT"
	var available_at := int(_backend.account_name_change_available_unix())
	var now := int(Time.get_unix_time_from_system())
	if available_at <= now:
		_rename_cooldown_label.text = \
			"Account Name changes are available once every 14 days — AVAILABLE NOW."
		_rename_cooldown_label.add_theme_color_override(
			"font_color", OneGunUI.color("green"))
		_rename_button.disabled = false
		return
	var date := Time.get_date_string_from_unix_time(available_at)
	_rename_cooldown_label.text = \
		"NEXT ACCOUNT NAME CHANGE: %s (14-DAY COOLDOWN)" % date
	_rename_cooldown_label.add_theme_color_override(
		"font_color", OneGunUI.color("muted"))
	_rename_button.disabled = true


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
	AudioManager.stop_ceremony_preview()
	closed.emit()
	queue_free()
