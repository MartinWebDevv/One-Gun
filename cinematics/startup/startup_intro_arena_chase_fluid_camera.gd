extends "res://cinematics/startup/startup_intro_arena_chase_final.gd"

## Motion guardrails for the fluid presentation camera. The parent establishes
## orbit-following behavior; this layer caps travel and turn velocity in real
## elapsed time and keeps camera orientation coupled to a blended action focus.

@export_group("Camera Motion Limits")
@export_range(18.0, 48.0, 1.0) var maximum_camera_speed := 34.0
@export_range(180.0, 420.0, 5.0) var maximum_camera_turn_speed := 300.0

var _last_camera_ticks_usec := 0
var _maximum_observed_camera_speed := 0.0
var _maximum_observed_turn_speed := 0.0
var _authored_camera_focus := CAMERA_ORBIT_FOCUS
var _presentation_camera_focus := CAMERA_ORBIT_FOCUS


func _camera_transform(position: Vector3, target: Vector3) -> Transform3D:
	# Every inherited shot already declares its subject through this helper.
	# Retain that target so the moving presentation camera can keep looking at a
	# smoothly blended subject throughout the transition, not just at its ends.
	_authored_camera_focus = target
	return super._camera_transform(position, target)


func _reset_presentation() -> void:
	super._reset_presentation()
	_presentation_camera_focus = _authored_camera_focus
	_last_camera_ticks_usec = Time.get_ticks_usec()
	_maximum_observed_camera_speed = 0.0
	_maximum_observed_turn_speed = 0.0


func _process(delta: float) -> void:
	if _presentation_camera == null or _camera == null:
		return
	if _reduced_motion:
		_sync_presentation_camera()
		_presentation_camera_focus = _authored_camera_focus
		return
	var current_ticks := Time.get_ticks_usec()
	var real_delta := maxf(delta, 0.0)
	if _last_camera_ticks_usec > 0:
		real_delta = maxf(
			float(current_ticks - _last_camera_ticks_usec) / 1_000_000.0, 0.0001)
	_last_camera_ticks_usec = current_ticks
	# A stalled frame must not turn into a visible catch-up jump.
	var safe_delta := minf(real_delta, 0.050)
	var response_blend := 1.0 - exp(-camera_follow_responsiveness * safe_delta)
	var current_transform := _presentation_camera.transform
	var target_transform := _camera.transform
	_presentation_camera_focus = _presentation_camera_focus.lerp(
		_authored_camera_focus, response_blend)

	var current_offset := current_transform.origin - CAMERA_ORBIT_FOCUS
	var target_offset := target_transform.origin - CAMERA_ORBIT_FOCUS
	var desired_origin := current_transform.origin.lerp(
		target_transform.origin, response_blend)
	if current_offset.length_squared() > 0.001 \
			and target_offset.length_squared() > 0.001:
		var desired_direction := current_offset.normalized().slerp(
			target_offset.normalized(), response_blend).normalized()
		var desired_radius := lerpf(
			current_offset.length(), target_offset.length(), response_blend)
		desired_origin = CAMERA_ORBIT_FOCUS + desired_direction * desired_radius
	var travel := desired_origin - current_transform.origin
	var maximum_travel := maximum_camera_speed * safe_delta
	if travel.length() > maximum_travel and maximum_travel > 0.0:
		desired_origin = current_transform.origin + travel.normalized() * maximum_travel

	# Recompute the desired look basis from the intermediate orbit position. A
	# plain endpoint-basis slerp can look outside the arena halfway through a
	# large arc even though both endpoint compositions are correct.
	var desired_look := Transform3D(Basis.IDENTITY, desired_origin).looking_at(
		_presentation_camera_focus, Vector3.UP)
	var current_forward := -current_transform.basis.z.normalized()
	var target_forward := -desired_look.basis.z.normalized()
	var turn_angle := acos(clampf(current_forward.dot(target_forward), -1.0, 1.0))
	var basis_blend := response_blend
	var maximum_turn := deg_to_rad(maximum_camera_turn_speed) * safe_delta
	if turn_angle > maximum_turn and turn_angle > 0.0001:
		basis_blend = minf(basis_blend, maximum_turn / turn_angle)
	var desired_basis := current_transform.basis.slerp(
		desired_look.basis, basis_blend).orthonormalized()
	var applied_forward := -desired_basis.z.normalized()
	var applied_turn := rad_to_deg(acos(clampf(
		current_forward.dot(applied_forward), -1.0, 1.0)))
	_maximum_observed_camera_speed = maxf(
		_maximum_observed_camera_speed,
		current_transform.origin.distance_to(desired_origin) / safe_delta)
	_maximum_observed_turn_speed = maxf(
		_maximum_observed_turn_speed, applied_turn / safe_delta)
	_presentation_camera.transform = Transform3D(desired_basis, desired_origin)
	_presentation_camera.fov = lerpf(
		_presentation_camera.fov, _camera.fov, response_blend)


func _shoot_first_contender(generation: int) -> bool:
	var blue := _actors.get("blue") as Node3D
	var purple := _actors.get("purple") as Node3D
	if blue == null or purple == null:
		return false
	_camera.fov = 38.0
	_camera.transform = _camera_transform(
		Vector3(1.40, 2.20, -5.40), Vector3(-0.92, 1.10, 0.28))
	_aim_action_spot(purple.global_position, Color(0.72, 0.42, 1.0))
	_face_actor_toward(purple, blue.position)
	_face_actor_toward(blue, purple.position)
	_set_blue_firing_pose()
	# This is the largest orbit in the sequence. Four tenths of a second keeps
	# the hit immediate while ensuring the capped camera completes the move.
	if not await _wait_for(0.40, generation):
		return false
	return await _shoot_actor("purple", 0.95, 0.30, generation)

