extends Node

const TEST_PORT := 24756
const TEST_MAP := "res://node_3d.tscn"
const TIMEOUT_MSEC := 65000

var role := ""
var deadline := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
	if role not in ["controller", "guest"]:
		_fail("missing --role=controller|guest")
		return
	call_deferred("_detach_and_run")


func _detach_and_run() -> void:
	reparent(get_tree().root)
	deadline = Time.get_ticks_msec() + TIMEOUT_MSEC
	if not NetworkManager.join_game("127.0.0.1", TEST_PORT):
		_fail("join_game failed")
		return
	if not await _wait_until(func(): return NetworkManager.peers.size() == 2):
		_fail("two-client roster was not synchronized")
		return
	if not NetworkManager.is_dedicated_session():
		_fail("server did not advertise a dedicated session")
		return
	if role == "controller":
		if not NetworkManager.can_manage_lobby():
			_fail("first client was not assigned lobby control")
			return
		GameConfig.bot_configs = []
		GameConfig.rounds_per_set = 1
		GameConfig.sets_per_match = 1
		for item_type in GameConfig.item_registry:
			GameConfig.item_registry[item_type]["enabled"] = item_type == "smoke_bomb"
		NetworkManager.broadcast_match_config(GameConfig.snapshot_for_network(), TEST_MAP)
		if not await _wait_until(NetworkManager.are_all_lobby_guests_ready):
			_fail("guest never became ready")
			return
		NetworkManager.begin_prelaunch(TEST_MAP)
	else:
		if NetworkManager.can_manage_lobby():
			_fail("second client incorrectly received lobby control")
			return
		NetworkManager.set_local_lobby_ready(true)

	if not await _wait_until(_match_is_live):
		_fail("dedicated match did not reach live combat with two remote humans")
		return
	print("DEDICATED_SERVER_PASS %s" % role)
	if not await _verify_client_owned_movement_sync():
		_fail("client-owned movement did not replicate through the dedicated server")
		return
	print("DEDICATED_MOVEMENT_SYNC_PASS %s" % role)
	await get_tree().create_timer(1.0).timeout
	var pickup_ok := await _controller_pickup_through_input() \
		if role == "controller" else await _wait_until(_controller_gun_is_held)
	if not pickup_ok:
		_fail("rendered-client pickup path did not complete for the controller")
		return
	print("DEDICATED_INPUT_PICKUP_PASS %s" % role)
	var fire_ok := await _controller_fire_through_input() \
		if role == "controller" else await _wait_until(_controller_gun_is_reloading)
	if not fire_ok:
		_fail("controller gun fire did not replicate through the stable coordinator")
		return
	print("DEDICATED_INPUT_FIRE_PASS %s" % role)
	if role == "controller" and not await _wait_until(_controller_gun_is_ready):
		_fail("controller gun reload did not replicate")
		return
	var drop_ok := await _controller_drop_gun() \
		if role == "controller" else await _wait_until(_controller_gun_is_dropped)
	if not drop_ok:
		_fail("controller gun drop did not replicate through the stable coordinator")
		return
	print("DEDICATED_INPUT_DROP_PASS %s" % role)
	var melee_pickup_ok := await _controller_pickup_melee_through_input() \
		if role == "controller" else await _wait_until(_controller_melee_is_held)
	if not melee_pickup_ok:
		_fail("controller melee pickup did not replicate through the stable coordinator")
		return
	print("DEDICATED_MELEE_PICKUP_PASS %s" % role)
	var melee_swing_ok := await _controller_swing_melee_through_input() \
		if role == "controller" else await _wait_until(_controller_melee_is_swinging)
	if not melee_swing_ok:
		_fail("controller melee swing did not replicate through the stable coordinator")
		return
	print("DEDICATED_MELEE_SWING_PASS %s" % role)
	if role == "controller" and not await _wait_until(_controller_melee_is_ready):
		_fail("controller melee recovery did not replicate")
		return
	var melee_drop_ok := await _controller_drop_melee() \
		if role == "controller" else await _wait_until(_controller_melee_is_dropped)
	if not melee_drop_ok:
		_fail("controller melee drop did not replicate through the stable coordinator")
		return
	print("DEDICATED_MELEE_DROP_PASS %s" % role)
	var item_pickup_ok := await _controller_pickup_item_through_input() \
		if role == "controller" else await _wait_until(_controller_item_is_held)
	if not item_pickup_ok:
		_fail("controller item pickup did not replicate through the stable coordinator")
		return
	print("DEDICATED_ITEM_PICKUP_PASS %s" % role)
	var item_drop_ok := await _controller_drop_item() \
		if role == "controller" else await _wait_until(_controller_item_is_dropped)
	if not item_drop_ok:
		_fail("controller item drop did not replicate through the stable coordinator")
		return
	print("DEDICATED_ITEM_DROP_PASS %s" % role)
	if role == "controller" and not await _controller_pickup_item_through_input():
		_fail("controller item repickup did not complete")
		return
	var item_throw_ok := await _controller_throw_item_through_input() \
		if role == "controller" else await _wait_until(_controller_item_is_in_flight)
	if not item_throw_ok:
		_fail("controller item activation/throw did not replicate through the stable coordinator")
		return
	print("DEDICATED_ITEM_THROW_PASS %s" % role)
	if role == "controller":
		await get_tree().create_timer(0.75).timeout
		NetworkManager.host_return_everyone_to_lobby()
	if not await _wait_until(_returned_to_lobby):
		_fail("dedicated session did not return to its persistent lobby")
		return
	print("DEDICATED_RETURN_PASS %s" % role)
	await get_tree().create_timer(1.0).timeout
	NetworkManager.disconnect_net()
	await get_tree().process_frame
	get_tree().quit(0)


func _match_is_live() -> bool:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != TEST_MAP:
		return false
	var players := scene.get_node_or_null("NetPlayers")
	var manager := scene.get_node_or_null("RoundManager")
	return players != null and players.get_child_count() == 2 \
		and manager != null and bool(manager.get("online_combat_live"))


func _returned_to_lobby() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == "res://game_setup.tscn" \
		and NetworkManager.is_online()


func _verify_client_owned_movement_sync() -> bool:
	var local_actor := NetworkManager.find_actor(NetworkManager.local_actor_id()) as Node3D
	if local_actor == null:
		return false
	var target := Vector3(31.0, local_actor.global_position.y, 17.0) \
		if role == "controller" else Vector3(-31.0, local_actor.global_position.y, -17.0)
	local_actor.global_position = target
	var remote_actor_id := -1
	for peer_id in NetworkManager.participant_peer_ids():
		var candidate_id := NetworkManager.actor_id_for_peer(int(peer_id))
		if candidate_id != NetworkManager.local_actor_id():
			remote_actor_id = candidate_id
			break
	if remote_actor_id < 0:
		return false
	var expected := Vector2(-31.0, -17.0) \
		if role == "controller" else Vector2(31.0, 17.0)
	return await _wait_until(func():
		var remote_actor := NetworkManager.find_actor(remote_actor_id) as Node3D
		return remote_actor != null \
			and Vector2(remote_actor.global_position.x, remote_actor.global_position.z).distance_to(expected) < 1.0)


func _controller_pickup_through_input() -> bool:
	var actor := NetworkManager.find_actor(NetworkManager.local_actor_id()) as Node3D
	var guns := get_tree().get_nodes_in_group("gun")
	if actor == null or guns.is_empty():
		return false
	var gun := guns[0] as Node3D
	actor.global_position = gun.global_position
	if not await _wait_until(func(): return actor.nearby_interactables.has(gun)):
		return false
	await get_tree().create_timer(0.25).timeout
	Input.action_press("p1_interact")
	await get_tree().physics_frame
	Input.action_release("p1_interact")
	return await _wait_until(_controller_gun_is_held)


func _controller_actor_id() -> int:
	return NetworkManager.actor_id_for_peer(NetworkManager.lobby_controller_peer_id)


func _controller_gun():
	var controller_id := _controller_actor_id()
	for gun in get_tree().get_nodes_in_group("gun"):
		var holder = gun.get("player_ref")
		if bool(gun.get("is_held")) and holder != null \
				and int(holder.get("actor_id")) == controller_id:
			return gun
	return null


func _controller_gun_is_held() -> bool:
	return _controller_gun() != null


func _controller_gun_is_reloading() -> bool:
	var gun = _controller_gun()
	return gun != null and not bool(gun.get("can_fire"))


func _controller_gun_is_ready() -> bool:
	var gun = _controller_gun()
	return gun != null and bool(gun.get("can_fire"))


func _controller_gun_is_dropped() -> bool:
	return _controller_gun() == null


func _controller_fire_through_input() -> bool:
	if not _controller_gun_is_ready():
		return false
	Input.action_press("p1_fire")
	await get_tree().physics_frame
	Input.action_release("p1_fire")
	return await _wait_until(_controller_gun_is_reloading)


func _controller_drop_gun() -> bool:
	var gun = _controller_gun()
	if gun == null:
		return false
	gun.request_online_drop()
	return await _wait_until(_controller_gun_is_dropped)


func _controller_actor():
	return NetworkManager.find_actor(_controller_actor_id())


func _loose_online_melee():
	for melee in get_tree().get_nodes_in_group("melee"):
		if bool(melee.get("online_active")) and not bool(melee.get("is_held")) \
				and not bool(melee.get("is_in_flight")) and not bool(melee.get("pickup_locked")):
			return melee
	return null


func _controller_melee():
	var actor = _controller_actor()
	return actor.get("held_melee_weapon") if actor != null else null


func _controller_melee_is_held() -> bool:
	return _controller_melee() != null


func _controller_melee_is_swinging() -> bool:
	var melee = _controller_melee()
	return melee != null and bool(melee.get("is_swinging"))


func _controller_melee_is_ready() -> bool:
	var melee = _controller_melee()
	return melee != null and not bool(melee.get("is_swinging"))


func _controller_melee_is_dropped() -> bool:
	return _controller_melee() == null


func _controller_pickup_melee_through_input() -> bool:
	var actor = _controller_actor() as Node3D
	var melee = _loose_online_melee() as Node3D
	if actor == null or melee == null:
		return false
	actor.global_position = melee.global_position
	if not await _wait_until(func(): return actor.nearby_interactables.has(melee)):
		return false
	Input.action_press("p1_interact")
	await get_tree().physics_frame
	Input.action_release("p1_interact")
	return await _wait_until(_controller_melee_is_held)


func _controller_swing_melee_through_input() -> bool:
	if not _controller_melee_is_ready():
		return false
	Input.action_press("p1_fire")
	await get_tree().physics_frame
	Input.action_release("p1_fire")
	return await _wait_until(_controller_melee_is_swinging)


func _controller_drop_melee() -> bool:
	var melee = _controller_melee()
	if melee == null:
		return false
	melee.request_online_drop()
	return await _wait_until(_controller_melee_is_dropped)


func _loose_online_item():
	for item in get_tree().get_nodes_in_group("online_item"):
		if str(item.get("item_type")) == "smoke_bomb" and bool(item.get("visible")) \
				and not bool(item.get("is_held")) and not bool(item.get("is_in_flight")):
			return item
	return null


func _controller_item():
	var actor = _controller_actor()
	if actor == null:
		return null
	if actor.get("held_item_1") != null:
		return actor.get("held_item_1")
	return actor.get("held_item_2")


func _controller_item_is_held() -> bool:
	return _controller_item() != null


func _controller_item_is_dropped() -> bool:
	return _controller_item() == null


func _controller_item_is_in_flight() -> bool:
	for item in get_tree().get_nodes_in_group("online_item"):
		if int(item.get("online_owner_actor_id")) == _controller_actor_id() \
				and bool(item.get("is_in_flight")):
			return true
	return false


func _controller_pickup_item_through_input() -> bool:
	var actor = _controller_actor() as Node3D
	var item = _loose_online_item() as Node3D
	if actor == null or item == null:
		return false
	actor.global_position = item.global_position
	if not await _wait_until(func(): return actor.nearby_interactables.has(item)):
		return false
	Input.action_press("p1_interact")
	await get_tree().physics_frame
	Input.action_release("p1_interact")
	return await _wait_until(_controller_item_is_held)


func _controller_drop_item() -> bool:
	var item = _controller_item()
	if item == null:
		return false
	item.request_online_drop()
	return await _wait_until(_controller_item_is_dropped)


func _controller_throw_item_through_input() -> bool:
	var actor = _controller_actor()
	var item = _controller_item()
	if actor == null or item == null:
		return false
	actor.active_slot = "item1" if actor.held_item_1 == item else "item2"
	Input.action_press("p1_fire")
	await get_tree().physics_frame
	Input.action_release("p1_fire")
	return await _wait_until(_controller_item_is_in_flight)


func _wait_until(predicate: Callable) -> bool:
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().create_timer(0.05).timeout
	return false


func _fail(message: String) -> void:
	push_error("DEDICATED_SERVER_FAIL %s: %s" % [role, message])
	get_tree().quit(1)
