extends HBoxContainer

var player = null

func _ready():
	visible = false
	move_child($AmmoLabel, 0)
	anchor_left = 1
	anchor_top = 1
	anchor_right = 1
	anchor_bottom = 1
	offset_left = -220
	offset_top = -70
	offset_right = -20
	offset_bottom = -20
	# Weapon pill styling: rounded chip, bold text.
	alignment = BoxContainer.ALIGNMENT_END
	var lbl = $AmmoLabel
	lbl.add_theme_stylebox_override("normal", ThemeManager.pill(Color(0.06, 0.07, 0.12, 0.85), ThemeManager.BORDER, 1))
	lbl.add_theme_font_size_override("font_size", 18)
	ThemeManager.embolden(lbl)

func set_player(p):
	player = p

func _process(_delta):
	if player == null:
		return
	visible = player.holding_gun
	if not visible:
		return
	var hold_point = player.get_hold_point()
	if hold_point.get_child_count() == 0:
		return
	var gun = hold_point.get_child(0)
	if gun.can_fire:
		$AmmoLabel.text = "GUN  •  READY"
		$AmmoLabel.add_theme_color_override("font_color", ThemeManager.ACCENT_GOLD)
	else:
		$AmmoLabel.text = "GUN  •  RELOADING…"
		$AmmoLabel.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
