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
		$NameLabel.text = item.get_display_name()
	else:
		$NameLabel.text = "Item"
