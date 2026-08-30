extends Node

const PREVIEW_SCENE = preload("res://cinematics/startup/startup_intro_arena_chase_final.tscn")
const CAPTURE_TIMES: Array[float] = [
	0.90, 2.05, 2.78, 3.72, 4.72, 5.90, 6.95, 8.00, 9.10, 10.20, 11.85,
]

var _preview: Node = null


func _ready() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	_preview = PREVIEW_SCENE.instantiate()
	_preview.set("show_preview_controls", false)
	add_child(_preview)
	while int(_preview.get("_state")) != 1:
		await get_tree().process_frame
	var last_time := 0.0
	for index in CAPTURE_TIMES.size():
		var capture_time := CAPTURE_TIMES[index]
		await get_tree().create_timer(capture_time - last_time, true, false, true).timeout
		last_time = capture_time
		if not await _capture(index):
			await _finish(1)
			return
	print("STARTUP_ARENA_CHASE_FINAL_RENDER_VALIDATION: PASS captures=%d" % CAPTURE_TIMES.size())
	await _finish(0)


func _capture(index: int) -> bool:
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path(
		"res://.godot/startup_arena_chase_final_captures")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("shot_%02d.png" % index)
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(output_path) != OK:
		push_error("STARTUP_ARENA_CHASE_FINAL_RENDER_VALIDATION: capture failed at %d" % index)
		return false
	print("STARTUP_ARENA_CHASE_FINAL_CAPTURE: %s" % output_path)
	return true


func _finish(exit_code: int) -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)

