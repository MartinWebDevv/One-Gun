class_name OneGunCabinet
extends PanelContainer

# Physical cabinet frame: layered metallic-gold rim around a navy face with
# a warm inner highlight, plus corner bolts (packet §4 materials). Three
# variants:
#   CABINET — gold outer rim + bolts (top-level panels, overlays)
#   SECTION — raised navy panel with a thin gold border (sections in a face)
#   WELL    — recessed dark content well (lists, previews, inputs)
# Add content via get_content().

enum Variant { CABINET, SECTION, WELL }

@export var variant: Variant = Variant.CABINET
@export var content_padding: int = OneGunUI.SPACE_L
@export var show_bolts: bool = true

var _content: MarginContainer
var _face: PanelContainer


func _ready() -> void:
	_build()
	queue_redraw()


func get_content() -> MarginContainer:
	return _content


func _build() -> void:
	_content = MarginContainer.new()
	_content.name = "Content"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_content.add_theme_constant_override(side, content_padding)

	match variant:
		Variant.CABINET:
			# Outer rim: gold panel whose padding forms the visible metal edge.
			var rim := OneGunUI.style_box(
				OneGunUI.color("gold").darkened(0.06),
				OneGunUI.color("gold_edge"),
				OneGunUI.RADIUS_CABINET, OneGunUI.BORDER_THIN, 14)
			rim.set_content_margin_all(OneGunUI.CABINET_RIM)
			add_theme_stylebox_override("panel", rim)

			# Inner face: deep navy with a faint warm highlight border.
			_face = PanelContainer.new()
			_face.name = "Face"
			var face_style := OneGunUI.style_box(
				OneGunUI.color("face").darkened(0.12),
				Color(1.0, 0.92, 0.75, 0.16),
				OneGunUI.RADIUS_CABINET - 5, 1)
			_face.add_theme_stylebox_override("panel", face_style)
			add_child(_face)
			_face.add_child(_content)
		Variant.SECTION:
			var section := OneGunUI.style_box(
				OneGunUI.color("face_raised"),
				OneGunUI.color("gold").darkened(0.25),
				OneGunUI.RADIUS_SECTION, OneGunUI.BORDER_THIN, 4)
			add_theme_stylebox_override("panel", section)
			add_child(_content)
		Variant.WELL:
			add_theme_stylebox_override("panel", OneGunUI.well_style(OneGunUI.RADIUS_SECTION))
			add_child(_content)


func _draw() -> void:
	if variant != Variant.CABINET or not show_bolts:
		return
	# Small corner bolts on the gold rim support the physical-cabinet look.
	var inset := OneGunUI.RADIUS_CABINET * 0.82
	var bolt_color := OneGunUI.color("gold_edge").lightened(0.1)
	var shine := Color(1.0, 0.95, 0.8, 0.55)
	for corner in [
		Vector2(inset, inset),
		Vector2(size.x - inset, inset),
		Vector2(inset, size.y - inset),
		Vector2(size.x - inset, size.y - inset),
	]:
		draw_circle(corner, 3.4, bolt_color)
		draw_circle(corner + Vector2(-0.8, -0.8), 1.3, shine)
