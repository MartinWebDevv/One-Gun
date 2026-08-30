extends SceneTree

# Runtime-only validation for Profile and Prize Counter. It seeds the manager
# in memory and never writes a session or calls the live backend.

const HatRegistry = preload("res://models/cosmetics/hats/hat_cosmetic_registry.gd")
const GIFT_CHARACTER_ITEM_IDS: Array[String] = [
	"character_goldfish_bag_man", "character_eye_wizard",
	"character_mr_mushroom", "character_mr_poop", "character_mr_salt",
	"character_spooky_witch",
]

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
	var original_model_id := str(prefs.settings.get("character_model_id", "male"))
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
	var back_button := overlay.find_child("ClosePlayerHub", true, false) as Button
	var canvas := overlay.find_child("PlayerHubCanvas", true, false) as Control
	_check(back_button != null and canvas != null and back_button.text == "BACK"
			and str(back_button.get("variant")) == "navy"
			and back_button.get_global_rect().get_center().x
				< canvas.get_global_rect().get_center().x
			and back_button.get_global_rect().get_center().y
				> canvas.get_global_rect().get_center().y,
		"Profile and Prize Counter share the blue bottom-left Back control")
	var browse_panel := overlay.find_child(
		"PrizeBrowseCounterPanel", true, false) as Control
	var affordable_filter := overlay.find_child(
		"PrizeAffordableFilter", true, false) as Control
	var footer_panel := overlay.find_child("PlayerHubFeedback", true, false) as Control
	var rotation_notice := overlay.find_child(
		"PrizeCounterRotationNotice", true, false) as Label
	_check(browse_panel != null and affordable_filter != null
			and browse_panel.get_global_rect().encloses(
				affordable_filter.get_global_rect()),
		"Browse Counter border does not wrap Affordable")
	_check(browse_panel != null and back_button != null
			and not browse_panel.get_global_rect().intersects(
				back_button.get_global_rect(), true),
		"Browse Counter still covers the bottom-left Back button")
	_check(rotation_notice != null and footer_panel != null
			and rotation_notice.text == overlay.PRIZE_ROTATION_NOTICE
			and footer_panel.is_ancestor_of(rotation_notice)
			and rotation_notice.visible,
		"public-rotation notice was not moved into the bottom footer bar")
	_check(back_button != null and overlay.get("_store_page") != null
			and back_button.get_index() > overlay.get("_store_page").get_index(),
		"Prize Counter Back button is not above the page interaction layer")
	for test_size in [Vector2(1280.0, 720.0), Vector2(1600.0, 900.0),
			Vector2(1920.0, 1080.0)]:
		overlay.size = test_size
		overlay.call("_apply_responsive_layout")
		await process_frame
		_check(not browse_panel.get_global_rect().intersects(
				back_button.get_global_rect(), true),
			"Browse Counter covers Back at %dx%d" % [
				int(test_size.x), int(test_size.y)])

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
	for item_id in GIFT_CHARACTER_ITEM_IDS:
		var gift_name := SupabaseCosmeticRegistry.display_name_fallback(
			item_id).to_upper()
		_check(not store_text.contains(gift_name),
			"gift-only character model appeared in the public Prize Counter: %s" % item_id)
	_check(store_text.contains("DEEP ORBIT") and store_text.contains("PREVIEW"),
		"music unlock was not previewable in the Prize Counter")

	overlay.call("_on_store_category_selected", 1)
	await process_frame
	store_text = _descendant_text(store_list)
	_check(store_text.contains("COWBOY HAT") and not store_text.contains("GOLDEN GUN"),
		"Character category did not isolate character cosmetics")
	overlay.call("_select_store_item", "hat_cowboy_classic")
	await process_frame
	await process_frame
	var hat_preview = overlay.get("_store_move_preview_container") as SubViewportContainer
	var hat_viewport = overlay.get("_store_move_preview_viewport") as SubViewport
	var hat_pivot = overlay.get("_store_move_preview_pivot") as Node3D
	var hat_camera = overlay.get("_store_move_preview_camera") as Camera3D
	var hat_visual = overlay.get("_store_move_preview_visual") as Node3D
	var hat_player = overlay.get("_store_move_preview_player") as AnimationPlayer
	var hat_socket = hat_visual.call("get_headwear_socket") as Marker3D \
		if hat_visual != null else null
	var hat_camera_distance := absf(
		hat_camera.global_position.z - hat_socket.global_position.z) \
		if hat_camera != null and hat_socket != null else 0.0
	_check(bool(overlay.get("_store_hat_preview_active"))
		and hat_preview != null and hat_preview.visible
		and hat_preview.mouse_filter == Control.MOUSE_FILTER_STOP
		and hat_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS
		and hat_player != null and hat_player.current_animation == "idle"
		and hat_player.is_playing()
		and hat_camera != null and hat_camera_distance >= 2.35 \
		and hat_camera_distance <= 5.20
		and hat_socket != null
		and hat_socket.find_child("HatVisual", false, false) != null,
		"Hat inspection did not use the animated interactive shoulder-up 3D framing")
	var mouse_rotation: float = hat_pivot.rotation.y
	overlay.set("_store_hat_preview_dragging", true)
	var mouse_motion := InputEventMouseMotion.new()
	mouse_motion.relative = Vector2(24.0, 0.0)
	overlay.call("_on_store_hat_preview_gui_input", mouse_motion)
	await process_frame
	_check(not is_equal_approx(hat_pivot.rotation.y, mouse_rotation),
		"Hat inspection did not rotate from a manual mouse drag")
	var pivot_screen := hat_camera.unproject_position(hat_pivot.global_position)
	_check(absf(pivot_screen.x - float(hat_viewport.size.x) * 0.5) < 1.0,
		"Hat inspection moved its authored character pivot off center")
	overlay.call("_show_store_hat_preview", "hat_yellow_point")
	await process_frame
	await process_frame
	var replacement_hat := hat_socket.find_child(
		"HatVisual", false, false) as Node3D
	var replacement_pivot_screen := hat_camera.unproject_position(
		hat_pivot.global_position)
	_check(replacement_hat != null and str(replacement_hat.get_meta(
		"supabase_hat_id", "")) == "hat_yellow_point"
		and hat_pivot.rotation.is_zero_approx()
		and absf(replacement_pivot_screen.x
			- float(hat_viewport.size.x) * 0.5) < 1.0,
		"Selecting another Hat after rotation did not reset attached/centered framing")
	var stick_rotation: float = hat_pivot.rotation.y
	Input.action_press("p1_look_right", 1.0)
	overlay.call("_process", 0.25)
	Input.action_release("p1_look_right")
	_check(not is_equal_approx(hat_pivot.rotation.y, stick_rotation),
		"Hat inspection did not rotate from the controller right stick")
	var hat_ids: Array = HatRegistry.HATS.keys()
	hat_ids.sort()
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

	# Run the exhaustive 3D geometry matrix after the catalog/auth assertions.
	# It intentionally advances many preview frames and must not race unrelated
	# asynchronous catalog refresh work that those earlier assertions exercise.
	overlay.call("_show_page", 1)
	for model_id in ["male", "female"]:
		prefs.settings["character_model_id"] = model_id
		for item_id in hat_ids:
			overlay.call("_show_store_hat_preview", str(item_id))
			await process_frame
			await process_frame
			var active_camera = overlay.get(
				"_store_move_preview_camera") as Camera3D
			var active_viewport = overlay.get(
				"_store_move_preview_viewport") as SubViewport
			var active_visual = overlay.get(
				"_store_move_preview_visual") as Node3D
			var active_pivot = overlay.get(
				"_store_move_preview_pivot") as Node3D
			var active_socket = active_visual.call("get_headwear_socket") as Marker3D \
				if active_visual != null else null
			for yaw_degrees in [0.0, 90.0, 180.0, 270.0]:
				if active_pivot != null:
					active_pivot.rotation.y = deg_to_rad(yaw_degrees)
				if active_visual != null and active_visual.has_method("_process"):
					active_visual.call("_process", 0.0)
				var screen_bounds := _hat_screen_bounds(active_camera, active_socket) \
					if active_camera != null and active_socket != null else Rect2()
				_check(active_camera != null and active_viewport != null \
						and active_socket != null and screen_bounds.position.y >= 12.0,
					"%s Prize Counter %s at %d degrees lost its top margin: %s" % [
						model_id, item_id, int(yaw_degrees), screen_bounds])
				_check(active_viewport != null and screen_bounds.position.x >= 8.0 \
						and screen_bounds.end.x <= float(active_viewport.size.x) - 8.0,
					"%s Prize Counter %s at %d degrees exceeded horizontal framing: %s" % [
						model_id, item_id, int(yaw_degrees), screen_bounds])
	prefs.settings["character_model_id"] = original_model_id

	overlay.queue_free()
	prefs.settings["player_name"] = original_display_name
	prefs.settings["character_model_id"] = original_model_id
	if _failed:
		quit(1)
		return
	print("SUPABASE UI VALIDATION OK: Profile identity, auth onboarding, categories, signed-out browsing, and 96 Hat preview frames")
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
		"id": "hat_cowboy_classic", "display_name": "Cowboy Hat",
		"item_type": "hat", "description": "Test hat", "price": 100,
		"rarity": "common", "purchasable": true,
		"shop_visible": true, "active": true, "rotation_scope": "daily",
		"rotation_starts_at": null, "rotation_ends_at": null,
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
	for item_id in GIFT_CHARACTER_ITEM_IDS:
		supabase.shop_items.append(
			SupabaseCosmeticRegistry.local_catalog_item(item_id))
	supabase.inventory.clear()
	supabase.inventory.append({"item_id": "hat_cowboy_classic", "source": "purchase"})
	supabase.inventory.append({"item_id": "founder_crown", "source": "founder_grant"})
	supabase.inventory.append({"item_id": "wc_theme_deep_orbit", "source": "purchase"})
	supabase.set("_owned_item_ids", {
		"hat_cowboy_classic": true, "founder_crown": true,
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


func _hat_screen_bounds(camera: Camera3D, socket: Marker3D) -> Rect2:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var hat := socket.find_child("HatVisual", false, false) as Node3D
	if hat == null:
		return Rect2(Vector2(-INF, -INF), Vector2.ZERO)
	for node in hat.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null \
				or not mesh_instance.is_visible_in_tree():
			continue
		var bounds := mesh_instance.mesh.get_aabb()
		for corner_index in 8:
			var corner := bounds.position + Vector3(
				bounds.size.x if (corner_index & 1) != 0 else 0.0,
				bounds.size.y if (corner_index & 2) != 0 else 0.0,
				bounds.size.z if (corner_index & 4) != 0 else 0.0)
			var screen := camera.unproject_position(mesh_instance.to_global(corner))
			minimum.x = minf(minimum.x, screen.x)
			minimum.y = minf(minimum.y, screen.y)
			maximum.x = maxf(maximum.x, screen.x)
			maximum.y = maxf(maximum.y, screen.y)
	return Rect2(minimum, maximum - minimum)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("SUPABASE UI VALIDATION FAILED: %s" % message)
