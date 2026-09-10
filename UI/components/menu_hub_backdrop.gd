class_name MenuHubBackdrop
extends Control

# Shared low-cost presentation layer for the three player-hub screens. Blender
# supplies one flat backdrop texture; this node adds only a tint and a small,
# quality-scaled field of slow dust lights. It never creates a second 3D world.

enum Variant { PRIZE_COUNTER, LOCKER, PROFILE }

const REDRAW_INTERVAL := 1.0 / 12.0
const PARTICLE_COUNTS := {
	"low": 14,
	"medium": 22,
	"high": 32,
	"ultra": 38,
}

var _texture: Texture2D
var _variant := Variant.PRIZE_COUNTER
var _motes: Array[Dictionary] = []
var _elapsed := 0.0
var _redraw_elapsed := 0.0
var _animated := true


func configure(texture: Texture2D, variant: Variant) -> void:
	_texture = texture
	_variant = variant


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_build_texture_layer()
	_build_motes()
	_animated = not _reduced_motion_enabled()
	set_process(_animated)
	resized.connect(queue_redraw)
	queue_redraw()


func _build_texture_layer() -> void:
	var texture_rect := TextureRect.new()
	texture_rect.name = "BlenderBackdrop"
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_rect.texture = _texture
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(texture_rect)

	var grade := ColorRect.new()
	grade.name = "AtmosphereGrade"
	grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grade.color = _grade_color()
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grade)


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
	for mote in _motes:
		var position := Vector2(float(mote["x"]) * size.x,
			float(mote["y"]) * size.y)
		var pulse := 0.72
		if _animated:
			pulse = 0.54 + 0.46 * (0.5 + 0.5 * sin(
				_elapsed * float(mote["speed"]) + float(mote["phase"])))
		var mote_color: Color = mote["color"]
		var alpha := float(mote["alpha"]) * pulse
		var radius := float(mote["radius"])
		draw_circle(position, radius * 4.0,
			Color(mote_color.r, mote_color.g, mote_color.b, alpha * 0.045))
		draw_circle(position, radius * 1.8,
			Color(mote_color.r, mote_color.g, mote_color.b, alpha * 0.16))
		draw_circle(position, radius,
			Color(mote_color.r, mote_color.g, mote_color.b, alpha))


func _build_motes() -> void:
	_motes.clear()
	var random := RandomNumberGenerator.new()
	random.seed = 109633 + _variant * 7919
	var quality := "high"
	var manager := get_node_or_null("/root/GraphicsQualityManager")
	if manager != null and manager.has_method("effects_quality"):
		quality = str(manager.call("effects_quality"))
	var count := int(PARTICLE_COUNTS.get(quality, PARTICLE_COUNTS["high"]))
	var colors := _mote_colors()
	for index in count:
		_motes.append({
			"x": random.randf_range(0.025, 0.975),
			"y": random.randf_range(0.055, 0.955),
			"radius": random.randf_range(0.65, 1.55),
			"speed": random.randf_range(0.34, 0.86),
			"phase": random.randf_range(0.0, TAU),
			"alpha": random.randf_range(0.18, 0.42),
			"color": colors[index % colors.size()],
		})


func _grade_color() -> Color:
	return Color(OneGunUI.color("face"), 0.68)

func _mote_colors() -> Array[Color]:
	return [OneGunUI.color("gold"),OneGunUI.color("green")]


func _reduced_motion_enabled() -> bool:
	var accessibility := get_node_or_null("/root/AccessibilityManager")
	return accessibility != null \
		and accessibility.has_method("reduced_motion_enabled") \
		and bool(accessibility.call("reduced_motion_enabled"))
