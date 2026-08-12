extends RigidBody3D

const VisibilityRules = preload("res://combat_visibility.gd")

const BulletScene = preload("res://bullet.tscn")
const ONLINE_PICKUP_MAX_DISTANCE := 2.25
const ONLINE_FIRE_MIN_AIM_DOT := 0.25

@export var HELD_SCALE := 1.0
@export var projectile_speed := 200.0
@export var reload_time := 2.0
@export var loose_return_time := 5.0

var player_ref = null
var is_held = false
var can_fire = true

var spawn_position = Vector3.ZERO
var spawn_rotation = Vector3.ZERO

var disarm_lock_player = null
var disarm_lock_timer = 0.0
var _loose_generation := 0
var is_overtime_gun := false
var personal_mode_gun := false
var playpen_spawn_id := -1
var overtime_owner_id := -1
var overtime_disabled := false

func _ready():
	add_to_group("weapon")
	add_to_group("gun")
	$Area3D.body_entered.connect(_on_body_entered)
	$Area3D.body_exited.connect(_on_body_exited)
	$ReloadTimer.timeout.connect(_on_reload_finished)
	$ReloadTimer.wait_time = reload_time
	spawn_position = global_position
	spawn_rotation = global_rotation
	_build_locator_arrow()
	_update_pickup_label()

# Floating "▼" above the loose gun, visible through walls, so players can
# always find the one gun. Hidden while held (the holder gets an outline
# instead — see character_body_3d/dummy _set_gun_holder_outline).
var _locator_arrow: Label3D = null
var _locator_bob_time := 0.0

func _build_locator_arrow():
	_locator_arrow = Label3D.new()
	_locator_arrow.name = "LocatorArrow"
	_locator_arrow.text = "▼"
	_locator_arrow.font_size = 120
	_locator_arrow.modulate = Color(1.0, 0.72, 0.1)          # warm gold
	_locator_arrow.outline_size = 16
	_locator_arrow.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_locator_arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_locator_arrow.no_depth_test = true                       # visible through walls
	_locator_arrow.render_priority = 10
	_locator_arrow.position = Vector3(0.0, 1.2, 0.0)
	add_child(_locator_arrow)

func _process(delta):
	if disarm_lock_timer > 0.0:
		disarm_lock_timer -= delta
		if disarm_lock_timer <= 0.0:
			disarm_lock_player = null
	if _locator_arrow != null:
		_locator_arrow.visible = not is_held and not personal_mode_gun \
			and (GameConfig.game_mode == GameConfig.MODE_ONE_GUN or playpen_spawn_id >= 0)
		if not is_held:
			_locator_bob_time += delta * 3.0
			_locator_arrow.position.y = 1.2 + sin(_locator_bob_time) * 0.12
	if not is_held:
		_update_pickup_label()

func _on_body_entered(body):
	if body.has_method("register_interactable"):
		body.register_interactable(self)

func _on_body_exited(body):
	if body.has_method("unregister_interactable"):
		body.unregister_interactable(self)

func try_fire():
	if overtime_disabled or not is_held or not can_fire:
		return
	if NetworkManager.is_online():
		# Only the local-authority holder may fire; ask the server to spawn the
		# authoritative bullet (server owns hit detection + eliminations).
		if player_ref != null and player_ref.has_method("is_locally_controlled") \
				and player_ref.is_locally_controlled():
			var dir = _calculate_fire_direction()
			var epoch := _online_round_epoch()
			if NetworkManager.is_host():
				var acting_id := _holder_actor_id()
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
	_server_try_fire(NetworkManager.actor_id_for_peer(multiplayer.get_remote_sender_id()), dir, epoch)

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
	var origin := _calculate_fire_origin(shot_dir)
	NetworkManager.broadcast_match_rpc(self, &"_net_spawn_bullet",
		[origin, shot_dir, _holder_actor_id(), epoch])

@rpc("authority", "reliable", "call_local")
func _net_spawn_bullet(origin: Vector3, dir: Vector3, shooter_id: int, epoch: int) -> void:
	can_fire = false
	$ReloadTimer.start()
	var bullet = BulletScene.instantiate()
	bullet.set("projectile_speed", projectile_speed)
	bullet.set("net_shooter_id", shooter_id)
	bullet.set("is_server_bullet", multiplayer.is_server())
	bullet.set("net_round_epoch", epoch)
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = origin
	bullet.launch(dir, NetworkManager.find_actor(shooter_id))
	AudioManager.play_sfx("gun_shot")
	GameEvents.combat_noise.emit(origin, shooter_id, "gunshot", 30.0)

@rpc("any_peer", "reliable")
func _net_request_pickup(epoch: int) -> void:
	_server_try_pickup(NetworkManager.actor_id_for_peer(multiplayer.get_remote_sender_id()), epoch)

func _server_try_pickup(sender_id: int, epoch: int) -> void:
	if not multiplayer.is_server() or overtime_disabled or is_held:
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(epoch):
		return
	var player = NetworkManager.find_actor(sender_id)
	if player == null or player.get("is_eliminated"):
		return
	var max_distance := GameConfig.REACH_POWERUP_DISTANCE if player.has_method("has_active_reach") and player.has_active_reach() else ONLINE_PICKUP_MAX_DISTANCE
	if player.global_position.distance_to(global_position) > max_distance:
		return
	if max_distance > ONLINE_PICKUP_MAX_DISTANCE and not VisibilityRules.has_visual_contact(player, self):
		return
	if player == disarm_lock_player and disarm_lock_timer > 0.0:
		return
	NetworkManager.broadcast_match_rpc(self, &"_net_do_pickup", [sender_id])

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
	_enable_loose_physics()
	if multiplayer.is_server():
		var rm = _online_round_manager()
		if rm != null and bool(rm.get("practice_mode")) \
				and rm.has_method("server_schedule_playpen_gun_cleanup"):
			rm.server_schedule_playpen_gun_cleanup(self)

func request_online_drop() -> void:
	if personal_mode_gun:
		return
	if not NetworkManager.is_online() or not is_held or player_ref == null:
		return
	var epoch := _online_round_epoch()
	if NetworkManager.is_host():
		var acting_id := _holder_actor_id()
		_server_try_drop(acting_id, epoch)
	else:
		_net_request_drop.rpc_id(1, epoch)

@rpc("any_peer", "reliable")
func _net_request_drop(epoch: int) -> void:
	_server_try_drop(NetworkManager.actor_id_for_peer(multiplayer.get_remote_sender_id()), epoch)

func _server_try_drop(sender_id: int, epoch: int) -> void:
	if personal_mode_gun or not multiplayer.is_server() or not is_held or _holder_actor_id() != sender_id:
		return
	var rm = _online_round_manager()
	if rm == null or not rm.can_accept_online_combat(epoch):
		return
	var pos = player_ref.global_position + Vector3(0.0, 0.6, 0.0)
	NetworkManager.broadcast_match_rpc(self, &"_net_do_drop", [pos])

# Server-side: drop the gun for everyone (on elimination / disarm).
func net_force_drop() -> void:
	if personal_mode_gun or not multiplayer.is_server() or not is_held:
		return
	var pos = global_position
	if player_ref != null:
		pos = player_ref.global_position + Vector3(0, 0.6, 0)
	NetworkManager.broadcast_match_rpc(self, &"_net_do_drop", [pos])

# Server-side melee disarm. Unlike a normal drop, this also replicates the
# configured lock that prevents the victim immediately reclaiming the gun.
func net_force_disarm() -> void:
	if not multiplayer.is_server() or not is_held:
		return
	var holder_actor_id := _holder_actor_id()
	var pos = player_ref.global_position + Vector3(0, 0.6, 0) if player_ref != null else global_position
	if personal_mode_gun:
		force_full_reload()
		return
	NetworkManager.broadcast_match_rpc(self, &"_net_do_force_disarm",
		[pos, holder_actor_id])

@rpc("authority", "reliable", "call_local")
func _net_do_force_disarm(drop_pos: Vector3, holder_actor_id: int) -> void:
	var holder = NetworkManager.find_actor(holder_actor_id)
	if is_held:
		drop()
	global_position = drop_pos
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_enable_loose_physics()
	disarm_lock_player = holder
	disarm_lock_timer = GameConfig.disarm_lock_time

func fire():
	can_fire = false
	var bullet = BulletScene.instantiate()
	bullet.set("projectile_speed", projectile_speed)
	get_tree().current_scene.add_child(bullet)
	var fire_direction = _calculate_fire_direction()
	bullet.global_position = _calculate_fire_origin(fire_direction)
	bullet.launch(fire_direction, player_ref)
	AudioManager.play_sfx("gun_shot")
	GameEvents.combat_noise.emit(global_position, int(player_ref.get("actor_id")) if player_ref != null else -1, "gunshot", 30.0)
	$ReloadTimer.start()

func force_full_reload() -> void:
	if NetworkManager.is_online():
		if multiplayer.is_server():
			NetworkManager.broadcast_match_rpc(self, &"_net_force_full_reload")
		return
	_apply_forced_reload()


@rpc("authority", "reliable", "call_local")
func _net_force_full_reload() -> void:
	_apply_forced_reload()


func _apply_forced_reload() -> void:
	can_fire = false
	$ReloadTimer.start(reload_time)

func get_reload_progress():
	if can_fire:
		return 1.0
	return 1.0 - ($ReloadTimer.time_left / $ReloadTimer.wait_time)

func _calculate_fire_direction() -> Vector3:
	var cam: Camera3D = player_ref.get_camera()
	if cam == null:
		if player_ref.has_method("get_gun_fire_direction"):
			return player_ref.get_gun_fire_direction()
		return player_ref.get_aim_direction()
	var viewport_rect: Rect2 = cam.get_viewport().get_visible_rect()
	var crosshair_position: Vector2 = viewport_rect.position + viewport_rect.size * 0.5
	return cam.project_ray_normal(crosshair_position).normalized()

func _calculate_fire_origin(direction: Vector3) -> Vector3:
	var muzzle: Node3D = get_node_or_null("WaterGun/MuzzlePoint")
	var muzzle_origin: Vector3 = muzzle.global_position if muzzle != null else global_position
	var cam: Camera3D = player_ref.get_camera()
	if cam == null or direction.is_zero_approx():
		return muzzle_origin
	var viewport_rect: Rect2 = cam.get_viewport().get_visible_rect()
	var crosshair_position: Vector2 = viewport_rect.position + viewport_rect.size * 0.5
	var ray_origin: Vector3 = cam.project_ray_origin(crosshair_position)
	# The model's muzzle is shoulder-offset from the reticle. Start the gameplay
	# projectile on the reticle ray at the muzzle's forward depth so it remains
	# dead-center instead of converging diagonally from the left or right.
	var muzzle_depth: float = (muzzle_origin - ray_origin).dot(direction)
	var spawn_depth: float = maxf(muzzle_depth, cam.near + 0.05)
	return ray_origin + direction * spawn_depth

func _on_reload_finished():
	if NetworkManager.is_online():
		if multiplayer.is_server():
			NetworkManager.broadcast_match_rpc(self, &"_net_set_can_fire", [true])
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
	label.visible = not is_held and visible and $Area3D.monitoring
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
	if overtime_disabled or is_held:
		return false
	if p == null:
		p = player_ref
	if p == null:
		return false
	if p == disarm_lock_player and disarm_lock_timer > 0.0:
		return false
	if NetworkManager.is_online():
		# Online: don't pick up locally — ask the server to grant it to everyone.
		if p.has_method("is_locally_controlled") and p.is_locally_controlled():
			var epoch := _online_round_epoch()
			if NetworkManager.is_host():
				var acting_id := int(p.actor_id)
				_server_try_pickup(acting_id, epoch)
			else:
				_net_request_pickup.rpc_id(1, epoch)
		return true   # "handled" so _try_interact stops probing other objects
	return _local_pickup(p)

func _local_pickup(p, preserve_melee: bool = false) -> bool:
	if is_held or p == null:
		return false
	_cancel_loose_return()
	# Picking up the gun is always an instant swap, even from a melee weapon —
	# only giving up the gun requires the deliberate hold (see character_body_3d.gd).
	var swap_position = global_position
	if p.held_melee_weapon != null and not preserve_melee:
		var old_weapon = p.held_melee_weapon
		old_weapon.drop()
		old_weapon.global_position = swap_position
	is_held = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
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
	if is_overtime_gun:
		overtime_owner_id = int(p.get("actor_id")) if "actor_id" in p else p.get_instance_id()
	_update_pickup_label()
	if not personal_mode_gun:
		var pname = p.get_display_name() if p.has_method("get_display_name") else p.name
		GameEvents.gun_picked_up.emit(pname)
		GameEvents.actor_gun_picked_up.emit(int(p.get("actor_id")) if p.get("actor_id") != null else -1)
	return true

func drop():
	if personal_mode_gun:
		return
	var p = player_ref
	var world = get_tree().current_scene
	visible = true
	scale = Vector3.ONE
	var drop_transform = global_transform
	var hold_point = get_parent()
	hold_point.remove_child(self)
	world.add_child(self)
	global_transform = drop_transform
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = true
	is_held = false
	_enable_loose_physics()
	if p != null:
		p.holding_gun = false
		if not NetworkManager.is_online():
			apply_impulse(p.get_aim_direction() * 8.0)
	_update_pickup_label()
	GameEvents.gun_dropped.emit()
	_start_loose_return()


func _enable_loose_physics() -> void:
	# Held weapons are frozen long enough for the rigid body to enter a sleeping
	# state. Unfreezing alone is not sufficient on every physics backend, so
	# explicitly wake it and let gravity/world collision resolve the drop.
	freeze = false
	sleeping = false

func force_disarm():
	if personal_mode_gun:
		force_full_reload()
		return
	var holder = player_ref
	drop()
	disarm_lock_player = holder
	disarm_lock_timer = GameConfig.disarm_lock_time

func _cancel_loose_return() -> void:
	_loose_generation += 1

func _start_loose_return() -> void:
	_loose_generation += 1
	var generation := _loose_generation
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	_finish_loose_return_after_delay(generation)

func _finish_loose_return_after_delay(generation: int) -> void:
	await get_tree().create_timer(loose_return_time).timeout
	if generation != _loose_generation or is_held:
		return
	if NetworkManager.is_online():
		NetworkManager.broadcast_match_rpc(self, &"_net_return_loose_to_spawn")
	else:
		_return_loose_to_spawn()

@rpc("authority", "reliable", "call_local")
func _net_return_loose_to_spawn() -> void:
	if not is_held:
		_return_loose_to_spawn()

func _return_loose_to_spawn() -> void:
	_cancel_loose_return()
	global_position = spawn_position
	global_rotation = spawn_rotation
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_enable_loose_physics()
	_update_pickup_label()

func reset_to_spawn():
	overtime_disabled = false
	_cancel_loose_return()
	if is_held:
		drop()
	is_held = false
	player_ref = null
	visible = true
	scale = Vector3.ONE
	global_position = spawn_position
	global_rotation = spawn_rotation
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	can_fire = true
	$ReloadTimer.stop()
	disarm_lock_player = null
	disarm_lock_timer = 0.0
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = true
	_enable_loose_physics()
	_update_pickup_label()

func disable_for_overtime() -> void:
	overtime_disabled = true
	if is_held:
		var holder = player_ref
		# Cache the destination while this node still belongs to the SceneTree.
		# Calling get_tree() after remove_child() returns null and used to crash
		# the match at the exact frame overtime began.
		var scene_tree := get_tree()
		var world := scene_tree.current_scene if scene_tree != null else null
		if world != null and get_parent() != world:
			reparent(world, true)
		if holder != null:
			holder.holding_gun = false
	is_held = false
	player_ref = null
	visible = false
	$CollisionShape3D.disabled = true
	$Area3D.monitoring = false
	freeze = true
