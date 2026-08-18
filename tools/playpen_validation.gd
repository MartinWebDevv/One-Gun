extends Node

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("PLAYPEN VALIDATION: " + message)


func _has_action_id(node: Node, action_id: String) -> bool:
	if str(node.get_meta("action_id", "")) == action_id:
		return true
	for child in node.get_children():
		if _has_action_id(child, action_id):
			return true
	return false


func _combined_world_mesh_bounds(root_node: Node) -> AABB:
	var combined := AABB()
	var found := false
	for candidate in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var world_bounds := mesh_instance.global_transform * mesh_instance.get_aabb()
		combined = world_bounds if not found else combined.merge(world_bounds)
		found = true
	return combined



func _run() -> void:
	var network = get_node("/root/NetworkManager")
	var validation_port := 26000 + int(OS.get_process_id() % 2000)
	var hosted: bool = network.host_game(validation_port, "Playpen Validation", {
		"privacy": "private",
		"max_players": 4,
	})
	_check(hosted, "Could not create local validation host")
	if not hosted:
		get_tree().quit(1)
		return
	await get_tree().process_frame
	reparent(network)
	network.pending_map_path = "res://maps/test/CityMap.tscn"
	network.request_enter_playpen()
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var scene := get_tree().current_scene
		if scene != null and scene.name == "Playpen" 				and scene.get_node_or_null("NetPlayers/NP1") != null:
			break
		await get_tree().process_frame
	await get_tree().create_timer(0.75).timeout
	var playpen := get_tree().current_scene
	_check(playpen != null and playpen.name == "Playpen",
		"The Playpen scene did not load")
	if playpen != null and playpen.name == "Playpen":
		var manager = playpen.get_node_or_null("RoundManager")
		_check(manager != null, "RoundManager practice subclass is missing")
		if manager != null:
			_check(bool(manager.get("practice_mode")),
				"RoundManager did not enter practice mode")
			_check(bool(manager.get("online_combat_live")),
				"Practice combat did not become live")
		_check(playpen.get_node_or_null("NetPlayers/NP1") != null,
			"Host practice actor did not spawn")
		_check(get_tree().get_nodes_in_group("spawn_point").size() == 10,
			"Expected ten Playpen player spawn points")
		var playpen_guns := get_tree().get_nodes_in_group("gun").filter(func(gun):
			return int(gun.get("playpen_spawn_id")) >= 0)
		_check(playpen_guns.size() == 6,
			"Expected exactly two initial guns in each of three armory bays")
		_check(get_tree().get_nodes_in_group("melee").size() == 15,
			"Expected all five melee weapons in every armory bay")
		_check(get_tree().get_nodes_in_group("online_item").size() == 27,
			"Expected all nine items in every armory bay")
		_check(get_tree().get_nodes_in_group("online_powerup").size() == 21,
			"Expected all seven powerups in every armory bay")
		var host_actor = playpen.get_node_or_null("NetPlayers/NP1")
		if host_actor != null:
			_check(is_zero_approx(host_actor.rotation.y),
				"Playpen human body kept spawn yaw and would double-rotate WASD")
			host_actor.activate_double_jump_shoes()
			for _frame in 3:
				await get_tree().process_frame
			var shoes: Array = host_actor.get("_double_jump_shoe_attachments")
			_check(shoes.size() == 2,
				"Playpen Double Jump Shoes did not attach to both animated feet")
			for shoe in shoes:
				var bounds := _combined_world_mesh_bounds(shoe)
				_check(bounds.size.length() > 0.05,
					"Playpen Spring Shoe has no visible runtime mesh bounds")
				_check(bounds.size.length() < 1.25,
					"Playpen Spring Shoe rendered at an oversized world scale")
				var socket := shoe.get_parent() as Node3D
				_check(socket != null and bounds.get_center().distance_to(
						socket.global_position) < 0.6,
					"Playpen Spring Shoe rendered away from its animated foot socket")
			host_actor.clear_double_jump_shoes()
		var pause_menu = playpen.get_node_or_null("OnlineHUD/PauseMenu")
		_check(pause_menu != null, "Playpen pause menu was not created")
		if pause_menu != null:
			pause_menu.call("_build_ui")
			await get_tree().process_frame
			_check(_has_action_id(pause_menu, "leave_playpen"),
				"Playpen pause menu is missing Leave Playpen")
			_check(_has_action_id(pause_menu, "start_match"),
				"Host Playpen pause menu is missing Start/Force Start Match")
			_check(not _has_action_id(pause_menu, "return_lobby") \
				and not _has_action_id(pause_menu, "leave_match"),
				"Normal-match exit actions leaked into the Playpen pause menu")
		if manager != null and host_actor != null:
			var actor_id := int(host_actor.get("actor_id"))
			if not playpen_guns.is_empty():
				var far_bay_gun = playpen_guns[-1]
				var saved_actor_transform: Transform3D = host_actor.global_transform
				host_actor.global_position = far_bay_gun.global_position
				manager._server_route_online_gun_action(actor_id, "pickup",
					int(manager.get("online_round_epoch")), Vector3.ZERO,
					str(far_bay_gun.name))
				await get_tree().process_frame
				_check(bool(far_bay_gun.get("is_held"))
					and far_bay_gun.get("player_ref") == host_actor,
					"Playpen rejected the exact gun touched outside the first armory bay")
				if bool(far_bay_gun.get("is_held")):
					far_bay_gun._net_do_drop(saved_actor_transform.origin + Vector3.UP)
				host_actor.global_transform = saved_actor_transform
			var loose_melee = get_tree().get_nodes_in_group("melee").filter(func(melee):
				return not bool(melee.get("is_held")))
			if not loose_melee.is_empty():
				var dropped_melee = loose_melee[0]
				dropped_melee._net_do_pickup(actor_id)
				dropped_melee._net_do_drop(host_actor.global_position + Vector3.UP)
				await get_tree().create_timer(2.15).timeout
				_check(not is_instance_valid(dropped_melee),
					"Dropped Playpen melee weapon did not despawn after two seconds")
			var loose_items = get_tree().get_nodes_in_group("online_item").filter(func(item):
				return not bool(item.get("is_held")) and item.visible)
			if not loose_items.is_empty():
				var dropped_item = loose_items[0]
				dropped_item._net_do_pickup(actor_id)
				dropped_item._net_do_drop(host_actor.global_position + Vector3.UP)
				await get_tree().create_timer(2.15).timeout
				_check(not is_instance_valid(dropped_item),
					"Dropped Playpen item did not despawn after two seconds")
		network.request_leave_playpen()
		await get_tree().create_timer(0.35).timeout
		_check(network.local_match_role == "playpen_hosting",
			"Host did not independently return to the lobby role")
		_check(network.is_playpen_open(),
			"Playpen closed when the host independently left")
		_check(playpen.get_node_or_null("NetPlayers/NP1") == null,
			"Host actor remained in Playpen after leaving")
		_check(manager != null and manager.get("_host_lobby_layer") != null,
			"Host lobby UI did not open over the authoritative Playpen scene")
		var host_lobby_layer = manager.get("_host_lobby_layer") \
			if manager != null else null
		var host_lobby = host_lobby_layer.get_child(0) \
			if host_lobby_layer != null and host_lobby_layer.get_child_count() > 0 \
			else null
		_check(host_lobby != null,
			"Host lobby overlay did not contain the lobby controls")
		if host_lobby != null:
			var modal_layer = host_lobby.get("_settings_layer")
			_check(modal_layer is CanvasLayer \
				and modal_layer.layer > host_lobby_layer.layer,
				"Host lobby modal layer rendered behind the Playpen lobby overlay")
			for property_name in ["_match_settings_button",
					"_character_customization_button", "_player_settings_button",
					"_playpen_button", "_back_button"]:
				var lobby_button = host_lobby.get(property_name)
				_check(lobby_button is BaseButton and not lobby_button.disabled,
					"Host lobby button remained disabled after leaving The Playpen: %s" \
					% property_name)
			var settings_button = host_lobby.get("_match_settings_button")
			settings_button.emit_signal("pressed")
			await get_tree().process_frame
			_check(host_lobby.get("_settings_slideout") != null,
				"Host lobby Settings button did not open its panel after Playpen exit")
			host_lobby.call("_discard_settings_slideout_immediately")
			await get_tree().process_frame
			var customization_button = host_lobby.get("_character_customization_button")
			customization_button.emit_signal("pressed")
			await get_tree().process_frame
			var customization = host_lobby.get("_character_customization_overlay")
			_check(customization != null and customization.get_parent() == modal_layer,
				"Host lobby Character Customization button did not open above Playpen")
			if customization != null:
				customization.call("_cancel")
				await get_tree().process_frame
			var player_settings_button = host_lobby.get("_player_settings_button")
			player_settings_button.emit_signal("pressed")
			await get_tree().process_frame
			var player_settings = host_lobby.get("_player_settings_overlay")
			_check(player_settings != null and player_settings.get_parent() == modal_layer,
				"Host lobby Player Settings button did not open above Playpen")
			if player_settings != null:
				player_settings.call("request_cancel_close")
				await get_tree().process_frame
			var playpen_button = host_lobby.get("_playpen_button")
			var ready_before_entry := bool(network.peers[1].get("ready", false))
			playpen_button.emit_signal("pressed")
			var entry_dialogs: Array[Node] = host_lobby.find_children(
				"*", "ConfirmationDialog", true, false)
			var visible_entry_dialog := false
			for dialog in entry_dialogs:
				visible_entry_dialog = visible_entry_dialog or dialog.visible
			_check(not visible_entry_dialog,
				"Host lobby Playpen entry still opened a Ready prompt")
			_check(bool(network.peers[1].get("ready", false)) == ready_before_entry,
				"Entering Playpen changed the player's lobby Ready state")
			await get_tree().process_frame
		var reentry_deadline := Time.get_ticks_msec() + 3000
		while playpen.get_node_or_null("NetPlayers/NP1") == null \
				and Time.get_ticks_msec() < reentry_deadline:
			await get_tree().process_frame
		_check(network.local_match_role == "playpen" \
			and playpen.get_node_or_null("NetPlayers/NP1") != null,
			"Host could not independently re-enter the running Playpen")
		_check(network.playpen_peer_ids() == [1],
			"Host Playpen membership was not synchronized")
		# Repeat the same transition in one live host session. The reported bug
		# was intermittent and only appeared after a Playpen round trip, so a
		# fresh-process smoke test alone cannot cover it.
		for repeat_cycle in 2:
			network.request_leave_playpen()
			await get_tree().create_timer(0.35).timeout
			var repeat_layer = manager.get("_host_lobby_layer") \
				if manager != null else null
			var repeat_lobby = repeat_layer.get_child(0) \
				if repeat_layer != null and repeat_layer.get_child_count() > 0 \
				else null
			_check(repeat_lobby != null,
				"Repeated Playpen exit did not restore the host lobby (%d)" \
				% (repeat_cycle + 2))
			if repeat_lobby != null:
				var repeat_modal = repeat_lobby.get("_settings_layer")
				_check(repeat_modal is CanvasLayer \
					and repeat_modal.layer > repeat_layer.layer,
					"Repeated host lobby modal layer was hidden behind Playpen")
				var repeat_settings = repeat_lobby.get("_match_settings_button")
				_check(repeat_settings is BaseButton and not repeat_settings.disabled,
					"Repeated host lobby Settings button was disabled")
				repeat_settings.emit_signal("pressed")
				await get_tree().process_frame
				_check(repeat_lobby.get("_settings_slideout") != null,
					"Repeated host lobby Settings click did nothing")
				repeat_lobby.call("_discard_settings_slideout_immediately")
			network.request_enter_playpen()
			var repeat_deadline := Time.get_ticks_msec() + 3000
			while playpen.get_node_or_null("NetPlayers/NP1") == null \
					and Time.get_ticks_msec() < repeat_deadline:
				await get_tree().process_frame
			_check(playpen.get_node_or_null("NetPlayers/NP1") != null,
				"Host could not re-enter Playpen after repeated lobby test")

		var capture_path := OS.get_environment("ONEGUN_PLAYPEN_CAPTURE")
		if capture_path != "":
			var capture_camera := Camera3D.new()
			capture_camera.name = "ValidationCamera"
			playpen.add_child(capture_camera)
			capture_camera.global_position = Vector3(0.0, 19.0, 34.0)
			capture_camera.look_at(Vector3(0.0, 1.0, -9.0), Vector3.UP)
			capture_camera.make_current()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var save_error := image.save_png(capture_path)
			_check(save_error == OK, "Could not save Playpen visual capture")
	if failures.is_empty():
		print("PLAYPEN VALIDATION PASSED")
	network.disconnect_net()
	get_tree().quit(0 if failures.is_empty() else 1)
