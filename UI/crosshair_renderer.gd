class_name OneGunCrosshair
extends Control

# Procedural, local-only crosshair. It reads presentation state but never feeds
# back into weapon spread, aim, hit validation, or networking.

var player = null
var preview_mode := false
var force_visible_without_weapon := false
var preview_settings: Dictionary = {}
var _uses_personal_settings := true
var _pulse := 0.0
var _preview_reload := -1.0
var _preview_pickup := 0.0
var _preview_interact := 0.0
var _last_can_fire := true
var _expansion := 0.0
var _cached_gun = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _has_property_name("text"): set("text", "")
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -100.0
	offset_top = -100.0
	offset_right = 100.0
	offset_bottom = 100.0
	PlayerPrefs.setting_changed.connect(_on_setting_changed)
	GameEvents.gun_picked_up.connect(_on_gun_picked_up)
	queue_redraw()


func set_player(value) -> void:
	player = value
	_uses_personal_settings = not bool(value.get("is_player2")) if value != null else true


func set_preview_settings(values: Dictionary) -> void:
	preview_mode = true
	preview_settings = values
	visible = true
	queue_redraw()


func trigger_preview(action: String) -> void:
	match action:
		"fire": _pulse = 1.0
		"reload": _preview_reload = 0.0
		"pickup": _preview_pickup = 1.0
		"interact": _preview_interact = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	var settings := _settings()
	if preview_mode:
		visible = str(settings.get("crosshair_style", "classic")) != "hidden"
	else:
		if player == null:
			visible = false
			return
		var has_weapon := bool(player.get("holding_gun")) or player.get("held_melee_weapon") != null
		var weapon_active := player.get("active_slot") == null or str(player.get("active_slot")) == "weapon"
		visible = (force_visible_without_weapon or has_weapon) and weapon_active \
			and str(settings.get("crosshair_style", "classic")) != "hidden"
	if not visible:
		return

	var speed_scale: float = float({"slow": 0.65, "normal": 1.0, "fast": 1.65}.get(str(settings.get("crosshair_animation_speed", "normal")), 1.0))
	if AccessibilityManager.reduced_motion_enabled() or bool(settings.get("reduce_crosshair_motion", false)):
		speed_scale = 0.0
	_pulse = maxf(_pulse - delta * 5.0 * speed_scale, 0.0)
	_preview_pickup = maxf(_preview_pickup - delta * 2.5, 0.0)
	_preview_interact = maxf(_preview_interact - delta * 2.5, 0.0)
	if _preview_reload >= 0.0:
		_preview_reload += delta / 1.5
		if _preview_reload > 1.0: _preview_reload = -1.0

	var target_expansion := 0.0
	var mode := str(settings.get("crosshair_behavior_mode", "static"))
	if not preview_mode and player != null:
		var gun = _find_gun()
		var can_fire := true if gun == null else bool(gun.get("can_fire"))
		if _last_can_fire and not can_fire and bool(settings.get("crosshair_fire_pulse", true)):
			_pulse = 1.0
		_last_can_fire = can_fire
		if mode in ["movement", "full_dynamic"] and bool(settings.get("crosshair_movement_expansion", false)):
			var velocity_value = player.get("velocity")
			if velocity_value is Vector3:
				target_expansion = minf(Vector2(velocity_value.x, velocity_value.z).length() / 12.0, 1.0)
		if bool(settings.get("crosshair_interactable_feedback", true)) and player.has_method("get_valid_crosshair_interactable") and player.get_valid_crosshair_interactable() != null:
			_preview_interact = maxf(_preview_interact, 0.2)
	var return_scale: float = float({"slow": 5.0, "normal": 10.0, "fast": 18.0}.get(str(settings.get("crosshair_return_speed", "normal")), 10.0))
	_expansion = move_toward(_expansion, target_expansion, delta * return_scale)
	queue_redraw()


func _draw() -> void:
	var settings := _settings()
	var center := size * 0.5
	var style := str(settings.get("crosshair_style", "classic"))
	if style == "hidden": return
	var scale_value := float(settings.get("crosshair_size", 1.0))
	var animation := float(settings.get("crosshair_animation_intensity", 0.5))
	var dynamic_gap := float(settings.get("crosshair_gap", 8.0)) + _expansion * 16.0 * float(settings.get("crosshair_movement_intensity", 0.5))
	dynamic_gap += _pulse * 7.0 * animation
	var length := float(settings.get("crosshair_line_length", 10.0)) * scale_value
	var thickness := float(settings.get("crosshair_thickness", 3.0)) * scale_value
	var color := _color(settings.get("crosshair_color", [0.2, 1.0, 0.12, 1.0]))
	color.a *= float(settings.get("crosshair_opacity", 1.0))
	if _preview_interact > 0.0: color = color.lerp(Color(0.22, 0.9, 1.0, color.a), minf(_preview_interact * 2.0, 0.7))
	if _preview_pickup > 0.0: color = color.lerp(Color(1.0, 0.72, 0.16, color.a), minf(_preview_pickup, 0.75))
	var outline := bool(settings.get("crosshair_outline", true))
	var outline_color := _color(settings.get("crosshair_outline_color", [0.02, 0.02, 0.03, 1.0]))
	outline_color.a *= color.a
	var outline_width := float(settings.get("crosshair_outline_thickness", 2.0))
	var glow := bool(settings.get("crosshair_glow", false))
	if glow:
		_draw_shape(center, style, dynamic_gap, length, color * Color(1, 1, 1, 0.18 * float(settings.get("crosshair_glow_intensity", 0.5))), thickness + 7.0)
	if outline:
		_draw_shape(center, style, dynamic_gap, length, outline_color, thickness + outline_width * 2.0)
	_draw_shape(center, style, dynamic_gap, length, color, thickness)
	if bool(settings.get("crosshair_center_dot", false)) or style in ["dot", "cross_dot"]:
		var radius := float(settings.get("crosshair_dot_size", 3.0)) * scale_value
		if outline: draw_circle(center, radius + outline_width, outline_color)
		draw_circle(center, radius, color)
	var reload := _reload_progress(settings)
	if reload >= 0.0:
		draw_arc(center, dynamic_gap + length + 8.0, -PI * 0.5, -PI * 0.5 + TAU * reload, 28, Color(0.2, 0.9, 1.0, color.a), maxf(2.0, thickness * 0.65), true)


func _draw_shape(center: Vector2, style: String, gap: float, length: float, color: Color, thickness: float) -> void:
	match style:
		"dot": pass
		"ring": draw_arc(center, gap + length * 0.55, 0.0, TAU, 36, color, thickness, true)
		"brackets":
			for side: float in [-1.0, 1.0]:
				var x: float = center.x + side * (gap + length)
				draw_line(Vector2(x, center.y - length), Vector2(center.x + side * gap, center.y - length), color, thickness, true)
				draw_line(Vector2(center.x + side * gap, center.y - length), Vector2(center.x + side * gap, center.y + length), color, thickness, true)
				draw_line(Vector2(center.x + side * gap, center.y + length), Vector2(x, center.y + length), color, thickness, true)
		"chevron":
			draw_line(center + Vector2(-gap - length, -length * 0.5), center + Vector2(0, gap), color, thickness, true)
			draw_line(center + Vector2(gap + length, -length * 0.5), center + Vector2(0, gap), color, thickness, true)
		"minimal":
			draw_line(center + Vector2(-gap - length, 0), center + Vector2(-gap, 0), color, thickness, true)
			draw_line(center + Vector2(gap, 0), center + Vector2(gap + length, 0), color, thickness, true)
		_:
			for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				draw_line(center + direction * gap, center + direction * (gap + length), color, thickness, true)


func _reload_progress(settings: Dictionary) -> float:
	if not bool(settings.get("crosshair_reload_indicator", true)): return -1.0
	if _preview_reload >= 0.0: return clampf(_preview_reload, 0.0, 1.0)
	var gun = _find_gun()
	if gun != null and gun.has_method("get_reload_progress") and not bool(gun.get("can_fire")):
		return clampf(float(gun.get_reload_progress()), 0.0, 1.0)
	return -1.0


func _find_gun():
	if player == null: return null
	if is_instance_valid(_cached_gun) and player.is_ancestor_of(_cached_gun): return _cached_gun
	_cached_gun = null
	for child in player.find_children("*", "", true, false):
		if child.has_method("get_reload_progress"):
			_cached_gun = child
			return child
	return null


func _settings() -> Dictionary:
	if preview_mode: return preview_settings
	return PlayerPrefs.settings if _uses_personal_settings else PlayerPrefs.DEFAULT_SETTINGS


func _color(value) -> Color:
	if value is Color: return value
	if value is Array and value.size() >= 4: return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Color.WHITE


func _has_property_name(property_name: String) -> bool:
	for property in get_property_list():
		if str(property.get("name", "")) == property_name: return true
	return false


func _on_setting_changed(key: String, _value) -> void:
	if key.begins_with("crosshair_"): queue_redraw()


func _on_gun_picked_up(player_name: String) -> void:
	if preview_mode or player == null or not bool(PlayerPrefs.get_setting("crosshair_pickup_feedback")): return
	if player.has_method("get_display_name") and str(player.get_display_name()) == player_name:
		_preview_pickup = 1.0


static func normalized_reload(elapsed: float, duration: float) -> float:
	return 1.0 if duration <= 0.0 else clampf(elapsed / duration, 0.0, 1.0)


static func shape_segment_count(style: String) -> int:
	return {"classic": 4, "dot": 0, "ring": 1, "cross_dot": 4, "brackets": 6, "chevron": 2, "minimal": 2, "hidden": 0}.get(style, 4)
