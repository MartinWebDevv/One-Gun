extends Node

const EFFECTS = ["normal", "knockback", "stagger", "slow"]

func _build_sword() -> WeaponData:
	var d = WeaponData.new()
	d.weapon_name = "Sword"
	d.model_scene_path = "res://sword.tscn"
	d.reach_multiplier = 1.5
	d.held_rotation = Vector3(-PI/2, PI, 0)
	# Sword_Eternity.glb is raw-exported at ~4.68 units long (measured via its
	# mesh AABB) — at scale 1.0 that's a ~4.7m sword in a 1-unit-per-meter
	# world. Scaled to land around ~1.2m; re-tune visually if it looks off.
	d.held_scale = 0.25
	d.swing_windup_offset = Vector3(-0.3, 0.5, -0.6)
	d.swing_followthrough_offset = Vector3(0.5, -0.5, 0.7)
	d.base_windup_time = 0.08
	d.base_active_time = 0.18
	d.base_recovery_time = 0.25
	d.base_stamina_cost = 15.0
	d.description = "Long reach, fast swing. Best tool for disarming from a safe distance."
	return d

func _build_bat() -> WeaponData:
	var d = WeaponData.new()
	d.weapon_name = "Baseball Bat"
	d.model_scene_path = "res://baseball_bat.tscn"
	d.reach_multiplier = 1.3
	d.held_rotation = Vector3(-PI/2, PI, 0)
	d.held_scale = 1.0
	d.swing_windup_offset = Vector3(-0.25, 0.6, -0.8)
	d.swing_followthrough_offset = Vector3(0.45, -0.6, 0.9)
	d.base_windup_time = 0.12
	d.base_active_time = 0.22
	d.base_recovery_time = 0.35
	d.base_stamina_cost = 15.0
	d.description = "Long reach, wide arc. Knockback effect sends the gunman flying."
	return d

func _build_stick() -> WeaponData:
	var d = WeaponData.new()
	d.weapon_name = "Stick"
	d.model_scene_path = "res://stick.tscn"
	d.reach_multiplier = 0.75
	d.held_rotation = Vector3(-PI/2, PI, 0)
	# Stick.glb is raw-exported at ~0.47 units long; bumped up from 1.0
	# (looked too small in-hand). Re-tune visually if still off.
	d.held_scale = 1.4
	d.swing_windup_offset = Vector3(-0.15, 0.3, -0.4)
	d.swing_followthrough_offset = Vector3(0.2, -0.3, 0.5)
	d.base_windup_time = 0.04
	d.base_active_time = 0.12
	d.base_recovery_time = 0.14
	d.base_stamina_cost = 8.0
	d.description = "Short reach, very fast, almost no stamina cost. Ideal for aggressive rushers."
	return d

func _build_crowbar() -> WeaponData:
	var d = WeaponData.new()
	d.weapon_name = "Crowbar"
	d.model_scene_path = "res://crowbar.tscn"
	d.reach_multiplier = 1.1
	d.held_rotation = Vector3(-PI/2, PI, 0)
	# Crowbar.glb is raw-exported at ~11.98 units long — scaled down to land
	# around ~0.55m, then bumped up (looked too small in-hand). Re-tune
	# visually if still off.
	d.held_scale = 0.065
	d.swing_windup_offset = Vector3(-0.28, 0.45, -0.55)
	d.swing_followthrough_offset = Vector3(0.42, -0.45, 0.65)
	d.base_windup_time = 0.08
	d.base_active_time = 0.18
	d.base_recovery_time = 0.26
	d.base_stamina_cost = 14.0
	d.description = "Medium reach, fast swing, reliable all-rounder."
	return d

func _build_frying_pan() -> WeaponData:
	var d = WeaponData.new()
	d.weapon_name = "Frying Pan"
	d.model_scene_path = "res://frying_pan.tscn"
	d.reach_multiplier = 0.7
	d.held_rotation = Vector3(-PI/2, PI, 0)
	# FryingPan.glb is raw-exported at ~2.83 units long (handle to pan edge) —
	# scaled down to land around ~0.55m, then bumped up (looked too small
	# in-hand). Re-tune visually if still off.
	d.held_scale = 0.28
	d.swing_windup_offset = Vector3(-0.4, 0.7, -0.9)
	d.swing_followthrough_offset = Vector3(0.6, -0.7, 1.1)
	d.base_windup_time = 0.32
	d.base_active_time = 0.28
	d.base_recovery_time = 0.55
	d.base_stamina_cost = 22.0
	d.description = "Short reach, very slow, very wide arc. Devastating in corridors and ambushes."
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
	return _weapons[randi() % _weapons.size()]

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
		"tier": get_random_tier(),
	}

func get_random_effect() -> String:
	return EFFECTS[randi() % EFFECTS.size()]

func get_random_tier() -> int:
	# T1 common (60%), T2 uncommon (30%), T3 rare (10%).
	# Finding a high tier should feel like discovering loot, not a certainty.
	var roll = randi() % 100
	if roll < 60:
		return 1
	elif roll < 90:
		return 2
	else:
		return 3

func get_stats_for_tier(data: WeaponData, tier: int) -> Dictionary:
	var tier_mult: float
	match tier:
		2: tier_mult = 0.82
		3: tier_mult = 0.65
		_: tier_mult = 1.0

	var recovery_mult: float
	match tier:
		2: recovery_mult = 0.80
		3: recovery_mult = 0.60
		_: recovery_mult = 1.0

	return {
		"windup_time":   data.base_windup_time * tier_mult,
		"active_time":   data.base_active_time,
		"recovery_time": data.base_recovery_time * recovery_mult,
		"stamina_cost":  max(data.base_stamina_cost * tier_mult, data.base_stamina_cost * 0.6),
	}

# Stagger bullet immunity durations by tier — protects the disarmed gunholder,
# giving them a window to escape after being hit.
# Higher tier = longer escape window. T3 was previously 0 (bug — now fixed).
const STAGGER_IMMUNITY_BY_TIER = [1.0, 1.5, 2.0]

func get_stagger_immunity_duration(tier: int) -> float:
	return STAGGER_IMMUNITY_BY_TIER[clamp(tier - 1, 0, 2)]
