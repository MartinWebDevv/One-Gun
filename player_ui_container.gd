extends Control

@export var player_path: NodePath
var player = null
var _owner_player = null
var throw_arc_overlay: ThrowArcOverlay = null
var flash_camera_overlay: FlashCameraOverlay = null
var flash_blind_overlay: FlashBlindOverlay = null

func _ready():
	await get_tree().process_frame
	if player_path != NodePath(""):
		player = get_node(player_path)
	_owner_player = player

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
	throw_arc_overlay = ThrowArcOverlay.new()
	throw_arc_overlay.name = "ThrowArcOverlay"
	add_child(throw_arc_overlay)
	throw_arc_overlay.set_player(player)
	flash_camera_overlay = FlashCameraOverlay.new()
	flash_camera_overlay.name = "FlashCameraOverlay"
	add_child(flash_camera_overlay)
	flash_camera_overlay.set_player(player)
	flash_blind_overlay = FlashBlindOverlay.new()
	flash_blind_overlay.name = "FlashBlindOverlay"
	add_child(flash_blind_overlay)
	flash_blind_overlay.set_player(player)

func _process(_delta: float) -> void:
	if _owner_player == null:
		return
	var display_player = _owner_player
	var spectator = _owner_player.get("_spectator")
	if bool(_owner_player.get("is_eliminated")) and spectator != null \
			and spectator.has_method("get_follow_target"):
		var target = spectator.get_follow_target()
		if target != null:
			display_player = target
	if display_player == player:
		return
	player = display_player
	for child in get_children():
		if child.has_method("set_player"):
			child.set_player(player)
