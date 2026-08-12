extends Node

# Emitted after a map finishes loading into the preview viewport. The lobby
# uses this to capture live thumbnails for the map carousel cards.
signal map_shown(index: int)
signal map_failed(index: int, reason: String)

# ============================================================
# LobbyMapPreview
# Live 3D map preview behind the lobby UI. A camera slowly orbits the
# selected map's perimeter looking inward. In Vote/Random mode it cycles
# through every map, ~10s each, with a fade-out/fade-in between them.
#
# The maps are the real gameplay scenes, loaded and stripped of their
# gameplay/audio nodes at runtime so nothing but visuals + ambience runs.
# No map files are modified — only read and stripped in memory.
# ============================================================

# Node names removed from a map before it becomes a preview (gameplay + audio).
const STRIP_NAMES = [
	"RoundManager", "player1", "player2", "CanvasLayer", "SplitScreenLayer",
	"Gun", "MeleeWeapon", "MeleeWeaponSpawn", "MeleeWeaponSpawnp", "Melee Weapons",
	"Power Ups", "Powerups", "Items", "SpawnPoints", "ItemSpawnPoints",
	"gun_spawn_point", "NavigationRegion3D", "ForestAmbience",
]

const ORBIT_SPEED := 0.14         # rad/sec — full circle ~45s
const MAP_VIEW_SECONDS := 10.0    # clear-viewing window per map in cycle mode
const FADE_HALF_TIME := OneGunUI.TIME_MAP_FADE * 0.5

var _maps: Array = []             # the MAPS array from game_setup
var _mode: int = 1                # MapSelectMode (1 = SPECIFIC by default)
const MODE_SPECIFIC := 1          # must match game_setup.MapSelectMode.SPECIFIC
const MODE_RANDOM := 2            # must match game_setup.MapSelectMode.RANDOM

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _preview_root: Node3D = null
var _fade_rect: ColorRect = null
var _status: OneGunStatusPanel = null

var _current_index := -1
var _current_map: Node3D = null
var _orbit_angle := 0.0
var _orbit_center := Vector3.ZERO
var _orbit_radius := 20.0
var _orbit_height_ratio := 0.6
var _orbit_target_height_ratio := 0.1

var _cycling := false
var _cycle_timer := 0.0
var _fade_tween: Tween = null
var _swapping := false
var _requested_index := -1

# ------------------------------------------------------------

func setup(host: Control, maps: Array) -> void:
	_maps = maps
	name = "LobbyMapPreview"

	var vpc := SubViewportContainer.new()
	vpc.name = "MapPreviewContainer"
	vpc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vpc.stretch = true
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(vpc)

	_viewport = SubViewport.new()
	# Online already keeps a live ENet session and may be running on the lower-
	# spec partner machine. Render the decorative lobby map at a lower internal
	# resolution there to avoid a second full-resolution Forward+ world spike.
	_viewport.size = Vector2i(960, 540) if NetworkManager.is_online() else Vector2i(1600, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vpc.add_child(_viewport)

	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.fov = 60.0
	_camera.current = true
	_viewport.add_child(_camera)

	_preview_root = Node3D.new()
	_preview_root.name = "PreviewRoot"
	_viewport.add_child(_preview_root)

	# Persistent readability tint.
	var tint := ColorRect.new()
	tint.name = "PreviewTint"
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.04, 0.05, 0.09, 0.10)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(tint)

	# Transition fade (black, transparent until a swap).
	_fade_rect = ColorRect.new()
	_fade_rect.name = "PreviewFade"
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_fade_rect)

	_status = OneGunStatusPanel.new()
	_status.name = "PreviewStatus"
	_status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_status)

	# Push preview layers behind the lobby's interactive cabinets.
	host.move_child(vpc, 0)
	host.move_child(tint, 1)
	host.move_child(_fade_rect, 2)
	host.move_child(_status, 3)
	if _maps.is_empty():
		_status.show_empty("NO MAPS AVAILABLE", "Add a valid map entry to the map registry.")

func current_index() -> int:
	return _current_index


# Live snapshot of the 3D preview (no UI), for carousel thumbnails.
func capture_image() -> Image:
	if _viewport == null or DisplayServer.get_name() == "headless":
		return null   # the dummy renderer has no texture to read back
	return _viewport.get_texture().get_image()


# Called by game_setup on init and whenever mode/selection changes.
func apply(mode: int, index: int) -> void:
	_mode = mode
	if _maps.is_empty():
		_cycling = false
		_status.visible = true
		_status.show_empty("NO MAPS AVAILABLE", "Add a valid map entry to the map registry.")
		return
	if mode == MODE_RANDOM:
		_show_random_mystery()
	elif mode == MODE_SPECIFIC:
		_cycling = false
		_fade_rect.color.a = 0.0
		if _current_map == null or index != _current_index:
			_fade_swap_to(index)
	else:
		# Vote / Random: cycle through everything, starting from the top.
		_cycling = true
		if _current_index < 0:
			_fade_swap_to(0)
		_cycle_timer = MAP_VIEW_SECONDS

func _show_random_mystery() -> void:
	_cycling = false
	_swapping = false
	_requested_index = -1
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_clear_current_map()
	_current_index = -1
	_fade_rect.color = Color(0.02, 0.025, 0.05, 0.72)
	_status.visible = true
	_status.show_mystery(
		"RANDOM MAP",
		"The battlefield will be revealed when the match begins.")

func _process(delta: float) -> void:
	if _camera == null:
		return
	_orbit_angle += ORBIT_SPEED * delta
	var r := _orbit_radius * 1.2
	_camera.position = _orbit_center + Vector3(
		cos(_orbit_angle) * r,
		_orbit_radius * _orbit_height_ratio,
		sin(_orbit_angle) * r)
	_camera.look_at(
		_orbit_center + Vector3(0, _orbit_radius * _orbit_target_height_ratio, 0),
		Vector3.UP)

	if _cycling and not _swapping and _maps.size() > 1:
		_cycle_timer -= delta
		if _cycle_timer <= 0.0:
			var nxt := (_current_index + 1) % _maps.size()
			_fade_swap_to(nxt)
			_cycle_timer = MAP_VIEW_SECONDS

# ------------------------------------------------------------

func _fade_swap_to(index: int) -> void:
	if index < 0 or index >= _maps.size():
		return
	_requested_index = index
	if _current_map == null:
		# First load: no fade, just show it.
		_load_map(index)
		return
	if _swapping:
		# Preserve the latest carousel request. The current transition completes,
		# then immediately continues to the newest requested map.
		return
	_swapping = true
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_rect, "color:a", 1.0, FADE_HALF_TIME)
	_fade_tween.tween_callback(func(): _load_map(index))
	_fade_tween.tween_property(_fade_rect, "color:a", 0.0, FADE_HALF_TIME)
	_fade_tween.tween_callback(_finish_swap)


func _finish_swap() -> void:
	_swapping = false
	if _requested_index >= 0 and _requested_index != _current_index:
		_fade_swap_to(_requested_index)

func _load_map(index: int) -> void:
	_status.visible = true
	_status.show_loading("Loading live map preview…")
	var path := str(_maps[index].get("scene_path", ""))
	if not ResourceLoader.exists(path):
		_fail_map_load(index, "The map scene could not be found.")
		return
	# The dummy renderer cannot display or capture this viewport. Avoid loading
	# several complete gameplay maps into headless validation/dedicated-server
	# processes; visible game builds continue through the full live-preview path.
	if DisplayServer.get_name() == "headless":
		var headless_data: Dictionary = _maps[index]
		_clear_current_map()
		_current_index = index
		_orbit_angle = float(headless_data.get("preview_angle", 0.0))
		_orbit_height_ratio = float(headless_data.get("preview_height_ratio", 0.6))
		_orbit_target_height_ratio = float(headless_data.get("preview_target_height_ratio", 0.1))
		_orbit_center = headless_data.get("preview_center", Vector3.ZERO)
		_orbit_radius = float(headless_data.get("preview_radius", 20.0))
		_status.visible = false
		map_shown.emit(index)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		_fail_map_load(index, "The map scene could not be loaded.")
		return
	var instance := packed.instantiate()
	var map := instance as Node3D
	if map == null:
		instance.free()
		_fail_map_load(index, "The map preview root must be a Node3D.")
		return
	# Strip gameplay/audio BEFORE the map enters the tree so their _ready
	# never runs (no bot spawn, no music hijack).
	for child in map.get_children():
		if child.name in STRIP_NAMES:
			child.free()
	var map_data: Dictionary = _maps[index]
	for node_path in map_data.get("preview_hide_paths", []):
		var preview_only_hidden := map.get_node_or_null(NodePath(str(node_path))) as Node3D
		if preview_only_hidden != null:
			preview_only_hidden.visible = false
	_clear_current_map()
	_preview_root.add_child(map)
	_current_map = map
	_current_index = index
	_compute_orbit(map)
	_orbit_angle = float(map_data.get("preview_angle", 0.0))
	_orbit_height_ratio = float(map_data.get("preview_height_ratio", 0.6))
	_orbit_target_height_ratio = float(map_data.get("preview_target_height_ratio", 0.1))
	if map_data.has("preview_center"):
		_orbit_center = map_data["preview_center"]
	if map_data.has("preview_radius"):
		_orbit_radius = float(map_data["preview_radius"])
	_status.visible = false
	map_shown.emit(index)


func _fail_map_load(index: int, reason: String) -> void:
	_clear_current_map()
	_current_index = index
	_status.visible = true
	_status.show_unavailable("PREVIEW UNAVAILABLE", reason)
	map_failed.emit(index, reason)


func _clear_current_map() -> void:
	if _current_map != null and is_instance_valid(_current_map):
		_current_map.free()
	_current_map = null

func _compute_orbit(map: Node3D) -> void:
	# Frame the play area using the Ground mesh only (ignores giant skyline /
	# desert-backdrop meshes that would otherwise blow up the bounds).
	var ground := map.get_node_or_null("Ground")
	var ab: AABB
	var got := false
	if ground != null:
		ab = _mesh_aabb(ground)
		got = ab.size.length() > 0.1
	if not got:
		ab = _mesh_aabb(map)  # fallback: whole map
	_orbit_center = ab.position + ab.size * 0.5
	_orbit_radius = maxf(maxf(ab.size.x, ab.size.z) * 0.5, 8.0)

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
	for c in node.get_children():
		result.append_array(_find_meshes(c))
	return result
