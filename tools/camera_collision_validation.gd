extends Node3D

var failures: Array[String] = []


func _ready() -> void:
	GameConfig.split_screen_enabled = false
	GameConfig.bot_configs = []
	PauseManager._pause_open = false

	var wall := _build_wall()
	add_child(wall)
	var player = load("res://player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector3.ZERO
	var arm := player.get_node("AimPivot/SpringArm3D") as SpringArm3D

	wall.global_position = arm.global_position + arm.global_basis.z * 2.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(arm.collision_mask == 1,
		"player camera does not use the map-geometry collision layer")
	_check(arm.margin >= 0.1,
		"player camera collision margin is too small to prevent near-plane clipping")
	_check(arm.get_hit_length() < arm.spring_length - 0.5,
		"player camera did not retract in front of blocking map geometry")

	wall.collision_layer = 2
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(arm.get_hit_length() > arm.spring_length - 0.1,
		"player camera is blocked by a non-map collision layer")

	var mouse_motion := InputEventMouseMotion.new()
	mouse_motion.relative = Vector2(40.0, 25.0)
	var yaw_before: float = player.get_node("AimPivot").rotation.y
	var pitch_before: float = arm.rotation.x
	PauseManager._pause_open = true
	player._input(mouse_motion)
	_check(is_equal_approx(player.get_node("AimPivot").rotation.y, yaw_before)
		and is_equal_approx(arm.rotation.x, pitch_before),
		"player camera still responds to mouse movement while paused")
	PauseManager._pause_open = false
	player._input(mouse_motion)
	_check(not is_equal_approx(player.get_node("AimPivot").rotation.y, yaw_before)
		and not is_equal_approx(arm.rotation.x, pitch_before),
		"player camera no longer responds after pause closes")

	wall.collision_layer = 1
	wall.global_position = Vector3(0.0, 2.0, 2.0)
	var spectator = load("res://spectator_controller.gd").new()
	player.add_child(spectator)
	spectator.setup(player)
	await get_tree().physics_frame
	spectator._free_cam_pivot.global_position = Vector3(0.0, 2.0, 0.0)
	spectator._move_free_camera(Vector3(0.0, 0.0, 4.0))
	_check(spectator._free_cam_pivot.global_position.z < 1.8,
		"spectator free camera passed through map geometry")

	var spectator_yaw: float = spectator._free_cam_pivot.rotation.y
	PauseManager._pause_open = true
	spectator._input(mouse_motion)
	_check(is_equal_approx(spectator._free_cam_pivot.rotation.y, spectator_yaw),
		"spectator camera still responds to mouse movement while paused")
	PauseManager._pause_open = false
	spectator.cleanup()

	_finish()


func _build_wall() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "CameraCollisionWall"
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10.0, 10.0, 0.5)
	collision.shape = shape
	body.add_child(collision)
	return body


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	PauseManager._pause_open = false
	if failures.is_empty():
		print("CAMERA COLLISION VALIDATION: PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("CAMERA COLLISION VALIDATION: %s" % failure)
	get_tree().quit(1)
