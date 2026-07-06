extends ProgressBar

var player = null

func _ready():
	anchor_left = 0
	anchor_top = 1
	anchor_right = 0
	anchor_bottom = 1
	offset_left = 20
	offset_top = -40
	offset_right = 220
	offset_bottom = -20

func set_player(p):
	player = p

func _process(_delta):
	if player:
		value = player.stamina
