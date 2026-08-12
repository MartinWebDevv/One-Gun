extends Area3D

## Gameplay volume for the City map's steaming manhole. A player must already
## be moving upward inside the steam, so walking across it does not launch them.

@export_category("Steam Boost Tuning")
@export_range(0.0, 40.0, 0.5) var lift_strength: float = 15.0
## Fast-fall gravity begins only after a steam-launched body rises this far
## above its launch point and starts descending.
@export_range(0.0, 10.0, 0.25) var descent_height_gate: float = 2.0
@export_range(1.0, 8.0, 0.1) var descent_gravity_multiplier: float = 3.0

const MINIMUM_UPWARD_VELOCITY := 0.1

var _boosted_bodies: Dictionary = {}


func _ready() -> void:
	collision_layer = 0
	set_collision_mask_value(2, true)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		if not is_instance_valid(body) or not body.is_in_group("player"):
			continue
		var character := body as CharacterBody3D
		if character == null:
			continue
		var body_id: int = character.get_instance_id()
		var vertical_velocity: float = character.velocity.y
		if vertical_velocity <= MINIMUM_UPWARD_VELOCITY:
			# Re-arm after the player reaches the apex or lands while still inside.
			_boosted_bodies.erase(body_id)
			continue
		if _boosted_bodies.has(body_id):
			continue
		_boosted_bodies[body_id] = true
		_apply_boost(character, maxf(vertical_velocity, lift_strength))


func _apply_boost(body: CharacterBody3D, launch_velocity: float) -> void:
	var launch_origin_y: float = body.global_position.y
	if NetworkManager.is_online():
		if multiplayer.is_server():
			var round_manager = get_tree().current_scene.get_node_or_null("RoundManager")
			var target_actor_id = body.get("actor_id")
			if round_manager != null and target_actor_id != null:
				round_manager.server_apply_online_item_effect(
					"steam_launch", int(target_actor_id), {
						"velocity": launch_velocity,
						"origin_y": launch_origin_y,
						"height_gate": descent_height_gate,
						"gravity_multiplier": descent_gravity_multiplier,
					})
		return
	if body.has_method("apply_steam_boost"):
		body.apply_steam_boost(
			launch_velocity, launch_origin_y, descent_height_gate,
			descent_gravity_multiplier)
	else:
		body.velocity.y = launch_velocity


func _on_body_exited(body: Node3D) -> void:
	_boosted_bodies.erase(body.get_instance_id())
