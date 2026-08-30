extends "res://cinematics/startup/startup_intro_preview_blue_shot.gd"

## Standalone smooth-shot revision of the startup blockout.
##
## The ceremonial display gun is the same Node3D Blue ultimately fires. It is
## reparented to the animated hand socket with its world transform preserved,
## then eased into the authored grip while Blue and the camera move together.
## This removes the visible display/held-model swap from earlier revisions.

@export_group("Final Shot Framing")
@export var final_camera_position := Vector3(0.18, 1.92, 4.82)
@export var final_camera_target := Vector3(0.0, 1.34, 0.48)
@export var gun_grip_offset := Vector3(0.035, -0.035, 0.105)
@export var gun_grip_rotation_degrees := Vector3(-3.0, 0.0, -4.0)
@export_range(0.0015, 0.0025, 0.00005) var final_gun_scale := 0.00195
@export_range(0.35, 1.20, 0.01) var pickup_duration := 0.72

const DISPLAY_GUN_SCALE := 0.0032
const DISPLAY_GUN_ROTATION_DEGREES := Vector3(-8.0, -90.0, 8.0)
const BLUE_FINAL_POSITION := Vector3(0.0, 0.23, 0.42)
const BLUE_FINAL_SCALE := Vector3.ONE * 1.12


func _reset_presentation() -> void:
	# Replay may find the one visible gun parented to Blue's animated hand.
	# Return that same instance to its display pivot before restoring the base
	# presentation. A second visible gun is never involved in this revision.
	if _gun_visual != null and _gun_pivot != null \
			and _gun_visual.get_parent() != _gun_pivot:
		_gun_visual.reparent(_gun_pivot, false)
	super._reset_presentation()
	if _gun_visual != null:
		_gun_visual.visible = true
		_gun_visual.position = Vector3.ZERO
		_gun_visual.rotation_degrees = DISPLAY_GUN_ROTATION_DEGREES
		_gun_visual.scale = Vector3.ONE * DISPLAY_GUN_SCALE
	if _held_gun_visual != null:
		# The inherited visual is retained only to keep this comparison scene
		# compatible with its parent. It never becomes visible.
		_held_gun_visual.visible = false


func _run_sequence(generation: int) -> void:
	if not await _wait_for(0.35, generation):
		return
	_stage.visible = true
	_gun_pivot.visible = true
	_show_phrase("ONE [color=#ffad29]GUN[/color]")
	_tween_property(_logo, "modulate:a", 0.0, 0.30)
	_tween_property(_camera, "transform", _camera_transform(
		Vector3(0.0, 1.92, 5.75), Vector3(0.0, 1.25, 0.0)), _motion_time(0.95))
	_tween_property(_gun_pivot, "rotation:y", PI * 0.72, _motion_time(1.10))

	if not await _wait_for(1.18, generation):
		return
	_show_phrase("ONE [color=#ffad29]SHOT[/color]")
	_tween_property(_camera, "transform", _camera_transform(
		Vector3(2.85, 1.70, 4.35), Vector3(0.0, 1.30, 0.0)), _motion_time(0.34))
	_tween_property(_gun_pivot, "rotation:y", PI * 1.10, _motion_time(0.42))

	if not await _wait_for(0.64, generation):
		return
	AudioManager.play_sfx("gun_shot", 1.0, 0.86)
	_fire_gunshot_flash()

	if not await _wait_for(0.16, generation):
		return
	_show_phrase("EVERYONE [color=#ffad29]WANTS IT[/color]")
	_tween_property(_camera, "transform", _camera_transform(
		Vector3(0.0, 4.20, 10.45), Vector3(0.0, 1.05, 0.15)), _motion_time(0.32))
	for configuration in ACTOR_LAYOUT:
		_reveal_actor(str(configuration["id"]))
		if not await _wait_for(0.10, generation):
			return

	if not await _wait_for(0.82, generation):
		return
	_show_phrase("LAST [color=#ffad29]ONE[/color]")

	if not await _wait_for(0.34, generation):
		return
	for index in ELIMINATION_ORDER.size():
		_eliminate_actor(ELIMINATION_ORDER[index])
		if not await _wait_for(ELIMINATION_DELAYS[index], generation):
			return

	await _blue_takes_and_fires_smoothly(generation)


func _blue_takes_and_fires_smoothly(generation: int) -> void:
	var blue := _actors.get("blue") as Node3D
	if blue == null or _blue_gun_socket == null or _gun_visual == null:
		await _transition_to_title(generation)
		return

	_show_phrase("LAST ONE\n[color=#ffad29]STANDING[/color]", 78)
	_tween_property(_blue_spotlight, "light_energy", 7.2, _motion_time(0.30))
	_tween_property(blue, "position", BLUE_FINAL_POSITION,
		_motion_time(pickup_duration), Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	_tween_property(blue, "scale", BLUE_FINAL_SCALE,
		_motion_time(pickup_duration), Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	_tween_property(_camera, "transform", _camera_transform(
		final_camera_position, final_camera_target), _motion_time(pickup_duration),
		Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)

	# Begin the pose before the gun reaches the paw. The model has already been
	# loaded during scene preparation, so this does not introduce a resource-load
	# hitch in the visible part of the cinematic.
	_begin_blue_firing_pose(generation)

	# Keep the exact display gun visible and preserve its current world pose at
	# the reparent frame. Local easing then carries it continuously into Blue's
	# character-facing hand socket. The GLB's muzzle is local +Z, so a near-zero
	# yaw correctly points it toward the center camera (the older look_at pivot
	# used -Z and therefore presented the gun backwards).
	_gun_visual.reparent(_blue_gun_socket, true)
	_gun_pivot.visible = false
	var gun_move := create_tween()
	gun_move.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	gun_move.set_parallel(true)
	gun_move.tween_property(_gun_visual, "position", gun_grip_offset,
		_motion_time(pickup_duration)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	gun_move.tween_property(_gun_visual, "rotation_degrees",
		gun_grip_rotation_degrees, _motion_time(pickup_duration)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	gun_move.tween_property(_gun_visual, "scale", Vector3.ONE * final_gun_scale,
		_motion_time(pickup_duration)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_active_tweens.append(gun_move)

	_fade_last_standing_text(generation)
	if not await _wait_for(pickup_duration + 0.14, generation):
		return
	await _fire_continuous_final_shot(blue, generation)


func _begin_blue_firing_pose(generation: int) -> void:
	if _blue_animation_player == null \
			or not _blue_animation_player.has_animation("pistol_run"):
		return
	_blue_animation_player.speed_scale = 0.92
	_blue_animation_player.play("pistol_run", 0.24)
	_settle_blue_firing_pose(generation)


func _settle_blue_firing_pose(generation: int) -> void:
	if not await _wait_for(0.30, generation):
		return
	if _blue_animation_player != null:
		_blue_animation_player.pause()
		_blue_animation_player.advance(0.0)


func _fade_last_standing_text(generation: int) -> void:
	if not await _wait_for(0.34, generation):
		return
	_tween_property(_phrase, "modulate:a", 0.0, 0.25,
		Tween.TRANS_QUAD, Tween.EASE_IN_OUT)


func _fire_continuous_final_shot(blue: Node3D, generation: int) -> void:
	AudioManager.play_sfx("gun_shot", 1.0, 0.94)
	if not _reduced_motion:
		var recoil_position := gun_grip_offset + Vector3(0.0, 0.015, -0.09)
		var recoil := create_tween()
		recoil.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		recoil.tween_property(_gun_visual, "position", recoil_position, 0.055) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		recoil.tween_property(_gun_visual, "position", gun_grip_offset, 0.11) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_active_tweens.append(recoil)
		_tween_property(blue, "rotation:x", deg_to_rad(-2.5), 0.055,
			Tween.TRANS_QUAD, Tween.EASE_OUT)

	var allowed_flash := AccessibilityManager.allow_flash()
	if allowed_flash:
		_flash.color = Color(1.0, 0.88, 0.66, 0.96)
	else:
		_screen_fade.color = Color(BACKGROUND_COLOR, 1.0)
	if not await _wait_for(0.075, generation):
		return

	_stage.visible = false
	_phrase.modulate.a = 0.0
	_logo.visible = true
	_logo.modulate.a = 0.0
	_prompt.visible = true
	_prompt.modulate.a = 0.0
	if allowed_flash:
		_tween_property(_flash, "color:a", 0.0, 0.40,
			Tween.TRANS_QUAD, Tween.EASE_OUT)
	else:
		_tween_property(_screen_fade, "color:a", 0.0, 0.32)
	_tween_property(_logo, "modulate:a", 1.0, 0.38,
		Tween.TRANS_QUAD, Tween.EASE_OUT)
	if not await _wait_for(0.44, generation):
		return
	_state = PreviewState.TITLE
	_tween_property(_prompt, "modulate:a", 0.88, 0.25)
	_start_prompt_pulse()

