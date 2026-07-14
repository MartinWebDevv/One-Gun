extends Area3D

@export var slow_duration := 4.0
@export var slow_multiplier := 0.5

var owner_player = null

func _ready():
	add_to_group("hazard")
	body_entered.connect(_on_body_entered)
	collision_layer = 0
	set_collision_mask_value(2, true)

func _on_body_entered(body):
	if not body.is_in_group("player"):
		return
	if not GameConfig.can_affect(owner_player, body):
		return
	if NetworkManager.is_online():
		if multiplayer.is_server():
			var rm = get_tree().current_scene.get_node_or_null("RoundManager")
			var actor_id = body.get("actor_id")
			if rm != null and actor_id != null:
				rm.server_apply_online_item_effect("slow", int(actor_id), {"duration": slow_duration, "multiplier": slow_multiplier})
		return
	if body.has_method("apply_slow"):
		body.apply_slow(slow_duration, slow_multiplier)
