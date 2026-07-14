extends Area3D

## Deployed bear trap: sits open until a player/bot steps in, then snaps shut
## and roots them in place (stagger). One use.

@export var root_duration := 1.5
@export var idle_lifetime := 20.0
var owner_player = null
var _sprung := false

func _ready() -> void:
	collision_layer = 0
	set_collision_mask_value(2, true)
	body_entered.connect(_on_body_entered)
	await get_tree().create_timer(idle_lifetime).timeout
	if not _sprung:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if _sprung:
		return
	if not body.is_in_group("player"):
		return
	if owner_player != null and not GameConfig.can_affect(owner_player, body):
		return
	if NetworkManager.is_online():
		if multiplayer.is_server():
			var rm = get_tree().current_scene.get_node_or_null("RoundManager")
			var actor_id = body.get("actor_id")
			if rm != null and actor_id != null:
				rm.server_apply_online_item_effect("stagger", int(actor_id), {"duration": root_duration})
				rm.broadcast_online_deployed_action(int(get_meta("online_deployed_id", -1)), "trigger")
		return
	_trigger_visual(body)

func _trigger_visual(body = null) -> void:
	_sprung = true
	var open = get_node_or_null("TrapOpen")
	var closed = get_node_or_null("TrapClosed")
	if open:
		open.visible = false
	if closed:
		closed.visible = true
	if body != null and body.has_method("apply_stagger"):
		body.apply_stagger(root_duration)
	await get_tree().create_timer(2.0).timeout
	queue_free()

func apply_online_action(action: String, _data: Dictionary) -> void:
	if action == "trigger" and not _sprung:
		_trigger_visual()
