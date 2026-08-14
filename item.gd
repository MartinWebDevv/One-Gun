extends RigidBody3D

const VisibilityRules = preload("res://combat_visibility.gd")

@export var item_type := "bubble_gum"
@export var deployed_scene: PackedScene
@export var deployed_lifetime := 8.0
@export var respawn_after_deploy_time := 12.0
@export var HELD_SCALE := 0.5
# 0 = deploy on first contact (default, e.g. bubble gum trap). > 0 = deploy
# this many seconds after being thrown, regardless of contact/landing —
# for grenade-style items that should keep flying/bouncing until they detonate.
@export var fuse_time := 0.0

const THROW_IMPULSE = GameConfig.SHARED_THROW_FORWARD_SPEED
const THROW_ARC_UPWARD_BOOST = GameConfig.SHARED_THROW_UPWARD_SPEED
const ONLINE_PICKUP_MAX_DISTANCE := 3.0

var player_ref = null
var is_held = false
var is_in_flight = false

var spawn_position = Vector3.ZERO
var spawn_rotation = Vector3.ZERO
var online_item_id := -1
var online_spawn_id := -1
var online_owner_actor_id := -1
var overtime_disabled := false
var deployment_forward := Vector3.FORWARD
# Marker pickups refill their map slot independently of the carried object.
# The flag is set only on RoundManager-authored marker items; legacy placed
# items retain their existing deploy/use-based respawn behavior.
var marker_refill_on_pickup := false
var marker_refill_requested := false
var _throw_preview_active := false
var _cook_active := false
var _cook_remaining := 0.0
var _fuse_generation := 0

func get_interact_category():
	return "item"

func get_display_name():
	return item_type.capitalize()

func _ready():
	if not GameConfig.is_item_enabled(item_type):
		queue_free()
		return
	add_to_group("item")
	$Area3D.body_entered.connect(_on_pickup_area_entered)
	$Area3D.body_exited.connect(_on_pickup_area_exited)
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_flight_body_entered)
	spawn_position = global_position
	spawn_rotation = global_rotation
	# items sit exactly where placed - physics only applies while thrown
	freeze = true
	_update_pickup_label()


func _process(delta: float) -> void:
	if not _cook_active:
		return
	_cook_remaining = maxf(_cook_remaining - delta, 0.0)
	if _cook_remaining > 0.0:
		return
	# Clients keep the committed state at zero until the host broadcasts the
	# authoritative in-hand detonation. Clearing it locally creates a one-frame
	# death/expiry race where ordinary inventory cleanup can cancel the grenade.
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	_cook_active = false
	_throw_preview_active = false
	if NetworkManager.is_online():
		if multiplayer.is_server():
			var rm = _online_round_manager()
			if rm != null:
				rm.server_deploy_online_held_item(online_item_id, _holder_actor_id(),
					respawn_after_deploy_time, _online_round_epoch())
	else:
		_deploy_from_hand()

func _on_pickup_area_entered(body):
	if body.has_method("register_interactable"):
		body.register_interactable(self)

func _on_pickup_area_exited(body):
	if body.has_method("unregister_interactable"):
		body.unregister_interactable(self)

func pick_up(p = null) -> bool:
	if p == null:
		p = player_ref
	if p == null:
		return false
	if NetworkManager.is_online():
		if p.has_method("is_locally_controlled") and p.is_locally_controlled():
			var rm = _online_round_manager()
			if rm != null:
				if NetworkManager.is_host() and "is_bot" in p and p.is_bot:
					_server_try_pickup(int(p.actor_id), _online_round_epoch())
				else:
					rm.request_online_item_action(online_item_id, "pickup", _online_round_epoch())
		return true
	return _do_pickup(p)

func _do_pickup(p) -> bool:
	if p == null or is_held or is_in_flight or not visible:
		return false
	var hold_point = p.get_item_hold_point()
	if hold_point == null or not hold_point.is_inside_tree():
		push_error("Item pickup aborted: holder has no active item attachment socket.")
		return false
	_drop_token += 1  # cancel any pending dropped-return timer
	if p.has_method("can_pick_up_item"):
		# Slot-aware controller (human, up to 2 item slots). If both are
		# full, swap out whichever slot is currently active.
		if not p.can_pick_up_item():
			var old_item = p.get_active_item() if p.has_method("get_active_item") else null
			if old_item == null or old_item == self:
				return false
			var swap_position = global_position
			if NetworkManager.is_online() and old_item.has_method("_net_do_drop"):
				old_item._net_do_drop(swap_position)
			else:
				old_item.drop()
			old_item.global_position = swap_position
	elif "held_item" in p and p.held_item != null:
		# Simple single-slot controller (bot) — refuse if already holding one.
		return false
	is_held = true
	is_in_flight = false
	freeze = true
	$CollisionShape3D.disabled = true
	$Area3D.monitoring = false
	var prev_parent = get_parent()
	if prev_parent != null:
		prev_parent.remove_child(self)
	hold_point.add_child(self)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	scale = Vector3.ONE * HELD_SCALE
	if p.has_method("assign_item"):
		p.assign_item(self)
	elif "held_item" in p:
		p.held_item = self
	player_ref = p
	_update_pickup_label()
	if marker_refill_on_pickup and not marker_refill_requested:
		marker_refill_requested = true
		if not NetworkManager.is_online():
			GameEvents.item_marker_refill_requested.emit(self)
	return true

func drop():
	if NetworkManager.is_online():
		request_online_drop()
		return
	_do_drop()

func _do_drop(forced_position = null):
	if not is_held or player_ref == null or _cook_active:
		return
	cancel_use()
	var p = player_ref
	var world = get_tree().current_scene
	visible = true
	scale = Vector3.ONE
	var drop_transform = global_transform
	var hold_point = get_parent()
	hold_point.remove_child(self)
	world.add_child(self)
	global_transform = drop_transform
	if forced_position is Vector3:
		global_position = forced_position
	# dropped items stay put (no roll); physics is reserved for throws
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = true
	is_held = false
	if p != null:
		if p.has_method("clear_item_slot"):
			p.clear_item_slot(self)
		elif "held_item" in p and p.held_item == self:
			p.held_item = null
	_update_pickup_label()
	_start_dropped_return_timer()

func request_online_drop() -> void:
	if not NetworkManager.is_online() or not is_held or player_ref == null:
		return
	if not player_ref.has_method("is_locally_controlled") or not player_ref.is_locally_controlled():
		return
	var rm = _online_round_manager()
	if rm != null:
		if NetworkManager.is_host() and "is_bot" in player_ref and player_ref.is_bot:
			_server_try_drop(_holder_actor_id(), _online_round_epoch())
		else:
			rm.request_online_item_action(online_item_id, "drop", _online_round_epoch())

func _net_do_drop(drop_position: Vector3) -> void:
	_do_drop(drop_position)

func force_online_drop_at(drop_position: Vector3) -> void:
	if NetworkManager.is_online():
		_net_do_drop(drop_position)
	else:
		_do_drop(drop_position)

# Death consumes held items instead of creating extra loose pickups. The item
# disappears immediately and then follows the same respawn/reroll path as a
# normally used item.
func discard_on_owner_death() -> void:
	# Priming is a commitment. A cooked grenade survives its holder's death and
	# drops at the body with the fuse already spent instead of being silently
	# cancelled by the ordinary death-inventory cleanup.
	if is_held and _cook_active and _uses_cook_fuse():
		_release_primed_on_owner_death()
		return
	cancel_use()
	_drop_token += 1
	var holder = player_ref
	var scene_tree := get_tree()
	var world := scene_tree.current_scene if scene_tree != null else null
	if is_held and world != null and get_parent() != world:
		reparent(world, true)
	if holder != null:
		if holder.has_method("clear_item_slot"):
			holder.clear_item_slot(self)
		elif "held_item" in holder and holder.held_item == self:
			holder.held_item = null
	player_ref = null
	is_held = false
	is_in_flight = false
	_hide_after_use()
	if NetworkManager.is_online():
		if multiplayer.is_server():
			var rm = _online_round_manager()
			if rm != null:
				rm.server_consume_online_item(
					online_item_id, respawn_after_deploy_time, _online_round_epoch())
	else:
		_schedule_respawn()

func _release_primed_on_owner_death() -> void:
	var holder = player_ref
	if holder == null:
		return
	var remaining := maxf(_cook_remaining, 0.01)
	if NetworkManager.is_online():
		# Every peer receives the same zero-velocity release before the normal
		# elimination cleanup clears the controller's slot reference.
		if multiplayer.is_server():
			var rm = _online_round_manager()
			if rm != null:
				var direction: Vector3 = holder.get_aim_direction().normalized()
				rm.broadcast_online_item_action(online_item_id, "throw", {
					"position": holder.global_position + Vector3.UP * 0.55,
					"rotation": holder.global_rotation,
					"velocity": Vector3.ZERO,
					"direction": direction,
					"owner_actor_id": _holder_actor_id(),
					"fuse_remaining": remaining,
				})
		return
	var world = get_tree().current_scene
	if world == null:
		return
	if get_parent() != world:
		reparent(world, true)
	global_position = holder.global_position + Vector3.UP * 0.55
	global_rotation = holder.global_rotation
	scale = Vector3.ONE
	freeze = false
	sleeping = false
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = false
	is_held = false
	is_in_flight = true
	_throw_preview_active = false
	_cook_active = false
	if holder.has_method("clear_item_slot"):
		holder.clear_item_slot(self)
	elif "held_item" in holder and holder.held_item == self:
		holder.held_item = null
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_update_pickup_label()
	_start_fuse_timer(remaining)

# Dropped items that nobody grabs within 2s return to their spawn point.
const DROPPED_RETURN_TIME := 2.0
var _drop_token := 0

func _start_dropped_return_timer():
	_drop_token += 1
	var token := _drop_token
	await get_tree().create_timer(DROPPED_RETURN_TIME).timeout
	if token != _drop_token:
		return  # a newer drop/pickup cycle superseded this timer
	if is_held or is_in_flight or not visible:
		return  # picked up, thrown, or deployed in the meantime
	if global_position.distance_to(spawn_position) < 0.5:
		return  # already at home
	if NetworkManager.is_online():
		if multiplayer.is_server():
			var rm = _online_round_manager()
			if rm != null:
				if bool(rm.get("practice_mode")):
					rm.broadcast_online_item_action(
						online_item_id, "consume", {"retire": true})
					return
				rm.broadcast_online_item_action(online_item_id, "return", {
					"position": spawn_position,
					"rotation": spawn_rotation,
				})
		return
	_net_return_to_spawn(spawn_position, spawn_rotation)

func _net_return_to_spawn(return_position: Vector3, return_rotation: Vector3) -> void:
	if is_held or is_in_flight:
		return
	global_position = return_position
	global_rotation = return_rotation
	scale = Vector3.ONE
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_update_pickup_label()

func _net_set_loose_position(new_position: Vector3) -> void:
	if not is_held and not is_in_flight and visible:
		global_position = new_position

func begin_use() -> void:
	if not is_held:
		return
	_throw_preview_active = true
	if not _uses_cook_fuse() or _cook_active:
		return
	if NetworkManager.is_online():
		var rm = _online_round_manager()
		if rm != null:
			if NetworkManager.is_host() and "is_bot" in player_ref and player_ref.is_bot:
				_server_try_prime(_holder_actor_id(), _online_round_epoch())
			else:
				rm.request_online_item_action(online_item_id, "prime", _online_round_epoch())
	else:
		_net_do_prime(fuse_time)


func release_use() -> void:
	if not is_held or not _throw_preview_active:
		return
	_throw_preview_active = false
	_try_release_throw()


func cancel_use() -> void:
	# A live fuse is committed and cannot be cancelled or dropped.
	if not _cook_active:
		_throw_preview_active = false


func is_committed_use() -> bool:
	return _cook_active


func is_throw_preview_active() -> bool:
	return _throw_preview_active and is_held


func get_cook_progress() -> float:
	if not _cook_active or not _uses_cook_fuse():
		return -1.0
	return clampf(1.0 - _cook_remaining / fuse_time, 0.0, 1.0)

func _uses_cook_fuse() -> bool:
	return item_type == "grenade" and fuse_time > 0.0


func get_throw_preview_data() -> Dictionary:
	if not is_throw_preview_active() or player_ref == null:
		return {}
	var direction: Vector3 = player_ref.get_aim_direction().normalized()
	var flat := Vector3(direction.x, 0.0, direction.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	return {
		"origin": player_ref.global_position + flat * 0.6 + Vector3.UP,
		"velocity": direction * THROW_IMPULSE + Vector3.UP * THROW_ARC_UPWARD_BOOST,
		"gravity": 9.8,
	}


func try_throw():
	if not is_held:
		return
	begin_use()
	release_use()


func _try_release_throw() -> void:
	if NetworkManager.is_online():
		if player_ref != null and player_ref.has_method("is_locally_controlled") \
				and player_ref.is_locally_controlled():
			var rm = _online_round_manager()
			if rm != null:
				var direction: Vector3 = player_ref.get_aim_direction()
				if NetworkManager.is_host() and "is_bot" in player_ref and player_ref.is_bot:
					_server_try_throw(_holder_actor_id(), _online_round_epoch(), direction)
				else:
					rm.request_online_item_action(online_item_id, "throw", _online_round_epoch(), direction)
		return
	throw()


func _server_try_prime(sender_id: int, epoch: int) -> void:
	if not multiplayer.is_server() or not is_held or _holder_actor_id() != sender_id or not _uses_cook_fuse():
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(epoch) or _cook_active:
		return
	rm.broadcast_online_item_action(online_item_id, "prime", {"fuse_time": fuse_time})


func _net_do_prime(duration: float) -> void:
	_cook_active = true
	_cook_remaining = duration
	_throw_preview_active = true

func _online_round_manager():
	var scene := get_tree().current_scene
	return scene.get_node_or_null("RoundManager") if scene != null else null

func _online_round_epoch() -> int:
	var rm = _online_round_manager()
	return int(rm.get("online_round_epoch")) if rm != null else -1

func _holder_peer_id() -> int:
	if player_ref != null and "owner_peer_id" in player_ref:
		return int(player_ref.owner_peer_id)
	return -1

func _holder_actor_id() -> int:
	if player_ref != null and "actor_id" in player_ref:
		return int(player_ref.actor_id)
	return _holder_peer_id()

func _server_try_pickup(sender_id: int, epoch: int) -> void:
	if not multiplayer.is_server() or is_held or is_in_flight or not visible:
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(epoch):
		return
	var player = NetworkManager.find_actor(sender_id)
	if player == null or player.is_eliminated:
		return
	var max_distance := GameConfig.REACH_POWERUP_DISTANCE if player.has_method("has_active_reach") and player.has_active_reach() else ONLINE_PICKUP_MAX_DISTANCE
	if player.global_position.distance_to(global_position) > max_distance:
		return
	if max_distance > ONLINE_PICKUP_MAX_DISTANCE and not VisibilityRules.has_visual_contact(player, self):
		return
	if player.has_method("can_pick_up_item") and not player.can_pick_up_item():
		if ("is_bot" in player and player.is_bot) or not player.has_method("get_active_item") or player.get_active_item() == null:
			return
	if marker_refill_on_pickup and not marker_refill_requested:
		rm.server_schedule_online_item_refill(self, epoch)
	rm.broadcast_online_item_action(online_item_id, "pickup", {"holder_actor_id": sender_id})

func _server_try_drop(sender_id: int, epoch: int) -> void:
	if not multiplayer.is_server() or not is_held or _holder_actor_id() != sender_id:
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(epoch):
		return
	var pos: Vector3 = player_ref.global_position + Vector3(0.0, 0.6, 0.0)
	rm.broadcast_online_item_action(online_item_id, "drop", {"position": pos})

func _server_try_throw(sender_id: int, epoch: int, direction: Vector3) -> void:
	if not multiplayer.is_server() or not is_held or _holder_actor_id() != sender_id:
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(epoch):
		return
	var player = NetworkManager.find_actor(sender_id)
	if player == null or player.is_eliminated or not direction.is_finite() or direction.is_zero_approx():
		return
	if _uses_cook_fuse() and not _cook_active:
		return
	direction = direction.normalized()
	var expected: Vector3 = player.get_aim_direction().normalized()
	if direction.dot(expected) < cos(deg_to_rad(35.0)):
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	var start: Vector3 = player.global_position + flat * 0.6 + Vector3.UP * 1.0
	var velocity: Vector3 = direction * THROW_IMPULSE + Vector3.UP * THROW_ARC_UPWARD_BOOST
	rm.broadcast_online_item_action(online_item_id, "throw", {
		"position": start,
		"rotation": player.global_rotation,
		"velocity": velocity,
		"direction": direction,
		"owner_actor_id": int(player.actor_id),
		"fuse_remaining": _cook_remaining if _uses_cook_fuse() else fuse_time,
	})

func _net_do_pickup(holder_actor_id: int) -> void:
	var player = NetworkManager.find_actor(holder_actor_id)
	if player != null:
		_do_pickup(player)

func _net_do_throw(start_position: Vector3, start_rotation: Vector3, velocity: Vector3, direction: Vector3, owner_actor_id: int, fuse_remaining := 0.0) -> void:
	var p = player_ref
	if p == null or not is_held:
		return
	if p.has_method("play_throw_animation"):
		p.play_throw_animation()
	_remember_deployment_forward(direction)
	var world = get_tree().current_scene
	get_parent().remove_child(self)
	world.add_child(self)
	global_position = start_position
	global_rotation = start_rotation
	scale = Vector3.ONE
	freeze = false
	sleeping = false
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = false
	is_held = false
	is_in_flight = true
	_throw_preview_active = false
	_cook_active = false
	online_owner_actor_id = owner_actor_id
	if p.has_method("clear_item_slot"):
		p.clear_item_slot(self)
	elif "held_item" in p and p.held_item == self:
		p.held_item = null
	linear_velocity = velocity
	angular_velocity = Vector3.ZERO
	_update_pickup_label()
	if fuse_time > 0.0 and multiplayer.is_server():
		_start_fuse_timer(maxf(float(fuse_remaining), 0.01))
	await get_tree().create_timer(0.15).timeout
	if is_in_flight:
		set_collision_mask_value(2, multiplayer.is_server())

func throw():
	var p = player_ref
	if p == null:
		return
	if p.has_method("play_throw_animation"):
		p.play_throw_animation()

	var forward = p.get_aim_direction()
	_remember_deployment_forward(forward)

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
	var remaining_fuse := _cook_remaining if _cook_active else fuse_time
	_throw_preview_active = false
	_cook_active = false
	if p.has_method("clear_item_slot"):
		p.clear_item_slot(self)
	elif "held_item" in p and p.held_item == self:
		p.held_item = null

	linear_velocity = Vector3.ZERO
	apply_impulse(forward * THROW_IMPULSE + Vector3.UP * THROW_ARC_UPWARD_BOOST)
	_update_pickup_label()

	if fuse_time > 0.0:
		_start_fuse_timer(maxf(remaining_fuse, 0.01))

	await get_tree().create_timer(0.15).timeout
	if is_in_flight:
		set_collision_mask_value(2, true)

func _start_fuse_timer(duration := -1.0):
	_fuse_generation += 1
	var generation := _fuse_generation
	await get_tree().create_timer(fuse_time if duration < 0.0 else duration).timeout
	if generation == _fuse_generation and is_in_flight:
		is_in_flight = false
		set_collision_mask_value(2, false)
		if NetworkManager.is_online():
			_server_request_online_deploy()
		else:
			_deploy()


func _deploy_from_hand() -> void:
	if not is_held or player_ref == null:
		return
	var holder = player_ref
	var deploy_pos: Vector3 = holder.global_position + Vector3.UP * 0.55
	var world = get_tree().current_scene
	if get_parent() != world:
		reparent(world, true)
	if holder.has_method("clear_item_slot"):
		holder.clear_item_slot(self)
	elif "held_item" in holder and holder.held_item == self:
		holder.held_item = null
	is_held = false
	player_ref = holder
	_spawn_deployed(deploy_pos, -1, -1)
	_hide_after_use()
	_schedule_respawn()


func _net_deploy_from_hand(deploy_pos: Vector3, deployed_id: int, owner_actor_id: int) -> void:
	if not is_held:
		return
	var holder = player_ref
	var world = get_tree().current_scene
	if get_parent() != world:
		reparent(world, true)
	if holder != null:
		if holder.has_method("clear_item_slot"):
			holder.clear_item_slot(self)
		elif "held_item" in holder and holder.held_item == self:
			holder.held_item = null
	is_held = false
	is_in_flight = false
	_cook_active = false
	_throw_preview_active = false
	_spawn_deployed(deploy_pos, deployed_id, owner_actor_id)
	_hide_after_use()

func _on_flight_body_entered(body):
	if not is_in_flight:
		return
	if body == player_ref:
		return
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	# Fuse-based items (e.g. grenades) keep bouncing on contact — they only
	# detonate when their fuse timer above expires, not on first hit.
	if fuse_time > 0.0:
		return
	is_in_flight = false
	set_collision_mask_value(2, false)
	if NetworkManager.is_online():
		_server_request_online_deploy()
	else:
		_deploy()

func _floor_deploy_position() -> Vector3:
	var deploy_pos := global_position
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.2, global_position + Vector3.DOWN * 12.0, 1)
	var hit := space.intersect_ray(q)
	if hit:
		deploy_pos = hit.position
	return deploy_pos

func _server_request_online_deploy() -> void:
	if not multiplayer.is_server():
		return
	var rm = _online_round_manager()
	if rm != null:
		rm.server_deploy_online_item(online_item_id, _floor_deploy_position(), online_owner_actor_id, respawn_after_deploy_time, _online_round_epoch())

func _deploy():
	var deploy_pos := _floor_deploy_position()
	_spawn_deployed(deploy_pos, -1, -1)
	_hide_after_use()
	_schedule_respawn()

func _spawn_deployed(deploy_pos: Vector3, deployed_id: int, owner_actor_id: int) -> void:
	if deployed_scene != null:
		var deployed = deployed_scene.instantiate()
		if deployed_id >= 0:
			deployed.name = "OnlineDeployed%d" % deployed_id
			deployed.set_meta("online_deployed_id", deployed_id)
			deployed.set_meta("online_owner_actor_id", owner_actor_id)
			deployed.add_to_group("online_deployed", true)
		if "owner_player" in deployed:
			deployed.owner_player = NetworkManager.find_actor(owner_actor_id) if NetworkManager.is_online() else player_ref
		if "initial_forward" in deployed:
			deployed.initial_forward = deployment_forward
		if "lifetime_seconds" in deployed:
			deployed.lifetime_seconds = deployed_lifetime
		var world = get_tree().current_scene
		# Set the future parent-local position before _ready() runs. One-shot
		# deployables such as grenades resolve their effect immediately in _ready.
		if world is Node3D:
			deployed.position = world.to_local(deploy_pos)
		world.add_child(deployed)
		deployed.global_position = deploy_pos
		# Maps are scaled (root scale 2); players get their scale cleaned by
		# round_manager, but a deployed child inherits the map scale. Cancel it
		# so deployed props (decoy, trap, pad) render at their authored,
		# player-matching size instead of 2x too big.
		var pscale = deployed.get_parent().global_transform.basis.get_scale()
		if pscale.x != 0.0 and pscale.y != 0.0 and pscale.z != 0.0:
			deployed.scale = Vector3(1.0 / pscale.x, 1.0 / pscale.y, 1.0 / pscale.z)
		deployed.add_to_group("deployed_trap")
		# Most deployables use the generic item lifetime. The decoy owns an
		# authoritative lifetime so its final pop is synchronized and cannot race
		# a second queue_free timer on each peer.
		if not (deployed.has_method("manages_deployed_lifetime") \
				and deployed.manages_deployed_lifetime()):
			_schedule_deployed_cleanup(deployed)

func _remember_deployment_forward(direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() > 0.01:
		deployment_forward = flat.normalized()

func _hide_after_use() -> void:
	_cook_active = false
	_throw_preview_active = false
	visible = false
	freeze = true
	$CollisionShape3D.disabled = true
	$Area3D.monitoring = false
	_update_pickup_label()

func _net_do_deploy(deploy_pos: Vector3, deployed_id: int, owner_actor_id: int) -> void:
	is_in_flight = false
	set_collision_mask_value(2, false)
	_spawn_deployed(deploy_pos, deployed_id, owner_actor_id)
	_hide_after_use()

func _net_consume() -> void:
	is_in_flight = false
	visible = false
	freeze = true
	$CollisionShape3D.disabled = true
	$Area3D.monitoring = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_update_pickup_label()

func _schedule_deployed_cleanup(deployed):
	await get_tree().create_timer(deployed_lifetime).timeout
	if is_instance_valid(deployed):
		deployed.queue_free()

# Set by round_manager for marker-spawned items: on respawn they re-roll into
# a random enabled item type (like powerups re-roll on respawn) instead of
# coming back as the same item.
var reroll_on_respawn := false

func _schedule_respawn():
	if NetworkManager.is_online():
		return
	if marker_refill_on_pickup and marker_refill_requested:
		queue_free()
		return
	await get_tree().create_timer(respawn_after_deploy_time).timeout
	if overtime_disabled:
		return
	if reroll_on_respawn and _respawn_as_random_item():
		return  # replaced by a fresh random item; this node is freed
	global_position = spawn_position
	global_rotation = spawn_rotation
	scale = Vector3.ONE
	visible = true
	freeze = true
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = true
	_update_pickup_label()

# Spawn a random enabled item at this marker's spot and free self. Returns
# false if it couldn't (empty pool / bad scene) so the caller restores self.
func _respawn_as_random_item() -> bool:
	var enabled: Array = []
	for t in GameConfig.ITEM_SCENES:
		if GameConfig.is_item_enabled(t):
			enabled.append(t)
	if enabled.is_empty():
		return false
	var pick: String = enabled[randi() % enabled.size()]
	var scene = load(GameConfig.ITEM_SCENES[pick])
	if scene == null:
		return false
	var inst = scene.instantiate()
	get_tree().current_scene.add_child(inst)
	inst.global_position = spawn_position
	if "spawn_position" in inst:
		inst.spawn_position = spawn_position
	if "spawn_rotation" in inst:
		inst.spawn_rotation = spawn_rotation
	if "reroll_on_respawn" in inst:
		inst.reroll_on_respawn = true
	inst.add_to_group("marker_spawned", true)
	queue_free()
	return true

func _update_pickup_label():
	if has_node("PickupLabel"):
		$PickupLabel.visible = not is_held and not is_in_flight and visible

func reset_to_spawn():
	_fuse_generation += 1
	_cook_active = false
	_throw_preview_active = false
	overtime_disabled = false
	if is_held:
		drop()
	is_in_flight = false
	visible = true
	scale = Vector3.ONE
	set_collision_mask_value(2, false)
	freeze = true
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = true
	global_position = spawn_position
	global_rotation = spawn_rotation
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_update_pickup_label()

func disable_for_overtime() -> void:
	overtime_disabled = true
	_drop_token += 1
	if is_held:
		var holder = player_ref
		var scene_tree := get_tree()
		var world := scene_tree.current_scene if scene_tree != null else null
		if world != null and get_parent() != world:
			reparent(world, true)
		if holder != null and holder.has_method("clear_item_slot"):
			holder.clear_item_slot(self)
	player_ref = null
	is_held = false
	is_in_flight = false
	_hide_after_use()

func preserve_held_for_standard_overtime() -> void:
	# The held item stays usable, but consuming or dropping it must never start
	# another ground-spawn cycle during this overtime.
	overtime_disabled = true
