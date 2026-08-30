extends "res://cinematics/startup/startup_intro_preview_smooth_shot.gd"

## Final captionless startup cinematic: Blue claims the one gun, eliminates the
## five competitors through clean single-subject montage cuts, then fires the
## approved muzzle-flash transition into the logo.

const ROCK_CUE = preload("res://audio/ui/startup_five_shot_rock.wav")
const TARGET_ORDER: Array[String] = [
	"green", "pink", "purple", "orange", "yellow",
]
const SHOT_PITCHES: Array[float] = [0.94, 0.99, 1.03, 0.97, 0.90]
const POST_SHOT_HOLDS: Array[float] = [0.34, 0.30, 0.26, 0.26, 0.40]

var _rock_player: AudioStreamPlayer = null
var _target_spotlight: SpotLight3D = null


func _build_stage() -> void:
	super._build_stage()
	_target_spotlight = SpotLight3D.new()
	_target_spotlight.name = "MontageTargetSpotlight"
	_target_spotlight.light_color = Color(1.0, 0.77, 0.48)
	_target_spotlight.light_energy = 0.0
	_target_spotlight.spot_range = 10.0
	_target_spotlight.spot_angle = 25.0
	_target_spotlight.shadow_enabled = false
	_stage.add_child(_target_spotlight)

	_rock_player = AudioStreamPlayer.new()
	_rock_player.name = "StartupRockCue"
	_rock_player.stream = ROCK_CUE
	_rock_player.bus = &"Master"
	_rock_player.volume_db = AudioManager.MUSIC_VOLUME_DB - 1.5
	add_child(_rock_player)


func _reset_presentation() -> void:
	super._reset_presentation()
	_set_actor_start("blue", Vector3(0.0, 0.23, -1.82))
	_set_actor_start("green", Vector3(-3.00, 0.23, 0.92))
	_set_actor_start("pink", Vector3(2.72, 0.23, -0.92))
	_set_actor_start("purple", Vector3(-1.48, 0.23, 2.12))
	_set_actor_start("orange", Vector3(1.48, 0.23, 2.12))
	_set_actor_start("yellow", Vector3(3.00, 0.23, 0.92))
	_phrase.text = ""
	_phrase.modulate.a = 0.0
	_screen_fade.color = Color(BACKGROUND_COLOR, 1.0)
	_camera.fov = 43.0
	_camera.transform = _camera_transform(
		Vector3(0.0, 3.72, 9.25), Vector3(0.0, 1.02, 0.20))
	_blue_spotlight.light_energy = 0.0
	if _target_spotlight != null:
		_target_spotlight.light_energy = 0.0
	if _rock_player != null:
		_rock_player.stop()
	var warm_key := _stage.get_node_or_null("WarmKey") as DirectionalLight3D
	if warm_key != null:
		warm_key.light_energy = 1.18
	var cool_rim := _stage.get_node_or_null("CoolRim") as DirectionalLight3D
	if cool_rim != null:
		cool_rim.light_energy = 0.86


func _run_sequence(generation: int) -> void:
	if not await _wait_for(0.35, generation):
		return
	_stage.visible = true
	_gun_pivot.visible = true
	if _rock_player != null:
		_rock_player.volume_db = AudioManager.MUSIC_VOLUME_DB - 1.5
		_rock_player.play()
	_tween_property(_logo, "modulate:a", 0.0, 0.28)
	_tween_property(_screen_fade, "color:a", 0.0, 0.58,
		Tween.TRANS_QUAD, Tween.EASE_OUT)
	for actor_id in ["blue", "green", "pink", "purple", "orange", "yellow"]:
		_reveal_actor(actor_id)
	_tween_property(_camera, "transform", _camera_transform(
		Vector3(0.0, 3.05, 7.82), Vector3(0.0, 1.10, 0.20)),
		_motion_time(1.16), Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	_tween_property(_gun_pivot, "rotation:y", PI * 0.62,
		_motion_time(1.18), Tween.TRANS_SINE, Tween.EASE_IN_OUT)

	if not await _wait_for(1.20, generation):
		return
	if not await _blue_claims_the_gun(generation):
		return
	if not await _wait_for(0.22, generation):
		return

	for index in TARGET_ORDER.size():
		if not await _play_clean_target_shot(
			TARGET_ORDER[index], SHOT_PITCHES[index],
			POST_SHOT_HOLDS[index], generation):
			return

	if not await _frame_blue_alone(generation):
		return
	var blue := _actors.get("blue") as Node3D
	if blue == null:
		await _transition_to_title(generation)
		return
	await _fire_continuous_final_shot(blue, generation)


func _blue_claims_the_gun(generation: int) -> bool:
	var blue := _actors.get("blue") as Node3D
	if blue == null or _blue_gun_socket == null or _gun_visual == null:
		return false
	_tween_property(blue, "position", Vector3(0.0, 0.23, 0.26),
		_motion_time(0.82), Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	_tween_property(blue, "scale", Vector3.ONE * 1.06,
		_motion_time(0.82), Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	_tween_property(_camera, "transform", _camera_transform(
		Vector3(0.0, 2.30, 6.24), Vector3(0.0, 1.18, 0.28)),
		_motion_time(0.82), Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	_tween_property(_blue_spotlight, "light_energy", 4.2,
		_motion_time(0.46), Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	_begin_blue_firing_pose(generation)

	_gun_visual.reparent(_blue_gun_socket, true)
	_gun_pivot.visible = false
	var gun_move := create_tween()
	gun_move.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	gun_move.set_parallel(true)
	gun_move.tween_property(_gun_visual, "position", gun_grip_offset,
		_motion_time(0.78)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	gun_move.tween_property(_gun_visual, "rotation_degrees",
		gun_grip_rotation_degrees, _motion_time(0.78)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	gun_move.tween_property(_gun_visual, "scale", Vector3.ONE * final_gun_scale,
		_motion_time(0.78)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_active_tweens.append(gun_move)
	return await _wait_for(0.84, generation)


func _play_clean_target_shot(actor_id: String, pitch: float,
		post_shot_hold: float, generation: int) -> bool:
	var target := _actors.get(actor_id) as Node3D
	if target == null:
		return false
	# Every montage cut has exactly one readable subject. The opening wide shot
	# already established Blue as the shooter and all five competitors as targets.
	for id in _actors:
		(_actors[id] as Node3D).visible = id == actor_id
	target.scale = Vector3.ONE * 1.04
	var target_focus := target.global_position + Vector3(0.0, 1.10, 0.0)
	_camera.fov = 37.0
	_camera.transform = _camera_transform(
		target.global_position + Vector3(0.0, 1.58, 4.42), target_focus)
	_aim_target_spotlight(target.global_position)
	# A restrained light wipe hides the instantaneous camera cut without turning
	# each elimination into a full-screen strobe.
	var allowed_flash := AccessibilityManager.allow_flash()
	_flash.color = Color(0.74, 0.84, 1.0, 0.10 if allowed_flash else 0.025)
	_tween_property(_flash, "color:a", 0.0, 0.085,
		Tween.TRANS_QUAD, Tween.EASE_OUT)
	if not await _wait_for(0.10, generation):
		return false

	AudioManager.play_sfx("gun_shot", 0.94, pitch)
	_fire_montage_flash()
	_spawn_silent_confetti(
		target.global_position,
		(_actor_configuration.get(actor_id, {}) as Dictionary).get("accent", GOLD) as Color)
	target.visible = false
	return await _wait_for(post_shot_hold, generation)


func _frame_blue_alone(generation: int) -> bool:
	for id in _actors:
		(_actors[id] as Node3D).visible = id == "blue"
	var blue := _actors.get("blue") as Node3D
	if blue == null:
		return false
	blue.position = Vector3(0.0, 0.23, 0.42)
	blue.rotation = Vector3.ZERO
	blue.scale = Vector3.ONE * 1.12
	if _target_spotlight != null:
		_target_spotlight.light_energy = 0.0
	_blue_spotlight.light_energy = 7.2
	# Cut back under the final target flash, then use only a short centered push.
	_flash.color = Color(1.0, 0.88, 0.66,
		0.20 if AccessibilityManager.allow_flash() else 0.04)
	_camera.fov = 39.0
	_camera.transform = _camera_transform(
		Vector3(0.10, 2.08, 5.34), Vector3(0.0, 1.32, 0.43))
	_tween_property(_flash, "color:a", 0.0, 0.18,
		Tween.TRANS_QUAD, Tween.EASE_OUT)
	if not await _wait_for(0.18, generation):
		return false
	_tween_property(_camera, "transform", _camera_transform(
		final_camera_position, final_camera_target), _motion_time(0.50),
		Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	return await _wait_for(0.50, generation)


func _fire_montage_flash() -> void:
	var allowed_flash := AccessibilityManager.allow_flash()
	_flash.color = Color(1.0, 0.82, 0.48, 0.20 if allowed_flash else 0.04)
	_tween_property(_flash, "color:a", 0.0, 0.11,
		Tween.TRANS_QUAD, Tween.EASE_OUT)


func _spawn_silent_confetti(world_position: Vector3, accent: Color) -> void:
	var root := Node3D.new()
	root.name = "CinematicSilentPop"
	_stage.add_child(root)
	root.global_position = world_position + Vector3.UP * 1.1
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.amount = 54 if not _reduced_motion else 30
	particles.lifetime = 1.42
	particles.explosiveness = 1.0
	var confetti := BoxMesh.new()
	confetti.size = Vector3(0.052, 0.18, 0.018)
	var confetti_material := StandardMaterial3D.new()
	confetti_material.vertex_color_use_as_albedo = true
	confetti_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	confetti_material.emission_enabled = AccessibilityManager.allow_flash()
	confetti_material.emission = Color(0.36, 0.36, 0.36)
	confetti_material.emission_energy_multiplier = 0.28
	confetti.material = confetti_material
	particles.draw_pass_1 = confetti
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 67.0
	process.initial_velocity_min = 3.8
	process.initial_velocity_max = 6.8
	process.gravity = Vector3(0.0, -9.2, 0.0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.34
	process.angular_velocity_min = -650.0
	process.angular_velocity_max = 650.0
	var palette := Gradient.new()
	palette.offsets = PackedFloat32Array([0.0, 0.30, 0.54, 0.78, 1.0])
	palette.colors = PackedColorArray([
		accent, accent.lightened(0.22), Color(1.0, 0.82, 0.15),
		Color(0.18, 0.78, 1.0), Color(0.96, 0.35, 0.62),
	])
	var palette_texture := GradientTexture1D.new()
	palette_texture.gradient = palette
	process.color_ramp = palette_texture
	particles.process_material = process
	root.add_child(particles)
	particles.emitting = true
	root.get_tree().create_timer(1.75, true, false, true).timeout.connect(root.queue_free)


func _aim_target_spotlight(target_position: Vector3) -> void:
	if _target_spotlight == null:
		return
	_target_spotlight.global_position = target_position + Vector3(0.0, 4.4, 2.2)
	_target_spotlight.look_at(target_position + Vector3.UP * 1.05, Vector3.UP)
	_target_spotlight.light_energy = 6.4


func _set_actor_start(actor_id: String, position: Vector3) -> void:
	var actor := _actors.get(actor_id) as Node3D
	if actor == null:
		return
	actor.position = position
	actor.rotation = Vector3.ZERO


func _cleanup_combat_pops() -> void:
	super._cleanup_combat_pops()
	if _stage == null:
		return
	for child in _stage.get_children():
		if child.name == "CinematicSilentPop":
			child.queue_free()


func _show_title_immediately() -> void:
	if _rock_player != null:
		_rock_player.stop()
	super._show_title_immediately()

