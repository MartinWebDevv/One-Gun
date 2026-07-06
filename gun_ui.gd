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
	$AmmoLabel.text = "1/1" if gun.can_fire else "0/1"
