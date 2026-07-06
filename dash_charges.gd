extends HBoxContainer

const PIP_GAP := 6

var player = null
var pip_template: ColorRect = null

func _ready():
	anchor_left = 0
	anchor_top = 1
	anchor_right = 0
	anchor_bottom = 1
	offset_left = 20
	offset_top = -75
	offset_right = 130
	offset_bottom = -45
	add_theme_constant_override("separation", PIP_GAP)
	if get_child_count() > 0 and get_child(0) is ColorRect:
		pip_template = get_child(0).duplicate()

func set_player(p):
	player = p
	_rebuild_pips()

func _rebuild_pips():
	if player == null or not ("max_dash_charges" in player):
		return
	if pip_template == null or not is_instance_valid(pip_template):
		return
	var target_count = player.max_dash_charges
	while get_child_count() < target_count:
		var pip = pip_template.duplicate()
		add_child(pip)
	while get_child_count() > target_count:
		var extra = get_child(get_child_count() - 1)
		remove_child(extra)
		extra.queue_free()

func _process(_delta):
	if player == null:
		return
	if get_child_count() != player.max_dash_charges:
		_rebuild_pips()
	for i in get_child_count():
		var pip = get_child(i)
		if i < player.dash_charges:
			pip.color = Color.CYAN
		else:
			pip.color = Color(0.2, 0.2, 0.2)
