class_name DamageDirectionIndicator
extends Control

# Viewport-scoped, victim-filtered incoming-fire feedback. Each entry stores
# the world-space bearing of the shot at impact, then rotates that bearing
# against the displayed player's camera while it fades.

const DISPLAY_TIME := 0.90
const FADE_IN_TIME := 0.055
const FADE_OUT_TIME := 0.52
const MAX_INDICATORS := 4
const MERGE_ANGLE_COS := 0.9396926 # cos(20 degrees)

var player = null
var _indicators: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	GameEvents.actor_damage_direction.connect(_on_actor_damage_direction)


func set_player(value) -> void:
	if value == player:
		return
	var preserve_lethal_hit := not _indicators.is_empty() and player != null \
		and bool(player.get("is_eliminated"))
	player = value
	if not preserve_lethal_hit:
		_clear()


func _on_actor_damage_direction(victim_actor_id: int,
		source_world_direction: Vector3, source_kind: String) -> void:
	if source_kind != "gun" or player == null:
		return
	var bound_actor_id = player.get("actor_id")
	if bound_actor_id == null or int(bound_actor_id) != victim_actor_id:
		return
	var direction := Vector3(source_world_direction.x, 0.0, source_world_direction.z)
	if not direction.is_finite() or direction.is_zero_approx():
		return
	direction = direction.normalized()
	var initial_bearing := _bearing_for_direction(_player_camera(), direction)
	for index in _indicators.size():
		var existing: Vector3 = _indicators[index].get("direction", Vector3.ZERO)
		if existing.dot(direction) >= MERGE_ANGLE_COS:
			_indicators[index]["direction"] = direction
			_indicators[index]["bearing"] = initial_bearing
			_indicators[index]["victim_actor_id"] = victim_actor_id
			_indicators[index]["age"] = 0.0
			_indicators[index]["strength"] = minf(
				float(_indicators[index].get("strength", 0.82)) + 0.12, 1.0)
			_activate()
			return
	if _indicators.size() >= MAX_INDICATORS:
		_indicators.pop_front()
	_indicators.append({
		"direction": direction,
		"bearing": initial_bearing,
		"victim_actor_id": victim_actor_id,
		"age": 0.0,
		"strength": 0.88,
	})
	_activate()


func _activate() -> void:
	visible = true
	set_process(true)
	queue_redraw()


func _clear() -> void:
	_indicators.clear()
	visible = false
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	for index in range(_indicators.size() - 1, -1, -1):
		var age := float(_indicators[index].get("age", 0.0)) + delta
		if age >= DISPLAY_TIME:
			_indicators.remove_at(index)
		else:
			_indicators[index]["age"] = age
	if _indicators.is_empty():
		_clear()
		return
	queue_redraw()


func _draw() -> void:
	if player == null or _indicators.is_empty():
		return
	var camera := _player_camera()
	var bound_actor_id = player.get("actor_id")
	var track_current_view := camera != null and bound_actor_id != null \
		and not bool(player.get("is_eliminated"))
	var center := size * 0.5
	var base_radius := clampf(minf(size.x, size.y) * 0.27, 94.0, 242.0)
	for entry in _indicators:
		var direction: Vector3 = entry.get("direction", Vector3.ZERO)
		var angle := float(entry.get("bearing", 0.0))
		if track_current_view and int(entry.get("victim_actor_id", -1)) == int(bound_actor_id):
			angle = _bearing_for_direction(camera, direction)
			entry["bearing"] = angle
		var age := float(entry.get("age", 0.0))
		var alpha := _alpha_for_age(age) * float(entry.get("strength", 1.0))
		var impact_push := 0.0
		if not AccessibilityManager.reduced_motion_enabled():
			impact_push = (1.0 - clampf(age / 0.12, 0.0, 1.0)) * 12.0
		_draw_damage_arc(center, angle, base_radius + impact_push, alpha)


func _player_camera() -> Camera3D:
	if player == null or not player.has_method("get_camera"):
		return null
	var camera = player.get_camera()
	return camera as Camera3D if camera is Camera3D and is_instance_valid(camera) else null


func _bearing_for_direction(camera: Camera3D, direction: Vector3) -> float:
	if camera == null:
		return 0.0
	var camera_forward := -camera.global_basis.z
	camera_forward.y = 0.0
	var camera_right := camera.global_basis.x
	camera_right.y = 0.0
	if camera_forward.is_zero_approx() or camera_right.is_zero_approx():
		return 0.0
	camera_forward = camera_forward.normalized()
	camera_right = camera_right.normalized()
	return atan2(direction.dot(camera_right), direction.dot(camera_forward))


func _alpha_for_age(age: float) -> float:
	if age < FADE_IN_TIME:
		return smoothstep(0.0, FADE_IN_TIME, age)
	return clampf((DISPLAY_TIME - age) / FADE_OUT_TIME, 0.0, 1.0)


func _draw_damage_arc(center: Vector2, bearing: float, radius: float, alpha: float) -> void:
	if alpha <= 0.0:
		return
	const SEGMENTS := 18
	const HALF_ARC := 0.44 # about 50 degrees total
	var canvas_angle := bearing - PI * 0.5
	var shadow := Color(0.03, 0.0, 0.0, 0.62 * alpha)
	var glow := Color(1.0, 0.015, 0.005, 0.15 * alpha)
	draw_arc(center, radius, canvas_angle - HALF_ARC, canvas_angle + HALF_ARC,
		SEGMENTS, shadow, 17.0, true)
	draw_arc(center, radius, canvas_angle - HALF_ARC, canvas_angle + HALF_ARC,
		SEGMENTS, glow, 22.0, true)

	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for index in range(SEGMENTS + 1):
		var t := float(index) / float(SEGMENTS)
		var taper := pow(sin(PI * t), 0.55)
		var half_thickness := lerpf(1.2, 6.6, taper)
		var angle := canvas_angle + lerpf(-HALF_ARC, HALF_ARC, t)
		var radial := Vector2.from_angle(angle)
		outer.append(center + radial * (radius + half_thickness))
		inner.append(center + radial * (radius - half_thickness))
	var band := PackedVector2Array()
	band.append_array(outer)
	for index in range(inner.size() - 1, -1, -1):
		band.append(inner[index])
	draw_colored_polygon(band, Color(0.94, 0.025, 0.012, 0.92 * alpha))
	draw_arc(center, radius - 0.5, canvas_angle - HALF_ARC * 0.78,
		canvas_angle + HALF_ARC * 0.78, SEGMENTS,
		Color(1.0, 0.24, 0.12, 0.9 * alpha), 1.8, true)

	# The small inward barb makes the bearing unambiguous without requiring a
	# large arrow that would compete with the crosshair.
	var radial := Vector2.from_angle(canvas_angle)
	var tangent := Vector2(-radial.y, radial.x)
	var barb := PackedVector2Array([
		center + radial * (radius - 3.0) - tangent * 5.0,
		center + radial * (radius - 15.0),
		center + radial * (radius - 3.0) + tangent * 5.0,
	])
	draw_colored_polygon(barb, Color(1.0, 0.055, 0.02, alpha))
