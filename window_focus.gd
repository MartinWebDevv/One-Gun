extends Node
## Window focus gates local input without pausing the shared simulation.
signal focus_changed(active: bool)
var active := true
var saved_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var automated := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100000
	automated = DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--hideout-test")
	get_tree().node_added.connect(_node_added)
	if not automated: set_active(get_window().has_focus())

func _node_added(node: Node) -> void:
	if node != self and node.get_parent() == get_tree().root:
		get_tree().root.move_child.call_deferred(self, -1)

func _notification(what: int) -> void:
	if automated or not is_inside_tree(): return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: set_active(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: set_active(true)

func set_active(value: bool) -> void:
	if active == value: return
	active = value
	_release_actions()
	if not active:
		saved_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = saved_mouse_mode
	focus_changed.emit(active)

func _input(_event: InputEvent) -> void:
	if not active:
		_release_actions()
		get_viewport().set_input_as_handled()

func _release_actions() -> void:
	for action in InputMap.get_actions():
		if Input.is_action_pressed(action): Input.action_release(action)
