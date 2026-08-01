class_name PlayerSettingsApplier
extends RefCounted

# Applies settings to the actual engine systems. Keeping this separate from
# the menu means startup, Apply, and Cancel restoration all share one path.

const QUALITY_PRESETS := {
	"low": {"shadow_quality": "low", "anti_aliasing": "off", "render_scale": 0.75},
	"medium": {"shadow_quality": "medium", "anti_aliasing": "fxaa", "render_scale": 0.9},
	"high": {"shadow_quality": "high", "anti_aliasing": "fxaa", "render_scale": 1.0},
	"ultra": {"shadow_quality": "ultra", "anti_aliasing": "msaa_4x", "render_scale": 1.0},
}


static func apply_all(values: Dictionary, tree: SceneTree, include_display := true) -> void:
	apply_audio(values)
	apply_video(values, tree, include_display)


static func apply_audio(values: Dictionary) -> void:
	var main_loop := Engine.get_main_loop() as SceneTree
	if main_loop == null:
		return
	var audio := main_loop.root.get_node_or_null("AudioManager")
	if audio == null:
		return
	audio.set_master_volume(float(values.get("master_volume", 1.0)))
	audio.set_music_volume(float(values.get("music_volume", 1.0)))
	audio.set_sfx_volume(float(values.get("sfx_volume", 1.0)))


static func apply_video(values: Dictionary, tree: SceneTree, include_display := true) -> void:
	Engine.max_fps = int(values.get("fps_limit", 0))
	var viewport := tree.root
	_apply_antialiasing(viewport, str(values.get("anti_aliasing", "fxaa")))
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = clampf(float(values.get("render_scale", 1.0)), 0.5, 1.5)
	viewport.positional_shadow_atlas_size = _shadow_atlas_size(str(values.get("shadow_quality", "high")))
	if not include_display or DisplayServer.get_name().to_lower() == "headless":
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(values.get("vsync_enabled", true)) else DisplayServer.VSYNC_DISABLED)
	var resolution = values.get("resolution", [1600, 900])
	var size := Vector2i(int(resolution[0]), int(resolution[1]))
	match str(values.get("display_mode", "windowed")):
		"fullscreen":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(size)
			_center_window(size)


static func apply_quality_preset(values: Dictionary, preset: String) -> void:
	if not QUALITY_PRESETS.has(preset):
		return
	for key in QUALITY_PRESETS[preset]:
		values[key] = QUALITY_PRESETS[preset][key]
	values["quality_preset"] = preset


static func valid_resolutions() -> Array[Vector2i]:
	var common: Array[Vector2i] = [
		Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
		Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440),
		Vector2i(3840, 2160),
	]
	if DisplayServer.get_name().to_lower() == "headless":
		return common
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var filtered: Array[Vector2i] = []
	for resolution in common:
		if resolution.x <= screen.x and resolution.y <= screen.y:
			filtered.append(resolution)
	var current := DisplayServer.window_get_size()
	if current.x >= 640 and current.y >= 480 and current not in filtered:
		filtered.append(current)
	filtered.sort_custom(func(a: Vector2i, b: Vector2i): return a.x * a.y < b.x * b.y)
	return filtered


static func _apply_antialiasing(viewport: Viewport, mode: String) -> void:
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	match mode:
		"fxaa": viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		"msaa_2x": viewport.msaa_3d = Viewport.MSAA_2X
		"msaa_4x": viewport.msaa_3d = Viewport.MSAA_4X


static func _shadow_atlas_size(quality: String) -> int:
	match quality:
		"low": return 1024
		"medium": return 2048
		"ultra": return 8192
		_: return 4096


static func _center_window(size: Vector2i) -> void:
	var screen_index := DisplayServer.window_get_current_screen()
	var screen_pos := DisplayServer.screen_get_position(screen_index)
	var screen_size := DisplayServer.screen_get_size(screen_index)
	DisplayServer.window_set_position(screen_pos + (screen_size - size) / 2)
