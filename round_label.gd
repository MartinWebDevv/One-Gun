extends Label

@export var is_second_screen := false

func _ready():
	anchor_top = 0.5
	anchor_bottom = 0.5
	anchor_left = 0.5
	anchor_right = 0.5
	offset_top = -80
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if is_second_screen:
		if not GameConfig.split_screen_enabled:
			visible = false
			return
		anchor_left = 0.5
		anchor_right = 1.0
	else:
		if GameConfig.split_screen_enabled:
			anchor_left = 0.0
			anchor_right = 0.5
		else:
			anchor_left = 0.0
			anchor_right = 1.0
