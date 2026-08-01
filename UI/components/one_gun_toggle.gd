class_name OneGunToggle
extends Button

# Physical toggle switch matching the Player Settings concepts: dark pill
# track, cream knob, gold fill + "ON" label when enabled. Drawn procedurally
# so it stays crisp at any UI scale.

const TRACK_SIZE := Vector2(92.0, 38.0)

var _knob_t := 0.0  # 0 = off (left), 1 = on (right)
var _knob_tween: Tween


func _init() -> void:
	# toggle_mode must exist before callers assign button_pressed.
	toggle_mode = true


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = TRACK_SIZE
	_knob_t = 1.0 if button_pressed else 0.0
	# The switch is fully custom-drawn; blank out the themed button chrome.
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, empty)
	add_theme_stylebox_override("focus",
		OneGunUI.focus_ring(OneGunUI.style_box(Color.TRANSPARENT, Color.TRANSPARENT, 999, 0)))
	toggled.connect(_on_toggled)
	mouse_entered.connect(func() -> void:
		if not disabled:
			AudioManager.play_hover()
		queue_redraw())
	mouse_exited.connect(queue_redraw)


func _on_toggled(now_on: bool) -> void:
	AudioManager.play_click()
	if _knob_tween != null and _knob_tween.is_valid():
		_knob_tween.kill()
	_knob_tween = create_tween()
	_knob_tween.tween_method(_set_knob_t, _knob_t, 1.0 if now_on else 0.0, 0.16)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_knob_t(value: float) -> void:
	_knob_t = value
	queue_redraw()


func _draw() -> void:
	var track := Rect2(Vector2.ZERO, size)
	var radius := size.y * 0.5
	var on_mix := _knob_t

	var track_off := OneGunUI.color("well")
	var track_on := OneGunUI.color("gold").darkened(0.08)
	var track_color := track_off.lerp(track_on, on_mix)
	if disabled:
		track_color = Color(track_color, 0.45)
	draw_style_box(_pill(track_color, radius), track)

	var border_color := OneGunUI.color("border").lerp(OneGunUI.color("gold").lightened(0.15), on_mix)
	if disabled:
		border_color = Color(border_color, 0.45)
	draw_style_box(_pill_border(border_color, radius), track)

	var knob_radius := radius - 6.0
	var knob_x := lerpf(radius, size.x - radius, _knob_t)
	var knob_color := OneGunUI.color("text").lerp(Color(1.0, 0.98, 0.9), on_mix)
	if disabled:
		knob_color = OneGunUI.color("muted")
	draw_circle(Vector2(knob_x, size.y * 0.5), knob_radius + (1.5 if is_hovered() and not disabled else 0.0), knob_color)

	var font := OneGunUI.font_bold()
	if font == null:
		return
	var label := "ON" if button_pressed else "OFF"
	var label_color := OneGunUI.color("ink") if button_pressed else OneGunUI.color("muted")
	if disabled:
		label_color = Color(label_color, 0.6)
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, OneGunUI.TEXT_S)
	# Label sits on the side the knob vacated: ON (knob right) -> text left.
	var text_x := 14.0 if button_pressed else size.x - text_size.x - 14.0
	draw_string(font, Vector2(text_x, size.y * 0.5 + text_size.y * 0.32), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, OneGunUI.TEXT_S, label_color)


func _pill(bg: Color, radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(int(radius))
	return style


func _pill_border(border: Color, radius: float) -> StyleBoxFlat:
	var style := _pill(Color.TRANSPARENT, radius)
	style.border_color = border
	style.set_border_width_all(OneGunUI.BORDER_THIN)
	return style
