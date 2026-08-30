extends Node

const PRODUCTION_INTRO_SCENE = preload(
	"res://cinematics/startup/startup_intro_preview_five_word_shot_barlow_condensed.tscn")
const EXPECTED_HANDOFF_SCENE := "res://main_menu.tscn"
const TEST_HANDOFF_SCENE := \
	"res://tools/startup_production_handoff_target.tscn"
const EXPECTED_FONT_PATH := \
	"res://fonts/cinematic/barlow_condensed/BarlowCondensed-ExtraBold.ttf"

var _intro: Node = null


func _ready() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	_intro = PRODUCTION_INTRO_SCENE.instantiate()
	add_child(_intro)
	if not _validate_production_configuration():
		_fail("production scene configuration drifted")
		return
	if not _intro.is_processing_input():
		_fail("approved intro node is not registered for viewport input")
		return
	if not await _wait_until(
		func() -> bool:
			return _intro_is_prepared() and int(_intro.get("_state")) == 1,
		10000):
		_fail("approved smooth-shot scene did not enter the cinematic state")
		return
	var source := _intro.get("_source") as Node
	if source.is_processing_input() or source.is_processing_unhandled_input() \
			or source.is_processing_unhandled_key_input():
		_fail("standalone child input remained enabled")
		return
	if not await _wait_until(
		func() -> bool:
			return int(source.get("_state")) == 2,
		15000):
		_fail("approved smooth-shot scene did not reach its visible title")
		return
	_intro.set("handoff_scene_path", TEST_HANDOFF_SCENE)
	_send_key(KEY_ENTER)
	if not await _wait_until(
		func() -> bool:
			return int(_intro.get("_state")) == 3,
		1000):
		_fail("first title input did not begin the scene handoff")
		return
	await get_tree().create_timer(2.0, true, false, true).timeout
	_fail("production handoff did not change scenes")


func _validate_production_configuration() -> bool:
	var font := _intro.get("caption_font") as Font
	return not bool(_intro.get("show_preview_controls")) \
		and not bool(_intro.get("allow_replay_input")) \
		and not bool(_intro.get("escape_quits_preview")) \
		and str(_intro.get("handoff_scene_path")) == EXPECTED_HANDOFF_SCENE \
		and font != null and font.resource_path == EXPECTED_FONT_PATH


func _intro_is_prepared() -> bool:
	var source := _intro.get("_source") as Node
	if source == null:
		return false
	var actors := source.get("_actors") as Dictionary
	var labels := _intro.get("_death_word_labels") as Array[Label]
	return actors.size() == 6 and labels.size() == 5


func _send_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	_intro.call("_input", event)


func _wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < timeout_msec:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false


func _fail(reason: String) -> void:
	push_error("STARTUP_PRODUCTION_FLOW_VALIDATION: FAIL %s" % reason)
	get_tree().quit(1)
