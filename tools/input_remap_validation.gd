extends Node

## Verifies the complete PlayerPrefs -> InputMap path used by Player Settings.
## The test is disk-free and restores the live project bindings before exit.

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var opening_settings := PlayerPrefs.settings.duplicate(true)
	var overrides := {
		"p1_jump": {"keyboard_mouse": [{"type": "key", "code": int(KEY_F13)}]},
		"p2_jump": {"keyboard_mouse": [{"type": "key", "code": int(KEY_F14)}]},
		"p1_fire": {"keyboard_mouse": [{"type": "mouse_button", "button": int(MOUSE_BUTTON_XBUTTON1)}]},
		"p2_fire": {"gamepad": [{"type": "joy_button", "button": int(JOY_BUTTON_DPAD_UP)}]},
		"p2_move_right": {"gamepad": [{"type": "joy_axis", "axis": int(JOY_AXIS_LEFT_X), "direction": 1}]},
	}
	PlayerPrefs.settings["input_overrides"] = overrides
	PlayerPrefs.apply_input_overrides()

	for action in overrides:
		_expect(InputMap.has_action(action), "missing remappable action: %s" % action)
		_expect(not InputMap.action_get_events(action).is_empty(),
			"override produced no InputMap event: %s" % action)

	await _expect_key_action(KEY_F13, "p1_jump", "p2_jump")
	await _expect_key_action(KEY_F14, "p2_jump", "p1_jump")
	await _expect_key_inactive(KEY_SPACE, "p1_jump")
	await _expect_mouse_action(MOUSE_BUTTON_XBUTTON1, "p1_fire")
	await _expect_joy_button_action(JOY_BUTTON_DPAD_UP, "p2_fire")
	await _expect_joy_axis_action(JOY_AXIS_LEFT_X, 0.9, "p2_move_right")

	PlayerPrefs.settings = opening_settings
	PlayerPrefs.apply_input_overrides()
	if _failures.is_empty():
		print("INPUT_REMAP_VALIDATION_OK p1_key=true p2_key=true mouse=true gamepad_button=true gamepad_axis=true")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("InputRemapValidation: " + failure)
		get_tree().quit(1)


func _expect_key_action(code: Key, expected_action: String, other_action: String) -> void:
	var event := InputEventKey.new()
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
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	_expect(Input.is_action_pressed(action), "%s did not react to remapped gamepad button" % action)
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _expect_joy_axis_action(axis: JoyAxis, value: float, action: String) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	await get_tree().process_frame
	_expect(Input.get_action_strength(action) > 0.8,
		"%s did not react to remapped gamepad axis" % action)
	event.axis_value = 0.0
	Input.parse_input_event(event)
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
