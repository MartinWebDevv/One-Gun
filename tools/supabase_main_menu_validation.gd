extends SceneTree

# Loads the real main-menu scene and exercises the approved top-level routes.
# Backend network calls stay disabled; this is a deterministic UI/callback test.

var _failed := false

const GOLDFISH_MODEL := "goldfish_bag_man"
const GOLDFISH_ITEM := "character_goldfish_bag_man"
const NEW_CHARACTER_GIFTS := {
	"eye_wizard": "character_eye_wizard",
	"mr_mushroom": "character_mr_mushroom",
	"mr_poop": "character_mr_poop",
	"mr_salt": "character_mr_salt",
	"spooky_witch": "character_spooky_witch",
}


func _initialize() -> void:
	var supabase = root.get_node_or_null("SupabaseManager")
	if supabase != null:
		supabase.project_url = ""
		supabase.publishable_key = ""
	var social = root.get_node_or_null("SocialManager")
	if social != null:
		# Autoload ready order can queue an authenticated refresh before this
		# offline harness clears Supabase. Detach that test-only backend reference
		# so a saved local session never leaks a real HTTP request into UI QA.
		social.set_process(false)
		social.set("_backend", null)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var scene_resource = load("res://main_menu.tscn")
	_check(scene_resource is PackedScene, "main menu scene did not load")
	if not scene_resource is PackedScene:
		quit(1)
		return
	var config = root.get_node("GameConfig")
	var backend = root.get_node("SupabaseManager")
	var prefs = root.get_node("PlayerPrefs")
	var saved_loadout: Dictionary = backend.loadout.duplicate(true)
	var saved_model_id := str(prefs.settings.get("character_model_id", "male"))
	var saved_base_model_id := str(prefs.settings.get("character_base_model_id", "male"))
	var saved_skin_id := str(prefs.settings.get("character_skin_id", "blue"))
	prefs.settings["character_base_model_id"] = "female"
	prefs.settings["character_model_id"] = GOLDFISH_MODEL
	prefs.settings["character_skin_id"] = "blue"
	backend.loadout = SupabaseCosmeticRegistry.sanitize_loadout({
		"character_model": GOLDFISH_ITEM,
		"hat": "hat_cowboy_classic",
		"character_skin": "purple",
	})
	var menu = scene_resource.instantiate()
	root.add_child(menu)
	var map_cycler = menu.get("_map_cycler") as Node
	if map_cycler != null:
		map_cycler.set_process(false)
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	var showcase_actor = menu.get("_showcase_actor") as Node3D
	var showcase_visual = showcase_actor.get_node_or_null("CharacterModel") as Node3D \
		if showcase_actor != null else null
	var showcase_socket = showcase_visual.call("get_headwear_socket") as Marker3D \
		if showcase_visual != null else null
	var showcase_hat = showcase_socket.find_child("HatVisual", false, false) as Node3D \
		if showcase_socket != null else null
	_check(showcase_visual != null and str(showcase_visual.get("model_id")) == GOLDFISH_MODEL
		and str(showcase_visual.get("skin_id")) == "purple"
		and showcase_hat != null and str(showcase_hat.get_meta(
			"supabase_hat_id", "")) == "hat_cowboy_classic",
		"home showcase did not display the equipped gifted model and Hat")
	var showcase_camera = menu.get("_showcase_camera") as Camera3D
	var showcase_viewport = menu.get("_showcase_viewport") as SubViewport
	var showcase_bounds := _screen_bounds(showcase_camera, showcase_visual)
	_check(showcase_viewport != null and showcase_bounds.position.y \
			>= float(showcase_viewport.size.y) * 0.035,
		"home showcase framing clipped the equipped Hat")
	backend.loadout = SupabaseCosmeticRegistry.sanitize_loadout({
		"character_model": GOLDFISH_ITEM,
		"hat": "hat_top",
		"character_skin": "purple",
	})
	backend.loadout_updated.emit(backend.loadout.duplicate(true))
	await process_frame
	await process_frame
	showcase_hat = showcase_socket.find_child("HatVisual", false, false) as Node3D \
		if showcase_socket != null else null
	_check(showcase_hat != null and str(showcase_hat.get_meta(
		"supabase_hat_id", "")) == "hat_top",
		"home showcase did not refresh after the equipped loadout changed")
	backend.loadout = SupabaseCosmeticRegistry.empty_loadout()
	backend.call("_apply_local_character_appearance")
	backend.loadout_updated.emit(backend.loadout.duplicate(true))
	await process_frame
	await process_frame
	showcase_visual = showcase_actor.get_node_or_null("CharacterModel") as Node3D \
		if showcase_actor != null else null
	_check(showcase_visual != null and str(showcase_visual.get("model_id")) == "female",
		"removing account entitlement did not restore the last public model")

	# Cycle the real home-podium actor through every new developer gift via the
	# owned character-model loadout seam. Keep a Hat equipped so replacement,
	# animated socket binding, and camera reframing are all exercised together.
	for model_id in NEW_CHARACTER_GIFTS:
		backend.loadout = SupabaseCosmeticRegistry.sanitize_loadout({
			"character_model": str(NEW_CHARACTER_GIFTS[model_id]),
			"hat": "hat_top",
		})
		backend.call("_apply_local_character_appearance")
		backend.loadout_updated.emit(backend.loadout.duplicate(true))
		for _frame in 4:
			await process_frame
		showcase_visual = showcase_actor.get_node_or_null(
			"CharacterModel") as Node3D if showcase_actor != null else null
		showcase_socket = showcase_visual.call(
			"get_headwear_socket") as Marker3D if showcase_visual != null else null
		showcase_hat = showcase_socket.find_child(
			"HatVisual", false, false) as Node3D if showcase_socket != null else null
		var showcase_animation := showcase_visual.call(
			"get_animation_player") as AnimationPlayer \
			if showcase_visual != null else null
		_check(showcase_visual != null
				and str(showcase_visual.get("model_id")) == model_id
				and showcase_hat != null
				and str(showcase_hat.get_meta(
					"supabase_hat_id", "")) == "hat_top",
			"home podium displays new character and Hat: %s" % model_id)
		_check(showcase_animation != null
				and showcase_animation.current_animation == "idle",
			"home podium animates new character: %s" % model_id)
		showcase_bounds = _screen_bounds(showcase_camera, showcase_visual)
		_check(showcase_viewport != null
				and showcase_bounds.position.y
					>= float(showcase_viewport.size.y) * 0.035
				and showcase_bounds.end.y
					<= float(showcase_viewport.size.y) * 0.965,
			"home podium reframes new character and Hat: %s" % model_id)

	var home_labels: Array[String] = []
	for button in menu.get("_primary_buttons"):
		var title = (button as Node).find_child("ButtonTitle", true, false) as Label
		if title != null:
			home_labels.append(title.text)
		else:
			home_labels.append(str((button as Button).text))
	for expected in ["PLAY", "PLAYER HUB", "SETTINGS", "QUIT GAME"]:
		_check(expected in home_labels, "home navigation is missing %s" % expected)
	_check(not "ONLINE PLAY" in home_labels,
		"Online Play remained a duplicate top-level route")
	_check(menu.get("_friends_orb") != null,
		"home screen is missing the separate Friends mascot orb")

	menu.call("_on_player_hub_pressed")
	await process_frame
	var player_hub = menu.get("_main_player_hub_overlay")
	_check(player_hub != null and is_instance_valid(player_hub),
		"Player Hub callback did not create its overlay")
	for destination in ["OpenProfileButton", "OpenLockerButton",
			"OpenPrizeCounterButton", "OpenProgressionButton"]:
		_check(player_hub != null and player_hub.find_child(
			destination, true, false) != null,
			"Player Hub is missing %s" % destination)
	_check(player_hub != null and player_hub.find_child(
		"OpenFriendsButton", true, false) == null,
		"Player Hub duplicated the separate Friends mascot action")
	if player_hub != null:
		player_hub.call("_close")
	await process_frame

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
		var progression_manager = root.get_node("ProgressionManager")
		var saved_progression: Dictionary = progression_manager.progression.duplicate(true)
		progression_manager.progression = {
			"progress": {"season_level": 31.0, "trophies": 5.0},
			"career": {"career_level": 42.0},
			"mode_stats": [{
				"mode": GameConfig.MODE_ONE_GUN,
				"wins": 4.0,
				"matches": 8.0,
				"best_finish": 2.0,
				"kills": 17.0,
				"disarms": 9.0,
				"round_wins": 12.0,
			}],
		}
		profile_overlay.call("_refresh_profile_progression")
		var profile_values = profile_overlay.get("_profile_value_labels")
		for stat_name in ["SEASON LEVEL", "SEASON PRESTIGE", "CLASSIC TROPHIES",
				"CAREER LEVEL", "CAREER PRESTIGE", "CAREER WINS", "MATCHES",
				"KILLS", "DISARMS", "ROUND WINS"]:
			var stat_label := profile_values.get(stat_name) as Label
			_check(stat_label != null and not stat_label.text.contains("."),
				"Profile count %s still rendered a decimal" % stat_name)
		progression_manager.progression = saved_progression
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

	backend.loadout = saved_loadout
	prefs.settings["character_model_id"] = saved_model_id
	prefs.settings["character_base_model_id"] = saved_base_model_id
	prefs.settings["character_skin_id"] = saved_skin_id
	menu.queue_free()
	for _frame in 12:
		await process_frame
	if _failed:
		quit(1)
		return
	print("MAIN MENU VALIDATION OK: Play, Player Hub destinations, Friends orb, map sort, and empty online bots")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("SUPABASE MAIN MENU VALIDATION FAILED: %s" % message)


func _screen_bounds(camera: Camera3D, visual: Node3D) -> Rect2:
	if camera == null or visual == null:
		return Rect2(Vector2(-INF, -INF), Vector2.ZERO)
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var actor := visual.get_parent() as Node3D
	var model_id := PlayerSkinRegistry.sanitize_model_id(str(
		visual.get("model_id")))
	var body_bounds := PlayerSkinRegistry.idle_actor_bounds(model_id).grow(0.08)
	for corner_index in 8:
		var corner := body_bounds.position + Vector3(
			body_bounds.size.x if (corner_index & 1) != 0 else 0.0,
			body_bounds.size.y if (corner_index & 2) != 0 else 0.0,
			body_bounds.size.z if (corner_index & 4) != 0 else 0.0)
		var world_corner := actor.to_global(corner)
		if camera.is_position_behind(world_corner):
			continue
		var screen := camera.unproject_position(world_corner)
		minimum.x = minf(minimum.x, screen.x)
		minimum.y = minf(minimum.y, screen.y)
		maximum.x = maxf(maximum.x, screen.x)
		maximum.y = maxf(maximum.y, screen.y)
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null \
				or not mesh_instance.is_visible_in_tree() \
				or not _mesh_is_cosmetic(mesh_instance, visual):
			continue
		var bounds := mesh_instance.mesh.get_aabb()
		for corner_index in 8:
			var corner := bounds.position + Vector3(
				bounds.size.x if (corner_index & 1) != 0 else 0.0,
				bounds.size.y if (corner_index & 2) != 0 else 0.0,
				bounds.size.z if (corner_index & 4) != 0 else 0.0)
			var world_corner := mesh_instance.to_global(corner)
			if camera.is_position_behind(world_corner):
				continue
			var screen := camera.unproject_position(world_corner)
			minimum.x = minf(minimum.x, screen.x)
			minimum.y = minf(minimum.y, screen.y)
			maximum.x = maxf(maximum.x, screen.x)
			maximum.y = maxf(maximum.y, screen.y)
	return Rect2(minimum, maximum - minimum)


func _mesh_is_cosmetic(mesh_instance: MeshInstance3D,
		visual: Node3D) -> bool:
	var current: Node = mesh_instance
	while current != null and current != visual:
		if current.has_meta("one_gun_cosmetic_id") \
				or current.has_meta("supabase_hat_id"):
			return true
		current = current.get_parent()
	return false
