extends Node

const EFFECTS = ["normal", "knockback", "stagger", "slow"]
const HELD_WEAPON_TARGET_LENGTH := 1.0

func _normalized_held_scale(raw_model_length: float) -> float:
	return HELD_WEAPON_TARGET_LENGTH / maxf(raw_model_length, 0.001)

func _build_sword() -> WeaponData:
	var d = WeaponData.new()
	d.weapon_name = "Sword"
	d.model_scene_path = "res://sword.tscn"
	d.raw_model_length = 4.683345
	d.held_rotation = Vector3(-PI/2, PI, 0)
	d.held_grip_anchor = Vector3(0.0, -0.723, 0.0)
	d.held_scale = _normalized_held_scale(d.raw_model_length)
	d.base_windup_time = 0.08
	d.base_active_time = 0.18
	d.base_recovery_time = 0.25
	d.base_stamina_cost = 15.0
	d.description = "Fast, responsive handling with the shared melee reach."
	return d

func _build_bat() -> WeaponData:
	var d = WeaponData.new()
	d.weapon_name = "Baseball Bat"
	d.model_scene_path = "res://baseball_bat.tscn"
	d.raw_model_length = 1.0
	d.held_rotation = Vector3(-PI/2, PI, 0)
	# The narrow +Z end is the bat's handle; the opposite end is the barrel.
	d.held_grip_anchor = Vector3(0.0, -0.243, 0.5)
	d.held_scale = _normalized_held_scale(d.raw_model_length)
	d.base_windup_time = 0.12
	d.base_active_time = 0.22
	d.base_recovery_time = 0.35
	d.base_stamina_cost = 15.0
	d.description = "Deliberate handling with the shared melee reach."
	return d

func _build_stick() -> WeaponData:
	var d = WeaponData.new()
	d.weapon_name = "Stick"
	d.model_scene_path = "res://stick.tscn"
	d.raw_model_length = 0.465133
	d.held_rotation = Vector3(-PI/2, PI, 0)
	d.held_grip_anchor = Vector3(0.018, 0.0, -0.168)
	d.held_scale = _normalized_held_scale(d.raw_model_length)
	d.base_windup_time = 0.04
	d.base_active_time = 0.12
	d.base_recovery_time = 0.14
	d.base_stamina_cost = 8.0
	d.description = "Very fast handling and low stamina cost."
	return d

func _build_crowbar() -> WeaponData:
	var d = WeaponData.new()
	d.weapon_name = "Crowbar"
	d.model_scene_path = "res://crowbar.tscn"
	d.raw_model_length = 11.9776
	d.held_rotation = Vector3(-PI/2, PI, 0)
	# Grip the straight end, leaving the hooked end away from the paw.
	d.held_grip_anchor = Vector3(0.0, -5.791, -0.276)
	d.held_scale = _normalized_held_scale(d.raw_model_length)
	d.base_windup_time = 0.08
	d.base_active_time = 0.18
	d.base_recovery_time = 0.26
	d.base_stamina_cost = 14.0
	d.description = "Fast, reliable all-rounder handling."
	return d

func _build_frying_pan() -> WeaponData:
	var d = WeaponData.new()
	d.weapon_name = "Frying Pan"
	d.model_scene_path = "res://frying_pan.tscn"
	d.raw_model_length = 2.82463
	d.held_rotation = Vector3(-PI/2, PI, 0)
	d.held_grip_anchor = Vector3(0.0, 0.0, -0.471)
	d.held_scale = _normalized_held_scale(d.raw_model_length)
	d.base_windup_time = 0.32
	d.base_active_time = 0.28
	d.base_recovery_time = 0.55
	d.base_stamina_cost = 22.0
	d.description = "Heavy, committed handling with the shared melee reach."
	return d

var _weapons: Array = []

func _ready():
	_weapons = [
		_build_sword(),
		_build_bat(),
		_build_stick(),
		_build_crowbar(),
		_build_frying_pan(),
	]

func get_random_weapon_data() -> WeaponData:
	var enabled_weapons := _weapons.filter(func(data: WeaponData) -> bool:
		return GameConfig.is_melee_weapon_enabled(data.weapon_name))
	# GameConfig and the lobby both enforce a non-empty pool. Keep this fallback
	# for malformed legacy presets so spawning can never index an empty array.
	if enabled_weapons.is_empty():
		return _weapons[0]
	return enabled_weapons[randi() % enabled_weapons.size()]

func get_weapon_data_by_name(weapon_name: String) -> WeaponData:
	for data in _weapons:
		if data.weapon_name == weapon_name:
			return data
	return null

func get_random_identity() -> Dictionary:
	var data := get_random_weapon_data()
	return {
		"weapon_name": data.weapon_name,
		"effect": get_random_effect(),
	}

func get_random_effect() -> String:
	return EFFECTS[randi() % EFFECTS.size()]

func get_base_stats(data: WeaponData) -> Dictionary:
	return {
		"windup_time":   data.base_windup_time,
		"active_time":   data.base_active_time,
		"recovery_time": data.base_recovery_time,
		"stamina_cost":  data.base_stamina_cost,
	}
