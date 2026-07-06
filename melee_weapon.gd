extends RigidBody3D

# ============================================================
# melee_weapon.gd — data-driven melee weapon.
#
# Visual model, reach, swing timing, stamina cost, and held
# orientation all come from a WeaponData resource (set by
# MeleeWeaponRegistry at spawn via apply_weapon_data()).
#
# Core rules that NEVER change regardless of tier or data:
#   - One successful hit always disarms the gun holder.
#   - Tiers NEVER increase damage.
#   - Effects NEVER change damage.
# ============================================================

# ---- Runtime weapon identity ----
var weapon_data: WeaponData = null
var effect_category: String = "normal"   # "normal" | "knockback" | "stagger"
var tier: int = 1

# ---- Cached tier-adjusted stats (read from registry each time tier changes) ----
var _windup_time: float = 0.1
var _active_time: float = 0.2
var _recovery_time: float = 0.3
var _stamina_cost: float = 15.0

# ---- Per-effect magnitudes by tier ----
# Effects never change damage — only repositioning/control duration.
const KNOCKBACK_DISTANCE_BY_TIER = [2.0, 3.0, 4.0]
const STAGGER_DURATION_BY_TIER   = [1.0, 1.5, 2.0]
const KNOCKBACK_IMMUNITY_BY_TIER = [1.5, 1.0, 0.0]

# ---- Fixed physics constants ----
const THROW_IMPULSE         = 8.0
const THROW_PICKUP_LOCK_TIME = 1.0
const BREAK_RESPAWN_TIME    = 5.0

# ---- Runtime state ----
var player_ref = null
var is_held           := false
var is_swinging       := false
var is_in_flight      := false
var deficit_swing_count := 0
var pickup_locked     := false
var swing_tween: Tween = null

var despawn_timer_active     := false
var despawn_timer_generation := 0

var spawn_position := Vector3.ZERO
var spawn_rotation := Vector3.ZERO

# ---- Held model reference ----
var _model_instance: Node3D = null

# ============================================================
# Initialisation
# ============================================================

func _ready():
	add_to_group("weapon")
	add_to_group("melee")
	$Area3D.body_entered.connect(_on_pickup_area_entered)
	$Area3D.body_exited.connect(_on_pickup_area_exited)
	$HitBox.body_entered.connect(_on_hit_landed)
	$HitBox.monitoring = false
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_flight_body_entered)
	spawn_position = global_position
	spawn_rotation  = global_rotation
	_update_pickup_label()
	# Apply a random weapon identity on first spawn including random tier.
	# round_manager.gd calls randomize_attributes() each round for a fresh roll.
	apply_weapon_data(
		MeleeWeaponRegistry.get_random_weapon_data(),
		MeleeWeaponRegistry.get_random_effect(),
		MeleeWeaponRegistry.get_random_tier()
	)

func apply_weapon_data(data: WeaponData, effect: String, new_tier: int):
	weapon_data    = data
	effect_category = effect
	tier           = new_tier

	# Cache tier-adjusted stats.
	var stats = MeleeWeaponRegistry.get_stats_for_tier(data, tier)
	_windup_time   = stats["windup_time"]
	_active_time   = stats["active_time"]
	_recovery_time = stats["recovery_time"]
	_stamina_cost  = stats["stamina_cost"]

	# Swap in the correct visual model.
	_swap_model(data)

	# Resize the hit box to match this weapon's reach.
	_apply_reach(data.reach_multiplier)

	_update_pickup_label()

func _swap_model(data: WeaponData):
	# Remove any previous model.
	if _model_instance != null and is_instance_valid(_model_instance):
		_model_instance.queue_free()
		_model_instance = null

	if data.model_scene_path == "":
		return

	var packed = load(data.model_scene_path)
	if packed == null:
		push_warning("MeleeWeapon: could not load model at '%s'" % data.model_scene_path)
		return

	_model_instance = packed.instantiate() if packed is PackedScene else packed
	add_child(_model_instance)
	_model_instance.scale = Vector3.ONE * data.held_scale

func _apply_reach(multiplier: float):
	var shape_node = $HitBox/CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return
	# Always work from the original shape resource dimensions,
	# not from whatever the previous weapon left behind.
	var shape = shape_node.shape.duplicate()
	shape_node.shape = shape
	if shape is SphereShape3D:
		shape.radius *= multiplier
	elif shape is CapsuleShape3D or shape is CylinderShape3D:
		shape.radius *= multiplier

# ============================================================
# Per-frame
# ============================================================

func _process(_delta):
	if is_swinging or weapon_data == null:
		return
	if is_held and player_ref != null and player_ref.has_method("get_aim_pitch"):
		rotation.x = weapon_data.held_rotation.x + player_ref.get_aim_pitch()
	elif not is_held and not is_in_flight:
		# Refresh the pickup label every frame while on the ground so the
		# button prompt correctly reflects whichever player walks nearby.
		_update_pickup_label()

# ============================================================
# Display
# ============================================================

func get_display_name() -> String:
	var wname = weapon_data.weapon_name if weapon_data != null else "Melee"
	var effect_label = effect_category.capitalize() if effect_category != "normal" else ""
	var tier_label = " (T" + str(tier) + ")"
	if effect_label != "":
		return wname + " — " + effect_label + tier_label
	return wname + tier_label

func randomize_attributes():
	# Called by round_manager.gd at the start of each round.
	# Full re-roll every round — weapon, effect, and tier all change.
	apply_weapon_data(
		MeleeWeaponRegistry.get_random_weapon_data(),
		MeleeWeaponRegistry.get_random_effect(),
		MeleeWeaponRegistry.get_random_tier()
	)

func upgrade_tier():
	# Called when a player purchases a tier upgrade (future system).
	var new_tier = clamp(tier + 1, 1, 3)
	if new_tier == tier:
		return
	apply_weapon_data(weapon_data, effect_category, new_tier)

# ============================================================
# Pickup / drop / throw
# ============================================================

func _on_pickup_area_entered(body):
	if body.has_method("register_interactable"):
		body.register_interactable(self)

func _on_pickup_area_exited(body):
	if body.has_method("unregister_interactable"):
		body.unregister_interactable(self)

func try_swing():
	if not is_held or is_swinging:
		return
	swing()

func try_throw():
	if not is_held or is_swinging:
		return
	throw()

func pick_up(p = null):
	if pickup_locked or is_held:
		return
	despawn_timer_generation += 1
	despawn_timer_active = false
	if p == null:
		p = player_ref
	if p == null:
		return
	if p.holding_gun:
		var gun_hold_point = p.get_hold_point()
		if gun_hold_point.get_child_count() > 0:
			gun_hold_point.get_child(0).drop()
	is_held      = true
	is_in_flight = false
	freeze       = true
	$CollisionShape3D.disabled = true
	$Area3D.monitoring = false
	var hold_point = p.get_melee_hold_point()
	var prev_parent = get_parent()
	if prev_parent != null:
		prev_parent.remove_child(self)
	hold_point.add_child(self)
	position = Vector3.ZERO
	rotation = weapon_data.held_rotation if weapon_data != null else Vector3(-PI/2, PI, 0)
	scale    = Vector3.ONE
	p.held_melee_weapon = self
	player_ref = p
	_update_pickup_label()

func drop(is_death_drop: bool = false):
	var p = player_ref
	var world = get_tree().current_scene
	if swing_tween != null and swing_tween.is_valid():
		swing_tween.kill()
	is_swinging = false
	scale = Vector3.ONE
	var drop_transform = global_transform
	var hold_point = get_parent()
	hold_point.remove_child(self)
	world.add_child(self)
	global_transform = drop_transform
	freeze = false
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = true
	is_held = false
	if p != null and p.held_melee_weapon == self:
		p.held_melee_weapon = null
	_update_pickup_label()
	if is_death_drop:
		_start_despawn_timer()
	else:
		despawn_timer_generation += 1
		despawn_timer_active = false

func _start_despawn_timer():
	if GameConfig.dropped_melee_despawn_time <= 0.0:
		return
	despawn_timer_generation += 1
	var this_generation = despawn_timer_generation
	despawn_timer_active = true
	await get_tree().create_timer(GameConfig.dropped_melee_despawn_time).timeout
	if this_generation != despawn_timer_generation:
		return
	despawn_timer_active = false
	if is_held:
		return
	reset_to_spawn()

func throw():
	var p = player_ref
	if p == null:
		return
	var forward = p.get_aim_direction()
	var world = get_tree().current_scene
	var hold_point = get_parent()
	hold_point.remove_child(self)
	world.add_child(self)
	scale = Vector3.ONE
	var flat_forward = Vector3(forward.x, 0, forward.z)
	if flat_forward.length() < 0.01:
		flat_forward = Vector3.FORWARD
	else:
		flat_forward = flat_forward.normalized()
	global_position = p.global_position + flat_forward * 0.6 + Vector3.UP * 1.0
	global_rotation = p.global_rotation
	freeze = false
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = false
	is_held = false
	is_in_flight = true
	if p.held_melee_weapon == self:
		p.held_melee_weapon = null
	linear_velocity = Vector3.ZERO
	apply_impulse(forward * THROW_IMPULSE)
	await get_tree().create_timer(0.15).timeout
	if is_in_flight:
		set_collision_mask_value(2, true)

func _on_flight_body_entered(body):
	if not is_in_flight:
		return
	is_in_flight = false
	set_collision_mask_value(2, false)
	if body.is_in_group("player") and GameConfig.can_affect(player_ref, body):
		if body.has_method("flash_hit"):
			body.flash_hit()
		_apply_hit_effects(body, true, body.holding_gun)
	_update_pickup_label()
	_start_landed_cooldown()

func _start_landed_cooldown():
	await get_tree().create_timer(THROW_PICKUP_LOCK_TIME).timeout
	$Area3D.monitoring = true

func _update_pickup_label():
	if not has_node("PickupLabel"):
		return
	var label = $PickupLabel
	label.visible = not is_held and not is_in_flight
	if not label.visible or weapon_data == null:
		return
	# Build display text: weapon name + tier + effect (if not normal) + button prompt.
	# Button prompt is determined by whichever player is nearby.
	# P2 is always gamepad; P1 is always keyboard (until input selection is added).
	var nearby_player = _get_nearby_player()
	var uses_gamepad = nearby_player != null and "use_gamepad_look" in nearby_player and nearby_player.use_gamepad_look
	var button_prompt = "[Y]" if uses_gamepad else "[F]"

	var weapon_name = weapon_data.weapon_name
	var tier_str = " T" + str(tier)
	var effect_str = ""
	if effect_category != "normal":
		effect_str = " | " + effect_category.capitalize()

	label.text = button_prompt + "  " + weapon_name + tier_str + effect_str

func _get_nearby_player():
	# Returns the nearest player in the pickup area, used for determining
	# which button prompt to display.
	if player_ref != null and is_instance_valid(player_ref):
		return player_ref
	# Fall back to checking nearby_interactable registrants — the most
	# recently registered player body that overlaps our Area3D.
	var bodies = $Area3D.get_overlapping_bodies()
	for body in bodies:
		if body.is_in_group("player"):
			return body
	return null

# ============================================================
# Swing
# ============================================================

func swing():
	var p = player_ref
	if p == null:
		return

	var was_already_in_deficit = not p.has_stamina()
	p.drain_stamina(_stamina_cost)

	if was_already_in_deficit:
		deficit_swing_count += 1
		if deficit_swing_count >= 2 and GameConfig.melee_weapon_breaking:
			_break_weapon()
			return
	else:
		deficit_swing_count = 0

	is_swinging = true

	var base_pitch  = p.get_aim_pitch() if p.has_method("get_aim_pitch") else 0.0
	var held_rot    = weapon_data.held_rotation if weapon_data != null else Vector3(-PI/2, PI, 0)
	var windup_off  = weapon_data.swing_windup_offset if weapon_data != null else Vector3(-0.3, 0.5, -0.6)
	var follow_off  = weapon_data.swing_followthrough_offset if weapon_data != null else Vector3(0.5, -0.5, 0.7)

	var rest_rotation         = Vector3(held_rot.x + base_pitch, held_rot.y, held_rot.z)
	var windup_rotation       = rest_rotation + windup_off
	var followthrough_rotation = rest_rotation + follow_off

	if swing_tween != null and swing_tween.is_valid():
		swing_tween.kill()
	swing_tween = create_tween()
	swing_tween.tween_property(self, "rotation", windup_rotation,        _windup_time)
	swing_tween.tween_callback(func(): $HitBox.monitoring = true)
	swing_tween.tween_property(self, "rotation", followthrough_rotation, _active_time)
	swing_tween.tween_callback(func(): $HitBox.monitoring = false)
	swing_tween.tween_property(self, "rotation", rest_rotation,          _recovery_time)

	await swing_tween.finished
	is_swinging = false

func _break_weapon():
	is_swinging = false
	deficit_swing_count = 0
	if is_held:
		drop()
	visible = false
	$CollisionShape3D.disabled = true
	$Area3D/CollisionShape3D.disabled = true
	freeze = true
	await get_tree().create_timer(BREAK_RESPAWN_TIME).timeout
	global_position = spawn_position
	global_rotation = spawn_rotation
	scale = Vector3.ONE
	linear_velocity = Vector3.ZERO
	visible = true
	$CollisionShape3D.disabled = false
	$Area3D/CollisionShape3D.disabled = false
	freeze = false

# ============================================================
# Hit resolution
# ============================================================

func _get_weapon_icon() -> String:
	if weapon_data == null:
		return "💀"
	match weapon_data.weapon_name:
		"Sword":        return "⚔"
		"Baseball Bat": return "🪃"
		"Stick":        return "🪵"
		"Crowbar":      return "🔧"
		"Frying Pan":   return "🍳"
		_:              return "💀"

func _on_hit_landed(body):
	if body == player_ref:
		return
	if not body.is_in_group("player"):
		return
	if not GameConfig.can_affect(player_ref, body):
		return

	if body.has_method("flash_hit"):
		body.flash_hit()

	var was_holding_gun = body.holding_gun
	var killer = player_ref.get_display_name() if player_ref != null else ""
	var icon = _get_weapon_icon()

	# Only count as a meaningful melee hit if we hit the gun holder,
	# or if melee_effects_hit_anyone is on (melee is relevant to everyone).
	if player_ref != null and (was_holding_gun or GameConfig.melee_effects_hit_anyone):
		GameEvents.melee_hit_landed.emit(player_ref.get_display_name())

	if GameConfig.melee_eliminates_anyone:
		if body.has_method("eliminate"):
			body.eliminate(killer, icon)
		return

	if was_holding_gun:
		if GameConfig.melee_eliminates_gunholder:
			if body.has_method("eliminate"):
				body.eliminate(killer, icon)
			return
		var has_shield = "melee_disarm_shields" in body and body.melee_disarm_shields > 0
		if has_shield:
			body.melee_disarm_shields -= 1
		else:
			var gun_hold_point = body.get_hold_point()
			if gun_hold_point.get_child_count() > 0:
				var gun_node = gun_hold_point.get_child(0)
				if gun_node.has_method("force_disarm"):
					gun_node.force_disarm()
				else:
					gun_node.drop()
				var victim = body.get_display_name() if body.has_method("get_display_name") else body.name
				GameEvents.player_disarmed.emit(victim, killer, icon)

	_apply_hit_effects(body, false, was_holding_gun)

func _apply_hit_effects(body, is_thrown: bool, was_holding_gun: bool = false):
	if effect_category == "normal":
		return
	# Effects only apply to gun holders unless melee_effects_hit_anyone is on.
	if not GameConfig.melee_effects_hit_anyone and not was_holding_gun:
		return

	var magnitude         = _get_effect_magnitude()
	var immunity_duration = _get_bullet_immunity_duration()
	if is_thrown:
		magnitude *= 0.5
		if effect_category == "stagger":
			immunity_duration *= 0.5

	if effect_category == "knockback" and body.has_method("apply_knockback"):
		var direction = body.global_position - global_position
		direction.y = 0
		if direction.length() < 0.01:
			direction = Vector3.FORWARD
		body.apply_knockback(direction.normalized(), magnitude)
	elif effect_category == "stagger" and body.has_method("apply_stagger"):
		body.apply_stagger(magnitude)

	if immunity_duration > 0.0 and body.has_method("grant_bullet_immunity"):
		body.grant_bullet_immunity(immunity_duration)

func _get_effect_magnitude() -> float:
	match effect_category:
		"knockback": return KNOCKBACK_DISTANCE_BY_TIER[tier - 1]
		"stagger":   return STAGGER_DURATION_BY_TIER[tier - 1]
		_:           return 0.0

func _get_bullet_immunity_duration() -> float:
	match effect_category:
		"stagger":
			# Immunity protects the disarmed gunholder — grows with tier
			# so rarer weapons give a longer escape window. T3 was
			# previously 0 due to a conditional bug; now fixed via registry.
			return MeleeWeaponRegistry.get_stagger_immunity_duration(tier)
		"knockback":
			return KNOCKBACK_IMMUNITY_BY_TIER[tier - 1]
		_:
			return 0.0

# ============================================================
# Reset
# ============================================================

func reset_to_spawn():
	if is_held:
		drop()
	despawn_timer_generation += 1
	despawn_timer_active = false
	if swing_tween != null and swing_tween.is_valid():
		swing_tween.kill()
	is_in_flight    = false
	is_swinging     = false
	deficit_swing_count = 0
	visible         = true
	scale           = Vector3.ONE
	set_collision_mask_value(2, false)
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = true
	$Area3D/CollisionShape3D.disabled = false
	freeze = false
	global_position = spawn_position
	global_rotation = spawn_rotation
	linear_velocity  = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_update_pickup_label()
	# Re-randomise the weapon identity on each respawn.
	randomize_attributes()

func get_interact_category():
	return "weapon"
