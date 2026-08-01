extends Area3D

## Removes actors that fall below an arena whose decorative environment is not
## itself playable. Online elimination remains host authoritative.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body == null or not body.is_in_group("player") or bool(body.get("is_eliminated")):
		return
	if NetworkManager.is_online():
		if not multiplayer.is_server():
			return
		var round_manager = get_tree().current_scene.get_node_or_null("RoundManager")
		if round_manager != null:
			round_manager.server_eliminate(
				int(body.get("actor_id")), -1, round_manager.online_round_epoch,
				"THE DROP", "FALL", "environment")
		return
	if body.has_method("eliminate"):
		body.eliminate("THE DROP", "FALL", "environment")
