extends Node

# Persistent, local-only player preferences. Match rules belong to GameConfig.
# The UI edits a pending copy and commits through apply_transaction(), so
# Cancel never leaks partial values to disk or gameplay.

signal setting_changed(key: String, value)

const SAVE_PATH := "user://player_prefs.json"
const BACKUP_PATH := "user://player_prefs.backup.json"
const TEMP_PATH := "user://player_prefs.pending.json"
const SETTINGS_VERSION := 4
const SETTINGS_APPLIER = preload("res://UI/player_settings_applier.gd")

const DEFAULT_SETTINGS := {
	"player_name": "Player 1",
	"character_skin_id": "blue",
	"master_volume": 1.0,
	"music_volume": 1.0,
	"sfx_volume": 1.0,
	"mouse_sensitivity": 1.0,
	"gamepad_sensitivity": 6.0,
	"ads_sensitivity_multiplier": 0.5,
	"gamepad_response_curve_exponent": 2.0,
	"gamepad_sprint_is_toggle": true,
	"mouse_keyboard_sprint_is_toggle": false,
	"field_of_view": 75.0,
	"invert_look_y": false,
	"ui_scale": 1.0,
	"text_size": "normal",
	"colorblind_filter": "off",
	"high_contrast_ui": false,
	"screen_shake_intensity": 1.0,
	"camera_bob_intensity": 1.0,
	"reduce_flashing": false,
	"motion_blur": false,
	"reduced_motion": false,
	"protection_icon_size": 1.0,
	"extra_life_icon_color": [1.0, 0.72, 0.18, 1.0],
	"sticky_hands_icon_color": [0.2, 1.0, 0.35, 1.0],
	"crosshair_style": "classic",
	"crosshair_color": [0.2, 1.0, 0.12, 1.0],
	"crosshair_size": 1.0,
	"crosshair_thickness": 3.0,
	"crosshair_gap": 8.0,
	"crosshair_line_length": 10.0,
	"crosshair_center_dot": false,
	"crosshair_dot_size": 3.0,
	"crosshair_opacity": 1.0,
	"crosshair_outline": true,
	"crosshair_outline_color": [0.02, 0.02, 0.03, 1.0],
	"crosshair_outline_thickness": 2.0,
	"crosshair_glow": false,
	"crosshair_glow_intensity": 0.5,
	"crosshair_behavior_mode": "static",
	"crosshair_movement_expansion": false,
	"crosshair_movement_intensity": 0.5,
	"crosshair_return_speed": "normal",
	"crosshair_fire_pulse": true,
	"crosshair_reload_indicator": true,
	"crosshair_pickup_feedback": true,
	"crosshair_interactable_feedback": true,
	"crosshair_animation_intensity": 0.5,
	"crosshair_animation_speed": "normal",
	"reduce_crosshair_motion": false,
	"crosshair_preview_background": "dark",
	"hit_marker_enabled": true,
	"hit_marker_style": "x",
	"hit_marker_color": [1.0, 1.0, 1.0, 1.0],
	"hit_marker_size": 1.0,
	"hit_marker_thickness": 2.5,
	"hit_marker_opacity": 1.0,
	"hit_marker_duration": 0.28,
	"hit_marker_sound": true,
	"hit_marker_volume": 0.55,
	"elimination_marker_enabled": true,
	"elimination_marker_style": "gold_star",
	"elimination_marker_color": [1.0, 0.72, 0.16, 1.0],
	"elimination_marker_size": 1.15,
	"elimination_marker_opacity": 1.0,
	"elimination_marker_duration": 0.48,
	"elimination_marker_sound": true,
	"elimination_marker_volume": 0.7,
	"display_mode": "windowed",
	"resolution": [1600, 900],
	"vsync_enabled": true,
	"fps_limit": 0,
	"quality_preset": "high",
	"shadow_quality": "high",
	"anti_aliasing": "fxaa",
	"render_scale": 1.0,
	# action -> {"keyboard_mouse": [event descriptors], "gamepad": [...]}
	"input_overrides": {},
}

var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var _project_default_bindings: Dictionary = {}


func _ready() -> void:
	_capture_project_default_bindings()
	load_from_disk()
	apply_input_overrides()
	SETTINGS_APPLIER.apply_video(settings, get_tree())


func snapshot() -> Dictionary:
	return settings.duplicate(true)


func get_setting(key: String):
	return settings.get(key, DEFAULT_SETTINGS.get(key))


func get_default(key: String):
	return DEFAULT_SETTINGS.get(key)


func set_setting(key: String, value) -> void:
	var next := snapshot()
	next[key] = value
	apply_transaction(next)


func apply_transaction(values: Dictionary) -> bool:
	var next := _normalize(values)
	if not _save_dictionary(next):
		return false
	var previous := settings
	settings = next
	apply_input_overrides()
	for key in settings:
		if not previous.has(key) or previous[key] != settings[key]:
			setting_changed.emit(str(key), settings[key])
	return true


func reset_to_defaults() -> void:
	apply_transaction(DEFAULT_SETTINGS.duplicate(true))


func get_crosshair_color() -> Color:
	var c = get_setting("crosshair_color")
	if c is Array and c.size() >= 4:
		return Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]))
	return Color.WHITE


func set_crosshair_color(color: Color) -> void:
	set_setting("crosshair_color", [color.r, color.g, color.b, color.a])


# -----------------------------------------------------------------------------
# Input bindings
# -----------------------------------------------------------------------------

func _capture_project_default_bindings() -> void:
	_project_default_bindings.clear()
	for action_name in InputMap.get_actions():
		var action := str(action_name)
		_project_default_bindings[action] = {
			"keyboard_mouse": _events_to_descriptors(InputMap.action_get_events(action), "keyboard_mouse"),
			"gamepad": _events_to_descriptors(InputMap.action_get_events(action), "gamepad"),
		}


func get_binding_descriptors(action: String, device_group: String,
		use_project_defaults := false) -> Array:
	var source: Dictionary = _project_default_bindings if use_project_defaults else get_setting("input_overrides")
	if source.has(action) and source[action] is Dictionary:
		var stored = source[action].get(device_group, [])
		if stored is Array:
			return stored.duplicate(true)
	if not use_project_defaults and _project_default_bindings.has(action):
		return (_project_default_bindings[action].get(device_group, []) as Array).duplicate(true)
	return []


func set_input_bindings(bindings: Dictionary) -> bool:
	var next := snapshot()
	next["input_overrides"] = bindings.duplicate(true)
	return apply_transaction(next)


func reset_input_overrides() -> void:
	var next := snapshot()
	next["input_overrides"] = {}
	apply_transaction(next)


func apply_input_overrides() -> void:
	apply_input_binding_map(get_setting("input_overrides"))


func apply_input_binding_map(overrides) -> void:
	# Rebuild from project defaults each time so saved commits and the settings
	# screen's reversible live preview use exactly the same application path.
	InputMap.load_from_project_settings()
	if not overrides is Dictionary:
		return
	for action_key in overrides:
		var action := str(action_key)
		if not InputMap.has_action(action) or not overrides[action_key] is Dictionary:
			continue
		for group in ["keyboard_mouse", "gamepad"]:
			if not overrides[action_key].has(group):
				continue
			_erase_group_events(action, group)
			var descriptors = overrides[action_key][group]
			if descriptors is Array:
				for descriptor in descriptors:
					if descriptor is Dictionary:
						var event := descriptor_to_event(descriptor)
						if event != null:
							InputMap.action_add_event(action, event)


func event_to_descriptor(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		return {"type": "key", "code": int(key.physical_keycode if key.physical_keycode != 0 else key.keycode)}
	if event is InputEventMouseButton:
		return {"type": "mouse_button", "button": int((event as InputEventMouseButton).button_index)}
	if event is InputEventJoypadButton:
		return {"type": "joy_button", "button": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {"type": "joy_axis", "axis": int(motion.axis), "direction": 1 if motion.axis_value >= 0.0 else -1}
	return {}


func descriptor_to_event(descriptor: Dictionary) -> InputEvent:
	match str(descriptor.get("type", "")):
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(descriptor.get("code", 0)) as Key
			return key
		"mouse_button":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(descriptor.get("button", 0)) as MouseButton
			return mouse
		"joy_button":
			var button := InputEventJoypadButton.new()
			button.button_index = int(descriptor.get("button", 0)) as JoyButton
			return button
		"joy_axis":
			var axis := InputEventJoypadMotion.new()
			axis.axis = int(descriptor.get("axis", 0)) as JoyAxis
			axis.axis_value = float(descriptor.get("direction", 1))
			return axis
	return null


func descriptor_label(descriptor: Dictionary) -> String:
	var event := descriptor_to_event(descriptor)
	if event == null:
		return "UNBOUND"
	return event.as_text().replace(" (Physical)", "").to_upper()


func _events_to_descriptors(events: Array, group: String) -> Array:
	var result: Array = []
	for event in events:
		if _event_matches_group(event, group):
			var descriptor := event_to_descriptor(event)
			if not descriptor.is_empty():
				result.append(descriptor)
	return result


func _event_matches_group(event: InputEvent, group: String) -> bool:
	if group == "keyboard_mouse":
		return event is InputEventKey or event is InputEventMouseButton
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


func _erase_group_events(action: String, group: String) -> void:
	for event in InputMap.action_get_events(action):
		if _event_matches_group(event, group):
			InputMap.action_erase_event(action, event)


# Compatibility for older callers. New settings UI uses two binding slots.
func set_input_override(action: String, device_class: String, code: int) -> void:
	var group := "gamepad" if device_class == "joy" else "keyboard_mouse"
	var descriptor: Dictionary
	match device_class:
		"key": descriptor = {"type": "key", "code": code}
		"mouse": descriptor = {"type": "mouse_button", "button": code}
		_: descriptor = {"type": "joy_button", "button": code}
	var overrides: Dictionary = get_setting("input_overrides").duplicate(true)
	var per_action: Dictionary = overrides.get(action, {})
	per_action[group] = [descriptor]
	overrides[action] = per_action
	set_input_bindings(overrides)


# -----------------------------------------------------------------------------
# Validation, migration, and recoverable persistence
# -----------------------------------------------------------------------------

func _normalize(values: Dictionary) -> Dictionary:
	var normalized := DEFAULT_SETTINGS.duplicate(true)
	for key in values:
		if normalized.has(key):
			normalized[key] = values[key]
	normalized["player_name"] = str(normalized["player_name"]).strip_edges().substr(0, 24)
	if normalized["player_name"] == "": normalized["player_name"] = "Player 1"
	normalized["character_skin_id"] = PlayerSkinRegistry.sanitize_skin_id(
		str(normalized["character_skin_id"]))
	for key in ["master_volume", "music_volume", "sfx_volume"]:
		normalized[key] = clampf(float(normalized[key]), 0.0, 1.0)
	normalized["mouse_sensitivity"] = clampf(float(normalized["mouse_sensitivity"]), 0.1, 5.0)
	normalized["gamepad_sensitivity"] = clampf(float(normalized["gamepad_sensitivity"]), 1.0, 15.0)
	normalized["ads_sensitivity_multiplier"] = clampf(float(normalized["ads_sensitivity_multiplier"]), 0.05, 1.0)
	normalized["gamepad_response_curve_exponent"] = clampf(float(normalized["gamepad_response_curve_exponent"]), 0.5, 4.0)
	normalized["field_of_view"] = clampf(float(normalized["field_of_view"]), 60.0, 110.0)
	normalized["render_scale"] = clampf(float(normalized["render_scale"]), 0.5, 1.5)
	normalized["ui_scale"] = clampf(float(normalized["ui_scale"]), 0.8, 1.25)
	for key in ["screen_shake_intensity", "camera_bob_intensity", "crosshair_opacity",
			"crosshair_glow_intensity", "crosshair_movement_intensity", "crosshair_animation_intensity",
			"hit_marker_opacity", "hit_marker_volume", "elimination_marker_opacity", "elimination_marker_volume"]:
		normalized[key] = clampf(float(normalized[key]), 0.0, 1.0)
	for key in ["crosshair_size", "hit_marker_size", "elimination_marker_size", "protection_icon_size"]:
		normalized[key] = clampf(float(normalized[key]), 0.5, 2.0)
	normalized["crosshair_thickness"] = clampf(float(normalized["crosshair_thickness"]), 1.0, 8.0)
	normalized["crosshair_gap"] = clampf(float(normalized["crosshair_gap"]), 0.0, 30.0)
	normalized["crosshair_line_length"] = clampf(float(normalized["crosshair_line_length"]), 2.0, 30.0)
	normalized["crosshair_dot_size"] = clampf(float(normalized["crosshair_dot_size"]), 1.0, 10.0)
	normalized["crosshair_outline_thickness"] = clampf(float(normalized["crosshair_outline_thickness"]), 0.0, 6.0)
	normalized["hit_marker_thickness"] = clampf(float(normalized["hit_marker_thickness"]), 1.0, 8.0)
	normalized["hit_marker_duration"] = clampf(float(normalized["hit_marker_duration"]), 0.08, 1.5)
	normalized["elimination_marker_duration"] = clampf(float(normalized["elimination_marker_duration"]), 0.08, 2.0)
	normalized["fps_limit"] = int(normalized["fps_limit"])
	if normalized["fps_limit"] not in [0, 30, 60, 120, 144, 240]: normalized["fps_limit"] = 0
	if str(normalized["display_mode"]) not in ["windowed", "borderless", "fullscreen"]: normalized["display_mode"] = "windowed"
	if str(normalized["quality_preset"]) not in ["low", "medium", "high", "ultra", "custom"]: normalized["quality_preset"] = "high"
	if str(normalized["shadow_quality"]) not in ["low", "medium", "high", "ultra"]: normalized["shadow_quality"] = "high"
	if str(normalized["anti_aliasing"]) not in ["off", "fxaa", "msaa_2x", "msaa_4x"]: normalized["anti_aliasing"] = "fxaa"
	if str(normalized["text_size"]) not in ["small", "normal", "large", "extra_large"]: normalized["text_size"] = "normal"
	if str(normalized["colorblind_filter"]) not in ["off", "protanopia", "deuteranopia", "tritanopia"]: normalized["colorblind_filter"] = "off"
	if str(normalized["crosshair_style"]) not in ["classic", "dot", "ring", "cross_dot", "brackets", "chevron", "minimal", "hidden"]: normalized["crosshair_style"] = "classic"
	if str(normalized["crosshair_behavior_mode"]) not in ["static", "movement", "full_dynamic"]: normalized["crosshair_behavior_mode"] = "static"
	if str(normalized["crosshair_return_speed"]) not in ["slow", "normal", "fast"]: normalized["crosshair_return_speed"] = "normal"
	if str(normalized["crosshair_animation_speed"]) not in ["slow", "normal", "fast"]: normalized["crosshair_animation_speed"] = "normal"
	if str(normalized["crosshair_preview_background"]) not in ["dark", "bright", "forest", "desert", "neon"]: normalized["crosshair_preview_background"] = "dark"
	if str(normalized["hit_marker_style"]) not in ["x", "diamond", "ticks"]: normalized["hit_marker_style"] = "x"
	if str(normalized["elimination_marker_style"]) not in ["gold_star", "toy_splash", "skull_star", "expanding_ring"]: normalized["elimination_marker_style"] = "gold_star"
	var resolution = normalized["resolution"]
	if not resolution is Array or resolution.size() < 2:
		normalized["resolution"] = [1600, 900]
	else:
		normalized["resolution"] = [clampi(int(resolution[0]), 640, 7680), clampi(int(resolution[1]), 480, 4320)]
	for key in ["vsync_enabled", "gamepad_sprint_is_toggle", "mouse_keyboard_sprint_is_toggle", "invert_look_y",
			"high_contrast_ui", "reduce_flashing", "motion_blur", "reduced_motion", "crosshair_center_dot",
			"crosshair_outline", "crosshair_glow", "crosshair_movement_expansion", "crosshair_fire_pulse",
			"crosshair_reload_indicator", "crosshair_pickup_feedback", "crosshair_interactable_feedback",
			"reduce_crosshair_motion", "hit_marker_enabled", "hit_marker_sound", "elimination_marker_enabled",
			"elimination_marker_sound"]:
		normalized[key] = bool(normalized[key])
	for key in ["crosshair_color", "crosshair_outline_color", "hit_marker_color", "elimination_marker_color",
			"extra_life_icon_color", "sticky_hands_icon_color"]:
		var color_value = normalized[key]
		if not color_value is Array or color_value.size() < 4:
			normalized[key] = DEFAULT_SETTINGS[key].duplicate()
		else:
			normalized[key] = [clampf(float(color_value[0]), 0.0, 1.0), clampf(float(color_value[1]), 0.0, 1.0), clampf(float(color_value[2]), 0.0, 1.0), clampf(float(color_value[3]), 0.0, 1.0)]
	if not normalized["input_overrides"] is Dictionary: normalized["input_overrides"] = {}
	return normalized


func save_to_disk() -> void:
	_save_dictionary(settings)


func _save_dictionary(values: Dictionary) -> bool:
	var envelope := {"version": SETTINGS_VERSION, "settings": values}
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("PlayerPrefs: failed to open temporary settings file.")
		return false
	file.store_string(JSON.stringify(envelope, "\t"))
	file.flush()
	file.close()
	var target := ProjectSettings.globalize_path(SAVE_PATH)
	var backup := ProjectSettings.globalize_path(BACKUP_PATH)
	var pending := ProjectSettings.globalize_path(TEMP_PATH)
	if FileAccess.file_exists(BACKUP_PATH): DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(SAVE_PATH):
		if DirAccess.rename_absolute(target, backup) != OK:
			DirAccess.remove_absolute(pending)
			return false
	var err := DirAccess.rename_absolute(pending, target)
	if err != OK:
		if FileAccess.file_exists(BACKUP_PATH): DirAccess.rename_absolute(backup, target)
		return false
	return true


func load_from_disk() -> void:
	var loaded = _load_dictionary(SAVE_PATH)
	if loaded == null:
		loaded = _load_dictionary(BACKUP_PATH)
	if loaded == null:
		settings = DEFAULT_SETTINGS.duplicate(true)
		return
	settings = _normalize(_migrate(loaded))


func _load_dictionary(path: String):
	if not FileAccess.file_exists(path): return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else null


func _migrate(raw: Dictionary) -> Dictionary:
	var version := int(raw.get("version", 0))
	var migrated: Dictionary = raw.get("settings", raw).duplicate(true)
	if version < 2:
		migrated["input_overrides"] = _migrate_legacy_bindings(migrated.get("input_overrides", {}))
	return migrated


func _migrate_legacy_bindings(legacy) -> Dictionary:
	if not legacy is Dictionary: return {}
	var result := {}
	for action_key in legacy:
		if not legacy[action_key] is Dictionary: continue
		var keyboard_mouse: Array = []
		var gamepad: Array = []
		if legacy[action_key].has("key"): keyboard_mouse.append({"type": "key", "code": int(legacy[action_key]["key"])})
		if legacy[action_key].has("mouse"): keyboard_mouse.append({"type": "mouse_button", "button": int(legacy[action_key]["mouse"])})
		if legacy[action_key].has("joy"): gamepad.append({"type": "joy_button", "button": int(legacy[action_key]["joy"])})
		result[str(action_key)] = {"keyboard_mouse": keyboard_mouse, "gamepad": gamepad}
	return result
