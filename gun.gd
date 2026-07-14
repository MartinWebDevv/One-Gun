extends RigidBody3D

const BulletScene = preload("res://bullet.tscn")
const ONLINE_PICKUP_MAX_DISTANCE := 2.25
const ONLINE_FIRE_MIN_AIM_DOT := 0.25

@export var HELD_SCALE := 1.0

var player_ref = null
var is_held = false
var can_fire = true

var spawn_position = Vector3.ZERO
var spawn_rotation = Vector3.ZERO

var disarm_lock_player = null
var disarm_lock_timer = 0.0

func _ready():
	add_to_group("weapon")
	add_to_group("gun")
	$Area3D.body_entered.connect(_on_body_entered)
	$Area3D.body_exited.connect(_on_body_exited)
	$ReloadTimer.timeout.connect(_on_reload_finished)
	spawn_position = global_position
	spawn_rotation = global_rotation
	_update_pickup_label()

func _process(delta):
	if disarm_lock_timer > 0.0:
		disarm_lock_timer -= delta
		if disarm_lock_timer <= 0.0:
			disarm_lock_player = null
	if not is_held:
		_update_pickup_label()

func _on_body_entered(body):
	if body.has_method("register_interactable"):
		body.register_interactable(self)

func _on_body_exited(body):
	if body.has_method("unregister_interactable"):
		body.unregister_interactable(self)

func try_fire():
	if not is_held or not can_fire:
		return
	if NetworkManager.is_online():
		# Only the local-authority holder may fire; ask the server to spawn the
		# authoritative bullet (server owns hit detection + eliminations).
		if player_ref != null and player_ref.is_multiplayer_authority():
			var dir = _calculate_fire_direction()
			var epoch := _online_round_epoch()
			if NetworkManager.is_host():
				var acting_id := _holder_actor_id() if "is_bot" in player_ref and player_ref.is_bot else NetworkManager.local_id()
				_server_try_fire(acting_id, dir, epoch)
			else:
				_net_request_fire.rpc_id(1, dir, epoch)
		return
	fire()

# ---- online combat (host-authoritative) ----------------------------------

func _holder_peer_id() -> int:
	if player_ref != null and "owner_peer_id" in player_ref:
		return player_ref.owner_peer_id
	if player_ref != null and "net_authority_id" in player_ref:
		return player_ref.net_authority_id
	return -1

func _holder_actor_id() -> int:
	if player_ref != null and "actor_id" in player_ref:
		return player_ref.actor_id
	return _holder_peer_id()

@rpc("any_peer", "reliable")
func _net_request_fire(dir: Vector3, epoch: int) -> void:
	_server_try_fire(multiplayer.get_remote_sender_id(), dir, epoch)

func _server_try_fire(sender_id: int, dir: Vector3, epoch: int) -> void:
	if not multiplayer.is_server() or not is_held or not can_fire:
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(epoch):
		return
	var holder = NetworkManager.find_actor(sender_id)
	if holder == null or holder != player_ref or _holder_actor_id() != sender_id:
		return
	if holder.get("is_eliminated") or not dir.is_finite() or dir.is_zero_approx():
		return
	var server_aim: Vector3 = holder.get_aim_direction().normalized()
	var shot_dir := dir.normalized()
	if server_aim.dot(shot_dir) < ONLINE_FIRE_MIN_AIM_DOT:
		return
	var muzzle = get_node_or_null("WaterGun/MuzzlePoint")
	var origin: Vector3 = muzzle.global_position if muzzle != null else global_position
	_net_spawn_bullet.rpc(origin, shot_dir, _holder_actor_id(), epoch)

@rpc("authority", "reliable", "call_local")
func _net_spawn_bullet(origin: Vector3, dir: Vector3, shooter_id: int, epoch: int) -> void:
	can_fire = false
	$ReloadTimer.start()
	var bullet = BulletScene.instantiate()
	bullet.set("net_shooter_id", shooter_id)
	bullet.set("is_server_bullet", multiplayer.is_server())
	bullet.set("net_round_epoch", epoch)
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = origin
	bullet.launch(dir, null)
	AudioManager.play_sfx("gun_shot")

@rpc("any_peer", "reliable")
func _net_request_pickup(epoch: int) -> void:
	_server_try_pickup(multiplayer.get_remote_sender_id(), epoch)

func _server_try_pickup(sender_id: int, epoch: int) -> void:
	if not multiplayer.is_server() or is_held:
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(epoch):
		return
	var player = NetworkManager.find_actor(sender_id)
	if player == null or player.get("is_eliminated"):
		return
	if player.global_position.distance_to(global_position) > ONLINE_PICKUP_MAX_DISTANCE:
		return
	if player == disarm_lock_player and disarm_lock_timer > 0.0:
		return
	_net_do_pickup.rpc(sender_id)

func _online_round_manager():
	var scene := get_tree().current_scene
	return scene.get_node_or_null("RoundManager") if scene != null else null

func _online_round_epoch() -> int:
	var rm = _online_round_manager()
	return int(rm.get("online_round_epoch")) if rm != null else -1

@rpc("authority", "reliable", "call_local")
func _net_do_pickup(holder_id: int) -> void:
	var player = NetworkManager.find_actor(holder_id)
	if player != null:
		_local_pickup(player)

@rpc("authority", "reliable", "call_local")
func _net_do_drop(drop_pos: Vector3) -> void:
	if not is_held:
		return
	drop()
	global_position = drop_pos
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func request_online_drop() -> void:
	if not NetworkManager.is_online() or not is_held or player_ref == null:
		return
	var epoch := _online_round_epoch()
	if NetworkManager.is_host():
		var acting_id := _holder_actor_id() if "is_bot" in player_ref and player_ref.is_bot else NetworkManager.local_id()
		_server_try_drop(acting_id, epoch)
	else:
		_net_request_drop.rpc_id(1, epoch)

@rpc("any_peer", "reliable")
func _net_request_drop(epoch: int) -> void:
	_server_try_drop(multiplayer.get_remote_sender_id(), epoch)

func _server_try_drop(sender_id: int, epoch: int) -> void:
	if not multiplayer.is_server() or not is_held or _holder_actor_id() != sender_id:
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(epoch):
		return
	var pos = player_ref.global_position + Vector3(0.0, 0.6, 0.0)
	_net_do_drop.rpc(pos)

# Server-side: drop the gun for everyone (on elimination / disarm).
func net_force_drop() -> void:
	if not multiplayer.is_server() or not is_held:
		return
	var pos = global_position
	if player_ref != null:
		pos = player_ref.global_position + Vector3(0, 0.6, 0)
	_net_do_drop.rpc(pos)

# Server-side melee disarm. Unlike a normal drop, this also replicates the
# configured lock that prevents the victim immediately reclaiming the gun.
func net_force_disarm() -> void:
	if not multiplayer.is_server() or not is_held:
		return
	var holder_actor_id := _holder_actor_id()
	var pos = player_ref.global_position + Vector3(0, 0.6, 0) if player_ref != null else global_position
	_net_do_force_disarm.rpc(pos, holder_actor_id)

@rpc("authority", "reliable", "call_local")
func _net_do_force_disarm(drop_pos: Vector3, holder_actor_id: int) -> void:
	var holder = NetworkManager.find_actor(holder_actor_id)
	if is_held:
		drop()
	global_position = drop_pos
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	disarm_lock_player = holder
	disarm_lock_timer = GameConfig.disarm_lock_time

func fire():
	can_fire = false
	var bullet = BulletScene.instantiate()
	get_tree().current_scene.add_child(bullet)
	var muzzle = get_node_or_null("WaterGun/MuzzlePoint")
	if muzzle != null:
		bullet.global_transform = muzzle.global_transform
	else:
		bullet.global_transform = global_transform
	var fire_direction = _calculate_fire_direction()
	bullet.launch(fire_direction, player_ref)
	AudioManager.play_sfx("gun_shot")
	$ReloadTimer.start()

func get_reload_progress():
	if can_fire:
		return 1.0
	return 1.0 - ($ReloadTimer.time_left / $ReloadTimer.wait_time)

func _calculate_fire_direction():
	var cam = player_ref.get_camera()
	if cam == null:
		if player_ref.has_method("get_gun_fire_direction"):
			return player_ref.get_gun_fire_direction()
		return player_ref.get_aim_direction()
	var from = cam.global_transform.origin
	var to = from + (-cam.global_transform.basis.z) * 1000.0
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player_ref.get_rid(), get_rid()]
	var result = space_state.intersect_ray(query)
	var target_point = to
	if result:
		target_point = result.position
	# Direction from muzzle tip toward crosshair target point — eliminates
	# the upward bullet arc caused by computing from the lower gun root origin.
	var muzzle = get_node_or_null("WaterGun/MuzzlePoint")
	var fire_origin = muzzle.global_position if muzzle != null else global_position
	return (target_point - fire_origin).normalized()

func _on_reload_finished():
	if NetworkManager.is_online():
		if multiplayer.is_server():
			_net_set_can_fire.rpc(true)
		return
	can_fire = true

@rpc("authority", "reliable", "call_local")
func _net_set_can_fire(value: bool) -> void:
	can_fire = value
	if value:
		$ReloadTimer.stop()

func _update_pickup_label():
	if not has_node("PickupLabel"):
		return
	var label = $PickupLabel
	label.visible = not is_held
	if not label.visible:
		return
	var bodies = $Area3D.get_overlapping_bodies()
	var uses_gamepad = false
	for body in bodies:
		if body.is_in_group("player") and "use_gamepad_look" in body:
			uses_gamepad = body.use_gamepad_look
			break
	var button_prompt = "[⏹️]" if uses_gamepad else "[F]"
	label.text = button_prompt + "  Gun"

func pick_up(p = null) -> bool:
	if is_held:
		return false
	if p == null:
		p = player_ref
	if p == null:
		return false
	if p == disarm_lock_player and disarm_lock_timer > 0.0:
		return false
	if NetworkManager.is_online():
		# Online: don't pick up locally — ask the server to grant it to everyone.
		if p.is_multiplayer_authority():
			var epoch := _online_round_epoch()
			if NetworkManager.is_host():
				var acting_id := int(p.actor_id) if "is_bot" in p and p.is_bot else NetworkManager.local_id()
				_server_try_pickup(acting_id, epoch)
			else:
				_net_request_pickup.rpc_id(1, epoch)
		return true   # "handled" so _try_interact stops probing other objects
	return _local_pickup(p)

func _local_pickup(p) -> bool:
	if is_held or p == null:
		return false
	# Picking up the gun is always an instant swap, even from a melee weapon —
	# only giving up the gun requires the deliberate hold (see character_body_3d.gd).
	var swap_position = global_position
	if p.held_melee_weapon != null:
		var old_weapon = p.held_melee_weapon
		old_weapon.drop()
		old_weapon.global_position = swap_position
	is_held = true
	freeze = true
	$CollisionShape3D.disabled = true
	$Area3D.monitoring = false
	var hold_point = p.get_hold_point()
	var prev_parent = get_parent()
	if prev_parent != null:
		prev_parent.remove_child(self)
	hold_point.add_child(self)
	position = Vector3.ZERO
	rotation = Vector3(0, PI, 0)
	scale = Vector3.ONE * HELD_SCALE
	p.holding_gun = true
	player_ref = p
	_update_pickup_label()
	var pname = p.get_display_name() if p.has_method("get_display_name") else p.name
	GameEvents.gun_picked_up.emit(pname)
	return true

func drop():
	var p = player_ref
	var world = get_tree().current_scene
	visible = true
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
	if p != null:
		p.holding_gun = false
		if not NetworkManager.is_online():
			apply_impulse(p.get_aim_direction() * 8.0)
	if NetworkManager.is_online():
		# freeze at the drop spot so it rests identically on every peer
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	_update_pickup_label()
	GameEvents.gun_dropped.emit()

func force_disarm():
	var holder = player_ref
	drop()
	disarm_lock_player = holder
	disarm_lock_timer = GameConfig.disarm_lock_time

func reset_to_spawn():
	if is_held:
		drop()
	scale = Vector3.ONE
	global_position = spawn_position
	global_rotation = spawn_rotation
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	can_fire = true
	$ReloadTimer.stop()
	disarm_lock_player = null
	disarm_lock_timer = 0.0
	_update_pickup_label()
