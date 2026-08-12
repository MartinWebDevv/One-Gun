extends "res://round_manager.gd"

const PLAYPEN_RESPAWN_TIME := 2.0
const PLAYPEN_REFILL_TIME := 2.0
const PLAYPEN_GUNS_PER_BAY := 2
const PLAYPEN_BAY_COUNT := 3
const PLAYPEN_WEAPONS := ["Sword", "Baseball Bat", "Stick", "Crowbar", "Frying Pan"]
const PLAYPEN_ITEMS := [
	"bubble_gum", "grenade", "bear_trap", "spring_pad", "smoke_bomb",
	"decoy", "boomerang", "flash_camera", "double_jump_shoes",
]
const PLAYPEN_POWERUPS := [
	"extra_dash", "sticky_hands", "speed_surge", "silent_steps",
	"vampire_touch", "extra_life", "reach",
]

var _gun_spawn_positions: Dictionary = {}
var _gun_spawn_generations: Dictionary = {}
var _gun_refill_pending: Dictionary = {}
var _practice_respawn_generation: Dictionary = {}
var _armory_materials: Dictionary = {}
var _host_lobby_layer: CanvasLayer
var _status_label: Label


func _ready() -> void:
	_initialize_playpen.call_deferred()


func _initialize_playpen() -> void:
	practice_mode = true
	round_state = "live"
	online_combat_live = true
	online_round_epoch = 1
	online_match_over = false
	online_announcement = ""
	if not NetworkManager.is_online():
		get_tree().call_deferred("change_scene_to_file", "res://game_setup.tscn")
		return
	_build_practice_arena()
	_setup_practice_network()
	_spawn_fixed_armories()
	_build_practice_overlay()
	NetworkManager.playpen_members_changed.connect(_reconcile_playpen_members)
	NetworkManager.lobby_changed.connect(_update_practice_overlay)
	NetworkManager.prelaunch_countdown_changed.connect(_on_prelaunch_changed)
	NetworkManager.server_disconnected.connect(_on_online_host_left)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	NetworkManager.report_playpen_scene_ready.call_deferred()
	if NetworkManager.is_host():
		_reconcile_playpen_members.call_deferred()


func _process(_delta: float) -> void:
	if NetworkManager.is_host() and online_combat_live:
		_monitor_gun_refills()


func get_round_timer_text() -> String:
	return ""


func _setup_practice_network() -> void:
	var root := get_tree().current_scene
	var items := Node3D.new()
	items.name = "OnlineItems"
	root.add_child(items)
	var deployables := Node3D.new()
	deployables.name = "OnlineDeployables"
	root.add_child(deployables)
	var net_players := Node3D.new()
	net_players.name = "NetPlayers"
	root.add_child(net_players)
	_player_spawner = MultiplayerSpawner.new()
	_player_spawner.name = "PlayerSpawner"
	_player_spawner.spawn_path = NodePath("../NetPlayers")
	_player_spawner.spawn_function = Callable(self, "_net_spawn_player")
	root.add_child(_player_spawner)
	_build_online_hud(root)
	_online_hud.set("practice_mode", true)


func _reconcile_playpen_members() -> void:
	if not NetworkManager.is_host() or _player_spawner == null:
		return
	var active_ids := NetworkManager.playpen_peer_ids()
	var net_players := get_tree().current_scene.get_node_or_null("NetPlayers")
	if net_players == null:
		return
	for actor in net_players.get_children():
		var owner_peer_id := int(actor.get("owner_peer_id"))
		if not active_ids.has(owner_peer_id):
			online_actor_state.erase(int(actor.get("actor_id")))
			actor.queue_free()
	for peer_id_value in active_ids:
		var peer_id := int(peer_id_value)
		var actor_id := NetworkManager.actor_id_for_peer(peer_id)
		var existing := NetworkManager.find_actor(actor_id)
		if existing == null:
			var spawn_transform := _practice_spawn_transform(actor_id)
			var entry: Dictionary = NetworkManager.peers.get(peer_id, {})
			_player_spawner.spawn({
				"kind": "human",
				"id": actor_id,
				"owner_peer_id": peer_id,
				"team_id": int(entry.get("team_id", -1)),
				"skin_id": str(entry.get("skin_id", PlayerSkinRegistry.DEFAULT_SKIN_ID)),
				"name": str(entry.get("name", "Player")),
				"pos": spawn_transform.origin,
				"yaw": spawn_transform.basis.get_euler().y,
			})
			online_actor_state[actor_id] = _practice_actor_entry(actor_id, peer_id)
		server_set_peer_actor_visibility(peer_id, true)
	await get_tree().process_frame
	_broadcast_online_state()
	_update_practice_overlay()


func _practice_actor_entry(actor_id: int, peer_id: int) -> Dictionary:
	var peer_entry: Dictionary = NetworkManager.peers.get(peer_id, {})
	return {
		"actor_id": actor_id,
		"owner_peer_id": peer_id,
		"name": str(peer_entry.get("name", "Player")),
		"team_id": int(peer_entry.get("team_id", -1)),
		"alive": true,
		"rounds": 0,
		"sets": 0,
		"kills": 0,
		"deaths": 0,
		"pickups": 0,
		"disarms": 0,
		"melee": 0,
		"round_kills": 0,
		"storm_time": 0.0,
		"eliminated_at_ms": -1,
		"hearts": 0,
	}


func _practice_spawn_transform(actor_id: int) -> Transform3D:
	var markers := get_tree().get_nodes_in_group("spawn_point")
	if markers.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var index := posmod(actor_id * 3 + int(Time.get_ticks_msec() / 1000), markers.size())
	var marker := markers[index] as Node3D
	return marker.global_transform


func server_eliminate(victim_id: int, killer_id: int, epoch: int = -1,
		weapon_icon: String = "GUN", feedback_kind: String = "gun",
		lethal_kind: String = "weapon") -> void:
	if not can_accept_online_combat(epoch):
		return
	if not online_actor_state.has(victim_id) 			or not bool(online_actor_state[victim_id].get("alive", false)):
		return
	var victim = NetworkManager.find_actor(victim_id)
	if lethal_kind == "weapon" and victim != null 			and float(victim.get("lethal_immunity_timer")) > 0.0:
		server_confirm_hit(killer_id, false, feedback_kind)
		return
	if lethal_kind == "weapon" and victim != null 			and bool(victim.get("second_wind_ready")):
		NetworkManager.broadcast_match_rpc(
			self, &"_net_consume_online_second_wind", [victim_id])
		server_confirm_hit(killer_id, false, feedback_kind)
		return
	var entry: Dictionary = online_actor_state[victim_id]
	entry["alive"] = false
	entry["deaths"] = int(entry.get("deaths", 0)) + 1
	entry["eliminated_at_ms"] = Time.get_ticks_msec()
	online_actor_state[victim_id] = entry
	if killer_id != victim_id and online_actor_state.has(killer_id):
		var killer_entry: Dictionary = online_actor_state[killer_id]
		killer_entry["kills"] = int(killer_entry.get("kills", 0)) + 1
		online_actor_state[killer_id] = killer_entry
	NetworkManager.broadcast_match_rpc(
		self, &"_net_eliminate", [victim_id, killer_id, weapon_icon, lethal_kind])
	if killer_id != victim_id:
		server_confirm_hit(killer_id, true, feedback_kind)
	_broadcast_online_state()
	var generation := int(_practice_respawn_generation.get(victim_id, 0)) + 1
	_practice_respawn_generation[victim_id] = generation
	_respawn_practice_actor(victim_id, generation)


func _respawn_practice_actor(actor_id: int, generation: int) -> void:
	await get_tree().create_timer(PLAYPEN_RESPAWN_TIME).timeout
	if not NetworkManager.is_host() 			or generation != int(_practice_respawn_generation.get(actor_id, 0)):
		return
	if not online_actor_state.has(actor_id):
		return
	var owner_peer_id := int(online_actor_state[actor_id].get("owner_peer_id", -1))
	if not NetworkManager.is_peer_in_playpen(owner_peer_id):
		return
	var entry: Dictionary = online_actor_state[actor_id]
	entry["alive"] = true
	entry["eliminated_at_ms"] = -1
	online_actor_state[actor_id] = entry
	var spawn_transform := _practice_spawn_transform(actor_id)
	NetworkManager.broadcast_match_rpc(self, &"_net_respawn", [
		actor_id, spawn_transform.origin, spawn_transform.basis.get_euler().y])
	_broadcast_online_state()


func server_schedule_online_melee_refill(melee, epoch: int) -> void:
	if not can_accept_online_combat(epoch) or melee == null 			or bool(melee.get("marker_refill_requested")):
		return
	melee.marker_refill_requested = true
	var weapon_name := str(melee.get_meta(
		"playpen_weapon_name", melee.weapon_data.weapon_name))
	_refill_playpen_melee(
		melee.spawn_position, melee.spawn_rotation, weapon_name, epoch)


func _refill_playpen_melee(position: Vector3, rotation_value: Vector3,

		weapon_name: String, epoch: int) -> void:
	await get_tree().create_timer(PLAYPEN_REFILL_TIME).timeout
	if not can_accept_online_combat(epoch):
		return
	var candidate_id := _next_online_melee_candidate_id
	_next_online_melee_candidate_id += 1
	NetworkManager.broadcast_match_rpc(self, &"_net_spawn_online_melee_refill", [{
		"candidate_id": candidate_id,
		"position": position,
		"rotation": rotation_value,
		"identity": {
			"weapon_name": weapon_name,
			"effect": "normal",
			"tier": 3,
		},
		"pickup_locked": false,
		"overtime_supply": false,
		"playpen_weapon_name": weapon_name,
	}])



func server_schedule_playpen_melee_cleanup(melee) -> void:
	if not NetworkManager.is_host() or melee == null:
		return
	var generation := int(melee.get_meta("playpen_cleanup_generation", 0)) + 1
	melee.set_meta("playpen_cleanup_generation", generation)
	await get_tree().create_timer(PLAYPEN_REFILL_TIME).timeout
	if not NetworkManager.is_host() or not is_instance_valid(melee) \
			or generation != int(melee.get_meta("playpen_cleanup_generation", 0)):
		return
	if bool(melee.get("is_held")) or bool(melee.get("is_in_flight")):
		return
	broadcast_online_melee_action(int(melee.get("online_candidate_id")), "retire")


func _spawn_online_melee(assignment: Dictionary) -> void:
	super._spawn_online_melee(assignment)
	var melee = _online_melee_by_id(int(assignment.get("candidate_id", -1)))
	if melee != null:
		melee.set_meta("playpen_weapon_name", str(
			assignment.get("playpen_weapon_name",
				assignment.get("identity", {}).get("weapon_name", "Sword"))))


func server_schedule_online_item_refill(item, epoch: int) -> void:
	if not can_accept_online_combat(epoch) or item == null 			or bool(item.get("marker_refill_requested")):
		return
	item.marker_refill_requested = true
	_refill_playpen_item(
		item.spawn_position, item.spawn_rotation, int(item.online_spawn_id),
		str(item.item_type), epoch)


func _refill_playpen_item(position: Vector3, rotation_value: Vector3,
		spawn_id: int, item_type: String, epoch: int) -> void:
	await get_tree().create_timer(PLAYPEN_REFILL_TIME).timeout
	if not can_accept_online_combat(epoch):
		return
	var item_id := _next_online_item_id
	_next_online_item_id += 1
	NetworkManager.broadcast_match_rpc(self, &"_net_spawn_online_item_refill", [{
		"item_id": item_id,
		"spawn_id": spawn_id,
		"item_type": item_type,
		"position": position,
		"rotation": rotation_value,
	}])


func server_collect_online_powerup(powerup_id: int, actor_id: int, epoch: int) -> void:
	if not can_accept_online_combat(epoch):
		return
	var powerup = _online_powerup(powerup_id)
	var actor = NetworkManager.find_actor(actor_id)
	if powerup == null or actor == null or powerup.collected or actor.is_eliminated:
		return
	var max_distance := GameConfig.REACH_POWERUP_DISTANCE 		if actor.has_method("has_active_reach") and actor.has_active_reach() else 3.0
	if actor.global_position.distance_to(powerup.global_position) > max_distance:
		return
	var collected_type := str(powerup.power_type)
	if actor.has_method("can_collect_powerup") 			and not actor.can_collect_powerup(collected_type):
		return
	NetworkManager.broadcast_match_rpc(
		self, &"_net_collect_online_powerup", [powerup_id, actor_id, collected_type])
	_respawn_playpen_powerup(powerup_id, collected_type, epoch)


func _respawn_playpen_powerup(powerup_id: int, power_type: String, epoch: int) -> void:
	await get_tree().create_timer(PLAYPEN_REFILL_TIME).timeout
	if not can_accept_online_combat(epoch):
		return
	var powerup = _online_powerup(powerup_id)
	if powerup == null or not powerup.collected:
		return
	NetworkManager.broadcast_match_rpc(
		self, &"_net_respawn_online_powerup", [powerup_id, power_type])


func _spawn_fixed_armories() -> void:
	_next_online_melee_candidate_id = 10000
	_next_online_item_id = 20000
	var bay_centers := [-25.0, 0.0, 25.0]
	for bay in PLAYPEN_BAY_COUNT:
		var center_x: float = bay_centers[bay]
		var slot := 0
		for gun_index in PLAYPEN_GUNS_PER_BAY:
			var gun_spawn_id := bay * PLAYPEN_GUNS_PER_BAY + gun_index
			var gun_position := _armory_slot_position(center_x, slot)
			_gun_spawn_positions[gun_spawn_id] = gun_position
			_gun_spawn_generations[gun_spawn_id] = 0
			_spawn_playpen_gun(gun_spawn_id, 0, gun_position)
			_add_slot_label("GUN", gun_position, Color(1.0, 0.72, 0.12))
			slot += 1
		for weapon_index in PLAYPEN_WEAPONS.size():
			var weapon_name: String = PLAYPEN_WEAPONS[weapon_index]
			var weapon_position := _armory_slot_position(center_x, slot)
			var candidate_id := bay * 100 + weapon_index
			_spawn_online_melee({
				"candidate_id": candidate_id,
				"position": weapon_position,
				"rotation": Vector3.ZERO,
				"identity": {
					"weapon_name": weapon_name,
					"effect": "normal",
					"tier": 3,
				},
				"pickup_locked": false,
				"playpen_weapon_name": weapon_name,
			})
			_add_slot_label(weapon_name.to_upper(), weapon_position, Color(0.2, 0.9, 1.0))
			slot += 1
		for item_index in PLAYPEN_ITEMS.size():
			var item_type: String = PLAYPEN_ITEMS[item_index]
			var item_position := _armory_slot_position(center_x, slot)
			var item_id := bay * 100 + item_index
			_spawn_online_item({
				"item_id": item_id,
				"spawn_id": item_id,
				"item_type": item_type,
				"position": item_position,
				"rotation": Vector3.ZERO,
			})
			_add_slot_label(item_type.replace("_", " ").to_upper(),
				item_position, Color(0.65, 0.35, 1.0))
			slot += 1
		for power_index in PLAYPEN_POWERUPS.size():
			var power_type: String = PLAYPEN_POWERUPS[power_index]
			var power_position := _armory_slot_position(center_x, slot)
			var powerup_id := bay * 100 + power_index
			_spawn_online_powerup({
				"powerup_id": powerup_id,
				"power_type": power_type,
				"position": power_position,
				"rotation": Vector3.ZERO,
			})
			_add_slot_label(power_type.replace("_", " ").to_upper(),
				power_position, Color(0.25, 1.0, 0.5))
			slot += 1


func _armory_slot_position(center_x: float, slot: int) -> Vector3:
	var column := slot % 8
	var row := slot / 8
	return Vector3(center_x + (column - 3.5) * 2.35, 0.72, -18.0 + row * 3.15)


func _spawn_playpen_gun(spawn_id: int, generation: int, position: Vector3) -> void:
	var gun = GunScene.instantiate()
	gun.name = "PlaypenGun%d_%d" % [spawn_id, generation]
	gun.playpen_spawn_id = spawn_id
	get_tree().current_scene.add_child(gun)
	gun.global_position = position
	gun.spawn_position = position


@rpc("authority", "reliable", "call_local")
func _net_spawn_playpen_gun(spawn_id: int, generation: int, position: Vector3) -> void:
	_spawn_playpen_gun(spawn_id, generation, position)


func _monitor_gun_refills() -> void:
	for spawn_id_value in _gun_spawn_positions:
		var spawn_id := int(spawn_id_value)
		if _has_loose_playpen_gun(spawn_id) 				or bool(_gun_refill_pending.get(spawn_id, false)):
			continue
		_gun_refill_pending[spawn_id] = true
		_refill_playpen_gun(spawn_id)


func _has_loose_playpen_gun(spawn_id: int) -> bool:
	for gun in get_tree().get_nodes_in_group("gun"):
		if int(gun.get("playpen_spawn_id")) == spawn_id 				and not bool(gun.get("is_held")) 				and gun.visible:
			return true
	return false


func _refill_playpen_gun(spawn_id: int) -> void:
	await get_tree().create_timer(PLAYPEN_REFILL_TIME).timeout
	_gun_refill_pending[spawn_id] = false
	if not NetworkManager.is_host() or not online_combat_live 			or _has_loose_playpen_gun(spawn_id):
		return
	var generation := int(_gun_spawn_generations.get(spawn_id, 0)) + 1
	_gun_spawn_generations[spawn_id] = generation
	NetworkManager.broadcast_match_rpc(self, &"_net_spawn_playpen_gun", [
		spawn_id, generation, _gun_spawn_positions[spawn_id]])


func server_schedule_playpen_gun_cleanup(gun) -> void:
	if not NetworkManager.is_host() or gun == null:
		return
	var generation := int(gun.get_meta("playpen_cleanup_generation", 0)) + 1
	gun.set_meta("playpen_cleanup_generation", generation)
	await get_tree().create_timer(PLAYPEN_REFILL_TIME).timeout
	if not NetworkManager.is_host() or not is_instance_valid(gun) \
			or generation != int(gun.get_meta("playpen_cleanup_generation", 0)) \
			or bool(gun.get("is_held")):
		return
	var spawn_id := int(gun.get("playpen_spawn_id"))
	var instance_name := str(gun.name)
	var has_replacement := false
	for candidate in get_tree().get_nodes_in_group("gun"):
		if candidate != gun and int(candidate.get("playpen_spawn_id")) == spawn_id \
				and not bool(candidate.get("is_held")) and candidate.visible:
			has_replacement = true
			break
	NetworkManager.broadcast_match_rpc(
		self, &"_net_retire_playpen_gun", [instance_name])
	if not has_replacement and _gun_spawn_positions.has(spawn_id):
		_gun_refill_pending[spawn_id] = false
		var next_generation := int(_gun_spawn_generations.get(spawn_id, 0)) + 1
		_gun_spawn_generations[spawn_id] = next_generation
		NetworkManager.broadcast_match_rpc(self, &"_net_spawn_playpen_gun", [
			spawn_id, next_generation, _gun_spawn_positions[spawn_id]])


@rpc("authority", "reliable", "call_local")
func _net_retire_playpen_gun(instance_name: String) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var gun := root.get_node_or_null(NodePath(instance_name))
	if gun != null and not bool(gun.get("is_held")):
		gun.queue_free()


func _build_practice_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PlaypenControls"
	layer.layer = 80
	get_tree().current_scene.add_child(layer)
	var title := Label.new()
	title.text = "THE PLAYPEN"
	title.position = Vector2(24, 18)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.25, 0.95, 1.0))
	layer.add_child(title)
	_status_label = Label.new()
	_status_label.position = Vector2(26, 55)
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	layer.add_child(_status_label)
func _update_practice_overlay() -> void:
	if _status_label == null:
		return
	var count := NetworkManager.playpen_peer_ids().size()
	_status_label.text = "NO SCORE  •  INFINITE RESPAWNS  •  %d PLAYER%s HERE" % [
		count, "" if count == 1 else "S"]
func _on_prelaunch_changed(active: bool, seconds: int) -> void:
	if active and _status_label != null:
		_status_label.text = "PULLING EVERYONE INTO THE MATCH..."


func show_host_lobby_overlay() -> void:
	if not NetworkManager.is_host() or _host_lobby_layer != null:
		return
	PauseManager.reset_pause_state()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_host_lobby_layer = CanvasLayer.new()
	_host_lobby_layer.name = "HostLobbyOverlay"
	_host_lobby_layer.layer = 150
	get_tree().current_scene.add_child(_host_lobby_layer)
	var lobby := load("res://game_setup.tscn").instantiate() as Control
	if lobby == null:
		_host_lobby_layer.queue_free()
		_host_lobby_layer = null
		return
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host_lobby_layer.add_child(lobby)


func restore_host_to_playpen() -> void:
	if _host_lobby_layer != null:
		_host_lobby_layer.queue_free()
		_host_lobby_layer = null
	PauseManager.reset_pause_state()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_reconcile_playpen_members.call_deferred()


func _add_slot_label(text: String, world_position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = world_position + Vector3(0.0, 1.3, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 24
	label.outline_size = 8
	label.modulate = color
	get_tree().current_scene.add_child(label)


func _build_practice_arena() -> void:
	var root := get_tree().current_scene
	var environment_node := WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.028, 0.045, 0.11)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.34, 0.46, 0.78)
	environment.ambient_light_energy = 1.25
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment_node.environment = environment
	root.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_color = Color(0.45, 0.58, 1.0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	root.add_child(light)
	for light_position in [
			Vector3(-26, 8, -12), Vector3(0, 8, -12), Vector3(26, 8, -12),
			Vector3(-26, 8, 16), Vector3(0, 8, 16), Vector3(26, 8, 16)]:
		_add_omni_light(root, light_position,
			Color(0.22, 0.72, 1.0) if light_position.z < 0.0 else Color(0.82, 0.3, 1.0))
	_add_box(root, "ArenaFloor", Vector3(0, -0.6, 0), Vector3(82, 1.2, 58),
		Color(0.075, 0.1, 0.2), true)
	_add_box(root, "NorthWall", Vector3(0, 5.5, -29), Vector3(82, 12, 1),
		Color(0.05, 0.07, 0.16), true)
	_add_box(root, "SouthWall", Vector3(0, 5.5, 29), Vector3(82, 12, 1),
		Color(0.05, 0.07, 0.16), true)
	_add_box(root, "WestWall", Vector3(-41, 5.5, 0), Vector3(1, 12, 58),
		Color(0.05, 0.07, 0.16), true)
	_add_box(root, "EastWall", Vector3(41, 5.5, 0), Vector3(1, 12, 58),
		Color(0.05, 0.07, 0.16), true)
	for stripe in 17:
		_add_box(root, "GridX%d" % stripe,
			Vector3(-40 + stripe * 5.0, 0.025, 0), Vector3(0.045, 0.025, 56),
			Color(0.05, 0.6, 0.95), false, 2.8)
	for stripe in 12:
		_add_box(root, "GridZ%d" % stripe,
			Vector3(0, 0.03, -27.5 + stripe * 5.0), Vector3(80, 0.025, 0.045),
			Color(0.55, 0.12, 0.95), false, 2.4)
	for x in [-30.0, -15.0, 0.0, 15.0, 30.0]:
		_add_box(root, "CoverA%s" % x, Vector3(x, 1.1, 6), Vector3(4.5, 2.2, 2.0),
			Color(0.08, 0.1, 0.22), true)
	for x in [-23.0, -7.5, 7.5, 23.0]:
		_add_box(root, "CoverB%s" % x, Vector3(x, 1.6, 17), Vector3(2.2, 3.2, 5.0),
			Color(0.07, 0.08, 0.2), true)
	for bay in PLAYPEN_BAY_COUNT:
		var bay_x: float = float([-25.0, 0.0, 25.0][bay])
		_add_box(root, "BayHeader%d" % bay, Vector3(bay_x, 4.7, -22.7),
			Vector3(21.5, 0.32, 0.35), Color(1.0, 0.35, 0.08), false, 4.0)
		var bay_label := Label3D.new()
		bay_label.text = "ARMORY BAY %d" % (bay + 1)
		bay_label.position = Vector3(bay_x, 5.25, -22.3)
		bay_label.font_size = 56
		bay_label.outline_size = 12
		bay_label.modulate = Color(1.0, 0.72, 0.2)
		root.add_child(bay_label)
	var center_pad := MeshInstance3D.new()
	center_pad.name = "WarpPad"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 7.0
	cylinder.bottom_radius = 7.0
	cylinder.height = 0.25
	center_pad.mesh = cylinder
	center_pad.position = Vector3(0, 0.13, 12)
	center_pad.material_override = _material(Color(0.04, 0.12, 0.3),
		Color(0.12, 0.75, 1.0), 3.5)
	root.add_child(center_pad)
	var warp_label := Label3D.new()
	warp_label.text = "WARP CORE"
	warp_label.position = Vector3(0, 0.32, 12)
	warp_label.rotation_degrees.x = -90
	warp_label.font_size = 64
	warp_label.modulate = Color(0.2, 0.92, 1.0)
	root.add_child(warp_label)
	for i in 10:
		var angle := TAU * float(i) / 10.0
		var marker := Node3D.new()
		marker.name = "SpawnPoint%d" % i
		marker.position = Vector3(cos(angle) * 11.0, 0.65, 12 + sin(angle) * 11.0)
		marker.rotation.y = -angle + PI * 0.5
		marker.add_to_group("spawn_point", true)
		root.add_child(marker)


func _add_omni_light(parent: Node, position: Vector3, color: Color) -> void:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = 3.2
	light.omni_range = 20.0
	light.shadow_enabled = false
	parent.add_child(light)


func _add_box(parent: Node, node_name: String, position: Vector3, size: Vector3,
		color: Color, collidable: bool, emission_energy := 0.0) -> void:
	var holder: Node3D
	if collidable:
		var body := StaticBody3D.new()
		holder = body
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
	else:
		holder = Node3D.new()
	holder.name = node_name
	holder.position = position
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = _material(
		color, color if emission_energy > 0.0 else Color.BLACK, emission_energy)
	holder.add_child(mesh_instance)
	parent.add_child(holder)


func _material(color: Color, emission: Color = Color.BLACK,
		emission_energy := 0.0) -> StandardMaterial3D:
	var key := "%s:%s:%s" % [color, emission, emission_energy]
	if _armory_materials.has(key):
		return _armory_materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.18
	material.roughness = 0.62
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy * 0.45
	_armory_materials[key] = material
	return material
