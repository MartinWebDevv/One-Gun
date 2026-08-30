extends SceneTree

# Runtime validation for the interactive Locker Hat preview path: full-body top
# clearance and manual controller rotation on every registered character model.

const HatRegistry = preload("res://models/cosmetics/hats/hat_cosmetic_registry.gd")
const SkinRegistry = preload("res://player_skin_registry.gd")

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var overlay_script = load("res://UI/themed_locker_overlay.gd")
	var overlay = overlay_script.new()
	overlay.configure(false, 1)
	root.add_child(overlay)
	await process_frame
	await process_frame
	var hat_ids: Array = HatRegistry.HATS.keys()
	hat_ids.sort()
	for model_id in SkinRegistry.MODEL_IDS:
		overlay.call("_select_model", model_id)
		await process_frame
		var camera = overlay.get("_preview_camera") as Camera3D
		var pivot = overlay.get("_preview_pivot") as Node3D
		var visual = overlay.get("_preview_visual") as Node3D
		var socket = visual.call("get_headwear_socket") as Marker3D \
			if visual != null else null
		var viewport = overlay.find_child(
			"CharacterViewport", true, false) as SubViewport
		var idle_player = overlay.get("_preview_animation_player") as AnimationPlayer
		_check(camera != null and pivot != null and socket != null \
			and viewport != null and idle_player != null \
			and idle_player.current_animation == "idle" \
			and idle_player.is_playing(),
			"%s Locker preview did not build its 3D character path" % model_id)
		if camera == null or pivot == null or socket == null or viewport == null:
			continue
		for item_id in hat_ids:
			overlay.call("_preview_locker_hat", str(item_id))
			await process_frame
			await process_frame
			for yaw_degrees in [0.0, 90.0, 180.0, 270.0]:
				pivot.rotation.y = deg_to_rad(yaw_degrees)
				if visual.has_method("_process"):
					visual.call("_process", 0.0)
				var bounds := _hat_screen_bounds(camera, socket)
				_check(bounds.position.y >= 20.0,
					"%s Locker %s at %d degrees had only %.1f px top margin" % [
						model_id, item_id, int(yaw_degrees), bounds.position.y])
				_check(bounds.position.x >= 8.0 \
						and bounds.end.x <= float(viewport.size.x) - 8.0,
					"%s Locker %s at %d degrees exceeded horizontal framing: %s" % [
						model_id, item_id, int(yaw_degrees), bounds])
		pivot.rotation = Vector3.ZERO
		var before_rotation: float = pivot.rotation.y
		var camera_before: Transform3D = camera.global_transform
		Input.action_press("p1_look_right", 1.0)
		overlay.call("_process", 0.30)
		Input.action_release("p1_look_right")
		await process_frame
		_check(not is_equal_approx(pivot.rotation.y, before_rotation),
			"%s Locker preview ignored controller rotation" % model_id)
		_check(camera.global_transform.is_equal_approx(camera_before),
			"%s Locker rotation moved the fixed preview camera/background" % model_id)
	overlay.queue_free()
	await process_frame
	if _failed:
		quit(1)
	else:
		print("HAT_PREVIEW_INTERACTION_VALIDATION: PASS hats=%d models=%d angles=4 controller=1" % [
			HatRegistry.HATS.size(), SkinRegistry.MODEL_IDS.size()])
		quit(0)


func _hat_screen_bounds(camera: Camera3D, socket: Marker3D) -> Rect2:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var hat := socket.find_child("HatVisual", false, false) as Node3D
	if hat == null:
		return Rect2(Vector2(-INF, -INF), Vector2.ZERO)
	for node in hat.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null \
				or not mesh_instance.is_visible_in_tree():
			continue
		var bounds := mesh_instance.mesh.get_aabb()
		for corner_index in 8:
			var corner := bounds.position + Vector3(
				bounds.size.x if (corner_index & 1) != 0 else 0.0,
				bounds.size.y if (corner_index & 2) != 0 else 0.0,
				bounds.size.z if (corner_index & 4) != 0 else 0.0)
			var screen := camera.unproject_position(mesh_instance.to_global(corner))
			minimum.x = minf(minimum.x, screen.x)
			minimum.y = minf(minimum.y, screen.y)
			maximum.x = maxf(maximum.x, screen.x)
			maximum.y = maxf(maximum.y, screen.y)
	return Rect2(minimum, maximum - minimum)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("HAT PREVIEW INTERACTION VALIDATION FAILED: %s" % message)
