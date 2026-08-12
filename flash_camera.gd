extends "res://item.gd"

const MAX_FLASH_DISTANCE := 30.0
const MAX_CAMERA_CONE_DEGREES := 60.0
const TARGET_FACING_TOLERANCE_DEGREES := 60.0

var camera_mode := false

func get_display_name():
	return "Flash Camera"

func begin_use() -> void:
	if not is_held or player_ref == null:
		return
	if camera_mode:
		_take_photo()
	else:
		_set_camera_mode(true)

func release_use() -> void:
	pass

func cancel_use() -> void:
	_set_camera_mode(false)

func is_committed_use() -> bool:
	return false

func is_throw_preview_active() -> bool:
	return false

func get_throw_preview_data() -> Dictionary:
	return {}

func is_camera_mode_active() -> bool:
	return camera_mode

func _set_camera_mode(enabled: bool) -> void:
	camera_mode = enabled and is_held

func _take_photo() -> void:
	if not camera_mode or not is_held or player_ref == null:
		return
	for overlay in get_tree().get_nodes_in_group("flash_camera_overlay"):
		if overlay.has_method("show_shutter_for"):
			overlay.show_shutter_for(player_ref)
	_set_camera_mode(false)
	if NetworkManager.is_online():
		var rm = _online_round_manager()
		if rm != null:
			if NetworkManager.is_host() and "is_bot" in player_ref and player_ref.is_bot:
				_server_try_photo(_holder_actor_id(), _online_round_epoch())
			else:
				rm.request_online_item_action(online_item_id, "photo", _online_round_epoch())
	else:
		_resolve_photo_local()
		_consume_camera_local()

func _server_try_photo(sender_id: int, epoch: int) -> void:
	if not multiplayer.is_server() or not is_held or _holder_actor_id() != sender_id:
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(epoch):
		return
	var photographer = NetworkManager.find_actor(sender_id)
	if photographer == null or photographer.is_eliminated:
		return
	for target in get_tree().get_nodes_in_group("player"):
		var duration := _validated_flash_duration(photographer, target)
		if duration > 0.0:
			rm.server_apply_online_item_effect("flash_blind", int(target.get("actor_id")), {"duration": duration})
	rm.server_consume_online_item(online_item_id, respawn_after_deploy_time, epoch)

func _resolve_photo_local() -> void:
	for target in get_tree().get_nodes_in_group("player"):
		var duration := _validated_flash_duration(player_ref, target)
		if duration > 0.0 and target.has_method("apply_flash_blind"):
			target.apply_flash_blind(duration)

func _validated_flash_duration(photographer, target) -> float:
	if photographer == null or target == null or target == photographer or bool(target.get("is_eliminated")):
		return 0.0
	if not GameConfig.can_affect(photographer, target):
		return 0.0
	var distance: float = photographer.global_position.distance_to(target.global_position)
	if distance > MAX_FLASH_DISTANCE or not VisibilityRules.has_visual_contact(photographer, target):
		return 0.0
	var camera: Camera3D = photographer.get_camera()
	var view_origin: Vector3 = camera.global_position if camera != null else photographer.global_position + Vector3.UP
	var view_forward: Vector3 = -camera.global_basis.z if camera != null else photographer.get_aim_direction().normalized()
	var to_target: Vector3 = (target.global_position + Vector3.UP - view_origin).normalized()
	if view_forward.dot(to_target) < cos(deg_to_rad(MAX_CAMERA_CONE_DEGREES * 0.5)):
		return 0.0
	# Human cameras get the stricter on-screen frame test. Camera-less bots use
	# the same 60-degree cone and LOS contract, allowing them to use the item
	# without inventing a render viewport solely for AI validation.
	if camera != null:
		var viewport_size := camera.get_viewport().get_visible_rect().size
		for overlay in get_tree().get_nodes_in_group("flash_camera_overlay"):
			if overlay.get("player") == photographer and overlay.size.x > 1.0 and overlay.size.y > 1.0:
				viewport_size = overlay.size
				break
		var screen_point := _project_for_view_size(camera, target.global_position + Vector3.UP, viewport_size)
		var frame := Rect2(viewport_size * 0.17, viewport_size * Vector2(0.66, 0.62))
		if not frame.has_point(screen_point):
			return 0.0
	var target_aim: Vector3 = target.get_aim_direction().normalized() if target.has_method("get_aim_direction") else -target.global_basis.z
	var toward_camera: Vector3 = (photographer.global_position - target.global_position).normalized()
	if target_aim.dot(toward_camera) < cos(deg_to_rad(TARGET_FACING_TOLERANCE_DEGREES)):
		return 0.0
	return lerpf(6.0, 3.0, clampf(distance / MAX_FLASH_DISTANCE, 0.0, 1.0))

func _project_for_view_size(camera: Camera3D, world_point: Vector3, view_size: Vector2) -> Vector2:
	var local := camera.global_transform.affine_inverse() * world_point
	var depth := maxf(-local.z, 0.001)
	var half_height := tan(deg_to_rad(camera.fov) * 0.5) * depth
	var half_width := half_height * (view_size.x / maxf(view_size.y, 1.0))
	return Vector2(
		(local.x / maxf(half_width, 0.001) + 1.0) * 0.5 * view_size.x,
		(1.0 - local.y / maxf(half_height, 0.001)) * 0.5 * view_size.y)

func _consume_camera_local() -> void:
	var holder = player_ref
	var world = get_tree().current_scene
	if get_parent() != world:
		reparent(world, true)
	if holder != null:
		if holder.has_method("clear_item_slot"):
			holder.clear_item_slot(self)
		elif "held_item" in holder and holder.held_item == self:
			holder.held_item = null
	is_held = false
	_hide_after_use()
	_schedule_respawn()

func _net_consume() -> void:
	_set_camera_mode(false)
	var holder = player_ref
	var world = get_tree().current_scene
	# Unlike thrown items, the camera is consumed while it is still parented to
	# the hand. Put the hidden pickup back in world space so its authoritative
	# respawn can restore it at the original marker.
	if world != null and get_parent() != world:
		reparent(world, true)
	if holder != null:
		if holder.has_method("clear_item_slot"):
			holder.clear_item_slot(self)
		elif "held_item" in holder and holder.held_item == self:
			holder.held_item = null
	is_held = false
	super._net_consume()
