class_name PlayerHubOverlay
extends "res://UI/supabase_overlay.gd"

# Presentation layer for the Supabase-backed player hub. The inherited script
# remains the backend/event contract; this subclass gives Profile and Prize
# Counter independent full-screen compositions without duplicating auth,
# purchase, ownership, preview, or equip behavior.

const BASE_SIZE := Vector2(1600.0, 900.0)
const HUB_BACKDROP_SCRIPT = preload("res://UI/components/menu_hub_backdrop.gd")
const PORTRAIT_SCRIPT = preload("res://UI/components/character_portrait.gd")
const PROFILE_BACKDROP = preload("res://UI/assets/menu_hubs/profile_backdrop.png")
const PRIZE_BACKDROP = preload("res://UI/assets/menu_hubs/prize_counter_backdrop.png")
const Catalog = preload("res://supabase/one_gun_catalog.gd")
const WinnersResultData = preload("res://winners_circle_match_result.gd")
const ProgressionCaptureFixture = preload("res://UI/progression_capture_fixture.gd")
const SkinRegistry = preload("res://player_skin_registry.gd")

const STORE_CATEGORIES := Catalog.PRIMARY_CATEGORIES
const PRIZE_ROTATION_NOTICE := \
	"Only the current public rotation appears here. Owned prizes remain permanently in your Locker."

var _canvas: Control
var _backdrop: Control
var _screen_title: Label
var _back_button: OneGunButton
var _profile_portrait: CharacterPortrait
var _profile_display_label: Label
var _profile_handle_label: Label
var _profile_token_label: Label
var _profile_trophy_label: Label
var _trophy_label: Label
var _store_category_buttons: Array[OneGunButton] = []
var _store_card_buttons: Dictionary = {}
var _selected_store_item_id := ""
var _store_subcategory := "ALL"
var _store_cosmetic_filter := "ALL"
var _store_sort_id := "rarity_asc"
var _store_favorites_only := false
var _store_affordable_only := false
var _store_subcategory_option: OptionButton
var _store_cosmetic_option: OptionButton
var _store_sort_option: OptionButton
var _store_detail_title: Label
var _store_detail_meta: Label
var _store_detail_description: Label
var _store_detail_price: Label
var _store_detail_art: Label
var _store_move_preview_container: SubViewportContainer
var _store_move_preview_viewport: SubViewport
var _store_move_preview_pivot: Node3D
var _store_move_preview_camera: Camera3D
var _store_move_preview_visual: Node3D
var _store_move_preview_player: AnimationPlayer
var _store_move_preview_animation := ""
var _store_move_preview_replay_delay := 0.0
var _store_hat_preview_active := false
var _store_hat_preview_dragging := false
var _store_detail_preview: OneGunButton
var _store_detail_action: OneGunButton
var _store_detail_favorite: OneGunButton
var _store_rotation_label: Label
var _store_footer_note: Label
var _store_inspect_chip: Control
var _store_carousel_controls: HBoxContainer
var _store_carousel_page_label: Label
var _store_carousel_previous: OneGunButton
var _store_carousel_next: OneGunButton
var _store_carousel_page := 0
var _active_page_index := 0
var _profile_value_labels: Dictionary = {}
var _profile_mode_id := GameConfig.MODE_ONE_GUN
var _profile_mode_option: OptionButton
var _legacy_shelves: HBoxContainer
var _history_rows: VBoxContainer


func _ready() -> void:
	# Stable, in-memory presentation data for automated screenshots only. It is
	# never enabled during ordinary play and never calls or writes Supabase.
	if OS.get_environment("ONEGUN_UI_CAPTURE") != "" \
			and OS.get_environment("ONEGUN_UI_CAPTURE_STATE") in [
				"profile", "prize_counter", "prize_counter_seasonal"]:
		_seed_capture_fixture(get_node("/root/SupabaseManager"))
	super._ready()
	for connection in [
		[ProgressionManager.catalog_updated, _on_extended_catalog_updated],
		[ProgressionManager.favorites_updated, _on_catalog_preferences_updated],
		[ProgressionManager.usage_updated, _on_catalog_usage_updated],
		[ProgressionManager.progression_updated, _on_progression_updated],
	]:
		if not (connection[0] as Signal).is_connected(connection[1] as Callable):
			(connection[0] as Signal).connect(connection[1] as Callable)
	if OS.get_environment("ONEGUN_UI_CAPTURE_STATE") == "prize_counter_seasonal":
		var starter_index := _store_subcategory_option.get_item_count() - 1
		_store_subcategory_option.select(starter_index)
		_on_store_subcategory_selected(starter_index)
	if OS.get_environment("ONEGUN_UI_CAPTURE") != "":
		Input.warp_mouse(Vector2(18.0, 18.0))


func _seed_capture_fixture(capture_backend: Node) -> void:
	ProgressionCaptureFixture.seed_backend(capture_backend)
	PlayerPrefs.settings["player_name"] = "Maverick"
	var capture_shop_items: Array[Dictionary] = [
		{"id": "hat_top", "display_name": "Top Hat", "item_type": "hat",
			"description": "Formal headwear for competitors with serious podium plans.",
			"price": 1650, "rarity": "rare", "purchasable": true,
			"shop_visible": true, "active": true},
		{"id": "golden_gun_skin", "display_name": "Golden Gun", "item_type": "gun_skin",
			"description": "A brilliant champion finish for the one and only gun.",
			"price": 2500, "rarity": "legendary", "purchasable": true,
			"shop_visible": true, "active": true},
		{"id": "victory_pose_spotlight", "display_name": "Spotlight Pose", "item_type": "emote",
			"description": "Hold the winning pose while the arena lights find you.",
			"price": 700, "rarity": "uncommon", "purchasable": true,
			"shop_visible": true, "active": true},
		{"id": "victory_move_showboat", "display_name": "Showboat Shuffle", "item_type": "emote",
			"description": "A full animated podium celebration for the confident winner.",
			"price": 1800, "rarity": "epic", "purchasable": true,
			"shop_visible": true, "active": true},
		{"id": "wc_theme_neon_victory", "display_name": "Neon Victory",
			"item_type": "ceremony_theme", "description": "A bright electronic victory charge timed to every podium reveal.",
			"price": 1200, "rarity": "rare", "purchasable": true,
			"shop_visible": true, "active": true},
		{"id": "wc_theme_grand_arena", "display_name": "Grand Arena",
			"item_type": "ceremony_theme", "description": "A large ceremonial anthem built for a champion entrance.",
			"price": 1800, "rarity": "epic", "purchasable": true,
			"shop_visible": true, "active": true},
		{"id": "wc_theme_western_toybox", "display_name": "Western Toybox",
			"item_type": "ceremony_theme", "description": "A playful frontier celebration with a One Gun toy-box spirit.",
			"price": 750, "rarity": "uncommon", "purchasable": true,
			"shop_visible": true, "active": true},
		{"id": "wc_theme_pixel_champion", "display_name": "Pixel Champion",
			"item_type": "ceremony_theme", "description": "A colorful digital victory theme with a smooth final flourish.",
			"price": 1400, "rarity": "rare", "purchasable": true,
			"shop_visible": true, "active": true},
		{"id": "wc_theme_champion_groove", "display_name": "Champion Groove",
			"item_type": "ceremony_theme", "description": "A confident champion groove with a playful arena-sized finish.",
			"price": 1600, "rarity": "epic", "purchasable": true,
			"shop_visible": true, "active": true},
		{"id": "wc_theme_deep_orbit", "display_name": "Deep Orbit",
			"item_type": "ceremony_theme", "description": "A deep electronic champion theme with warm bass and cinematic space.",
			"price": 2200, "rarity": "legendary", "purchasable": true,
			"shop_visible": true, "active": true},
	]
	capture_backend.shop_items = capture_shop_items
	var capture_inventory: Array[Dictionary] = [
		{"item_id": "hat_top", "source": "purchase"},
		{"item_id": "wc_theme_deep_orbit", "source": "purchase"},
		{"item_id": "wc_theme_ceremony_march", "source": "starter_unlock"},
	]
	capture_backend.inventory = capture_inventory
	capture_backend.set("_owned_item_ids", {
		"hat_top": true,
		"wc_theme_deep_orbit": true,
		"wc_theme_ceremony_march": true,
	})
	capture_backend.loadout = SupabaseCosmeticRegistry.sanitize_loadout({
		"hat": "hat_top",
		"ceremony_theme": "wc_theme_deep_orbit",
	})
	ProgressionManager.catalog_items.clear()
	for item in capture_shop_items:
		var catalog_item: Dictionary = Catalog.normalize_item(item)
		catalog_item["rotation_scope"] = "seasonal_starter" \
			if str(catalog_item.get("item_type", "")) == "ceremony_theme" \
			else ("daily" if str(catalog_item.get("id", "")) in [
				"hat_top", "victory_pose_spotlight"] else "monthly")
		ProgressionManager.catalog_items.append(catalog_item)
	ProgressionManager.favorites = {"wc_theme_deep_orbit": true}
	ProgressionManager.usage = {
		"hat_top": {"equip_count": 11},
		"wc_theme_deep_orbit": {"equip_count": 7},
	}
	ProgressionManager.progression = ProgressionCaptureFixture.snapshot()


func _build_ui() -> void:
	var scrim := ColorRect.new()
	scrim.name = "PlayerHubScrim"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.002, 0.004, 0.012, 1.0)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	_canvas = Control.new()
	_canvas.name = "PlayerHubCanvas"
	_canvas.size = BASE_SIZE
	add_child(_canvas)

	_active_page_index = 1 if _initial_page == "prize_counter" else 0
	_replace_backdrop(_active_page_index)
	_build_screen_header()

	_account_page = _build_account_page()
	_account_page.name = "ProfilePage"
	_account_page.position = Vector2(64.0, 142.0)
	_account_page.size = Vector2(1472.0, 654.0)
	_canvas.add_child(_account_page)

	_store_page = _build_store_page()
	_store_page.name = "PrizeCounterPage"
	_store_page.position = Vector2(64.0, 142.0)
	_store_page.size = Vector2(1472.0, 654.0)
	_canvas.add_child(_store_page)

	_inventory_page = _build_inventory_page()
	_inventory_page.visible = false
	_canvas.add_child(_inventory_page)

	var feedback_panel := PanelContainer.new()
	feedback_panel.name = "PlayerHubFeedback"
	feedback_panel.position = Vector2(304.0, 814.0)
	feedback_panel.size = Vector2(1232.0, 54.0)
	feedback_panel.add_theme_stylebox_override("panel", _glass_style(
		Color(0.008, 0.014, 0.035, 0.92), Color(1.0, 0.67, 0.17, 0.28), 12, 1, 8))
	_canvas.add_child(feedback_panel)
	var feedback_margin := MarginContainer.new()
	feedback_margin.add_theme_constant_override("margin_left", 18)
	feedback_margin.add_theme_constant_override("margin_right", 18)
	feedback_panel.add_child(feedback_margin)
	var feedback_row := HBoxContainer.new()
	feedback_row.add_theme_constant_override("separation", 16)
	feedback_margin.add_child(feedback_row)
	_store_footer_note = OneGunUI.make_label(
		PRIZE_ROTATION_NOTICE, OneGunUI.TEXT_S, "muted", true)
	_store_footer_note.name = "PrizeCounterRotationNotice"
	_store_footer_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_store_footer_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_store_footer_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_row.add_child(_store_footer_note)
	_feedback_label = OneGunUI.make_label("", OneGunUI.TEXT_S, "muted", true)
	_feedback_label.custom_minimum_size.x = 420.0
	_feedback_label.visible = false
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_row.add_child(_feedback_label)
	# Pages are constructed after the shared footer Back button. Keep Back at the
	# top of the Canvas stack so no future content panel can intercept its clicks.
	_canvas.move_child(_back_button, _canvas.get_child_count() - 1)

	_show_page(_active_page_index)
	_apply_responsive_layout()
	resized.connect(_apply_responsive_layout)
	_animate_entrance()


func _build_screen_header() -> void:
	_screen_title = OneGunUI.make_heading("COMPETITOR PROFILE", 42, "text_bright")
	_screen_title.position = Vector2(64.0, 42.0)
	_screen_title.size = Vector2(900.0, 52.0)
	_canvas.add_child(_screen_title)

	_back_button = _make_button("BACK", "navy")
	_back_button.name = "ClosePlayerHub"
	_back_button.position = Vector2(64.0, 808.0)
	_back_button.size = Vector2(220.0, 60.0)
	_back_button.pressed.connect(_close)
	_canvas.add_child(_back_button)

	var rule := ColorRect.new()
	rule.position = Vector2(64.0, 126.0)
	rule.size = Vector2(1472.0, 2.0)
	rule.color = Color(OneGunUI.color("gold"), 0.65)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(rule)


func _build_account_page() -> Control:
	var root := Control.new()

	var status_panel := PanelContainer.new()
	status_panel.position = Vector2.ZERO
	status_panel.size = Vector2(1472.0, 62.0)
	status_panel.add_theme_stylebox_override("panel", _glass_style(
		Color(0.015, 0.025, 0.055, 0.94), Color(0.20, 0.70, 0.78, 0.42), 14, 2, 7))
	root.add_child(status_panel)
	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 22)
	status_margin.add_theme_constant_override("margin_right", 22)
	status_panel.add_child(status_margin)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	status_margin.add_child(status_row)
	_account_status = OneGunUI.make_heading("SIGNED OUT", OneGunUI.TEXT_XL, "muted")
	_account_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_account_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_row.add_child(_account_status)
	var season_chip := _make_chip("BETA SEASON", "gold")
	status_row.add_child(season_chip)
	var official_chip := _make_chip("PRIVATE TAILSCALE = OFFICIAL", "cyan")
	status_row.add_child(official_chip)

	_signed_out_content = HBoxContainer.new()
	_signed_out_content.position = Vector2(0.0, 78.0)
	_signed_out_content.size = Vector2(1472.0, 576.0)
	(_signed_out_content as HBoxContainer).add_theme_constant_override("separation", 18)
	root.add_child(_signed_out_content)
	_build_signed_out_profile(_signed_out_content as HBoxContainer)

	_signed_in_content = HBoxContainer.new()
	_signed_in_content.position = Vector2(0.0, 78.0)
	_signed_in_content.size = Vector2(1472.0, 576.0)
	(_signed_in_content as HBoxContainer).add_theme_constant_override("separation", 18)
	root.add_child(_signed_in_content)
	_build_signed_in_profile(_signed_in_content as HBoxContainer)

	_show_auth_mode(0)
	_show_profile_section(0)
	return root


func _build_signed_out_profile(parent: HBoxContainer) -> void:
	var identity_panel := _make_panel(Vector2(430.0, 576.0), "gold")
	parent.add_child(identity_panel)
	var identity := _panel_column(identity_panel, 24)
	identity.add_child(OneGunUI.make_label("ARENA CREDENTIAL", OneGunUI.TEXT_S, "cyan", true))
	identity.add_child(OneGunUI.make_heading("CLAIM YOUR RECORD", 28, "gold"))
	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(0.0, 292.0)
	portrait_frame.add_theme_stylebox_override("panel", _glass_style(
		Color(0.01, 0.02, 0.05, 0.92), Color(1.0, 0.66, 0.14, 0.55), 18, 2, 0))
	identity.add_child(portrait_frame)
	var portrait := PORTRAIT_SCRIPT.new() as CharacterPortrait
	portrait.set_appearance(str(PlayerPrefs.get_setting("character_skin_id")),
		str(PlayerPrefs.get_setting("character_model_id")))
	portrait_frame.add_child(portrait)
	var intro := OneGunUI.make_label(
		"Sign in to keep purchases, ceremony themes, and your permanent player identity connected across seasons.",
		OneGunUI.TEXT_M, "text")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.add_child(intro)
	identity.add_child(_make_feature_line("◆", "Permanent cosmetic ownership"))
	identity.add_child(_make_feature_line("★", "Season and Legacy Hall records"))
	identity.add_child(_make_feature_line("◎", "One unique Account Name"))

	var auth_panel := _make_panel(Vector2(1024.0, 576.0), "cyan")
	auth_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(auth_panel)
	var auth := _panel_column(auth_panel, 26)
	var auth_header := HBoxContainer.new()
	auth_header.add_theme_constant_override("separation", 12)
	auth.add_child(auth_header)
	var auth_title := OneGunUI.make_heading("PLAYER ACCOUNT", 28, "text_bright")
	auth_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auth_header.add_child(auth_title)
	var security := _make_chip("SUPABASE SECURED", "green")
	auth_header.add_child(security)

	var auth_tabs := OneGunTabBar.new()
	auth_tabs.name = "AuthenticationModeTabs"
	auth_tabs.tabs = PackedStringArray(["SIGN IN", "CREATE ACCOUNT"])
	auth_tabs.tab_selected.connect(_show_auth_mode)
	auth.add_child(auth_tabs)

	_signed_out_content = parent
	var fields := GridContainer.new()
	fields.columns = 2
	fields.add_theme_constant_override("h_separation", 16)
	fields.add_theme_constant_override("v_separation", 8)
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auth.add_child(fields)
	fields.add_child(OneGunUI.make_heading("EMAIL", OneGunUI.TEXT_M, "text"))
	fields.add_child(OneGunUI.make_heading("PASSWORD", OneGunUI.TEXT_M, "text"))
	_email_field = _make_line_edit("player@example.com")
	_email_field.name = "SupabaseEmail"
	_email_field.custom_minimum_size.x = 430.0
	fields.add_child(_email_field)
	_password_field = _make_line_edit("Password")
	_password_field.name = "SupabasePassword"
	_password_field.secret = true
	_password_field.secret_character = "•"
	_password_field.custom_minimum_size.x = 430.0
	_password_field.text_submitted.connect(func(_value: String) -> void:
		if _auth_mode == 0:
			_on_sign_in()
		else:
			_on_create_account())
	fields.add_child(_password_field)

	_account_name_caption = OneGunUI.make_heading("ACCOUNT NAME", OneGunUI.TEXT_M, "text")
	auth.add_child(_account_name_caption)
	_account_name_field = _make_line_edit("Unique Account Name")
	_account_name_field.name = "SupabaseAccountName"
	_account_name_field.max_length = _backend.ACCOUNT_NAME_MAX_LENGTH
	_account_name_field.tooltip_text = "3–20 characters. Letters, numbers, and underscores only."
	auth.add_child(_account_name_field)
	_account_name_hint = OneGunUI.make_label(
		"Your unique Account Name is separate from the Display Name shown during matches.",
		OneGunUI.TEXT_S, "cyan")
	(_account_name_hint as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auth.add_child(_account_name_hint)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	auth.add_child(actions)
	_sign_in_button = _make_button("ENTER THE ARENA", "gold")
	_sign_in_button.custom_minimum_size = Vector2(250.0, 52.0)
	_sign_in_button.pressed.connect(_on_sign_in)
	actions.add_child(_sign_in_button)
	_create_button = _make_button("CREATE PLAYER RECORD", "blue")
	_create_button.custom_minimum_size = Vector2(280.0, 52.0)
	_create_button.pressed.connect(_on_create_account)
	actions.add_child(_create_button)

	var safety := OneGunUI.make_label(
		"One Gun never saves your password. Supabase Auth receives it directly; only the returned session is kept for sign-in restoration.",
		OneGunUI.TEXT_S, "muted")
	safety.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auth.add_child(safety)


func _build_signed_in_profile(parent: HBoxContainer) -> void:
	var player_card := _make_panel(Vector2(404.0, 576.0), "gold")
	parent.add_child(player_card)
	var card := _panel_column(player_card, 22)
	card.add_child(OneGunUI.make_label("OFFICIAL COMPETITOR CARD", OneGunUI.TEXT_S, "cyan", true))
	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(0.0, 302.0)
	portrait_frame.add_theme_stylebox_override("panel", _glass_style(
		Color(0.006, 0.015, 0.038, 0.94), Color(1.0, 0.62, 0.12, 0.62), 18, 2, 4))
	card.add_child(portrait_frame)
	_profile_portrait = PORTRAIT_SCRIPT.new() as CharacterPortrait
	portrait_frame.add_child(_profile_portrait)
	_profile_display_label = OneGunUI.make_heading("PLAYER", 30, "text_bright")
	_profile_display_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_profile_display_label)
	_profile_handle_label = OneGunUI.make_label("@ACCOUNT", OneGunUI.TEXT_M, "cyan", true)
	_profile_handle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_profile_handle_label)
	var balances := HBoxContainer.new()
	balances.alignment = BoxContainer.ALIGNMENT_CENTER
	balances.add_theme_constant_override("separation", 8)
	card.add_child(balances)
	_profile_token_label = _make_chip("0 GUN TOKENS", "gold")
	balances.add_child(_profile_token_label)
	_profile_trophy_label = _make_chip("0 TROPHIES", "cyan")
	balances.add_child(_profile_trophy_label)

	var records_panel := _make_panel(Vector2(1050.0, 576.0), "cyan")
	records_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(records_panel)
	var records := _panel_column(records_panel, 20)
	var profile_tabs := OneGunTabBar.new()
	profile_tabs.name = "ProfileSectionTabs"
	profile_tabs.tabs = PackedStringArray(["OVERVIEW", "STATS", "LEGACY HALL", "MATCH HISTORY"])
	profile_tabs.tab_selected.connect(_show_profile_section)
	records.add_child(profile_tabs)

	var page_holder := MarginContainer.new()
	page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	records.add_child(page_holder)
	_profile_pages.clear()
	_profile_pages.append(_build_profile_overview())
	_profile_pages.append(_build_profile_stats())
	_profile_pages.append(_build_legacy_hall())
	_profile_pages.append(_build_match_history())
	for page in _profile_pages:
		page_holder.add_child(page)


func _build_profile_overview() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	column.add_child(stats)
	stats.add_child(_make_stat_tile("SEASON LEVEL", "—", "gold"))
	stats.add_child(_make_stat_tile("CLASSIC TROPHIES", "0", "cyan"))
	stats.add_child(_make_stat_tile("SEASON PRESTIGE", "0", "cyan"))
	stats.add_child(_make_stat_tile("CAREER LEVEL", "0", "purple"))
	stats.add_child(_make_stat_tile("CAREER PRESTIGE", "0", "purple"))

	var season := PanelContainer.new()
	season.add_theme_stylebox_override("panel", _glass_style(
		Color(0.018, 0.035, 0.072, 0.88), Color(1.0, 0.64, 0.13, 0.32), 12, 1, 0))
	column.add_child(season)
	var season_margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		season_margin.add_theme_constant_override(side, 12)
	season.add_child(season_margin)
	var season_row := HBoxContainer.new()
	season_margin.add_child(season_row)
	var season_copy := VBoxContainer.new()
	season_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	season_row.add_child(season_copy)
	season_copy.add_child(OneGunUI.make_heading("BETA SEASON", OneGunUI.TEXT_L, "gold"))
	season_copy.add_child(OneGunUI.make_label(
		"Your first official match begins this season record. Cosmetics and Gun Tokens remain yours forever.",
		OneGunUI.TEXT_S, "muted"))
	season_row.add_child(_make_chip("SEASON ROAD READY", "green"))

	var display_row := HBoxContainer.new()
	display_row.add_theme_constant_override("separation", 10)
	column.add_child(display_row)
	var display_copy := VBoxContainer.new()
	display_copy.custom_minimum_size.x = 230.0
	display_row.add_child(display_copy)
	display_copy.add_child(OneGunUI.make_heading("IN-GAME DISPLAY NAME", OneGunUI.TEXT_M, "text"))
	display_copy.add_child(OneGunUI.make_label("Free to change. Shown during matches.", OneGunUI.TEXT_S, "muted"))
	_display_name_field = _make_line_edit("Name shown during matches")
	_display_name_field.name = "ProfileDisplayName"
	_display_name_field.max_length = 24
	_display_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display_row.add_child(_display_name_field)
	var save_display := _make_button("SAVE", "blue")
	save_display.custom_minimum_size.x = 126.0
	save_display.pressed.connect(_on_save_display_name)
	display_row.add_child(save_display)

	var rename_row := HBoxContainer.new()
	rename_row.add_theme_constant_override("separation", 10)
	column.add_child(rename_row)
	var rename_copy := VBoxContainer.new()
	rename_copy.custom_minimum_size.x = 230.0
	rename_row.add_child(rename_copy)
	rename_copy.add_child(OneGunUI.make_heading("ACCOUNT NAME", OneGunUI.TEXT_M, "text"))
	rename_copy.add_child(OneGunUI.make_label("Unique. Changes every 14 days.", OneGunUI.TEXT_S, "muted"))
	_rename_field = _make_line_edit("New Account Name")
	_rename_field.name = "ProfileAccountRename"
	_rename_field.max_length = _backend.ACCOUNT_NAME_MAX_LENGTH
	_rename_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_row.add_child(_rename_field)
	_rename_button = _make_button("RENAME", "gold")
	_rename_button.custom_minimum_size.x = 126.0
	_rename_button.pressed.connect(_on_rename_account)
	rename_row.add_child(_rename_button)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	_rename_cooldown_label = OneGunUI.make_label("", OneGunUI.TEXT_S, "muted")
	_rename_cooldown_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rename_cooldown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_rename_cooldown_label)
	_sign_out_button = _make_button("SIGN OUT", "red")
	_sign_out_button.custom_minimum_size = Vector2(148.0, 44.0)
	_sign_out_button.pressed.connect(_on_sign_out)
	footer.add_child(_sign_out_button)
	return column


func _build_profile_stats() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := OneGunUI.make_heading("CAREER STATS", OneGunUI.TEXT_XL, "gold")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_profile_mode_option = OptionButton.new()
	_profile_mode_option.name = "ProfileModeStatsFilter"
	_profile_mode_option.custom_minimum_size = Vector2(260.0, 42.0)
	for mode_id in GameConfig.GAME_MODES:
		_profile_mode_option.add_item(GameConfig.GAME_MODE_NAMES[mode_id])
	_profile_mode_option.item_selected.connect(func(index: int) -> void:
		_profile_mode_id = GameConfig.GAME_MODES[clampi(
			index, 0, GameConfig.GAME_MODES.size() - 1)]
		_refresh_profile_progression())
	header.add_child(_profile_mode_option)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	column.add_child(grid)
	for data in [
		["CAREER WINS", "—", "gold"], ["MATCHES", "—", "cyan"],
		["BEST FINISH", "—", "purple"], ["KILLS", "—", "gold"],
		["DISARMS", "—", "cyan"], ["ROUND WINS", "—", "green"],
	]:
		grid.add_child(_make_stat_tile(str(data[0]), str(data[1]), str(data[2])))
	var note := OneGunUI.make_label(
		"Classic One Gun is shown first. Switch modes here as their official records become available.",
		OneGunUI.TEXT_M, "muted")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	return column


func _build_legacy_hall() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.add_child(OneGunUI.make_heading("LEGACY HALL", OneGunUI.TEXT_XL, "gold"))
	var copy := OneGunUI.make_label(
		"Every completed season becomes a permanent display of your final Level, Prestige, Trophies, mode wins, and reward-road milestones.",
		OneGunUI.TEXT_M, "text")
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(copy)
	_legacy_shelves = HBoxContainer.new()
	_legacy_shelves.add_theme_constant_override("separation", 12)
	column.add_child(_legacy_shelves)
	for index in 3:
		var season := PanelContainer.new()
		season.custom_minimum_size = Vector2(0.0, 250.0)
		season.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		season.add_theme_stylebox_override("panel", _glass_style(
			Color(0.012, 0.030, 0.052, 0.90), Color(1.0, 0.62, 0.13, 0.28), 14, 1, 2))
		_legacy_shelves.add_child(season)
		var season_column := VBoxContainer.new()
		season_column.alignment = BoxContainer.ALIGNMENT_CENTER
		season_column.add_theme_constant_override("separation", 12)
		season.add_child(season_column)
		var star := OneGunUI.make_heading("★", 48, "gold" if index == 0 else "muted")
		star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		season_column.add_child(star)
		var label := OneGunUI.make_heading(
			"BETA SEASON" if index == 0 else "FUTURE SEASON", OneGunUI.TEXT_M,
			"text" if index == 0 else "muted")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		season_column.add_child(label)
		var status := OneGunUI.make_label(
			"IN PROGRESS" if index == 0 else "ARCHIVE SLOT", OneGunUI.TEXT_S,
			"cyan" if index == 0 else "muted", true)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		season_column.add_child(status)
	return column


func _build_match_history() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.add_child(OneGunUI.make_heading("MATCH HISTORY", OneGunUI.TEXT_XL, "gold"))
	var header := _make_history_row("RESULT", "MODE", "MAP", "REWARDS", true)
	column.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_history_rows = VBoxContainer.new()
	_history_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_history_rows)
	return column


func _build_store_page() -> Control:
	var root := Control.new()
	var currency_panel := PanelContainer.new()
	currency_panel.position = Vector2.ZERO
	currency_panel.size = Vector2(1472.0, 64.0)
	currency_panel.add_theme_stylebox_override("panel", _glass_style(
		Color(0.035, 0.018, 0.018, 0.94), Color(1.0, 0.58, 0.10, 0.54), 14, 2, 8))
	root.add_child(currency_panel)
	var currency_margin := MarginContainer.new()
	currency_margin.add_theme_constant_override("margin_left", 22)
	currency_margin.add_theme_constant_override("margin_right", 12)
	currency_panel.add_child(currency_margin)
	var currency_row := HBoxContainer.new()
	currency_row.add_theme_constant_override("separation", 12)
	currency_margin.add_child(currency_row)
	_currency_label = OneGunUI.make_heading("GUN TOKENS: 0", OneGunUI.TEXT_XL, "gold")
	_currency_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	currency_row.add_child(_currency_label)
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(1.0, 32.0)
	divider.color = Color(OneGunUI.color("gold"), 0.32)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	currency_row.add_child(divider)
	_trophy_label = OneGunUI.make_heading("TROPHIES: 0", OneGunUI.TEXT_L, "cyan")
	_trophy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	currency_row.add_child(_trophy_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	currency_row.add_child(spacer)
	_store_rotation_label = OneGunUI.make_label(
		"BETA SEASON  •  LIVE ROTATION", OneGunUI.TEXT_M, "text", true)
	_store_rotation_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	currency_row.add_child(_store_rotation_label)
	_refresh_button = _make_button("REFRESH COUNTER", "navy")
	_refresh_button.custom_minimum_size = Vector2(190.0, 46.0)
	_refresh_button.pressed.connect(_on_refresh)
	currency_row.add_child(_refresh_button)

	var category_panel := _make_panel(Vector2(224.0, 0.0), "gold")
	category_panel.name = "PrizeBrowseCounterPanel"
	category_panel.position = Vector2(0.0, 80.0)
	root.add_child(category_panel)
	var category_column := _panel_column(category_panel, 16)
	category_column.name = "PrizeCounterCategories"
	category_column.add_theme_constant_override("separation", 5)
	category_column.add_child(OneGunUI.make_label("BROWSE COUNTER", OneGunUI.TEXT_S, "cyan", true))
	category_column.add_child(OneGunUI.make_heading("PRIZE AISLES", OneGunUI.TEXT_L, "gold"))
	_store_category_buttons.clear()
	for index in STORE_CATEGORIES.size():
		var category := _make_button(STORE_CATEGORIES[index], "gold" if index == 0 else "navy")
		category.custom_minimum_size = Vector2(0.0, 38.0)
		category.pressed.connect(_on_store_category_selected.bind(index))
		category_column.add_child(category)
		_store_category_buttons.append(category)
	category_column.add_child(OneGunUI.make_label(
		"SHELF FILTER", OneGunUI.TEXT_XS, "cyan", true))
	_store_subcategory_option = OptionButton.new()
	_store_subcategory_option.name = "PrizeSubcategoryFilter"
	_store_subcategory_option.custom_minimum_size.y = 38.0
	_store_subcategory_option.item_selected.connect(_on_store_subcategory_selected)
	category_column.add_child(_store_subcategory_option)
	_store_cosmetic_option = OptionButton.new()
	_store_cosmetic_option.name = "PrizeCosmeticFilter"
	_store_cosmetic_option.custom_minimum_size.y = 38.0
	for option in Catalog.COSMETIC_SUBCATEGORIES:
		_store_cosmetic_option.add_item(option)
	_store_cosmetic_option.item_selected.connect(_on_store_cosmetic_selected)
	category_column.add_child(_store_cosmetic_option)
	_store_sort_option = OptionButton.new()
	_store_sort_option.name = "PrizeSortOrder"
	_store_sort_option.custom_minimum_size.y = 38.0
	for label in Catalog.SORT_LABELS:
		_store_sort_option.add_item(label)
	_store_sort_option.item_selected.connect(_on_store_sort_selected)
	category_column.add_child(_store_sort_option)
	var quick_filters := VBoxContainer.new()
	quick_filters.add_theme_constant_override("separation", 4)
	category_column.add_child(quick_filters)
	var favorites := _make_button("★ FAVORITES", "navy")
	favorites.name = "PrizeFavoritesFilter"
	# Typed assignment keeps the button state available to the callback without
	# adding another long-lived UI reference.
	favorites.toggle_mode = true
	favorites.custom_minimum_size.y = 32.0
	favorites.toggled.connect(func(value: bool) -> void:
		_store_favorites_only = value
		favorites.variant = "gold" if value else "navy"
		_rebuild_store())
	quick_filters.add_child(favorites)
	var affordable := _make_button("AFFORDABLE", "navy")
	affordable.name = "PrizeAffordableFilter"
	affordable.toggle_mode = true
	affordable.custom_minimum_size.y = 32.0
	affordable.toggled.connect(func(value: bool) -> void:
		_store_affordable_only = value
		affordable.variant = "green" if value else "navy"
		_rebuild_store())
	quick_filters.add_child(affordable)
	_rebuild_store_subcategories()

	var shelf_panel := _make_panel(Vector2(790.0, 574.0), "gold")
	shelf_panel.position = Vector2(242.0, 80.0)
	root.add_child(shelf_panel)
	var shelf := _panel_column(shelf_panel, 16)
	var shelf_header := HBoxContainer.new()
	shelf.add_child(shelf_header)
	var shelf_title := OneGunUI.make_heading("CURRENT SHELF", OneGunUI.TEXT_L, "text_bright")
	shelf_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf_header.add_child(shelf_title)
	_store_inspect_chip = _make_chip("SELECT A PRIZE TO INSPECT", "cyan")
	shelf_header.add_child(_store_inspect_chip)
	_store_carousel_controls = HBoxContainer.new()
	_store_carousel_controls.add_theme_constant_override("separation", 6)
	_store_carousel_controls.visible = false
	shelf_header.add_child(_store_carousel_controls)
	_store_carousel_previous = _make_button("‹", "navy")
	_store_carousel_previous.custom_minimum_size = Vector2(40.0, 34.0)
	_store_carousel_previous.tooltip_text = "Previous three Seasonal Starter prizes"
	_store_carousel_previous.pressed.connect(_change_store_carousel_page.bind(-1))
	_store_carousel_controls.add_child(_store_carousel_previous)
	_store_carousel_page_label = OneGunUI.make_label("1 / 2", OneGunUI.TEXT_S,
		"cyan", true)
	_store_carousel_page_label.custom_minimum_size = Vector2(60.0, 34.0)
	_store_carousel_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_store_carousel_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_store_carousel_controls.add_child(_store_carousel_page_label)
	_store_carousel_next = _make_button("›", "navy")
	_store_carousel_next.custom_minimum_size = Vector2(40.0, 34.0)
	_store_carousel_next.tooltip_text = "Next three Seasonal Starter prizes"
	_store_carousel_next.pressed.connect(_change_store_carousel_page.bind(1))
	_store_carousel_controls.add_child(_store_carousel_next)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shelf.add_child(scroll)
	_store_list = VBoxContainer.new()
	_store_list.name = "PrizeShelfGrid"
	_store_list.custom_minimum_size.x = 742.0
	_store_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_store_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_store_list)

	var detail_panel := _make_panel(Vector2(422.0, 574.0), "cyan")
	detail_panel.position = Vector2(1050.0, 80.0)
	root.add_child(detail_panel)
	var detail := _panel_column(detail_panel, 18)
	detail.add_child(OneGunUI.make_label("PRIZE INSPECTION", OneGunUI.TEXT_S, "cyan", true))
	var art_panel := PanelContainer.new()
	art_panel.custom_minimum_size = Vector2(0.0, 190.0)
	art_panel.add_theme_stylebox_override("panel", _glass_style(
		Color(0.01, 0.018, 0.045, 0.96), Color(1.0, 0.62, 0.12, 0.48), 16, 2, 4))
	detail.add_child(art_panel)
	var art_stack := Control.new()
	art_stack.name = "PrizeInspectionPreviewStack"
	art_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_panel.add_child(art_stack)
	_store_detail_art = OneGunUI.make_heading("OG", 64, "gold")
	_store_detail_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_store_detail_art.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_store_detail_art.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art_stack.add_child(_store_detail_art)
	_store_move_preview_container = SubViewportContainer.new()
	_store_move_preview_container.name = "PrizeMovePreview"
	_store_move_preview_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_store_move_preview_container.stretch = true
	_store_move_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_store_move_preview_container.gui_input.connect(_on_store_hat_preview_gui_input)
	_store_move_preview_container.visible = false
	art_stack.add_child(_store_move_preview_container)
	_build_store_move_preview_world()
	_store_detail_title = OneGunUI.make_heading("SELECT A PRIZE", 25, "text_bright")
	_store_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_store_detail_title)
	_store_detail_meta = OneGunUI.make_label("LIVE ROTATION", OneGunUI.TEXT_S, "cyan", true)
	detail.add_child(_store_detail_meta)
	_store_detail_description = OneGunUI.make_label(
		"Choose an item from the shelf to see its details.", OneGunUI.TEXT_M, "text")
	_store_detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_store_detail_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(_store_detail_description)
	_store_detail_price = OneGunUI.make_heading("—", OneGunUI.TEXT_XL, "gold")
	detail.add_child(_store_detail_price)
	var detail_actions := HBoxContainer.new()
	detail_actions.add_theme_constant_override("separation", 10)
	detail.add_child(detail_actions)
	_store_detail_favorite = _make_button("☆", "navy")
	_store_detail_favorite.custom_minimum_size = Vector2(52.0, 50.0)
	_store_detail_favorite.tooltip_text = "Add or remove this prize from Favorites"
	_store_detail_favorite.pressed.connect(_toggle_selected_store_favorite)
	detail_actions.add_child(_store_detail_favorite)
	_store_detail_preview = _make_button("PREVIEW", "blue")
	_store_detail_preview.custom_minimum_size = Vector2(132.0, 50.0)
	_store_detail_preview.pressed.connect(_preview_selected_store_item)
	detail_actions.add_child(_store_detail_preview)
	_store_detail_action = _make_button("BUY", "gold")
	_store_detail_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_store_detail_action.custom_minimum_size.y = 50.0
	_store_detail_action.pressed.connect(_purchase_selected_store_item)
	detail_actions.add_child(_store_detail_action)
	return root


func _build_store_move_preview_world() -> void:
	_store_move_preview_viewport = SubViewport.new()
	_store_move_preview_viewport.name = "PrizeMoveViewport"
	_store_move_preview_viewport.size = Vector2i(512, 256)
	_store_move_preview_viewport.own_world_3d = true
	_store_move_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_store_move_preview_container.add_child(_store_move_preview_viewport)
	var world := Node3D.new()
	world.name = "PrizeMoveWorld"
	_store_move_preview_viewport.add_child(world)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.014, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.62, 0.88)
	env.ambient_light_energy = 1.0
	environment.environment = env
	world.add_child(environment)

	var podium := MeshInstance3D.new()
	podium.name = "PrizePreviewPodium"
	var podium_mesh := CylinderMesh.new()
	podium_mesh.top_radius = 1.05
	podium_mesh.bottom_radius = 1.15
	podium_mesh.height = 0.20
	podium_mesh.radial_segments = 48
	podium.mesh = podium_mesh
	podium.position.y = 0.10
	var podium_material := StandardMaterial3D.new()
	podium_material.albedo_color = Color(0.055, 0.085, 0.17)
	podium_material.metallic = 0.72
	podium_material.roughness = 0.25
	podium_material.emission_enabled = true
	podium_material.emission = Color(0.06, 0.16, 0.34)
	podium_material.emission_energy_multiplier = 0.75
	podium.material_override = podium_material
	world.add_child(podium)

	_store_move_preview_pivot = Node3D.new()
	_store_move_preview_pivot.name = "PrizeMoveCharacterPivot"
	_store_move_preview_pivot.position.y = 0.20
	world.add_child(_store_move_preview_pivot)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	key.light_color = Color(1.0, 0.82, 0.60)
	key.light_energy = 2.0
	key.shadow_enabled = false
	world.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(1.6, 1.9, -1.4)
	rim.light_color = Color(0.24, 0.56, 1.0)
	rim.light_energy = 2.6
	rim.omni_range = 5.0
	rim.shadow_enabled = false
	world.add_child(rim)

	_store_move_preview_camera = Camera3D.new()
	_store_move_preview_camera.name = "PrizeMoveCamera"
	_store_move_preview_camera.fov = 36.0
	world.add_child(_store_move_preview_camera)
	_store_move_preview_camera.look_at_from_position(
		Vector3(0.0, 1.56, 5.95), Vector3(0.0, 1.20, 0.0), Vector3.UP)
	_store_move_preview_camera.current = true
	GraphicsQualityManager.apply_subtree(_store_move_preview_viewport)


func _frame_store_full_body_preview() -> void:
	if _store_move_preview_camera == null:
		return
	_store_move_preview_camera.fov = 36.0
	_store_move_preview_camera.look_at_from_position(
		Vector3(0.0, 1.56, 5.95), Vector3(0.0, 1.20, 0.0), Vector3.UP)


func _frame_store_hat_preview() -> void:
	if _store_move_preview_camera == null or _store_move_preview_visual == null:
		return
	var socket := _store_move_preview_visual.call("get_headwear_socket") as Marker3D
	if socket == null:
		return
	# Crop at the shoulders, then derive the camera distance from this hat's
	# actual rendered height. A witch hat receives more room than a fedora while
	# both retain a deliberate safety margin above the crown/brim.
	var frame_bottom := socket.global_position.y - 0.90
	var frame_top := socket.global_position.y + 0.72
	var rotation_radius := 0.0
	var hat := socket.find_child("HatVisual", false, false) as Node3D
	if hat != null:
		for node in hat.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null \
					or not mesh_instance.is_visible_in_tree():
				continue
			var world_bounds := mesh_instance.global_transform \
				* mesh_instance.mesh.get_aabb()
			frame_top = maxf(frame_top,
				world_bounds.position.y + world_bounds.size.y)
			for corner_index in 8:
				var corner := world_bounds.position + Vector3(
					world_bounds.size.x if (corner_index & 1) != 0 else 0.0,
					world_bounds.size.y if (corner_index & 2) != 0 else 0.0,
					world_bounds.size.z if (corner_index & 4) != 0 else 0.0)
				var radial := Vector2(
					corner.x - _store_move_preview_pivot.global_position.x,
					corner.z - _store_move_preview_pivot.global_position.z).length()
				rotation_radius = maxf(rotation_radius, radial)
	frame_bottom -= 0.06
	frame_top += 0.18
	var frame_center := (frame_bottom + frame_top) * 0.5
	var half_height := maxf((frame_top - frame_bottom) * 0.5, 0.68)
	_store_move_preview_camera.fov = 36.0
	# Include the largest X/Z radius in the distance. A wide/deep hat can rotate
	# toward the camera after framing; height-only framing let that nearer edge
	# grow into the top of the viewport even though the front pose looked safe.
	var distance := clampf(
		half_height / tan(deg_to_rad(_store_move_preview_camera.fov * 0.5)) * 1.18
			+ rotation_radius,
		2.60, 6.20)
	# The preview world is a fixed display set. Only the character pivot rotates;
	# following the animated socket on X/Z made the first frame appear offset and
	# made the stationary background seem to orbit while the player dragged.
	_store_move_preview_camera.look_at_from_position(
		Vector3(0.0, frame_center, distance),
		Vector3(0.0, frame_center, 0.0), Vector3.UP)


func _rotate_store_hat_preview(angle: float) -> void:
	if _store_move_preview_pivot == null or is_zero_approx(angle):
		return
	_store_move_preview_pivot.rotate_y(angle)


func _ensure_store_move_preview_visual() -> bool:
	var model_id := SkinRegistry.sanitize_model_id(
		str(PlayerPrefs.get_setting("character_model_id")))
	if _store_move_preview_visual != null \
			and is_instance_valid(_store_move_preview_visual) \
			and str(_store_move_preview_visual.get("model_id")) != model_id:
		_store_move_preview_visual.free()
		_store_move_preview_visual = null
		_store_move_preview_player = null
	if _store_move_preview_visual == null:
		var visual_scene := SkinRegistry.load_visual_scene(model_id)
		if visual_scene == null:
			return false
		_store_move_preview_visual = visual_scene.instantiate() as Node3D
		if _store_move_preview_visual == null:
			return false
		_store_move_preview_visual.name = "PrizeMoveCharacter"
		_store_move_preview_visual.set("build_animation_library", false)
		_store_move_preview_pivot.add_child(_store_move_preview_visual)
	if _store_move_preview_visual.has_method("set_skin"):
		_store_move_preview_visual.call("set_skin", SkinRegistry.sanitize_skin_id(
			str(PlayerPrefs.get_setting("character_skin_id"))))
	return true


func _store_move_animation(item_id: String, slot: String) -> String:
	if slot in ["victory_dance", "emote", "round_victory_move"]:
		return SupabaseCosmeticRegistry.local_victory_animation(item_id)
	return ""


func _show_store_move_preview(item_id: String, slot: String) -> bool:
	var animation_name := _store_move_animation(item_id, slot)
	if animation_name == "" or not _ensure_store_move_preview_visual():
		_hide_store_move_preview()
		return false
	_store_hat_preview_active = false
	_store_hat_preview_dragging = false
	_store_move_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_store_full_body_preview()
	_store_move_preview_visual.position.x = 0.0
	_store_move_preview_visual.position.z = 0.0
	if _store_move_preview_visual.has_method("set_hat_cosmetic"):
		_store_move_preview_visual.call("set_hat_cosmetic", "")
	_store_move_preview_player = _store_move_preview_visual.call(
		"ensure_animations", [animation_name]) as AnimationPlayer
	if _store_move_preview_player == null \
			or not _store_move_preview_player.has_animation(animation_name):
		_hide_store_move_preview()
		return false
	_store_move_preview_animation = animation_name
	_store_move_preview_replay_delay = 0.0
	_store_detail_art.visible = false
	_store_move_preview_container.visible = true
	_store_move_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_store_move_preview_pivot.rotation = Vector3.ZERO
	_store_move_preview_player.play(animation_name, 0.08)
	_store_move_preview_player.advance(0.0)
	return true


func _show_store_hat_preview(item_id: String) -> bool:
	if not SupabaseCosmeticRegistry.has_local_visual(item_id, "hat") \
			or not _ensure_store_move_preview_visual() \
			or not _store_move_preview_visual.has_method("set_hat_cosmetic"):
		_hide_store_move_preview()
		return false
	_store_move_preview_animation = "idle"
	_store_move_preview_replay_delay = 0.0
	_store_move_preview_player = _store_move_preview_visual.call(
		"ensure_animations", ["idle"]) as AnimationPlayer
	if _store_move_preview_player != null \
			and _store_move_preview_player.has_animation("idle"):
		_store_move_preview_player.play("idle", 0.0)
		_store_move_preview_player.advance(0.0)
	else:
		_store_move_preview_animation = ""
	if not is_zero_approx(_store_move_preview_pivot.rotation.y):
		_rotate_store_hat_preview(-_store_move_preview_pivot.rotation.y)
	else:
		_store_move_preview_pivot.rotation = Vector3.ZERO
	_store_move_preview_visual.call("set_hat_cosmetic", item_id)
	_store_detail_art.visible = false
	_store_move_preview_container.visible = true
	_store_move_preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_store_hat_preview_active = true
	_store_hat_preview_dragging = false
	_frame_store_hat_preview()
	_frame_store_hat_preview.call_deferred()
	# Hats follow the living character's shared idle instead of freezing in a
	# mannequin pose. The one reusable quality-scaled viewport is disabled again
	# as soon as inspection closes or another non-3D item is selected.
	_store_move_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return true


func _hide_store_move_preview() -> void:
	_store_move_preview_animation = ""
	_store_move_preview_replay_delay = 0.0
	_store_hat_preview_active = false
	_store_hat_preview_dragging = false
	if _store_move_preview_player != null:
		_store_move_preview_player.stop()
	if _store_move_preview_visual != null \
			and _store_move_preview_visual.has_method("set_hat_cosmetic"):
		_store_move_preview_visual.call("set_hat_cosmetic", "")
	if _store_move_preview_container != null:
		_store_move_preview_container.visible = false
		_store_move_preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _store_move_preview_viewport != null:
		_store_move_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _store_detail_art != null:
		_store_detail_art.visible = true


func _on_store_hat_preview_gui_input(event: InputEvent) -> void:
	if not _store_hat_preview_active or _store_move_preview_pivot == null:
		return
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_store_hat_preview_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _store_hat_preview_dragging:
		_rotate_store_hat_preview(event.relative.x * 0.012)
		accept_event()


func _process(delta: float) -> void:
	if _store_hat_preview_active and _store_move_preview_container.visible \
			and _store_move_preview_pivot != null:
		var look_axis := Input.get_axis("p1_look_left", "p1_look_right")
		if absf(look_axis) > 0.18:
			_rotate_store_hat_preview(look_axis * 1.9 * delta)
	if _store_move_preview_animation == "" \
			or _store_move_preview_player == null \
			or not _store_move_preview_container.visible:
		return
	if _store_move_preview_player.is_playing():
		_store_move_preview_replay_delay = 0.0
		return
	_store_move_preview_replay_delay += delta
	if _store_move_preview_replay_delay >= 0.65:
		_store_move_preview_replay_delay = 0.0
		_store_move_preview_player.play(_store_move_preview_animation, 0.08)


func _build_inventory_page() -> Control:
	var hidden := Control.new()
	_inventory_list = VBoxContainer.new()
	hidden.add_child(_inventory_list)
	return hidden


func _rebuild_store() -> void:
	_configure_store_controller_focus.call_deferred()
	var seasonal_starter := _active_store_category == "FEATURED" \
		and _store_subcategory == "SEASONAL STARTER"
	_store_carousel_controls.visible = seasonal_starter
	_store_inspect_chip.visible = not seasonal_starter
	_clear_children(_store_list)
	_store_card_buttons.clear()
	var filtered_items: Array[Dictionary] = []
	var catalog_source := _store_catalog_source()
	for item in catalog_source:
		if not Catalog.is_in_live_rotation(item):
			continue
		if not Catalog.item_matches(item, _active_store_category,
				_store_subcategory, _store_cosmetic_filter):
			continue
		var item_id := str(item.get("id", ""))
		if _store_favorites_only and not ProgressionManager.is_favorite(item_id):
			continue
		if _store_affordable_only and _store_item_price(item) > _backend.gun_tokens:
			continue
		filtered_items.append(item)
	if catalog_source.is_empty():
		_store_list.add_child(_empty_label(
			"THE COUNTER IS RESTOCKING — TRY REFRESH" if _backend.is_configured() \
			else "SUPABASE IS NOT CONFIGURED FOR THIS BUILD"))
		_selected_store_item_id = ""
		_refresh_store_detail()
		return
	if filtered_items.is_empty():
		_store_list.add_child(_empty_label(
			"NO %s PRIZES ARE IN THIS ROTATION" % _active_store_category))
		_selected_store_item_id = ""
		_refresh_store_detail()
		return
	filtered_items = Catalog.sorted_items(
		filtered_items, _store_sort_id, _catalog_usage_counts())
	if seasonal_starter:
		var starter_items: Array[Dictionary] = []
		for starter_index in mini(filtered_items.size(), 6):
			starter_items.append(filtered_items[starter_index])
		filtered_items = starter_items
		var page_count := maxi(ceili(float(filtered_items.size()) / 3.0), 1)
		_store_carousel_page = clampi(_store_carousel_page, 0, page_count - 1)
		_store_carousel_page_label.text = "%d / %d" % [
			_store_carousel_page + 1, page_count]
		_store_carousel_previous.disabled = _store_carousel_page <= 0
		_store_carousel_next.disabled = _store_carousel_page >= page_count - 1
		var start_index := _store_carousel_page * 3
		var page_items: Array[Dictionary] = []
		for item_index in range(start_index,
				mini(start_index + 3, filtered_items.size())):
			page_items.append(filtered_items[item_index])
		if _selected_store_item_id == "" or not _item_array_contains(
				page_items, _selected_store_item_id):
			_selected_store_item_id = str(page_items[0].get("id", ""))
		var carousel_row := HBoxContainer.new()
		carousel_row.name = "SeasonalStarterPage%d" % (_store_carousel_page + 1)
		carousel_row.add_theme_constant_override("separation", 12)
		_store_list.add_child(carousel_row)
		for item in page_items:
			carousel_row.add_child(_make_seasonal_store_card(item))
		for missing_index in 3 - page_items.size():
			var spacer := Control.new()
			spacer.custom_minimum_size.x = 239.0
			carousel_row.add_child(spacer)
		_refresh_store_selection_styles()
		_refresh_store_detail()
		return
	if _selected_store_item_id == "" or not _item_array_contains(
			filtered_items, _selected_store_item_id):
		_selected_store_item_id = str(filtered_items[0].get("id", ""))
	var index := 0
	while index < filtered_items.size():
		var row := HBoxContainer.new()
		row.name = "PrizeShelfRow%d" % (index / 2 + 1)
		row.add_theme_constant_override("separation", 12)
		_store_list.add_child(row)
		for column_index in 2:
			if index >= filtered_items.size():
				var spacer := Control.new()
				spacer.custom_minimum_size.x = 365.0
				row.add_child(spacer)
				break
			var item := filtered_items[index]
			var card := _make_store_row(item)
			row.add_child(card)
			index += 1
	_refresh_store_selection_styles()
	_refresh_store_detail()


func _configure_store_controller_focus() -> void:
	if not is_inside_tree() or _store_page == null:
		return
	var browse_controls: Array = []
	for control in _store_category_buttons:
		browse_controls.append(control)
	for control in [_store_subcategory_option, _store_cosmetic_option,
			_store_sort_option, find_child("PrizeFavoritesFilter", true, false),
			find_child("PrizeAffordableFilter", true, false), _refresh_button]:
		if control is Control and (control as Control).is_visible_in_tree():
			browse_controls.append(control)
	if not browse_controls.is_empty():
		OneGunUI.chain_focus_vertical(browse_controls)
	var cards: Array = []
	for item_id in _store_card_buttons:
		var card := _store_card_buttons[item_id] as Control
		if card != null and card.is_visible_in_tree():
			cards.append(card)
	if not cards.is_empty():
		OneGunUI.chain_focus_vertical(cards)
		if not browse_controls.is_empty():
			var browse := browse_controls[0] as Control
			var first_card := cards[0] as Control
			browse.focus_neighbor_right = browse.get_path_to(first_card)
			first_card.focus_neighbor_left = first_card.get_path_to(browse)
	var detail_controls: Array = [_store_detail_favorite,
		_store_detail_preview, _store_detail_action]
	detail_controls = detail_controls.filter(func(control):
		return control != null and not (control as BaseButton).disabled)
	if detail_controls.size() >= 2:
		for index in detail_controls.size():
			var control := detail_controls[index] as Control
			var previous := detail_controls[wrapi(index - 1, 0,
				detail_controls.size())] as Control
			var next := detail_controls[wrapi(index + 1, 0,
				detail_controls.size())] as Control
			control.focus_neighbor_left = control.get_path_to(previous)
			control.focus_neighbor_right = control.get_path_to(next)
	if _back_button != null:
		for control_value in cards + detail_controls:
			var control := control_value as Control
			control.focus_neighbor_bottom = control.get_path_to(_back_button)
		var back_target := browse_controls[0] as Control if not browse_controls.is_empty() \
			else (cards[0] as Control if not cards.is_empty() else null)
		if back_target != null:
			_back_button.focus_neighbor_top = _back_button.get_path_to(back_target)
	if _store_page.is_visible_in_tree():
		var owner := get_viewport().gui_get_focus_owner()
		if owner == null or not is_ancestor_of(owner):
			if not browse_controls.is_empty():
				(browse_controls[0] as Control).grab_focus()


func _configure_profile_controller_focus() -> void:
	if _account_page == null or not _account_page.is_visible_in_tree():
		return
	var controls: Array = []
	for node in _account_page.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not control.is_visible_in_tree() \
				or control.focus_mode == Control.FOCUS_NONE:
			continue
		if control is BaseButton and (control as BaseButton).disabled:
			continue
		controls.append(control)
	if _back_button != null:
		controls.append(_back_button)
	if not controls.is_empty():
		OneGunUI.chain_focus_vertical(controls)


func _make_seasonal_store_card(item: Dictionary) -> Control:
	var item_id := str(item.get("id", ""))
	var card := Button.new()
	card.name = "SeasonalStarter_%s" % item_id.validate_node_name()
	card.custom_minimum_size = Vector2(239.0, 444.0)
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.set_meta("store_item_id", item_id)
	card.set_meta("rarity", str(item.get("rarity", "standard")))
	card.pressed.connect(_select_store_item.bind(item_id))
	_store_card_buttons[item_id] = card
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var rarity := str(item.get("rarity", "standard"))
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var rarity_label := OneGunUI.make_label(rarity.to_upper(), OneGunUI.TEXT_XS,
		_rarity_role(rarity), true)
	rarity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(rarity_label)
	if _backend.owns_item(item_id):
		top.add_child(_make_chip("OWNED", "green"))
	var art := PanelContainer.new()
	art.custom_minimum_size.y = 132.0
	art.add_theme_stylebox_override("panel", _glass_style(
		Color(0.006, 0.016, 0.040, 0.96),
		Color(_rarity_color(rarity), 0.45), 14, 1, 2))
	column.add_child(art)
	var monogram := OneGunUI.make_heading(
		_store_art_monogram(SupabaseCosmeticRegistry.item_slot(item)), 44,
		_rarity_role(rarity))
	monogram.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	monogram.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art.add_child(monogram)
	var title := OneGunUI.make_heading(str(item.get("display_name",
		SupabaseCosmeticRegistry.display_name_fallback(item_id))).to_upper(),
		OneGunUI.TEXT_M, "text_bright")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var description := OneGunUI.make_label(str(item.get("description", "")),
		OneGunUI.TEXT_S, "text")
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(description)
	var price := OneGunUI.make_heading("%d GUN TOKENS" % _store_item_price(item),
		OneGunUI.TEXT_M, "gold")
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(price)
	return card


func _make_store_row(item: Dictionary) -> Control:
	var item_id := str(item.get("id", ""))
	var card := Button.new()
	card.name = "PrizeCard_%s" % item_id.validate_node_name()
	card.custom_minimum_size = Vector2(365.0, 148.0)
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.set_meta("store_item_id", item_id)
	card.set_meta("rarity", str(item.get("rarity", "standard")))
	card.pressed.connect(_select_store_item.bind(item_id))
	_store_card_buttons[item_id] = card

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var rarity := str(item.get("rarity", "standard")).to_upper()
	var rarity_label := OneGunUI.make_label(rarity, OneGunUI.TEXT_XS,
		_rarity_role(rarity), true)
	rarity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(rarity_label)
	var owned := bool(_backend.is_authenticated()) and bool(_backend.owns_item(item_id))
	if owned:
		top.add_child(_make_chip("OWNED", "green"))
	if ProgressionManager.is_favorite(item_id):
		top.add_child(_make_chip("★", "gold"))
	var title := OneGunUI.make_heading(str(item.get("display_name",
		SupabaseCosmeticRegistry.display_name_fallback(item_id))).to_upper(),
		OneGunUI.TEXT_L, "text_bright")
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(title)
	var slot := SupabaseCosmeticRegistry.item_slot(item)
	var line := "%s  •  %s" % [
		_locker_style_slot_name(slot),
		"PREVIEW AVAILABLE" if slot == "ceremony_theme" else (
			"VISUAL READY" if SupabaseCosmeticRegistry.has_local_visual(item_id, slot) else "ART PENDING")]
	var meta := OneGunUI.make_label(line, OneGunUI.TEXT_XS, "muted", true)
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(meta)
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom)
	var description := OneGunUI.make_label(str(item.get("description", "")),
		OneGunUI.TEXT_S, "text")
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bottom.add_child(description)
	bottom.add_child(OneGunUI.make_heading("%d" % _store_item_price(item),
		OneGunUI.TEXT_M, "gold"))
	return card


func _select_store_item(item_id: String) -> void:
	_selected_store_item_id = item_id
	_refresh_store_selection_styles()
	_refresh_store_detail()


func _refresh_store_selection_styles() -> void:
	for item_id in _store_card_buttons:
		var card := _store_card_buttons[item_id] as Button
		var selected := str(item_id) == _selected_store_item_id
		var rarity := str(card.get_meta("rarity", "standard"))
		var accent := _rarity_color(rarity)
		var normal := _glass_style(
			Color(0.018, 0.028, 0.065, 0.94) if not selected else Color(0.055, 0.070, 0.13, 0.98),
			Color(accent, 0.34 if not selected else 0.92), 14, 2 if selected else 1, 3)
		card.add_theme_stylebox_override("normal", normal)
		card.add_theme_stylebox_override("hover", _glass_style(
			Color(0.06, 0.075, 0.14, 0.98), Color(accent, 0.88), 14, 2, 5))
		card.add_theme_stylebox_override("pressed", _glass_style(
			Color(0.008, 0.016, 0.042, 0.98), accent, 14, 2, 0))
		card.add_theme_stylebox_override("focus", OneGunUI.focus_ring(normal))


func _refresh_store_detail() -> void:
	if _store_detail_title == null:
		return
	var item := _store_item(_selected_store_item_id)
	if item.is_empty():
		_hide_store_move_preview()
		_store_detail_art.text = "OG"
		_store_detail_title.text = "SELECT A PRIZE"
		_store_detail_meta.text = "LIVE ROTATION"
		_store_detail_description.text = "Choose an item from the shelf to see its details."
		_store_detail_price.text = "—"
		_store_detail_favorite.disabled = true
		_store_detail_preview.visible = false
		_store_detail_action.disabled = true
		_store_detail_action.text = "SELECT ITEM"
		return
	var item_id := str(item.get("id", ""))
	var slot := SupabaseCosmeticRegistry.item_slot(item)
	var rarity := str(item.get("rarity", "standard"))
	_store_detail_art.text = _store_art_monogram(slot)
	if slot == "hat":
		_show_store_hat_preview(item_id)
	else:
		_show_store_move_preview(item_id, slot)
	_store_detail_art.add_theme_color_override("font_color", _rarity_color(rarity))
	_store_detail_title.text = str(item.get("display_name",
		SupabaseCosmeticRegistry.display_name_fallback(item_id))).to_upper()
	_store_detail_meta.text = "%s  •  %s" % [rarity.to_upper(), _locker_style_slot_name(slot)]
	if slot == "hat":
		_store_detail_meta.text += "  •  DRAG / RIGHT STICK TO ROTATE"
	_store_detail_meta.add_theme_color_override("font_color", _rarity_color(rarity))
	_store_detail_description.text = str(item.get("description", "A prize from the current rotation."))
	var display_price := _store_item_price(item)
	_store_detail_price.text = "%d GUN TOKENS" % display_price
	if str(item.get("item_type", "")) == "outfit_bundle":
		_store_detail_price.text += "  •  15% OFF UNOWNED PIECES"
	_store_detail_favorite.disabled = not _backend.is_authenticated()
	_store_detail_favorite.text = "★" if ProgressionManager.is_favorite(item_id) else "☆"
	_store_detail_favorite.variant = "gold" if ProgressionManager.is_favorite(item_id) \
		else "navy"
	_store_detail_preview.visible = slot == "ceremony_theme"
	var authenticated := bool(_backend.is_authenticated())
	var owned := authenticated and bool(_backend.owns_item(item_id))
	_store_detail_action.text = "OWNED — OPEN LOCKER" if owned else (
		"PURCHASE" if authenticated else "SIGN IN TO PURCHASE")
	_store_detail_action.variant = "green" if owned else "gold"
	_store_detail_action.disabled = not authenticated or owned \
		or not bool(item.get("purchasable", false))


func _preview_selected_store_item() -> void:
	if _selected_store_item_id != "":
		_on_preview_theme(_selected_store_item_id)


func _purchase_selected_store_item() -> void:
	if _selected_store_item_id != "":
		ProgressionManager.purchase_item(_selected_store_item_id)


func _on_store_category_selected(index: int) -> void:
	_active_store_category = STORE_CATEGORIES[clampi(index, 0, STORE_CATEGORIES.size() - 1)]
	_store_subcategory = "ALL"
	_store_cosmetic_filter = "ALL"
	_rebuild_store_subcategories()
	for button_index in _store_category_buttons.size():
		_store_category_buttons[button_index].variant = \
			"gold" if button_index == index else "navy"
	if _active_store_category != "AUDIO":
		AudioManager.stop_ceremony_preview()
	_selected_store_item_id = ""
	_store_carousel_page = 0
	_rebuild_store()


func _rebuild_store_subcategories() -> void:
	if _store_subcategory_option == null:
		return
	_store_subcategory_option.clear()
	for option in Catalog.category_subcategories(_active_store_category):
		_store_subcategory_option.add_item(option)
	_store_subcategory_option.select(0)
	_store_cosmetic_option.select(0)
	_store_cosmetic_option.visible = false


func _on_store_subcategory_selected(index: int) -> void:
	_store_subcategory = _store_subcategory_option.get_item_text(index)
	_store_cosmetic_filter = "ALL"
	_store_cosmetic_option.select(0)
	_store_cosmetic_option.visible = _active_store_category == "CHARACTER" \
		and _store_subcategory == "COSMETICS"
	_selected_store_item_id = ""
	_store_carousel_page = 0
	_rebuild_store()


func _on_store_cosmetic_selected(index: int) -> void:
	_store_cosmetic_filter = _store_cosmetic_option.get_item_text(index)
	_selected_store_item_id = ""
	_store_carousel_page = 0
	_rebuild_store()


func _on_store_sort_selected(index: int) -> void:
	_store_sort_id = Catalog.SORT_IDS[clampi(
		index, 0, Catalog.SORT_IDS.size() - 1)]
	_store_carousel_page = 0
	_rebuild_store()


func _change_store_carousel_page(delta: int) -> void:
	_store_carousel_page = maxi(_store_carousel_page + delta, 0)
	_selected_store_item_id = ""
	_rebuild_store()


func _toggle_selected_store_favorite() -> void:
	if _selected_store_item_id == "":
		return
	await ProgressionManager.set_favorite(_selected_store_item_id,
		not ProgressionManager.is_favorite(_selected_store_item_id))
	_rebuild_store()


func _store_catalog_source() -> Array[Dictionary]:
	if not ProgressionManager.catalog_items.is_empty():
		return ProgressionManager.catalog_items.duplicate(true)
	var result: Array[Dictionary] = []
	for item in _backend.shop_items:
		result.append(Catalog.normalize_item(item))
	return result


func _catalog_usage_counts() -> Dictionary:
	var result := {}
	for item_id in ProgressionManager.usage:
		result[item_id] = ProgressionManager.usage_count(str(item_id))
	return result


func _on_extended_catalog_updated(_items: Array) -> void:
	_rebuild_store()


func _on_catalog_preferences_updated(_item_ids: Array) -> void:
	_rebuild_store()


func _on_catalog_usage_updated(_usage: Dictionary) -> void:
	if _store_sort_id == "most_used":
		_rebuild_store()


func _show_page(index: int) -> void:
	_active_page_index = clampi(index, 0, 1)
	if _active_page_index == 1:
		_refresh_store_detail()
	else:
		AudioManager.stop_ceremony_preview()
		_hide_store_move_preview()
	if _account_page != null:
		_account_page.visible = _active_page_index == 0
	if _store_page != null:
		_store_page.visible = _active_page_index == 1
	if _inventory_page != null:
		_inventory_page.visible = false
	if _screen_title != null:
		_screen_title.text = "PRIZE COUNTER" if _active_page_index == 1 else "COMPETITOR PROFILE"
	if _store_footer_note != null:
		_store_footer_note.visible = _active_page_index == 1
	if _active_page_index == 0:
		_configure_profile_controller_focus.call_deferred()
	else:
		_configure_store_controller_focus.call_deferred()
	_replace_backdrop(_active_page_index)


func _refresh_account() -> void:
	super._refresh_account()
	if _profile_display_label == null:
		return
	var display_name := str(PlayerPrefs.get_setting("player_name"))
	var username := str(_backend.current_account_name())
	_profile_display_label.text = display_name.to_upper()
	_profile_handle_label.text = "@%s" % (username if username != "" else "ACCOUNT NAME NEEDED")
	_profile_portrait.set_appearance(str(PlayerPrefs.get_setting("character_skin_id")),
		str(PlayerPrefs.get_setting("character_model_id")))
	_profile_token_label.text = "%d GUN TOKENS" % int(_backend.gun_tokens)
	_refresh_profile_progression()


func _refresh_currency() -> void:
	super._refresh_currency()
	_refresh_profile_progression()
	if _profile_token_label != null:
		_profile_token_label.text = "%d GUN TOKENS" % int(_backend.gun_tokens)


func _set_feedback(message: String, is_error: bool) -> void:
	super._set_feedback(message, is_error)
	if _feedback_label != null:
		_feedback_label.visible = not message.strip_edges().is_empty()


func _on_purchase_succeeded(item_id: String) -> void:
	super._on_purchase_succeeded(item_id)
	_selected_store_item_id = item_id
	_refresh_store_detail()


func _apply_responsive_layout() -> void:
	if _canvas == null:
		return
	var available := size
	if available.x <= 0.0 or available.y <= 0.0:
		available = get_viewport_rect().size
	var scale_factor := minf(available.x / BASE_SIZE.x, available.y / BASE_SIZE.y)
	_canvas.scale = Vector2.ONE * scale_factor
	_canvas.position = (available - BASE_SIZE * scale_factor) * 0.5


func _replace_backdrop(page_index: int) -> void:
	if _canvas == null:
		return
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.free()
	_backdrop = HUB_BACKDROP_SCRIPT.new()
	_backdrop.name = "PrizeCounterAtmosphere" if page_index == 1 else "ProfileAtmosphere"
	_backdrop.position = Vector2.ZERO
	_backdrop.size = BASE_SIZE
	_backdrop.configure(PRIZE_BACKDROP if page_index == 1 else PROFILE_BACKDROP,
		MenuHubBackdrop.Variant.PRIZE_COUNTER if page_index == 1 \
		else MenuHubBackdrop.Variant.PROFILE)
	_canvas.add_child(_backdrop)
	_canvas.move_child(_backdrop, 0)


func _animate_entrance() -> void:
	if _reduced_motion_enabled():
		return
	_canvas.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_canvas, "modulate:a", 1.0, 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _make_panel(minimum: Vector2, accent_role: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.add_theme_stylebox_override("panel", _glass_style(
		Color(0.010, 0.020, 0.050, 0.94),
		Color(OneGunUI.color(accent_role), 0.46), 16, 2, 8))
	return panel


func _panel_column(panel: PanelContainer, padding: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, padding)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	return column


func _glass_style(background: Color, border: Color, radius: int,
		border_width: int, shadow_size: int) -> StyleBoxFlat:
	return OneGunUI.style_box(background, border, radius, border_width,
		shadow_size, 0.0, Color(0.0, 0.0, 0.0, 0.55))


func _make_chip(text: String, role: String) -> Label:
	var label := OneGunUI.make_label(text, OneGunUI.TEXT_XS,
		"ink" if role in ["gold", "green"] else "text_bright", true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0.0, 30.0)
	label.add_theme_stylebox_override("normal", OneGunUI.style_box(
		Color(OneGunUI.color(role), 0.88 if role in ["gold", "green"] else 0.46),
		Color(OneGunUI.color(role), 0.92), OneGunUI.RADIUS_CHIP, 1, 0, 12.0))
	return label


func _make_feature_line(symbol: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(OneGunUI.make_heading(symbol, OneGunUI.TEXT_M, "gold"))
	row.add_child(OneGunUI.make_label(text, OneGunUI.TEXT_M, "text"))
	return row


func _make_stat_tile(title: String, value: String, role: String) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(0.0, 96.0)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.add_theme_stylebox_override("panel", _glass_style(
		Color(0.012, 0.028, 0.060, 0.90), Color(OneGunUI.color(role), 0.35), 12, 1, 2))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(column)
	var value_label := OneGunUI.make_heading(value, 28, role)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(value_label)
	_profile_value_labels[title] = value_label
	var title_label := OneGunUI.make_label(title, OneGunUI.TEXT_XS, "muted", true)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title_label)
	return tile


func _make_history_row(result: String, mode: String, map_name: String,
		rewards: String, header: bool) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size.y = 54.0
	row.add_theme_stylebox_override("panel", _glass_style(
		Color(0.02, 0.038, 0.075, 0.88 if not header else 0.98),
		Color(OneGunUI.color("gold"), 0.28), 10, 1, 0))
	var grid := GridContainer.new()
	grid.columns = 4
	row.add_child(grid)
	for data in [[result, 150.0], [mode, 360.0], [map_name, 190.0], [rewards, 200.0]]:
		var label := OneGunUI.make_label(str(data[0]), OneGunUI.TEXT_S,
			"gold" if header else "muted", header)
		label.custom_minimum_size.x = float(data[1])
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(label)
	return row


func _rarity_color(rarity: String) -> Color:
	match rarity.to_lower():
		"legendary": return Color(1.0, 0.48, 0.10)
		"epic": return OneGunUI.color("purple").lightened(0.18)
		"rare": return OneGunUI.color("cyan")
		"uncommon": return OneGunUI.color("green")
		_: return OneGunUI.color("text")


func _rarity_role(rarity: String) -> String:
	match rarity.to_lower():
		"epic": return "purple"
		"rare": return "cyan"
		"uncommon": return "green"
		_: return "gold" if rarity.to_lower() == "legendary" else "text"


func _locker_style_slot_name(slot: String) -> String:
	if slot == "ceremony_theme":
		return "WINNERS CIRCLE MUSIC"
	if slot == "emote":
		return "PODIUM POSE"
	if slot in ["victory_dance", "round_victory_move"]:
		return "VICTORY DANCE"
	if slot == "":
		return "COSMETIC"
	return slot.replace("_", " ").to_upper()


func _store_art_monogram(slot: String) -> String:
	match slot:
		"ceremony_theme": return "♫"
		"gun_skin", "melee_skin": return "OG"
		"emote", "victory_dance", "round_victory_move": return "★"
		"hat", "accessory", "character_skin": return "◆"
	return "OG"


func _store_item_price(item: Dictionary) -> int:
	if str(item.get("item_type", "")) != "outfit_bundle":
		return maxi(int(item.get("price", 0)), 0)
	var component_total := 0
	var component_ids := ProgressionManager.components_for(str(item.get("id", "")))
	for component_id in component_ids:
		if _backend.owns_item(component_id):
			continue
		var component := ProgressionManager.item(component_id)
		if component.is_empty():
			component = _backend.catalog_item(component_id)
		component_total += maxi(int(component.get("price", 0)), 0)
	if component_total <= 0:
		return maxi(int(item.get("price", 0)), 0)
	# Mirrors purchase_shop_item(): outfits cost 85% of only the pieces the
	# player does not already own, rounded up on the server.
	return ceili(float(component_total) * 0.85)


func _store_item(item_id: String) -> Dictionary:
	var extended := ProgressionManager.item(item_id)
	return extended if not extended.is_empty() else _backend.catalog_item(item_id)


func _item_array_contains(items: Array[Dictionary], item_id: String) -> bool:
	for item in items:
		if str(item.get("id", "")) == item_id:
			return true
	return false


func _reduced_motion_enabled() -> bool:
	var accessibility := get_node_or_null("/root/AccessibilityManager")
	return accessibility != null \
		and accessibility.has_method("reduced_motion_enabled") \
		and bool(accessibility.call("reduced_motion_enabled"))


func _on_progression_updated(_snapshot: Dictionary) -> void:
	_refresh_profile_progression()


func _refresh_profile_progression() -> void:
	var snapshot: Dictionary = ProgressionManager.progression
	var progress = snapshot.get("progress", {})
	var career = snapshot.get("career", {})
	if not progress is Dictionary:
		progress = {}
	if not career is Dictionary:
		career = {}
	var season_level := int(progress.get("season_level", 1))
	var career_level := int(career.get(
		"career_level", int(career.get("levels_earned", 0)) + 1))
	_set_profile_value("SEASON LEVEL", str(season_level))
	_set_profile_value("SEASON PRESTIGE", str(int((season_level - 1) / 100)))
	_set_profile_value("CLASSIC TROPHIES", str(int(progress.get("trophies", 0))))
	_set_profile_value("CAREER LEVEL", str(career_level))
	_set_profile_value("CAREER PRESTIGE", str(int((career_level - 1) / 100)))
	if _profile_trophy_label != null:
		_profile_trophy_label.text = "%d TROPHIES" % int(progress.get("trophies", 0))
	if _trophy_label != null:
		_trophy_label.text = "TROPHIES: %d" % int(progress.get("trophies", 0))
	var mode_stats := _mode_stats(_profile_mode_id)
	if mode_stats.is_empty() and _profile_mode_id == GameConfig.MODE_ONE_GUN:
		mode_stats = {
			"wins": progress.get("classic_wins", 0),
			"matches": progress.get("official_matches", 0),
			"round_wins": progress.get("round_wins", 0),
			"kills": progress.get("kills", 0),
			"disarms": progress.get("disarms", 0),
		}
	_set_profile_value("CAREER WINS", str(int(mode_stats.get("wins", 0))))
	_set_profile_value("MATCHES", str(int(mode_stats.get("matches", 0))))
	var best_finish = mode_stats.get("best_finish", null)
	_set_profile_value("BEST FINISH", "—" if best_finish == null \
		else _ordinal(int(best_finish)))
	_set_profile_value("KILLS", str(int(mode_stats.get("kills", 0))))
	_set_profile_value("DISARMS", str(int(mode_stats.get("disarms", 0))))
	_set_profile_value("ROUND WINS", str(int(mode_stats.get("round_wins", 0))))
	_rebuild_legacy_records()
	_rebuild_match_history_records()


func _set_profile_value(title: String, value: String) -> void:
	var label := _profile_value_labels.get(title) as Label
	if label != null:
		label.text = value


func _mode_stats(mode_id: String) -> Dictionary:
	var records = ProgressionManager.progression.get("mode_stats", [])
	if records is Array:
		for value in records:
			if value is Dictionary and str(value.get("mode", "")) == mode_id:
				return value.duplicate(true)
	return {}


func _rebuild_legacy_records() -> void:
	if _legacy_shelves == null:
		return
	_clear_children(_legacy_shelves)
	var archives = ProgressionManager.progression.get("legacy", [])
	if not archives is Array or archives.is_empty():
		var current := _make_profile_record_panel("★", "BETA SEASON",
			"IN PROGRESS", "cyan")
		_legacy_shelves.add_child(current)
		for index in 2:
			_legacy_shelves.add_child(_make_profile_record_panel(
				"☆", "FUTURE SEASON", "ARCHIVE SLOT", "muted"))
		return
	for value in archives:
		if not value is Dictionary:
			continue
		var detail := "SEASON LVL %d / P%d  •  %d TROPHIES  •  %d WINS  •  CAREER LVL %d / P%d" % [
			int(value.get("final_level", 1)), int(value.get("final_prestige", 0)),
			int(value.get("trophies", 0)), int(value.get("classic_wins", 0)),
			int(value.get("career_level_snapshot", 1)),
			int(value.get("career_prestige_snapshot", 0))]
		_legacy_shelves.add_child(_make_profile_record_panel(
			"★", str(value.get("season_name", "SEASON")).to_upper(), detail, "gold"))


func _make_profile_record_panel(symbol: String, title: String,
		detail: String, role: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, 250.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _glass_style(
		Color(0.012, 0.030, 0.052, 0.90),
		Color(OneGunUI.color(role), 0.34), 14, 1, 2))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var star := OneGunUI.make_heading(symbol, 48, role)
	star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(star)
	var heading := OneGunUI.make_heading(title, OneGunUI.TEXT_M, "text")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var copy := OneGunUI.make_label(detail, OneGunUI.TEXT_S, role, true)
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(copy)
	return panel


func _rebuild_match_history_records() -> void:
	if _history_rows == null:
		return
	_clear_children(_history_rows)
	var history = ProgressionManager.progression.get("match_history", [])
	if not history is Array or history.is_empty():
		_history_rows.add_child(_make_history_row(
			"—", "AWAITING OFFICIAL MATCH", "—", "—", false))
		return
	for value in history:
		if not value is Dictionary:
			continue
		var placement := int(value.get("placement", 0))
		var map_name := str(value.get("map_id", "UNKNOWN")).get_file().get_basename()
		var rewards := "+%d XP  •  +%d GT%s" % [
			int(value.get("xp_delta", 0)), int(value.get("gun_tokens_delta", 0)),
			"  •  +1★" if int(value.get("trophy_delta", 0)) > 0 else ""]
		_history_rows.add_child(_make_history_row(
			_ordinal(placement), WinnersResultData.mode_display_name(
				str(value.get("mode", GameConfig.MODE_ONE_GUN))), map_name.to_upper(),
			rewards, false))


func _ordinal(value: int) -> String:
	if value <= 0:
		return "—"
	var suffix := "TH"
	if value % 100 not in [11, 12, 13]:
		match value % 10:
			1: suffix = "ST"
			2: suffix = "ND"
			3: suffix = "RD"
	return "%d%s" % [value, suffix]
