extends Node

## Standalone concept scene for the proposed One Gun startup sequence.
##
## This preview intentionally performs no scene change and is not referenced by
## project.godot or app_bootstrap.gd. Run this scene directly from the editor.

const SkinRegistry = preload("res://player_skin_registry.gd")
const CombatPopEffect = preload("res://combat_pop.gd")
const GUN_SCENE = preload("res://models/weaponModels/water_gun.glb")
const LOGO_TEXTURE = preload("res://UI/MainMenu/OneGunLogoV2.png")

const BACKGROUND_COLOR := Color(0.005, 0.009, 0.020)
const FLOOR_COLOR := Color(0.018, 0.030, 0.060)
const GOLD := Color(1.0, 0.68, 0.16)
const WARM_WHITE := Color(0.96, 0.95, 0.91)
const BLUE_ACCENT := Color(0.16, 0.56, 1.0)
const CAMERA_TARGET := Vector3(0.0, 1.20, 0.0)

const ACTOR_LAYOUT: Array[Dictionary] = [
	{
		"id": "blue",
		"position": Vector3(0.0, 0.23, -2.25),
		"yaw": 0.0,
		"pose": 0.12,
		"accent": Color(0.16, 0.56, 1.0),
	},
	{
		"id": "orange",
		"position": Vector3(-2.62, 0.23, -1.12),
		"yaw": -12.0,
		"pose": 0.24,
		"accent": Color(1.0, 0.45, 0.08),
	},
	{
		"id": "pink",
		"position": Vector3(2.62, 0.23, -1.12),
		"yaw": 12.0,
		"pose": 0.36,
		"accent": Color(1.0, 0.25, 0.62),
	},
	{
		"id": "green",
		"position": Vector3(-3.18, 0.23, 1.28),
		"yaw": -20.0,
		"pose": 0.48,
		"accent": Color(0.22, 0.92, 0.32),
	},
	{
		"id": "yellow",
		"position": Vector3(3.18, 0.23, 1.28),
		"yaw": 20.0,
		"pose": 0.60,
		"accent": Color(1.0, 0.82, 0.10),
	},
	{
		"id": "purple",
		"position": Vector3(0.0, 0.23, 2.15),
		"yaw": 0.0,
		"pose": 0.72,
		"accent": Color(0.66, 0.28, 1.0),
	},
]

const ELIMINATION_ORDER: Array[String] = [
	"green", "pink", "purple", "orange", "yellow",
]
const ELIMINATION_DELAYS: Array[float] = [0.30, 0.24, 0.17, 0.17, 0.30]

enum PreviewState {
	LOADING,
	CINEMATIC,
	TITLE,
	END_CARD,
}

@export var show_preview_controls := true
@export var autoplay := true

var _state := PreviewState.LOADING
var _sequence_generation := 0
var _reduced_motion := false

var _stage: Node3D
var _camera: Camera3D
var _gun_pivot: Node3D
var _gun_visual: Node3D
var _blue_spotlight: SpotLight3D
var _actors: Dictionary = {}
var _actor_configuration: Dictionary = {}

var _phrase: RichTextLabel
var _logo: TextureRect
var _prompt: Label
var _preview_controls: Label
var _end_card: Label
var _screen_fade: ColorRect
var _flash: ColorRect

var _active_tweens: Array[Tween] = []
var _prompt_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reduced_motion = AccessibilityManager.reduced_motion_enabled()
	_build_interface()
	_build_stage()
	# Render the logo handoff before the character rigs are prepared. The six
	# actors then share the cached idle retarget rather than eagerly loading the
	# complete gameplay animation library six times.
	await get_tree().process_frame
	await _build_actors()
	if autoplay:
		_start_preview()


func _input(event: InputEvent) -> void:
	if not _is_deliberate_press(event):
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_R:
		_start_preview()
		return
	if event.is_action("ui_cancel"):
		get_tree().quit()
		return
	match _state:
		PreviewState.CINEMATIC:
			_show_title_immediately()
		PreviewState.TITLE:
			_show_unlinked_handoff()


func _is_deliberate_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return key_event.pressed and not key_event.echo
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	return false


func _build_interface() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "CinematicInterface"
	canvas.layer = 10
	add_child(canvas)

	_phrase = RichTextLabel.new()
	_phrase.name = "RuleText"
	_phrase.bbcode_enabled = true
	_phrase.fit_content = false
	_phrase.scroll_active = false
	_phrase.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phrase.anchor_left = 0.08
	_phrase.anchor_top = 0.07
	_phrase.anchor_right = 0.92
	_phrase.anchor_bottom = 0.35
	_phrase.add_theme_font_size_override("normal_font_size", 92)
	_phrase.add_theme_color_override("default_color", WARM_WHITE)
	_phrase.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	_phrase.add_theme_constant_override("outline_size", 12)
	_phrase.modulate.a = 0.0
	canvas.add_child(_phrase)

	_logo = TextureRect.new()
	_logo.name = "OneGunLogo"
	_logo.texture = LOGO_TEXTURE
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.anchor_left = 0.24
	_logo.anchor_top = 0.17
	_logo.anchor_right = 0.76
	_logo.anchor_bottom = 0.72
	canvas.add_child(_logo)

	_prompt = Label.new()
	_prompt.name = "PressAnyButton"
	_prompt.text = "PRESS ANY BUTTON"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.anchor_left = 0.25
	_prompt.anchor_top = 0.78
	_prompt.anchor_right = 0.75
	_prompt.anchor_bottom = 0.88
	_prompt.add_theme_font_size_override("font_size", 24)
	_prompt.add_theme_color_override("font_color", WARM_WHITE)
	_prompt.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_prompt.add_theme_constant_override("shadow_offset_x", 2)
	_prompt.add_theme_constant_override("shadow_offset_y", 2)
	_prompt.visible = false
	canvas.add_child(_prompt)

	_preview_controls = Label.new()
	_preview_controls.name = "PreviewControls"
	_preview_controls.text = "STANDALONE PREVIEW  •  ANY BUTTON: SKIP / TEST HANDOFF  •  R: REPLAY  •  ESC: EXIT"
	_preview_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_controls.anchor_left = 0.12
	_preview_controls.anchor_top = 0.94
	_preview_controls.anchor_right = 0.88
	_preview_controls.anchor_bottom = 0.985
	_preview_controls.add_theme_font_size_override("font_size", 13)
	_preview_controls.add_theme_color_override("font_color", Color(0.68, 0.72, 0.82, 0.72))
	_preview_controls.visible = show_preview_controls
	canvas.add_child(_preview_controls)

	_end_card = Label.new()
	_end_card.name = "UnlinkedHandoffNotice"
	_end_card.text = "STANDALONE PREVIEW COMPLETE\n\nThe main-menu handoff is intentionally not connected.\nPress R to replay."
	_end_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_end_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_card.add_theme_font_size_override("font_size", 24)
	_end_card.add_theme_color_override("font_color", Color(0.72, 0.76, 0.84))
	_end_card.visible = false
	canvas.add_child(_end_card)

	_screen_fade = ColorRect.new()
	_screen_fade.name = "ScreenFade"
	_screen_fade.color = Color(BACKGROUND_COLOR, 0.0)
	_screen_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(_screen_fade)

	_flash = ColorRect.new()
	_flash.name = "GunshotFlash"
	_flash.color = Color(1.0, 0.86, 0.58, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(_flash)


func _build_stage() -> void:
	_stage = Node3D.new()
	_stage.name = "IntroStage"
	add_child(_stage)

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.18, 0.25, 0.43)
	environment.ambient_light_energy = 0.34
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	_stage.add_child(world_environment)

	var floor := MeshInstance3D.new()
	floor.name = "ArenaDisc"
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 5.65
	floor_mesh.bottom_radius = 5.9
	floor_mesh.height = 0.24
	floor_mesh.radial_segments = 64
	floor.mesh = floor_mesh
	floor.position.y = 0.12
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = FLOOR_COLOR
	floor_material.metallic = 0.58
	floor_material.roughness = 0.30
	floor_material.emission_enabled = true
	floor_material.emission = Color(0.005, 0.018, 0.055)
	floor_material.emission_energy_multiplier = 0.42
	floor.material_override = floor_material
	_stage.add_child(floor)

	var center_disc := MeshInstance3D.new()
	center_disc.name = "GunDisc"
	var center_mesh := CylinderMesh.new()
	center_mesh.top_radius = 1.35
	center_mesh.bottom_radius = 1.40
	center_mesh.height = 0.035
	center_mesh.radial_segments = 48
	center_disc.mesh = center_mesh
	center_disc.position.y = 0.258
	var center_material := StandardMaterial3D.new()
	center_material.albedo_color = Color(0.14, 0.075, 0.012)
	center_material.metallic = 0.82
	center_material.roughness = 0.24
	center_material.emission_enabled = true
	center_material.emission = Color(0.50, 0.20, 0.015)
	center_material.emission_energy_multiplier = 0.58
	center_disc.material_override = center_material
	_stage.add_child(center_disc)

	_gun_pivot = Node3D.new()
	_gun_pivot.name = "GunDisplay"
	_gun_pivot.position = Vector3(0.0, 1.33, 0.0)
	_stage.add_child(_gun_pivot)
	_gun_visual = GUN_SCENE.instantiate() as Node3D
	_gun_visual.name = "CeremonialOneGun"
	_gun_visual.scale = Vector3.ONE * 0.0032
	_gun_visual.rotation_degrees = Vector3(-8.0, -90.0, 8.0)
	_gun_pivot.add_child(_gun_visual)

	var key := DirectionalLight3D.new()
	key.name = "WarmKey"
	key.rotation_degrees = Vector3(-46.0, -26.0, 0.0)
	key.light_color = Color(1.0, 0.78, 0.56)
	key.light_energy = 1.45
	key.shadow_enabled = true
	_stage.add_child(key)

	var rim := DirectionalLight3D.new()
	rim.name = "CoolRim"
	rim.rotation_degrees = Vector3(-35.0, 154.0, 0.0)
	rim.light_color = Color(0.18, 0.42, 1.0)
	rim.light_energy = 0.78
	rim.shadow_enabled = false
	_stage.add_child(rim)

	var gun_spot := SpotLight3D.new()
	gun_spot.name = "GunSpotlight"
	gun_spot.position = Vector3(0.0, 6.6, 2.0)
	gun_spot.light_color = Color(1.0, 0.68, 0.26)
	gun_spot.light_energy = 5.2
	gun_spot.spot_range = 11.0
	gun_spot.spot_angle = 27.0
	gun_spot.shadow_enabled = false
	_stage.add_child(gun_spot)
	gun_spot.look_at(Vector3(0.0, 0.2, 0.0), Vector3.UP)

	_blue_spotlight = SpotLight3D.new()
	_blue_spotlight.name = "LastStandingSpotlight"
	_blue_spotlight.position = Vector3(0.0, 6.9, 3.0)
	_blue_spotlight.light_color = Color(1.0, 0.67, 0.24)
	_blue_spotlight.light_energy = 0.0
	_blue_spotlight.spot_range = 12.0
	_blue_spotlight.spot_angle = 23.0
	_blue_spotlight.shadow_enabled = false
	_stage.add_child(_blue_spotlight)
	_blue_spotlight.look_at(Vector3(0.0, 0.8, 0.35), Vector3.UP)

	_camera = Camera3D.new()
	_camera.name = "CinematicCamera"
	_camera.fov = 40.0
	_camera.transform = _camera_transform(Vector3(0.0, 2.15, 6.8), Vector3(0.0, 1.22, 0.0))
	_stage.add_child(_camera)
	_camera.current = true


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

		var animation_player := visual.call("ensure_animations", ["idle"]) as AnimationPlayer
		if animation_player != null and animation_player.has_animation("idle"):
			animation_player.play("idle")
			var idle := animation_player.get_animation("idle")
			animation_player.seek(idle.length * float(configuration["pose"]), true)
			animation_player.speed_scale = 0.22
			animation_player.advance(0.0)
		_actors[actor_id] = anchor
		_actor_configuration[actor_id] = configuration


func _start_preview() -> void:
	_sequence_generation += 1
	_stop_active_tweens()
	_cleanup_combat_pops()
	_state = PreviewState.CINEMATIC
	_reset_presentation()
	_run_sequence(_sequence_generation)


func _reset_presentation() -> void:
	_stage.visible = false
	_gun_pivot.visible = false
	_gun_pivot.position = Vector3(0.0, 1.33, 0.0)
	_gun_pivot.rotation = Vector3.ZERO
	_blue_spotlight.light_energy = 0.0
	_camera.fov = 40.0
	_camera.transform = _camera_transform(Vector3(0.0, 2.15, 6.8), CAMERA_TARGET)
	for actor_id in _actors:
		var anchor := _actors[actor_id] as Node3D
		var configuration := _actor_configuration[actor_id] as Dictionary
		anchor.visible = false
		anchor.position = configuration["position"]
		anchor.rotation_degrees = Vector3(0.0, float(configuration["yaw"]), 0.0)
		anchor.scale = Vector3.ONE
	_phrase.text = ""
	_phrase.modulate = Color.WHITE
	_phrase.modulate.a = 0.0
	_logo.visible = true
	_logo.modulate = Color.WHITE
	_prompt.visible = false
	_prompt.modulate.a = 0.0
	_end_card.visible = false
	_screen_fade.color = Color(BACKGROUND_COLOR, 0.0)
	_flash.color = Color(1.0, 0.86, 0.58, 0.0)


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

	if not await _wait_for(1.08, generation):
		return
	await _transition_to_title(generation)


func _show_phrase(bbcode: String, font_size := 92) -> void:
	_phrase.add_theme_font_size_override("normal_font_size", font_size)
	_phrase.text = "[center]%s[/center]" % bbcode
	_phrase.modulate.a = 0.0
	_tween_property(_phrase, "modulate:a", 1.0, 0.14 if not _reduced_motion else 0.05)
	if not _reduced_motion:
		_phrase.scale = Vector2(0.965, 0.965)
		_phrase.pivot_offset = _phrase.size * 0.5
		_tween_property(_phrase, "scale", Vector2.ONE, 0.20, Tween.TRANS_BACK, Tween.EASE_OUT)


func _reveal_actor(actor_id: String) -> void:
	var anchor := _actors.get(actor_id) as Node3D
	if anchor == null:
		return
	anchor.visible = true
	if _reduced_motion:
		anchor.scale = Vector3.ONE
		return
	anchor.scale = Vector3.ONE * 0.88
	_tween_property(anchor, "scale", Vector3.ONE, 0.20, Tween.TRANS_BACK, Tween.EASE_OUT)


func _eliminate_actor(actor_id: String) -> void:
	var anchor := _actors.get(actor_id) as Node3D
	if anchor == null or not anchor.visible:
		return
	var configuration := _actor_configuration.get(actor_id, {}) as Dictionary
	CombatPopEffect.spawn(_stage, anchor.global_position,
		configuration.get("accent", GOLD) as Color)
	anchor.visible = false


func _fire_gunshot_flash() -> void:
	var allowed := AccessibilityManager.allow_flash()
	_flash.color.a = 0.52 if allowed else 0.10
	_tween_property(_flash, "color:a", 0.0, 0.16 if allowed else 0.08)


func _transition_to_title(generation: int) -> void:
	_tween_property(_screen_fade, "color:a", 1.0, 0.24)
	if not await _wait_for(0.26, generation):
		return
	_stage.visible = false
	_phrase.modulate.a = 0.0
	_logo.visible = true
	_logo.modulate.a = 0.0
	_prompt.visible = true
	_prompt.modulate.a = 0.0
	_tween_property(_screen_fade, "color:a", 0.0, 0.34)
	_tween_property(_logo, "modulate:a", 1.0, 0.38)
	if not await _wait_for(0.42, generation):
		return
	_state = PreviewState.TITLE
	_tween_property(_prompt, "modulate:a", 0.88, 0.25)
	_start_prompt_pulse()


func _show_title_immediately() -> void:
	_sequence_generation += 1
	_stop_active_tweens()
	_cleanup_combat_pops()
	_stage.visible = false
	_phrase.modulate.a = 0.0
	_screen_fade.color.a = 0.0
	_flash.color.a = 0.0
	_logo.visible = true
	_logo.modulate.a = 1.0
	_prompt.visible = true
	_prompt.modulate.a = 0.88
	_end_card.visible = false
	_state = PreviewState.TITLE
	_start_prompt_pulse()


func _show_unlinked_handoff() -> void:
	if _state != PreviewState.TITLE:
		return
	_sequence_generation += 1
	_state = PreviewState.END_CARD
	_stop_active_tweens()
	var generation := _sequence_generation
	_run_unlinked_handoff(generation)


func _run_unlinked_handoff(generation: int) -> void:
	_tween_property(_screen_fade, "color:a", 1.0, 0.24)
	if not await _wait_for(0.26, generation):
		return
	_logo.visible = false
	_prompt.visible = false
	_end_card.visible = true
	_screen_fade.color.a = 0.0


func _start_prompt_pulse() -> void:
	if _prompt_tween != null:
		_prompt_tween.kill()
		_prompt_tween = null
	if _reduced_motion:
		_prompt.modulate.a = 0.88
		return
	_prompt_tween = create_tween().set_loops()
	_prompt_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_prompt_tween.tween_property(_prompt, "modulate:a", 0.46, 0.72) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_prompt_tween.tween_property(_prompt, "modulate:a", 0.90, 0.72) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _wait_for(seconds: float, generation: int) -> bool:
	await get_tree().create_timer(seconds, true, false, true).timeout
	return generation == _sequence_generation


func _motion_time(normal_time: float) -> float:
	return 0.06 if _reduced_motion else normal_time


func _camera_transform(position: Vector3, target: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, position).looking_at(target, Vector3.UP)


func _tween_property(object: Object, property: NodePath, final_value: Variant,
		duration: float, transition := Tween.TRANS_QUAD,
		ease := Tween.EASE_IN_OUT) -> Tween:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(object, property, final_value, duration) \
		.set_trans(transition).set_ease(ease)
	_active_tweens.append(tween)
	return tween


func _stop_active_tweens() -> void:
	if _prompt_tween != null:
		_prompt_tween.kill()
		_prompt_tween = null
	for tween in _active_tweens:
		if tween != null:
			tween.kill()
	_active_tweens.clear()


func _cleanup_combat_pops() -> void:
	if _stage == null:
		return
	for child in _stage.get_children():
		if child.name == "CombatPop":
			child.queue_free()

