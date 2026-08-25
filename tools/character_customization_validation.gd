extends Node

const CUSTOMIZATION_SCRIPT = preload("res://UI/themed_locker_overlay.gd")
const Catalog = preload("res://supabase/one_gun_catalog.gd")

var _failed := false
var _overlay = null
var _output_dir := ""
var _prefix := "customization"


func _ready() -> void:
	_output_dir = OS.get_environment("ONEGUN_CUSTOMIZATION_CAPTURE_DIR")
	_prefix = OS.get_environment("ONEGUN_CUSTOMIZATION_CAPTURE_PREFIX")
	if _prefix.is_empty():
		_prefix = "customization"
	_run.call_deferred()


func _run() -> void:
	var requested_window := OS.get_environment("ONEGUN_CUSTOMIZATION_WINDOW")
	if requested_window.contains("x"):
		var parts := requested_window.split("x")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(parts[0].to_int(), parts[1].to_int()))
			await _wait_frames(3)
	var original_p1 := str(PlayerPrefs.get_setting("character_skin_id"))
	var original_p2 := str(GameConfig.player2_skin_id)
	var original_p1_model := str(PlayerPrefs.get_setting("character_model_id"))
	var original_p2_model := str(GameConfig.player2_model_id)
	_seed_locker_data()
	_overlay = CUSTOMIZATION_SCRIPT.new()
	_overlay.configure(false, 2)
	add_child(_overlay)
	await _wait_frames(18)

	_check(_overlay.find_children("*", "SubViewport", true, false).size() == 1,
		"customization should use one shared preview viewport")
	_check(_overlay.find_children("ColorCard_*", "", true, false).size() == 13,
		"customization should show all 13 color cards")
	for row_index in 3:
		var row = _overlay.find_child("ColorRow%d" % (row_index + 1), true, false)
		var expected := 5 if row_index < 2 else 3
		_check(row != null and row.get_child_count() == expected,
			"color row %d should contain %d cards" % [row_index + 1, expected])
	_check(_overlay.find_child("LockedSkins", true, false) == null,
		"Locker should not show unowned locked-item placeholders")
	_check(_overlay.find_child("LockerCategoryTabs", true, false) != null,
		"Locker should expose Character, Weapons, Victory, and Audio")
	_check(_overlay.find_child("CharacterLockerTabs", true, false) != null,
		"Character Locker should expose Skins, Colors, and Cosmetics")
	var title := _overlay.find_child("CustomizationTitle", true, false) as Label
	_check(title != null and title.text == "THE LOCKER",
		"customization screen did not build the themed Locker header")
	_check(_overlay.find_child("Player1Tab", true, false) != null
		and _overlay.find_child("Player2Tab", true, false) != null,
		"split-screen customization should show P1/P2 tabs")
	_check(_overlay.find_child("MaleModel", true, false) != null
		and _overlay.find_child("FemaleModel", true, false) != null,
		"customization should show M/F model buttons beneath the preview")
	_check(_overlay.find_child("Randomize", true, false) != null
		and _overlay.find_child("Default", true, false) != null
		and _overlay.find_child("ResetLoadout", true, false) != null
		and _overlay.find_child("Confirm", true, false) != null,
		"action bar should contain color tools, Reset Loadout, and Confirm")

	_overlay.call("_show_character_subcategory", 2)
	await _wait_frames(2)
	var owned_list = _overlay.get("_owned_list") as VBoxContainer
	var owned_text := _descendant_text(owned_list)
	_check(owned_text.contains("COWBOY HAT") and owned_text.contains("FOUNDER CROWN"),
		"Character Owned Gear did not include owned hidden/public cosmetics")
	_check(not owned_text.contains("GOLDEN GUN"),
		"Character Owned Gear included an item from another category")
	_overlay.call("_show_locker_category", 1)
	await _wait_frames(2)
	owned_text = _descendant_text(owned_list)
	_check(owned_text.contains("GOLDEN GUN") and not owned_text.contains("COWBOY HAT"),
		"Weapons Locker did not isolate owned weapon cosmetics")
	_overlay.call("_show_locker_category", 2)
	await _wait_frames(2)
	owned_text = _descendant_text(owned_list)
	var reset_loadout = _overlay.find_child("ResetLoadout", true, false) as Button
	_check(reset_loadout != null and reset_loadout.visible,
		"Reset Loadout should replace color tools outside the Colors screen")
	_check(owned_text.contains("FRESH FOOTWORK")
		and owned_text.contains("BIRDIE BOOGIE")
		and owned_text.contains("PREVIEW")
		and owned_text.contains("EQUIP PODIUM")
		and owned_text.contains("EQUIP ROUND")
		and owned_text.contains("UNEQUIP"),
		"Victory Locker did not expose dual-slot dance controls")
	_overlay.call("_on_locker_subcategory_selected", 1)
	await _wait_frames(2)
	owned_text = _descendant_text(owned_list)
	_check(not owned_text.contains("FRESH FOOTWORK")
		and not owned_text.contains("BIRDIE BOOGIE"),
		"Animated dances leaked into the Poses filter")
	_overlay.call("_on_locker_subcategory_selected", 2)
	await _wait_frames(2)
	owned_text = _descendant_text(owned_list)
	_check(owned_text.contains("FRESH FOOTWORK")
		and owned_text.contains("BIRDIE BOOGIE"),
		"Dances filter did not keep all animated victory moves together")
	_overlay.call("_show_locker_category", 3)
	await _wait_frames(2)
	owned_text = _descendant_text(owned_list)
	_check(owned_text.contains("DEEP ORBIT") and owned_text.contains("PREVIEW"),
		"Music Locker did not expose the owned Winners Circle theme")
	_overlay.call("_show_locker_category", 0)
	_overlay.call("_show_character_subcategory", 0)

	for skin in PlayerSkinRegistry.SKINS:
		var skin_id := str(skin["id"])
		_check(PlayerSkinRegistry.load_portrait(skin_id) != null,
			"portrait missing for %s" % skin_id)
		_check(PlayerSkinRegistry.load_portrait(skin_id, "female") != null,
			"female portrait missing for %s" % skin_id)

	var preview = _overlay.find_child("PreviewCharacter", true, false)
	var animation_player := preview.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer if preview != null else null
	_check(preview != null and animation_player != null
		and animation_player.current_animation == "idle",
		"shared preview should show an evaluated Idle pose")
	var preview_pivot = _overlay.get("_preview_pivot") as Node3D
	var still_rotation := preview_pivot.rotation.y
	await _wait_frames(8)
	_check(is_equal_approx(preview_pivot.rotation.y, still_rotation),
		"Locker preview rotated without a click-drag")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	_overlay.call("_on_preview_gui_input", press)
	var drag_right := InputEventMouseMotion.new()
	drag_right.relative = Vector2(32.0, 0.0)
	_overlay.call("_on_preview_gui_input", drag_right)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	_overlay.call("_on_preview_gui_input", release)
	_check(preview_pivot.rotation.y > still_rotation,
		"dragging right did not rotate the model to the right")
	var released_rotation := preview_pivot.rotation.y
	await _wait_frames(8)
	_check(is_equal_approx(preview_pivot.rotation.y, released_rotation),
		"Locker preview kept rotating after the mouse was released")

	_overlay.call("_select_skin", "salmon")
	_overlay.call("_select_model", "female")
	_check(str(PlayerPrefs.get_setting("character_skin_id")) == original_p1,
		"P1 preview selection leaked before Confirm")
	_check(str(PlayerPrefs.get_setting("character_model_id")) == original_p1_model,
		"P1 model preview selection leaked before Confirm")
	_overlay.call("_default_active_skin")
	_check(str(_overlay._pending_skin_ids.get(0, "")) == "blue",
		"Default should set the pending P1 color to Blue")
	_check(str(PlayerPrefs.get_setting("character_skin_id")) == original_p1,
		"Default changed the stored P1 color before Confirm")

	await _capture("%s_p1.png" % _prefix)
	_overlay.call("_set_active_slot", 1)
	_overlay.call("_select_skin", "salmon")
	_overlay.call("_select_model", "female")
	await _wait_frames(4)
	_check(str(GameConfig.player2_skin_id) == original_p2,
		"P2 preview selection leaked before Confirm")
	_check(str(GameConfig.player2_model_id) == original_p2_model,
		"P2 model preview selection leaked before Confirm")
	await _capture("%s_p2.png" % _prefix)

	var canvas := _overlay.find_child("CustomizationCanvas", true, false) as Control
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	_check(canvas != null and _rect_fits(canvas.get_global_rect(), viewport_rect),
		"responsive customization canvas extends out of frame")
	for control_name in ["CharacterPreviewPanel", "LockerCabinet",
			"Back", "Randomize", "Default", "ResetLoadout", "Confirm"]:
		var control := _overlay.find_child(control_name, true, false) as Control
		_check(control != null and _rect_fits(control.get_global_rect(), viewport_rect),
			"%s extends out of frame" % control_name)

	var roster_row := OneGunRosterRow.new()
	add_child(roster_row)
	roster_row.visible = false
	roster_row.set_human("Remote Player", false, false,
		OneGunRosterRow.ReadyState.READY, "purple", "female")
	await get_tree().process_frame
	var roster_portraits := roster_row.find_children(
		"PlayerPortrait", "", true, false)
	var roster_portrait = roster_portraits[0] \
		if not roster_portraits.is_empty() else null
	_check(roster_portrait != null and roster_portrait.visible
		and roster_portrait.skin_id == "purple"
		and roster_portrait.model_id == "female"
		and roster_portrait.texture != null,
		"human lobby row did not resolve the synchronized skin portrait")
	roster_row.queue_free()

	_overlay.call("_cancel")
	await get_tree().process_frame
	_check(str(PlayerPrefs.get_setting("character_skin_id")) == original_p1
		and str(GameConfig.player2_skin_id) == original_p2
		and str(PlayerPrefs.get_setting("character_model_id")) == original_p1_model
		and str(GameConfig.player2_model_id) == original_p2_model,
		"Cancel failed to preserve both confirmed appearances")

	var confirm_overlay = CUSTOMIZATION_SCRIPT.new()
	confirm_overlay.configure(false, 2)
	add_child(confirm_overlay)
	await _wait_frames(3)
	confirm_overlay.call("_set_active_slot", 1)
	confirm_overlay.call("_select_skin", "cyan")
	confirm_overlay.call("_select_model", "female")
	confirm_overlay.call("_confirm")
	await get_tree().process_frame
	_check(str(GameConfig.player2_skin_id) == "cyan"
		and str(GameConfig.player2_model_id) == "female",
		"Confirm did not commit the pending P2 appearance")
	GameConfig.player2_skin_id = original_p2
	GameConfig.player2_model_id = original_p2_model
	if _failed:
		get_tree().quit(1)
	else:
		print("LOCKER_VALIDATION_OK colors=13 owned-only categories=4 models=2 portraits=online-ready")
		get_tree().quit(0)


func _seed_locker_data() -> void:
	var supabase = get_node("/root/SupabaseManager")
	supabase.project_url = ""
	supabase.publishable_key = ""
	supabase.access_token = "validation-access-token"
	supabase.refresh_token = "validation-refresh-token"
	supabase.authenticated_user_id = "00000000-0000-0000-0000-000000000003"
	supabase.access_token_expires_at = int(Time.get_unix_time_from_system()) + 3600
	supabase.login_state = "authenticated"
	supabase.shop_items.clear()
	supabase.shop_items.append({"id": "cowboy_hat", "display_name": "Cowboy Hat", "item_type": "hat"})
	supabase.shop_items.append({"id": "golden_gun_skin", "display_name": "Golden Gun Skin", "item_type": "gun_skin"})
	supabase.shop_items.append({"id": "base_one_gun", "display_name": "Original One Gun", "item_type": "gun_skin", "category": "weapons", "subcategory": "gun_skins"})
	supabase.shop_items.append({"id": "base_arena_melee", "display_name": "Original Melee Finish", "item_type": "melee_skin", "category": "weapons", "subcategory": "melee_skins"})
	supabase.shop_items.append({"id": "hip_hop_dance", "display_name": "Hip Hop Dance", "item_type": "victory_dance", "category": "victory", "subcategory": "dances"})
	supabase.shop_items.append({
		"id": "podium_fresh_footwork", "display_name": "Fresh Footwork",
		"item_type": "victory_dance", "category": "victory", "subcategory": "dances",
	})
	supabase.shop_items.append({
		"id": "round_birdie_boogie", "display_name": "Birdie Boogie",
		"item_type": "victory_dance", "category": "victory", "subcategory": "dances",
	})
	supabase.shop_items.append({"id": "wc_theme_deep_orbit", "display_name": "Deep Orbit", "item_type": "ceremony_theme"})
	var progression = get_node("/root/ProgressionManager")
	progression.catalog_items.clear()
	for shop_item in supabase.shop_items:
		progression.catalog_items.append(Catalog.normalize_item(shop_item))
	progression.catalog_items.append(Catalog.normalize_item({
		"id": "founder_crown", "display_name": "Founder Crown",
		"item_type": "hat", "shop_visible": false, "active": true,
	}))
	supabase.inventory.clear()
	supabase.inventory.append({"item_id": "cowboy_hat", "source": "purchase"})
	supabase.inventory.append({"item_id": "founder_crown", "source": "founder_grant"})
	supabase.inventory.append({"item_id": "golden_gun_skin", "source": "purchase"})
	supabase.inventory.append({"item_id": "base_one_gun", "source": "base_game"})
	supabase.inventory.append({"item_id": "base_arena_melee", "source": "base_game"})
	supabase.inventory.append({"item_id": "hip_hop_dance", "source": "purchase"})
	supabase.inventory.append({"item_id": "wc_theme_deep_orbit", "source": "purchase"})
	supabase.inventory.append({"item_id": "podium_fresh_footwork", "source": "purchase"})
	supabase.inventory.append({"item_id": "round_birdie_boogie", "source": "purchase"})
	supabase.set("_owned_item_ids", {
		"cowboy_hat": true,
		"founder_crown": true,
		"golden_gun_skin": true,
		"base_one_gun": true,
		"base_arena_melee": true,
		"hip_hop_dance": true,
		"wc_theme_deep_orbit": true,
		"podium_fresh_footwork": true,
		"round_birdie_boogie": true,
	})
	supabase.loadout = SupabaseCosmeticRegistry.sanitize_loadout({
		"hat": "founder_crown",
		"gun_skin": "base_one_gun",
		"melee_skin": "base_arena_melee",
		"emote": "podium_fresh_footwork",
		"round_victory_move": "round_birdie_boogie",
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


func _capture(file_name: String) -> void:
	if _output_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_output_dir)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _output_dir.path_join(file_name)
	var error := image.save_png(path)
	_check(error == OK, "could not save capture %s" % path)
	if error == OK:
		print("CHARACTER_CUSTOMIZATION_CAPTURE ", path)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("CharacterCustomizationValidation: %s" % message)


func _rect_fits(inner: Rect2, outer: Rect2) -> bool:
	const TOLERANCE := 1.0
	return inner.position.x >= outer.position.x - TOLERANCE \
		and inner.position.y >= outer.position.y - TOLERANCE \
		and inner.end.x <= outer.end.x + TOLERANCE \
		and inner.end.y <= outer.end.y + TOLERANCE


func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame
