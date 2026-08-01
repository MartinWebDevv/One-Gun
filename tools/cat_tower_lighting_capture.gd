extends Node

const OUTPUT_DIR := "res://.godot"
const PREVIEW_CENTER := Vector3(-89.67, 7.69, -126.75)
const PREVIEW_RADIUS := 46.0
const PREVIEW_ANGLE := 1.62


func _ready() -> void:
	GameConfig.split_screen_enabled = false
	GameConfig.bot_configs = [{"difficulty": "easy", "team_id": -1}]
	GameConfig.round_time_limit = 999.0
	GameConfig.chaos_overtime_enabled = false

	var arena := load("res://maps/test/catTower.tscn").instantiate() as Node3D
	add_child(arena)
	var manager = arena.get_node_or_null("RoundManager")
	if manager == null:
		push_error("Cat Tower lighting capture could not find RoundManager")
		get_tree().quit(1)
		return

	var deadline := Time.get_ticks_msec() + 15000
	while manager.round_state != "live" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if manager.round_state != "live":
		push_error("Cat Tower lighting capture never reached live play")
		get_tree().quit(1)
		return

	var canvas := arena.get_node_or_null("CanvasLayer") as CanvasLayer
	if canvas != null:
		canvas.visible = false
	var split_layer := arena.get_node_or_null("SplitScreenLayer") as CanvasLayer
	if split_layer != null:
		split_layer.visible = false

	var camera := Camera3D.new()
	camera.fov = 60.0
	add_child(camera)
	var horizontal_radius := PREVIEW_RADIUS * 1.2
	camera.global_position = PREVIEW_CENTER + Vector3(
		cos(PREVIEW_ANGLE) * horizontal_radius,
		PREVIEW_RADIUS * 0.75,
		sin(PREVIEW_ANGLE) * horizontal_radius)
	camera.look_at(PREVIEW_CENTER + Vector3.UP * PREVIEW_RADIUS * 0.06)
	camera.current = true

	await get_tree().create_timer(0.5).timeout
	var normal_path := OUTPUT_DIR.path_join("cat_tower_normal_check.png")
	var normal_result := _save_viewport(normal_path)

	GameConfig.round_time_limit = 0.01
	manager.round_elapsed = 1.0
	deadline = Time.get_ticks_msec() + 5000
	while not manager.overtime_active and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not manager.overtime_active:
		push_error("Cat Tower lighting capture could not enter overtime")
		get_tree().quit(1)
		return
	manager.overtime_elapsed = 120.0
	manager._update_storm_visual()
	await get_tree().create_timer(0.6).timeout
	var overtime_path := OUTPUT_DIR.path_join("cat_tower_overtime_check.png")
	var overtime_result := _save_viewport(overtime_path)

	print("CAT TOWER LIGHTING CAPTURE normal=%s overtime=%s" % [
		normal_path, overtime_path])
	get_tree().quit(0 if normal_result == OK and overtime_result == OK else 1)


func _save_viewport(path: String) -> Error:
	var image := get_viewport().get_texture().get_image()
	var absolute_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	return image.save_png(absolute_path)
