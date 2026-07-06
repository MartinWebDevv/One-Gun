extends RigidBody3D

@export var item_type := "bubble_gum"
@export var deployed_scene: PackedScene
@export var deployed_lifetime := 8.0
@export var respawn_after_deploy_time := 12.0
@export var HELD_SCALE := 0.5

const THROW_IMPULSE = 10.0

var player_ref = null
var is_held = false
var is_in_flight = false

var spawn_position = Vector3.ZERO
var spawn_rotation = Vector3.ZERO

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
	_update_pickup_label()

func _on_pickup_area_entered(body):
	if body.has_method("register_interactable"):
		body.register_interactable(self)

func _on_pickup_area_exited(body):
	if body.has_method("unregister_interactable"):
		body.unregister_interactable(self)

func pick_up(p = null):
	if p == null:
		p = player_ref
	if p == null:
		return
	if "held_item" in p and p.held_item != null:
		return
	is_held = true
	is_in_flight = false
	freeze = true
	$CollisionShape3D.disabled = true
	$Area3D.monitoring = false
	var hold_point = p.get_item_hold_point()
	var prev_parent = get_parent()
	if prev_parent != null:
		prev_parent.remove_child(self)
	hold_point.add_child(self)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	scale = Vector3.ONE * HELD_SCALE
	p.held_item = self
	player_ref = p
	_update_pickup_label()

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
	if p != null and p.held_item == self:
		p.held_item = null
	_update_pickup_label()

func try_throw():
	if not is_held:
		return
	throw()

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
	if p.held_item == self:
		p.held_item = null

	linear_velocity = Vector3.ZERO
	apply_impulse(forward * THROW_IMPULSE)
	_update_pickup_label()

	await get_tree().create_timer(0.15).timeout
	if is_in_flight:
		set_collision_mask_value(2, true)

func _on_flight_body_entered(body):
	if not is_in_flight:
		return
	if body == player_ref:
		return
	is_in_flight = false
	set_collision_mask_value(2, false)
	_deploy()

func _deploy():
	if deployed_scene != null:
		var deployed = deployed_scene.instantiate()
		get_tree().current_scene.add_child(deployed)
		deployed.global_position = global_position
		deployed.add_to_group("deployed_trap")
		if "owner_player" in deployed:
			deployed.owner_player = player_ref
		_schedule_deployed_cleanup(deployed)
	visible = false
	freeze = true
	$CollisionShape3D.disabled = true
	$Area3D.monitoring = false
	_update_pickup_label()
	_schedule_respawn()

func _schedule_deployed_cleanup(deployed):
	await get_tree().create_timer(deployed_lifetime).timeout
	if is_instance_valid(deployed):
		deployed.queue_free()

func _schedule_respawn():
	await get_tree().create_timer(respawn_after_deploy_time).timeout
	global_position = spawn_position
	global_rotation = spawn_rotation
	scale = Vector3.ONE
	visible = true
	freeze = false
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = true
	_update_pickup_label()

func _update_pickup_label():
	if has_node("PickupLabel"):
		$PickupLabel.visible = not is_held and not is_in_flight and visible

func reset_to_spawn():
	if is_held:
		drop()
	is_in_flight = false
	visible = true
	scale = Vector3.ONE
	set_collision_mask_value(2, false)
	freeze = false
	$CollisionShape3D.disabled = false
	$Area3D.monitoring = true
	global_position = spawn_position
	global_rotation = spawn_rotation
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_update_pickup_label()
