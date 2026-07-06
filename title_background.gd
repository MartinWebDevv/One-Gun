extends Node3D

# ============================================================
# TitleBackground
# Loads NukeTownMap geometry into a SubViewport, spawns 3
# characters doing idle animations, and slowly pans the camera.
# No game logic — purely visual.
# ============================================================

const PLAYER_SCENE   = "res://player.tscn"
const ANIM_SOURCE    = "res://models/playerAnimations/Dance.glb"
const IDLE_IDX       = 0   # Layer0 = idle

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

	var packed = load(ANIM_SOURCE)
	if packed == null:
		return

	for i in positions.size():
		# Instantiate the animation GLB as a visual-only character stand-in.
		var char_instance = packed.instantiate()
		char_instance.position = positions[i]
		# Face roughly toward camera.
		char_instance.rotation.y = PI
		add_child(char_instance)

		var anim_player = char_instance.find_child("AnimationPlayer", true, false)
		if anim_player == null:
			_characters.append(null)
			continue

		# Add idle animation to default library.
		if not anim_player.has_animation_library(""):
			anim_player.add_animation_library("", AnimationLibrary.new())
		var lib = anim_player.get_animation_library("")

		var source = packed.instantiate()
		var source_ap = source.find_child("AnimationPlayer", true, false)
		if source_ap != null:
			var anim_list = source_ap.get_animation_list()
			if anim_list.size() > IDLE_IDX:
				var anim = source_ap.get_animation(anim_list[IDLE_IDX]).duplicate()
				anim.loop_mode = Animation.LOOP_LINEAR
				if not lib.has_animation("idle"):
					lib.add_animation("idle", anim)
				anim_player.play("idle")
		source.queue_free()
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
