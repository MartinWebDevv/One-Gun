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

func set_player(p):
	player = p

func _process(_delta):
	if player == null:
		return
	visible = "held_item" in player and player.held_item != null
	if not visible:
		return
	var item = player.held_item
	if item.has_method("get_display_name"):
		$NameLabel.text = item.get_display_name()
	else:
		$NameLabel.text = "Item"
