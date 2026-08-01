extends CanvasLayer

# Central adapter for local visual/accessibility preferences. It owns global
# UI/text scaling and a lightweight screen-space color/motion filter; gameplay
# scripts query it for shake, bob, flashing, and reduced-motion policy.

var _filter_rect: ColorRect
var _filter_material: ShaderMaterial
var _high_contrast := false
var _text_scale := 1.0
var _motion_blur_enabled := false
var _previous_camera_transform := Transform3D.IDENTITY
var _has_previous_camera := false
var _effective_values: Dictionary = {}
var _pending_control_ids: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	_build_filter()
	PlayerPrefs.setting_changed.connect(_on_setting_changed)
	get_tree().node_added.connect(_on_node_added)
	apply_all()


func _build_filter() -> void:
	_filter_rect = ColorRect.new()
	_filter_rect.name = "AccessibilityScreenFilter"
	_filter_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform int filter_mode = 0;
uniform vec2 motion_vector = vec2(0.0);

vec3 color_filter(vec3 c) {
	if (filter_mode == 1) {
		return vec3(dot(c, vec3(0.567, 0.433, 0.000)), dot(c, vec3(0.558, 0.442, 0.000)), dot(c, vec3(0.000, 0.242, 0.758)));
	}
	if (filter_mode == 2) {
		return vec3(dot(c, vec3(0.625, 0.375, 0.000)), dot(c, vec3(0.700, 0.300, 0.000)), dot(c, vec3(0.000, 0.300, 0.700)));
	}
	if (filter_mode == 3) {
		return vec3(dot(c, vec3(0.950, 0.050, 0.000)), dot(c, vec3(0.000, 0.433, 0.567)), dot(c, vec3(0.000, 0.475, 0.525)));
	}
	return c;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = texture(screen_texture, uv).rgb * 0.40;
	c += texture(screen_texture, uv - motion_vector).rgb * 0.24;
	c += texture(screen_texture, uv + motion_vector).rgb * 0.24;
	c += texture(screen_texture, uv - motion_vector * 2.0).rgb * 0.06;
	c += texture(screen_texture, uv + motion_vector * 2.0).rgb * 0.06;
	COLOR = vec4(color_filter(c), 1.0);
}
"""
	_filter_material = ShaderMaterial.new()
	_filter_material.shader = shader
	_filter_rect.material = _filter_material
	add_child(_filter_rect)


func apply_all(values: Dictionary = {}) -> void:
	var source := PlayerPrefs.settings if values.is_empty() else values
	_effective_values = source.duplicate(true)
	var root := get_tree().root
	root.content_scale_factor = clampf(float(source.get("ui_scale", 1.0)), 0.8, 1.25)
	_text_scale = _text_multiplier(str(source.get("text_size", "normal")))
	_high_contrast = bool(source.get("high_contrast_ui", false))
	var filter_name := str(source.get("colorblind_filter", "off"))
	var filter_mode := ["off", "protanopia", "deuteranopia", "tritanopia"].find(filter_name)
	_filter_material.set_shader_parameter("filter_mode", maxi(filter_mode, 0))
	_motion_blur_enabled = bool(source.get("motion_blur", false)) and not bool(source.get("reduced_motion", false))
	if not _motion_blur_enabled:
		_has_previous_camera = false
		_filter_material.set_shader_parameter("motion_vector", Vector2.ZERO)
	_filter_rect.visible = filter_mode > 0 or _motion_blur_enabled
	_apply_accessibility_recursive(root)


func _process(_delta: float) -> void:
	if not _motion_blur_enabled: return
	var camera := _active_camera()
	if camera == null:
		_filter_material.set_shader_parameter("motion_vector", Vector2.ZERO)
		_has_previous_camera = false
		return
	var current := camera.global_transform
	if not _has_previous_camera:
		_previous_camera_transform = current
		_has_previous_camera = true
		return
	var local_delta := current.basis.inverse() * (current.origin - _previous_camera_transform.origin)
	var previous_rotation := _previous_camera_transform.basis.get_euler()
	var current_rotation := current.basis.get_euler()
	var angular_delta := Vector2(wrapf(current_rotation.y - previous_rotation.y, -PI, PI), wrapf(current_rotation.x - previous_rotation.x, -PI, PI))
	_filter_material.set_shader_parameter("motion_vector", motion_blur_vector(local_delta, angular_delta))
	_previous_camera_transform = current


func screen_shake_scale() -> float:
	return 0.0 if reduced_motion_enabled() else clampf(float(_effective_values.get("screen_shake_intensity", 1.0)), 0.0, 1.0)


func camera_bob_scale() -> float:
	return 0.0 if reduced_motion_enabled() else clampf(float(_effective_values.get("camera_bob_intensity", 1.0)), 0.0, 1.0)


func reduced_motion_enabled() -> bool:
	return bool(_effective_values.get("reduced_motion", false))


func allow_flash() -> bool:
	return not bool(_effective_values.get("reduce_flashing", false))


func preview_policy(values: Dictionary) -> void:
	# Cheap live-preview path for gameplay-only policy sliders/toggles; unlike
	# apply_all(), this intentionally avoids walking the full Control tree.
	_effective_values = values.duplicate(true)


func _on_setting_changed(key: String, _value) -> void:
	if key in ["ui_scale", "text_size", "colorblind_filter", "high_contrast_ui", "motion_blur", "reduced_motion"]:
		apply_all.call_deferred()
	elif key in ["screen_shake_intensity", "camera_bob_intensity", "reduce_flashing"]:
		_effective_values[key] = _value


func _on_node_added(node: Node) -> void:
	if node is Control:
		var instance_id := node.get_instance_id()
		if _pending_control_ids.has(instance_id):
			return
		_pending_control_ids[instance_id] = true
		_apply_accessibility_if_valid.call_deferred(weakref(node), instance_id)


func _apply_accessibility_if_valid(reference: WeakRef, instance_id: int) -> void:
	_pending_control_ids.erase(instance_id)
	var node = reference.get_ref()
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	_apply_accessibility_recursive(node)


func _apply_accessibility_recursive(node: Node) -> void:
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	if node is Control:
		_apply_control(node as Control)
	for child in node.get_children():
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			_apply_accessibility_recursive(child)


func _active_camera() -> Camera3D:
	var root_camera := get_viewport().get_camera_3d()
	if root_camera != null: return root_camera
	for player in get_tree().get_nodes_in_group("player"):
		if player.has_method("get_camera"):
			var candidate = player.get_camera()
			if candidate is Camera3D and candidate.current: return candidate
	return null


static func motion_blur_vector(local_delta: Vector3, angular_delta: Vector2) -> Vector2:
	var vector := Vector2(-angular_delta.x, angular_delta.y) * 0.035
	vector += Vector2(-local_delta.x, local_delta.y) * 0.0025
	return vector.limit_length(0.012)


func _apply_control(control: Control) -> void:
	if control is Label or control is Button or control is LineEdit or control is OptionButton:
		if not control.has_meta("accessibility_base_font_size"):
			control.set_meta("accessibility_base_font_size", control.get_theme_font_size("font_size"))
		var base := int(control.get_meta("accessibility_base_font_size"))
		control.add_theme_font_size_override("font_size", maxi(roundi(base * _text_scale), 10))
		if _high_contrast:
			control.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.96))
			control.add_theme_constant_override("outline_size", 2)
		else:
			control.remove_theme_color_override("font_outline_color")
			control.remove_theme_constant_override("outline_size")


func _text_multiplier(value: String) -> float:
	match value:
		"small": return 0.9
		"large": return 1.15
		"extra_large": return 1.3
		_: return 1.0
