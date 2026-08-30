extends SceneTree

## Builds the playable Trippy Mountains wrapper around the partner-authored
## environment scene. The environment remains independently editable; rerunning
## this tool refreshes only the gameplay wrapper and authored marker layout.

const OUTPUT_PATH := "res://maps/test/TrippyMountainsMap.tscn"
const ENVIRONMENT_PATH := \
	"res://maps/trippy_mountains/trippy_mountains_environment.tscn"
const SCAFFOLD_PATH := "res://node_3d.tscn"
const NAVIGATION_PATH := "res://navigation/TrippyMountainsNavigation.tres"

const ARENA_CENTER := Vector3(68.235, 0.0, -118.369)
const MAP_SCALE := 2.3
const PLAY_AREA_LOCAL_BOUNDS := Rect2(
	Vector2(47.7, -138.05), Vector2(41.05, 39.36))

var _collision_faces := PackedVector3Array()
var _collision_source_paths := PackedStringArray()

const PLAYER_SPAWNS: Array[Vector3] = [
	Vector3(52.698, 1.5, -123.269),
	Vector3(59.872, 1.5, -133.704),
	Vector3(69.655, 1.5, -133.704),
	Vector3(76.828, 1.5, -129.791),
	Vector3(83.350, 1.5, -123.269),
	Vector3(84.655, 1.5, -111.530),
	Vector3(77.481, 1.5, -105.661),
	Vector3(68.350, 1.5, -103.052),
	Vector3(58.568, 1.5, -105.661),
	Vector3(54.655, 1.5, -114.139),
]

const GUN_SPAWNS: Array[Vector3] = [
	Vector3(67.046, 0.45, -120.661),
	Vector3(63.785, 0.45, -108.269),
	Vector3(78.785, 0.45, -110.878),
	Vector3(76.828, 0.45, -119.356),
	Vector3(55.959, 0.45, -119.356),
]

const MELEE_SPAWNS: Array[Vector3] = [
	Vector3(66.394, 0.35, -127.835),
	Vector3(56.611, 0.35, -126.530),
	Vector3(80.089, 0.35, -126.530),
	Vector3(72.263, 0.35, -118.704),
	Vector3(71.611, 0.35, -108.922),
	Vector3(57.263, 0.35, -110.226),
]

const ITEM_SPAWNS: Array[Vector3] = [
	Vector3(72.915, 0.35, -131.096),
	Vector3(74.220, 0.35, -122.617),
	Vector3(60.524, 0.35, -124.574),
	Vector3(72.915, 0.35, -105.009),
	Vector3(64.437, 0.35, -131.748),
]

const POWERUP_SPAWNS: Array[Vector3] = [
	Vector3(71.611, 0.6, -127.182),
	Vector3(75.524, 0.6, -115.443),
]

func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	var environment_scene := load(ENVIRONMENT_PATH) as PackedScene
	var scaffold_scene := load(SCAFFOLD_PATH) as PackedScene
	if environment_scene == null or scaffold_scene == null:
		push_error("Trippy Mountains builder could not load its source scenes.")
		quit(1)
		return

	var map := Node3D.new()
	map.name = "TrippyMountainsMap"
	# Keep overtime flames readable without making this already-colorful map too
	# expensive on the Low quality target.
	map.set_meta("overtime_fire_intensity_scale", 0.8)
	map.set_meta("trippy_map_scale", MAP_SCALE)

	var environment := environment_scene.instantiate() as Node3D
	environment.name = "Environment"
	# Scale around PlayArea's authored center instead of the imported scene
	# origin, keeping the arena in the same world-space neighborhood while making
	# its art, walls, and traversal distances read correctly beside One Gun's
	# standard player body.
	environment.scale = Vector3.ONE * MAP_SCALE
	environment.position = Vector3(
		ARENA_CENTER.x * (1.0 - MAP_SCALE),
		0.0,
		ARENA_CENTER.z * (1.0 - MAP_SCALE))
	map.add_child(environment)
	environment.owner = map
	_add_play_area_asset_collisions(map, environment)

	_add_navigation_region(map)
	_add_marker_branch(map, "SpawnPoints", "SpawnPoint", "spawn_point", PLAYER_SPAWNS, true)
	_add_marker_branch(map, "GunSpawnPoints", "GunSpawn", "gun_spawn_point", GUN_SPAWNS)
	_add_marker_branch(map, "MeleeSpawnPoints", "MeleeSpawn", "melee_spawn_point", MELEE_SPAWNS)
	_add_marker_branch(map, "ItemSpawnPoints", "ItemSpawn", "item_spawn_point", ITEM_SPAWNS)
	_add_marker_branch(map, "PowerupSpawnPoints", "PowerupSpawn", "powerup_spawn_point", POWERUP_SPAWNS)
	_add_overtime_markers(map)
	_add_round_intro_marker(map)
	_copy_gameplay_scaffold(map, scaffold_scene)

	var packed := PackedScene.new()
	var pack_error := packed.pack(map)
	if pack_error != OK:
		push_error("Could not pack Trippy Mountains: %s" % error_string(pack_error))
		map.free()
		quit(1)
		return
	var save_error := ResourceSaver.save(packed, OUTPUT_PATH)
	print("TRIPPY_MAP_BUILD output=%s save_error=%d" % [OUTPUT_PATH, save_error])
	map.free()
	quit(0 if save_error == OK else 1)

func _add_play_area_asset_collisions(map: Node3D, environment: Node3D) -> void:
	_collision_faces = PackedVector3Array()
	_collision_source_paths = PackedStringArray()
	var flat_ground := environment.get_node_or_null("FlatGround")
	_collect_play_area_collision_faces(
		environment, environment, flat_ground)
	if _collision_faces.is_empty():
		push_error("Trippy Mountains collision build found no PlayArea asset faces.")
		return

	var body := StaticBody3D.new()
	body.name = "PlayAreaAssetCollisions"
	body.add_to_group("trippy_play_area_asset_collision", true)
	body.set_meta("source_mesh_count", _collision_source_paths.size())
	body.set_meta("triangle_count", _collision_faces.size() / 3)
	body.set_meta("source_mesh_paths", _collision_source_paths)
	environment.add_child(body)
	body.owner = map

	var collision := CollisionShape3D.new()
	collision.name = "AssetCollision"
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(_collision_faces)
	collision.shape = shape
	body.add_child(collision)
	collision.owner = map


func _collect_play_area_collision_faces(
		node: Node,
		environment: Node3D,
		flat_ground: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var belongs_to_ground := flat_ground != null \
			and (mesh_instance == flat_ground \
			or flat_ground.is_ancestor_of(mesh_instance))
		if not belongs_to_ground \
				and mesh_instance.mesh != null \
				and _is_effectively_visible(mesh_instance, environment):
			var to_environment := _transform_to_ancestor(mesh_instance, environment)
			var local_bounds := _transformed_aabb(
				mesh_instance.get_aabb(), to_environment)
			var footprint := Rect2(
				Vector2(local_bounds.position.x, local_bounds.position.z),
				Vector2(local_bounds.size.x, local_bounds.size.z))
			if local_bounds.end.y >= -0.05 \
					and PLAY_AREA_LOCAL_BOUNDS.intersects(footprint, true):
				var source_faces := mesh_instance.mesh.get_faces()
				if source_faces.size() >= 3:
					for point in source_faces:
						_collision_faces.append(to_environment * point)
					_collision_source_paths.append(str(
						environment.get_path_to(mesh_instance)))

	for child in node.get_children():
		_collect_play_area_collision_faces(child, environment, flat_ground)


func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _transformed_aabb(box: AABB, to_space: Transform3D) -> AABB:
	var transformed := AABB(to_space * box.position, Vector3.ZERO)
	var box_end := box.end
	for endpoint_index in 8:
		var point := Vector3(
			box_end.x if (endpoint_index & 1) != 0 else box.position.x,
			box_end.y if (endpoint_index & 2) != 0 else box.position.y,
			box_end.z if (endpoint_index & 4) != 0 else box.position.z)
		transformed = transformed.expand(to_space * point)
	return transformed


func _is_effectively_visible(node: Node3D, stop_at: Node3D) -> bool:
	var current: Node = node
	while current != null:
		if current is Node3D and not (current as Node3D).visible:
			return false
		if current == stop_at:
			return true
		current = current.get_parent()
	return false

func _add_navigation_region(map: Node3D) -> void:
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	var baked := load(NAVIGATION_PATH) as NavigationMesh \
		if ResourceLoader.exists(NAVIGATION_PATH) else null
	region.navigation_mesh = baked if baked != null else NavigationMesh.new()
	map.add_child(region)
	region.owner = map


func _copy_gameplay_scaffold(map: Node3D, scaffold_scene: PackedScene) -> void:
	var scaffold := scaffold_scene.instantiate()
	for node_name in ["Gun", "player1", "player2", "CanvasLayer", "RoundManager", "SplitScreenLayer"]:
		var source := scaffold.get_node_or_null(node_name)
		if source == null:
			push_error("Gameplay scaffold is missing %s." % node_name)
			continue
		var copy := source.duplicate()
		map.add_child(copy)
		_own_shallow(copy, map)

	var gun := map.get_node_or_null("Gun") as Node3D
	if gun != null:
		gun.position = _map_position(GUN_SPAWNS[0])
	var player1 := map.get_node_or_null("player1") as Node3D
	if player1 != null:
		player1.position = _map_position(PLAYER_SPAWNS[0])
	var player2 := map.get_node_or_null("player2") as Node3D
	if player2 != null:
		player2.position = _map_position(PLAYER_SPAWNS[5])
	scaffold.free()


func _add_marker_branch(
		map: Node3D,
		branch_name: String,
		marker_prefix: String,
		group_name: String,
		positions: Array[Vector3],
		face_center := false) -> void:
	var branch := Node3D.new()
	branch.name = branch_name
	map.add_child(branch)
	branch.owner = map
	for index in positions.size():
		var marker := Marker3D.new()
		marker.name = "%s%d" % [marker_prefix, index + 1]
		marker.position = _map_position(positions[index])
		if face_center:
			var target := Vector3(ARENA_CENTER.x, marker.position.y, ARENA_CENTER.z)
			marker.basis = Basis.looking_at((target - marker.position).normalized(), Vector3.UP)
		marker.add_to_group(group_name, true)
		branch.add_child(marker)
		marker.owner = map


func _add_overtime_markers(map: Node3D) -> void:
	var branch := Node3D.new()
	branch.name = "OvertimeMarkers"
	map.add_child(branch)
	branch.owner = map

	_add_marker(branch, map, "OvertimeCenter", ARENA_CENTER + Vector3.UP * 0.1,
		"overtime_center_point")
	var corners: Array[Vector3] = [
		Vector3(48.2, 0.1, -137.5),
		Vector3(88.2, 0.1, -137.5),
		Vector3(88.2, 0.1, -99.2),
		Vector3(48.2, 0.1, -99.2),
	]
	for index in corners.size():
		_add_marker(branch, map, "OvertimeBoundary%d" % (index + 1),
			_map_position(corners[index]), "overtime_boundary_point")


func _add_round_intro_marker(map: Node3D) -> void:
	var marker := Marker3D.new()
	marker.name = "RoundIntroCameraPoint"
	# Stay inside the mountain ring. The per-map sweep is deliberately narrow
	# so the first-round camera never exposes scenery behind the perimeter.
	marker.position = ARENA_CENTER + Vector3(0.0, 16.0, 22.0)
	marker.set_meta("intro_orbit_angle_radians", deg_to_rad(40.0))
	marker.add_to_group("round_intro_camera_point", true)
	map.add_child(marker)
	marker.owner = map


func _add_marker(
		parent: Node3D,
		owner: Node,
		marker_name: String,
		position: Vector3,
		group_name: String) -> void:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = position
	marker.add_to_group(group_name, true)
	parent.add_child(marker)
	marker.owner = owner


func _map_position(authored_position: Vector3) -> Vector3:
	return Vector3(
		ARENA_CENTER.x + (authored_position.x - ARENA_CENTER.x) * MAP_SCALE,
		authored_position.y,
		ARENA_CENTER.z + (authored_position.z - ARENA_CENTER.z) * MAP_SCALE)


func _own_shallow(node: Node, scene_owner: Node) -> void:
	node.owner = scene_owner
	# Preserve player/gun PackedScene instancing; descend only through locally
	# authored UI/system branches copied out of the scaffold scene.
	if node.scene_file_path != "":
		return
	for child in node.get_children():
		_own_shallow(child, scene_owner)
