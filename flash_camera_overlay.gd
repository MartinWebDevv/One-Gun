class_name FlashCameraOverlay
extends Control

var camera_mode := false
var shutter_flash := 0.0
var player = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_to_group("flash_camera_overlay")

func set_player(p) -> void:
	player = p
	_sync_camera_mode()

func show_shutter_for(source_player) -> void:
	if source_player == player:
		flash_shutter()

func set_camera_mode(enabled: bool) -> void:
	camera_mode = enabled
	visible = enabled or shutter_flash > 0.0
	queue_redraw()

func flash_shutter() -> void:
	shutter_flash = 1.0
	visible = true
	queue_redraw()

func _process(delta: float) -> void:
	_sync_camera_mode()
	if shutter_flash > 0.0:
		shutter_flash = maxf(shutter_flash - delta * 6.0, 0.0)
		visible = camera_mode or shutter_flash > 0.0
		queue_redraw()

func _sync_camera_mode() -> void:
	var enabled := false
	if player != null and player.has_method("get_active_item"):
		var active_item = player.get_active_item()
		enabled = active_item != null and active_item.has_method("is_camera_mode_active") \
			and active_item.is_camera_mode_active()
	if enabled != camera_mode:
		set_camera_mode(enabled)

func _draw() -> void:
	var rect := get_rect()
	if shutter_flash > 0.0:
		draw_rect(rect, Color(1.0, 0.98, 0.88, shutter_flash * 0.42))
	if not camera_mode:
		return
	var frame_size := rect.size * Vector2(0.66, 0.62)
	var frame := Rect2((rect.size - frame_size) * 0.5, frame_size)
	var color := Color(1.0, 0.86, 0.28, 0.95)
	var corner := minf(frame.size.x, frame.size.y) * 0.11
	var points := [
		[frame.position, frame.position + Vector2(corner, 0), frame.position + Vector2(0, corner)],
		[Vector2(frame.end.x, frame.position.y), Vector2(frame.end.x - corner, frame.position.y), Vector2(frame.end.x, frame.position.y + corner)],
		[Vector2(frame.position.x, frame.end.y), Vector2(frame.position.x + corner, frame.end.y), Vector2(frame.position.x, frame.end.y - corner)],
		[frame.end, frame.end - Vector2(corner, 0), frame.end - Vector2(0, corner)],
	]
	for corner_points in points:
		draw_line(corner_points[0], corner_points[1], color, 5.0, true)
		draw_line(corner_points[0], corner_points[2], color, 5.0, true)
	var center := rect.size * 0.5
	draw_line(center - Vector2(9, 0), center + Vector2(9, 0), Color.WHITE, 2.0)
	draw_line(center - Vector2(0, 9), center + Vector2(0, 9), Color.WHITE, 2.0)
