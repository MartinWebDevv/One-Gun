extends SceneTree

# Loads the real main-menu scene and exercises the approved top-level routes.
# Backend network calls stay disabled; this is a deterministic UI/callback test.

var _failed := false


func _initialize() -> void:
	var supabase = root.get_node_or_null("SupabaseManager")
	if supabase != null:
		supabase.project_url = ""
		supabase.publishable_key = ""
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var scene_resource = load("res://main_menu.tscn")
	_check(scene_resource is PackedScene, "main menu scene did not load")
	if not scene_resource is PackedScene:
		quit(1)
		return
	var config = root.get_node("GameConfig")
	var menu = scene_resource.instantiate()
	root.add_child(menu)
	var map_cycler = menu.get("_map_cycler") as Node
	if map_cycler != null:
		map_cycler.set_process(false)
	await process_frame
	await process_frame

	var home_labels: Array[String] = []
	for button in menu.get("_primary_buttons"):
		var title = (button as Node).find_child("ButtonTitle", true, false) as Label
		if title != null:
			home_labels.append(title.text)
		else:
			home_labels.append(str((button as Button).text))
	for expected in ["PLAY", "LOCKER", "PRIZE COUNTER", "PROGRESSION",
			"PROFILE", "SETTINGS", "QUIT GAME"]:
		_check(expected in home_labels, "home navigation is missing %s" % expected)
	_check(not "ONLINE PLAY" in home_labels,
		"Online Play remained a duplicate top-level route")

	menu.call("_on_local_menu_pressed")
	await process_frame
	_check(menu.get("_local_panel").visible,
		"Play callback did not open its route chooser")
	_check(menu.find_child("OnlinePlayChoice", true, false) != null,
		"Play chooser did not include Online Play")
	menu.call("_close_modal")
	await process_frame

	menu.call("_on_profile_pressed")
	await process_frame
	var profile_overlay = menu.get("_supabase_overlay")
	var modal_layer = menu.get("_modal_layer") as Control
	_check(profile_overlay != null and is_instance_valid(profile_overlay),
		"Profile callback did not create its overlay")
	_check(modal_layer != null and modal_layer.visible,
		"Profile did not activate the modal layer")
	if profile_overlay != null and is_instance_valid(profile_overlay):
		_check(profile_overlay.get("_account_page").visible,
			"Profile route opened on the wrong page")
		profile_overlay.call("_close")
	await process_frame
	_check(menu.get("_supabase_overlay") == null,
		"Profile close left a stale overlay reference")

	menu.call("_on_account_store_pressed")
	await process_frame
	var prize_overlay = menu.get("_supabase_overlay")
	_check(prize_overlay != null and is_instance_valid(prize_overlay),
		"Prize Counter callback did not create its overlay")
	if prize_overlay != null and is_instance_valid(prize_overlay):
		_check(prize_overlay.get("_store_page").visible,
			"Prize Counter route opened on the wrong page")
		prize_overlay.call("_close")
	await process_frame

	menu.call("_on_progression_pressed")
	await process_frame
	var progression = menu.get("_progression_overlay")
	_check(progression != null and is_instance_valid(progression),
		"Progression callback did not create its dedicated screen")
	if progression != null and is_instance_valid(progression):
		_check(progression.find_child("ProgressionCabinet", true, false) != null,
			"Progression screen did not build its cabinet")
		progression.call("_close")
	await process_frame
	_check(menu.get("_progression_overlay") == null,
		"Progression close left a stale overlay reference")

	menu.call("_on_character_customization_pressed")
	await process_frame
	var locker = menu.get("_character_customization_overlay")
	_check(locker != null and is_instance_valid(locker),
		"Locker callback did not create its overlay")
	if locker != null and is_instance_valid(locker):
		_check(locker.find_child("LockerCabinet", true, false) != null,
			"Locker route built the old customization cabinet")
		menu.call("_close_character_customization")
	await process_frame

	var original_bot_count := int(config.bot_count)
	menu.call("_prepare_online_lobby_defaults")
	_check(int(config.bot_count) == 0,
		"new online lobby did not start with an empty bot roster")
	config.set_bot_count(original_bot_count)

	var alphabetical := MapRegistry.sorted_indices("alphabetical")
	var alphabetical_names: Array[String] = []
	for map_index in alphabetical:
		alphabetical_names.append(str(MapRegistry.MAPS[map_index].get("name", "")))
	var expected_names := alphabetical_names.duplicate()
	expected_names.sort_custom(func(a: String, b: String) -> bool:
		return a.nocasecmp_to(b) < 0)
	_check(alphabetical_names == expected_names,
		"default map order was not alphabetical")
	var newest := MapRegistry.sorted_indices("newest")
	_check(not newest.is_empty() 			and str(MapRegistry.MAPS[newest[0]].get("name", "")) == "Neon Circuit",
		"Newest map order did not place Neon Circuit first")

	menu.queue_free()
	for _frame in 12:
		await process_frame
	if _failed:
		quit(1)
		return
	print("MAIN MENU VALIDATION OK: Play, Locker, Prize Counter, Progression, Profile, map sort, and empty online bots")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("SUPABASE MAIN MENU VALIDATION FAILED: %s" % message)
