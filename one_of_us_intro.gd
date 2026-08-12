class_name OneOfUsIntro
extends CanvasLayer

# All timing and camera values live here so the role reveal can be tuned without
# touching RoundManager, networking, or either player controller.
const OPENING_HOLD_TIME := 0.15
const DIVE_TIME := 0.75
const SEARCH_TARGET_COUNT := 3
const SEARCH_FLYBY_TIME := 0.40
const FINAL_APPROACH_TIME := 0.65
const TRANSFORMATION_ORBIT_TIME := 1.80
const ENDING_TRANSITION_TIME := 0.85
const FIRST_TEXT_TIME := 0.70
const SECOND_TEXT_TIME := 0.80
const FADE_TIME := 0.25
const TOTAL_TIME := OPENING_HOLD_TIME + DIVE_TIME \
	+ SEARCH_TARGET_COUNT * SEARCH_FLYBY_TIME + FINAL_APPROACH_TIME \
	+ TRANSFORMATION_ORBIT_TIME + ENDING_TRANSITION_TIME \
	+ FIRST_TEXT_TIME + SECOND_TEXT_TIME + FADE_TIME

const HIGH_CAMERA_MIN_HEIGHT := 19.0
const SEARCH_DISTANCE := 5.2
const SEARCH_HEIGHT := 2.6
const INFECTED_REVEAL_DISTANCE := 5.4
const INFECTED_REVEAL_HEIGHT := 2.3
const ORBIT_START_RADIUS := 5.0
const ORBIT_END_RADIUS := 2.65
const ORBIT_TURNS := 1.10
const CINEMATIC_FOV := 62.0
const TRANSFORMATION_SFX := "" # Assign an AudioManager SFX key when an asset is added.

const FIRST_INFECTED_TEXT := "YOU ARE THE FIRST."
const INFECTED_OBJECTIVE_TEXT := "MAKE THEM ONE OF US."
const SURVIVOR_WARNING_TEXT := "ONE OF THEM HAS TURNED."
const SURVIVOR_OBJECTIVE_TEXT := "RUN."

var _local_actor = null
var _infected_actor = null
var _first_infected := false
var _camera: Camera3D
var _screen_effect: ColorRect
var _effect_material: ShaderMaterial
var _text: Label


func play(actor, first_actor_id: int) -> void:
	_local_actor = actor
	_infected_actor = _find_actor(first_actor_id)
	if _infected_actor == null:
		_infected_actor = actor
	_first_infected = actor != null and int(actor.get("actor_id")) == first_actor_id
	layer = 120
	_build_ui(_display_rect_for(actor))
	_build_camera()
	if actor != null and actor.has_method("begin_one_of_us_intro_view"):
		actor.begin_one_of_us_intro_view(_first_infected, _camera)
	_run_sequence()


func _find_actor(actor_id: int):
	if NetworkManager.is_online():
		var network_actor = NetworkManager.find_actor(actor_id)
		if network_actor != null:
			return network_actor
	for candidate in get_tree().get_nodes_in_group("combat_target"):
		if is_instance_valid(candidate) and int(candidate.get("actor_id")) == actor_id:
			return candidate
	return null


func _arena_actors() -> Array:
	var actors: Array = []
	for candidate in get_tree().get_nodes_in_group("combat_target"):
		if not is_instance_valid(candidate) or bool(candidate.get("is_eliminated")):
			continue
		actors.append(candidate)
	actors.sort_custom(func(a, b): return int(a.get("actor_id")) < int(b.get("actor_id")))
	return actors


func _actor_focus(actor) -> Vector3:
	return actor.global_position + Vector3.UP * 1.35 if actor != null else Vector3.UP


func _actor_forward(actor) -> Vector3:
	if actor == null:
		return Vector3.FORWARD
	var pivot := actor.get_node_or_null("AimPivot") as Node3D
	var forward: Vector3 = -pivot.global_basis.z if pivot != null else -actor.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD


func _arena_center(actors: Array) -> Vector3:
	if actors.is_empty():
		return _actor_focus(_infected_actor)
	var center := Vector3.ZERO
	for actor in actors:
		center += _actor_focus(actor)
	return center / float(actors.size())


func _arena_radius(actors: Array, center: Vector3) -> float:
	var radius := 12.0
	for actor in actors:
		var offset: Vector3 = _actor_focus(actor) - center
		offset.y = 0.0
		radius = maxf(radius, offset.length())
	return radius


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "OneOfUsCinematicCamera"
	_camera.fov = CINEMATIC_FOV
	get_tree().current_scene.add_child(_camera)
	var actors := _arena_actors()
	var center := _arena_center(actors)
	var radius := _arena_radius(actors, center)
	_camera.global_position = center + Vector3(0.0,
		maxf(HIGH_CAMERA_MIN_HEIGHT, radius * 0.72), radius * 0.30)
	_camera.look_at(center, Vector3.UP)


func _display_rect_for(actor) -> Rect2:
	if actor != null and actor.has_method("get_one_of_us_intro_display_rect"):
		return actor.get_one_of_us_intro_display_rect()
	return get_viewport().get_visible_rect()


func _fit_to_rect(control: Control, display_rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = display_rect.position
	control.size = display_rect.size


func _build_ui(display_rect: Rect2) -> void:
	_screen_effect = ColorRect.new()
	_fit_to_rect(_screen_effect, display_rect)
	_screen_effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength = 0.0;
uniform float tint = 0.0;
uniform float flicker = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	float band = step(0.70, fract(uv.y * 42.0 + TIME * 21.0));
	float jitter = sin(uv.y * 103.0 + TIME * 37.0) * strength * band;
	uv.x += jitter;
	vec4 base = texture(screen_texture, uv);
	float split = strength * 0.62;
	base.r = texture(screen_texture, uv + vec2(split, 0.0)).r;
	base.b = texture(screen_texture, uv - vec2(split, 0.0)).b;
	base.rgb = mix(base.rgb, vec3(0.34, 0.01, 0.12), tint);
	base.rgb *= 1.0 - flicker * step(0.74, fract(TIME * 19.0));
	COLOR = base;
}
"""
	_effect_material = ShaderMaterial.new()
	_effect_material.shader = shader
	_screen_effect.material = _effect_material
	add_child(_screen_effect)
	_text = Label.new()
	_fit_to_rect(_text, display_rect)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.add_theme_font_size_override("font_size", 42)
	_text.add_theme_constant_override("outline_size", 12)
	_text.add_theme_color_override("font_color", Color(1.0, 0.93, 0.88))
	_text.add_theme_color_override("font_outline_color", Color(0.08, 0.0, 0.03, 0.96))
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	_set_glitch(0.0, 0.0, 0.0)


func _set_glitch(strength: float, tint: float, flicker: float) -> void:
	if _effect_material == null:
		return
	_effect_material.set_shader_parameter("strength", strength)
	_effect_material.set_shader_parameter("tint", tint)
	_effect_material.set_shader_parameter("flicker", flicker)


func _run_sequence() -> void:
	_text.text = ""
	await get_tree().create_timer(OPENING_HOLD_TIME).timeout
	if not _cinematic_valid():
		return
	var actors := _arena_actors()
	var center := _arena_center(actors)
	var radius := _arena_radius(actors, center)
	var dive_position := center + Vector3(0.0, 8.5, radius * 0.18)
	await _move_camera(dive_position, center, DIVE_TIME, 0.06)

	var search_targets: Array = actors.filter(func(candidate): return candidate != _infected_actor)
	for index in SEARCH_TARGET_COUNT:
		var focus := center
		if not search_targets.is_empty():
			focus = _actor_focus(search_targets[index % search_targets.size()])
		var angle := -0.9 + float(index) * 1.15
		var destination := focus + Vector3(cos(angle) * SEARCH_DISTANCE,
			SEARCH_HEIGHT, sin(angle) * SEARCH_DISTANCE)
		await _move_camera(destination, focus, SEARCH_FLYBY_TIME, 0.025)

	var infected_focus := _actor_focus(_infected_actor)
	var infected_forward := _actor_forward(_infected_actor)
	var behind := infected_focus - infected_forward * INFECTED_REVEAL_DISTANCE \
		+ Vector3.UP * INFECTED_REVEAL_HEIGHT
	await _move_camera(behind, infected_focus, FINAL_APPROACH_TIME, 0.015)
	if _infected_actor != null and _infected_actor.has_method("play_one_of_us_transformation"):
		_infected_actor.play_one_of_us_transformation()
	if TRANSFORMATION_SFX != "":
		AudioManager.play_sfx(TRANSFORMATION_SFX)
	await _orbit_transformation(infected_focus, infected_forward)
	await _play_role_ending()
	await _show_role_text()
	_finish_intro()


func _orbit_transformation(focus: Vector3, forward: Vector3) -> void:
	var elapsed := 0.0
	var starting_angle := atan2(-forward.z, -forward.x)
	while elapsed < TRANSFORMATION_ORBIT_TIME and _cinematic_valid():
		var t := clampf(elapsed / TRANSFORMATION_ORBIT_TIME, 0.0, 1.0)
		var eased := t * t * (3.0 - 2.0 * t)
		var radius := lerpf(ORBIT_START_RADIUS, ORBIT_END_RADIUS, eased)
		var instability := sin(t * 47.0) * 0.09 * t
		var angle := starting_angle + TAU * ORBIT_TURNS * eased + instability
		_camera.global_position = focus + Vector3(cos(angle) * radius,
			lerpf(2.6, 1.95, eased) + sin(t * 31.0) * 0.10 * t,
			sin(angle) * radius)
		_camera.fov = lerpf(CINEMATIC_FOV, 69.0, eased)
		_camera.look_at(focus + Vector3.UP * 0.12, Vector3.UP)
		_set_glitch(lerpf(0.018, 0.105, eased), lerpf(0.08, 0.34, eased),
			lerpf(0.05, 0.28, eased))
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _play_role_ending() -> void:
	var gameplay_camera: Camera3D = _local_actor.get_gameplay_camera() \
		if _local_actor != null and _local_actor.has_method("get_gameplay_camera") else null
	if gameplay_camera == null:
		await get_tree().create_timer(ENDING_TRANSITION_TIME).timeout
		return
	var gameplay_look := gameplay_camera.global_position - gameplay_camera.global_basis.z * 10.0
	if _first_infected:
		await _move_camera(gameplay_camera.global_position, gameplay_look,
			ENDING_TRANSITION_TIME, 0.12)
	else:
		var infected_focus := _actor_focus(_infected_actor)
		var thrown_back := _camera.global_position \
			+ (_camera.global_position - infected_focus).normalized() * 5.5 \
			+ Vector3.UP * 1.2
		await _move_camera(thrown_back, infected_focus, ENDING_TRANSITION_TIME * 0.28, 0.11)
		var local_focus := _actor_focus(_local_actor)
		var local_forward := _actor_forward(_local_actor)
		var shoulder := local_focus - local_forward * 2.2 \
			+ local_forward.cross(Vector3.UP).normalized() * 1.35 + Vector3.UP * 0.55
		await _move_camera(shoulder, local_focus, ENDING_TRANSITION_TIME * 0.42, 0.06)
		await _move_camera(gameplay_camera.global_position, gameplay_look,
			ENDING_TRANSITION_TIME * 0.30, 0.035)
	if _local_actor != null and _local_actor.has_method("transition_one_of_us_intro_to_gameplay"):
		_local_actor.transition_one_of_us_intro_to_gameplay(_first_infected)


func _show_role_text() -> void:
	_set_glitch(0.018 if _first_infected else 0.010,
		0.15 if _first_infected else 0.035, 0.02)
	_text.text = FIRST_INFECTED_TEXT if _first_infected else SURVIVOR_WARNING_TEXT
	await get_tree().create_timer(FIRST_TEXT_TIME).timeout
	if not is_inside_tree():
		return
	_text.text = INFECTED_OBJECTIVE_TEXT if _first_infected else SURVIVOR_OBJECTIVE_TEXT
	await get_tree().create_timer(SECOND_TEXT_TIME).timeout
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(_text, "modulate:a", 0.0, FADE_TIME)
	tween.parallel().tween_method(func(value: float):
		_set_glitch(value, value * 2.0, value), 0.01, 0.0, FADE_TIME)
	await tween.finished


func _move_camera(end_position: Vector3, end_look: Vector3,
		duration: float, max_glitch: float) -> void:
	if not _cinematic_valid():
		return
	var start_position := _camera.global_position
	var start_look := start_position - _camera.global_basis.z * 10.0
	var elapsed := 0.0
	while elapsed < duration and _cinematic_valid():
		var t := clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
		var eased := t * t * (3.0 - 2.0 * t)
		_camera.global_position = start_position.lerp(end_position, eased)
		_camera.look_at(start_look.lerp(end_look, eased), Vector3.UP)
		if max_glitch > 0.0:
			_set_glitch(max_glitch * sin(PI * t), max_glitch * 1.8, max_glitch)
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if _cinematic_valid():
		_camera.global_position = end_position
		_camera.look_at(end_look, Vector3.UP)


func _cinematic_valid() -> bool:
	return is_inside_tree() and is_instance_valid(_camera)


func _finish_intro() -> void:
	if _local_actor != null and is_instance_valid(_local_actor) \
			and _local_actor.has_method("end_one_of_us_intro_view"):
		_local_actor.end_one_of_us_intro_view()
	if _camera != null:
		_camera.queue_free()
	_camera = null
	queue_free()
