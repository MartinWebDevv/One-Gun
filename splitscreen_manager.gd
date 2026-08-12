extends CanvasLayer

@export var player1_path: NodePath
@export var player2_path: NodePath

@onready var _viewport_container_1: SubViewportContainer = $ViewportRow/SubViewportContainer1
@onready var _viewport_container_2: SubViewportContainer = $ViewportRow/SubViewportContainer2
@onready var _viewport_2: SubViewport = $ViewportRow/SubViewportContainer2/SubViewport2
@onready var _viewport_camera_1: Camera3D = $ViewportRow/SubViewportContainer1/SubViewport1/ViewportCamera1
@onready var _viewport_camera_2: Camera3D = $ViewportRow/SubViewportContainer2/SubViewport2/ViewportCamera2

var player1: Node = null
var player2: Node = null
var _split_screen_active := false

func _ready() -> void:
	if player1_path != NodePath(""):
		player1 = get_node_or_null(player1_path)
	if player2_path != NodePath(""):
		player2 = get_node_or_null(player2_path)

	_split_screen_active = GameConfig.split_screen_enabled
	if not _split_screen_active:
		_viewport_container_2.visible = false
		_viewport_container_1.anchor_right = 1.0
		# A hidden SubViewport with UPDATE_ALWAYS still renders a complete second
		# 3D view. Disable it in solo play instead of paying nearly splitscreen cost.
		_viewport_2.render_target_update_mode = SubViewport.UPDATE_DISABLED
		player2 = null


func _process(_delta: float) -> void:
	_sync_camera(player1, _viewport_camera_1)
	if _split_screen_active:
		_sync_camera(player2, _viewport_camera_2)


func _sync_camera(player: Node, viewport_camera: Camera3D) -> void:
	if not is_instance_valid(player) or not player.has_method("get_camera"):
		return
	var source_camera := player.get_camera() as Camera3D
	if not is_instance_valid(source_camera):
		return
	viewport_camera.global_transform = source_camera.global_transform
	viewport_camera.fov = source_camera.fov
	# Per-view combat presentation (Reach ring and gun-holder identity tags)
	# uses reserved visual layers on the source camera. Mirror the mask as well
	# as the transform so P1 and P2 cannot see each other's private overlays.
	viewport_camera.cull_mask = source_camera.cull_mask
