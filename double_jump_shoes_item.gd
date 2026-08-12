extends "res://item.gd"

var _activation_armed := false


func begin_use() -> void:
	if not is_held or player_ref == null:
		return
	_activation_armed = true


func release_use() -> void:
	if not _activation_armed or not is_held or player_ref == null:
		return
	_activation_armed = false
	if NetworkManager.is_online():
		var rm = _online_round_manager()
		if rm != null:
			rm.request_online_item_action(online_item_id, "activate_shoes", _online_round_epoch())
	else:
		_do_activate_for(player_ref)


func cancel_use() -> void:
	_activation_armed = false


func is_throw_preview_active() -> bool:
	return false


func get_throw_preview_data() -> Dictionary:
	return {}


func _server_try_activate(sender_id: int, epoch: int) -> void:
	if not multiplayer.is_server() or not is_held or _holder_actor_id() != sender_id:
		return
	var rm = _online_round_manager()
	var holder = NetworkManager.find_actor(sender_id)
	if rm == null or holder == null or not rm.can_accept_online_combat(epoch):
		return
	if bool(holder.get("double_jump_shoes_active")):
		return
	rm.broadcast_online_item_action(online_item_id, "activate_shoes",
		{"holder_actor_id": sender_id})
	rm.server_consume_online_item(online_item_id, respawn_after_deploy_time, epoch)


func _net_do_activate(holder_actor_id: int) -> void:
	var holder = NetworkManager.find_actor(holder_actor_id)
	if holder != null:
		_do_activate_for(holder)


func _do_activate_for(holder) -> void:
	if holder == null or bool(holder.get("double_jump_shoes_active")):
		return
	if holder.has_method("activate_double_jump_shoes"):
		holder.activate_double_jump_shoes()
	if holder.has_method("clear_item_slot"):
		holder.clear_item_slot(self)
	elif "held_item" in holder and holder.held_item == self:
		holder.held_item = null
	var world = get_tree().current_scene
	if world != null and get_parent() != world:
		reparent(world, true)
	player_ref = null
	is_held = false
	_activation_armed = false
	_hide_after_use()
	if not NetworkManager.is_online():
		_schedule_respawn()
