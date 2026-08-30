extends Node

const PREVIEW_SCENE = preload(
	"res://cinematics/startup/startup_intro_preview_five_word_shot_barlow_condensed.tscn")
const EARLY_CAPTURE_TIMES: Array[float] = [0.55, 1.65, 2.72]
const EXPECTED_FONT_PATH := \
	"res://fonts/cinematic/barlow_condensed/BarlowCondensed-ExtraBold.ttf"

var _preview: Node = null


func _ready() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	_preview = PREVIEW_SCENE.instantiate()
	_preview.set("show_preview_controls", false)
	add_child(_preview)
	if not await _wait_until(
		func() -> bool:
			return int(_preview.get("_state")) == 1,
		5000):
		await _finish(false, "preview did not start")
		return
	if not _validate_source_label_fonts():
		await _finish(false, "one or more source labels did not use Barlow")
		return
	var last_time := 0.0
	var capture_index := 0
	for capture_time in EARLY_CAPTURE_TIMES:
		await get_tree().create_timer(
			capture_time - last_time, true, false, true).timeout
		last_time = capture_time
		if not await _capture(capture_index):
			await _finish(false, "early capture failed")
			return
		capture_index += 1
	if not await _wait_until(
		func() -> bool:
			return int(_preview.get("_revealed_word_count")) == 5,
		5000):
		await _finish(false, "five-word phrase did not complete")
		return
	await get_tree().create_timer(0.12, true, false, true).timeout
	if not await _capture(capture_index):
		await _finish(false, "five-word capture failed")
		return
	capture_index += 1
	if not await _wait_until(
		func() -> bool:
			return int(_preview.get("_state")) == 2,
		3000):
		await _finish(false, "title state timed out")
		return
	if not await _capture(capture_index):
		await _finish(false, "title capture failed")
		return
	capture_index += 1
	print("STARTUP_FIVE_WORD_BARLOW_LABELS_VALIDATION: PASS captures=%d" % capture_index)
	await _finish(true)


func _validate_source_label_fonts() -> bool:
	var source := _preview.get("_source") as Node
	var label_properties: Array[String] = [
		"_phrase", "_prompt", "_preview_controls", "_end_card",
	]
	for property_name in label_properties:
		var control := source.get(property_name) as Control
		if control == null:
			return false
		var font_slot := "normal_font" if control is RichTextLabel else "font"
		var font: Font = control.get_theme_font(font_slot)
		if font == null or font.resource_path != EXPECTED_FONT_PATH:
			push_error("STARTUP_FIVE_WORD_BARLOW_LABELS_VALIDATION: %s font=%s" % [
				property_name, font.resource_path if font != null else "null"])
			return false
	return true


func _capture(index: int) -> bool:
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path(
		"res://.godot/startup_five_word_barlow_labels")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("shot_%02d.png" % index)
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(output_path) != OK:
		return false
	print("STARTUP_FIVE_WORD_BARLOW_LABEL_CAPTURE: %s" % output_path)
	return true


func _wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < timeout_msec:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false


func _finish(passed: bool, reason := "") -> void:
	if not passed:
		push_error("STARTUP_FIVE_WORD_BARLOW_LABELS_VALIDATION: FAIL %s" % reason)
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if passed else 1)
