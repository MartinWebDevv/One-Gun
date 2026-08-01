extends Control

# Development utility: generates the carousel thumbnails from the same
# stripped live-map preview used by the lobby. These are honest map captures,
# not concept-art crops or gameplay screenshots.

const OUTPUT_SIZE := Vector2i(480, 270)
const MODE_SPECIFIC := 1

var _preview: Node
var _failures := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview = preload("res://lobby_map_preview.gd").new()
	add_child(_preview)
	_preview.setup(self, MapRegistry.MAPS)
	_capture_all.call_deferred()


func _capture_all() -> void:
	var indices: Array[int] = []
	var requested_index := OS.get_environment("ONEGUN_THUMBNAIL_INDEX")
	if requested_index.is_valid_int():
		var parsed_index := int(requested_index)
		if parsed_index >= 0 and parsed_index < MapRegistry.MAPS.size():
			indices.append(parsed_index)
		else:
			_failures += 1
			push_error("Requested thumbnail index %d is outside the map registry" % parsed_index)
	else:
		for index in MapRegistry.MAPS.size():
			indices.append(index)
	for index in indices:
		_preview.apply(MODE_SPECIFIC, index)
		while _preview.current_index() != index:
			await _preview.map_shown
		# Let particles, lighting, and the orbit camera settle before readback.
		await get_tree().create_timer(0.65).timeout
		var image: Image = _preview.capture_image()
		if image == null:
			_failures += 1
			push_error("Map thumbnail capture failed for index %d" % index)
			continue
		image.resize(OUTPUT_SIZE.x, OUTPUT_SIZE.y, Image.INTERPOLATE_LANCZOS)
		var output_path := ProjectSettings.globalize_path(
				str(MapRegistry.MAPS[index].get("thumbnail_path", "")))
		DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
		var err := image.save_png(output_path)
		if err != OK:
			_failures += 1
			push_error("Could not save %s: %s" % [output_path, error_string(err)])
		else:
			print("Saved map thumbnail: ", output_path)
	get_tree().quit(_failures)
