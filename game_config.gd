extends Node

var split_screen_enabled = false
var lobby_settings_dirty = false
var melee_effects_hit_anyone = false
var player2_name = "Player 2"  # session-only, not saved to disk — P2 may be a different guest each time

# -- Bots --
# Each entry: {"difficulty": "easy"/"medium"/"hard"/"expert", "team_id": int}
# bot_count is derived from this array's size; existing code that reads
# GameConfig.bot_count keeps working unchanged.
var bot_configs: Array = [{"difficulty": "easy", "team_id": -1}]

var bot_count: int:
	get:
		return bot_configs.size()
	set(value):
		set_bot_count(value)

func set_bot_count(count: int):
	count = max(0, count)
	# Hard cap: bots + human players can never exceed 8 total.
	# Split screen has 2 humans so max 6 bots; solo has 1 human so max 7.
	var human_count = 2 if split_screen_enabled else 1
	var max_bots = 8 - human_count
	count = min(count, max_bots)
	while bot_configs.size() < count:
		bot_configs.append({"difficulty": "easy", "team_id": -1})
	while bot_configs.size() > count:
		bot_configs.pop_back()

# -- Team mode --
var teams_enabled = false
var friendly_fire_enabled = false

# -- Round rules --
var melee_eliminates_gunholder = false
var melee_eliminates_anyone = false
var round_time_limit = 0.0  # 0 = no limit
var melee_spawn_delay = 0.0  # seconds after round start before melee weapons can be picked up
var gun_spawn_mode = "center"  # "center" or "random" — read by whatever spawns the gun each round
var disarm_lock_time = 3.0
var max_dash_charges = 2  # clamped 0-6 at spawn time by character_body_3d.gd
var dropped_melee_despawn_time = 3.0  # seconds after a death-drop before the weapon despawns and returns to spawn; <= 0 disables this (weapon stays where dropped, forever)
var melee_weapon_breaking = true  # when true, swinging with zero stamina twice breaks the weapon temporarily

# -- Win conditions --
var rounds_per_set = 3  # rounds a player/team must win to take a set
var sets_per_match = 3  # sets a player/team must win to take the match

# -- Items / hazards / consumables --
# Category toggles act as convenience "select/deselect all" switches.
# The per-item registry below is the actual source of truth checked at spawn time.
var hazards_enabled = true
var consumables_enabled = true

# item_type -> { enabled: bool, category: "hazard" or "consumable" }
var item_registry = {
	"bubble_gum": {"enabled": true, "category": "hazard"}
}

func is_item_enabled(item_type: String) -> bool:
	if not item_registry.has(item_type):
		return true
	var entry = item_registry[item_type]
	if entry["category"] == "hazard" and not hazards_enabled:
		return false
	if entry["category"] == "consumable" and not consumables_enabled:
		return false
	return entry["enabled"]

func set_item_enabled(item_type: String, enabled: bool):
	if item_registry.has(item_type):
		item_registry[item_type]["enabled"] = enabled

func set_category_enabled(category: String, enabled: bool):
	if category == "hazard":
		hazards_enabled = enabled
	elif category == "consumable":
		consumables_enabled = enabled

# Returns true if `attacker` is allowed to affect `target` (melee, disarm,
# knockback, stagger, thrown items, bullets). False only when teams are
# enabled, both have a valid matching team_id, friendly fire is off, and
# they are not the same player.
func can_affect(attacker, target) -> bool:
	if attacker == target:
		return true
	if not teams_enabled:
		return true
	if friendly_fire_enabled:
		return true
	if attacker == null or target == null:
		return true
	if not ("team_id" in attacker) or not ("team_id" in target):
		return true
	if attacker.team_id < 0 or target.team_id < 0:
		return true
	return attacker.team_id != target.team_id

# ============================================================
# Match-settings presets — up to 5 disk-saved slots, each a full
# snapshot of every rule toggle plus the bot setup, so a host can
# save a ruleset and load it back into a future lobby instantly.
# This is intentionally separate from PlayerPrefs (personal, no
# slots, always-on auto-save) — this is shared "house rules" state.
# ============================================================

const PRESET_SAVE_PATH := "user://match_preset_slots.json"
const MAX_PRESET_SLOTS := 5

# The fields captured in every preset snapshot. Keep this list as the
# single source of truth for what a preset includes — adding a new
# match-rule field later just means adding its name here.
const PRESET_FIELDS := [
	"teams_enabled",
	"friendly_fire_enabled",
	"melee_eliminates_gunholder",
	"melee_eliminates_anyone",
	"melee_spawn_delay",
	"gun_spawn_mode",
	"disarm_lock_time",
	"max_dash_charges",
	"dropped_melee_despawn_time",
	"melee_weapon_breaking",
	"rounds_per_set",
	"sets_per_match",
	"hazards_enabled",
	"consumables_enabled",
	"item_registry",
	"bot_configs",
]

# Engine defaults for every field above — the values a fresh game launch
# (or "Default" button press) restores. Kept separate from PRESET_FIELDS'
# order so this reads clearly as "what is default," not "what gets saved."
const DEFAULT_VALUES := {
	"teams_enabled": false,
	"friendly_fire_enabled": false,
	"melee_eliminates_gunholder": false,
	"melee_eliminates_anyone": false,
	"melee_spawn_delay": 0.0,
	"gun_spawn_mode": "center",
	"disarm_lock_time": 3.0,
	"max_dash_charges": 2,
	"dropped_melee_despawn_time": 3.0,
	"melee_weapon_breaking": true,
	"rounds_per_set": 3,
	"sets_per_match": 3,
	"hazards_enabled": true,
	"consumables_enabled": true,
	"item_registry": {"bubble_gum": {"enabled": true, "category": "hazard"}},
	"bot_configs": [{"difficulty": "easy", "team_id": -1}],
}

func reset_match_settings_to_defaults():
	apply_preset_values(DEFAULT_VALUES)
	lobby_settings_dirty = false

# preset_slots[slot_index] = {"name": String, "values": Dictionary} or null.
var preset_slots: Array = []

func _ready():
	preset_slots.resize(MAX_PRESET_SLOTS)
	_load_presets_from_disk()

func snapshot_for_preset() -> Dictionary:
	var values = {}
	for field in PRESET_FIELDS:
		var value = get(field)
		# Deep-copy any Array/Dictionary fields so later changes to the
		# live GameConfig state can't reach back and mutate a saved preset.
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		values[field] = value
	return values

func apply_preset_values(values: Dictionary):
	for field in PRESET_FIELDS:
		if not values.has(field):
			continue
		var value = values[field]
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		set(field, value)

func save_preset_slot(slot_index: int, preset_name: String):
	if slot_index < 0 or slot_index >= MAX_PRESET_SLOTS:
		return
	preset_slots[slot_index] = {
		"name": preset_name,
		"values": snapshot_for_preset(),
	}
	_save_presets_to_disk()

func load_preset_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_PRESET_SLOTS:
		return false
	var slot = preset_slots[slot_index]
	if slot == null:
		return false
	apply_preset_values(slot["values"])
	return true

func delete_preset_slot(slot_index: int):
	if slot_index < 0 or slot_index >= MAX_PRESET_SLOTS:
		return
	preset_slots[slot_index] = null
	_save_presets_to_disk()

func get_preset_slot_name(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= MAX_PRESET_SLOTS:
		return ""
	var slot = preset_slots[slot_index]
	if slot == null:
		return "(empty)"
	return slot["name"]

func is_preset_slot_empty(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_PRESET_SLOTS:
		return true
	return preset_slots[slot_index] == null

func _save_presets_to_disk():
	var file = FileAccess.open(PRESET_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("GameConfig: failed to open preset save file for writing: " + PRESET_SAVE_PATH)
		return
	file.store_string(JSON.stringify(preset_slots))
	file.close()

func _load_presets_from_disk():
	if not FileAccess.file_exists(PRESET_SAVE_PATH):
		return
	var file = FileAccess.open(PRESET_SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("GameConfig: failed to open preset save file for reading: " + PRESET_SAVE_PATH)
		return
	var text = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Array):
		push_warning("GameConfig: preset save file was corrupt or unreadable.")
		return

	preset_slots.resize(MAX_PRESET_SLOTS)
	for i in min(parsed.size(), MAX_PRESET_SLOTS):
		preset_slots[i] = parsed[i]
