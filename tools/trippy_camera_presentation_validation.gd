extends Node

## Focused presentation contract for Trippy Mountains. This runs as a project
## scene (not a standalone script) so the real lobby and menu preview scripts
## have their normal autoload context without loading a full rotating menu.

const MAP_PATH := "res://maps/test/TrippyMountainsMap.tscn"
const INNER_PLAY_AREA := Rect2(
	Vector2(21.00, -163.64), Vector2(94.42, 90.53))
const LOBBY_PREVIEW := preload("res://lobby_map_preview.gd")
const MENU_CYCLER := preload("res://menu_map_cycler.gd")


func _ready() -> void:
	var failures: Array[String] = []
	var map_index := MapRegistry.find_index_by_path(MAP_PATH)
	if map_index < 0:
		failures.append("map registry entry is missing")
		_finish(failures)
		return
	var map_data := MapRegistry.get_map(map_index)
	if MapRegistry.load_thumbnail(map_index) == null:
		failures.append("registered thumbnail does not load as a Texture2D")

	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var preview = LOBBY_PREVIEW.new()
	host.add_child(preview)
	preview.setup(host, MapRegistry.MAPS)
	preview.apply(1, map_index)
	await get_tree().process_frame
	if preview.current_index() != map_index:
		failures.append("lobby preview did not select Trippy Mountains")
	for step in 240:
		preview._process(1.0 / 60.0)
		var camera_point := Vector2(
			preview._orbit_center.x
				+ cos(preview._orbit_angle) * preview._orbit_camera_distance,
			preview._orbit_center.z
				+ sin(preview._orbit_angle) * preview._orbit_camera_distance)
		if not INNER_PLAY_AREA.has_point(camera_point):
			failures.append("lobby camera left PlayArea at %s" % camera_point)
			break
	host.free()

	var menu_override: Dictionary = MENU_CYCLER.MAP_OVERRIDES.get(
		MAP_PATH, {})
	if menu_override.is_empty():
		failures.append("main-menu interior camera override is missing")
	else:
		var anchor: Vector3 = menu_override.get(
			"anchor_local", Vector3.INF)
		var direction: Vector3 = menu_override.get(
			"camera_direction", Vector3.ZERO)
		direction.y = 0.0
		var distance := float(menu_override.get("view_distance", INF))
		var camera_position := anchor + direction.normalized() * distance
		if not INNER_PLAY_AREA.has_point(Vector2(
				camera_position.x, camera_position.z)):
			failures.append("main-menu camera is outside PlayArea")
		if float(menu_override.get("pan_range", 1.0)) > 0.12:
			failures.append("main-menu pan is wider than the enclosed view contract")

	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("TRIPPY_CAMERA_PRESENTATION_VALIDATION_OK")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("TRIPPY_CAMERA_PRESENTATION_VALIDATION: %s" % failure)
	get_tree().quit(1)
