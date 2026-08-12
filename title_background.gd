extends Node3D

# ============================================================
# TitleBackground
# Loads NukeTownMap geometry into a SubViewport, spawns 3
# characters doing idle animations, and slowly pans the camera.
# No game logic — purely visual.
# ============================================================

const VISUAL_SCENE = preload("res://models/player_v2/player_v2_visual.tscn")

# Camera pan settings
const PAN_SPEED      = 0.04   # radians per second
const PAN_MIN_Y      = -0.3
const PAN_MAX_Y      = 0.3
const CAM_DISTANCE   = 14.0
const CAM_HEIGHT     = 3.5
const CAM_LOOK_OFFSET = Vector3(0, 1.2, 0)

var _pan_angle   : float = 0.0
var _pan_dir     : float = 1.0
var _characters  : Array = []

@onready var _camera : Camera3D = $Camera3D

func _ready():
	_pan_angle = 0.0
	_spawn_characters()

func _spawn_characters():
	# Spawn positions hand-placed to look good in front of camera.
	var positions = [
		Vector3(-3.0, 0.0,  2.0),
		Vector3( 0.0, 0.0,  0.0),
		Vector3( 3.0, 0.0,  2.0),
	]

	for i in positions.size():
		var char_instance = VISUAL_SCENE.instantiate()
		char_instance.position = positions[i]
		# Face roughly toward camera.
		char_instance.rotation.y = PI
		char_instance.set("skin_id", str(PlayerPrefs.get_setting("character_skin_id")) \
			if i == 1 else PlayerSkinRegistry.skin_id_at(i * 4))
		char_instance.set("build_animation_library", false)
		add_child(char_instance)

		var anim_player = char_instance.ensure_animations(["idle"])
		if anim_player == null:
			_characters.append(null)
			continue

		if anim_player.has_animation("idle"):
			anim_player.play("idle")
			anim_player.advance(0.0)
		_characters.append(char_instance)

func _process(delta):
	_pan_angle += PAN_SPEED * _pan_dir * delta

	if _pan_angle > PAN_MAX_Y:
		_pan_angle = PAN_MAX_Y
		_pan_dir = -1.0
	elif _pan_angle < PAN_MIN_Y:
		_pan_angle = PAN_MIN_Y
		_pan_dir = 1.0

	var cam_x = sin(_pan_angle) * CAM_DISTANCE
	var cam_z = cos(_pan_angle) * CAM_DISTANCE
	_camera.global_position = Vector3(cam_x, CAM_HEIGHT, cam_z)
	_camera.look_at(CAM_LOOK_OFFSET, Vector3.UP)
