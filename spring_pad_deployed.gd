extends Area3D

## Deployed spring pad: launches anyone who steps on it. Lives 30s.
## Re-triggerable with a short per-body cooldown.

@export var launch_velocity := 11.0
@export var lifetime := 30.0
var owner_player = null
var _cooldowns := {}

func _ready() -> void:
	collision_layer = 0
	set_collision_mask_value(2, true)
	body_entered.connect(_on_body_entered)
	await get_tree().create_timer(lifetime).timeout
	queue_free()

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var now := Time.get_ticks_msec()
	if _cooldowns.has(body) and now - _cooldowns[body] < 500:
		return
	_cooldowns[body] = now
	if NetworkManager.is_online():
		if multiplayer.is_server():
			var rm = get_tree().current_scene.get_node_or_null("RoundManager")
			var actor_id = body.get("actor_id")
			if rm != null and actor_id != null:
				rm.server_apply_online_item_effect("launch", int(actor_id), {"velocity": launch_velocity})
				rm.broadcast_online_deployed_action(int(get_meta("online_deployed_id", -1)), "bounce")
		return
	if "velocity" in body:
		body.velocity.y = launch_velocity
	_play_bounce_visual()

func _play_bounce_visual() -> void:
	# squash & stretch
	var visual = get_node_or_null("PadModel")
	if visual:
		var tw := create_tween()
		tw.tween_property(visual, "scale", Vector3(1.25, 0.5, 1.25), 0.08)
		tw.tween_property(visual, "scale", Vector3(0.9, 1.35, 0.9), 0.10)
		tw.tween_property(visual, "scale", Vector3.ONE, 0.16)

func apply_online_action(action: String, _data: Dictionary) -> void:
	if action == "bounce":
		_play_bounce_visual()
