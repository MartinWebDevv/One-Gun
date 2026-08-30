class_name OneGunButton
extends Button

# Themed action button for the redesigned menus. Six semantic variants
# (packet §4 core palette) with the full interaction-state set: normal,
# hover, focus, pressed, disabled. Focus combines a cyan ring + glow so it
# is never communicated by color alone; hover adds a restrained scale.

const VARIANTS := ["gold", "navy", "purple", "blue", "green", "red"]

@export_enum("gold", "navy", "purple", "blue", "green", "red") var variant: String = "navy":
	set(value):
		variant = value
		if is_inside_tree():
			_apply_styles()
@export var font_size: int = OneGunUI.TEXT_M
@export var play_sounds: bool = true

var _rest_scale := Vector2.ONE
var _hover_tween: Tween


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	_apply_styles()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	pressed.connect(_on_pressed_sound)
	resized.connect(_update_pivot)
	_update_pivot()


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _apply_styles() -> void:
	var accent: Color
	match variant:
		"gold":
			accent = OneGunUI.color("gold")
		"purple":
			accent = OneGunUI.color("purple")
		"blue":
			accent = OneGunUI.color("blue")
		"green":
			accent = OneGunUI.color("green")
		"red":
			accent = OneGunUI.color("red")
		_:  # navy
			accent = OneGunUI.color("cyan")

	# Every semantic color shares one idle construction. Hue communicates the
	# action family; opacity, border weight, depth, and label contrast no longer
	# jump between filled, blacked-out, and washed-out buttons.
	var tint_strength := 0.10 if variant == "navy" else 0.30
	var bg := OneGunUI.color("face_raised").lerp(accent, tint_strength)
	var border := Color(accent, 0.86)
	var text_color := OneGunUI.color("text_bright")
	var text_hover := OneGunUI.color("text_bright")

	var radius := OneGunUI.RADIUS_BUTTON
	var margin := 14.0
	var normal := OneGunUI.style_box(bg, border, radius, OneGunUI.BORDER_THIN, 4, margin)
	var hover := OneGunUI.style_box(bg.lightened(0.12), border.lightened(0.1), radius, OneGunUI.BORDER_THIN, 5, margin)
	var pressed_style := OneGunUI.style_box(bg.darkened(0.18), border, radius, OneGunUI.BORDER_THIN, 0, margin)
	pressed_style.content_margin_top = margin + 2.0
	pressed_style.content_margin_bottom = margin - 2.0
	var disabled := OneGunUI.style_box(
		Color(OneGunUI.color("well").lerp(accent, 0.10), 0.86),
		Color(accent, 0.28), radius, OneGunUI.BORDER_THIN, 0, margin)

	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed_style)
	add_theme_stylebox_override("focus", OneGunUI.focus_ring(normal))
	add_theme_stylebox_override("disabled", disabled)

	add_theme_color_override("font_color", text_color)
	add_theme_color_override("font_hover_color", text_hover)
	add_theme_color_override("font_pressed_color", text_color.darkened(0.15))
	add_theme_color_override("font_focus_color", text_color)
	add_theme_color_override("font_hover_pressed_color", text_color)
	add_theme_color_override("font_disabled_color", OneGunUI.color("muted"))
	add_theme_font_size_override("font_size", font_size)
	var font := OneGunUI.font_bold()
	if font != null:
		add_theme_font_override("font", font)


func _on_mouse_entered() -> void:
	if disabled:
		return
	if play_sounds:
		AudioManager.play_hover()
	_tween_scale(_rest_scale * OneGunUI.HOVER_SCALE)


func _on_mouse_exited() -> void:
	_tween_scale(_rest_scale)


func _on_pressed_sound() -> void:
	if play_sounds:
		AudioManager.play_click()


func _tween_scale(target: Vector2) -> void:
	pivot_offset = size * 0.5
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	var accessibility = get_node_or_null("/root/AccessibilityManager")
	if accessibility != null and accessibility.reduced_motion_enabled():
		scale = target
		return
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", target, 0.12)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
