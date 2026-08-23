extends SceneTree

# Runtime-only validation for the account/store/inventory overlay. It seeds the
# manager in memory and never writes a session or calls the live backend.

var _failed := false


func _initialize() -> void:
	# Keep this harness deterministic: the live public-catalog policy is checked
	# separately, and this test must never depend on network availability.
	var supabase = root.get_node_or_null("SupabaseManager")
	if supabase != null:
		supabase.project_url = ""
		supabase.publishable_key = ""
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var supabase = root.get_node("SupabaseManager")
	_validate_helpers(supabase)
	_seed_runtime_data(supabase)
	var overlay_script = load("res://UI/supabase_overlay.gd")
	var overlay = overlay_script.new()
	root.add_child(overlay)
	await process_frame
	await process_frame

	_check(overlay.find_child("SupabaseEmail", true, false) is LineEdit,
		"account email field was not built")
	_check(overlay.find_child("SupabasePassword", true, false) is LineEdit,
		"account password field was not built")
	var account_status = overlay.get("_account_status") as Label
	_check(account_status != null and account_status.text.contains("TESTER"),
		"authenticated profile status did not render")
	var currency = overlay.get("_currency_label") as Label
	_check(currency != null and currency.text == "GUN TOKENS: 4321",
		"Gun Token balance did not render")

	var store_list = overlay.get("_store_list") as VBoxContainer
	var inventory_list = overlay.get("_inventory_list") as VBoxContainer
	_check(store_list != null and store_list.get_child_count() == 3,
		"Prize Counter did not render the public cosmetic items")
	_check(inventory_list != null and inventory_list.get_child_count() == 3,
		"Locker did not render all owned cosmetics")
	var store_text := _descendant_text(store_list)
	var inventory_text := _descendant_text(inventory_list)
	_check(not store_text.contains("FOUNDER CROWN"),
		"hidden founder crown appeared in the public store")
	_check(inventory_text.contains("FOUNDER CROWN"),
		"owned hidden founder crown did not appear in inventory")
	_check(inventory_text.contains("DEEP ORBIT") \
			and inventory_text.contains("CEREMONY THEME") \
			and inventory_text.contains("EQUIPPED"),
		"owned ceremony theme did not render as a ready equipped unlock")
	_check(store_text.contains("PREVIEW") and inventory_text.contains("PREVIEW"),
		"ceremony themes were not previewable before purchase or equip")
	_check(inventory_text.contains("ART PENDING"),
		"missing local cosmetic art was not surfaced safely")

	# Public catalog rows remain browseable after logout, while purchase actions
	# are visibly gated behind authentication.
	supabase.call("_clear_runtime_session", false)
	overlay.call("_refresh_all")
	await process_frame
	store_text = _descendant_text(store_list)
	_check(store_list.get_child_count() == 3,
		"signed-out public Prize Counter rows disappeared")
	_check(store_text.contains("SIGN IN TO BUY"),
		"signed-out purchase controls were not authentication-gated")
	_check(not store_text.contains("FOUNDER CROWN"),
		"hidden founder crown appeared in the signed-out public store")

	overlay.queue_free()
	if _failed:
		quit(1)
		return
	print("SUPABASE UI VALIDATION OK: account, currency, public store, hidden ownership, and art fallback")
	quit(0)


func _validate_helpers(supabase: Node) -> void:
	_check(bool(supabase.call("_looks_like_email", "tester@example.com")),
		"valid email was rejected")
	_check(not bool(supabase.call("_looks_like_email", "not-an-email")),
		"invalid email was accepted")
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
	supabase.access_token = "validation-access-token"
	supabase.refresh_token = "validation-refresh-token"
	supabase.authenticated_user_id = "00000000-0000-0000-0000-000000000002"
	supabase.access_token_expires_at = int(Time.get_unix_time_from_system()) + 3600
	supabase.login_state = "authenticated"
	supabase.profile = {"id": supabase.authenticated_user_id, "username": "Tester"}
	supabase.gun_tokens = 4321
	supabase.shop_items.clear()
	supabase.shop_items.append({
		"id": "cowboy_hat", "display_name": "Cowboy Hat",
		"item_type": "hat", "description": "Test hat", "price": 100,
		"rarity": "common", "purchasable": true,
		"shop_visible": true, "active": true,
	})
	supabase.shop_items.append({
		"id": "golden_gun_skin", "display_name": "Golden Gun Skin",
		"item_type": "gun_skin", "description": "Test gun finish",
		"price": 500, "rarity": "rare", "purchasable": true,
		"shop_visible": true, "active": true,
	})
	supabase.shop_items.append({
		"id": "wc_theme_deep_orbit", "display_name": "Deep Orbit",
		"item_type": "ceremony_theme", "description": "Test ceremony theme",
		"price": 2200, "rarity": "legendary", "purchasable": true,
		"shop_visible": true, "active": true,
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
