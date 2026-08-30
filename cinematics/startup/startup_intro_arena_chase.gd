extends "res://cinematics/startup/startup_intro_preview_smooth_shot.gd"

## Standalone, deliberately unlinked startup concept.
##
## Six cats race for the one gun in a full-size presentation arena. Blue wins
## the pickup, drops the closest contender, catches a second cat reaching for a
## frying pan, then survives three staggered melee charges. The final shot is
## aimed directly through the lens and becomes the official logo.

const ROCK_CUE = preload("res://audio/ui/startup_arena_chase_rock.wav")

const FIXED_ROCK_VOLUME_DB := -11.5
const ACTOR_FLOOR_Y := 0.23
const ACTOR_IDS: Array[String] = [
	"blue", "orange", "pink", "green", "yellow", "purple",
]
const SURVIVOR_IDS: Array[String] = ["green", "orange", "pink", "yellow"]
const MELEE_ATTACKERS: Array[String] = ["orange", "pink", "yellow"]

const START_POSITIONS := {
	"blue": Vector3(0.0, ACTOR_FLOOR_Y, 6.15),
	"purple": Vector3(-3.45, ACTOR_FLOOR_Y, 5.25),
	"green": Vector3(-6.50, ACTOR_FLOOR_Y, 2.40),
	"orange": Vector3(-6.25, ACTOR_FLOOR_Y, -2.65),
	"pink": Vector3(6.25, ACTOR_FLOOR_Y, -2.65),
	"yellow": Vector3(6.50, ACTOR_FLOOR_Y, 2.40),
}

const RACE_POSITIONS := {
	"blue": Vector3(0.15, ACTOR_FLOOR_Y, 0.82),
	"purple": Vector3(-1.28, ACTOR_FLOOR_Y, -0.08),
	"green": Vector3(-2.12, ACTOR_FLOOR_Y, 0.72),
	"orange": Vector3(-1.72, ACTOR_FLOOR_Y, 1.40),
	"pink": Vector3(1.72, ACTOR_FLOOR_Y, 1.40),
	"yellow": Vector3(2.12, ACTOR_FLOOR_Y, 0.72),
}

const WEAPON_LAYOUT := {
	"green": {
		"label": "Frying Pan",
		"scene": "res://frying_pan.tscn",
		"position": Vector3(-5.75, 0.34, 2.10),
		"floor_rotation": Vector3(0.08, -0.62, 1.48),
		"raw_length": 2.82463,
		"grip": Vector3(0.0, 0.0, -0.471),
		"accent": Color(0.22, 0.92, 0.32),
	},
	"orange": {
		"label": "Baseball Bat",
		"scene": "res://baseball_bat.tscn",
		"position": Vector3(-5.85, 0.34, -2.70),
		"floor_rotation": Vector3(0.10, 0.78, 1.46),
		"raw_length": 1.0,
		"grip": Vector3(0.0, -0.243, 0.5),
		"accent": Color(1.0, 0.45, 0.08),
	},
	"pink": {
		"label": "Crowbar",
		"scene": "res://crowbar.tscn",
		"position": Vector3(5.85, 0.34, -2.70),
		"floor_rotation": Vector3(0.05, -0.82, 1.50),
		"raw_length": 11.9776,
		"grip": Vector3(0.0, -5.791, -0.276),
		"accent": Color(1.0, 0.25, 0.62),
	},
	"yellow": {
		"label": "Stick",
		"scene": "res://stick.tscn",
		"position": Vector3(5.75, 0.34, 2.10),
		"floor_rotation": Vector3(0.08, 0.64, 1.48),
		"raw_length": 0.465133,
		"grip": Vector3(0.018, 0.0, -0.168),
		"accent": Color(1.0, 0.82, 0.10),
	},
}

const DUELS: Array[Dictionary] = [
	{
		"id": "orange",
		"blue_start": Vector3(0.25, ACTOR_FLOOR_Y, 0.55),
		"blue_end": Vector3(1.30, ACTOR_FLOOR_Y, 0.84),
		"attacker_start": Vector3(-3.85, ACTOR_FLOOR_Y, 0.52),
		"attacker_end": Vector3(-0.55, ACTOR_FLOOR_Y, 0.55),
		"camera": Vector3(0.58, 2.18, 6.38),
		"target": Vector3(-1.08, 1.12, 0.55),
		"blue_animation": "pistol_strafe_right",
		"pitch": 0.96,
	},
	{
		"id": "pink",
		"blue_start": Vector3(-0.12, ACTOR_FLOOR_Y, 0.16),
		"blue_end": Vector3(-1.20, ACTOR_FLOOR_Y, 1.02),
		"attacker_start": Vector3(3.70, ACTOR_FLOOR_Y, -0.25),
		"attacker_end": Vector3(0.72, ACTOR_FLOOR_Y, -0.05),
		"camera": Vector3(-0.62, 2.24, 6.20),
		"target": Vector3(1.05, 1.12, 0.12),
		"blue_animation": "pistol_backward",
		"pitch": 1.02,
	},
	{
		"id": "yellow",
		"blue_start": Vector3(0.05, ACTOR_FLOOR_Y, 0.90),
		"blue_end": Vector3(-1.20, ACTOR_FLOOR_Y, 1.16),
		"attacker_start": Vector3(0.08, ACTOR_FLOOR_Y, -4.05),
		"attacker_end": Vector3(0.05, ACTOR_FLOOR_Y, -0.58),
		"camera": Vector3(5.75, 2.38, 5.75),
		"target": Vector3(-0.02, 1.08, -0.62),
		"blue_animation": "pistol_strafe_left",
		"pitch": 0.91,
	},
]

var _animation_players: Dictionary = {}
var _melee_sockets: Dictionary = {}
var _weapon_rigs: Dictionary = {}
var _target_spotlight: SpotLight3D = null
var _rock_player: AudioStreamPlayer = null


func _build_interface() -> void:
	super._build_interface()
	var canvas := get_node_or_null("CinematicInterface") as CanvasLayer
	if canvas == null:
		return
	var top_bar := ColorRect.new()
	top_bar.name = "TopLetterbox"
	top_bar.color = Color(0.0, 0.0, 0.0, 0.94)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.anchor_right = 1.0
	top_bar.anchor_bottom = 0.055
	canvas.add_child(top_bar)
	canvas.move_child(top_bar, 0)
	var bottom_bar := ColorRect.new()
	bottom_bar.name = "BottomLetterbox"
	bottom_bar.color = Color(0.0, 0.0, 0.0, 0.94)
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bar.anchor_top = 0.93
	bottom_bar.anchor_right = 1.0
	bottom_bar.anchor_bottom = 1.0
	canvas.add_child(bottom_bar)
	canvas.move_child(bottom_bar, 1)
	_preview_controls.anchor_top = 0.952
	_preview_controls.anchor_bottom = 0.990


func _build_stage() -> void:
	_stage = Node3D.new()
	_stage.name = "ArenaChaseStage"
	add_child(_stage)

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.002, 0.005, 0.014)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.12, 0.19, 0.34)
	environment.ambient_light_energy = 0.38
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	_stage.add_child(world_environment)

	_add_box_mesh("ArenaFloor", Vector3(22.0, 0.24, 16.0),
		Vector3(0.0, 0.12, 0.0), FLOOR_COLOR, 0.68, 0.28,
		Color(0.003, 0.012, 0.040), 0.54)
	_add_box_mesh("BackApron", Vector3(22.0, 0.10, 3.4),
		Vector3(0.0, 0.08, -9.65), Color(0.008, 0.015, 0.032), 0.40, 0.42)
	_add_box_mesh("FrontApron", Vector3(22.0, 0.10, 2.4),
		Vector3(0.0, 0.08, 9.10), Color(0.008, 0.015, 0.032), 0.40, 0.42)

	# A thin inlaid center mark keeps the gun spatially legible without putting
	# the action on another small pedestal.
	_add_disc("CenterInlay", Vector3.ZERO, 1.52,
		Color(0.13, 0.050, 0.008), Color(0.72, 0.20, 0.015), 0.82)
	for actor_id in WEAPON_LAYOUT:
		var data := WEAPON_LAYOUT[actor_id] as Dictionary
		var weapon_position := data["position"] as Vector3
		var accent := data["accent"] as Color
		_add_disc("%sWeaponPool" % actor_id.capitalize(), weapon_position,
			0.92, Color(accent, 0.05), accent.darkened(0.22), 0.66)
		_add_lane_strip("%sLane" % actor_id.capitalize(),
			Vector3.ZERO, weapon_position, accent.darkened(0.22))

	# Low emissive rails and tall light fins sell the size of the arena while
	# remaining cheap enough for the lower-spec Forward+ target.
	_add_box_mesh("LeftRail", Vector3(0.11, 0.08, 15.7),
		Vector3(-10.75, 0.31, 0.0), Color(0.05, 0.19, 0.52), 0.15, 0.32,
		Color(0.05, 0.30, 1.0), 2.1)
	_add_box_mesh("RightRail", Vector3(0.11, 0.08, 15.7),
		Vector3(10.75, 0.31, 0.0), Color(0.52, 0.18, 0.035), 0.15, 0.32,
		Color(1.0, 0.32, 0.04), 2.1)
	_add_box_mesh("BackRail", Vector3(21.4, 0.08, 0.11),
		Vector3(0.0, 0.31, -7.70), Color(0.31, 0.18, 0.04), 0.15, 0.32,
		Color(1.0, 0.48, 0.06), 1.7)
	for side in [-1.0, 1.0]:
		for z_value in [-6.4, -2.2, 2.2, 6.4]:
			var fin_color := Color(0.06, 0.34, 1.0) if side < 0.0 \
				else Color(1.0, 0.30, 0.045)
			_add_box_mesh("ArenaFin", Vector3(0.14, 3.7, 0.22),
				Vector3(side * 10.55, 2.05, z_value), Color(fin_color, 0.12),
				0.10, 0.34, fin_color, 1.85)

	_gun_pivot = Node3D.new()
	_gun_pivot.name = "CenterGunDisplay"
	_gun_pivot.position = Vector3(0.0, 1.30, 0.0)
	_stage.add_child(_gun_pivot)
	_gun_visual = GUN_SCENE.instantiate() as Node3D
	_gun_visual.name = "TheOneGun"
	_gun_visual.scale = Vector3.ONE * DISPLAY_GUN_SCALE
	_gun_visual.rotation_degrees = DISPLAY_GUN_ROTATION_DEGREES
	_gun_pivot.add_child(_gun_visual)

	var warm_key := DirectionalLight3D.new()
	warm_key.name = "WarmKey"
	warm_key.rotation_degrees = Vector3(-50.0, -32.0, 0.0)
	warm_key.light_color = Color(1.0, 0.75, 0.48)
	warm_key.light_energy = 1.38
	warm_key.shadow_enabled = true
	_stage.add_child(warm_key)

	var cool_rim := DirectionalLight3D.new()
	cool_rim.name = "CoolRim"
	cool_rim.rotation_degrees = Vector3(-36.0, 148.0, 0.0)
	cool_rim.light_color = Color(0.13, 0.38, 1.0)
	cool_rim.light_energy = 0.92
	cool_rim.shadow_enabled = false
	_stage.add_child(cool_rim)

	var gun_spot := SpotLight3D.new()
	gun_spot.name = "CenterGunSpot"
	gun_spot.position = Vector3(0.0, 7.8, 1.6)
	gun_spot.light_color = Color(1.0, 0.60, 0.17)
	gun_spot.light_energy = 7.0
	gun_spot.spot_range = 13.0
	gun_spot.spot_angle = 24.0
	gun_spot.shadow_enabled = false
	_stage.add_child(gun_spot)
	gun_spot.look_at(Vector3(0.0, 0.25, 0.0), Vector3.UP)

	for actor_id in WEAPON_LAYOUT:
		var light_data := WEAPON_LAYOUT[actor_id] as Dictionary
		var weapon_spot := SpotLight3D.new()
		weapon_spot.name = "%sWeaponSpot" % actor_id.capitalize()
		var pad_position := light_data["position"] as Vector3
		weapon_spot.position = pad_position + Vector3(0.0, 4.8, 1.3)
		weapon_spot.light_color = light_data["accent"] as Color
		weapon_spot.light_energy = 2.7
		weapon_spot.spot_range = 8.0
		weapon_spot.spot_angle = 27.0
		weapon_spot.shadow_enabled = false
		_stage.add_child(weapon_spot)
		weapon_spot.look_at(pad_position, Vector3.UP)

	_blue_spotlight = SpotLight3D.new()
	_blue_spotlight.name = "BlueHeroSpot"
	_blue_spotlight.position = Vector3(0.0, 7.0, 3.0)
	_blue_spotlight.light_color = Color(0.35, 0.62, 1.0)
	_blue_spotlight.light_energy = 0.0
	_blue_spotlight.spot_range = 12.0
	_blue_spotlight.spot_angle = 24.0
	_blue_spotlight.shadow_enabled = false
	_stage.add_child(_blue_spotlight)
	_blue_spotlight.look_at(Vector3(0.0, 0.9, 0.4), Vector3.UP)

	_target_spotlight = SpotLight3D.new()
	_target_spotlight.name = "ActionSpot"
	_target_spotlight.light_color = Color(1.0, 0.75, 0.46)
	_target_spotlight.light_energy = 0.0
	_target_spotlight.spot_range = 10.0
	_target_spotlight.spot_angle = 29.0
	_target_spotlight.shadow_enabled = false
	_stage.add_child(_target_spotlight)

	_camera = Camera3D.new()
	_camera.name = "CinematicCamera"
	_camera.fov = 46.0
	_camera.transform = _camera_transform(
		Vector3(0.0, 7.65, 13.70), Vector3(0.0, 0.78, 0.15))
	_stage.add_child(_camera)
	_camera.current = true

	_rock_player = AudioStreamPlayer.new()
	_rock_player.name = "FixedVolumeArenaRock"
	_rock_player.stream = ROCK_CUE
	# Intentionally bypass the Music bus. The cue has one authored, conservative
	# level and still obeys the user's Master/OS mute controls.
	_rock_player.bus = &"Master"
	_rock_player.volume_db = FIXED_ROCK_VOLUME_DB
	add_child(_rock_player)


func _build_actors() -> void:
	var visual_scene := SkinRegistry.load_visual_scene("male")
	if visual_scene == null:
		push_error("Arena chase preview could not load the male cat visual.")
		return
	for configuration in ACTOR_LAYOUT:
		var actor_id := str(configuration["id"])
		var anchor := Node3D.new()
		anchor.name = "%sCat" % actor_id.capitalize()
		anchor.position = START_POSITIONS[actor_id] as Vector3
		anchor.visible = false
		_stage.add_child(anchor)

		var visual := visual_scene.instantiate() as Node3D
		visual.name = "CharacterModel"
		visual.set("model_id", "male")
		visual.set("skin_id", actor_id)
		visual.set("build_animation_library", false)
		anchor.add_child(visual)
		await get_tree().process_frame

		var requested: Array = ["idle", "standard_run", "hit"]
		if actor_id == "blue":
			requested.append_array([
				"pistol_run", "pistol_backward",
				"pistol_strafe_left", "pistol_strafe_right",
			])
		elif actor_id == "green":
			requested.append("melee")
		elif actor_id in MELEE_ATTACKERS:
			requested.append_array(["run_with_sword", "melee"])
		var animation_player := visual.call(
			"ensure_animations", requested) as AnimationPlayer
		_animation_players[actor_id] = animation_player
		_melee_sockets[actor_id] = visual.find_child(
			"MeleeHoldPoint", true, false) as Node3D
		if actor_id == "blue":
			_blue_animation_player = animation_player
			_blue_gun_socket = visual.find_child(
				"GunHoldPoint", true, false) as Node3D
		_actors[actor_id] = anchor
		_actor_configuration[actor_id] = configuration

	_build_weapon_rigs()


func _build_weapon_rigs() -> void:
	for actor_id in WEAPON_LAYOUT:
		var data := WEAPON_LAYOUT[actor_id] as Dictionary
		var packed := load(str(data["scene"])) as PackedScene
		if packed == null:
			push_warning("Arena chase preview could not load %s." % data["label"])
			continue
		var holder := Node3D.new()
		holder.name = "%sPresentationRig" % str(data["label"]).replace(" ", "")
		_stage.add_child(holder)
		var visual := packed.instantiate() as Node3D
		visual.name = "Model"
		holder.add_child(visual)
		var held_scale := 1.0 / maxf(float(data["raw_length"]), 0.001)
		visual.scale = Vector3.ONE * held_scale
		visual.position = -(visual.basis * (data["grip"] as Vector3))
		for area_node in visual.find_children("*", "Area3D", true, false):
			var area := area_node as Area3D
			area.monitoring = false
			area.monitorable = false
		_weapon_rigs[actor_id] = holder


func _reset_presentation() -> void:
	super._reset_presentation()
	for actor_id in ACTOR_IDS:
		var actor := _actors.get(actor_id) as Node3D
		if actor == null:
			continue
		actor.position = START_POSITIONS[actor_id] as Vector3
		actor.rotation = Vector3.ZERO
		actor.scale = Vector3.ONE
		actor.visible = false
		_face_actor_toward(actor, Vector3.ZERO)
		_reset_animation(actor_id)
	_reset_weapon_rigs()
	_phrase.text = ""
	_phrase.modulate.a = 0.0
	_logo.visible = true
	_logo.modulate.a = 0.0
	_prompt.visible = false
	_screen_fade.color = Color(BACKGROUND_COLOR, 1.0)
	_flash.color.a = 0.0
	_camera.fov = 46.0
	_camera.transform = _camera_transform(
		Vector3(0.0, 7.65, 13.70), Vector3(0.0, 0.78, 0.15))
	_gun_pivot.position = Vector3(0.0, 1.30, 0.0)
	_gun_pivot.rotation = Vector3.ZERO
	_blue_spotlight.light_energy = 0.0
	_target_spotlight.light_energy = 0.0
	if _rock_player != null:
		_rock_player.stop()
		_rock_player.volume_db = FIXED_ROCK_VOLUME_DB


func _run_sequence(generation: int) -> void:
	if not await _wait_for(0.35, generation):
		return
	_stage.visible = true
	_gun_pivot.visible = true
	if _rock_player != null:
		_rock_player.volume_db = FIXED_ROCK_VOLUME_DB
		_rock_player.play()
	for actor_id in ACTOR_IDS:
		_reveal_actor(actor_id)
		_face_actor_toward(_actors[actor_id] as Node3D, Vector3.ZERO)
		_play_animation(actor_id, "standard_run", 1.04, 0.08)
		_tween_property(_actors[actor_id], "position", RACE_POSITIONS[actor_id],
			_motion_time(1.45), Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	_tween_property(_screen_fade, "color:a", 0.0, 0.54,
		Tween.TRANS_QUAD, Tween.EASE_OUT)
	_tween_property(_camera, "transform", _camera_transform(
		Vector3(0.0, 5.45, 10.75), Vector3(0.0, 0.92, 0.18)),
		_motion_time(1.46), Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	_tween_property(_gun_pivot, "rotation:y", PI * 0.82,
		_motion_time(1.45), Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	if not await _wait_for(1.47, generation):
		return

	if not await _blue_claims_center_gun(generation):
		return
	if not await _shoot_first_contender(generation):
		return
	if not await _survivors_break_for_weapons(generation):
		return
	if not await _shoot_pan_reach(generation):
		return
	if not await _three_attackers_return(generation):
		return
	for duel in DUELS:
		if not await _play_duel(duel, generation):
			return
		if not await _wait_for(0.10, generation):
			return
	await _blue_finishes_to_camera(generation)


func _blue_claims_center_gun(generation: int) -> bool:
	var blue := _actors.get("blue") as Node3D
	if blue == null or _blue_gun_socket == null or _gun_visual == null:
		return false
	for actor_id in ACTOR_IDS:
		_pause_animation(actor_id)
	_soft_camera_cut()
	_camera.fov = 39.0
	_camera.transform = _camera_transform(
		Vector3(3.85, 2.32, 5.18), Vector3(-0.10, 1.16, 0.42))
	_play_animation("blue", "pistol_run", 0.92, 0.16)
	_gun_visual.reparent(_blue_gun_socket, true)
	_gun_pivot.visible = false
	var gun_move := create_tween()
	gun_move.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	gun_move.set_parallel(true)
	gun_move.tween_property(_gun_visual, "position", gun_grip_offset,
		_motion_time(0.54)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	gun_move.tween_property(_gun_visual, "rotation_degrees",
		gun_grip_rotation_degrees, _motion_time(0.54)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	gun_move.tween_property(_gun_visual, "scale", Vector3.ONE * final_gun_scale,
		_motion_time(0.54)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_active_tweens.append(gun_move)
	_tween_property(_blue_spotlight, "light_energy", 3.8, 0.34,
		Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	if not await _wait_for(0.56, generation):
		return false
	_pause_animation("blue")
	return true


func _shoot_first_contender(generation: int) -> bool:
	var blue := _actors.get("blue") as Node3D
	var purple := _actors.get("purple") as Node3D
	if blue == null or purple == null:
		return false
	_camera.fov = 38.0
	_camera.transform = _camera_transform(
		Vector3(3.05, 2.14, 5.10), Vector3(-0.48, 1.12, 0.30))
	_aim_action_spot(purple.global_position, Color(0.72, 0.42, 1.0))
	_face_actor_toward(blue, purple.position)
	_play_animation("blue", "pistol_run", 0.88, 0.12)
	if not await _wait_for(0.16, generation):
		return false
	_pause_animation("blue")
	return await _shoot_actor("purple", 0.95, 0.30, generation)


func _survivors_break_for_weapons(generation: int) -> bool:
	_soft_camera_cut()
	_show_only(["blue", "green", "orange", "pink", "yellow"])
	_camera.fov = 47.0
	_camera.transform = _camera_transform(
		Vector3(0.0, 6.25, 11.35), Vector3(0.0, 0.72, 0.0))
	for actor_id in SURVIVOR_IDS:
		var actor := _actors.get(actor_id) as Node3D
		var destination := (WEAPON_LAYOUT[actor_id] as Dictionary)["position"] as Vector3
		destination.y = ACTOR_FLOOR_Y
		_face_actor_toward(actor, destination)
		_play_animation(actor_id, "standard_run", 1.16, 0.08)
		_tween_property(actor, "position", destination, _motion_time(1.24),
			Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	_face_actor_toward(_actors["blue"] as Node3D, Vector3(-4.0, ACTOR_FLOOR_Y, 1.4))
	if not await _wait_for(0.86, generation):
		return false
	for actor_id in MELEE_ATTACKERS:
		_attach_melee_weapon(actor_id)
		_play_animation(actor_id, "run_with_sword", 1.05, 0.10)
	return await _wait_for(0.40, generation)


func _shoot_pan_reach(generation: int) -> bool:
	var blue := _actors.get("blue") as Node3D
	var green := _actors.get("green") as Node3D
	if blue == null or green == null:
		return false
	_show_only(["blue", "green"])
	_face_actor_toward(green,
		(WEAPON_LAYOUT["green"] as Dictionary)["position"] as Vector3)
	_play_animation("green", "melee", 0.78, 0.12)
	_soft_camera_cut()
	_camera.fov = 39.0
	_camera.transform = _camera_transform(
		Vector3(-0.10, 2.75, 8.35), Vector3(-2.65, 1.02, 1.24))
	_aim_action_spot(green.global_position, Color(0.30, 1.0, 0.42))
	if not await _wait_for(0.26, generation):
		return false
	_pause_animation("green")
	_face_actor_toward(blue, green.position)
	_play_animation("blue", "pistol_run", 0.90, 0.12)
	if not await _wait_for(0.15, generation):
		return false
	_pause_animation("blue")
	return await _shoot_actor("green", 1.01, 0.32, generation)


func _three_attackers_return(generation: int) -> bool:
	_soft_camera_cut()
	_show_only(["blue", "orange", "pink", "yellow"])
	var blue := _actors.get("blue") as Node3D
	blue.position = Vector3(-0.10, ACTOR_FLOOR_Y, 0.62)
	blue.rotation = Vector3.ZERO
	_play_animation("blue", "pistol_run", 0.88, 0.10)
	var staging := {
		"orange": Vector3(-3.55, ACTOR_FLOOR_Y, 0.62),
		"pink": Vector3(3.45, ACTOR_FLOOR_Y, -0.25),
		"yellow": Vector3(0.10, ACTOR_FLOOR_Y, -3.62),
	}
	for actor_id in MELEE_ATTACKERS:
		var actor := _actors.get(actor_id) as Node3D
		_face_actor_toward(actor, blue.position)
		_play_animation(actor_id, "run_with_sword", 1.13, 0.08)
		_tween_property(actor, "position", staging[actor_id], _motion_time(1.04),
			Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	_camera.fov = 46.0
	_camera.transform = _camera_transform(
		Vector3(0.0, 6.05, 10.15), Vector3(0.0, 0.88, -0.12))
	if not await _wait_for(1.06, generation):
		return false
	_pause_animation("blue")
	for actor_id in MELEE_ATTACKERS:
		_pause_animation(actor_id)
	return await _wait_for(0.14, generation)


func _play_duel(duel: Dictionary, generation: int) -> bool:
	var actor_id := str(duel["id"])
	var blue := _actors.get("blue") as Node3D
	var attacker := _actors.get(actor_id) as Node3D
	if blue == null or attacker == null:
		return false
	_show_only(["blue", actor_id])
	blue.position = duel["blue_start"] as Vector3
	blue.rotation = Vector3.ZERO
	attacker.position = duel["attacker_start"] as Vector3
	attacker.rotation = Vector3.ZERO
	var weapon := _weapon_rigs.get(actor_id) as Node3D
	if weapon != null:
		weapon.visible = true
	_face_actor_toward(blue, attacker.position)
	_face_actor_toward(attacker, blue.position)
	_soft_camera_cut()
	_camera.fov = 38.0
	_camera.transform = _camera_transform(
		duel["camera"] as Vector3, duel["target"] as Vector3)
	_aim_action_spot(attacker.global_position,
		(WEAPON_LAYOUT[actor_id] as Dictionary)["accent"] as Color)
	_play_animation("blue", str(duel["blue_animation"]), 1.05, 0.08)
	_play_animation(actor_id, "melee", 1.14, 0.08)
	_tween_property(blue, "position", duel["blue_end"], _motion_time(0.62),
		Tween.TRANS_CUBIC, Tween.EASE_OUT)
	_tween_property(attacker, "position", duel["attacker_end"],
		_motion_time(0.62), Tween.TRANS_CUBIC, Tween.EASE_IN)
	if not await _wait_for(0.52, generation):
		return false
	_pause_animation(actor_id)
	_face_actor_toward(blue, attacker.position)
	_play_animation("blue", "pistol_run", 0.92, 0.08)
	if not await _wait_for(0.12, generation):
		return false
	_pause_animation("blue")
	return await _shoot_actor(actor_id, float(duel["pitch"]), 0.30, generation)


func _blue_finishes_to_camera(generation: int) -> void:
	var blue := _actors.get("blue") as Node3D
	if blue == null:
		await _transition_to_title(generation)
		return
	_show_only(["blue"])
	_target_spotlight.light_energy = 0.0
	blue.rotation = Vector3.ZERO
	blue.scale = Vector3.ONE * 1.12
	_play_animation("blue", "pistol_run", 0.84, 0.14)
	_tween_property(blue, "position", Vector3(0.0, ACTOR_FLOOR_Y, 0.44),
		_motion_time(0.72), Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	_tween_property(_blue_spotlight, "light_energy", 7.4, 0.42,
		Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	_camera.fov = 39.0
	_tween_property(_camera, "transform", _camera_transform(
		final_camera_position, final_camera_target), _motion_time(0.72),
		Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	if not await _wait_for(0.74, generation):
		return
	_pause_animation("blue")
	if not await _wait_for(0.28, generation):
		return
	await _fire_continuous_final_shot(blue, generation)


func _fire_continuous_final_shot(blue: Node3D, generation: int) -> void:
	if _rock_player != null:
		_tween_property(_rock_player, "volume_db", -34.0, 0.72,
			Tween.TRANS_QUAD, Tween.EASE_IN)
	await super._fire_continuous_final_shot(blue, generation)
	if _rock_player != null and generation == _sequence_generation:
		_rock_player.stop()


func _shoot_actor(actor_id: String, pitch: float, hold: float,
		generation: int) -> bool:
	var target := _actors.get(actor_id) as Node3D
	if target == null:
		return false
	AudioManager.play_sfx("gun_shot", 0.94, pitch)
	_fire_action_flash()
	if not _reduced_motion and _gun_visual != null:
		var recoil := create_tween()
		recoil.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		recoil.tween_property(_gun_visual, "position",
			gun_grip_offset + Vector3(0.0, 0.012, -0.075), 0.050) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		recoil.tween_property(_gun_visual, "position", gun_grip_offset, 0.105) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_active_tweens.append(recoil)
	_play_animation(actor_id, "hit", 1.08, 0.04)
	_spawn_silent_confetti(target.global_position,
		(_actor_configuration.get(actor_id, {}) as Dictionary).get(
			"accent", GOLD) as Color)
	if not await _wait_for(0.055, generation):
		return false
	target.visible = false
	var target_weapon := _weapon_rigs.get(actor_id) as Node3D
	if target_weapon != null and actor_id != "green":
		target_weapon.visible = false
	return await _wait_for(hold, generation)


func _attach_melee_weapon(actor_id: String) -> void:
	var weapon := _weapon_rigs.get(actor_id) as Node3D
	var socket := _melee_sockets.get(actor_id) as Node3D
	if weapon == null or socket == null:
		return
	weapon.reparent(socket, false)
	weapon.position = Vector3.ZERO
	weapon.rotation = Vector3(-PI / 2.0, PI, 0.0)
	weapon.scale = Vector3.ONE
	weapon.visible = true


func _reset_weapon_rigs() -> void:
	for actor_id in _weapon_rigs:
		var weapon := _weapon_rigs[actor_id] as Node3D
		if weapon == null:
			continue
		if weapon.get_parent() != _stage:
			weapon.reparent(_stage, false)
		var data := WEAPON_LAYOUT[actor_id] as Dictionary
		weapon.position = data["position"] as Vector3
		weapon.rotation = data["floor_rotation"] as Vector3
		weapon.scale = Vector3.ONE
		weapon.visible = true


func _reset_animation(actor_id: String) -> void:
	var player := _animation_players.get(actor_id) as AnimationPlayer
	if player == null or not player.has_animation("idle"):
		return
	player.speed_scale = 0.24
	player.play("idle", 0.0)
	var idle := player.get_animation("idle")
	var pose := float((_actor_configuration.get(actor_id, {}) as Dictionary).get(
		"pose", 0.0))
	player.seek(idle.length * pose, true)
	player.advance(0.0)


func _play_animation(actor_id: String, animation_name: String,
		speed: float, blend: float) -> void:
	var player := _animation_players.get(actor_id) as AnimationPlayer
	if player == null or not player.has_animation(animation_name):
		return
	player.speed_scale = speed
	player.play(animation_name, blend)


func _pause_animation(actor_id: String) -> void:
	var player := _animation_players.get(actor_id) as AnimationPlayer
	if player == null:
		return
	player.pause()
	player.advance(0.0)


func _face_actor_toward(actor: Node3D, target: Vector3) -> void:
	if actor == null:
		return
	var direction := target - actor.position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	actor.rotation = Vector3(0.0, atan2(direction.x, direction.z), 0.0)


func _show_only(actor_ids: Array) -> void:
	for actor_id in ACTOR_IDS:
		var actor := _actors.get(actor_id) as Node3D
		if actor != null:
			actor.visible = actor_id in actor_ids
	for weapon_owner in _weapon_rigs:
		if weapon_owner == "green":
			(_weapon_rigs[weapon_owner] as Node3D).visible = true
		elif weapon_owner in MELEE_ATTACKERS:
			(_weapon_rigs[weapon_owner] as Node3D).visible = weapon_owner in actor_ids


func _aim_action_spot(world_position: Vector3, color: Color) -> void:
	if _target_spotlight == null:
		return
	_target_spotlight.global_position = world_position + Vector3(0.0, 4.8, 2.1)
	_target_spotlight.light_color = color
	_target_spotlight.light_energy = 5.6
	_target_spotlight.look_at(world_position + Vector3.UP * 1.0, Vector3.UP)


func _soft_camera_cut() -> void:
	var alpha := 0.095 if AccessibilityManager.allow_flash() else 0.025
	_flash.color = Color(0.68, 0.78, 1.0, alpha)
	_tween_property(_flash, "color:a", 0.0, 0.09,
		Tween.TRANS_QUAD, Tween.EASE_OUT)


func _fire_action_flash() -> void:
	var alpha := 0.22 if AccessibilityManager.allow_flash() else 0.04
	_flash.color = Color(1.0, 0.82, 0.48, alpha)
	_tween_property(_flash, "color:a", 0.0, 0.12,
		Tween.TRANS_QUAD, Tween.EASE_OUT)


func _spawn_silent_confetti(world_position: Vector3, accent: Color) -> void:
	var root := Node3D.new()
	root.name = "CinematicSilentPop"
	_stage.add_child(root)
	root.global_position = world_position + Vector3.UP * 1.08
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.amount = 58 if not _reduced_motion else 30
	particles.lifetime = 1.45
	particles.explosiveness = 1.0
	var confetti := BoxMesh.new()
	confetti.size = Vector3(0.052, 0.18, 0.018)
	var confetti_material := StandardMaterial3D.new()
	confetti_material.vertex_color_use_as_albedo = true
	confetti_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	confetti_material.emission_enabled = AccessibilityManager.allow_flash()
	confetti_material.emission = Color(0.34, 0.34, 0.34)
	confetti_material.emission_energy_multiplier = 0.28
	confetti.material = confetti_material
	particles.draw_pass_1 = confetti
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 66.0
	process.initial_velocity_min = 3.8
	process.initial_velocity_max = 6.9
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
	root.get_tree().create_timer(1.78, true, false, true).timeout.connect(root.queue_free)


func _add_box_mesh(node_name: String, size: Vector3, position_value: Vector3,
		color: Color, metallic: float, roughness: float,
		emission := Color.TRANSPARENT, emission_energy := 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = _make_material(
		color, metallic, roughness, emission, emission_energy)
	_stage.add_child(instance)
	return instance


func _add_disc(node_name: String, position_value: Vector3, radius: float,
		color: Color, emission: Color, emission_energy: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.02
	mesh.height = 0.028
	mesh.radial_segments = 48
	instance.mesh = mesh
	instance.position = Vector3(position_value.x, 0.255, position_value.z)
	instance.material_override = _make_material(
		color, 0.62, 0.30, emission, emission_energy)
	_stage.add_child(instance)
	return instance


func _add_lane_strip(node_name: String, from: Vector3, to: Vector3,
		emission: Color) -> void:
	var direction := to - from
	direction.y = 0.0
	var strip := _add_box_mesh(node_name,
		Vector3(0.075, 0.018, direction.length()),
		(from + to) * 0.5 + Vector3(0.0, 0.255, 0.0),
		Color(emission, 0.16), 0.18, 0.32, emission, 1.18)
	strip.rotation.y = atan2(direction.x, direction.z)


func _make_material(color: Color, metallic: float, roughness: float,
		emission: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material


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

