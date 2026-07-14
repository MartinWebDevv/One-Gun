extends Node

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
	"Gun", "MeleeWeapon", "MeleeWeaponSpawnp", "SpawnPoints", "ItemSpawnPoints",
	"gun_spawn_point", "NavigationRegion3D", "ForestAmbience",
]

const ORBIT_SPEED := 0.14         # rad/sec — full circle ~45s
const MAP_VIEW_SECONDS := 10.0    # clear-viewing window per map in cycle mode
const FADE_TIME := 0.6

var _maps: Array = []             # the MAPS array from game_setup
var _mode: int = 1                # MapSelectMode (1 = SPECIFIC by default)
const MODE_SPECIFIC := 1          # must match game_setup.MapSelectMode.SPECIFIC

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _preview_root: Node3D = null
var _fade_rect: ColorRect = null

var _current_index := -1
var _current_map: Node3D = null
var _orbit_angle := 0.0
var _orbit_center := Vector3.ZERO
var _orbit_radius := 20.0

var _cycling := false
var _cycle_timer := 0.0
var _fade_tween: Tween = null
var _swapping := false

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
	tint.color = Color(0.04, 0.05, 0.09, 0.28)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(tint)

	# Transition fade (black, transparent until a swap).
	_fade_rect = ColorRect.new()
	_fade_rect.name = "PreviewFade"
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_fade_rect)

	# Push all three behind the .tscn's existing UI panels.
	host.move_child(vpc, 0)
	host.move_child(tint, 1)
	host.move_child(_fade_rect, 2)

# Called by game_setup on init and whenever mode/selection changes.
func apply(mode: int, index: int) -> void:
	_mode = mode
	if mode == MODE_SPECIFIC:
		_cycling = false
		if index != _current_index:
			_fade_swap_to(index)
	else:
		# Vote / Random: cycle through everything, starting from the top.
		_cycling = true
		if _current_index < 0:
			_fade_swap_to(0)
		_cycle_timer = MAP_VIEW_SECONDS

func _process(delta: float) -> void:
	if _camera == null:
		return
	_orbit_angle += ORBIT_SPEED * delta
	var r := _orbit_radius * 1.2
	_camera.position = _orbit_center + Vector3(cos(_orbit_angle) * r, _orbit_radius * 0.6, sin(_orbit_angle) * r)
	_camera.look_at(_orbit_center + Vector3(0, _orbit_radius * 0.1, 0), Vector3.UP)

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
	if _current_map == null:
		# First load: no fade, just show it.
		_load_map(index)
		return
	if _swapping:
		return
	_swapping = true
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_rect, "color:a", 1.0, FADE_TIME)
	_fade_tween.tween_callback(func(): _load_map(index))
	_fade_tween.tween_property(_fade_rect, "color:a", 0.0, FADE_TIME)
	_fade_tween.tween_callback(func(): _swapping = false)

func _load_map(index: int) -> void:
	if _current_map != null and is_instance_valid(_current_map):
		_current_map.queue_free()
		_current_map = null
	var path: String = _maps[index]["scene_path"]
	if not ResourceLoader.exists(path):
		return
	var packed = load(path)
	if packed == null:
		return
	var map: Node3D = packed.instantiate()
	# Strip gameplay/audio BEFORE the map enters the tree so their _ready
	# never runs (no bot spawn, no music hijack).
	for child in map.get_children():
		if child.name in STRIP_NAMES:
			child.free()
	_preview_root.add_child(map)
	_current_map = map
	_current_index = index
	_orbit_angle = 0.0
	_compute_orbit(map)

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
