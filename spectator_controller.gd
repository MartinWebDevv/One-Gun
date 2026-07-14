extends Node

# ============================================================
# SpectatorController
#
# Activates after a player's death animation finishes.
# Two modes:
#   FOLLOW — rides a living player's third-person camera
#   FREE   — floating camera the spectator flies manually
#
# Toggle with jump button. Cycle follow targets with left/right.
# splitscreen_manager.gd picks up the spectator camera
# automatically via get_camera() override on the player node.
# ============================================================

enum Mode { FOLLOW, FREE }

const FREE_CAM_SPEED     = 12.0
const FREE_CAM_FAST_MULT = 3.0
const FREE_CAM_SENS      = 0.003

var _player: CharacterBody3D = null
var _input_prefix: String = "p1"
var _use_gamepad: bool = false
var _mode: Mode = Mode.FOLLOW

var _follow_targets: Array = []
var _follow_index: int = 0

var _free_cam: Camera3D = null
var _free_cam_pivot: Node3D = null
var _free_cam_arm: Node3D = null

var _mode_label: Label = null

func setup(player: CharacterBody3D):
	_player = player
	_input_prefix = player.input_prefix
	_use_gamepad = player.use_gamepad_look

	_build_free_cam()
	_build_ui()
	_refresh_follow_targets()

	if _follow_targets.size() > 0:
		_set_mode(Mode.FOLLOW)
	else:
		_set_mode(Mode.FREE)

	set_process(true)
	set_process_input(true)

func _build_free_cam():
	_free_cam_pivot = Node3D.new()
	_free_cam_pivot.name = "SpectatorPivot"
	_free_cam_arm = Node3D.new()
	_free_cam_arm.name = "SpectatorArm"
	_free_cam = Camera3D.new()
	_free_cam.name = "SpectatorCamera"
	_free_cam.fov = 75.0

	_free_cam_arm.add_child(_free_cam)
	_free_cam_pivot.add_child(_free_cam_arm)

	_player.get_tree().current_scene.add_child(_free_cam_pivot)
	if _player != null:
		# global_position is only valid after the new pivot enters the scene tree.
		_free_cam_pivot.global_position = _player.global_position + Vector3(0, 2.0, 0)

func _build_ui():
	_mode_label = Label.new()
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label.add_theme_font_size_override("font_size", 14)
	_mode_label.modulate = Color(1.0, 1.0, 1.0, 0.75)
	_mode_label.anchor_left   = 0.5
	_mode_label.anchor_right  = 0.5
	_mode_label.anchor_top    = 1.0
	_mode_label.anchor_bottom = 1.0
	_mode_label.offset_left   = -300
	_mode_label.offset_right  = 300
	_mode_label.offset_top    = -40
	_mode_label.offset_bottom = -10

	var canvas = _player.get_tree().current_scene.get_node_or_null("OnlineHUD")
	if canvas == null:
		canvas = _player.get_node_or_null("../CanvasLayer")
	if canvas != null:
		canvas.add_child(_mode_label)
	else:
		_player.get_tree().current_scene.add_child(_mode_label)

func _refresh_follow_targets():
	_follow_targets.clear()
	var players = _player.get_tree().get_nodes_in_group("player")
	for p in players:
		if p == _player:
			continue
		if "is_eliminated" in p and p.is_eliminated:
			continue
		if "is_bot" in p and p.is_bot:
			continue
		_follow_targets.append(p)
	_follow_index = clamp(_follow_index, 0, max(0, _follow_targets.size() - 1))

func _set_mode(mode: Mode):
	_mode = mode
	if mode == Mode.FREE:
		if not _use_gamepad:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _follow_targets.size() > 0:
			var target = _follow_targets[_follow_index]
			_free_cam_pivot.global_position = target.global_position + Vector3(0, 2.5, 0)
	_update_ui()

func _update_ui():
	if _mode_label == null:
		return
	match _mode:
		Mode.FOLLOW:
			var name = ""
			if _follow_targets.size() > 0:
				var target = _follow_targets[_follow_index]
				name = target.get_display_name() if target.has_method("get_display_name") else target.name
			_mode_label.text = "👁 SPECTATING: " + name + "   [JUMP] Free Cam   [←→] Switch"
		Mode.FREE:
			_mode_label.text = "🎥 FREE CAM   [JUMP] Follow Cam   [WASD] Fly   [Mouse] Look"

func get_spectator_camera() -> Camera3D:
	match _mode:
		Mode.FOLLOW:
			if _follow_targets.size() > 0:
				var target = _follow_targets[_follow_index]
				if target.has_method("get_camera"):
					return target.get_camera()
		Mode.FREE:
			return _free_cam
	return _free_cam

func _input(event):
	if _player == null:
		return

	if event.is_action_pressed(_input_prefix + "_jump"):
		if _mode == Mode.FOLLOW:
			_set_mode(Mode.FREE)
		else:
			_refresh_follow_targets()
			_set_mode(Mode.FOLLOW)
		get_viewport().set_input_as_handled()
		return

	if _mode == Mode.FOLLOW:
		if event.is_action_pressed(_input_prefix + "_cycle_left") or event.is_action_pressed(_input_prefix + "_move_left"):
			_cycle_target(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(_input_prefix + "_cycle_right") or event.is_action_pressed(_input_prefix + "_move_right"):
			_cycle_target(1)
			get_viewport().set_input_as_handled()

	if _mode == Mode.FREE and not _use_gamepad:
		if event is InputEventMouseMotion:
			_free_cam_pivot.rotate_y(-event.relative.x * FREE_CAM_SENS)
			_free_cam_arm.rotate_x(-event.relative.y * FREE_CAM_SENS)
			_free_cam_arm.rotation.x = clamp(_free_cam_arm.rotation.x, -1.4, 1.4)
			get_viewport().set_input_as_handled()

func _cycle_target(direction: int):
	_refresh_follow_targets()
	if _follow_targets.size() == 0:
		return
	_follow_index = (_follow_index + direction) % _follow_targets.size()
	if _follow_index < 0:
		_follow_index += _follow_targets.size()
	_update_ui()

func _process(delta):
	if _player == null:
		return

	if _mode == Mode.FOLLOW:
		_refresh_follow_targets()
		_update_ui()
		return

	# Free cam movement
	var move = Vector3.ZERO
	var speed = FREE_CAM_SPEED

	if _use_gamepad:
		var stick = Input.get_vector(
			_input_prefix + "_move_left",
			_input_prefix + "_move_right",
			_input_prefix + "_move_forward",
			_input_prefix + "_move_back"
		)
		move += _free_cam_pivot.transform.basis * Vector3(stick.x, 0, stick.y)

		var look_x = Input.get_action_strength(_input_prefix + "_look_right") - Input.get_action_strength(_input_prefix + "_look_left")
		var look_y = Input.get_action_strength(_input_prefix + "_look_down") - Input.get_action_strength(_input_prefix + "_look_up")
		_free_cam_pivot.rotate_y(-look_x * 0.05)
		_free_cam_arm.rotate_x(-look_y * 0.05)
		_free_cam_arm.rotation.x = clamp(_free_cam_arm.rotation.x, -1.4, 1.4)

		if Input.is_action_pressed(_input_prefix + "_sprint"):
			speed *= FREE_CAM_FAST_MULT
	else:
		var input_dir = Input.get_vector(
			_input_prefix + "_move_left",
			_input_prefix + "_move_right",
			_input_prefix + "_move_forward",
			_input_prefix + "_move_back"
		)
		move += _free_cam_pivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y)

		if Input.is_action_pressed(_input_prefix + "_sprint"):
			speed *= FREE_CAM_FAST_MULT

	# Vertical movement: dash = down, interact = up
	if Input.is_action_pressed(_input_prefix + "_interact"):
		move.y += 1.0
	if Input.is_action_pressed(_input_prefix + "_dash"):
		move.y -= 1.0

	if move.length() > 0.01:
		_free_cam_pivot.global_position += move.normalized() * speed * delta

func cleanup():
	if _free_cam_pivot != null and is_instance_valid(_free_cam_pivot):
		_free_cam_pivot.queue_free()
	if _mode_label != null and is_instance_valid(_mode_label):
		_mode_label.queue_free()
	queue_free()
