extends HBoxContainer

var player = null



func _ready():
	visible = false
	anchor_left = 1
	anchor_top = 0
	anchor_right = 1
	anchor_bottom = 0
	offset_left = -220
	offset_top = 20
	offset_right = -20
	offset_bottom = 70
	# Item pill styling: rounded chip, bold cyan text (items are the cyan family).
	alignment = BoxContainer.ALIGNMENT_END
	$NameLabel.add_theme_stylebox_override("normal", ThemeManager.pill(Color(0.06, 0.07, 0.12, 0.85), ThemeManager.BORDER, 1))
	$NameLabel.add_theme_font_size_override("font_size", 16)
	$NameLabel.add_theme_color_override("font_color", ThemeManager.ACCENT_CYAN)
	ThemeManager.embolden($NameLabel)

func set_player(p):
	player = p

func _process(_delta):
	if player == null:
		return
	var item = null
	if "active_slot" in player:
		if player.active_slot == "item1" and "held_item_1" in player:
			item = player.held_item_1
		elif player.active_slot == "item2" and "held_item_2" in player:
			item = player.held_item_2
	visible = item != null
	if not visible:
		return
	if item.has_method("get_display_name"):
		$NameLabel.text = item.get_display_name() + "  •  THROW"
	else:
		$NameLabel.text = "Item  •  THROW"
