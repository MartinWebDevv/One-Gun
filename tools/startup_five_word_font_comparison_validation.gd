extends Node

const VARIANTS: Array[Dictionary] = [
	{
		"name": "fredoka_bold",
		"scene": preload("res://cinematics/startup/startup_intro_preview_five_word_shot_fredoka_bold.tscn"),
	},
	{
		"name": "barlow_condensed_extrabold",
		"scene": preload("res://cinematics/startup/startup_intro_preview_five_word_shot_barlow_condensed.tscn"),
	},
	{
		"name": "anton",
		"scene": preload("res://cinematics/startup/startup_intro_preview_five_word_shot_anton.tscn"),
	},
]


func _ready() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	for configuration in VARIANTS:
		if not await _capture_variant(configuration):
			get_tree().quit(1)
			return
	print("STARTUP_FIVE_WORD_FONT_COMPARISON_VALIDATION: PASS variants=%d" % VARIANTS.size())
	get_tree().quit(0)


func _capture_variant(configuration: Dictionary) -> bool:
	var preview := (configuration["scene"] as PackedScene).instantiate()
	preview.set("show_preview_controls", false)
	add_child(preview)
	if not await _wait_until(
		func() -> bool:
			return int(preview.get("_state")) == 1,
		5000):
		push_error("STARTUP_FIVE_WORD_FONT_COMPARISON_VALIDATION: %s did not start" % configuration["name"])
		preview.queue_free()
		return false
	if not await _wait_until(
		func() -> bool:
			return int(preview.get("_revealed_word_count")) == 5,
		8000):
		push_error("STARTUP_FIVE_WORD_FONT_COMPARISON_VALIDATION: %s did not reveal all words" % configuration["name"])
		preview.queue_free()
		return false
	await get_tree().create_timer(0.12, true, false, true).timeout
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path(
		"res://.godot/startup_five_word_font_comparison")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("%s.png" % configuration["name"])
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(output_path) != OK:
		push_error("STARTUP_FIVE_WORD_FONT_COMPARISON_VALIDATION: %s capture failed" % configuration["name"])
		preview.queue_free()
		return false
	print("STARTUP_FIVE_WORD_FONT_CAPTURE: %s" % output_path)
	preview.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return true


func _wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < timeout_msec:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false

