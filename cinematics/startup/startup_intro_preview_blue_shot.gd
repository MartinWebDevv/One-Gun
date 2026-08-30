extends "res://cinematics/startup/startup_intro_preview.gd"

## Standalone revision of the startup blockout. It inherits the original scene
## and replaces only the final beat: Blue takes the display gun into the shared
## animated hand socket, aims toward center camera, and fires into the logo.

var _blue_animation_player: AnimationPlayer = null
var _blue_gun_socket: Node3D = null
var _held_gun_visual: Node3D = null


func _build_actors() -> void:
	var visual_scene := SkinRegistry.load_visual_scene("male")
	if visual_scene == null:
		push_error("Startup intro preview could not load the male cat visual.")
		return
	for configuration in ACTOR_LAYOUT:
		var actor_id := str(configuration["id"])
		var anchor := Node3D.new()
		anchor.name = "%sCat" % actor_id.capitalize()
		anchor.position = configuration["position"]
		anchor.rotation_degrees.y = float(configuration["yaw"])
		anchor.visible = false
		_stage.add_child(anchor)

		var visual := visual_scene.instantiate() as Node3D
		visual.name = "CharacterModel"
		visual.set("model_id", "male")
		visual.set("skin_id", actor_id)
		visual.set("build_animation_library", false)
		anchor.add_child(visual)
		await get_tree().process_frame

		var requested_animations := ["idle", "pistol_run"] \
			if actor_id == "blue" else ["idle"]
		var animation_player := visual.call(
			"ensure_animations", requested_animations) as AnimationPlayer
		if animation_player != null and animation_player.has_animation("idle"):
			animation_player.play("idle")
			var idle := animation_player.get_animation("idle")
			animation_player.seek(idle.length * float(configuration["pose"]), true)
			animation_player.speed_scale = 0.22
			animation_player.advance(0.0)
		_actors[actor_id] = anchor
		_actor_configuration[actor_id] = configuration

		if actor_id == "blue":
			_blue_animation_player = animation_player
			_blue_gun_socket = visual.find_child(
				"GunHoldPoint", true, false) as Node3D
			if _blue_gun_socket != null:
				_held_gun_visual = GUN_SCENE.instantiate() as Node3D
				_held_gun_visual.name = "HeldOneGun"
				# The production gun scene's root contributes the complementary
				# rotation when this GLB is used in gameplay. Attached directly to
				# the common hand marker, the visual uses this unrotated local pose.
				_held_gun_visual.scale = Vector3.ONE * 0.002
				_held_gun_visual.visible = false
				_blue_gun_socket.add_child(_held_gun_visual)


func _reset_presentation() -> void:
	super._reset_presentation()
	if _held_gun_visual != null:
		_held_gun_visual.visible = false
	if _blue_animation_player != null \
			and _blue_animation_player.has_animation("idle"):
		_blue_animation_player.speed_scale = 0.22
		_blue_animation_player.play("idle", 0.0)
		var idle := _blue_animation_player.get_animation("idle")
		_blue_animation_player.seek(idle.length * 0.12, true)
		_blue_animation_player.advance(0.0)


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

	var blue := _actors.get("blue") as Node3D
	if blue != null:
		_tween_property(blue, "position", Vector3(0.0, 0.23, 0.42), _motion_time(0.48))
		_tween_property(blue, "scale", Vector3.ONE * 1.12, _motion_time(0.48))
	_tween_property(_gun_pivot, "position", Vector3(-1.20, 1.14, 0.20), _motion_time(0.48))
	_tween_property(_blue_spotlight, "light_energy", 7.2, _motion_time(0.30))
	_tween_property(_camera, "transform", _camera_transform(
		Vector3(0.0, 2.45, 6.55), Vector3(0.0, 1.25, 0.25)), _motion_time(0.50))
	_show_phrase("LAST ONE\n[color=#ffad29]STANDING[/color]", 78)

	if not await _wait_for(0.82, generation):
		return
	await _blue_takes_and_fires(generation)


func _blue_takes_and_fires(generation: int) -> void:
	var blue := _actors.get("blue") as Node3D
	if blue == null or _blue_gun_socket == null or _held_gun_visual == null:
		await _transition_to_title(generation)
		return

	# Clear the rule text while the display gun crosses into Blue's animated
	# right-hand socket. The swap occurs only after both presentations meet.
	_tween_property(_phrase, "modulate:a", 0.0, 0.18)
	_tween_property(_camera, "transform", _camera_transform(
		Vector3(0.0, 2.18, 5.45), Vector3(0.0, 1.30, 0.34)),
		_motion_time(0.48))
	var socket_position := _stage.to_local(_blue_gun_socket.global_position)
	_tween_property(_gun_pivot, "position", socket_position, _motion_time(0.42))
	_tween_property(_gun_pivot, "rotation:y", PI * 1.78, _motion_time(0.42))
	if not await _wait_for(0.44, generation):
		return

	_gun_pivot.visible = false
	_held_gun_visual.visible = true
	if _blue_animation_player != null \
			and _blue_animation_player.has_animation("pistol_run"):
		_blue_animation_player.speed_scale = 0.72
		_blue_animation_player.play("pistol_run", 0.16)
		if not await _wait_for(0.34, generation):
			return
		_blue_animation_player.pause()
		_blue_animation_player.advance(0.0)

	# Center the held gun before the final shot.
	_tween_property(_camera, "transform", _camera_transform(
		Vector3(0.0, 1.92, 4.75), Vector3(0.0, 1.34, 0.42)),
		_motion_time(0.38))
	if not await _wait_for(0.46, generation):
		return
	await _fire_final_shot_to_title(blue, generation)


func _fire_final_shot_to_title(blue: Node3D, generation: int) -> void:
	AudioManager.play_sfx("gun_shot", 1.0, 0.94)
	if not _reduced_motion:
		_tween_property(blue, "rotation:x", deg_to_rad(-4.0), 0.06,
			Tween.TRANS_QUAD, Tween.EASE_OUT)
		var recoil := create_tween()
		recoil.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		recoil.tween_interval(0.065)
		recoil.tween_property(blue, "rotation:x", 0.0, 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_active_tweens.append(recoil)

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

