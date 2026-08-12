class_name UICapture
extends Object

# Development-only screenshot hook for menu-redesign phase reviews.
# When the ONEGUN_UI_CAPTURE env var is set, waits for the screen to settle,
# saves the viewport to docs/screenshots/menu_redesign/<name>.png, and quits.
# A no-op in normal play (env var unset).

const CAPTURE_DIR := "res://docs/screenshots/menu_redesign/"


static func maybe_capture(node: Node, base_name: String, delay: float = 1.5) -> void:
	if OS.get_environment("ONEGUN_UI_CAPTURE") == "":
		return
	_run.call_deferred(node, base_name, delay)


static func _run(node: Node, base_name: String, delay: float) -> void:
	var tree := node.get_tree()
	if tree == null:
		return
	# Env value "WxH" forces an exact windowed capture size (the project's
	# maximized window mode otherwise wins over --resolution).
	var requested := OS.get_environment("ONEGUN_UI_CAPTURE")
	if requested.contains("x"):
		var parts := requested.split("x")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(parts[0].to_int(), parts[1].to_int()))
	await tree.create_timer(delay).timeout
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var requested_dir := OS.get_environment("ONEGUN_UI_CAPTURE_DIR")
	var dir_path := requested_dir if not requested_dir.is_empty() \
		else ProjectSettings.globalize_path(CAPTURE_DIR)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var image := node.get_viewport().get_texture().get_image()
	var file_name := "%s_%dx%d.png" % [base_name.get_basename(), image.get_width(), image.get_height()]
	var err := image.save_png(dir_path.path_join(file_name))
	print("ui capture %s -> %s" % [file_name, error_string(err)])
	# Paired host/guest QA captures need the host to remain online until the
	# guest saves its frame. Normal captures still quit immediately.
	if OS.get_environment("ONEGUN_UI_CAPTURE_NO_QUIT") == "":
		tree.quit()
