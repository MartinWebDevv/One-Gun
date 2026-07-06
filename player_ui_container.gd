extends Control

@export var player_path: NodePath
var player = null

func _ready():
	await get_tree().process_frame
	if player_path != NodePath(""):
		player = get_node(player_path)

	var is_player2_ui = player != null and "is_player2" in player and player.is_player2

	if is_player2_ui and not GameConfig.split_screen_enabled:
		visible = false
		return

	if not GameConfig.split_screen_enabled:
		anchor_left = 0
		anchor_right = 1

	for child in get_children():
		if child.has_method("set_player"):
			child.set_player(player)
