extends ProgressBar

var player = null

var _display_value := 100.0
var _was_empty := false
var _caption: Label = null
var _base_x := 20.0

func _ready():
	anchor_left = 0
	anchor_top = 1
	anchor_right = 0
	anchor_bottom = 1
	offset_left = 20
	offset_top = -40
	offset_right = 220
	offset_bottom = -20
	show_percentage = false
	_base_x = offset_left

	# Kit styling: dark rounded track, gold fill.
	add_theme_stylebox_override("background", ThemeManager.panel(
		Color(ThemeManager.BG_INPUT.r, ThemeManager.BG_INPUT.g, ThemeManager.BG_INPUT.b, 0.75),
		ThemeManager.BORDER, 8, 1))
	var fill = ThemeManager.panel(ThemeManager.ACCENT_GOLD, Color.TRANSPARENT, 8, 0)
	fill.shadow_size = 0
	add_theme_stylebox_override("fill", fill)

	_caption = Label.new()
	_caption.text = "STAMINA"
	_caption.add_theme_font_size_override("font_size", 10)
	_caption.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	_caption.position = Vector2(2, -14)
	ThemeManager.embolden(_caption)
	add_child(_caption)

func set_player(p):
	player = p
	if p != null and "stamina" in p:
		_display_value = p.stamina

func _process(delta):
	if player == null:
		return
	# Smooth toward the real value instead of snapping.
	_display_value = lerpf(_display_value, player.stamina, minf(delta * 12.0, 1.0))
	value = _display_value

	# Flash + tiny shake the moment stamina bottoms out.
	var empty: bool = player.stamina <= 0.01
	if empty and not _was_empty:
		ThemeManager.flash(self, ThemeManager.DANGER, 0.4)
		var tw = create_tween()
		tw.tween_property(self, "offset_left", _base_x - 3.0, 0.04)
		tw.tween_property(self, "offset_left", _base_x + 3.0, 0.04)
		tw.tween_property(self, "offset_left", _base_x, 0.04)
	_was_empty = empty
