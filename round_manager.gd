extends Node

@export var countdown_time := 3
@export var round_end_display_time := 3
@export var set_end_display_time := 4
@export var match_end_display_time := 6

const MAX_TOTAL_PLAYERS := 8
const MAX_BOTS_SOLO := 7
const MAX_BOTS_SPLIT := 6
const ONLINE_BOT_ACTOR_ID_BASE := 10000
const ONLINE_POWERUP_TYPES := ["extra_dash", "extra_melee_shield", "speed_surge", "silent_steps", "vampire_touch", "second_wind", "magnet_hands"]

const DummyScene = preload("res://DummyModel.tscn")

var players = []
var spawn_transforms = {}
var round_state = "countdown"
var round_number = 1
var set_number = 1

var round_wins = {}
var match_points = {}
var previous_alive = []

# -- Match stats (accumulate across all rounds, reset when match ends) --
var stat_kills    := {}
var stat_deaths   := {}
var stat_disarms  := {}
var stat_pickups  := {}
var stat_melee    := {}

func _leave_match_to(scene_path: String):
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManager.stop_music(0.5)
	get_tree().change_scene_to_file(scene_path)

# ============================================================
# ONLINE Phases 1-2d. Strips the baked local players/HUD/splitscreen, spawns
# one networked character per connected peer via MultiplayerSpawner, and runs
# host-authoritative gun/melee combat plus the round/set/match state machine.
# Everything here is gated behind NetworkManager.is_online(); local play is
# completely untouched. No map .tscn files are edited (runtime strip only).
# ============================================================
var _player_spawner: MultiplayerSpawner = null
var online_round_epoch := 1
var online_combat_live := false
var online_actor_state: Dictionary = {}
var online_announcement := "LOADING..."
var online_match_over := false
var _online_transitioning := false
var _online_hud = null
var _next_online_deployed_id := 1

func _setup_online_freeroam() -> void:
	var root := get_tree().current_scene
	# Free the baked local players + local HUD nodes (online = one view per
	# machine). Runtime strip only — no map .tscn is edited.
	for n in ["player1", "player2", "SplitScreenLayer", "CanvasLayer"]:
		var node = root.get_node_or_null(n)
		if node:
			node.free()
	# Preserve every authored melee placement and assign stable IDs before any
	# weapon is reparented. The host rolls an independent identity for every
	# placement each round, matching local map behavior.
	var online_melee := get_tree().get_nodes_in_group("melee")
	online_melee.sort_custom(func(a, b): return str(a.get_path()) < str(b.get_path()))
	for i in online_melee.size():
		online_melee[i].online_candidate_id = i
		online_melee[i].set_online_active(false)
	# Remove legacy baked pickup instances, but preserve every authored marker.
	# Phase 2d respawns synchronized pickups from those markers on each peer.
	for group_name in ["item", "powerup", "deployed_trap"]:
		for obj in get_tree().get_nodes_in_group(group_name):
			obj.free()
	for container_name in ["OnlineItems", "OnlineDeployables"]:
		var container := Node3D.new()
		container.name = container_name
		root.add_child(container)
	var net_players := Node3D.new()
	net_players.name = "NetPlayers"
	root.add_child(net_players)
	_player_spawner = MultiplayerSpawner.new()
	_player_spawner.name = "PlayerSpawner"
	# Relative path is valid before the spawner enters the tree; assigning the
	# NetPlayers absolute path here made MultiplayerSpawner resolve it while it
	# was still outside the active scene tree.
	_player_spawner.spawn_path = NodePath("../NetPlayers")
	_player_spawner.spawn_function = Callable(self, "_net_spawn_player")
	root.add_child(_player_spawner)
	_build_online_hud(root)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not NetworkManager.server_disconnected.is_connected(_on_online_host_left):
		NetworkManager.server_disconnected.connect(_on_online_host_left)
	NetworkManager.report_match_scene_ready()
	if NetworkManager.is_host():
		# Wait for every connected peer to build the identical spawner path.
		# A readiness signal also fires on disconnect, so setup cannot remain
		# stuck waiting for a peer that left during the scene transition.
		while not NetworkManager.are_all_match_peers_ready():
			await NetworkManager.match_readiness_changed
		var markers := get_tree().get_nodes_in_group("spawn_point")
		var ids := NetworkManager.peer_ids_sorted()
		for i in ids.size():
			var m = markers[i % max(markers.size(), 1)] if markers.size() > 0 else null
			var pos := Vector3.ZERO
			var yaw := 0.0
			if m != null:
				pos = m.position
				yaw = m.rotation.y
			_player_spawner.spawn({"kind": "human", "id": ids[i], "pos": pos, "yaw": yaw})
		var available_bot_slots := maxi(MAX_TOTAL_PLAYERS - ids.size(), 0)
		var online_bot_count := mini(GameConfig.bot_configs.size(), available_bot_slots)
		for i in online_bot_count:
			var marker_index := ids.size() + i
			var m = markers[marker_index % max(markers.size(), 1)] if markers.size() > 0 else null
			var pos: Vector3 = m.position if m != null else Vector3.ZERO
			var yaw: float = m.rotation.y if m != null else 0.0
			var config: Dictionary = GameConfig.bot_configs[i]
			_player_spawner.spawn({
				"kind": "bot",
				"id": ONLINE_BOT_ACTOR_ID_BASE + i,
				"owner_peer_id": 1,
				"name": "Bot %d" % (i + 1),
				"difficulty": str(config.get("difficulty", "easy")),
				"team_id": int(config.get("team_id", -1)),
				"pos": pos,
				"yaw": yaw,
			})
		await get_tree().process_frame
		_initialize_online_match()
		_online_start_round()

func _build_online_hud(root: Node) -> void:
	_online_hud = load("res://online_hud.gd").new()
	_online_hud.name = "OnlineHUD"
	root.add_child(_online_hud)

# Runs on host AND every client (via the spawner) with identical data, so
# authority + starting transform are consistent everywhere.
func _net_spawn_player(data: Dictionary) -> Node:
	var actor_spawn_id := int(data["id"])
	if str(data.get("kind", "human")) == "bot":
		var bot = DummyScene.instantiate()
		bot.name = "NB%d" % actor_spawn_id
		bot.position = data["pos"]
		bot.rotation.y = data["yaw"]
		bot.set("is_online", true)
		bot.set("net_authority_id", 1)
		bot.set("actor_id", actor_spawn_id)
		bot.set("owner_peer_id", int(data.get("owner_peer_id", 1)))
		bot.set("online_display_name", str(data.get("name", "Bot")))
		bot.set("ai_difficulty", str(data.get("difficulty", "easy")))
		bot.set("team_id", int(data.get("team_id", -1)))
		bot.set_multiplayer_authority(1)
		return bot
	var peer_id := actor_spawn_id
	var p = preload("res://player.tscn").instantiate()
	p.name = "NP%d" % peer_id
	p.position = data["pos"]
	p.rotation.y = data["yaw"]
	p.set("is_online", true)
	p.set("net_authority_id", peer_id)
	p.set("actor_id", peer_id)
	p.set("owner_peer_id", peer_id)
	p.set_multiplayer_authority(peer_id)
	return p

func can_accept_online_combat(epoch: int) -> bool:
	return (
		NetworkManager.is_online()
		and multiplayer.is_server()
		and online_combat_live
		and epoch == online_round_epoch
	)

func _online_melee_weapon():
	var weapons := get_tree().get_nodes_in_group("melee")
	for weapon in weapons:
		if bool(weapon.get("online_active")):
			return weapon
	return null

func _online_melee_by_id(candidate_id: int):
	for weapon in get_tree().get_nodes_in_group("melee"):
		if int(weapon.get("online_candidate_id")) == candidate_id:
			return weapon
	return null

func _online_melee_candidates() -> Array:
	var weapons := get_tree().get_nodes_in_group("melee")
	weapons.sort_custom(func(a, b): return int(a.get("online_candidate_id")) < int(b.get("online_candidate_id")))
	return weapons

func _online_item(item_id: int):
	for item in get_tree().get_nodes_in_group("online_item"):
		if int(item.get("online_item_id")) == item_id:
			return item
	return null

func _online_powerup(powerup_id: int):
	for powerup in get_tree().get_nodes_in_group("online_powerup"):
		if int(powerup.get("online_powerup_id")) == powerup_id:
			return powerup
	return null

func _online_deployed(deployed_id: int):
	for deployed in get_tree().get_nodes_in_group("online_deployed"):
		if int(deployed.get_meta("online_deployed_id", -1)) == deployed_id:
			return deployed
	return null

func _sorted_online_markers(group_name: String) -> Array:
	var markers := get_tree().get_nodes_in_group(group_name)
	markers.sort_custom(func(a, b): return str(a.get_path()) < str(b.get_path()))
	return markers

func _enabled_online_item_types() -> Array:
	var enabled: Array = []
	for item_type in GameConfig.ITEM_SCENES:
		if GameConfig.is_item_enabled(item_type):
			enabled.append(str(item_type))
	return enabled

func _random_online_item_type() -> String:
	var enabled := _enabled_online_item_types()
	return str(enabled[randi() % enabled.size()]) if not enabled.is_empty() else ""

func _build_online_item_assignments() -> Array:
	var assignments: Array = []
	var enabled := _enabled_online_item_types()
	if enabled.is_empty():
		return assignments
	var markers := _sorted_online_markers("item_spawn_point")
	for i in markers.size():
		var marker = markers[i]
		assignments.append({
			"item_id": i,
			"spawn_id": i,
			"item_type": str(enabled[randi() % enabled.size()]),
			"position": marker.global_position,
			"rotation": marker.global_rotation,
		})
	return assignments

func _build_online_powerup_assignments() -> Array:
	var assignments: Array = []
	var markers := _sorted_online_markers("powerup_spawn_point")
	for i in markers.size():
		var marker = markers[i]
		assignments.append({
			"powerup_id": i,
			"power_type": str(ONLINE_POWERUP_TYPES[randi() % ONLINE_POWERUP_TYPES.size()]),
			"position": marker.global_position,
			"rotation": marker.global_rotation,
		})
	return assignments

# Melee is reparented between the map and a player's hand. Route its network
# messages through this stable RoundManager path so RPC delivery never depends
# on which parent the weapon currently has on a given peer.
func request_online_melee_action(candidate_id: int, action: String, epoch: int) -> void:
	if NetworkManager.is_host():
		_server_route_online_melee_action(NetworkManager.local_id(), candidate_id, action, epoch)
	else:
		_net_request_online_melee_action.rpc_id(1, candidate_id, action, epoch)

@rpc("any_peer", "reliable")
func _net_request_online_melee_action(candidate_id: int, action: String, epoch: int) -> void:
	_server_route_online_melee_action(multiplayer.get_remote_sender_id(), candidate_id, action, epoch)

func _server_route_online_melee_action(sender_id: int, candidate_id: int, action: String, epoch: int) -> void:
	if not multiplayer.is_server():
		return
	var melee = _online_melee_by_id(candidate_id)
	if melee == null:
		return
	match action:
		"pickup": melee._server_try_pickup(sender_id, epoch)
		"swing": melee._server_try_swing(sender_id, epoch)
		"drop": melee._server_try_drop(sender_id, epoch)
		"throw": melee._server_try_throw(sender_id, epoch)

func broadcast_online_melee_action(candidate_id: int, action: String, data: Dictionary = {}) -> void:
	if multiplayer.is_server():
		_net_apply_online_melee_action.rpc(candidate_id, action, data)

@rpc("authority", "reliable", "call_local")
func _net_apply_online_melee_action(candidate_id: int, action: String, data: Dictionary) -> void:
	var melee = _online_melee_by_id(candidate_id)
	if melee == null:
		return
	match action:
		"pickup": melee._net_do_pickup(int(data.get("holder_actor_id", -1)))
		"swing": melee._net_do_swing(int(data.get("deficit_count", 0)), bool(data.get("should_break", false)))
		"drop": melee._net_do_drop(data.get("position", Vector3.ZERO))
		"throw": melee._net_do_throw(data.get("position", Vector3.ZERO), data.get("rotation", Vector3.ZERO), data.get("velocity", Vector3.ZERO))
		"land": melee._net_land_throw(data.get("position", Vector3.ZERO), data.get("rotation", Vector3.ZERO))
		"despawn_reset": melee._net_reset_existing_identity()
		"hit":
			melee._net_apply_melee_hit(
				int(data.get("target_id", -1)),
				int(data.get("attacker_id", -1)),
				bool(data.get("meaningful_hit", false)),
				bool(data.get("did_disarm", false)),
				bool(data.get("shield_consumed", false)),
				bool(data.get("is_thrown", false)),
				bool(data.get("will_eliminate", false)),
				data.get("source_position", Vector3.ZERO)
			)

# Items are also reparented while held, so requests and broadcasts use this
# stable coordinator rather than RPCs on the moving item nodes themselves.
func request_online_item_action(item_id: int, action: String, epoch: int, direction: Vector3 = Vector3.ZERO) -> void:
	if NetworkManager.is_host():
		_server_route_online_item_action(NetworkManager.local_id(), item_id, action, epoch, direction)
	else:
		_net_request_online_item_action.rpc_id(1, item_id, action, epoch, direction)

@rpc("any_peer", "reliable")
func _net_request_online_item_action(item_id: int, action: String, epoch: int, direction: Vector3) -> void:
	_server_route_online_item_action(multiplayer.get_remote_sender_id(), item_id, action, epoch, direction)

func _server_route_online_item_action(sender_id: int, item_id: int, action: String, epoch: int, direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var item = _online_item(item_id)
	if item == null:
		return
	match action:
		"pickup": item._server_try_pickup(sender_id, epoch)
		"drop": item._server_try_drop(sender_id, epoch)
		"throw": item._server_try_throw(sender_id, epoch, direction)

func broadcast_online_item_action(item_id: int, action: String, data: Dictionary = {}) -> void:
	if multiplayer.is_server():
		_net_apply_online_item_action.rpc(item_id, action, data)

# Magnet pulls stream position nudges at 10 Hz per player; keep them off the
# reliable ordered channel so they can't queue behind (or delay) combat RPCs.
# A dropped move packet is harmless — the next tick supersedes it.
func broadcast_online_item_move(item_id: int, position: Vector3) -> void:
	if multiplayer.is_server():
		_net_apply_online_item_move.rpc(item_id, position)

@rpc("authority", "unreliable_ordered", "call_local")
func _net_apply_online_item_move(item_id: int, position: Vector3) -> void:
	var item = _online_item(item_id)
	if item != null:
		item._net_set_loose_position(position)

@rpc("authority", "reliable", "call_local")
func _net_apply_online_item_action(item_id: int, action: String, data: Dictionary) -> void:
	var item = _online_item(item_id)
	if item == null:
		return
	match action:
		"pickup": item._net_do_pickup(int(data.get("holder_actor_id", -1)))
		"drop": item._net_do_drop(data.get("position", Vector3.ZERO))
		"throw": item._net_do_throw(
			data.get("position", Vector3.ZERO),
			data.get("rotation", Vector3.ZERO),
			data.get("velocity", Vector3.ZERO),
			data.get("direction", Vector3.FORWARD),
			int(data.get("owner_actor_id", -1))
		)
		"return": item._net_return_to_spawn(data.get("position", Vector3.ZERO), data.get("rotation", Vector3.ZERO))
		"deploy": item._net_do_deploy(
			data.get("position", Vector3.ZERO),
			int(data.get("deployed_id", -1)),
			int(data.get("owner_actor_id", -1))
		)
		"consume": item._net_consume()

func server_deploy_online_item(item_id: int, position: Vector3, owner_actor_id: int, respawn_delay: float, epoch: int) -> void:
	if not can_accept_online_combat(epoch):
		return
	var item = _online_item(item_id)
	if item == null or item.is_held or not item.visible:
		return
	var deployed_id := _next_online_deployed_id
	_next_online_deployed_id += 1
	broadcast_online_item_action(item_id, "deploy", {
		"position": position,
		"deployed_id": deployed_id,
		"owner_actor_id": owner_actor_id,
	})
	_schedule_online_item_respawn(item_id, respawn_delay, epoch)

func server_consume_online_item(item_id: int, respawn_delay: float, epoch: int) -> void:
	if not can_accept_online_combat(epoch):
		return
	broadcast_online_item_action(item_id, "consume")
	_schedule_online_item_respawn(item_id, respawn_delay, epoch)

func _schedule_online_item_respawn(item_id: int, delay: float, epoch: int) -> void:
	await get_tree().create_timer(delay).timeout
	if not NetworkManager.is_host() or epoch != online_round_epoch or online_match_over:
		return
	var item = _online_item(item_id)
	if item == null or item.is_held or item.is_in_flight or item.visible:
		return
	var replacement_type := _random_online_item_type()
	if replacement_type == "":
		return
	_net_replace_online_item.rpc(item_id, replacement_type, item.spawn_position, item.spawn_rotation, int(item.online_spawn_id))

@rpc("authority", "reliable", "call_local")
func _net_replace_online_item(item_id: int, item_type: String, position: Vector3, rotation: Vector3, spawn_id: int) -> void:
	var old_item = _online_item(item_id)
	if old_item != null:
		if old_item.is_held and old_item.player_ref != null:
			old_item.player_ref.clear_item_slot(old_item)
		old_item.free()
	_spawn_online_item({
		"item_id": item_id,
		"spawn_id": spawn_id,
		"item_type": item_type,
		"position": position,
		"rotation": rotation,
	})

func server_collect_online_powerup(powerup_id: int, actor_id: int, epoch: int) -> void:
	if not can_accept_online_combat(epoch):
		return
	var powerup = _online_powerup(powerup_id)
	var actor = NetworkManager.find_actor(actor_id)
	if powerup == null or actor == null or powerup.collected or actor.is_eliminated:
		return
	if actor.global_position.distance_to(powerup.global_position) > 3.0:
		return
	var collected_type := str(powerup.power_type)
	_net_collect_online_powerup.rpc(powerup_id, actor_id, collected_type)
	if collected_type == "magnet_hands":
		_schedule_online_magnet_expiry(actor_id, powerup.effect_duration, epoch)
	_schedule_online_powerup_respawn(powerup_id, powerup.respawn_time, epoch)

@rpc("authority", "reliable", "call_local")
func _net_collect_online_powerup(powerup_id: int, actor_id: int, power_type: String) -> void:
	var powerup = _online_powerup(powerup_id)
	if powerup != null:
		powerup._net_collect(actor_id, power_type)

func _schedule_online_powerup_respawn(powerup_id: int, delay: float, epoch: int) -> void:
	await get_tree().create_timer(delay).timeout
	if not NetworkManager.is_host() or epoch != online_round_epoch or online_match_over:
		return
	var powerup = _online_powerup(powerup_id)
	if powerup == null or not powerup.collected:
		return
	var new_type := str(ONLINE_POWERUP_TYPES[randi() % ONLINE_POWERUP_TYPES.size()])
	_net_respawn_online_powerup.rpc(powerup_id, new_type)

@rpc("authority", "reliable", "call_local")
func _net_respawn_online_powerup(powerup_id: int, power_type: String) -> void:
	var powerup = _online_powerup(powerup_id)
	if powerup != null:
		powerup._net_respawn(power_type)

func _schedule_online_magnet_expiry(actor_id: int, duration: float, epoch: int) -> void:
	await get_tree().create_timer(duration).timeout
	if NetworkManager.is_host() and epoch == online_round_epoch:
		_net_clear_online_magnet.rpc(actor_id)

@rpc("authority", "reliable", "call_local")
func _net_clear_online_magnet(actor_id: int) -> void:
	var actor = NetworkManager.find_actor(actor_id)
	if actor != null:
		actor.magnet_timer = 0.0
		actor.active_powerup_order.erase("magnet_hands")

func request_online_magnet_pull(actor_id: int) -> void:
	if NetworkManager.is_host():
		_server_online_magnet_pull(NetworkManager.local_id(), actor_id)
	else:
		_net_request_online_magnet_pull.rpc_id(1, actor_id)

@rpc("any_peer", "unreliable")
func _net_request_online_magnet_pull(actor_id: int) -> void:
	_server_online_magnet_pull(multiplayer.get_remote_sender_id(), actor_id)

func _server_online_magnet_pull(sender_id: int, actor_id: int) -> void:
	if not multiplayer.is_server() or not online_combat_live:
		return
	var actor = NetworkManager.find_actor(actor_id)
	if actor == null or int(actor.owner_peer_id) != sender_id or actor.magnet_timer <= 0.0:
		return
	for item in get_tree().get_nodes_in_group("online_item"):
		if item.is_held or item.is_in_flight or not item.visible:
			continue
		var to_actor: Vector3 = actor.global_position + Vector3(0.0, 0.4, 0.0) - item.global_position
		if to_actor.length() <= 1.1 or to_actor.length() > 4.0:
			continue
		var new_position: Vector3 = item.global_position + to_actor.normalized() * 6.0 * 0.1
		broadcast_online_item_move(int(item.online_item_id), new_position)

func server_apply_online_item_effect(effect: String, target_id: int, data: Dictionary = {}) -> void:
	if not NetworkManager.is_host() or not online_combat_live:
		return
	if not online_actor_state.has(target_id) or not bool(online_actor_state[target_id].get("alive", false)):
		return
	_net_apply_online_item_effect.rpc(effect, target_id, data)

@rpc("authority", "reliable", "call_local")
func _net_apply_online_item_effect(effect: String, target_id: int, data: Dictionary) -> void:
	var target = NetworkManager.find_actor(target_id)
	if target == null or target.is_eliminated:
		return
	match effect:
		"slow": target.apply_slow(float(data.get("duration", 2.0)), float(data.get("multiplier", 0.5)))
		"stagger": target.apply_stagger(float(data.get("duration", 1.5)))
		"knockback": target.apply_knockback(data.get("direction", Vector3.FORWARD), float(data.get("distance", 3.0)))
		"launch": target.velocity.y = float(data.get("velocity", 11.0))
		"immunity": target.grant_bullet_immunity(float(data.get("duration", 1.0)))

func server_online_radial_knockback(position: Vector3, owner_actor_id: int, radius: float, distance: float) -> void:
	if not NetworkManager.is_host() or not online_combat_live:
		return
	var owner = NetworkManager.find_actor(owner_actor_id)
	for actor_id in online_actor_state:
		var target = NetworkManager.find_actor(int(actor_id))
		if target == null or target.is_eliminated or target.global_position.distance_to(position) > radius:
			continue
		if not GameConfig.can_affect(owner, target):
			continue
		var direction: Vector3 = target.global_position - position
		direction.y = 0.0
		if direction.length() < 0.01:
			direction = Vector3.FORWARD
		server_apply_online_item_effect("knockback", int(actor_id), {"direction": direction.normalized(), "distance": distance})

func broadcast_online_deployed_action(deployed_id: int, action: String, data: Dictionary = {}) -> void:
	if multiplayer.is_server():
		_net_apply_online_deployed_action.rpc(deployed_id, action, data)

@rpc("authority", "reliable", "call_local")
func _net_apply_online_deployed_action(deployed_id: int, action: String, data: Dictionary) -> void:
	var deployed = _online_deployed(deployed_id)
	if deployed != null and deployed.has_method("apply_online_action"):
		deployed.apply_online_action(action, data)

func server_online_boomerang_hit(item_id: int, owner_actor_id: int, target_id: int, epoch: int) -> void:
	if not can_accept_online_combat(epoch):
		return
	var item = _online_item(item_id)
	var owner = NetworkManager.find_actor(owner_actor_id)
	var target = NetworkManager.find_actor(target_id)
	if item == null or owner == null or target == null or target == owner or not GameConfig.can_affect(owner, target):
		return
	if target.holding_gun:
		if target.melee_disarm_shields > 0:
			_net_consume_online_shield.rpc(target_id)
		else:
			var gun = get_tree().get_nodes_in_group("gun")[0] if not get_tree().get_nodes_in_group("gun").is_empty() else null
			if gun != null and gun.is_held and gun.player_ref == target:
				gun.net_force_disarm()
				server_record_online_melee_hit(owner_actor_id, false, true)
			server_apply_online_item_effect("immunity", target_id, {"duration": 1.0})
	else:
		var direction: Vector3 = target.global_position - owner.global_position
		direction.y = 0.0
		server_apply_online_item_effect("knockback", target_id, {"direction": direction.normalized(), "distance": 3.0})
	server_consume_online_item(item_id, float(item.respawn_after_deploy_time), epoch)

@rpc("authority", "reliable", "call_local")
func _net_consume_online_shield(actor_id: int) -> void:
	var actor = NetworkManager.find_actor(actor_id)
	if actor != null:
		actor.melee_disarm_shields = maxi(actor.melee_disarm_shields - 1, 0)

@rpc("authority", "reliable", "call_local")
func _net_set_online_combat(enabled: bool, epoch: int) -> void:
	online_round_epoch = epoch
	online_combat_live = enabled
	round_state = "live" if enabled else "countdown"

func _initialize_online_match() -> void:
	if not NetworkManager.is_host():
		return
	players = get_tree().current_scene.get_node("NetPlayers").get_children()
	round_number = 1
	set_number = 1
	online_round_epoch = 1
	online_match_over = false
	online_actor_state.clear()
	for p in players:
		var id := int(p.actor_id)
		online_actor_state[id] = {
			"actor_id": id,
			"owner_peer_id": int(p.owner_peer_id),
			"name": p.get_display_name(),
			"alive": true,
			"rounds": 0,
			"sets": 0,
			"kills": 0,
			"deaths": 0,
			"pickups": 0,
			"disarms": 0,
			"melee": 0,
		}
	if not GameEvents.gun_picked_up.is_connected(_on_online_gun_picked_up):
		GameEvents.gun_picked_up.connect(_on_online_gun_picked_up)
	if not NetworkManager.lobby_changed.is_connected(_on_online_roster_changed):
		NetworkManager.lobby_changed.connect(_on_online_roster_changed)
	if not NetworkManager.server_disconnected.is_connected(_on_online_host_left):
		NetworkManager.server_disconnected.connect(_on_online_host_left)
	_broadcast_online_state()

func _online_start_round() -> void:
	if not NetworkManager.is_host() or online_match_over:
		return
	_online_transitioning = true
	_net_set_online_combat.rpc(false, online_round_epoch)
	online_announcement = "NEW ROUND"
	var assignments := _build_online_spawn_assignments()
	var melee_candidates := _online_melee_candidates()
	var melee_assignments: Array = []
	for melee in melee_candidates:
		melee_assignments.append({
			"candidate_id": int(melee.online_candidate_id),
			"identity": MeleeWeaponRegistry.get_random_identity(),
		})
	var item_assignments := _build_online_item_assignments()
	var powerup_assignments := _build_online_powerup_assignments()
	_net_reset_online_round.rpc(assignments, melee_assignments, item_assignments, powerup_assignments)
	_online_unlock_melee_after_delay(online_round_epoch)
	for actor_id in online_actor_state:
		var entry: Dictionary = online_actor_state[actor_id]
		entry["alive"] = true
		online_actor_state[actor_id] = entry
	_broadcast_online_state()
	for count in range(countdown_time, 0, -1):
		online_announcement = str(count)
		_broadcast_online_state()
		await get_tree().create_timer(1.0).timeout
	online_announcement = "GO!"
	_net_set_online_combat.rpc(true, online_round_epoch)
	_net_set_online_players_enabled.rpc(true)
	_broadcast_online_state()
	_online_transitioning = false
	await get_tree().create_timer(0.7).timeout
	if online_combat_live and not online_match_over:
		online_announcement = ""
		_broadcast_online_state()

func _build_online_spawn_assignments() -> Array:
	var markers := get_tree().get_nodes_in_group("spawn_point")
	markers.shuffle()
	var assignments: Array = []
	var actor_ids := online_actor_state.keys()
	actor_ids.sort()
	for i in actor_ids.size():
		var actor = NetworkManager.find_actor(int(actor_ids[i]))
		var pos = actor.global_position if actor != null else Vector3.ZERO
		var yaw := 0.0
		if not markers.is_empty():
			var marker = markers[i % markers.size()]
			pos = marker.global_position
			yaw = marker.global_rotation.y
		assignments.append({"actor_id": int(actor_ids[i]), "pos": pos, "yaw": yaw})
	return assignments

@rpc("authority", "reliable", "call_local")
func _net_reset_online_round(assignments: Array, melee_assignments: Array, item_assignments: Array, powerup_assignments: Array) -> void:
	for bullet in get_tree().get_nodes_in_group("online_bullet"):
		bullet.queue_free()
	for group_name in ["online_item", "online_powerup", "online_deployed"]:
		for node in get_tree().get_nodes_in_group(group_name):
			node.free()
	for gun in get_tree().get_nodes_in_group("gun"):
		gun.reset_to_spawn()
	for melee in _online_melee_candidates():
		melee.reset_to_spawn(false)
		melee.set_online_active(true)
		for melee_assignment in melee_assignments:
			if int(melee_assignment.get("candidate_id", -1)) == int(melee.online_candidate_id):
				melee.apply_network_identity(melee_assignment.get("identity", {}))
				break
		melee.set_online_pickup_locked(GameConfig.melee_spawn_delay > 0.0)
	for item_assignment in item_assignments:
		_spawn_online_item(item_assignment)
	for powerup_assignment in powerup_assignments:
		_spawn_online_powerup(powerup_assignment)
	for assignment in assignments:
		var actor = NetworkManager.find_actor(int(assignment["actor_id"]))
		if actor != null:
			actor.respawn(Transform3D(Basis(Vector3.UP, float(assignment["yaw"])), assignment["pos"]))
	_net_set_online_players_enabled(false)

func _spawn_online_item(assignment: Dictionary) -> void:
	var item_type := str(assignment.get("item_type", ""))
	if not GameConfig.ITEM_SCENES.has(item_type):
		return
	var scene = load(GameConfig.ITEM_SCENES[item_type])
	if scene == null:
		return
	var item = scene.instantiate()
	item.name = "OnlineItem%d" % int(assignment.get("item_id", -1))
	item.online_item_id = int(assignment.get("item_id", -1))
	item.online_spawn_id = int(assignment.get("spawn_id", -1))
	item.add_to_group("online_item", true)
	var container = get_tree().current_scene.get_node_or_null("OnlineItems")
	if container == null:
		container = get_tree().current_scene
	container.add_child(item)
	item.global_position = assignment.get("position", Vector3.ZERO)
	item.global_rotation = assignment.get("rotation", Vector3.ZERO)
	item.spawn_position = item.global_position
	item.spawn_rotation = item.global_rotation
	item.reroll_on_respawn = true

func _spawn_online_powerup(assignment: Dictionary) -> void:
	var powerup = load("res://powerup.tscn").instantiate()
	powerup.name = "OnlinePowerup%d" % int(assignment.get("powerup_id", -1))
	powerup.online_powerup_id = int(assignment.get("powerup_id", -1))
	powerup.power_type = str(assignment.get("power_type", "extra_dash"))
	powerup.add_to_group("online_powerup", true)
	var container = get_tree().current_scene.get_node_or_null("OnlineItems")
	if container == null:
		container = get_tree().current_scene
	container.add_child(powerup)
	powerup.global_position = assignment.get("position", Vector3.ZERO)
	powerup.global_rotation = assignment.get("rotation", Vector3.ZERO)
	powerup.spawn_position = powerup.global_position
	powerup.base_y = powerup.position.y

func _online_unlock_melee_after_delay(epoch: int) -> void:
	if not NetworkManager.is_host() or GameConfig.melee_spawn_delay <= 0.0:
		return
	await get_tree().create_timer(GameConfig.melee_spawn_delay).timeout
	if epoch == online_round_epoch and not online_match_over:
		_net_set_online_melee_locked.rpc(false)

@rpc("authority", "reliable", "call_local")
func _net_set_online_melee_locked(value: bool) -> void:
	for melee in get_tree().get_nodes_in_group("melee"):
		if melee.has_method("set_online_pickup_locked"):
			melee.set_online_pickup_locked(value)

@rpc("authority", "reliable", "call_local")
func _net_set_online_players_enabled(enabled: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var net_players := scene.get_node_or_null("NetPlayers")
	if net_players == null:
		return
	for p in net_players.get_children():
		p.velocity = Vector3.ZERO
		p.set_physics_process(enabled and not p.is_eliminated)

func _broadcast_online_state() -> void:
	if not NetworkManager.is_host():
		return
	_net_apply_online_state.rpc({
		"phase": round_state,
		"combat_live": online_combat_live,
		"round_epoch": online_round_epoch,
		"round_number": round_number,
		"set_number": set_number,
		"announcement": online_announcement,
		"match_over": online_match_over,
		"actors": online_actor_state.duplicate(true),
	})

@rpc("authority", "reliable", "call_local")
func _net_apply_online_state(snapshot: Dictionary) -> void:
	round_state = str(snapshot.get("phase", "countdown"))
	online_combat_live = bool(snapshot.get("combat_live", false))
	online_round_epoch = int(snapshot.get("round_epoch", 1))
	round_number = int(snapshot.get("round_number", 1))
	set_number = int(snapshot.get("set_number", 1))
	online_announcement = str(snapshot.get("announcement", ""))
	online_match_over = bool(snapshot.get("match_over", false))
	online_actor_state = snapshot.get("actors", {}).duplicate(true)
	if _online_hud != null and _online_hud.has_method("bind_local_player"):
		_online_hud.bind_local_player(NetworkManager.find_net_player(NetworkManager.local_id()))

func _check_online_round_end() -> void:
	if _online_transitioning or not online_combat_live or online_actor_state.size() < 2:
		return
	var alive_ids: Array = []
	for actor_id in online_actor_state:
		var actor = NetworkManager.find_actor(int(actor_id))
		if actor != null and not actor.is_eliminated:
			alive_ids.append(int(actor_id))
	if alive_ids.size() <= 1:
		_online_finish_round(alive_ids[0] if alive_ids.size() == 1 else -1)

func _online_finish_round(winner_id: int) -> void:
	if _online_transitioning or not NetworkManager.is_host():
		return
	_online_transitioning = true
	_net_set_online_combat.rpc(false, online_round_epoch)
	_net_set_online_players_enabled.rpc(false)
	var winner_name := ""
	var won_set := false
	var won_match := false
	if winner_id >= 0 and online_actor_state.has(winner_id):
		var winner: Dictionary = online_actor_state[winner_id]
		winner_name = str(winner["name"])
		winner["rounds"] = int(winner["rounds"]) + 1
		if int(winner["rounds"]) >= GameConfig.rounds_per_set:
			winner["sets"] = int(winner["sets"]) + 1
			won_set = true
			won_match = int(winner["sets"]) >= GameConfig.sets_per_match
		online_actor_state[winner_id] = winner
		_net_play_online_victory.rpc(winner_id)
	else:
		winner_name = "Draw"

	if won_match:
		online_match_over = true
		online_announcement = winner_name + " WINS THE MATCH!"
		round_state = "match_end"
		_broadcast_online_state()
		await get_tree().create_timer(match_end_display_time).timeout
		_net_return_online_lobby.rpc()
		return

	if won_set:
		online_announcement = winner_name + " wins the set!"
		round_state = "set_end"
		_broadcast_online_state()
		await get_tree().create_timer(set_end_display_time).timeout
		for actor_id in online_actor_state:
			var entry: Dictionary = online_actor_state[actor_id]
			entry["rounds"] = 0
			online_actor_state[actor_id] = entry
		set_number += 1
		round_number = 1
	else:
		online_announcement = "Draw!" if winner_id < 0 else winner_name + " wins the round!"
		round_state = "ended"
		_broadcast_online_state()
		await get_tree().create_timer(round_end_display_time).timeout
		round_number += 1

	online_round_epoch += 1
	_online_transitioning = false
	_online_start_round()

@rpc("authority", "reliable", "call_local")
func _net_play_online_victory(actor_id: int) -> void:
	var actor = NetworkManager.find_actor(actor_id)
	if actor != null and actor.has_method("play_victory_dance"):
		actor.play_victory_dance()

@rpc("authority", "reliable", "call_local")
func _net_return_online_lobby() -> void:
	NetworkManager.set_accepting_new_peers(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManager.stop_music(0.5)
	get_tree().change_scene_to_file("res://game_setup.tscn")

func _on_online_roster_changed() -> void:
	if not NetworkManager.is_host() or online_actor_state.is_empty():
		return
	var removed: Array = []
	for actor_id in online_actor_state:
		var owner_id := int(online_actor_state[actor_id].get("owner_peer_id", -1))
		if not NetworkManager.peers.has(owner_id):
			removed.append(int(actor_id))
	for actor_id in removed:
		online_actor_state.erase(actor_id)
		_net_remove_online_actor.rpc(actor_id)
	_broadcast_online_state()

func _on_online_gun_picked_up(_player_name: String) -> void:
	if not NetworkManager.is_host():
		return
	# Attribute by the gun's actual holder, not the emitted display name —
	# two players with the same name would otherwise mis-credit pickups.
	var guns := get_tree().get_nodes_in_group("gun")
	if guns.is_empty():
		return
	var holder = guns[0].player_ref
	if holder == null or not ("actor_id" in holder):
		return
	var actor_id := int(holder.actor_id)
	if not online_actor_state.has(actor_id):
		return
	var entry: Dictionary = online_actor_state[actor_id]
	entry["pickups"] = int(entry.get("pickups", 0)) + 1
	online_actor_state[actor_id] = entry
	_broadcast_online_state()

func server_record_online_melee_hit(attacker_id: int, meaningful_hit: bool, did_disarm: bool) -> void:
	if not NetworkManager.is_host() or not online_actor_state.has(attacker_id):
		return
	var entry: Dictionary = online_actor_state[attacker_id]
	if meaningful_hit:
		entry["melee"] = int(entry.get("melee", 0)) + 1
	if did_disarm:
		entry["disarms"] = int(entry.get("disarms", 0)) + 1
	online_actor_state[attacker_id] = entry
	_broadcast_online_state()

@rpc("authority", "reliable", "call_local")
func _net_remove_online_actor(actor_id: int) -> void:
	var actor = NetworkManager.find_actor(actor_id)
	if actor != null:
		actor.queue_free()

func _on_online_host_left() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")

# ---- online combat: eliminations (host-authoritative) ---------------------
# Death is permanent for the rest of the round: the victim drops the gun and
# goes to spectate — there is NO mid-round respawn. Players only come back at
# the START of the next round (round-start reset is Phase 2b). Round/set/match
# SCORING is Phase 2b; _net_respawn below is the reset hook 2b will call.

func server_eliminate(victim_id: int, killer_id: int, epoch: int = -1, weapon_icon: String = "🔫") -> void:
	if not can_accept_online_combat(epoch):
		return
	if not online_actor_state.has(victim_id) or not bool(online_actor_state[victim_id].get("alive", false)):
		return
	var victim = NetworkManager.find_actor(victim_id)
	if victim != null and bool(victim.get("second_wind_ready")):
		_net_consume_online_second_wind.rpc(victim_id)
		return
	var victim_entry: Dictionary = online_actor_state[victim_id]
	victim_entry["alive"] = false
	victim_entry["deaths"] = int(victim_entry.get("deaths", 0)) + 1
	online_actor_state[victim_id] = victim_entry
	if killer_id != victim_id and online_actor_state.has(killer_id):
		var killer_entry: Dictionary = online_actor_state[killer_id]
		killer_entry["kills"] = int(killer_entry.get("kills", 0)) + 1
		online_actor_state[killer_id] = killer_entry
	_net_eliminate.rpc(victim_id, killer_id, weapon_icon)
	_broadcast_online_state()

@rpc("authority", "reliable", "call_local")
func _net_consume_online_second_wind(actor_id: int) -> void:
	var actor = NetworkManager.find_actor(actor_id)
	if actor == null:
		return
	actor.second_wind_ready = false
	actor.active_powerup_order.erase("second_wind")
	actor.grant_bullet_immunity(2.0)
	actor.flash_hit()

@rpc("authority", "reliable", "call_local")
func _net_eliminate(victim_id: int, killer_id: int, weapon_icon: String) -> void:
	var victim = NetworkManager.find_actor(victim_id)
	if victim == null or victim.get("is_eliminated"):
		return
	var killer_name := ""
	var kp = NetworkManager.find_actor(killer_id)
	if kp != null and kp.has_method("get_display_name"):
		killer_name = kp.get_display_name()
	# The victim's eliminate() drops the gun locally on each peer (online drop
	# is deterministic — see gun.gd), so the gun frees up everywhere at once,
	# and the victim's own machine enters spectate. No respawn until round start.
	victim.eliminate(killer_name, weapon_icon)

# Round-start reset hook (called by Phase 2b scoring, not on death).
@rpc("authority", "reliable", "call_local")
func _net_respawn(victim_id: int, pos: Vector3, yaw: float) -> void:
	var victim = NetworkManager.find_actor(victim_id)
	if victim != null and victim.has_method("respawn"):
		victim.respawn(Transform3D(Basis(Vector3.UP, yaw), pos))

func _ready():
	if NetworkManager.is_online():
		# Defer: the scene tree is still "busy setting up children" during
		# _ready, so we can't free/add nodes yet.
		call_deferred("_setup_online_freeroam")
		return
	_spawn_bots()
	players = get_tree().get_nodes_in_group("player")
	if not GameConfig.split_screen_enabled:
		players = players.filter(func(p): return not ("is_player2" in p and p.is_player2))
	for p in players:
		round_wins[p] = 0
		match_points[p] = 0
		stat_kills[p]   = 0
		stat_deaths[p]  = 0
		stat_disarms[p] = 0
		stat_pickups[p] = 0
		stat_melee[p]   = 0
	_disable_all_players()
	await get_tree().process_frame
	_disable_all_players()
	_assign_spawn_transforms()
	_apply_gun_spawn_mode()
	_spawn_marker_items()
	GameEvents.player_eliminated.connect(_on_stat_eliminated)
	GameEvents.player_disarmed.connect(_on_stat_disarmed)
	GameEvents.gun_picked_up.connect(_on_stat_gun_picked_up)
	GameEvents.melee_hit_landed.connect(_on_stat_melee_hit)
	await get_tree().process_frame
	AudioManager.play_music("game")
	_start_countdown()

func _find_player_by_name(display_name: String):
	for p in players:
		if p.get_display_name() == display_name:
			return p
	return null

func _on_stat_eliminated(victim_name: String, killer_name: String, _icon: String):
	var victim = _find_player_by_name(victim_name)
	if victim != null and stat_deaths.has(victim):
		stat_deaths[victim] += 1
	if killer_name != "":
		var killer = _find_player_by_name(killer_name)
		if killer != null and stat_kills.has(killer):
			stat_kills[killer] += 1

func _on_stat_disarmed(victim_name: String, disarmer_name: String, _icon: String):
	var disarmer = _find_player_by_name(disarmer_name)
	if disarmer != null and stat_disarms.has(disarmer):
		stat_disarms[disarmer] += 1

func _on_stat_gun_picked_up(player_name: String):
	var p = _find_player_by_name(player_name)
	if p != null and stat_pickups.has(p):
		stat_pickups[p] += 1

func _on_stat_melee_hit(hitter_name: String):
	var p = _find_player_by_name(hitter_name)
	if p != null and stat_melee.has(p):
		stat_melee[p] += 1

func get_scoreboard_data() -> Array:
	if NetworkManager.is_online():
		var online_data: Array = []
		for actor_id in online_actor_state:
			var entry: Dictionary = online_actor_state[actor_id]
			online_data.append({
				"name": str(entry.get("name", "Player")),
				"sets": int(entry.get("sets", 0)),
				"rounds": int(entry.get("rounds", 0)),
				"kills": int(entry.get("kills", 0)),
				"deaths": int(entry.get("deaths", 0)),
				"disarms": int(entry.get("disarms", 0)),
				"pickups": int(entry.get("pickups", 0)),
				"melee": int(entry.get("melee", 0)),
				"alive": bool(entry.get("alive", false)),
			})
		online_data.sort_custom(func(a, b):
			if a["sets"] != b["sets"]:
				return a["sets"] > b["sets"]
			if a["rounds"] != b["rounds"]:
				return a["rounds"] > b["rounds"]
			return a["kills"] > b["kills"]
		)
		return online_data
	var data = []
	for p in players:
		data.append({
			"name":    p.get_display_name(),
			"sets":    match_points.get(p, 0),
			"rounds":  round_wins.get(p, 0),
			"kills":   stat_kills.get(p, 0),
			"deaths":  stat_deaths.get(p, 0),
			"disarms": stat_disarms.get(p, 0),
			"pickups": stat_pickups.get(p, 0),
			"melee":   stat_melee.get(p, 0),
			"alive":   not p.is_eliminated,
		})
	data.sort_custom(func(a, b):
		if a["sets"] != b["sets"]:
			return a["sets"] > b["sets"]
		return a["rounds"] > b["rounds"]
	)
	return data

# A spawn marker only defines WHERE (and which way) a player spawns — never
# how big the player is. Copying a marker's full transform used to stamp any
# scale on the marker or its parent (e.g. an accidentally-scaled SpawnPoints
# container) onto the player, non-uniformly stretching the model. This strips
# scale, pitch, and roll, keeping only position + yaw so the player always
# spawns upright and at its own natural scale.
func _clean_spawn_transform(gt: Transform3D) -> Transform3D:
	var yaw = gt.basis.get_euler().y
	return Transform3D(Basis(Vector3.UP, yaw), gt.origin)

func _assign_spawn_transforms():
	var all_spawns = get_tree().get_nodes_in_group("spawn_point")
	if all_spawns.size() == 0:
		push_warning("RoundManager: no spawn_point markers found — all players spawn at their scene positions.")
		for p in players:
			spawn_transforms[p] = _clean_spawn_transform(p.global_transform)
		return

	var shuffled = all_spawns.duplicate()
	shuffled.shuffle()
	var used_indices = []

	var human_players = players.filter(func(p): return not ("is_bot" in p and p.is_bot))
	for i in human_players.size():
		var idx = i % shuffled.size()
		spawn_transforms[human_players[i]] = _clean_spawn_transform(shuffled[idx].global_transform)
		used_indices.append(idx)
		human_players[i].global_transform = spawn_transforms[human_players[i]]

	var bot_players = players.filter(func(p): return "is_bot" in p and p.is_bot)
	var next_idx = human_players.size()
	for bot in bot_players:
		var idx = next_idx % shuffled.size()
		spawn_transforms[bot] = _clean_spawn_transform(shuffled[idx].global_transform)
		bot.global_transform = spawn_transforms[bot]
		next_idx += 1

func _spawn_bots():
	var human_count = 2 if GameConfig.split_screen_enabled else 1
	var max_bots = MAX_BOTS_SPLIT if GameConfig.split_screen_enabled else MAX_BOTS_SOLO
	var bot_count = clamp(GameConfig.bot_configs.size(), 0, min(max_bots, MAX_TOTAL_PLAYERS - human_count))

	if bot_count == 0:
		return

	for i in range(bot_count):
		var bot = DummyScene.instantiate()
		bot.name = "Bot" + str(i + 1)
		var config = GameConfig.bot_configs[i]
		bot.ai_difficulty = config.get("difficulty", "easy")
		bot.team_id = config.get("team_id", -1)
		add_child(bot)

func _disable_all_players():
	for p in players:
		if is_instance_valid(p):
			p.set_physics_process(false)

func _enable_all_players():
	for p in players:
		if is_instance_valid(p) and not p.is_eliminated:
			p.set_physics_process(true)

func _set_round_label_text(text):
	get_node("../CanvasLayer/RoundLabel").text = text
	get_node("../CanvasLayer/RoundLabel2").text = text

func _start_countdown():
	round_state = "countdown"
	for m in get_tree().get_nodes_in_group("melee"):
		if m.has_method("randomize_attributes"):
			m.randomize_attributes()
	_apply_melee_spawn_delay()
	previous_alive = players.duplicate()
	_update_status_label()
	GameEvents.hud_notification.emit("NEW ROUND STARTING")
	for i in range(countdown_time, 0, -1):
		_set_round_label_text(str(i))
		await get_tree().create_timer(1.0).timeout
	_set_round_label_text("GO!")
	round_state = "live"
	_enable_all_players()
	await get_tree().create_timer(0.5).timeout
	_set_round_label_text("")

func _apply_melee_spawn_delay():
	var melee_weapons = get_tree().get_nodes_in_group("melee")
	if GameConfig.melee_spawn_delay <= 0.0:
		for m in melee_weapons:
			m.pickup_locked = false
		return
	for m in melee_weapons:
		m.pickup_locked = true
	await get_tree().create_timer(GameConfig.melee_spawn_delay).timeout
	for m in melee_weapons:
		if is_instance_valid(m):
			m.pickup_locked = false

func _process(_delta):
	if NetworkManager.is_online():
		if NetworkManager.is_host():
			_check_online_round_end()
		return
	if round_state == "live":
		_check_round_end()
		_update_status_label()

func _update_status_label():
	var alive_count = 0
	for p in players:
		if not p.is_eliminated:
			alive_count += 1

	var hud = get_node_or_null("../CanvasLayer/MatchHUD")
	if hud != null and hud.has_method("update_match_state"):
		hud.update_match_state(round_number, set_number, alive_count, players.size())

	var hud2 = get_node_or_null("../CanvasLayer/MatchHUD2")
	if hud2 != null and hud2.has_method("update_match_state"):
		hud2.update_match_state(round_number, set_number, alive_count, players.size())

func _check_round_end():
	var alive = []
	for p in players:
		if not p.is_eliminated:
			alive.append(p)

	var alive_count = alive.size()
	var prev_count = previous_alive.size()
	if alive_count != prev_count:
		# Don't emit these via hud_notification — the remaining label
		# already repositions to center and displays the dramatic text.
		# Emitting here would cause them to appear twice in the same spot.
		pass

	if not GameConfig.teams_enabled:
		if alive.size() == 0 and previous_alive.size() >= 2:
			_end_round(previous_alive, true)
			previous_alive = alive
			return
		if alive.size() <= 1:
			_end_round(alive)
		previous_alive = alive
		return

	var alive_teams = {}
	for p in alive:
		var t = p.team_id if "team_id" in p else -1
		if not alive_teams.has(t):
			alive_teams[t] = []
		alive_teams[t].append(p)

	if alive.size() == 0 and previous_alive.size() >= 2:
		var prev_teams = {}
		for p in previous_alive:
			var t = p.team_id if "team_id" in p else -1
			prev_teams[t] = true
		if prev_teams.size() >= 2:
			_end_round(previous_alive, true)
			previous_alive = alive
			return

	if alive_teams.size() <= 1:
		_end_round(alive)
	previous_alive = alive

func _end_round(alive, multi_winner_draw := false):
	round_state = "ended"
	_disable_all_players()

	if GameConfig.teams_enabled and alive.size() > 0:
		if multi_winner_draw:
			await _resolve_team_multi_winner(alive)
			return
		var winning_team_id = alive[0].team_id if "team_id" in alive[0] else -1
		for p in alive:
			round_wins[p] += 1
		_set_round_label_text("Team " + str(winning_team_id + 1) + " wins the round!")
		await get_tree().create_timer(round_end_display_time).timeout

		var team_round_wins = round_wins[alive[0]]
		if team_round_wins >= GameConfig.rounds_per_set:
			for p in alive:
				match_points[p] += 1
			for p in players:
				round_wins[p] = 0

			if match_points[alive[0]] >= GameConfig.sets_per_match:
				_set_round_label_text("Team " + str(winning_team_id + 1) + " WINS THE MATCH!")
				await get_tree().create_timer(match_end_display_time).timeout
				_leave_match_to("res://game_setup.tscn")
				return
			else:
				_set_round_label_text("Team " + str(winning_team_id + 1) + " wins the set!")
				await get_tree().create_timer(set_end_display_time).timeout
				set_number += 1
				round_number = 0
		_reset_round()
		return

	if multi_winner_draw and alive.size() >= 2:
		await _resolve_multi_winner(alive)
		return

	if alive.size() == 1:
		var winner = alive[0]
		round_wins[winner] += 1
		# Trigger victory dance on the winner immediately.
		if winner.has_method("play_victory_dance"):
			winner.play_victory_dance()
		_set_round_label_text(winner.get_display_name() + " wins the round!")
		await get_tree().create_timer(round_end_display_time).timeout

		if round_wins[winner] >= GameConfig.rounds_per_set:
			match_points[winner] += 1
			for p in players:
				round_wins[p] = 0

			if match_points[winner] >= GameConfig.sets_per_match:
				_set_round_label_text(winner.get_display_name() + " WINS THE MATCH!")
				await get_tree().create_timer(match_end_display_time).timeout
				_leave_match_to("res://game_setup.tscn")
				return
			else:
				_set_round_label_text(winner.get_display_name() + " wins the set!")
				await get_tree().create_timer(set_end_display_time).timeout
				set_number += 1
				round_number = 0
	else:
		_set_round_label_text("Draw!")
		await get_tree().create_timer(round_end_display_time).timeout

	_reset_round()

func _resolve_multi_winner(tied_players):
	var names = []
	for p in tied_players:
		round_wins[p] += 1
		names.append(p.get_display_name())
	_set_round_label_text(" & ".join(names) + " tie the round!")
	await get_tree().create_timer(round_end_display_time).timeout

	var match_winners = []
	for p in tied_players:
		if round_wins[p] >= GameConfig.rounds_per_set:
			match_points[p] += 1
			match_winners.append(p)

	if match_winners.size() > 0:
		for p in players:
			round_wins[p] = 0

		var set_winners = []
		for p in players:
			if match_points[p] >= GameConfig.sets_per_match:
				set_winners.append(p)

		if set_winners.size() > 0:
			var winner_names = []
			for p in set_winners:
				winner_names.append(p.get_display_name())
			_set_round_label_text(" & ".join(winner_names) + " TIE FOR THE MATCH!")
			await get_tree().create_timer(match_end_display_time).timeout
			_leave_match_to("res://game_setup.tscn")
			return
		else:
			var winner_names = []
			for p in match_winners:
				winner_names.append(p.get_display_name())
			_set_round_label_text(" & ".join(winner_names) + " tie for the set!")
			await get_tree().create_timer(set_end_display_time).timeout
			set_number += 1
			round_number = 0

	_reset_round()

func _resolve_team_multi_winner(tied_players):
	var tied_team_ids = []
	for p in tied_players:
		var t = p.team_id if "team_id" in p else -1
		if t not in tied_team_ids:
			tied_team_ids.append(t)

	for p in tied_players:
		round_wins[p] += 1

	var team_labels = []
	for t in tied_team_ids:
		team_labels.append("Team " + str(t + 1))
	_set_round_label_text(" & ".join(team_labels) + " tie the round!")
	await get_tree().create_timer(round_end_display_time).timeout

	var match_winner_teams = []
	for t in tied_team_ids:
		var rep = null
		for p in tied_players:
			if ("team_id" in p and p.team_id == t):
				rep = p
				break
		if rep != null and round_wins[rep] >= GameConfig.rounds_per_set:
			match_winner_teams.append(t)

	if match_winner_teams.size() > 0:
		for p in players:
			if ("team_id" in p and p.team_id in match_winner_teams):
				match_points[p] += 1
		for p in players:
			round_wins[p] = 0

		var set_winner_teams = []
		for t in match_winner_teams:
			var rep = null
			for p in players:
				if ("team_id" in p and p.team_id == t):
					rep = p
					break
			if rep != null and match_points[rep] >= GameConfig.sets_per_match:
				set_winner_teams.append(t)

		if set_winner_teams.size() > 0:
			var labels = []
			for t in set_winner_teams:
				labels.append("Team " + str(t + 1))
			_set_round_label_text(" & ".join(labels) + " TIE FOR THE MATCH!")
			await get_tree().create_timer(match_end_display_time).timeout
			_leave_match_to("res://game_setup.tscn")
			return
		else:
			var labels = []
			for t in match_winner_teams:
				labels.append("Team " + str(t + 1))
			_set_round_label_text(" & ".join(labels) + " tie for the set!")
			await get_tree().create_timer(set_end_display_time).timeout
			set_number += 1
			round_number = 0

	_reset_round()

func _reset_round():
	round_number += 1
	_assign_spawn_transforms()
	for p in players:
		p.respawn(spawn_transforms[p])
	for w in get_tree().get_nodes_in_group("weapon"):
		w.reset_to_spawn()
	_apply_gun_spawn_mode()
	_spawn_marker_items()
	for it in get_tree().get_nodes_in_group("item"):
		it.reset_to_spawn()
	for pu in get_tree().get_nodes_in_group("powerup"):
		if pu.has_method("reset_to_spawn"):
			pu.reset_to_spawn()
	for trap in get_tree().get_nodes_in_group("deployed_trap"):
		trap.queue_free()
	_start_countdown()

# ============================================================
# Marker-driven item spawning: maps place `item_spawn_point` and
# `powerup_spawn_point` Marker3Ds (user-positioned); each round every item
# marker gets a random enabled item, every powerup marker gets a powerup.
# Scene-placed legacy item nodes keep working alongside.
# ============================================================
const POWERUP_SCENE_PATH := "res://powerup.tscn"

func _spawn_marker_items():
	# Free everything spawned last round. A group (not an array) is used so
	# that items which re-rolled themselves mid-round (item.gd) are tracked and
	# cleaned up too, not just the originals.
	for node in get_tree().get_nodes_in_group("marker_spawned"):
		node.queue_free()
	var enabled_types: Array = []
	for t in GameConfig.ITEM_SCENES:
		if GameConfig.is_item_enabled(t):
			enabled_types.append(t)
	if enabled_types.size() > 0:
		for m in get_tree().get_nodes_in_group("item_spawn_point"):
			var t: String = enabled_types[randi() % enabled_types.size()]
			var scene = load(GameConfig.ITEM_SCENES[t])
			if scene == null:
				continue
			var inst = scene.instantiate()
			get_tree().current_scene.add_child(inst)
			inst.global_position = m.global_position
			# _ready() captured spawn_position at the origin (before we moved it);
			# re-point it so reset_to_spawn() keeps the item at its marker on
			# round 2+ instead of teleporting it to map center near the gun.
			if "spawn_position" in inst:
				inst.spawn_position = inst.global_position
			if "spawn_rotation" in inst:
				inst.spawn_rotation = inst.global_rotation
			# marker items re-roll into a random type when they respawn mid-round
			if "reroll_on_respawn" in inst:
				inst.reroll_on_respawn = true
			inst.add_to_group("marker_spawned", true)
	if ResourceLoader.exists(POWERUP_SCENE_PATH):
		var pu_scene = load(POWERUP_SCENE_PATH)
		for m in get_tree().get_nodes_in_group("powerup_spawn_point"):
			var pu = pu_scene.instantiate()
			get_tree().current_scene.add_child(pu)
			pu.global_position = m.global_position
			if "spawn_position" in pu:
				pu.spawn_position = pu.global_position
			if "base_y" in pu:
				pu.base_y = pu.position.y
			pu.add_to_group("marker_spawned", true)

func _apply_gun_spawn_mode():
	if GameConfig.gun_spawn_mode != "random":
		return
	var spawn_points = get_tree().get_nodes_in_group("gun_spawn_point")
	if spawn_points.size() == 0:
		return
	var guns = get_tree().get_nodes_in_group("gun")
	if guns.size() == 0:
		return
	var chosen = spawn_points[randi() % spawn_points.size()]
	guns[0].global_position = chosen.global_position
	guns[0].spawn_position = chosen.global_position
