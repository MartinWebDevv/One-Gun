extends CanvasLayer

@export var player1_path: NodePath
@export var player2_path: NodePath

var player1 = null
var player2 = null

func _ready():
	if player1_path != NodePath(""):
		player1 = get_node(player1_path)
	if player2_path != NodePath(""):
		player2 = get_node(player2_path)

	if not GameConfig.split_screen_enabled:
		$ViewportRow/SubViewportContainer2.visible = false
		$ViewportRow/SubViewportContainer1.anchor_right = 1.0

func _process(_delta):
	if player1 != null:
		var cam1 = player1.get_camera()
		$ViewportRow/SubViewportContainer1/SubViewport1/ViewportCamera1.global_transform = cam1.global_transform
		$ViewportRow/SubViewportContainer1/SubViewport1/ViewportCamera1.fov = cam1.fov
	if player2 != null:
		var cam2 = player2.get_camera()
		$ViewportRow/SubViewportContainer2/SubViewport2/ViewportCamera2.global_transform = cam2.global_transform
		$ViewportRow/SubViewportContainer2/SubViewport2/ViewportCamera2.fov = cam2.fov
