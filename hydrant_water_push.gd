class_name HydrantWaterPush
extends Area3D

## Directional launch volume for Maple & 3rd's bursting fire hydrant. The
## authored collision box controls where the water can catch a player, while
## LaunchDirection independently controls the ballistic direction.

@export_category("Water Jet Tuning")
@export var launch_direction_path: NodePath = NodePath("LaunchDirection")
@export_range(0.0, 30.0, 0.5) var push_speed := 15.0
@export_range(0.0, 10.0, 0.1) var minimum_jump_velocity := 0.1

const FALLBACK_LOCAL_DIRECTION := Vector3(0.0, 1.0, -0.585)
const BODY_MARGIN := 0.55

var _push_direction := FALLBACK_LOCAL_DIRECTION.normalized()
var _boosted_bodies: Dictionary = {}


func _ready() -> void:
	collision_layer = 0
	set_collision_mask_value(2, true)
	_configure_launch_direction()


func _physics_process(_delta: float) -> void:
	# The host resolves online launches from synchronized actor positions. Peers
	# receive the exact velocity through RoundManager's actor-ID action path.
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	for body in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(body) or not body.is_in_group("player"):
			continue
		var character := body as CharacterBody3D
		if character == null:
			continue
		var body_id := character.get_instance_id()
		if not is_body_in_activation_zone(character):
			# Leaving the small nozzle-side zone re-arms the next jump.
			_boosted_bodies.erase(body_id)
			continue
		if bool(character.get("is_eliminated")):
			continue
		if _boosted_bodies.has(body_id):
			continue
		# Walking through the low end of the volume does nothing. A regular jump
		# into the visible stream arms the push, matching the requested interaction.
		if character.velocity.y <= minimum_jump_velocity:
			continue
		_boosted_bodies[body_id] = true
		_apply_push(character, _push_direction * push_speed)


func get_push_direction() -> Vector3:
	return _push_direction


func is_body_in_activation_zone(body: Node3D) -> bool:
	if not is_instance_valid(body):
		return false
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or collision.disabled:
		return false
	var shape := collision.shape as BoxShape3D
	if shape == null:
		return false
	# Test against the exact box authored in the map. This intentionally does not
	# derive volume placement from the launch vector: level-design edits to the
	# collision box must survive unchanged when the scene starts.
	var local_position := collision.to_local(body.global_position)
	var half_size := shape.size * 0.5
	return absf(local_position.x) <= half_size.x + BODY_MARGIN \
		and absf(local_position.y) <= half_size.y + BODY_MARGIN \
		and absf(local_position.z) <= half_size.z + BODY_MARGIN


static func direction_between_points(origin: Vector3, target: Vector3) -> Vector3:
	var direction := target - origin
	if direction.is_zero_approx():
		return FALLBACK_LOCAL_DIRECTION.normalized()
	return direction.normalized()


func _configure_launch_direction() -> void:
	var launch_direction := get_node_or_null(launch_direction_path) as Node3D
	if launch_direction == null:
		push_warning(
			"HydrantWaterPush: launch direction is missing at %s." % launch_direction_path)
		_push_direction = (
			global_basis.orthonormalized() * FALLBACK_LOCAL_DIRECTION).normalized()
		return
	_push_direction = direction_between_points(
		global_position, launch_direction.global_position)


func _apply_push(body: CharacterBody3D, launch_velocity: Vector3) -> void:
	if NetworkManager.is_online():
		var round_manager = get_tree().current_scene.get_node_or_null("RoundManager")
		var target_actor_id = body.get("actor_id")
		if round_manager != null and target_actor_id != null:
			round_manager.server_apply_online_item_effect(
				"directional_launch", int(target_actor_id), {"velocity": launch_velocity})
		return
	if body.has_method("apply_directional_launch"):
		body.apply_directional_launch(launch_velocity)
	else:
		body.velocity = launch_velocity
