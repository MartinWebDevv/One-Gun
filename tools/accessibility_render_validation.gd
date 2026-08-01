extends Node3D

# Rendered smoke test for the camera-delta screen-space blur adapter. It never
# writes PlayerPrefs; a temporary values dictionary is passed directly.

var _camera: Camera3D
var _frames := 0


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	var values: Dictionary = PlayerPrefs.snapshot()
	values["motion_blur"] = true
	values["reduced_motion"] = false
	AccessibilityManager.apply_all(values)


func _process(_delta: float) -> void:
	_frames += 1
	_camera.position.x += 0.12
	_camera.rotation.y += 0.025
	if _frames < 20: return
	var material = AccessibilityManager.get("_filter_material")
	var vector: Vector2 = material.get_shader_parameter("motion_vector")
	if vector.is_zero_approx():
		push_error("ACCESSIBILITY RENDER FAILED: moving camera produced zero blur vector")
		get_tree().quit(1)
	else:
		print("ACCESSIBILITY RENDER OK: camera motion drove screen shader %s" % vector)
		get_tree().quit(0)
