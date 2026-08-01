class_name OneGunIcon
extends Control

# Code-drawn indicator icons for the redesigned menus. Vector drawing keeps
# them crisp at every resolution and UI scale (packet §4 / Phase 1), matching
# the MenuButtonIcon approach already used by main_menu.gd.

enum Kind {
	PLAYER, BOT, CROWN, CHECK, CROSS,
	LOCK, GLOBE, FRIENDS, WARNING, HELP,
	PLUS, MINUS, CHEVRON_LEFT, CHEVRON_RIGHT, SPINNER,
	EDIT,
}

@export var kind: Kind = Kind.PLAYER:
	set(value):
		kind = value
		queue_redraw()
@export var icon_color: Color = Color(0.953, 0.914, 0.812):
	set(value):
		icon_color = value
		queue_redraw()

var _spin_angle := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(24.0, 24.0)


func _process(delta: float) -> void:
	if kind == Kind.SPINNER and is_visible_in_tree():
		_spin_angle = fmod(_spin_angle + delta * TAU * 0.9, TAU)
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var s := minf(size.x, size.y) / 24.0  # icons authored on a 24px grid
	match kind:
		Kind.PLAYER:
			_draw_player(center, s)
		Kind.BOT:
			_draw_bot(center, s)
		Kind.CROWN:
			_draw_crown(center, s)
		Kind.CHECK:
			_draw_check(center, s)
		Kind.CROSS:
			_draw_cross(center, s)
		Kind.LOCK:
			_draw_lock(center, s)
		Kind.GLOBE:
			_draw_globe(center, s)
		Kind.FRIENDS:
			_draw_friends(center, s)
		Kind.WARNING:
			_draw_warning(center, s)
		Kind.HELP:
			_draw_help(center, s)
		Kind.PLUS:
			_draw_plus(center, s, true)
		Kind.MINUS:
			_draw_plus(center, s, false)
		Kind.CHEVRON_LEFT:
			_draw_chevron(center, s, -1.0)
		Kind.CHEVRON_RIGHT:
			_draw_chevron(center, s, 1.0)
		Kind.SPINNER:
			_draw_spinner(center, s)
		Kind.EDIT:
			_draw_edit(center, s)


func _draw_edit(center: Vector2, s: float) -> void:
	var start := center + Vector2(-5.5, 5.5) * s
	var finish := center + Vector2(4.5, -4.5) * s
	draw_line(start, finish, icon_color, 3.6 * s, true)
	draw_line(start + Vector2(-1.5, 1.5) * s, start + Vector2(2.0, 0.5) * s,
			icon_color, 2.0 * s, true)
	draw_line(finish + Vector2(-1.8, -1.8) * s, finish + Vector2(1.4, 1.4) * s,
			icon_color.lightened(0.18), 2.0 * s, true)


func _draw_player(center: Vector2, s: float) -> void:
	draw_circle(center + Vector2(0.0, -4.5) * s, 4.5 * s, icon_color)
	var body := PackedVector2Array()
	for index in 17:
		var angle := PI + PI * float(index) / 16.0
		body.append(center + Vector2(0.0, 8.5) * s + Vector2(cos(angle), sin(angle)) * 7.0 * s)
	body.append(center + Vector2(7.0, 10.0) * s)
	body.append(center + Vector2(-7.0, 10.0) * s)
	draw_colored_polygon(body, icon_color)


func _draw_bot(center: Vector2, s: float) -> void:
	var head := Rect2(center + Vector2(-8.0, -6.0) * s, Vector2(16.0, 12.0) * s)
	draw_rect(head, icon_color, false, 2.0 * s, true)
	draw_line(center + Vector2(0.0, -6.0) * s, center + Vector2(0.0, -10.0) * s, icon_color, 2.0 * s, true)
	draw_circle(center + Vector2(0.0, -11.0) * s, 1.6 * s, icon_color)
	draw_circle(center + Vector2(-4.0, -1.0) * s, 1.8 * s, icon_color)
	draw_circle(center + Vector2(4.0, -1.0) * s, 1.8 * s, icon_color)
	draw_line(center + Vector2(-4.0, 3.5) * s, center + Vector2(4.0, 3.5) * s, icon_color, 1.8 * s, true)
	draw_line(center + Vector2(-8.0, 9.0) * s, center + Vector2(8.0, 9.0) * s, icon_color, 2.0 * s, true)


func _draw_crown(center: Vector2, s: float) -> void:
	var base_y := 6.0
	var points := PackedVector2Array([
		center + Vector2(-9.0, base_y) * s,
		center + Vector2(-10.0, -5.0) * s,
		center + Vector2(-4.5, 0.0) * s,
		center + Vector2(0.0, -8.0) * s,
		center + Vector2(4.5, 0.0) * s,
		center + Vector2(10.0, -5.0) * s,
		center + Vector2(9.0, base_y) * s,
	])
	draw_colored_polygon(points, icon_color)
	draw_rect(Rect2(center + Vector2(-9.0, base_y + 1.0) * s, Vector2(18.0, 2.4) * s), icon_color)


func _draw_check(center: Vector2, s: float) -> void:
	draw_polyline(PackedVector2Array([
		center + Vector2(-8.0, 0.5) * s,
		center + Vector2(-2.5, 6.5) * s,
		center + Vector2(8.5, -6.5) * s,
	]), icon_color, 3.4 * s, true)


func _draw_cross(center: Vector2, s: float) -> void:
	draw_line(center + Vector2(-6.5, -6.5) * s, center + Vector2(6.5, 6.5) * s, icon_color, 3.4 * s, true)
	draw_line(center + Vector2(6.5, -6.5) * s, center + Vector2(-6.5, 6.5) * s, icon_color, 3.4 * s, true)


func _draw_lock(center: Vector2, s: float) -> void:
	var body := Rect2(center + Vector2(-7.0, -1.0) * s, Vector2(14.0, 10.5) * s)
	draw_rect(body, icon_color, true)
	draw_arc(center + Vector2(0.0, -1.5) * s, 5.0 * s, PI, TAU, 20, icon_color, 2.6 * s, true)
	draw_circle(center + Vector2(0.0, 3.5) * s, 1.9 * s, Color(0.1, 0.12, 0.2))


func _draw_globe(center: Vector2, s: float) -> void:
	draw_arc(center, 9.0 * s, 0.0, TAU, 40, icon_color, 2.0 * s, true)
	draw_polyline(_ellipse_points(center, Vector2(4.0, 9.0) * s), icon_color, 1.6 * s, true)
	draw_line(center + Vector2(-8.5, -3.2) * s, center + Vector2(8.5, -3.2) * s, icon_color, 1.6 * s, true)
	draw_line(center + Vector2(-8.5, 3.2) * s, center + Vector2(8.5, 3.2) * s, icon_color, 1.6 * s, true)


func _draw_friends(center: Vector2, s: float) -> void:
	draw_circle(center + Vector2(-4.5, -3.5) * s, 3.4 * s, icon_color)
	draw_arc(center + Vector2(-4.5, 6.0) * s, 5.4 * s, PI, TAU, 20, icon_color, 2.6 * s, true)
	var back := Color(icon_color, icon_color.a * 0.55)
	draw_circle(center + Vector2(5.5, -4.5) * s, 2.9 * s, back)
	draw_arc(center + Vector2(5.5, 4.5) * s, 4.6 * s, PI, TAU, 20, back, 2.3 * s, true)


func _draw_warning(center: Vector2, s: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -9.5) * s,
		center + Vector2(10.0, 8.5) * s,
		center + Vector2(-10.0, 8.5) * s,
	])
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), icon_color, 2.2 * s, true)
	draw_line(center + Vector2(0.0, -3.5) * s, center + Vector2(0.0, 2.5) * s, icon_color, 2.4 * s, true)
	draw_circle(center + Vector2(0.0, 5.8) * s, 1.4 * s, icon_color)


func _draw_help(center: Vector2, s: float) -> void:
	draw_arc(center, 9.5 * s, 0.0, TAU, 36, icon_color, 2.0 * s, true)
	draw_arc(center + Vector2(0.0, -2.5) * s, 3.6 * s, PI * 0.85, TAU * 1.08, 20, icon_color, 2.2 * s, true)
	draw_line(center + Vector2(0.9, 0.5) * s, center + Vector2(0.9, 2.8) * s, icon_color, 2.2 * s, true)
	draw_circle(center + Vector2(0.9, 6.0) * s, 1.4 * s, icon_color)


func _draw_plus(center: Vector2, s: float, with_vertical: bool) -> void:
	draw_line(center + Vector2(-7.0, 0.0) * s, center + Vector2(7.0, 0.0) * s, icon_color, 3.4 * s, true)
	if with_vertical:
		draw_line(center + Vector2(0.0, -7.0) * s, center + Vector2(0.0, 7.0) * s, icon_color, 3.4 * s, true)


func _draw_chevron(center: Vector2, s: float, direction: float) -> void:
	draw_polyline(PackedVector2Array([
		center + Vector2(-3.0 * direction, -7.5) * s,
		center + Vector2(3.5 * direction, 0.0) * s,
		center + Vector2(-3.0 * direction, 7.5) * s,
	]), icon_color, 3.2 * s, true)


func _draw_spinner(center: Vector2, s: float) -> void:
	draw_arc(center, 8.5 * s, _spin_angle, _spin_angle + TAU * 0.72, 30, icon_color, 3.0 * s, true)


func _ellipse_points(center: Vector2, radii: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in 33:
		var angle := TAU * float(index) / 32.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points
