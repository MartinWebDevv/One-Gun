extends RigidBody3D

const VisibilityRules = preload("res://combat_visibility.gd")
const HitboxDebug = preload("res://hitbox_debug_visual.gd")

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
var effect_category: String = "normal"   # "normal" | "knockback" | "stagger" | "slow"
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

# Slow is flat regardless of tier — a minor effect, not worth tier-scaling.
const SLOW_MULTIPLIER = 0.85
const SLOW_DURATION   = 3.0

# ---- Fixed physics constants ----
const THROW_IMPULSE         = GameConfig.SHARED_THROW_FORWARD_SPEED
const THROW_ARC_UPWARD_BOOST = GameConfig.SHARED_THROW_UPWARD_SPEED
const THROW_PICKUP_LOCK_TIME = 1.0
const BREAK_RESPAWN_TIME    = 5.0
const ONLINE_PICKUP_MAX_DISTANCE = 2.25
const ONLINE_MELEE_MAX_HIT_DISTANCE = 5.5
const NORMAL_MELEE_MIN_HITBOX_LENGTH := 3.0
const NORMAL_MELEE_MAX_HITBOX_LENGTH := 3.8
const POWERUP_MELEE_MAX_HIT_DISTANCE := 8.0
const SWING_TIME_MULTIPLIER := 0.85
const HITBOX_WIDTH_MULTIPLIER := 1.20
const POWERUP_REACH_MULTIPLIER := POWERUP_MELEE_MAX_HIT_DISTANCE / ONLINE_MELEE_MAX_HIT_DISTANCE

# ---- Runtime state ----
var player_ref = null
var is_held           := false
var is_swinging       := false
var is_in_flight      := false
var online_active     := true
var online_candidate_id := -1
var _break_after_swing := false
var pickup_locked     := false
var swing_tween: Tween = null

var despawn_timer_active     := false
var despawn_timer_generation := 0

var spawn_position := Vector3.ZERO
var spawn_rotation := Vector3.ZERO
var marker_refill_on_pickup := false
var marker_refill_requested := false
var overtime_marker_supply := false

# ---- Held model reference ----
var _model_instance: Node3D = null

var _throw_collision_ignored_player: PhysicsBody3D = null
# ---- Per-weapon custom hit box (see _apply_custom_hitbox) ----
var _custom_hitbox_applied := false
var _default_hitbox_shape: Shape3D = null
var _default_hitbox_transform := Transform3D.IDENTITY
var _online_hit_actor_ids: Dictionary = {}
var overtime_disabled := false
var personal_mode_melee := false
var _hitbox_debug: HitboxDebugVisual = null
var _swing_shape_restore: Shape3D = null
var _swing_transform_restore := Transform3D.IDENTITY
var _throw_preview_active := false

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
	if $HitBox/CollisionShape3D.shape != null:
		_default_hitbox_shape = $HitBox/CollisionShape3D.shape.duplicate()
		_default_hitbox_transform = $HitBox/CollisionShape3D.transform
	_hitbox_debug = HitboxDebug.new()
	_hitbox_debug.name = "MeleeHitboxDebug"
	$HitBox.add_child(_hitbox_debug)
	_hitbox_debug.setup($HitBox/CollisionShape3D,
		Color(1.0, 0.82, 0.08, 0.13), Color(1.0, 0.08, 0.03, 0.42))
	# Online map instances stay model-free during the coordinated scene load.
	# Once every peer is ready, the host activates every authored placement and
	# supplies an independently rolled identity for each one.
	if NetworkManager.is_online():
		set_online_active(false)
	else:
		apply_weapon_data(
			MeleeWeaponRegistry.get_random_weapon_data(),
			MeleeWeaponRegistry.get_random_effect(),
			MeleeWeaponRegistry.get_random_tier()
		)
	if NetworkManager.is_online():
		freeze = true

func apply_weapon_data(data: WeaponData, effect: String, new_tier: int):
	weapon_data    = data
	effect_category = effect
	tier           = new_tier

	# Cache tier-adjusted stats.
	var stats = MeleeWeaponRegistry.get_stats_for_tier(data, tier)
	_windup_time   = float(stats["windup_time"]) * SWING_TIME_MULTIPLIER
	_active_time   = float(stats["active_time"]) * SWING_TIME_MULTIPLIER
	_recovery_time = float(stats["recovery_time"]) * SWING_TIME_MULTIPLIER
	_stamina_cost  = stats["stamina_cost"]

	# Swap in the correct visual model.
	_swap_model(data)

	# Resize the hit box to match this weapon's reach.
	_apply_reach(tier)

	_update_pickup_label()

func _swap_model(data: WeaponData):
	# Remove any previous model.
	if _model_instance != null and is_instance_valid(_model_instance):
		_model_instance.queue_free()
		_model_instance = null

	_custom_hitbox_applied = false

	if data.model_scene_path == "":
		return

	var packed = load(data.model_scene_path)
	if packed == null:
		push_warning("MeleeWeapon: could not load model at '%s'" % data.model_scene_path)
		return

	_model_instance = packed.instantiate() if packed is PackedScene else packed
	add_child(_model_instance)
	_model_instance.scale = Vector3.ONE * data.held_scale
	# Put the authored base of the handle on this weapon root. The root is what
	# gets attached to the animated paw socket.
	_model_instance.position = -(_model_instance.basis * data.held_grip_anchor)
	_apply_custom_hitbox(_model_instance, tier)

func _apply_custom_hitbox(model: Node, weapon_tier: int) -> void:
	# Convention: a per-weapon model scene may carry its own HitShape/CollisionShape3D,
	# sized and positioned to match its actual geometry (see baseball_bat.tscn). When
	# present it replaces the generic reach-scaled hit box below instead of stacking
	# with it. Weapons still using a bare model (no matching node) keep the shared
	# default shape scaled by reach_multiplier, unchanged.
	var hit_shape_node = model.get_node_or_null("HitShape/CollisionShape3D")
	if hit_shape_node == null or hit_shape_node.shape == null:
		return
	var hit_box_shape: CollisionShape3D = $HitBox/CollisionShape3D
	# Match the visual's anchored scene-root rotation and held scale. Bake that
	# uniform scale into the duplicated shape so Jolt receives an orthonormal
	# CollisionShape3D transform.
	var relative_transform: Transform3D = global_transform.affine_inverse() \
		* hit_shape_node.global_transform
	var shape_scale: float = relative_transform.basis.get_scale().x
	relative_transform.basis = relative_transform.basis.orthonormalized()
	hit_box_shape.transform = relative_transform
	var widened_shape: Shape3D = hit_shape_node.shape.duplicate()
	_scale_hitbox_shape(widened_shape, shape_scale)
	_widen_hitbox_shape(widened_shape)
	_set_outward_hitbox_length(hit_box_shape, widened_shape,
		_normal_hitbox_length(weapon_tier))
	hit_box_shape.shape = widened_shape
	_custom_hitbox_applied = true

func _scale_hitbox_shape(shape: Shape3D, scale_factor: float) -> void:
	if shape is BoxShape3D:
		shape.size *= scale_factor
	elif shape is SphereShape3D:
		shape.radius *= scale_factor
	elif shape is CapsuleShape3D or shape is CylinderShape3D:
		shape.radius *= scale_factor
		shape.height *= scale_factor

func _widen_hitbox_shape(shape: Shape3D) -> void:
	if shape is BoxShape3D:
		shape.size.x *= HITBOX_WIDTH_MULTIPLIER
	elif shape is SphereShape3D or shape is CapsuleShape3D or shape is CylinderShape3D:
		shape.radius *= HITBOX_WIDTH_MULTIPLIER

func _normal_hitbox_length(weapon_tier: int) -> float:
	var tier_progress := clampf((float(weapon_tier) - 1.0) / 2.0, 0.0, 1.0)
	return lerpf(NORMAL_MELEE_MIN_HITBOX_LENGTH,
		NORMAL_MELEE_MAX_HITBOX_LENGTH, tier_progress)


func _set_outward_hitbox_length(shape_node: CollisionShape3D, shape: Shape3D,
		target_length: float) -> void:
	var reach_axis := Vector3.ZERO
	if shape is BoxShape3D:
		reach_axis = shape_node.transform.basis.z.normalized()
	elif shape is CapsuleShape3D or shape is CylinderShape3D:
		reach_axis = shape_node.transform.basis.y.normalized()
	elif shape is SphereShape3D:
		reach_axis = shape_node.position.normalized()
		if reach_axis.is_zero_approx():
			reach_axis = shape_node.transform.basis.z.normalized()
	if reach_axis.is_zero_approx():
		return
	if shape is BoxShape3D:
		shape.size.z = target_length
	elif shape is CapsuleShape3D or shape is CylinderShape3D:
		shape.height = target_length
	elif shape is SphereShape3D:
		shape.radius = target_length * 0.5
	# Anchor the near end at the paw so the normal attack shape only extends
	# toward the target instead of growing backward through the holder.
	var center := shape_node.position
	var parallel_distance := center.dot(reach_axis)
	var outward_sign := -1.0 if parallel_distance < 0.0 else 1.0
	var lateral_offset := center - reach_axis * parallel_distance
	shape_node.position = lateral_offset + reach_axis * outward_sign \
		* (target_length * 0.5)

func _apply_reach(weapon_tier: int):
	if _custom_hitbox_applied:
		return
	var shape_node = $HitBox/CollisionShape3D
	if shape_node == null or _default_hitbox_shape == null:
		return
	# Always reset from the cached original shape/transform, not from whatever
	# the previous weapon (generic-reach OR custom-hitbox) left behind.
	var shape = _default_hitbox_shape.duplicate()
	shape_node.shape = shape
	shape_node.transform = _default_hitbox_transform
	if shape is BoxShape3D:
		shape.size.x *= HITBOX_WIDTH_MULTIPLIER
	elif shape is SphereShape3D:
		shape.radius *= HITBOX_WIDTH_MULTIPLIER
	elif shape is CapsuleShape3D or shape is CylinderShape3D:
		shape.radius *= HITBOX_WIDTH_MULTIPLIER
	_set_outward_hitbox_length(shape_node, shape,
		_normal_hitbox_length(weapon_tier))

# ============================================================
# Per-frame
# ============================================================

func _process(_delta):
	if _hitbox_debug != null:
		_hitbox_debug.set_active(is_swinging and $HitBox.monitoring)
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

func apply_network_identity(identity: Dictionary) -> bool:
	var data = MeleeWeaponRegistry.get_weapon_data_by_name(str(identity.get("weapon_name", "")))
	var effect := str(identity.get("effect", "normal"))
	var new_tier := clampi(int(identity.get("tier", 1)), 1, 3)
	if data == null or effect not in MeleeWeaponRegistry.EFFECTS:
		return false
	apply_weapon_data(data, effect, new_tier)
	return true

func get_network_identity() -> Dictionary:
	return {
		"weapon_name": weapon_data.weapon_name if weapon_data != null else "",
		"effect": effect_category,
		"tier": tier,
	}

func set_online_active(value: bool) -> void:
	online_active = value
	if not value and _model_instance != null and is_instance_valid(_model_instance):
		_model_instance.free()
		_model_instance = null
		weapon_data = null
	visible = value
	freeze = true
	$HitBox.monitoring = false
	$CollisionShape3D.disabled = not value
	$Area3D/CollisionShape3D.disabled = not value
	$Area3D.monitoring = value and not pickup_locked and not is_held and not is_in_flight
	_update_pickup_label()

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
	if not online_active or not is_held or is_swinging:
		return
	if NetworkManager.is_online():
		if player_ref != null and player_ref.has_method("is_locally_controlled") \
				and player_ref.is_locally_controlled():
			var epoch := _online_round_epoch()
			var rm = _online_round_manager()
			if rm != null:
				if NetworkManager.is_host() and "is_bot" in player_ref and player_ref.is_bot:
					_server_try_swing(_holder_actor_id(), epoch)
				else:
					rm.request_online_melee_action(online_candidate_id, "swing", epoch)
		return
	swing()

func try_throw():
	if personal_mode_melee:
		return
	if not online_active or not is_held or is_swinging:
		return
	if NetworkManager.is_online():
		if player_ref != null and player_ref.has_method("is_locally_controlled") \
				and player_ref.is_locally_controlled():
			var epoch := _online_round_epoch()
			var rm = _online_round_manager()
			if rm != null:
				if NetworkManager.is_host() and "is_bot" in player_ref and player_ref.is_bot:
					_server_try_throw(_holder_actor_id(), epoch)
				else:
					rm.request_online_melee_action(online_candidate_id, "throw", epoch)
		return
	throw()


func begin_throw_preview() -> void:
	if online_active and is_held and not is_swinging and not personal_mode_melee:
		_throw_preview_active = true


func release_throw() -> void:
	if not _throw_preview_active:
		return
	_throw_preview_active = false
	try_throw()


func is_throw_preview_active() -> bool:
	return _throw_preview_active and is_held


func get_throw_preview_data() -> Dictionary:
	if not is_throw_preview_active() or player_ref == null:
		return {}
	var direction: Vector3 = player_ref.get_aim_direction().normalized()
	var flat := Vector3(direction.x, 0.0, direction.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	return {
		"origin": player_ref.global_position + flat * 1.2 + Vector3.UP * 1.15,
		"velocity": direction * THROW_IMPULSE + Vector3.UP * THROW_ARC_UPWARD_BOOST,
		"gravity": 9.8,
	}

func pick_up(p = null) -> bool:
	if not online_active or pickup_locked or is_held:
		return false
	if p == null:
		p = player_ref
	if p == null:
		return false
	if NetworkManager.is_online():
		if p.has_method("is_locally_controlled") and p.is_locally_controlled():
			var epoch := _online_round_epoch()
			var rm = _online_round_manager()
			if rm != null:
				if NetworkManager.is_host() and "is_bot" in p and p.is_bot:
					_server_try_pickup(int(p.actor_id), epoch)
				else:
					rm.request_online_melee_action(online_candidate_id, "pickup", epoch)
		return true
	return _local_pickup(p)

func _local_pickup(p) -> bool:
	if not online_active or pickup_locked or is_held or p == null:
		return false
	# The gun is never tap-swapped away for a melee weapon — the holder must
	# deliberately hold-drop it first (see character_body_3d.gd). No auto-drop here.
	if p.holding_gun:
		return false
	despawn_timer_generation += 1
	despawn_timer_active = false
	var swap_position = global_position
	if p.held_melee_weapon != null and p.held_melee_weapon != self:
		var old_weapon = p.held_melee_weapon
		old_weapon.drop()
		old_weapon.global_position = swap_position
	is_held      = true
	is_in_flight = false
	freeze       = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
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
	if marker_refill_on_pickup and not marker_refill_requested:
		marker_refill_requested = true
		if not NetworkManager.is_online():
			GameEvents.melee_marker_refill_requested.emit(self)
	return true

func _holder_peer_id() -> int:
	return int(player_ref.owner_peer_id) if player_ref != null and "owner_peer_id" in player_ref else -1

func _holder_actor_id() -> int:
	return int(player_ref.actor_id) if player_ref != null and "actor_id" in player_ref else -1

func _online_round_manager():
	var scene := get_tree().current_scene
	return scene.get_node_or_null("RoundManager") if scene != null else null

func _online_round_epoch() -> int:
	var rm = _online_round_manager()
	return int(rm.get("online_round_epoch")) if rm != null else -1

func _server_try_pickup(sender_id: int, epoch: int) -> void:
	if not multiplayer.is_server() or not online_active or is_held or pickup_locked or is_in_flight:
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(epoch):
		return
	var player = NetworkManager.find_actor(sender_id)
	if player == null or player.is_eliminated or player.holding_gun:
		return
	var max_distance := GameConfig.REACH_POWERUP_DISTANCE if player.has_method("has_active_reach") and player.has_active_reach() else ONLINE_PICKUP_MAX_DISTANCE
	if player.global_position.distance_to(global_position) > max_distance:
		return
	if max_distance > ONLINE_PICKUP_MAX_DISTANCE and not VisibilityRules.has_visual_contact(player, self):
		return
	if marker_refill_on_pickup and not marker_refill_requested:
		rm.server_schedule_online_melee_refill(self, epoch)
	rm.broadcast_online_melee_action(online_candidate_id, "pickup", {"holder_actor_id": sender_id})

func _net_do_pickup(holder_actor_id: int) -> void:
	var player = NetworkManager.find_actor(holder_actor_id)
	if player != null:
		_local_pickup(player)

func drop(is_death_drop: bool = false):
	if not is_held or personal_mode_melee:
		return
	var p = player_ref
	var world = get_tree().current_scene
	if swing_tween != null and swing_tween.is_valid():
		swing_tween.kill()
	is_swinging = false
	$HitBox.monitoring = false
	_restore_powerup_reach()
	_throw_preview_active = false
	visible = true
	scale = Vector3.ONE
	var drop_transform = global_transform
	reparent(world, true)
	global_transform = drop_transform
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = true
	is_held = false
	_enable_loose_physics()
	if p != null and p.held_melee_weapon == self:
		p.held_melee_weapon = null
	_update_pickup_label()
	if is_death_drop and NetworkManager.is_online():
		if multiplayer.is_server():
			_start_online_despawn_timer()
	elif is_death_drop:
		_start_despawn_timer()
	else:
		despawn_timer_generation += 1
		despawn_timer_active = false
	if NetworkManager.is_online() and multiplayer.is_server():
		var rm = _online_round_manager()
		if rm != null and bool(rm.get("practice_mode")) and rm.has_method("server_schedule_playpen_melee_cleanup"):
			rm.server_schedule_playpen_melee_cleanup(self)

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

func _start_online_despawn_timer() -> void:
	if GameConfig.dropped_melee_despawn_time <= 0.0:
		return
	despawn_timer_generation += 1
	var this_generation := despawn_timer_generation
	despawn_timer_active = true
	await get_tree().create_timer(GameConfig.dropped_melee_despawn_time).timeout
	if this_generation != despawn_timer_generation or is_held:
		return
	var rm = _online_round_manager()
	if rm != null:
		rm.broadcast_online_melee_action(online_candidate_id, "despawn_reset")

func _net_reset_existing_identity() -> void:
	reset_to_spawn(false)

func request_online_drop() -> void:
	if not NetworkManager.is_online() or not is_held or player_ref == null:
		return
	var epoch := _online_round_epoch()
	var rm = _online_round_manager()
	if rm != null:
		if NetworkManager.is_host() and "is_bot" in player_ref and player_ref.is_bot:
			_server_try_drop(_holder_actor_id(), epoch)
		else:
			rm.request_online_melee_action(online_candidate_id, "drop", epoch)

func _server_try_drop(sender_id: int, epoch: int) -> void:
	if not multiplayer.is_server() or not online_active or not is_held or _holder_actor_id() != sender_id:
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(epoch):
		return
	var pos = player_ref.global_position + Vector3(0.0, 0.6, 0.0)
	rm.broadcast_online_melee_action(online_candidate_id, "drop", {"position": pos})

func _net_do_drop(drop_pos: Vector3) -> void:
	if is_held:
		drop()
	global_position = drop_pos
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_enable_loose_physics()


func _enable_loose_physics() -> void:
	# A held rigid body may still be sleeping after it is unfrozen. Explicitly
	# wake it so synchronized online drops and local drops both fall naturally.
	freeze = false
	sleeping = false

func throw():
	var p = player_ref
	if p == null:
		return
	if p.has_method("play_throw_animation"):
		p.play_throw_animation()
	var forward = p.get_aim_direction()
	var world = get_tree().current_scene
	reparent(world, true)
	var flat_forward = Vector3(forward.x, 0, forward.z)
	if flat_forward.length() < 0.01:
		flat_forward = Vector3.FORWARD
	else:
		flat_forward = flat_forward.normalized()
	global_position = p.global_position + flat_forward * 1.2 + Vector3.UP * 1.15
	global_rotation = p.global_rotation
	_enable_loose_physics()
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = false
	is_held = false
	is_in_flight = true
	if p.held_melee_weapon == self:
		p.held_melee_weapon = null
	_arm_thrower_collision_grace(p)
	linear_velocity = forward.normalized() * THROW_IMPULSE + Vector3.UP * THROW_ARC_UPWARD_BOOST
	angular_velocity = Vector3.ZERO
	await get_tree().create_timer(0.40).timeout
	if is_in_flight:
		_end_thrower_collision_grace()
		set_collision_mask_value(2, true)

func _server_try_throw(sender_id: int, epoch: int) -> void:
	if not multiplayer.is_server() or not online_active or not is_held or is_swinging or _holder_actor_id() != sender_id:
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(epoch):
		return
	var forward: Vector3 = player_ref.get_aim_direction().normalized()
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	flat_forward = Vector3.FORWARD if flat_forward.length() < 0.01 else flat_forward.normalized()
	var start_pos: Vector3 = player_ref.global_position + flat_forward * 1.2 + Vector3.UP * 1.15
	var start_rot: Vector3 = player_ref.global_rotation
	var launch_velocity := forward * THROW_IMPULSE + Vector3.UP * THROW_ARC_UPWARD_BOOST
	rm.broadcast_online_melee_action(online_candidate_id, "throw", {
		"position": start_pos,
		"rotation": start_rot,
		"velocity": launch_velocity,
	})

func _net_do_throw(start_pos: Vector3, start_rot: Vector3, launch_velocity: Vector3) -> void:
	if not is_held:
		return
	var p = player_ref
	if p != null and p.has_method("play_throw_animation"):
		p.play_throw_animation()
	var world = get_tree().current_scene
	reparent(world, true)
	global_position = start_pos
	global_rotation = start_rot
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = false
	is_held = false
	is_in_flight = true
	_online_hit_actor_ids.clear()
	_arm_thrower_collision_grace(p)
	if p != null and p.held_melee_weapon == self:
		p.held_melee_weapon = null
	linear_velocity = launch_velocity
	angular_velocity = Vector3.ZERO
	# Every peer launches the same approved visual trajectory. Only the server
	# resolves impacts, then broadcasts the authoritative landing transform.
	_enable_loose_physics()
	if multiplayer.is_server():
		call_deferred("_online_enable_throw_player_collision")

func _online_enable_throw_player_collision() -> void:
	await get_tree().create_timer(0.40).timeout
	if is_in_flight:
		_end_thrower_collision_grace()
		set_collision_mask_value(2, true)


func _arm_thrower_collision_grace(thrower) -> void:
	_end_thrower_collision_grace()
	if thrower is PhysicsBody3D:
		_throw_collision_ignored_player = thrower
		add_collision_exception_with(thrower)
	set_collision_mask_value(2, false)


func _end_thrower_collision_grace() -> void:
	if is_instance_valid(_throw_collision_ignored_player):
		remove_collision_exception_with(_throw_collision_ignored_player)
	_throw_collision_ignored_player = null


func _net_retire_playpen_drop() -> void:
	if is_held or is_in_flight:
		return
	queue_free()

func _on_flight_body_entered(body):
	if not is_in_flight:
		return
	if body == player_ref:
		add_collision_exception_with(body)
		return
	if body.is_in_group("combat_decoy"):
		if body.has_method("pop_from_attack"):
			body.pop_from_attack(player_ref, "thrown_melee")
		add_collision_exception_with(body)
		return
	if NetworkManager.is_online():
		if not multiplayer.is_server():
			return
		if body.is_in_group("player"):
			_server_resolve_hit(body, true)
		var rm = _online_round_manager()
		if rm != null:
			rm.broadcast_online_melee_action(online_candidate_id, "land", {"position": global_position, "rotation": global_rotation})
		return
	_end_thrower_collision_grace()
	is_in_flight = false
	set_collision_mask_value(2, false)
	if body.is_in_group("player") and GameConfig.can_affect(player_ref, body):
		_resolve_local_hit(body, true)
	_update_pickup_label()
	_start_landed_cooldown()

func _net_land_throw(land_pos: Vector3, land_rot: Vector3) -> void:
	_end_thrower_collision_grace()
	is_in_flight = false
	set_collision_mask_value(2, false)
	global_position = land_pos
	global_rotation = land_rot
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	if NetworkManager.is_online() and multiplayer.is_server():
		var rm = _online_round_manager()
		if rm != null and bool(rm.get("practice_mode")) and rm.has_method("server_schedule_playpen_melee_cleanup"):
			rm.server_schedule_playpen_melee_cleanup(self)
	_update_pickup_label()
	_start_landed_cooldown()

func _start_landed_cooldown():
	await get_tree().create_timer(THROW_PICKUP_LOCK_TIME).timeout
	if not pickup_locked and not is_held and not is_in_flight:
		$Area3D.monitoring = true

func _update_pickup_label():
	if not has_node("PickupLabel"):
		return
	var label = $PickupLabel
	label.visible = online_active and not is_held and not is_in_flight and not pickup_locked
	if not label.visible or weapon_data == null:
		return
	# Build display text: weapon name + tier + effect (if not normal) + button prompt.
	# Button prompt is determined by whichever player is nearby.
	# P2 is always gamepad; P1 is always keyboard (until input selection is added).
	var nearby_player = _get_nearby_player()
	var uses_gamepad = nearby_player != null and "use_gamepad_look" in nearby_player and nearby_player.use_gamepad_look
	var button_prompt = "[Y]" if uses_gamepad else "[F]"
	var hold_prompt = "[Hold Y]" if uses_gamepad else "[Hold F]"

	# The gun is never tap-swapped away (see pick_up()) — a gun holder needs
	# to know that pressing the pickup button here won't do anything until
	# they hold-drop the gun first.
	if nearby_player != null and "holding_gun" in nearby_player and nearby_player.holding_gun:
		label.text = hold_prompt + "  Drop Gun First"
		return

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

func _server_try_swing(sender_id: int, epoch: int) -> void:
	if not multiplayer.is_server() or not online_active or not is_held or is_swinging or _holder_actor_id() != sender_id:
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(epoch):
		return
	if player_ref == null or player_ref.is_eliminated:
		return
	var was_in_deficit: bool = not player_ref.has_stamina()
	var should_break := was_in_deficit and GameConfig.melee_weapon_breaking
	rm.broadcast_online_melee_action(online_candidate_id, "swing", {
		"should_break": should_break,
	})

func _net_do_swing(should_break: bool) -> void:
	swing(should_break)

func swing(should_break: bool = false):
	var p = player_ref
	if p == null:
		return

	var was_already_in_deficit = not p.has_stamina()
	p.drain_stamina(_stamina_cost)
	_break_after_swing = should_break if NetworkManager.is_online() \
		else was_already_in_deficit and GameConfig.melee_weapon_breaking

	is_swinging = true
	if p.has_method("play_melee_animation"):
		p.play_melee_animation(_windup_time + _active_time + _recovery_time)
	_online_hit_actor_ids.clear()
	_apply_powerup_reach(p.has_method("has_active_reach") and p.has_active_reach())

	var base_pitch = p.get_aim_pitch() if p.has_method("get_aim_pitch") else 0.0
	var held_rot = weapon_data.held_rotation if weapon_data != null \
		else Vector3(-PI/2, PI, 0)
	var rest_rotation = Vector3(held_rot.x + base_pitch, held_rot.y, held_rot.z)
	# The character's authored melee clip owns the visible attack motion. Keep
	# the weapon fixed to its paw socket; this tween only sequences gameplay.
	rotation = rest_rotation

	if swing_tween != null and swing_tween.is_valid():
		swing_tween.kill()
	AudioManager.play_sfx("melee_swing")
	GameEvents.combat_noise.emit(p.global_position, int(p.get("actor_id")), "melee", 12.0)
	swing_tween = create_tween()
	swing_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	swing_tween.tween_interval(_windup_time)
	swing_tween.tween_callback(func(): $HitBox.monitoring = true)
	swing_tween.tween_interval(_active_time)
	swing_tween.tween_callback(func():
		$HitBox.monitoring = false
		_restore_powerup_reach())
	swing_tween.tween_interval(_recovery_time)

	await swing_tween.finished
	is_swinging = false
	if _break_after_swing:
		_break_after_swing = false
		_break_weapon()


func _apply_powerup_reach(enabled: bool) -> void:
	_restore_powerup_reach()
	var target_reach := POWERUP_MELEE_MAX_HIT_DISTANCE if enabled else 0.0
	if target_reach <= 0.0 and player_ref != null and str(player_ref.get("one_of_us_role")) == "them":
		target_reach = NORMAL_MELEE_MAX_HITBOX_LENGTH * GameConfig.ONE_OF_US_THEM_REACH_MULTIPLIER
	if target_reach <= 0.0:
		return
	var shape_node: CollisionShape3D = $HitBox/CollisionShape3D
	if shape_node.shape == null:
		return
	_swing_shape_restore = shape_node.shape.duplicate()
	_swing_transform_restore = shape_node.transform
	var extended := shape_node.shape.duplicate()
	var reach_axis := Vector3.ZERO
	if extended is BoxShape3D:
		reach_axis = shape_node.transform.basis.z.normalized()
		extended.size.z = target_reach
	elif extended is CapsuleShape3D or extended is CylinderShape3D:
		reach_axis = shape_node.transform.basis.y.normalized()
		extended.height = target_reach
	elif extended is SphereShape3D:
		reach_axis = shape_node.position.normalized()
		if reach_axis.is_zero_approx():
			reach_axis = shape_node.transform.basis.z.normalized()
		extended.radius = target_reach * 0.5
	if not reach_axis.is_zero_approx():
		# Keep the near end at the holder and put the far end at 8m. Merely
		# multiplying each weapon's authored length left short weapons far below
		# the advertised Reach distance and let long centered shapes extend back.
		var center := shape_node.position
		var parallel_distance := center.dot(reach_axis)
		var outward_sign := -1.0 if parallel_distance < 0.0 else 1.0
		var lateral_offset := center - reach_axis * parallel_distance
		shape_node.position = lateral_offset + reach_axis * outward_sign \
			* (target_reach * 0.5)
	shape_node.shape = extended


func _restore_powerup_reach() -> void:
	if _swing_shape_restore == null:
		return
	$HitBox/CollisionShape3D.transform = _swing_transform_restore
	$HitBox/CollisionShape3D.shape = _swing_shape_restore
	_swing_shape_restore = null

const HIT_SOUND_KEYS = {
	"Sword": "hit_sword",
	"Baseball Bat": "hit_bat",
	"Stick": "hit_stick",
	"Crowbar": "hit_crowbar",
	"Frying Pan": "hit_pan",
}

func _play_hit_sound():
	var wname: String = weapon_data.weapon_name if weapon_data != null else ""
	AudioManager.play_sfx(HIT_SOUND_KEYS.get(wname, "hit_stick"))

func _break_weapon():
	is_swinging = false
	if is_held:
		drop()
	visible = false
	$CollisionShape3D.disabled = true
	$Area3D/CollisionShape3D.disabled = true
	freeze = true
	await get_tree().create_timer(BREAK_RESPAWN_TIME).timeout
	if NetworkManager.is_online():
		if multiplayer.is_server():
			var rm = _online_round_manager()
			if rm != null:
				rm.broadcast_online_melee_action(online_candidate_id, "despawn_reset")
		return
	global_position = spawn_position
	global_rotation = spawn_rotation
	scale = Vector3.ONE
	linear_velocity = Vector3.ZERO
	visible = true
	$CollisionShape3D.disabled = false
	$Area3D/CollisionShape3D.disabled = false
	freeze = NetworkManager.is_online()

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


func _holder_max_hit_distance() -> float:
	if player_ref != null and player_ref.has_method("has_active_reach") \
			and player_ref.has_active_reach():
		return POWERUP_MELEE_MAX_HIT_DISTANCE
	if player_ref != null and str(player_ref.get("one_of_us_role")) == "them":
		return NORMAL_MELEE_MAX_HITBOX_LENGTH * GameConfig.ONE_OF_US_THEM_REACH_MULTIPLIER
	return ONLINE_MELEE_MAX_HIT_DISTANCE

func _on_hit_landed(body):
	if body == player_ref:

		return
	if player_ref == null or not body is Node3D:
		return
	var max_hit_distance := _holder_max_hit_distance()
	if body.global_position.distance_to(player_ref.global_position) > max_hit_distance:
		return
	if body.is_in_group("combat_decoy"):
		if body.has_method("pop_from_attack"):
			body.pop_from_attack(player_ref, "melee")
		return
	if not body.is_in_group("player"):
		return
	if NetworkManager.is_online():
		if multiplayer.is_server():
			_server_resolve_hit(body, false)
		return
	if not GameConfig.can_affect(player_ref, body):
		return
	_resolve_local_hit(body, false)

func _resolve_local_hit(body, is_thrown: bool) -> void:
	var round_manager = get_tree().current_scene.get_node_or_null("RoundManager")
	if round_manager != null and round_manager.has_method("try_resolve_one_of_us_melee") \
			and round_manager.try_resolve_one_of_us_melee(player_ref, body):
		return
	if body.has_method("flash_hit"):
		body.flash_hit()
	_play_hit_sound()
	var was_holding_gun := bool(body.holding_gun)
	var killer: String = player_ref.get_display_name() if player_ref != null else ""
	var icon: String = _get_weapon_icon()
	var will_eliminate := (GameConfig.melee_eliminates_anyone
		or (was_holding_gun and GameConfig.melee_eliminates_gunholder))
	if player_ref != null:
		GameEvents.melee_hit_landed.emit(player_ref.get_display_name())
		GameEvents.actor_melee_hit_landed.emit(int(player_ref.get("actor_id")) if player_ref.get("actor_id") != null else -1)
		if not will_eliminate:
			GameEvents.combat_feedback.emit(killer, "melee_hit")
			GameEvents.actor_combat_feedback.emit(int(player_ref.get("actor_id")) if player_ref.get("actor_id") != null else -1, "melee_hit")

	# Sticky Hands is independent from Extra Life. A lethal swing can consume
	# both: Sticky prevents the disarm and Extra Life prevents the elimination.
	var sticky_consumed: bool = false
	if was_holding_gun:
		if body.has_method("consume_sticky_hands"):
			sticky_consumed = body.consume_sticky_hands()
		elif "melee_disarm_shields" in body and body.melee_disarm_shields > 0:
			body.melee_disarm_shields -= 1
			sticky_consumed = true
		if not sticky_consumed:
			_disarm_local_target(body, killer, icon)

	if will_eliminate and body.has_method("eliminate"):
		var killer_actor_id := int(player_ref.get("actor_id")) if player_ref != null and player_ref.get("actor_id") != null else -1
		body.eliminate(killer, icon, "weapon", killer_actor_id)
		var eliminated := bool(body.get("is_eliminated"))
		var event_kind := "melee_elimination" if eliminated else "melee_hit"
		GameEvents.combat_feedback.emit(killer, event_kind)
		GameEvents.actor_combat_feedback.emit(killer_actor_id, event_kind)
		if eliminated:
			return

	_apply_hit_effects(body, is_thrown, was_holding_gun)

func _disarm_local_target(body, killer: String, icon: String) -> void:
	var gun_hold_point = body.get_hold_point()
	if gun_hold_point != null and gun_hold_point.get_child_count() > 0:
		var gun_node = gun_hold_point.get_child(0)
		if gun_node.has_method("force_disarm"):
			gun_node.force_disarm()
		else:
			gun_node.drop()
		var victim = body.get_display_name() if body.has_method("get_display_name") else body.name
		GameEvents.player_disarmed.emit(victim, killer, icon)
		var victim_actor_id := int(body.get("actor_id")) if body.get("actor_id") != null else -1
		var disarmer_actor_id := int(player_ref.get("actor_id")) if player_ref != null and player_ref.get("actor_id") != null else -1
		GameEvents.actor_disarmed.emit(victim_actor_id, disarmer_actor_id, icon)

func _server_resolve_hit(body, is_thrown: bool) -> void:
	if not multiplayer.is_server() or not online_active or player_ref == null or body == player_ref:
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(_online_round_epoch()):
		return
	if rm.has_method("try_resolve_one_of_us_melee") and rm.try_resolve_one_of_us_melee(player_ref, body):
		return
	if not is_thrown and not is_swinging:
		return
	if not body.is_in_group("player") or body.is_eliminated or not GameConfig.can_affect(player_ref, body):
		return
	var max_hit_distance := _holder_max_hit_distance()
	if body.global_position.distance_to(player_ref.global_position) > max_hit_distance:
		return
	var target_id := int(body.actor_id) if "actor_id" in body else -1
	var attacker_id := _holder_actor_id()
	if target_id < 0 or attacker_id < 0 or _online_hit_actor_ids.has(target_id):
		return
	_online_hit_actor_ids[target_id] = true

	var was_holding_gun := bool(body.holding_gun)
	var meaningful_hit := true
	var will_eliminate := GameConfig.melee_eliminates_anyone or (was_holding_gun and GameConfig.melee_eliminates_gunholder)
	var survives_lethal := will_eliminate and bool(body.get("second_wind_ready"))
	var shield_consumed := false
	var did_disarm := false
	var gun_node = null
	if was_holding_gun:
		shield_consumed = "melee_disarm_shields" in body and body.melee_disarm_shields > 0
		if not shield_consumed and (not will_eliminate or survives_lethal):
			var gun_hold_point = body.get_hold_point()
			if gun_hold_point != null and gun_hold_point.get_child_count() > 0:
				gun_node = gun_hold_point.get_child(0)
				did_disarm = true

	if rm.has_method("server_record_online_melee_hit"):
		rm.server_record_online_melee_hit(attacker_id, meaningful_hit, did_disarm)
	rm.broadcast_online_melee_action(online_candidate_id, "hit", {
		"target_id": target_id,
		"attacker_id": attacker_id,
		"meaningful_hit": meaningful_hit,
		"did_disarm": did_disarm,
		"shield_consumed": shield_consumed,
		"is_thrown": is_thrown,
		"will_eliminate": will_eliminate,
		"survives_lethal": survives_lethal,
		"source_position": global_position,
	})
	if did_disarm and gun_node != null:
		if gun_node.has_method("net_force_disarm"):
			gun_node.net_force_disarm()
		else:
			gun_node.net_force_drop()
	if will_eliminate:
		rm.server_eliminate(target_id, attacker_id, _online_round_epoch(), _get_weapon_icon(), "melee")

func _net_apply_melee_hit(
	target_id: int,
	attacker_id: int,
	meaningful_hit: bool,
	did_disarm: bool,
	shield_consumed: bool,
	is_thrown: bool,
	will_eliminate: bool,
	survives_lethal: bool,
	source_position: Vector3
) -> void:
	var body = NetworkManager.find_actor(target_id)
	var attacker = NetworkManager.find_actor(attacker_id)
	if body == null:
		return
	if body.has_method("flash_hit"):
		body.flash_hit()
	_play_hit_sound()
	var attacker_name: String = attacker.get_display_name() if attacker != null and attacker.has_method("get_display_name") else ""
	var victim_name: String = body.get_display_name() if body.has_method("get_display_name") else body.name
	if meaningful_hit and attacker_name != "":
		GameEvents.melee_hit_landed.emit(attacker_name)
		GameEvents.actor_melee_hit_landed.emit(attacker_id)
		# Ordinary melee feedback for the attacker's own machine; an elimination
		# comes through round_manager's typed server-confirmed path instead.
		if not will_eliminate and attacker != null \
				and not ("is_bot" in attacker and attacker.is_bot) \
				and int(attacker.get("owner_peer_id")) == NetworkManager.local_id():
			GameEvents.combat_feedback.emit(attacker_name, "melee_hit")
			GameEvents.actor_combat_feedback.emit(attacker_id, "melee_hit")
	if shield_consumed:
		if body.has_method("consume_sticky_hands"):
			body.consume_sticky_hands()
		elif "melee_disarm_shields" in body:
			body.melee_disarm_shields = maxi(body.melee_disarm_shields - 1, 0)
	if did_disarm:
		GameEvents.player_disarmed.emit(victim_name, attacker_name, _get_weapon_icon())
		GameEvents.actor_disarmed.emit(target_id, attacker_id, _get_weapon_icon())
	if not will_eliminate or survives_lethal:
		_apply_hit_effects(body, is_thrown, bool(body.holding_gun) or did_disarm, source_position)

func _apply_hit_effects(body, is_thrown: bool, was_holding_gun: bool = false, source_position: Vector3 = Vector3.INF):
	if effect_category == "normal":
		return
	if not GameConfig.melee_effects_hit_anyone and not was_holding_gun:
		return

	# A thrown hit is harder to land and earns the complete effect. A wide,
	# multi-target swing applies half duration/distance to each person hit.
	var effect_scale := 1.0 if is_thrown else 0.5
	var magnitude         = _get_effect_magnitude() * effect_scale
	var immunity_duration = _get_bullet_immunity_duration() * effect_scale

	if effect_category == "knockback" and body.has_method("apply_knockback"):
		var hit_origin := global_position if not source_position.is_finite() else source_position
		var direction = body.global_position - hit_origin
		direction.y = 0
		if direction.length() < 0.01:
			direction = Vector3.FORWARD
		body.apply_knockback(direction.normalized(), magnitude)
	elif effect_category == "stagger" and body.has_method("apply_stagger"):
		body.apply_stagger(magnitude)
	elif effect_category == "slow" and body.has_method("apply_slow"):
		body.apply_slow(magnitude, SLOW_MULTIPLIER)

	if immunity_duration > 0.0 and body.has_method("grant_bullet_immunity"):
		body.grant_bullet_immunity(immunity_duration)

func _get_effect_magnitude() -> float:
	match effect_category:
		"knockback": return KNOCKBACK_DISTANCE_BY_TIER[tier - 1]
		"stagger":   return STAGGER_DURATION_BY_TIER[tier - 1]
		"slow":      return SLOW_DURATION
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

func set_online_pickup_locked(value: bool) -> void:
	pickup_locked = value
	if not is_held and not is_in_flight:
		$Area3D.monitoring = online_active and not value
	_update_pickup_label()

func reset_to_spawn(randomize_identity: bool = true):
	overtime_disabled = false
	overtime_marker_supply = false
	online_active = true
	if is_held:
		drop()
	despawn_timer_generation += 1
	despawn_timer_active = false
	if swing_tween != null and swing_tween.is_valid():
		swing_tween.kill()
	is_in_flight    = false
	is_swinging     = false
	$HitBox.monitoring = false
	_restore_powerup_reach()
	visible         = true
	scale           = Vector3.ONE
	set_collision_mask_value(2, false)
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = true
	$Area3D/CollisionShape3D.disabled = false
	freeze = NetworkManager.is_online()
	global_position = spawn_position
	global_rotation = spawn_rotation
	linear_velocity  = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	pickup_locked = false
	_update_pickup_label()
	# Re-randomise the weapon identity on each respawn.
	if randomize_identity and not NetworkManager.is_online():
		randomize_attributes()

func disable_for_overtime() -> void:
	overtime_disabled = true
	online_active = false
	if is_held:
		drop()
	is_in_flight = false
	is_swinging = false
	_restore_powerup_reach()
	visible = false
	$HitBox.monitoring = false
	$CollisionShape3D.disabled = true
	$Area3D.monitoring = false
	$Area3D/CollisionShape3D.disabled = true
	freeze = true

func preserve_held_for_overtime() -> void:
	# Overtime shuts authored ground spawns down, but a melee weapon already in
	# a survivor's hands remains fully usable in both Standard and Chaos OT.
	if not is_held:
		disable_for_overtime()
		return
	overtime_disabled = false
	online_active = true
	despawn_timer_generation += 1
	despawn_timer_active = false
	is_in_flight = false
	pickup_locked = false
	visible = true
	$CollisionShape3D.disabled = true
	$Area3D.monitoring = false
	$Area3D/CollisionShape3D.disabled = true
	freeze = true

func get_interact_category():
	return "weapon"
