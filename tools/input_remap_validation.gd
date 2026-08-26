extends Node

## Verifies the complete PlayerPrefs -> InputMap path used by Player Settings.
## The test is disk-free and restores the live project bindings before exit.

var _failures: Array[String] = []

const CONTROLLER_ACTION_SUFFIXES := [
	"move_left", "move_right", "move_forward", "move_back",
	"look_left", "look_right", "look_up", "look_down",
	"jump", "interact", "fire", "throw", "dash", "sprint", "ads",
	"decoy_command", "cycle_left", "cycle_right",
]
const EXPECTED_CONTROLLER_BINDINGS := {
	"move_left": {"type": "joy_axis", "axis": JOY_AXIS_LEFT_X, "direction": -1},
	"move_right": {"type": "joy_axis", "axis": JOY_AXIS_LEFT_X, "direction": 1},
	"move_forward": {"type": "joy_axis", "axis": JOY_AXIS_LEFT_Y, "direction": -1},
	"move_back": {"type": "joy_axis", "axis": JOY_AXIS_LEFT_Y, "direction": 1},
	"look_left": {"type": "joy_axis", "axis": JOY_AXIS_RIGHT_X, "direction": -1},
	"look_right": {"type": "joy_axis", "axis": JOY_AXIS_RIGHT_X, "direction": 1},
	"look_up": {"type": "joy_axis", "axis": JOY_AXIS_RIGHT_Y, "direction": -1},
	"look_down": {"type": "joy_axis", "axis": JOY_AXIS_RIGHT_Y, "direction": 1},
	"jump": {"type": "joy_button", "button": JOY_BUTTON_A},
	"interact": {"type": "joy_button", "button": JOY_BUTTON_X},
	"fire": {"type": "joy_axis", "axis": JOY_AXIS_TRIGGER_RIGHT, "direction": 1},
	"throw": {"type": "joy_button", "button": JOY_BUTTON_Y},
	"dash": {"type": "joy_button", "button": JOY_BUTTON_B},
	"sprint": {"type": "joy_button", "button": JOY_BUTTON_LEFT_STICK},
	"ads": {"type": "joy_axis", "axis": JOY_AXIS_TRIGGER_LEFT, "direction": 1},
	"decoy_command": {"type": "joy_button", "button": JOY_BUTTON_DPAD_UP},
	"cycle_left": {"type": "joy_button", "button": JOY_BUTTON_LEFT_SHOULDER},
	"cycle_right": {"type": "joy_button", "button": JOY_BUTTON_RIGHT_SHOULDER},
}
const SHARED_CONTROLLER_ACTIONS := [
	"ui_left", "ui_right", "ui_up", "ui_down", "ui_accept", "ui_cancel",
	"pause", "scoreboard",
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var opening_settings := PlayerPrefs.settings.duplicate(true)
	var opening_split_screen: bool = GameConfig.split_screen_enabled

	# Audit the authored defaults before active-device filtering. Both human
	# prefixes need every controller path, including right-stick look.
	for prefix in ["p1", "p2"]:
		for suffix in CONTROLLER_ACTION_SUFFIXES:
			var action := "%s_%s" % [prefix, suffix]
			_expect(InputMap.has_action(action),
				"missing controller action: %s" % action)
			_expect(not PlayerPrefs.get_binding_descriptors(
				action, "gamepad", true).is_empty(),
				"missing default controller binding: %s" % action)
			_expect(_has_default_descriptor(
				action, EXPECTED_CONTROLLER_BINDINGS[suffix]),
				"incorrect default controller binding: %s" % action)
	for action in SHARED_CONTROLLER_ACTIONS:
		_expect(InputMap.has_action(action), "missing shared action: %s" % action)
		_expect(_has_group_event(action, "gamepad"),
			"shared action has no controller binding: %s" % action)
	_expect(_has_default_descriptor("ui_accept",
		{"type": "joy_button", "button": JOY_BUTTON_A}),
		"UI Select is not A / Cross")
	_expect(_has_default_descriptor("ui_cancel",
		{"type": "joy_button", "button": JOY_BUTTON_B}),
		"UI Back is not B / Circle")
	_expect(_has_default_descriptor("pause",
		{"type": "joy_button", "button": JOY_BUTTON_START}),
		"Pause is not Start / Menu")
	_expect(_has_default_descriptor("scoreboard",
		{"type": "joy_button", "button": JOY_BUTTON_BACK}),
		"Scoreboard is not Back / View")

	GameConfig.split_screen_enabled = false
	var overrides := {
		"p1_jump": {"keyboard_mouse": [{"type": "key", "code": int(KEY_F13)}]},
		"p1_fire": {"keyboard_mouse": [{"type": "mouse_button", "button": int(MOUSE_BUTTON_XBUTTON1)}]},
		"p2_fire": {"gamepad": [{"type": "joy_button", "button": int(JOY_BUTTON_DPAD_UP)}]},
		"p2_move_right": {"gamepad": [{"type": "joy_axis", "axis": int(JOY_AXIS_LEFT_X), "direction": 1}]},
	}
	PlayerPrefs.settings["input_device"] = "keyboard_mouse"
	PlayerPrefs.settings["input_overrides"] = overrides
	PlayerPrefs.apply_input_overrides()

	for action in overrides:
		_expect(InputMap.has_action(action), "missing remappable action: %s" % action)
		_expect(not InputMap.action_get_events(action).is_empty(),
			"override produced no InputMap event: %s" % action)

	await _expect_key_action(KEY_F13, "p1_jump", "p2_jump")
	await _expect_key_inactive(KEY_SPACE, "p1_jump")
	await _expect_mouse_action(MOUSE_BUTTON_XBUTTON1, "p1_fire")
	await _expect_joy_button_action(JOY_BUTTON_DPAD_UP, "p2_fire")
	await _expect_joy_axis_action(JOY_AXIS_LEFT_X, 0.9, "p2_move_right")
	_expect(not _has_group_event("p1_jump", "gamepad"),
		"keyboard selection left Player 1 controller events active")
	_expect(not _has_group_event("p2_jump", "keyboard_mouse"),
		"Player 2 incorrectly retained shared keyboard/mouse events")

	# Switch the primary player to controller and verify the complete runtime
	# path, including remapped button/axis input and keyboard isolation.
	overrides["p1_jump"] = {
		"gamepad": [{"type": "joy_button", "button": int(JOY_BUTTON_DPAD_DOWN)}],
	}
	overrides["p1_move_right"] = {
		"gamepad": [{"type": "joy_axis", "axis": int(JOY_AXIS_LEFT_X), "direction": 1}],
	}
	PlayerPrefs.settings["input_device"] = "controller"
	PlayerPrefs.settings["input_overrides"] = overrides
	PlayerPrefs.apply_input_overrides()
	_expect(PlayerPrefs.is_using_controller("p1"),
		"Player 1 device selection did not switch to controller")
	_expect(not _has_group_event("p1_jump", "keyboard_mouse"),
		"controller selection left Player 1 keyboard events active")
	await _expect_joy_button_action(JOY_BUTTON_DPAD_DOWN, "p1_jump")
	await _expect_joy_axis_action(JOY_AXIS_LEFT_X, 0.9, "p1_move_right")
	await _expect_key_inactive(KEY_F13, "p1_jump")
	await _expect_key_action(KEY_ESCAPE, "pause", "p1_jump")
	await _expect_key_action(KEY_TAB, "scoreboard", "p1_jump")
	await _expect_joy_button_excludes(
		JOY_BUTTON_B, "p1_dash", "pause")
	await _expect_joy_button_excludes(
		JOY_BUTTON_START, "pause", "p1_dash")
	await _expect_joy_button_excludes(
		JOY_BUTTON_BACK, "scoreboard", "p1_dash")

	# With primary-controller splitscreen, the two players must never share the
	# same physical pad route. If only one pad exists, P2 is intentionally left
	# unassigned until a second pad is hot-plugged.
	GameConfig.split_screen_enabled = true
	PlayerPrefs.apply_input_overrides()
	var p1_device := _runtime_gamepad_device("p1_jump")
	var p2_device := _runtime_gamepad_device("p2_jump")
	_expect(p1_device != p2_device,
		"primary-controller splitscreen routed both players to device %d" % p1_device)

	PlayerPrefs.settings = opening_settings
	GameConfig.split_screen_enabled = opening_split_screen
	PlayerPrefs.apply_input_overrides()
	if _failures.is_empty():
		print("INPUT_REMAP_VALIDATION_OK defaults=complete device_switch=true keyboard=true mouse=true controller_button=true controller_axis=true split_routing=true ui=true pause=true scoreboard=true")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("InputRemapValidation: " + failure)
		get_tree().quit(1)


func _expect_key_action(code: Key, expected_action: String, other_action: String) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	_expect(Input.is_action_pressed(expected_action),
		"%s did not react to remapped key %s" % [expected_action, OS.get_keycode_string(code)])
	_expect(not Input.is_action_pressed(other_action),
		"%s remap also activated %s" % [expected_action, other_action])
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _expect_key_inactive(code: Key, action: String) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	_expect(not Input.is_action_pressed(action),
		"old key still activated %s after remap" % action)
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _expect_mouse_action(button: MouseButton, action: String) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	_expect(Input.is_action_pressed(action), "%s did not react to remapped mouse button" % action)
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _expect_joy_button_action(button: JoyButton, action: String) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = _runtime_gamepad_device(action)
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	_expect(Input.is_action_pressed(action), "%s did not react to remapped gamepad button" % action)
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _expect_joy_button_excludes(button: JoyButton, expected_action: String,
		excluded_action: String) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = _runtime_gamepad_device(expected_action)
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	_expect(Input.is_action_pressed(expected_action),
		"%s did not react to controller button %d" % [expected_action, button])
	_expect(not Input.is_action_pressed(excluded_action),
		"controller button %d activated both %s and %s" % [
			button, expected_action, excluded_action])
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _expect_joy_axis_action(axis: JoyAxis, value: float, action: String) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	event.device = _runtime_gamepad_device(action)
	Input.parse_input_event(event)
	await get_tree().process_frame
	_expect(Input.get_action_strength(action) > 0.8,
		"%s did not react to remapped gamepad axis" % action)
	event.axis_value = 0.0
	Input.parse_input_event(event)
	await get_tree().process_frame


func _has_group_event(action: String, group: String) -> bool:
	for event in InputMap.action_get_events(action):
		if group == "keyboard_mouse" and (
				event is InputEventKey or event is InputEventMouseButton):
			return true
		if group == "gamepad" and (
				event is InputEventJoypadButton or event is InputEventJoypadMotion):
			return true
	return false


func _has_default_descriptor(action: String, expected: Dictionary) -> bool:
	for descriptor in PlayerPrefs.get_binding_descriptors(
			action, "gamepad", true):
		if descriptor == expected:
			return true
	return false


func _runtime_gamepad_device(action: String) -> int:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return event.device
	return -1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
