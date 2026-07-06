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
