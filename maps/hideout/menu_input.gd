extends Node
## Keep locomotion out of UI navigation while the pointer operates Hideout menus.
const MOVEMENT = ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "dash"]
var world: Node3D

func _ready() -> void:
	process_physics_priority = -100

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(world.pilot): return
	var typing: bool = world._menu_captures_input()
	if world.pilot.menu_text_input_active != typing:
		world._sync_controls()
	# Settings/Locker may reapply player preferences while their overlay is open.
	if world._menu_is_open() and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	if not world._menu_is_open() or not is_instance_valid(world.pilot): return
	var typing: bool = world._menu_captures_input()
	world.pilot.menu_text_input_active = typing
	if typing: return
	# Pointer events belong to controls. Physical movement keys/sticks still reach
	# Input's action state, but must never also press a focused button or slider.
	if event is InputEventMouse: return
	for suffix in MOVEMENT:
		var action: String = world.pilot.input_prefix + "_" + suffix
		if InputMap.has_action(action) and event.is_action(action):
			get_viewport().set_input_as_handled()
			return
