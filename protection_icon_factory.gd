extends RefCounted

static var _cache: Dictionary = {}

static func texture_from_svg(path: String) -> Texture2D:
	# Dedicated exports intentionally strip visual resources. Server-side actors
	# still run their normal gameplay setup, but they never need world-space UI.
	if DisplayServer.get_name() == "headless":
		return null
	if _cache.has(path):
		return _cache[path]
	if not FileAccess.file_exists(path):
		push_warning("Protection icon SVG missing: %s" % path)
		return null
	var image := Image.new()
	var error := image.load_svg_from_string(FileAccess.get_file_as_string(path))
	if error != OK:
		push_warning("Protection icon SVG failed to load: %s" % path)
		return null
	var texture := ImageTexture.create_from_image(image)
	_cache[path] = texture
	return texture
