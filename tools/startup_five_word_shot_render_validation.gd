extends Node

const PREVIEW_SCENE = preload(
	"res://cinematics/startup/startup_intro_preview_five_word_shot.tscn")
const INTRO_CAPTURE_TIMES: Array[float] = [0.55, 1.65, 2.72]
const EXPECTED_CAPTURE_COUNT := 12

var _preview: Node = null


func _ready() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	_preview = PREVIEW_SCENE.instantiate()
	_preview.set("show_preview_controls", false)
	add_child(_preview)
	while int(_preview.get("_state")) != 1:
		await get_tree().process_frame
	var last_time := 0.0
	var capture_index := 0
	for capture_time in INTRO_CAPTURE_TIMES:
		await get_tree().create_timer(
			capture_time - last_time, true, false, true).timeout
		last_time = capture_time
		if not await _capture(capture_index):
			await _finish(1)
			return
		capture_index += 1

	# Capture the exact frame each death contributes its word rather than
	# estimating around the deliberately quick elimination timings.
	for expected_word_count in range(1, 6):
		if not await _wait_until(
			func() -> bool:
				return int(_preview.get("_revealed_word_count")) >= expected_word_count,
			3000):
			push_error("STARTUP_FIVE_WORD_SHOT_RENDER_VALIDATION: "
				+ "word %d was not revealed" % expected_word_count)
			await _finish(1)
			return
		if not await _capture(capture_index):
			await _finish(1)
			return
		capture_index += 1

	# Preserve a clean look at Blue taking aim, then capture the lens flash,
	# the logo reveal, and the completed title state from their actual signals.
	await get_tree().create_timer(0.56, true, false, true).timeout
	if not await _capture(capture_index):
		await _finish(1)
		return
	capture_index += 1
	var approved_source := _preview.get("_source") as Node
	var flash := approved_source.get("_flash") as ColorRect
	if not await _wait_until(
		func() -> bool:
			return flash.color.a >= 0.80,
		3000):
		push_error("STARTUP_FIVE_WORD_SHOT_RENDER_VALIDATION: final lens flash missing")
		await _finish(1)
		return
	if not await _capture(capture_index):
		await _finish(1)
		return
	capture_index += 1
	var stage := approved_source.get("_stage") as Node3D
	if not await _wait_until(
		func() -> bool:
			return not stage.visible,
		1000):
		push_error("STARTUP_FIVE_WORD_SHOT_RENDER_VALIDATION: logo handoff missing")
		await _finish(1)
		return
	if not await _capture(capture_index):
		await _finish(1)
		return
	capture_index += 1
	if not await _wait_until(
		func() -> bool:
			return int(_preview.get("_state")) == 2,
		3000):
		push_error("STARTUP_FIVE_WORD_SHOT_RENDER_VALIDATION: title state timed out")
		await _finish(1)
		return
	if not await _capture(capture_index):
		await _finish(1)
		return
	capture_index += 1

	var final_state := int(_preview.get("_state"))
	var revealed_words := int(_preview.get("_revealed_word_count"))
	if final_state != 2 or revealed_words != 5 \
			or capture_index != EXPECTED_CAPTURE_COUNT:
		push_error("STARTUP_FIVE_WORD_SHOT_RENDER_VALIDATION: "
			+ "unexpected final state=%d words=%d captures=%d" % [
				final_state, revealed_words, capture_index])
		await _finish(1)
		return
	print("STARTUP_FIVE_WORD_SHOT_RENDER_VALIDATION: PASS captures=%d words=%d" % [
		capture_index, revealed_words])
	await _finish(0)


func _wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < timeout_msec:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false


func _capture(index: int) -> bool:
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path(
		"res://.godot/startup_five_word_shot_captures")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("shot_%02d.png" % index)
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(output_path) != OK:
		push_error("STARTUP_FIVE_WORD_SHOT_RENDER_VALIDATION: capture failed at %d" % index)
		return false
	print("STARTUP_FIVE_WORD_SHOT_CAPTURE: %s" % output_path)
	return true


func _finish(exit_code: int) -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)
