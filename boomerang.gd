extends "res://item.gd"

## Boomerang: thrown, flies out ~10m, arcs back to the thrower. Disarms a gun
## holder on hit (same rules as melee: shields respected), knocks back anyone
## else. Makes exactly ONE trip: it vanishes the moment it hits a target OR
## the moment it returns to the thrower, then respawns like any consumable.

const FLIGHT_RANGE := 10.0
const OUT_TIME := 0.8
const BACK_TIME := 0.9
const SPIN_SPEED := 18.0

var _flying := false
var _consumed := false
var _flight_t := 0.0
var _origin := Vector3.ZERO
var _out_dir := Vector3.FORWARD
var _thrower = null
var _hit_bodies := {}

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

	var flat := Vector3(forward.x, 0, forward.z)
	_out_dir = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	_origin = p.global_position + _out_dir * 0.6 + Vector3.UP * 1.3
	global_position = _origin
	_thrower = p
	_flying = true
	_consumed = false
	_flight_t = 0.0
	_hit_bodies.clear()

	freeze = true  # kinematic flight - we drive the path ourselves
	$CollisionShape3D.disabled = true
	$Area3D.monitoring = true  # reuse the pickup area as the hit sensor
	is_held = false
	is_in_flight = true
	if p.has_method("clear_item_slot"):
		p.clear_item_slot(self)
	elif "held_item" in p and p.held_item == self:
		p.held_item = null
	_update_pickup_label()

func _net_do_throw(start_position: Vector3, _start_rotation: Vector3, _velocity: Vector3, direction: Vector3, owner_actor_id: int) -> void:
	var p = player_ref
	if p == null or not is_held:
		return
	var world = get_tree().current_scene
	get_parent().remove_child(self)
	world.add_child(self)
	scale = Vector3.ONE
	var flat := Vector3(direction.x, 0.0, direction.z)
	_out_dir = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	_origin = start_position + Vector3.UP * 0.3
	global_position = _origin
	_thrower = NetworkManager.find_actor(owner_actor_id)
	online_owner_actor_id = owner_actor_id
	_flying = true
	_consumed = false
	_flight_t = 0.0
	_hit_bodies.clear()
	freeze = true
	$CollisionShape3D.disabled = true
	$Area3D.monitoring = true
	is_held = false
	is_in_flight = true
	if p.has_method("clear_item_slot"):
		p.clear_item_slot(self)
	_update_pickup_label()

func _physics_process(delta: float) -> void:
	if not _flying:
		return
	_flight_t += delta
	rotation.y += SPIN_SPEED * delta
	if _flight_t <= OUT_TIME:
		var t := _flight_t / OUT_TIME
		var eased := 1.0 - (1.0 - t) * (1.0 - t)  # decelerate outward
		global_position = _origin + _out_dir * FLIGHT_RANGE * eased
	else:
		var t := (_flight_t - OUT_TIME) / BACK_TIME
		# return trip finished (reached the thrower, or ran out of time) -> gone
		if t >= 1.0 or _thrower == null or not is_instance_valid(_thrower):
			if NetworkManager.is_online():
				if multiplayer.is_server():
					_server_consume_online()
			else:
				_consume()
			return
		var apex := _origin + _out_dir * FLIGHT_RANGE
		var home: Vector3 = _thrower.global_position + Vector3.UP * 1.2
		var eased := t * t  # accelerate homeward
		global_position = apex.lerp(home, eased)
		if global_position.distance_to(home) < 0.9:
			if NetworkManager.is_online():
				if multiplayer.is_server():
					_server_consume_online()
			else:
				_consume()  # back at the thrower -> go away
			return
	if not NetworkManager.is_online() or multiplayer.is_server():
		_check_hits()

func _check_hits() -> void:
	for body in $Area3D.get_overlapping_bodies():
		if not body.is_in_group("player"):
			continue
		if body == _thrower:
			continue  # never collides with the thrower (return is handled above)
		if _hit_bodies.has(body):
			continue
		if not GameConfig.can_affect(_thrower, body):
			continue
		_hit_bodies[body] = true
		if NetworkManager.is_online():
			var target_id = body.get("actor_id")
			var rm = _online_round_manager()
			if target_id != null and rm != null:
				rm.server_online_boomerang_hit(online_item_id, online_owner_actor_id, int(target_id), _online_round_epoch())
			return
		_strike(body)
		_consume()  # collision landed -> go away, no return trip
		return

func _strike(body: Node3D) -> void:
	if body.has_method("flash_hit"):
		body.flash_hit()
	var killer: String = _thrower.get_display_name() if _thrower != null else ""
	if "holding_gun" in body and body.holding_gun:
		var has_shield: bool = "melee_disarm_shields" in body and body.melee_disarm_shields > 0
		if has_shield:
			body.melee_disarm_shields -= 1
		else:
			var hold = body.get_hold_point()
			if hold.get_child_count() > 0:
				var gun_node = hold.get_child(0)
				if gun_node.has_method("force_disarm"):
					gun_node.force_disarm()
				else:
					gun_node.drop()
				var victim: String = body.get_display_name() if body.has_method("get_display_name") else str(body.name)
				GameEvents.player_disarmed.emit(victim, killer, null)
			if body.has_method("grant_bullet_immunity"):
				body.grant_bullet_immunity(1.0)
	elif body.has_method("apply_knockback"):
		var dir := (body.global_position - global_position)
		dir.y = 0
		body.apply_knockback(dir.normalized(), 3.0)

# End the single trip: hide the boomerang and let it respawn like any other
# consumable. Guarded so a hit + arrival on the same frame can't double-fire.
func _consume() -> void:
	if _consumed:
		return
	_consumed = true
	_flying = false
	is_in_flight = false
	visible = false
	$CollisionShape3D.disabled = true
	$Area3D.monitoring = false
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_update_pickup_label()
	_schedule_respawn()

func _server_consume_online() -> void:
	if not multiplayer.is_server() or _consumed:
		return
	var rm = _online_round_manager()
	if rm != null:
		rm.server_consume_online_item(online_item_id, respawn_after_deploy_time, _online_round_epoch())

func _net_consume() -> void:
	_consumed = true
	_flying = false
	super._net_consume()
