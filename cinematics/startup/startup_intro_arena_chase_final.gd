extends "res://cinematics/startup/startup_intro_arena_chase.gd"

## Fluid-camera refinement for the arena-chase concept. The base scene authors
## clean shot targets; a separate presentation camera follows those targets on
## a damped arc around the arena. This preserves readable compositions without
## exposing hard transform cuts or flying linearly through the action.

@export_group("Camera Flow")
@export_range(7.0, 20.0, 0.25) var camera_follow_responsiveness := 11.5
@export_range(0.12, 0.40, 0.01) var transition_veil_strength := 0.22

const CAMERA_ORBIT_FOCUS := Vector3(0.0, 1.05, 0.0)

var _presentation_camera: Camera3D = null


func _build_stage() -> void:
	super._build_stage()
	# The inherited camera remains the authored target used by every existing
	# shot and tween. Only this follower becomes current, so no choreography code
	# needs to fight a second set of camera keyframes.
	_presentation_camera = Camera3D.new()
	_presentation_camera.name = "FluidPresentationCamera"
	_presentation_camera.transform = _camera.transform
	_presentation_camera.fov = _camera.fov
	_presentation_camera.near = _camera.near
	_presentation_camera.far = _camera.far
	_presentation_camera.cull_mask = _camera.cull_mask
	_stage.add_child(_presentation_camera)
	_camera.current = false
	_presentation_camera.current = true


func _process(delta: float) -> void:
	if _presentation_camera == null or _camera == null:
		return
	if _reduced_motion:
		_sync_presentation_camera()
		return
	var blend := 1.0 - exp(-camera_follow_responsiveness * maxf(delta, 0.0))
	var current_transform := _presentation_camera.transform
	var target_transform := _camera.transform
	var current_offset := current_transform.origin - CAMERA_ORBIT_FOCUS
	var target_offset := target_transform.origin - CAMERA_ORBIT_FOCUS
	var next_origin := current_transform.origin.lerp(target_transform.origin, blend)
	if current_offset.length_squared() > 0.001 \
			and target_offset.length_squared() > 0.001:
		# Spherical direction interpolation keeps large reversals outside the
		# center action instead of sending the camera straight through the cats.
		var next_direction := current_offset.normalized().slerp(
			target_offset.normalized(), blend).normalized()
		var next_radius := lerpf(current_offset.length(), target_offset.length(), blend)
		next_origin = CAMERA_ORBIT_FOCUS + next_direction * next_radius
	var next_basis := current_transform.basis.slerp(
		target_transform.basis, blend).orthonormalized()
	_presentation_camera.transform = Transform3D(next_basis, next_origin)
	_presentation_camera.fov = lerpf(_presentation_camera.fov, _camera.fov, blend)


func _reset_presentation() -> void:
	super._reset_presentation()
	_sync_presentation_camera()


func _sync_presentation_camera() -> void:
	if _presentation_camera == null or _camera == null:
		return
	_presentation_camera.transform = _camera.transform
	_presentation_camera.fov = _camera.fov


func _blue_claims_center_gun(generation: int) -> bool:
	# The race wide has already established everyone. A clean two-character cut
	# keeps the handoff free of tails, shoulders, and unrelated faces. Extra
	# lateral separation prevents the two silhouettes from touching in camera.
	var blue := _actors.get("blue") as Node3D
	var purple := _actors.get("purple") as Node3D
	if blue != null:
		blue.position = Vector3(0.35, ACTOR_FLOOR_Y, 0.88)
	if purple != null:
		purple.position = Vector3(-2.25, ACTOR_FLOOR_Y, -0.18)
	_show_only(["blue", "purple"])
	return await super._blue_claims_center_gun(generation)


func _shoot_first_contender(generation: int) -> bool:
	var blue := _actors.get("blue") as Node3D
	var purple := _actors.get("purple") as Node3D
	if blue == null or purple == null:
		return false
	# Cross to Blue's on-hand side. The follower travels around the arena focus,
	# so this large reversal becomes a fast orbit rather than a center-crossing
	# cut. The slightly longer settle is still short enough to feel immediate.
	_camera.fov = 38.0
	_camera.transform = _camera_transform(
		Vector3(1.40, 2.20, -5.40), Vector3(-0.92, 1.10, 0.28))
	_aim_action_spot(purple.global_position, Color(0.72, 0.42, 1.0))
	_face_actor_toward(purple, blue.position)
	_face_actor_toward(blue, purple.position)
	_set_blue_firing_pose()
	if not await _wait_for(0.26, generation):
		return false
	return await _shoot_actor("purple", 0.95, 0.30, generation)


func _pause_animation(actor_id: String) -> void:
	if actor_id == "blue":
		_set_blue_firing_pose()
		return
	super._pause_animation(actor_id)


func _set_blue_firing_pose() -> void:
	# Pistol Run contains a clean two-handed aim at 0.30 seconds. Seeking to that
	# exact pose removes animation-loop luck from every shot and, most
	# importantly, keeps the final barrel aimed through the center lens.
	var player := _animation_players.get("blue") as AnimationPlayer
	if player == null or not player.has_animation("pistol_run"):
		return
	player.speed_scale = 1.0
	player.play("pistol_run", 0.08)
	var animation := player.get_animation("pistol_run")
	player.seek(minf(0.30, animation.length * 0.42), true)
	player.pause()
	player.advance(0.0)


func _soft_camera_cut() -> void:
	# A dark exposure veil masks actor visibility/setup changes while the camera
	# begins moving. It is intentionally subtler and slower than the old blue
	# flash, so transitions breathe without reading as another gunshot.
	_flash.color = Color(BACKGROUND_COLOR, transition_veil_strength)
	_tween_property(_flash, "color:a", 0.0, 0.24,
		Tween.TRANS_SINE, Tween.EASE_OUT)

