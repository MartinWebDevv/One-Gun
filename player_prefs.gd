extends Node

# ============================================================
# PlayerPrefs — persistent, per-player preference settings.
#
# Distinct from GameConfig: GameConfig is match-rules state (resets every
# match; its own preset system handles save/load there). PlayerPrefs is
# personal preference state (volume, sensitivity, etc.) that persists
# across the entire lifetime of the game, auto-saved to disk on every
# change. No presets here — there's only ever one set of personal
# preferences in effect.
#
# setting_changed fires on every change, from any source (main menu's
# Player Settings screen, or the in-match pause menu's Settings overlay).
# Anything that applies a setting once at spawn (camera FOV, crosshair
# color) needs to also listen for this and re-apply live, since those
# aren't re-read every frame the way sensitivity values are.
# ============================================================

signal setting_changed(key: String, value)

const SAVE_PATH := "user://player_prefs.json"

const DEFAULT_SETTINGS := {
	"player_name": "Player 1",
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
	"crosshair_color": [1.0, 1.0, 1.0, 1.0],  # [r, g, b, a] — JSON can't store a Color directly
}

func get_crosshair_color() -> Color:
	var c = get_setting("crosshair_color")
	if c is Array and c.size() >= 4:
		return Color(c[0], c[1], c[2], c[3])
	return Color.WHITE

func set_crosshair_color(color: Color):
	set_setting("crosshair_color", [color.r, color.g, color.b, color.a])

# The currently active settings, applied to gameplay right now.
var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)

func _ready():
	load_from_disk()

func get_setting(key: String):
	return settings.get(key, DEFAULT_SETTINGS.get(key))

func set_setting(key: String, value):
	settings[key] = value
	save_to_disk()
	setting_changed.emit(key, value)

func reset_to_defaults():
	settings = DEFAULT_SETTINGS.duplicate(true)
	save_to_disk()
	for key in settings:
		setting_changed.emit(key, settings[key])

# ------------------------------------------------------------
# Disk persistence
# ------------------------------------------------------------
func save_to_disk():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("PlayerPrefs: failed to open save file for writing: " + SAVE_PATH)
		return
	file.store_string(JSON.stringify(settings))
	file.close()

func load_from_disk():
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("PlayerPrefs: failed to open save file for reading: " + SAVE_PATH)
		return
	var text = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_warning("PlayerPrefs: save file was corrupt or unreadable, using defaults.")
		return

	var merged = DEFAULT_SETTINGS.duplicate(true)
	for key in parsed:
		merged[key] = parsed[key]
	settings = merged
