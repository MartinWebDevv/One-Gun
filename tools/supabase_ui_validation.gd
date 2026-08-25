extends SceneTree

# Runtime-only validation for Profile and Prize Counter. It seeds the manager
# in memory and never writes a session or calls the live backend.

var _failed := false


func _initialize() -> void:
	var supabase = root.get_node_or_null("SupabaseManager")
	if supabase != null:
		supabase.project_url = ""
		supabase.publishable_key = ""
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var supabase = root.get_node("SupabaseManager")
	var prefs = root.get_node("PlayerPrefs")
	_validate_helpers(supabase)
	var original_display_name := str(prefs.settings.get("player_name", "Player"))
	prefs.settings["player_name"] = "ArenaAlias"
	_seed_runtime_data(supabase)

	var overlay_script = load("res://UI/player_hub_overlay.gd")
	var overlay = overlay_script.new()
	overlay.configure("prize_counter")
	root.add_child(overlay)
	await process_frame
	await process_frame

	_check(overlay.find_child("SupabaseEmail", true, false) is LineEdit,
		"Profile email field was not built")
	_check(overlay.find_child("SupabasePassword", true, false) is LineEdit,
		"Profile password field was not built")
	_check(overlay.find_child("SupabaseAccountName", true, false) is LineEdit,
		"Create Account did not include Account Name")
	_check(overlay.find_child("AuthenticationModeTabs", true, false) != null,
		"Sign In and Create Account modes were not built")
	_check(overlay.find_child("ProfileSectionTabs", true, false) != null,
		"Profile Overview/Stats/Legacy Hall/Match History tabs were not built")
	_check(overlay.find_child("PrizeCounterCategories", true, false) != null,
		"Prize Counter category tabs were not built")
	_check(overlay.get("_store_page").visible,
		"Prize Counter was not the configured initial page")

	var account_status = overlay.get("_account_status") as Label
	_check(account_status != null and account_status.text.contains("TESTER"),
		"authenticated Account Name did not render")
	var seeded_profile: Dictionary = supabase.profile.duplicate(true)
	supabase.profile["username"] = null
	overlay.call("_refresh_account")
	var rename_button = overlay.get("_rename_button") as Button
	_check(account_status.text.contains("CLOUD PROFILE"),
		"database null Account Name did not use the Cloud Profile fallback")
	_check(rename_button != null and rename_button.text == "SET ACCOUNT NAME" \
			and not rename_button.disabled,
		"existing unnamed account could not claim its initial Account Name")
	supabase.profile = seeded_profile
	overlay.call("_refresh_account")
	var currency = overlay.get("_currency_label") as Label
	_check(currency != null and currency.text == "GUN TOKENS: 4321",
		"Gun Token balance did not render")
	var display_name = overlay.get("_display_name_field") as LineEdit
	_check(display_name != null and display_name.text == "ArenaAlias",
		"in-game Display Name was not kept separate from Account Name")
	_check(rename_button != null and not rename_button.disabled,
		"expired 14-day rename cooldown did not enable account rename")

	var store_list = overlay.get("_store_list") as VBoxContainer
	_check(store_list != null and store_list.find_children(
		"PrizeCard_*", "Button", true, false).size() == 5,
		"Featured Prize Counter did not render the public rotation")
	var store_text := _descendant_text(store_list)
	_check(overlay.find_children(
		"PrizeMoveViewport", "SubViewport", true, false).size() == 1,
		"Prize Counter should build exactly one reusable move-preview viewport")
	_check(not store_text.contains("FOUNDER CROWN"),
		"hidden founder crown appeared in the public Prize Counter")
	_check(store_text.contains("DEEP ORBIT") and store_text.contains("PREVIEW"),
		"music unlock was not previewable in the Prize Counter")

	overlay.call("_on_store_category_selected", 1)
	await process_frame
	store_text = _descendant_text(store_list)
	_check(store_text.contains("COWBOY HAT") and not store_text.contains("GOLDEN GUN"),
		"Character category did not isolate character cosmetics")
	overlay.call("_on_store_category_selected", 2)
	await process_frame
	store_text = _descendant_text(store_list)
	_check(store_text.contains("GOLDEN GUN") and not store_text.contains("COWBOY HAT"),
		"Weapons category did not isolate weapon cosmetics")
	overlay.call("_on_store_category_selected", 3)
	await process_frame
	store_text = _descendant_text(store_list)
	_check(store_text.contains("FRESH FOOTWORK") and store_text.contains("BIRDIE BOOGIE"),
		"Victory category did not expose both podium and round move products")
	var move_preview = overlay.get("_store_move_preview_container") as SubViewportContainer
	var move_viewport = overlay.get("_store_move_preview_viewport") as SubViewport
	var move_visual = overlay.get("_store_move_preview_visual") as Node3D
	var move_player = overlay.get("_store_move_preview_player") as AnimationPlayer
	var move_animation := str(overlay.get("_store_move_preview_animation"))
	var detail_art = overlay.get("_store_detail_art") as Label
	_check(move_preview != null and move_preview.visible
		and move_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS
		and move_visual != null and move_player != null
		and move_animation != "" and move_player.current_animation == move_animation
		and detail_art != null and not detail_art.visible,
		"Victory inspection did not replace the monogram with a live animation preview")
	overlay.call("_on_store_category_selected", 4)
	await process_frame
	_check(not move_preview.visible
		and move_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
		and detail_art.visible,
		"leaving Victory did not pause the 3D preview and restore ordinary item art")
	store_text = _descendant_text(store_list)
	_check(store_text.contains("DEEP ORBIT") and store_text.contains("WINNERS CIRCLE MUSIC"),
		"Music category did not isolate Winners Circle themes")

	overlay.call("_show_page", 0)
	overlay.call("_refresh_all")
	await process_frame
	_check(overlay.get("_account_page").visible,
		"Profile page did not open")
	_check(str(prefs.settings.get("player_name", "")) == "ArenaAlias",
		"cloud Account Name overwrote the in-game Display Name")

	# Public catalog rows remain browseable after logout, while purchase actions
	# are visibly gated behind authentication.
	overlay.call("_show_page", 1)
	overlay.call("_on_store_category_selected", 0)
	supabase.call("_clear_runtime_session", false)
	overlay.call("_refresh_all")
	await process_frame
	store_text = _descendant_text(store_list)
	_check(store_list.find_children(
		"PrizeCard_*", "Button", true, false).size() == 5,
		"signed-out public Prize Counter rows disappeared")
	var detail_action = overlay.get("_store_detail_action") as Button
	_check(detail_action != null and detail_action.text == "SIGN IN TO PURCHASE",
		"signed-out purchase controls were not authentication-gated")
	overlay.call("_show_page", 0)
	overlay.call("_show_auth_mode", 1)
	await process_frame
	var account_name_field = overlay.find_child(
		"SupabaseAccountName", true, false) as LineEdit
	_check(account_name_field != null and account_name_field.visible,
		"Account Name was not shown in Create Account mode")

	overlay.queue_free()
	prefs.settings["player_name"] = original_display_name
	if _failed:
		quit(1)
		return
	print("SUPABASE UI VALIDATION OK: Profile identity, auth onboarding, categories, and signed-out browsing")
	quit(0)


func _validate_helpers(supabase: Node) -> void:
	_check(bool(supabase.call("_looks_like_email", "tester@example.com")),
		"valid email was rejected")
	_check(not bool(supabase.call("_looks_like_email", "not-an-email")),
		"invalid email was accepted")
	_check(str(supabase.call("account_name_error", "Tester_01")) == "",
		"valid Account Name was rejected")
	_check(str(supabase.call("account_name_error", "_Tester")).contains("begin"),
		"leading underscore Account Name was accepted")
	_check(str(supabase.call("account_name_error", "ThisAccountNameIsFarTooLong")).contains("exceed"),
		"overlong Account Name was silently truncated")
	var original_profile: Dictionary = supabase.profile.duplicate(true)
	supabase.profile = {"username": null}
	_check(str(supabase.call("current_account_name")) == "",
		"database null rendered as a literal Account Name")
	supabase.profile = {"username": "<null>"}
	_check(str(supabase.call("current_account_name")) == "",
		"legacy <null> placeholder rendered as an Account Name")
	supabase.profile = original_profile
	_check(bool(supabase.call("_is_forbidden_credential", "sb_secret_test")),
		"opaque secret key was not rejected")
	var payload := Marshalls.utf8_to_base64('{"role":"service_role"}') \
		.replace("+", "-").replace("/", "_").trim_suffix("=")
	_check(bool(supabase.call("_is_forbidden_credential", "x.%s.x" % payload)),
		"legacy service-role JWT was not rejected")
	var null_loadout := SupabaseCosmeticRegistry.sanitize_loadout({"hat": null})
	_check(str(null_loadout.get("hat", "invalid")) == "",
		"database null was not normalized to an empty cosmetic slot")


func _seed_runtime_data(supabase: Node) -> void:
	var progression = root.get_node("ProgressionManager")
	progression.catalog_items.clear()
	supabase.access_token = "validation-access-token"
	supabase.refresh_token = "validation-refresh-token"
	supabase.authenticated_user_id = "00000000-0000-0000-0000-000000000002"
	supabase.access_token_expires_at = int(Time.get_unix_time_from_system()) + 3600
	supabase.login_state = "authenticated"
	supabase.profile = {
		"id": supabase.authenticated_user_id,
		"username": "Tester",
		"username_changed_at": "2020-01-01T00:00:00Z",
	}
	supabase.gun_tokens = 4321
	supabase.shop_items.clear()
	supabase.shop_items.append({
		"id": "cowboy_hat", "display_name": "Cowboy Hat",
		"item_type": "hat", "description": "Test hat", "price": 100,
		"rarity": "common", "purchasable": true,
		"shop_visible": true, "active": true, "rotation_scope": "daily",
	})
	supabase.shop_items.append({
		"id": "golden_gun_skin", "display_name": "Golden Gun Skin",
		"item_type": "gun_skin", "description": "Test gun finish",
		"price": 500, "rarity": "rare", "purchasable": true,
		"shop_visible": true, "active": true, "rotation_scope": "monthly",
	})
	supabase.shop_items.append({
		"id": "podium_fresh_footwork", "display_name": "Fresh Footwork",
		"item_type": "victory_dance", "description": "Test podium dance",
		"price": 1700, "rarity": "rare", "purchasable": true,
		"shop_visible": true, "active": true, "rotation_scope": "monthly",
		"category": "victory", "subcategory": "dances",
	})
	supabase.shop_items.append({
		"id": "round_birdie_boogie", "display_name": "Birdie Boogie",
		"item_type": "victory_dance", "description": "Test round move",
		"price": 900, "rarity": "uncommon", "purchasable": true,
		"shop_visible": true, "active": true, "rotation_scope": "daily",
		"category": "victory", "subcategory": "dances",
	})
	supabase.shop_items.append({
		"id": "wc_theme_deep_orbit", "display_name": "Deep Orbit",
		"item_type": "ceremony_theme", "description": "Test ceremony theme",
		"price": 2200, "rarity": "legendary", "purchasable": true,
		"shop_visible": true, "active": true, "rotation_scope": "seasonal_starter",
	})
	supabase.inventory.clear()
	supabase.inventory.append({"item_id": "cowboy_hat", "source": "purchase"})
	supabase.inventory.append({"item_id": "founder_crown", "source": "founder_grant"})
	supabase.inventory.append({"item_id": "wc_theme_deep_orbit", "source": "purchase"})
	supabase.set("_owned_item_ids", {
		"cowboy_hat": true, "founder_crown": true,
		"wc_theme_deep_orbit": true,
	})
	supabase.loadout = SupabaseCosmeticRegistry.sanitize_loadout({
		"hat": "founder_crown",
		"ceremony_theme": "wc_theme_deep_orbit",
	})


func _descendant_text(root_node: Node) -> String:
	var result := ""
	if root_node == null:
		return result
	for child in root_node.find_children("*", "Label", true, false):
		result += "%s\n" % str((child as Label).text)
	for child in root_node.find_children("*", "Button", true, false):
		result += "%s\n" % str((child as Button).text)
	return result


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("SUPABASE UI VALIDATION FAILED: %s" % message)
