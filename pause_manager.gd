extends Node

# ============================================================
# PauseManager — autoload, PROCESS_MODE_ALWAYS.
#
# Owns the ESC toggle and pause state. Deliberately NOT done on the
# pause menu Control itself: Godot has a known input-routing quirk
# where _unhandled_input on a PROCESS_MODE_WHEN_PAUSED node can miss
# keyboard/mouse-button events while the tree is paused (godotengine/
# godot#97054). Centralizing the toggle on an always-running autoload
# avoids that entirely — this is the documented best-practice pattern.
#
# The actual pause menu UI is a child node inside the match scene's
# CanvasLayer (pause_menu.gd); this manager just tells it when to
# show/hide and tracks whether a pause-blocking popup (e.g. the exit
# confirmation) is currently open, so ESC doesn't fight it.
# ============================================================

signal pause_state_changed(is_paused: bool)

var pause_menu: Control = null

# When set, ESC calls this instead of toggling pause — used so a nested
# overlay (e.g. Settings opened from the pause menu) can claim ESC to
# step itself back, rather than pause/resume fighting it or ESC doing
# nothing while a sub-screen is open.
var escape_override: Callable = Callable()

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		if escape_override.is_valid():
			escape_override.call()
			get_viewport().set_input_as_handled()
			return
		if pause_menu == null:
			return
		toggle_pause()
		get_viewport().set_input_as_handled()

func register_pause_menu(menu: Control):
	pause_menu = menu

func unregister_pause_menu(menu: Control):
	if pause_menu == menu:
		pause_menu = null

func set_escape_override(callback: Callable):
	escape_override = callback

func clear_escape_override():
	escape_override = Callable()

func toggle_pause():
	if get_tree().paused:
		resume()
	else:
		pause()

func pause():
	if pause_menu == null:
		return
	get_tree().paused = true
	pause_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_state_changed.emit(true)

func resume():
	get_tree().paused = false
	if pause_menu != null:
		pause_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	pause_state_changed.emit(false)
