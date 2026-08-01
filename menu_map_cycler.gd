extends Node

# ============================================================
# MenuMapCycler — FABLE5 packet §2.
#
# Shows live, gameplay-stripped previews of the real maps behind the main
# menu and rotates to the next one every 10 seconds with a full-screen fade.
#
# - Map list comes from game_setup.MAPS (single source of truth, no
#   hard-coded paths) and gameplay stripping reuses lobby_map_preview's
#   proven STRIP_NAMES (nodes are freed BEFORE entering the tree, so no
#   round logic, players, HUD, nav, or map audio ever runs).
# - Maps load with ResourceLoader threaded requests so switching never
#   freezes the menu; the swap itself happens fully behind the fade.
# - The menu camera orbits each map's auto-framed play area very slowly.
#   The character showcase is parented to the camera, so composition holds
#   across every map.
# - Cycling pauses when the application loses focus or the menu is hidden.
# ============================================================

const GAME_SETUP := preload("res://game_setup.gd")
const LOBBY_PREVIEW := preload("res://lobby_map_preview.gd")

const VIEW_SECONDS := 10.0         # packet: exactly 10 s per map
const FADE_TIME := 0.35            # x2 (out + in) = 0.7 s total transition

# Presentation: the camera stands flat on the ground at player eye height,
# pulled back from the map's middle (the gun spawn), gazing level across the
# arena with a slow pan — like a player standing there looking around.
const EYE_HEIGHT := 3.2            # player eye level (maps authored at root scale 2)
const VIEW_DISTANCE := 15.0        # horizontal pull-back from the anchor
const PAN_SPEED := 0.035           # rad/s gaze sweep
const PAN_RANGE := 0.32            # radians each side of the anchor

# Fallback when a map has no spawn markers: the old high orbit.
const ORBIT_SPEED := 0.04
const CAMERA_HEIGHT_MULT := 0.55
const CAMERA_DIST_MULT := 1.25

# Optional per-map tuning (keyed by scene_path):
#   "anchor_local": Vector3 — view anchor in map-local coords, replacing the
#                   gun spawn (used where the gun sits somewhere awkward).
#   "dist": float — multiplies the fallback orbit radius.
const MAP_OVERRIDES: Dictionary = {
	# Forest: view anchored in the flat southern clearing (its gun sits on the
	# bridge), and a brightness lift — its twilight mood runs darker than the
	# other maps, leaving the showcase underexposed without it.
	"res://maps/test/ForestMap.tscn": {
		"anchor_local": Vector3(-2.0, 1.2, -13.0),
		"brightness": 1.10,
		# Forest's trees/rocks sit much closer to the camera than the other
		# maps' buildings — pull the blur in so it softens like City/Western.
		"dof_begin": 6.0,
		"dof_transition": 4.0,
	},
}

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _fade_rect: ColorRect = null
var _menu_root: Control = null
var _reduced_motion := false

var _maps: Array = []
var _current_index := -1
var _current_map: Node3D = null
var _view_timer := 0.0
var _orbit_angle := 0.0
var _orbit_center := Vector3.ZERO
var _orbit_radius := 16.0
var _grounded := false             # true when a gun/spawn anchor placed the camera
var _cam_pos := Vector3.ZERO
var _view_target := Vector3.ZERO
var _pan_angle := 0.0
var _pan_direction := 1.0
var _swapping := false
var _loading_path := ""
var _loading_index := -1
var _app_focused := true
var _ambient_suspended := false

func setup(viewport: SubViewport, camera: Camera3D, fade_rect: ColorRect, menu_root: Control, reduced_motion: bool) -> void:
	_viewport = viewport
	_camera = camera
	_fade_rect = fade_rect
	_menu_root = menu_root
	_reduced_motion = reduced_motion
	_maps = GAME_SETUP.MAPS
	if _maps.is_empty():
		push_warning("MenuMapCycler: no maps registered in game_setup.MAPS")
		return
	# First preview shows immediately (synchronous — menu is still loading).
	_show_map(0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_app_focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_app_focused = true

func set_ambient_suspended(suspended: bool) -> void:
	_ambient_suspended = suspended

func _running() -> bool:
	return (
		_app_focused
		and not _ambient_suspended
		and _menu_root != null
		and _menu_root.is_visible_in_tree())

func _process(delta: float) -> void:
	if _camera == null or _current_map == null:
		return
	if not _running():
		return

	if _grounded:
		# Hovering behind/above the gun anchor, looking forward-and-down at it,
		# gaze sweeping slowly — same panning treatment as the old title camera.
		if not _reduced_motion:
			_pan_angle += PAN_SPEED * _pan_direction * delta
			if _pan_angle > PAN_RANGE:
				_pan_angle = PAN_RANGE
				_pan_direction = -1.0
			elif _pan_angle < -PAN_RANGE:
				_pan_angle = -PAN_RANGE
				_pan_direction = 1.0
		_camera.position = _cam_pos
		var gaze := (_view_target - _cam_pos).normalized().rotated(Vector3.UP, _pan_angle)
		_camera.look_at(_cam_pos + gaze * 10.0, Vector3.UP)
	else:
		# Fallback high orbit (map without spawn markers).
		if not _reduced_motion:
			_orbit_angle += ORBIT_SPEED * delta
		var r := _orbit_radius * CAMERA_DIST_MULT
		_camera.position = _orbit_center + Vector3(
			cos(_orbit_angle) * r,
			_orbit_radius * CAMERA_HEIGHT_MULT,
			sin(_orbit_angle) * r)
		_camera.look_at(_orbit_center + Vector3(0.0, _orbit_radius * 0.08, 0.0), Vector3.UP)

	# 10-second rotation (sequential order → never repeats the same map
	# back-to-back when more than one exists).
	if _maps.size() > 1 and not _swapping and _loading_path == "":
		_view_timer += delta
		if _view_timer >= VIEW_SECONDS:
			_begin_threaded_load((_current_index + 1) % _maps.size())

	# Poll the threaded load; swap behind the fade once it's ready.
	if _loading_path != "" and not _swapping:
		var status := ResourceLoader.load_threaded_get_status(_loading_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var packed: PackedScene = ResourceLoader.load_threaded_get(_loading_path)
			_loading_path = ""
			_fade_swap(packed, _loading_index)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			# Threaded path failed (can happen for cached resources) — fall back
			# to a direct load so the cycle never silently stops.
			var fallback: PackedScene = load(_loading_path) as PackedScene
			var fallback_index := _loading_index
			_loading_path = ""
			if fallback != null:
				_fade_swap(fallback, fallback_index)
			else:
				push_warning("MenuMapCycler: failed to load " + str(_maps[fallback_index]["scene_path"]))
				_view_timer = 0.0

func _begin_threaded_load(index: int) -> void:
	var path := str(_maps[index]["scene_path"])
	if not ResourceLoader.exists(path):
		_view_timer = 0.0
		return
	# Already in the resource cache (e.g. cycling back to the map that loaded
	# synchronously at menu open): threaded status reporting is unreliable for
	# cached resources, and load() is instant here anyway — swap directly.
	if ResourceLoader.has_cached(path):
		var packed: PackedScene = load(path)
		if packed != null:
			_fade_swap(packed, index)
		else:
			_view_timer = 0.0
		return
	_loading_index = index
	_loading_path = path
	ResourceLoader.load_threaded_request(path)

func _fade_swap(packed: PackedScene, index: int) -> void:
	_swapping = true
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, FADE_TIME)
	tween.tween_callback(func():
		_instance_map(packed, index)
	)
	tween.tween_property(_fade_rect, "color:a", 0.0, FADE_TIME)
	tween.tween_callback(func():
		_swapping = false
		_view_timer = 0.0
	)

# Synchronous first-map path (menu open shows a preview immediately).
func _show_map(index: int) -> void:
	var path := str(_maps[index]["scene_path"])
	if not ResourceLoader.exists(path):
		return
	var packed: PackedScene = load(path)
	if packed != null:
		_instance_map(packed, index)

func _instance_map(packed: PackedScene, index: int) -> void:
	if _current_map != null and is_instance_valid(_current_map):
		_current_map.free()   # immediate: never two full maps alive at once
		_current_map = null
	var map := packed.instantiate() as Node3D
	if map == null:
		return
	# The gun marks the middle of every ONE GUN arena — capture its local
	# position BEFORE the strip removes it.
	var gun_local := Vector3.INF
	for gun_name in ["Gun", "gun_spawn_point", "GunSpawnPoint"]:
		var gun_node := map.get_node_or_null(gun_name)
		if gun_node is Node3D:
			gun_local = gun_node.position
			break
	# Strip gameplay/audio BEFORE entering the tree so their _ready never runs.
	# Spawn markers are kept (inert Marker3Ds) — they help aim the view camera.
	# Melee placements are stripped by prefix (maps have several, numbered) so
	# no floating "[F] Crowbar" pickup labels appear in the menu.
	for child in map.get_children():
		var doomed: bool = child.name in LOBBY_PREVIEW.STRIP_NAMES and child.name != "SpawnPoints"
		doomed = doomed or String(child.name).begins_with("MeleeWeapon")
		if doomed:
			child.free()
	# Weapons/items can be nested anywhere in a map (Western parents its melee
	# under sub-nodes), so sweep the WHOLE tree by script — no "[F] Crowbar"
	# pickup labels may leak into the menu.
	for node in _collect_gameplay_nodes(map):
		node.free()
	_viewport.add_child(map)
	_current_map = map
	_current_index = index
	_apply_menu_environment(map)
	_compute_orbit(map)
	_setup_view_camera(map, gun_local)
	_orbit_angle = randf() * TAU if _current_index > 0 else 0.0
	if OS.is_debug_build():
		print("[MENU] map preview -> ", _maps[index]["scene_path"], " (grounded=", _grounded, ")")


# Anchor the view on the gun spawn (map middle) or the map's override anchor:
# camera stands flat at eye height, pulled back, gazing level across the
# arena. Pull-back direction runs toward the farthest spawn point so the shot
# looks across the play area.
func _setup_view_camera(map: Node3D, gun_local: Vector3) -> void:
	_grounded = false
	var override: Dictionary = MAP_OVERRIDES.get(str(_maps[_current_index]["scene_path"]), {})
	if override.has("anchor_local"):
		gun_local = override["anchor_local"]
	var target := Vector3.INF
	if gun_local != Vector3.INF:
		target = map.to_global(gun_local)
	else:
		# No gun node — fall back to the spawn point nearest the play center.
		var best_dist := INF
		for marker in get_tree().get_nodes_in_group("spawn_point"):
			if marker is Node3D and map.is_ancestor_of(marker):
				var d: float = Vector2(marker.global_position.x - _orbit_center.x,
					marker.global_position.z - _orbit_center.z).length()
				if d < best_dist:
					best_dist = d
					target = marker.global_position
	if target == Vector3.INF:
		return
	_grounded = true
	var back_dir := Vector3.BACK
	var far_dist := 0.0
	for marker in get_tree().get_nodes_in_group("spawn_point"):
		if marker is Node3D and map.is_ancestor_of(marker):
			var to_marker: Vector3 = marker.global_position - target
			to_marker.y = 0.0
			if to_marker.length() > far_dist:
				far_dist = to_marker.length()
				back_dir = to_marker.normalized()
	# Flat-on-the-ground: camera and gaze target share the same eye height,
	# so the horizon stays level (no downward tilt).
	_cam_pos = target + back_dir * VIEW_DISTANCE + Vector3(0.0, EYE_HEIGHT, 0.0)
	_view_target = target + Vector3(0.0, EYE_HEIGHT, 0.0)
	_pan_angle = 0.0
	_pan_direction = 1.0

# Frame the play area off the Ground mesh (same proven approach as the lobby
# preview) with optional per-map multipliers from MAP_OVERRIDES.
func _compute_orbit(map: Node3D) -> void:
	var ground := map.get_node_or_null("Ground")
	var ab: AABB
	var got := false
	if ground != null:
		ab = _mesh_aabb(ground)
		got = ab.size.length() > 0.1
	if not got:
		ab = _mesh_aabb(map)
	_orbit_center = ab.position + ab.size * 0.5
	_orbit_radius = maxf(maxf(ab.size.x, ab.size.z) * 0.5, 8.0)
	var override: Dictionary = MAP_OVERRIDES.get(str(_maps[_current_index]["scene_path"]) if _current_index >= 0 else "", {})
	_orbit_radius *= float(override.get("dist", 1.0))

# Section 5: shared cinematic identity layered onto each map's OWN mood.
# The map's environment resource is duplicated (never mutated — it's shared
# with gameplay) and enhanced: filmic tonemap, bloom so the pedestal's gold
# ring and map lights glow, a saturation/contrast lift toward the premium-toy
# look, and auto-exposure forced off so map swaps never pump brightness.
func _apply_menu_environment(map: Node3D) -> void:
	var we := _find_world_environment(map)
	var env: Environment
	if we != null and we.environment != null:
		env = we.environment.duplicate() as Environment
	else:
		env = Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 1.0
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.16
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.16
	env.adjustment_contrast = 1.05
	# Per-map exposure + depth-of-field trims (packet §5: shared identity,
	# per-map overrides). DOF distances vary because maps differ wildly in
	# how close their scenery sits to the menu camera.
	var override: Dictionary = MAP_OVERRIDES.get(str(_maps[_current_index]["scene_path"]), {})
	env.adjustment_brightness = float(override.get("brightness", 1.0))
	var attrs := _camera.attributes as CameraAttributesPractical
	if attrs != null:
		attrs.dof_blur_far_distance = float(override.get("dof_begin", 13.0))
		attrs.dof_blur_far_transition = float(override.get("dof_transition", 8.0))
	# The maps' fog was washing the showcase into a faded haze (it sits ~6 m
	# from the camera, inside the fog falloff). Thin it hard for the menu —
	# distant atmosphere survives, the near-field showcase stays punchy.
	if env.fog_enabled:
		env.fog_density *= 0.35
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density *= 0.4
	if we != null:
		we.environment = env
	else:
		var holder := WorldEnvironment.new()
		holder.name = "MenuEnvironment"
		holder.environment = env
		map.add_child(holder)

func _find_world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var found := _find_world_environment(child)
		if found != null:
			return found
	return null

# Every descendant carrying a combat-pickup script (melee, gun, item),
# collected before freeing so the traversal isn't invalidated mid-walk.
const GAMEPLAY_SCRIPTS := ["res://melee_weapon.gd", "res://gun.gd", "res://item.gd"]

func _collect_gameplay_nodes(node: Node, out: Array = []) -> Array:
	var node_script = node.get_script()
	if node_script != null and node_script is Script and (node_script as Script).resource_path in GAMEPLAY_SCRIPTS:
		out.append(node)
		return out   # children die with the parent
	for child in node.get_children():
		_collect_gameplay_nodes(child, out)
	return out

func _mesh_aabb(node: Node) -> AABB:
	var combined: AABB
	var first := true
	for mi in _find_meshes(node):
		if mi.mesh == null:
			continue
		var world_ab: AABB = mi.global_transform * mi.mesh.get_aabb()
		combined = world_ab if first else combined.merge(world_ab)
		first = false
	return combined

func _find_meshes(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_meshes(child))
	return result
