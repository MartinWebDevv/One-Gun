extends HBoxContainer

var player = null

func _ready():
	visible = false
	move_child($NameLabel, 0)
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
	$NameLabel.add_theme_stylebox_override("normal", ThemeManager.pill(Color(0.06, 0.07, 0.12, 0.85), ThemeManager.BORDER, 1))
	$NameLabel.add_theme_font_size_override("font_size", 18)
	ThemeManager.embolden($NameLabel)

func set_player(p):
	player = p

func _process(_delta):
	if player == null:
		return
	var weapon_active = not ("active_slot" in player) or player.active_slot == "weapon"
	visible = player.held_melee_weapon != null and weapon_active
	if not visible:
		return
	var weapon = player.held_melee_weapon
	if weapon.has_method("get_display_name"):
		$NameLabel.text = weapon.get_display_name()
	else:
		$NameLabel.text = "Melee"
