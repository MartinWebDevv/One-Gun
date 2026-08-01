extends Control

# One non-stacking local feedback renderer. Typed, server/local-authoritative
# events select hit versus elimination presentation; an elimination can replace
# an active hit, while a later ordinary hit cannot downgrade an elimination.

var filter_name := ""
var _life := 0.0
var _duration := 0.28
var _event_kind := ""
var _elimination := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -80.0
	offset_top = -80.0
	offset_right = 80.0
	offset_bottom = 80.0
	visible = false
	GameEvents.combat_feedback.connect(_on_combat_feedback)


func _on_combat_feedback(attacker_name: String, event_kind: String) -> void:
	if filter_name != "" and attacker_name != filter_name: return
	show_feedback(event_kind)


func show_feedback(event_kind: String) -> void:
	var incoming_elimination := event_kind.ends_with("_elimination")
	if _life > 0.0 and _elimination and not incoming_elimination: return
	if incoming_elimination and not bool(PlayerPrefs.get_setting("elimination_marker_enabled")): return
	if not incoming_elimination and not bool(PlayerPrefs.get_setting("hit_marker_enabled")): return
	_event_kind = event_kind
	_elimination = incoming_elimination
	_duration = float(PlayerPrefs.get_setting("elimination_marker_duration" if _elimination else "hit_marker_duration"))
	_life = 1.0
	visible = true
	queue_redraw()
	var sound_key := "elimination_marker_sound" if _elimination else "hit_marker_sound"
	if bool(PlayerPrefs.get_setting(sound_key)):
		var volume_key := "elimination_marker_volume" if _elimination else "hit_marker_volume"
		AudioManager.play_sfx("click", 0.8 if _elimination else 1.7, float(PlayerPrefs.get_setting(volume_key)))


func _process(delta: float) -> void:
	if _life <= 0.0: return
	_life = maxf(_life - delta / maxf(_duration, 0.01), 0.0)
	visible = _life > 0.0
	queue_redraw()


func _draw() -> void:
	if _life <= 0.0: return
	var center := size * 0.5
	var size_key := "elimination_marker_size" if _elimination else "hit_marker_size"
	var opacity_key := "elimination_marker_opacity" if _elimination else "hit_marker_opacity"
	var style_key := "elimination_marker_style" if _elimination else "hit_marker_style"
	var color_key := "elimination_marker_color" if _elimination else "hit_marker_color"
	var scale_value := float(PlayerPrefs.get_setting(size_key)) * (1.0 + 0.22 * _life)
	var color := _color(PlayerPrefs.get_setting(color_key))
	if _event_kind.begins_with("melee_"):
		color = Color(1.0, 0.48, 0.12) if _elimination else Color.WHITE
	color.a *= float(PlayerPrefs.get_setting(opacity_key)) * minf(_life * 2.5, 1.0)
	var style := str(PlayerPrefs.get_setting(style_key))
	var thickness := float(PlayerPrefs.get_setting("hit_marker_thickness"))
	if _elimination:
		_draw_elimination(center, style, color, scale_value, thickness)
	else:
		_draw_hit(center, style, color, scale_value, thickness)


func _draw_hit(center: Vector2, style: String, color: Color, scale_value: float, thickness: float) -> void:
	var gap := 5.0 * scale_value
	var length := 11.0 * scale_value
	var offset := 0.0 if style == "x" else 45.0
	var count := 4 if style != "diamond" else 4
	for i in count:
		var angle := deg_to_rad(45.0 + 90.0 * i + offset)
		var direction := Vector2.from_angle(angle)
		draw_line(center + direction * gap, center + direction * (gap + length), color, thickness, true)


func _draw_elimination(center: Vector2, style: String, color: Color, scale_value: float, thickness: float) -> void:
	if style == "expanding_ring":
		draw_arc(center, (12.0 + 12.0 * (1.0 - _life)) * scale_value, 0.0, TAU, 32, color, thickness, true)
		return
	if style == "toy_splash":
		for i in 8:
			var direction := Vector2.from_angle(TAU * i / 8.0)
			draw_circle(center + direction * (10.0 + 8.0 * (1.0 - _life)) * scale_value, 2.5 * scale_value, color)
		return
	# Gold Star and Skull + Star use a crisp procedural star; the latter adds eyes.
	var points := PackedVector2Array()
	for i in 10:
		var radius := (16.0 if i % 2 == 0 else 7.0) * scale_value
		points.append(center + Vector2.from_angle(-PI * 0.5 + TAU * i / 10.0) * radius)
	draw_colored_polygon(points, color)
	if style == "skull_star":
		draw_circle(center + Vector2(-4, -1) * scale_value, 1.8 * scale_value, Color("151525"))
		draw_circle(center + Vector2(4, -1) * scale_value, 1.8 * scale_value, Color("151525"))


func _color(value) -> Color:
	if value is Color: return value
	if value is Array and value.size() >= 4: return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Color.WHITE


static func should_replace(active_kind: String, incoming_kind: String) -> bool:
	return not active_kind.ends_with("_elimination") or incoming_kind.ends_with("_elimination")
