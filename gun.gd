extends RigidBody3D

const BulletScene = preload("res://bullet.tscn")

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
	fire()

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
	can_fire = true

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

func pick_up(p = null):
	if is_held:
		return
	if p == null:
		p = player_ref
	if p == null:
		return
	if p == disarm_lock_player and disarm_lock_timer > 0.0:
		return
	if p.held_melee_weapon != null:
		p.held_melee_weapon.drop()
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

func drop():
	var p = player_ref
	var world = get_tree().current_scene
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
		apply_impulse(p.get_aim_direction() * 8.0)
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
	disarm_lock_player = null
	disarm_lock_timer = 0.0
	_update_pickup_label()
