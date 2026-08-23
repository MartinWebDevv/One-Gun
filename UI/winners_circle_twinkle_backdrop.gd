class_name WinnersCircleTwinkleBackdrop
extends Control

# A deliberately soft, low-cost results backdrop. The normalized star layout
# is deterministic, so resizing never causes distracting constellation jumps.

const REDRAW_INTERVAL := 1.0 / 15.0
const STAR_COLORS := [
	Color(1.0, 0.69, 0.22),
	Color(0.52, 0.68, 1.0),
	Color(0.88, 0.93, 1.0),
]
const FEATURE_POSITIONS := [
	Vector2(0.08, 0.055), Vector2(0.24, 0.075),
	Vector2(0.76, 0.070), Vector2(0.92, 0.048),
	Vector2(0.65, 0.24), Vector2(0.65, 0.49), Vector2(0.65, 0.70),
	Vector2(0.12, 0.925), Vector2(0.31, 0.955),
	Vector2(0.52, 0.930), Vector2(0.74, 0.955), Vector2(0.91, 0.925),
]

var _stars: Array[Dictionary] = []
var _elapsed := 0.0
var _redraw_elapsed := 0.0
var _animated := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_animated = not _reduced_motion_enabled()
	_build_star_field()
	resized.connect(queue_redraw)
	set_process(_animated)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	_redraw_elapsed += delta
	if _redraw_elapsed < REDRAW_INTERVAL:
		return
	_redraw_elapsed = 0.0
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	for star in _stars:
		var position := Vector2(
			float(star["x"]) * size.x, float(star["y"]) * size.y)
		var radius := float(star["radius"])
		var pulse := 0.78
		if _animated:
			pulse = 0.58 + 0.42 * (
				0.5 + 0.5 * sin(_elapsed * float(star["speed"]) + float(star["phase"])))
		var base_color: Color = star["color"]
		var alpha := float(star["alpha"]) * pulse
		if bool(star["feature"]):
			draw_circle(position, radius * 5.2,
				Color(base_color.r, base_color.g, base_color.b, alpha * 0.055))
		draw_circle(position, radius * 3.4,
			Color(base_color.r, base_color.g, base_color.b, alpha * 0.08))
		draw_circle(position, radius * 1.8,
			Color(base_color.r, base_color.g, base_color.b, alpha * 0.20))
		draw_circle(position, radius,
			Color(base_color.r, base_color.g, base_color.b, alpha))


func _build_star_field() -> void:
	_stars.clear()
	var random := RandomNumberGenerator.new()
	random.seed = 85625045
	var count := _star_count_for_quality()
	for index in range(count):
		var feature := index < FEATURE_POSITIONS.size()
		var star_position := Vector2.ZERO
		if feature:
			star_position = FEATURE_POSITIONS[index]
		else:
			match index % 5:
				0, 1:
					star_position = Vector2(
						random.randf_range(0.025, 0.975),
						random.randf_range(0.025, 0.105))
				2, 3:
					star_position = Vector2(
						random.randf_range(0.025, 0.975),
						random.randf_range(0.905, 0.978))
				_:
					star_position = Vector2(
						random.randf_range(0.025, 0.975),
						random.randf_range(0.12, 0.88))
		_stars.append({
			"x": star_position.x,
			"y": star_position.y,
			"radius": random.randf_range(1.35, 2.30) if feature \
				else random.randf_range(0.90, 1.90),
			"speed": random.randf_range(0.62, 1.32),
			"phase": random.randf_range(0.0, TAU),
			"alpha": random.randf_range(0.34, 0.58) if feature \
				else random.randf_range(0.20, 0.44),
			"color": STAR_COLORS[index % STAR_COLORS.size()],
			"feature": feature,
		})


func _star_count_for_quality() -> int:
	var manager := get_node_or_null("/root/GraphicsQualityManager")
	var quality := "high"
	if manager != null and manager.has_method("effects_quality"):
		quality = str(manager.call("effects_quality"))
	match quality:
		"low": return 26
		"medium": return 38
		_: return 52


func _reduced_motion_enabled() -> bool:
	var accessibility := get_node_or_null("/root/AccessibilityManager")
	return accessibility != null \
		and accessibility.has_method("reduced_motion_enabled") \
		and bool(accessibility.call("reduced_motion_enabled"))
