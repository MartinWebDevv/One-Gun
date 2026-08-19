extends Node

const MAP_PATH := "res://maps/test/SpaceStationPrototype.tscn"
const OUTPUT_PATH := "res://.godot/neon_circuit_polished_overview.png"
const GAMEPLAY_OUTPUT_PATH := "res://.godot/neon_circuit_polished_gameplay.png"
const COMPACT_MAP_PATH := "res://maps/test/SpaceStationPrototypeCompactSnapshot.tscn"
const PRE_ASSET_MAP_PATH := "res://maps/test/NeonCircuitPreAssetSnapshot.tscn"

var _failures := 0


func _ready() -> void:
	var packed := load(MAP_PATH) as PackedScene
	_check(packed != null, "prototype scene loads")
	if packed == null:
		get_tree().quit(1)
		return
	var compact_packed := load(COMPACT_MAP_PATH) as PackedScene
	_check(compact_packed != null, "preserved compact snapshot remains F6-playable")
	var pre_asset_packed := load(PRE_ASSET_MAP_PATH) as PackedScene
	_check(pre_asset_packed != null,
			"preserved pre-asset Neon Circuit snapshot remains F6-playable")

	var arena := packed.instantiate() as Node3D
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	for node_name in ["RoundManager", "CanvasLayer", "SplitScreenLayer"]:
		var scripted := arena.get_node_or_null(node_name)
		if scripted != null:
			scripted.set_script(null)
	add_child(arena)

	_check(get_tree().get_nodes_in_group("spawn_point").size() == 10,
			"Neon Circuit carries ten player spawns")
	_check(get_tree().get_nodes_in_group("gun_spawn_point").size() == 4,
			"prototype carries four random-gun candidates")
	_check(get_tree().get_nodes_in_group("melee_spawn_point").size() == 6,
			"prototype carries six melee supplies")
	_check(get_tree().get_nodes_in_group("item_spawn_point").size() == 4,
			"prototype carries four item supplies")
	_check(get_tree().get_nodes_in_group("powerup_spawn_point").size() == 3,
			"prototype carries three powerup supplies")
	_check(get_tree().get_nodes_in_group("capacity_cover").size() == 4,
			"expanded arena carries four additional lane-cover props")
	var arena_identity := arena.get_node_or_null("ArenaIdentity")
	_check(arena_identity != null, "Neon Circuit arena identity layer is present")
	var entry_pad_count := 0
	var identity_collision_free := arena_identity != null
	if arena_identity != null:
		entry_pad_count = arena_identity.find_children(
				"EntryPad*", "CSGCylinder3D", false, false).size()
		for visual in arena_identity.find_children("*", "CSGShape3D", true, false):
			identity_collision_free = identity_collision_free and not (visual as CSGShape3D).use_collision
	var asset_art_pass := arena.get_node_or_null("AssetArtPass")
	_check(asset_art_pass != null,
			"curated external-asset art layer is present")
	var art_collision_free := asset_art_pass != null
	var art_mesh_count := 0
	if asset_art_pass != null:
		art_collision_free = asset_art_pass.find_children(
				"*", "CollisionObject3D", true, false).is_empty()
		art_mesh_count = asset_art_pass.find_children(
				"*", "MeshInstance3D", true, false).size()
	_check(art_collision_free,
			"external model dressing remains visual-only and collision-free")
	_check(art_mesh_count >= 100,
			"external art layer contains the curated station shell and props")
	_check(entry_pad_count == 10, "all ten spawns have visible arena entry pads")
	_check(identity_collision_free,
			"Neon Circuit primitive dressing remains visual-only and collision-free")
	var expected_zone_labels := {
		"ObservationLabel": "BLUE CIRCUIT",
		"ResearchLabel": "GREEN CIRCUIT",
		"ZeroGLabel": "VIOLET CIRCUIT",
		"EngineLabel": "RED CIRCUIT",
		"CoreStatusLabel": "ONE GUN // LIVE VAULT",
		"DeckHeaderLabel": "NEON CIRCUIT // ORBITAL TAG ARENA",
		"ArenaCapacityLabel": "NEON CIRCUIT // 10 PLAYERS // SYSTEM LIVE",
	}
	var zone_identity_matches := true
	for label_name in expected_zone_labels:
		var label := arena.get_node_or_null(
				"ZoneLabels/" + str(label_name)) as Label3D
		zone_identity_matches = zone_identity_matches \
			and label != null and label.text == expected_zone_labels[label_name]
	_check(zone_identity_matches,
			"color circuits and one-gun vault retain their arena identities")
	var main_deck := arena.get_node_or_null("Graybox/MainDeck") as CSGBox3D
	_check(main_deck != null and main_deck.size.x >= 38.0
			and main_deck.size.z >= 34.0,
			"single-room footprint supports up to ten players")
	var nav := arena.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	_check(nav != null and nav.navigation_mesh != null
			and nav.navigation_mesh.get_polygon_count() > 0,
			"prototype navigation bake is non-empty")

	var spawn_markers := get_tree().get_nodes_in_group("spawn_point")
	var navigation_map := nav.get_navigation_map() if nav != null else RID()
	for frame in 10:
		await get_tree().physics_frame
	var navigation_deadline := Time.get_ticks_msec() + 5000
	while navigation_map.is_valid() \
			and NavigationServer3D.map_get_iteration_id(navigation_map) == 0 \
			and Time.get_ticks_msec() < navigation_deadline:
		await get_tree().physics_frame
	var navigation_ready := navigation_map.is_valid() \
		and NavigationServer3D.map_get_iteration_id(navigation_map) > 0
	_check(navigation_ready, "Neon Circuit navigation map synchronizes")
	if navigation_ready and not spawn_markers.is_empty():
		var start_nav := NavigationServer3D.map_get_closest_point(
				navigation_map, spawn_markers[0].global_position)
		var every_spawn_on_nav := true
		var every_spawn_connected := true
		for marker in spawn_markers:
			var nearest := NavigationServer3D.map_get_closest_point(
					navigation_map, marker.global_position)
			var horizontal_gap := Vector2(nearest.x - marker.global_position.x,
					nearest.z - marker.global_position.z).length()
			every_spawn_on_nav = every_spawn_on_nav and horizontal_gap < 1.5
			if marker != spawn_markers[0]:
				var path := NavigationServer3D.map_get_path(
						navigation_map, start_nav, nearest, true)
				every_spawn_connected = every_spawn_connected and path.size() >= 2
		_check(every_spawn_on_nav, "all ten player spawns sit over baked navigation")
		_check(every_spawn_connected, "bots can path between all ten player spawns")

	var player := arena.get_node_or_null("player1") as CharacterBody3D
	var movement_manager: Variant = load("res://round_manager.gd").new()
	var movement_axes_aligned := player != null
	if player != null:
		for marker in get_tree().get_nodes_in_group("spawn_point"):
			var spawn_transform := Transform3D(
				Basis(Vector3.UP, marker.global_rotation.y), marker.global_position)
			movement_manager._apply_local_human_spawn_transform(player, spawn_transform)
			var aim_pivot := player.get_node("AimPivot") as Node3D
			var camera_node := player.get_node("AimPivot/SpringArm3D/Camera3D") as Camera3D
			var input_forward := (aim_pivot.transform.basis * Vector3.FORWARD).normalized()
			var camera_forward := -camera_node.global_transform.basis.z
			camera_forward.y = 0.0
			camera_forward = camera_forward.normalized()
			var input_right := (aim_pivot.transform.basis * Vector3.RIGHT).normalized()
			var camera_right := camera_node.global_transform.basis.x
			camera_right.y = 0.0
			camera_right = camera_right.normalized()
			movement_axes_aligned = movement_axes_aligned \
				and absf(player.global_rotation.y) < 0.001 \
				and input_forward.dot(camera_forward) > 0.999 \
				and input_right.dot(camera_right) > 0.999
	_check(movement_axes_aligned, "all rotated spawns keep movement camera-relative")
	movement_manager.free()

	for canvas_name in ["CanvasLayer", "SplitScreenLayer"]:
		var canvas := arena.get_node_or_null(canvas_name) as CanvasLayer
		if canvas != null:
			canvas.visible = false
	var camera := Camera3D.new()
	camera.fov = 56.0
	camera.position = Vector3(62, 54, 60)
	add_child(camera)
	camera.look_at(Vector3(0, 0, 0))
	camera.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var absolute_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var save_error := get_viewport().get_texture().get_image().save_png(absolute_path)
	_check(save_error == OK, "prototype overview capture saves")

	camera.fov = 68.0
	camera.position = Vector3(0, 8.5, 29)
	camera.look_at(Vector3(0, 3.2, 0))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var gameplay_absolute_path := ProjectSettings.globalize_path(GAMEPLAY_OUTPUT_PATH)
	var gameplay_save_error := get_viewport().get_texture().get_image().save_png(
			gameplay_absolute_path)
	_check(gameplay_save_error == OK, "prototype gameplay-view capture saves")
	print("NEON_CIRCUIT_PROTOTYPE_VALIDATION failures=%d capture=%s" % [
		_failures, OUTPUT_PATH])
	get_tree().quit(_failures)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
		return
	_failures += 1
	push_error("FAIL: " + description)
