class_name ThrowArcOverlay
extends Control

var player = null
const SAMPLE_STEP := 0.07
const SAMPLE_COUNT := 11


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_player(value) -> void:
	player = value


func _process(_delta: float) -> void:
	queue_redraw()


func _preview_source():
	if player == null:
		return null
	if "active_slot" in player and player.active_slot in ["item1", "item2"] and player.has_method("get_active_item"):
		var item = player.get_active_item()
		if item != null and item.has_method("is_throw_preview_active") and item.is_throw_preview_active():
			return item
	if "active_slot" in player and player.active_slot == "weapon" and player.get("held_melee_weapon") != null:
		var melee = player.held_melee_weapon
		if melee.has_method("is_throw_preview_active") and melee.is_throw_preview_active():
			return melee
	return null


func _draw() -> void:
	var source = _preview_source()
	if source == null:
		return
	var data: Dictionary = source.get_throw_preview_data()
	if data.is_empty():
		return
	var camera: Camera3D = player.get_camera() if player.has_method("get_camera") else null
	if camera == null:
		return
	var origin: Vector3 = data["origin"]
	var velocity: Vector3 = data["velocity"]
	var gravity := float(data.get("gravity", 9.8))
	var previous := origin
	for index in range(1, SAMPLE_COUNT + 1):
		var t := index * SAMPLE_STEP
		var point := origin + velocity * t + Vector3.DOWN * 0.5 * gravity * t * t
		var query := PhysicsRayQueryParameters3D.create(previous, point, 1)
		if player is CollisionObject3D:
			query.exclude = [player.get_rid()]
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			point = hit.position
		if not camera.is_position_behind(point):
			var screen := _project_to_overlay(camera, point)
			draw_circle(screen, 3.7 if index % 2 == 0 else 2.7,
				Color(1.0, 0.82, 0.25, 0.92) if index % 2 == 0 else Color(1.0, 1.0, 1.0, 0.84))
		if not hit.is_empty():
			break
		previous = point


func _project_to_overlay(camera: Camera3D, world_point: Vector3) -> Vector2:
	# The gameplay camera is copied into a SubViewport for splitscreen, while the
	# source Camera3D still belongs to the root viewport. Project explicitly with
	# this HUD control's aspect ratio so dots stay aligned in both half-screen and
	# full-screen play.
	var local := camera.global_transform.affine_inverse() * world_point
	var depth := maxf(-local.z, 0.001)
	var half_height := tan(deg_to_rad(camera.fov) * 0.5) * depth
	var half_width := half_height * (size.x / maxf(size.y, 1.0))
	var normalized_x := local.x / maxf(half_width, 0.001)
	var normalized_y := local.y / maxf(half_height, 0.001)
	return Vector2(
		(normalized_x + 1.0) * 0.5 * size.x,
		(1.0 - normalized_y) * 0.5 * size.y)
