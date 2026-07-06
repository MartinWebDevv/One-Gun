extends Label

@export var is_second_screen := false

func _ready():
	add_theme_constant_override("line_spacing", 8)
	anchor_top = 0
	anchor_bottom = 0
	offset_top = 20
	offset_bottom = 260
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	if is_second_screen:
		if not GameConfig.split_screen_enabled:
			visible = false
			return
		anchor_left = 0.5
		anchor_right = 0.5
		offset_left = 20
		offset_right = 400
	else:
		anchor_left = 0
		anchor_right = 0
		offset_left = 20
		offset_right = 400
