extends Node

@export var countdown_time := 3
@export var round_end_display_time := 3
@export var set_end_display_time := 4
@export var match_end_display_time := 6

const MAX_TOTAL_PLAYERS := 10
const MAX_BOTS_SOLO := 9
const MAX_BOTS_SPLIT := 8
const ONLINE_BOT_ACTOR_ID_BASE := 10000
const ONLINE_POWERUP_TYPES := ["extra_dash", "sticky_hands", "speed_surge", "silent_steps", "vampire_touch", "extra_life", "magnet_hands"]

const DummyScene = preload("res://DummyModel.tscn")
const GunScene = preload("res://gun.tscn")
const MeleeScene = preload("res://melee_weapon.tscn")
const CombatIdentityTag = preload("res://combat_identity_tag.gd")
const OVERTIME_MOVEMENT_PHASE_COUNT := 10
const OVERTIME_OPENING_APPROACH_TIME := 5.0
const OVERTIME_FULL_ENGULF_TIME := 120.0
const OVERTIME_ZONE_DURATION := \
	(OVERTIME_FULL_ENGULF_TIME - OVERTIME_OPENING_APPROACH_TIME) \
	/ OVERTIME_MOVEMENT_PHASE_COUNT
const OVERTIME_MIN_OPENING_RADIUS := 12.0
const OVERTIME_START_BUFFER_RATIO := 0.05
const OVERTIME_START_BUFFER_MIN := 2.0
const OVERTIME_FIRE_SAMPLE_MARGIN := 3.0
const OVERTIME_FIRE_VISUAL_UPDATE_STEP := 0.10
const OVERTIME_FIRE_VISUAL_LEAD := 0.35
const OVERTIME_FIRE_BASE_INTENSITY := 0.12

var players = []
var spawn_transforms = {}
var round_state = "countdown"
var round_number = 1
var set_number = 1

var round_wins = {}
var match_points = {}
var previous_alive = []
var round_elapsed := 0.0
var overtime_active := false
var overtime_elapsed := 0.0
var _overtime_center := Vector3.ZERO
var _overtime_outer_radius := 50.0
var _overtime_start_radius := 52.5
var _overtime_fire_outer_radius := 65.0
var _overtime_outer_extents := Vector2(50.0, 50.0)
var _overtime_start_extents := Vector2(52.5, 52.5)
var _overtime_fire_outer_extents := Vector2(65.0, 65.0)
var _overtime_floor_y := 0.05
var _storm_wall: Node3D = null
var _storm_visual_radius := -1.0
var _storm_floor_mesh: MeshInstance3D = null
var _storm_floor_material: ShaderMaterial = null
var _storm_flame_particles: CPUParticles3D = null
var _storm_surface_samples: Array[Dictionary] = []
var _storm_fire_visual_radius := -1.0
var _storm_exposure := {}
var _storm_safe_time := {}
var _storm_cumulative := {}
var _elimination_time_ms := {}
var _round_kills := {}
var _last_overtime_pulse_zone := -1
var _online_previous_alive_ids: Array = []
var _local_round_generation := 0

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
var _online_overtime_sync_timer := 0.0

func _setup_online_freeroam() -> void:
	var root := get_tree().current_scene
	# Free the baked local players + local HUD nodes (online = one view per
	# machine). Runtime strip only — no map .tscn is edited.
	for n in ["player1", "player2", "SplitScreenLayer", "CanvasLayer"]:
		var node = root.get_node_or_null(n)
		if node:
			node.free()
	# Remove legacy baked pickup/weapon instances, but preserve every authored
	# marker. Each round spawns one synchronized melee from melee_spawn_point.
	for melee in get_tree().get_nodes_in_group("melee"):
		melee.free()
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
		"swing": melee._net_do_swing(bool(data.get("should_break", false)))
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
				bool(data.get("survives_lethal", false)),
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
	if not NetworkManager.is_host() or epoch != online_round_epoch or online_match_over or overtime_active:
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
	if actor.has_method("can_collect_powerup") and not actor.can_collect_powerup(collected_type):
		return
	_net_collect_online_powerup.rpc(powerup_id, actor_id, collected_type)
	_schedule_online_powerup_respawn(powerup_id, powerup.respawn_time, epoch)

@rpc("authority", "reliable", "call_local")
func _net_collect_online_powerup(powerup_id: int, actor_id: int, power_type: String) -> void:
	var powerup = _online_powerup(powerup_id)
	if powerup != null:
		powerup._net_collect(actor_id, power_type)

func _schedule_online_powerup_respawn(powerup_id: int, delay: float, epoch: int) -> void:
	await get_tree().create_timer(delay).timeout
	if not NetworkManager.is_host() or epoch != online_round_epoch or online_match_over or overtime_active:
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
		"steam_launch":
			if target.has_method("apply_steam_boost"):
				target.apply_steam_boost(
					float(data.get("velocity", 12.0)),
					float(data.get("origin_y", target.global_position.y)),
					float(data.get("height_gate", 2.0)),
					float(data.get("gravity_multiplier", 3.0)))
			else:
				target.velocity.y = float(data.get("velocity", 12.0))
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
		if bool(target.get("holding_gun")):
			if int(target.get("melee_disarm_shields")) > 0:
				_net_consume_online_shield.rpc(int(actor_id))
			else:
				var hold_point = target.get_hold_point()
				if hold_point != null and hold_point.get_child_count() > 0:
					var gun = hold_point.get_child(0)
					if gun.has_method("net_force_disarm"):
						gun.net_force_disarm()
					else:
						gun.net_force_drop()
					_record_online_item_disarm(owner_actor_id, int(actor_id), "💥")
	for decoy in get_tree().get_nodes_in_group("combat_decoy"):
		if decoy.global_position.distance_to(position) <= radius \
				and decoy.has_method("pop_from_attack"):
			decoy.pop_from_attack(owner, "grenade")

func broadcast_online_deployed_action(deployed_id: int, action: String, data: Dictionary = {}) -> void:
	if multiplayer.is_server():
		_net_apply_online_deployed_action.rpc(deployed_id, action, data)

func broadcast_online_decoy_transform(
		deployed_id: int, transform: Transform3D, velocity: Vector3) -> void:
	if multiplayer.is_server():
		_net_apply_online_decoy_transform.rpc(
			deployed_id, transform, velocity, online_round_epoch)

@rpc("authority", "unreliable_ordered", "call_remote")
func _net_apply_online_decoy_transform(
		deployed_id: int, transform: Transform3D, velocity: Vector3, epoch: int) -> void:
	if epoch != online_round_epoch:
		return
	var deployed = _online_deployed(deployed_id)
	if deployed != null and deployed.has_method("apply_online_action"):
		deployed.apply_online_action("transform", {
			"transform": transform,
			"velocity": velocity,
		})

func _record_online_item_disarm(disarmer_id: int, victim_id: int, icon: String) -> void:
	if online_actor_state.has(disarmer_id):
		var entry: Dictionary = online_actor_state[disarmer_id]
		entry["disarms"] = int(entry.get("disarms", 0)) + 1
		online_actor_state[disarmer_id] = entry
	_net_announce_online_disarm.rpc(victim_id, disarmer_id, icon)
	_broadcast_online_state()

@rpc("authority", "reliable", "call_local")
func _net_announce_online_disarm(victim_id: int, disarmer_id: int, icon: String) -> void:
	var victim = NetworkManager.find_actor(victim_id)
	var disarmer = NetworkManager.find_actor(disarmer_id)
	if victim != null:
		GameEvents.player_disarmed.emit(
			victim.get_display_name(),
			disarmer.get_display_name() if disarmer != null else "",
			icon)

func request_online_decoy_control_toggle(deployed_id: int, actor_id: int) -> void:
	if NetworkManager.is_host():
		_server_online_decoy_control_toggle(
			deployed_id, actor_id, NetworkManager.local_id(), online_round_epoch)
	else:
		_net_request_online_decoy_control_toggle.rpc_id(
			1, deployed_id, actor_id, online_round_epoch)

@rpc("any_peer", "reliable")
func _net_request_online_decoy_control_toggle(
		deployed_id: int, actor_id: int, epoch: int) -> void:
	_server_online_decoy_control_toggle(
		deployed_id, actor_id, multiplayer.get_remote_sender_id(), epoch)

func _server_online_decoy_control_toggle(
		deployed_id: int, actor_id: int, sender_peer: int, epoch: int) -> void:
	if not can_accept_online_combat(epoch):
		return
	var decoy = _online_deployed(deployed_id)
	var actor = NetworkManager.find_actor(actor_id)
	if decoy == null or actor == null or int(actor.get("owner_peer_id")) != sender_peer:
		return
	if decoy.get("owner_player") != actor:
		return
	broadcast_online_deployed_action(deployed_id, "toggle_control")

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
		if actor.has_method("consume_sticky_hands"):
			actor.consume_sticky_hands()
		else:
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
			"round_kills": 0,
			"storm_time": 0.0,
			"eliminated_at_ms": -1,
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
	var melee_assignments := _build_online_melee_assignments()
	var item_assignments := _build_online_item_assignments()
	var powerup_assignments := _build_online_powerup_assignments()
	_net_reset_online_round.rpc(assignments, melee_assignments, item_assignments, powerup_assignments)
	_online_unlock_melee_after_delay(online_round_epoch)
	for actor_id in online_actor_state:
		var entry: Dictionary = online_actor_state[actor_id]
		entry["alive"] = true
		entry["round_kills"] = 0
		entry["storm_time"] = 0.0
		entry["eliminated_at_ms"] = -1
		online_actor_state[actor_id] = entry
	_online_previous_alive_ids = online_actor_state.keys()
	_broadcast_online_state()
	for count in range(countdown_time, 0, -1):
		online_announcement = str(count)
		_broadcast_online_state()
		await get_tree().create_timer(1.0).timeout
	online_announcement = "GO!"
	round_elapsed = 0.0
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

func _build_online_melee_assignments() -> Array:
	var markers := _sorted_online_markers("melee_spawn_point")
	if markers.is_empty():
		push_warning("RoundManager: map has no melee_spawn_point markers.")
		return []
	var marker = markers[randi() % markers.size()]
	return [{
		"candidate_id": 0,
		"position": marker.global_position,
		"rotation": marker.global_rotation,
		"identity": MeleeWeaponRegistry.get_random_identity(),
	}]

@rpc("authority", "reliable", "call_local")
func _net_reset_online_round(assignments: Array, melee_assignments: Array, item_assignments: Array, powerup_assignments: Array) -> void:
	_clear_overtime_state()
	for bullet in get_tree().get_nodes_in_group("online_bullet"):
		bullet.queue_free()
	for group_name in ["online_item", "online_powerup", "online_deployed"]:
		for node in get_tree().get_nodes_in_group(group_name):
			node.free()
	for melee in get_tree().get_nodes_in_group("online_spawned_melee"):
		melee.free()
	for gun in get_tree().get_nodes_in_group("gun"):
		gun.reset_to_spawn()
	for melee_assignment in melee_assignments:
		_spawn_online_melee(melee_assignment)
	for item_assignment in item_assignments:
		_spawn_online_item(item_assignment)
	for powerup_assignment in powerup_assignments:
		_spawn_online_powerup(powerup_assignment)
	for assignment in assignments:
		var actor = NetworkManager.find_actor(int(assignment["actor_id"]))
		if actor != null:
			actor.respawn(Transform3D(Basis(Vector3.UP, float(assignment["yaw"])), assignment["pos"]))
	_net_set_online_players_enabled(false)

func _spawn_online_melee(assignment: Dictionary) -> void:
	var melee = MeleeScene.instantiate()
	melee.name = "OnlineMelee"
	melee.online_candidate_id = int(assignment.get("candidate_id", 0))
	melee.add_to_group("online_spawned_melee", true)
	get_tree().current_scene.add_child(melee)
	melee.global_position = assignment.get("position", Vector3.ZERO)
	melee.global_rotation = assignment.get("rotation", Vector3.ZERO)
	melee.spawn_position = melee.global_position
	melee.spawn_rotation = melee.global_rotation
	melee.apply_network_identity(assignment.get("identity", {}))
	melee.set_online_active(true)
	melee.set_online_pickup_locked(GameConfig.melee_spawn_delay > 0.0)

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
		"overtime_active": overtime_active,
		"overtime_elapsed": overtime_elapsed,
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
	if bool(snapshot.get("overtime_active", false)) and overtime_active:
		overtime_elapsed = float(snapshot.get("overtime_elapsed", overtime_elapsed))
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
	if alive_ids.size() == 1:
		_online_finish_round(alive_ids[0])
	elif alive_ids.is_empty():
		var winner_id := _select_online_overtime_winner(_online_previous_alive_ids) if overtime_active else -1
		_online_finish_round(winner_id)
	else:
		_online_previous_alive_ids = alive_ids

func _select_online_overtime_winner(candidates: Array) -> int:
	var remaining := candidates.filter(func(id): return online_actor_state.has(int(id)))
	if remaining.is_empty():
		return -1
	var latest := -1
	for id in remaining:
		latest = maxi(latest, int(online_actor_state[int(id)].get("eliminated_at_ms", -1)))
	remaining = remaining.filter(func(id):
		return int(online_actor_state[int(id)].get("eliminated_at_ms", -1)) == latest)
	if remaining.size() == 1:
		return int(remaining[0])
	var least_storm := INF
	for id in remaining:
		least_storm = minf(least_storm, float(online_actor_state[int(id)].get("storm_time", 0.0)))
	remaining = remaining.filter(func(id):
		return is_equal_approx(float(online_actor_state[int(id)].get("storm_time", 0.0)), least_storm))
	if remaining.size() == 1:
		return int(remaining[0])
	var most_kills := -1
	for id in remaining:
		most_kills = maxi(most_kills, int(online_actor_state[int(id)].get("round_kills", 0)))
	remaining = remaining.filter(func(id):
		return int(online_actor_state[int(id)].get("round_kills", 0)) == most_kills)
	return int(remaining[0]) if remaining.size() == 1 else -1

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
		if overtime_active:
			online_announcement += "\nOT %s" % _format_time_ms(overtime_elapsed)
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

func server_eliminate(victim_id: int, killer_id: int, epoch: int = -1,
		weapon_icon: String = "🔫", feedback_kind: String = "gun",
		lethal_kind: String = "weapon") -> void:
	if not can_accept_online_combat(epoch):
		return
	if not online_actor_state.has(victim_id) or not bool(online_actor_state[victim_id].get("alive", false)):
		return
	var victim = NetworkManager.find_actor(victim_id)
	if lethal_kind == "weapon" and victim != null and float(victim.get("lethal_immunity_timer")) > 0.0:
		server_confirm_hit(killer_id, false, feedback_kind)
		return
	if lethal_kind == "weapon" and victim != null and bool(victim.get("second_wind_ready")):
		_net_consume_online_second_wind.rpc(victim_id)
		server_confirm_hit(killer_id, false, feedback_kind)
		return
	var victim_entry: Dictionary = online_actor_state[victim_id]
	victim_entry["alive"] = false
	victim_entry["deaths"] = int(victim_entry.get("deaths", 0)) + 1
	victim_entry["eliminated_at_ms"] = Time.get_ticks_msec()
	victim_entry["storm_time"] = float(_storm_cumulative.get(victim_id, victim_entry.get("storm_time", 0.0)))
	online_actor_state[victim_id] = victim_entry
	if killer_id != victim_id and online_actor_state.has(killer_id):
		var killer_entry: Dictionary = online_actor_state[killer_id]
		killer_entry["kills"] = int(killer_entry.get("kills", 0)) + 1
		killer_entry["round_kills"] = int(killer_entry.get("round_kills", 0)) + 1
		online_actor_state[killer_id] = killer_entry
	_net_eliminate.rpc(victim_id, killer_id, weapon_icon, lethal_kind)
	if killer_id != victim_id:
		server_confirm_hit(killer_id, true, feedback_kind)
	_broadcast_online_state()

# Tell the attacker's machine their shot/swing connected (hit-marker feedback).
# Broadcast + local filter: each peer emits only if the attacker is its own
# locally-controlled actor (bots never trigger a marker anywhere).
func server_confirm_hit(attacker_id: int, eliminated: bool, source_kind: String = "gun") -> void:
	if multiplayer.is_server():
		_net_hit_confirmed.rpc(attacker_id, eliminated, source_kind)

@rpc("authority", "reliable", "call_local")
func _net_hit_confirmed(attacker_id: int, eliminated: bool, source_kind: String = "gun") -> void:
	var attacker = NetworkManager.find_actor(attacker_id)
	if attacker == null:
		return
	if "is_bot" in attacker and attacker.is_bot:
		return
	if int(attacker.get("owner_peer_id")) != NetworkManager.local_id():
		return
	GameEvents.combat_feedback.emit(attacker.get_display_name(), "%s_%s" % [source_kind, "elimination" if eliminated else "hit"])

@rpc("authority", "reliable", "call_local")
func _net_consume_online_second_wind(actor_id: int) -> void:
	var actor = NetworkManager.find_actor(actor_id)
	if actor == null:
		return
	if actor.has_method("consume_extra_life"):
		actor.consume_extra_life()
	else:
		actor.second_wind_ready = false
		actor.active_powerup_order.erase("extra_life")
		actor.lethal_immunity_timer = 1.0
	actor.flash_hit()

@rpc("authority", "reliable", "call_local")
func _net_eliminate(victim_id: int, killer_id: int, weapon_icon: String, lethal_kind: String = "weapon") -> void:
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
	victim.eliminate(killer_name, weapon_icon, lethal_kind)

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
		_round_kills[p] = 0
	_setup_local_combat_tags()
	_disable_all_players()
	await get_tree().process_frame
	_disable_all_players()
	_assign_spawn_transforms()
	_apply_gun_spawn_mode()
	_spawn_marker_melee()
	_spawn_marker_items()
	GameEvents.player_eliminated.connect(_on_stat_eliminated)
	GameEvents.player_disarmed.connect(_on_stat_disarmed)
	GameEvents.gun_picked_up.connect(_on_stat_gun_picked_up)
	GameEvents.melee_hit_landed.connect(_on_stat_melee_hit)
	_setup_local_hit_markers()
	await get_tree().process_frame
	AudioManager.play_music("game")
	_start_countdown()

func _setup_local_combat_tags() -> void:
	if NetworkManager.is_online():
		return
	var viewers := players.filter(func(p): return not ("is_bot" in p and p.is_bot))
	var reserved_mask := (1 << 17) | (1 << 18) | (1 << 19)
	for viewer in viewers:
		var viewer_camera: Camera3D = viewer.get_camera()
		if viewer_camera != null:
			viewer_camera.cull_mask &= ~reserved_mask
	for viewer_index in viewers.size():
		var viewer = viewers[viewer_index]
		var camera: Camera3D = viewer.get_camera()
		if camera == null:
			continue
		var render_layer := 18 + viewer_index
		camera.cull_mask |= 1 << (render_layer - 1)
		for target in players:
			if target != viewer:
				_add_local_combat_tag(target, viewer, render_layer)

func _add_local_combat_tag(target, viewer, render_layer: int) -> void:
	var tag = CombatIdentityTag.new()
	tag.name = "CombatIdentityFor%s" % viewer.name
	target.add_child(tag)
	tag.setup(target, viewer, render_layer)

func register_local_decoy_tags(decoy) -> void:
	if NetworkManager.is_online():
		return
	var viewers := players.filter(func(p): return not ("is_bot" in p and p.is_bot))
	for viewer_index in viewers.size():
		_add_local_combat_tag(decoy, viewers[viewer_index], 18 + viewer_index)

# Inject a crosshair hit-marker into each local player's UI half at runtime
# (maps are never edited — same rule as the online strip). Each marker filters
# by its player's display name so splitscreen halves only flash for their owner.
func _setup_local_hit_markers():
	var canvas = get_node_or_null("../CanvasLayer")
	if canvas == null:
		return
	for cfg in [["PlayerUI1", "player1"], ["PlayerUI2", "player2"]]:
		var ui = canvas.get_node_or_null(cfg[0])
		var pnode = get_node_or_null("../" + cfg[1])
		if ui == null or pnode == null:
			continue
		var marker = Control.new()
		marker.name = "HitMarker"
		marker.set_script(load("res://hit_marker.gd"))
		marker.set("filter_name", pnode.get_display_name())
		ui.add_child(marker)

func _find_player_by_name(display_name: String):
	for p in players:
		if p.get_display_name() == display_name:
			return p
	return null

func _on_stat_eliminated(victim_name: String, killer_name: String, _icon: String):
	var victim = _find_player_by_name(victim_name)
	if overtime_active and victim != null and not _elimination_time_ms.has(victim):
		_elimination_time_ms[victim] = Time.get_ticks_msec()
	if victim != null and stat_deaths.has(victim):
		stat_deaths[victim] += 1
	if killer_name != "":
		var killer = _find_player_by_name(killer_name)
		if killer != null and stat_kills.has(killer):
			stat_kills[killer] += 1
			_round_kills[killer] = int(_round_kills.get(killer, 0)) + 1

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

var _round_labels_styled := false

func _set_round_label_text(text):
	for label_name in ["RoundLabel", "RoundLabel2"]:
		var label = get_node_or_null("../CanvasLayer/" + label_name)
		if label == null:
			continue
		# Style once at runtime (labels are map-baked; no .tscn edits).
		if not _round_labels_styled:
			label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
			label.add_theme_constant_override("shadow_offset_x", 3)
			label.add_theme_constant_override("shadow_offset_y", 3)
			ThemeManager.embolden(label)
		# Punch on every text change — countdown ticks, GO, winner banners.
		if label.text != str(text) and str(text) != "":
			ThemeManager.punch(label, 1.3, 0.22)
		label.text = text
	_round_labels_styled = true

func _start_countdown():
	_clear_overtime_state()
	round_state = "countdown"
	_local_round_generation += 1
	for m in get_tree().get_nodes_in_group("melee"):
		if m.has_method("randomize_attributes"):
			m.randomize_attributes()
	_apply_melee_spawn_delay(_local_round_generation)
	previous_alive = players.duplicate()
	_update_status_label()
	GameEvents.hud_notification.emit("NEW ROUND STARTING")
	for i in range(countdown_time, 0, -1):
		_set_round_label_text(str(i))
		await get_tree().create_timer(1.0).timeout
	_set_round_label_text("GO!")
	round_elapsed = 0.0
	round_state = "live"
	_enable_all_players()
	await get_tree().create_timer(0.5).timeout
	_set_round_label_text("")

func _apply_melee_spawn_delay(generation: int):
	var melee_weapons = get_tree().get_nodes_in_group("melee")
	if GameConfig.melee_spawn_delay <= 0.0:
		for m in melee_weapons:
			m.pickup_locked = false
		return
	for m in melee_weapons:
		m.pickup_locked = true
	await get_tree().create_timer(GameConfig.melee_spawn_delay).timeout
	if generation != _local_round_generation or round_state != "countdown" and round_state != "live":
		return
	for m in melee_weapons:
		if is_instance_valid(m):
			m.pickup_locked = false

func _process(delta):
	if NetworkManager.is_online():
		if overtime_active:
			overtime_elapsed += delta
			if NetworkManager.is_host():
				_online_overtime_sync_timer -= delta
				if _online_overtime_sync_timer <= 0.0:
					_online_overtime_sync_timer = 0.2
					_net_sync_overtime_clock.rpc(overtime_elapsed, online_round_epoch)
			_update_storm_visual()
			# Every peer tracks exposure locally so its HUD countdown stays
			# responsive. Only the host is allowed to resolve an elimination.
			if online_combat_live:
				_update_overtime_damage(delta, true, NetworkManager.is_host())
		if NetworkManager.is_host():
			if online_combat_live and not overtime_active:
				round_elapsed += delta
				if GameConfig.round_time_limit > 0.0 and round_elapsed >= GameConfig.round_time_limit:
					_start_online_overtime()
			_check_online_round_end()
		return
	if round_state == "live":
		round_elapsed += delta
		if GameConfig.round_time_limit > 0.0 and round_elapsed >= GameConfig.round_time_limit:
			_start_local_overtime()
		_check_round_end()
		_update_status_label()
	elif round_state == "overtime":
		overtime_elapsed += delta
		_update_storm_visual()
		_update_overtime_damage(delta, false)
		_check_round_end()
		_update_status_label()

@rpc("authority", "unreliable_ordered", "call_remote")
func _net_sync_overtime_clock(host_elapsed: float, epoch: int) -> void:
	if epoch != online_round_epoch or not overtime_active:
		return
	var difference := host_elapsed - overtime_elapsed
	if absf(difference) > 0.5:
		overtime_elapsed = host_elapsed
	else:
		overtime_elapsed += difference * 0.5

func _clear_overtime_state() -> void:
	overtime_active = false
	overtime_elapsed = 0.0
	round_elapsed = 0.0
	_last_overtime_pulse_zone = -1
	_storm_exposure.clear()
	_storm_safe_time.clear()
	_storm_cumulative.clear()
	_elimination_time_ms.clear()
	_overtime_start_radius = 0.0
	_overtime_outer_extents = Vector2.ZERO
	_overtime_start_extents = Vector2.ZERO
	_overtime_fire_outer_extents = Vector2.ZERO
	_online_previous_alive_ids.clear()
	for hud_path in ["../CanvasLayer/MatchHUD", "../CanvasLayer/MatchHUD2"]:
		var hud = get_node_or_null(hud_path)
		if hud != null and hud.has_method("update_fire_warning"):
			hud.update_fire_warning({"active": false})
	if _storm_wall != null and is_instance_valid(_storm_wall):
		_storm_wall.queue_free()
	_storm_wall = null
	_storm_visual_radius = -1.0
	_storm_floor_mesh = null
	_storm_floor_material = null
	_storm_flame_particles = null
	_storm_surface_samples.clear()
	_storm_fire_visual_radius = -1.0
	for gun in get_tree().get_nodes_in_group("gun"):
		if bool(gun.get("is_overtime_gun")):
			var holder = gun.get("player_ref")
			if holder != null:
				holder.holding_gun = false
			gun.free()

func _calculate_overtime_geometry() -> void:
	# Future maps can author explicit edge markers when their playable footprint
	# is unusual. Existing maps need no migration: player/item/powerup markers
	# provide an automatic combat-footprint fallback.
	var boundary_markers := _arena_markers_in_group("overtime_boundary_point")
	if boundary_markers.is_empty():
		for group_name in [
			"spawn_point", "item_spawn_point", "powerup_spawn_point",
			"gun_spawn_point",
		]:
			for marker in _arena_markers_in_group(group_name):
				if not boundary_markers.has(marker):
					boundary_markers.append(marker)
	var gun_markers := _arena_markers_in_group("gun_spawn_point")
	var fallback_center := Vector3.ZERO
	if not gun_markers.is_empty():
		fallback_center = gun_markers[0].global_position
	else:
		var guns := get_tree().get_nodes_in_group("gun")
		fallback_center = guns[0].global_position if not guns.is_empty() else Vector3.ZERO
	var center_markers := _arena_markers_in_group("overtime_center_point")
	if not center_markers.is_empty():
		_overtime_center = center_markers[0].global_position
	elif not boundary_markers.is_empty():
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for marker in boundary_markers:
			minimum.x = minf(minimum.x, marker.global_position.x)
			minimum.y = minf(minimum.y, marker.global_position.z)
			maximum.x = maxf(maximum.x, marker.global_position.x)
			maximum.y = maxf(maximum.y, marker.global_position.z)
		var footprint_center := (minimum + maximum) * 0.5
		_overtime_center = Vector3(
			footprint_center.x, fallback_center.y, footprint_center.y)
	else:
		_overtime_center = fallback_center
	var furthest_x := 0.0
	var furthest_z := 0.0
	var boundary_offsets: Array[Vector2] = []
	for marker in boundary_markers:
		var delta_pos: Vector3 = marker.global_position - _overtime_center
		furthest_x = maxf(furthest_x, absf(delta_pos.x))
		furthest_z = maxf(furthest_z, absf(delta_pos.z))
		boundary_offsets.append(Vector2(delta_pos.x, delta_pos.z))
	# Gameplay markers describe the combat footprint much more accurately than
	# the full authored model bounds. Using extents instead of one corner radius
	# keeps rectangular maps such as City advancing evenly from every side.
	var base_extents := Vector2(
		maxf(furthest_x, OVERTIME_MIN_OPENING_RADIUS),
		maxf(furthest_z, OVERTIME_MIN_OPENING_RADIUS))
	var fit_scale := 1.0
	for offset in boundary_offsets:
		fit_scale = maxf(fit_scale, _superellipse_distance(offset, base_extents))
	_overtime_outer_extents = base_extents * fit_scale
	_overtime_outer_radius = maxf(
		_overtime_outer_extents.x, _overtime_outer_extents.y)
	_configure_overtime_extents()
	_overtime_floor_y = _find_overtime_floor_y()

func _configure_overtime_extents() -> void:
	if _overtime_outer_extents.x <= 0.0 or _overtime_outer_extents.y <= 0.0:
		_overtime_outer_extents = Vector2(
			_overtime_outer_radius, _overtime_outer_radius)
	var start_buffer := Vector2(
		maxf(_overtime_outer_extents.x * OVERTIME_START_BUFFER_RATIO,
			OVERTIME_START_BUFFER_MIN),
		maxf(_overtime_outer_extents.y * OVERTIME_START_BUFFER_RATIO,
			OVERTIME_START_BUFFER_MIN))
	_overtime_start_extents = _overtime_outer_extents + start_buffer
	_overtime_fire_outer_extents = _overtime_start_extents \
		+ Vector2.ONE * OVERTIME_FIRE_SAMPLE_MARGIN
	_overtime_outer_radius = maxf(
		_overtime_outer_extents.x, _overtime_outer_extents.y)
	_overtime_start_radius = maxf(
		_overtime_start_extents.x, _overtime_start_extents.y)
	_overtime_fire_outer_radius = maxf(
		_overtime_fire_outer_extents.x, _overtime_fire_outer_extents.y)

func _superellipse_distance(point: Vector2, extents: Vector2) -> float:
	if extents.x <= 0.001 or extents.y <= 0.001:
		return INF
	var normalized := Vector2(
		absf(point.x) / extents.x,
		absf(point.y) / extents.y)
	# The damage boundary is an axis-aligned footprint, matching the four floor
	# projections exactly. Authored boundary markers can still describe any
	# future map by establishing its usable X/Z limits.
	return maxf(normalized.x, normalized.y)

func _arena_markers_in_group(group_name: String) -> Array:
	var result: Array = []
	var arena_root := get_parent()
	if arena_root == null:
		return result
	for node in arena_root.find_children("*", "Marker3D", true, false):
		if node.is_in_group(group_name):
			result.append(node)
	return result

func _find_overtime_floor_y() -> float:
	var from := _overtime_center + Vector3.UP * 30.0
	var to := _overtime_center + Vector3.DOWN * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var excluded: Array[RID] = []
	for body in get_tree().get_nodes_in_group("gun") + players:
		if body is CollisionObject3D:
			excluded.append(body.get_rid())
	query.exclude = excluded
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
	return float(hit["position"].y) + 0.06 if hit.has("position") else _overtime_center.y - 0.75

func _start_local_overtime() -> void:
	var alive := players.filter(func(p): return is_instance_valid(p) and not p.is_eliminated)
	if alive.size() < 2:
		return
	_calculate_overtime_geometry()
	_begin_overtime(alive)
	round_state = "overtime"
	GameEvents.hud_notification.emit(_overtime_announcement())

func _start_online_overtime() -> void:
	if overtime_active or not NetworkManager.is_host():
		return
	var alive_ids: Array = []
	for actor_id in online_actor_state:
		var actor = NetworkManager.find_actor(int(actor_id))
		if actor != null and not actor.is_eliminated:
			alive_ids.append(int(actor_id))
	if alive_ids.size() < 2:
		return
	_calculate_overtime_geometry()
	_net_begin_overtime.rpc(
		alive_ids, _overtime_center, _overtime_outer_extents, _overtime_floor_y)
	online_announcement = _overtime_announcement()
	_broadcast_online_state()
	_clear_online_overtime_banner()

func _clear_online_overtime_banner() -> void:
	await get_tree().create_timer(1.5).timeout
	if overtime_active and online_combat_live:
		online_announcement = ""
		_broadcast_online_state()

@rpc("authority", "reliable", "call_local")
func _net_begin_overtime(alive_ids: Array, center: Vector3, outer_extents: Vector2,
		floor_y: float) -> void:
	_overtime_center = center
	_overtime_outer_extents = outer_extents
	_overtime_outer_radius = maxf(outer_extents.x, outer_extents.y)
	_overtime_floor_y = floor_y
	_configure_overtime_extents()
	var alive: Array = []
	for actor_id in alive_ids:
		var actor = NetworkManager.find_actor(int(actor_id))
		if actor != null:
			alive.append(actor)
	_begin_overtime(alive)

func _begin_overtime(alive: Array) -> void:
	round_state = "overtime"
	overtime_active = true
	overtime_elapsed = 0.0
	_online_overtime_sync_timer = 0.0
	_last_overtime_pulse_zone = -1
	_storm_exposure.clear()
	_storm_safe_time.clear()
	_storm_cumulative.clear()
	_disable_overtime_ground_spawns()
	if GameConfig.chaos_overtime_enabled:
		_begin_chaos_overtime(alive)
	else:
		_begin_standard_overtime(alive)
	_build_storm_fire()
	_pulse_overtime_players(alive)
	_last_overtime_pulse_zone = 0

func _overtime_announcement() -> String:
	return "OVERTIME - CHAOS GUNFIGHT" if GameConfig.chaos_overtime_enabled \
		else "OVERTIME - ONE GUN"

func _disable_overtime_ground_spawns() -> void:
	# Both overtime modes close every authored item/powerup/melee spawn. Standard
	# OT preserves held inventory, while marking it as non-respawning.
	for item in get_tree().get_nodes_in_group("item"):
		if bool(item.get("is_held")):
			if item.has_method("preserve_held_for_standard_overtime"):
				item.preserve_held_for_standard_overtime()
			elif "overtime_disabled" in item:
				item.overtime_disabled = true
			elif item.has_method("disable_for_overtime"):
				item.disable_for_overtime()
		elif item.has_method("disable_for_overtime"):
			item.disable_for_overtime()
	for powerup in get_tree().get_nodes_in_group("powerup"):
		if powerup.has_method("disable_for_overtime"):
			powerup.disable_for_overtime()
	for melee in get_tree().get_nodes_in_group("melee"):
		if melee.has_method("disable_for_overtime"):
			melee.disable_for_overtime()

func _begin_standard_overtime(alive: Array) -> void:
	for actor in alive:
		if actor.has_method("clear_overtime_protections"):
			actor.clear_overtime_protections()

func _begin_chaos_overtime(alive: Array) -> void:
	for actor in alive:
		if actor.has_method("clear_all_powerups"):
			actor.clear_all_powerups()
		actor.lethal_immunity_timer = 0.0
	for item in get_tree().get_nodes_in_group("item"):
		if item.has_method("disable_for_overtime"):
			item.disable_for_overtime()
	for trap in get_tree().get_nodes_in_group("deployed_trap"):
		trap.queue_free()
	for gun in get_tree().get_nodes_in_group("gun"):
		var holder = gun.get("player_ref")
		if holder != null:
			holder.holding_gun = false
		if bool(gun.get("is_overtime_gun")):
			gun.free()
		elif gun.has_method("disable_for_overtime"):
			gun.disable_for_overtime()
	for i in alive.size():
		var actor = alive[i]
		var gun = GunScene.instantiate()
		gun.name = "OvertimeGun%d" % i
		gun.is_overtime_gun = true
		gun.overtime_owner_id = int(actor.get("actor_id")) if "actor_id" in actor else i
		get_tree().current_scene.add_child(gun)
		gun.global_position = _overtime_center
		gun.spawn_position = _overtime_center
		gun._local_pickup(actor)

func _build_storm_fire() -> void:
	if _storm_wall != null and is_instance_valid(_storm_wall):
		_storm_wall.queue_free()
	var map_fire_intensity := clampf(float(
		get_parent().get_meta("overtime_fire_intensity_scale", 1.0)), 0.5, 1.5)
	var fire_intensity_scale := OVERTIME_FIRE_BASE_INTENSITY * map_fire_intensity
	_storm_wall = Node3D.new()
	_storm_wall.name = "OvertimeFireField"
	get_tree().current_scene.add_child(_storm_wall)
	_storm_wall.top_level = true
	_storm_wall.global_position = Vector3(
		_overtime_center.x, _overtime_center.y, _overtime_center.z)
	# The baked navigation surface is the authoritative playable floor on every
	# game-ready map. Rendering the burn on a copy of that mesh avoids Decal
	# receiver differences and avoids guessing terrain heights with loose tiles.
	if not _build_navigation_fire_surface(fire_intensity_scale):
		push_warning("Overtime fire could not find a baked NavigationRegion3D")
	_build_surface_flame_particles()
	_storm_fire_visual_radius = -1.0
	_update_storm_visual()

func _build_navigation_fire_surface(fire_intensity_scale: float) -> bool:
	_storm_surface_samples.clear()
	var navigation_region: NavigationRegion3D = null
	for candidate in get_parent().find_children(
			"*", "NavigationRegion3D", true, false):
		var region := candidate as NavigationRegion3D
		if region != null and region.navigation_mesh != null \
				and not region.navigation_mesh.get_vertices().is_empty():
			navigation_region = region
			break
	if navigation_region == null:
		return false
	var navigation_mesh := navigation_region.navigation_mesh
	var navigation_vertices := navigation_mesh.get_vertices()
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sample_keys := {}
	var triangle_count := 0
	for polygon_index in navigation_mesh.get_polygon_count():
		var polygon := navigation_mesh.get_polygon(polygon_index)
		if polygon.size() < 3:
			continue
		for triangle_index in range(1, polygon.size() - 1):
			var world_a: Vector3 = navigation_region.to_global(
				navigation_vertices[polygon[0]])
			var world_b: Vector3 = navigation_region.to_global(
				navigation_vertices[polygon[triangle_index]])
			var world_c: Vector3 = navigation_region.to_global(
				navigation_vertices[polygon[triangle_index + 1]])
			var normal := (world_b - world_a).cross(world_c - world_a).normalized()
			if normal.dot(Vector3.UP) < 0.0:
				var swap := world_b
				world_b = world_c
				world_c = swap
				normal = -normal
			for world_vertex in [world_a, world_b, world_c]:
				surface_tool.set_normal(normal)
				surface_tool.add_vertex(
					_storm_wall.to_local(world_vertex) + Vector3.UP * 0.055)
				_add_navigation_fire_sample(world_vertex, sample_keys)
			_add_navigation_fire_sample(
				(world_a + world_b + world_c) / 3.0, sample_keys)
			triangle_count += 1
	if triangle_count == 0:
		return false
	_storm_floor_mesh = MeshInstance3D.new()
	_storm_floor_mesh.name = "NavigationFireFloor"
	_storm_floor_mesh.mesh = surface_tool.commit()
	_storm_floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_storm_floor_material = ShaderMaterial.new()
	var fire_shader := Shader.new()
	fire_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

uniform vec2 fire_center;
uniform vec2 safe_extents;
uniform vec2 fire_outer_extents;
uniform float emission_strength = 0.18;
varying vec3 fire_world_position;

void vertex() {
	fire_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 offset = abs(fire_world_position.xz - fire_center);
	if (any(greaterThan(offset, fire_outer_extents))) {
		discard;
	}
	if (safe_extents.x > 0.001 && safe_extents.y > 0.001
			&& all(lessThanEqual(offset, safe_extents))) {
		discard;
	}
	float wave_a = sin(fire_world_position.x * 2.7
		+ fire_world_position.z * 1.9 + TIME * 2.8);
	float wave_b = sin(fire_world_position.x * -1.4
		+ fire_world_position.z * 3.2 - TIME * 2.1);
	float heat = clamp(0.55 + wave_a * 0.24 + wave_b * 0.18, 0.0, 1.0);
	vec3 fire_color = mix(vec3(0.40, 0.008, 0.0),
		vec3(1.0, 0.18, 0.008), heat);
	ALBEDO = fire_color;
	EMISSION = fire_color * emission_strength;
	// Keep the arena readable through the burn layer. The separate upright
	// particles carry the brightest part of the fire effect.
	ALPHA = mix(0.44, 0.62, heat);
}
"""
	_storm_floor_material.shader = fire_shader
	_storm_floor_material.set_shader_parameter(
		"fire_center", Vector2(_overtime_center.x, _overtime_center.z))
	_storm_floor_material.set_shader_parameter(
		"fire_outer_extents", _overtime_fire_outer_extents)
	_storm_floor_material.set_shader_parameter(
		"emission_strength", clampf(0.04 + fire_intensity_scale, 0.08, 0.20))
	_storm_floor_mesh.material_override = _storm_floor_material
	_storm_wall.add_child(_storm_floor_mesh)
	return true

func _add_navigation_fire_sample(world_position: Vector3, sample_keys: Dictionary) -> void:
	var offset := Vector2(
		world_position.x - _overtime_center.x,
		world_position.z - _overtime_center.z)
	if _superellipse_distance(offset, _overtime_fire_outer_extents) > 1.0:
		return
	var key := Vector3i(
		roundi(world_position.x * 2.0),
		roundi(world_position.y * 2.0),
		roundi(world_position.z * 2.0))
	if sample_keys.has(key):
		return
	sample_keys[key] = true
	_storm_surface_samples.append({
		"offset": offset,
		"particle_position": _storm_wall.to_local(world_position)
			+ Vector3.UP * 0.10,
		"normal": Vector3.UP,
	})

func _build_surface_flame_particles() -> void:
	_storm_flame_particles = CPUParticles3D.new()
	_storm_flame_particles.name = "SurfaceFlameParticles"
	_storm_flame_particles.amount = 1
	_storm_flame_particles.lifetime = 0.72
	_storm_flame_particles.lifetime_randomness = 0.20
	_storm_flame_particles.local_coords = true
	_storm_flame_particles.emission_shape = \
		CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
	_storm_flame_particles.direction = Vector3.UP
	_storm_flame_particles.spread = 20.0
	_storm_flame_particles.initial_velocity_min = 2.0
	_storm_flame_particles.initial_velocity_max = 5.5
	_storm_flame_particles.gravity = Vector3(0.0, 1.3, 0.0)
	_storm_flame_particles.scale_amount_min = 0.65
	_storm_flame_particles.scale_amount_max = 1.35
	var flame_gradient := Gradient.new()
	flame_gradient.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	flame_gradient.colors = PackedColorArray([
		Color(1.0, 0.88, 0.18, 0.95),
		Color(1.0, 0.18, 0.015, 0.9),
		Color(0.28, 0.005, 0.0, 0.0),
	])
	_storm_flame_particles.color_ramp = flame_gradient
	var flame_mesh := QuadMesh.new()
	flame_mesh.size = Vector2(0.55, 1.1)
	var flame_material := StandardMaterial3D.new()
	flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flame_material.vertex_color_use_as_albedo = true
	flame_material.albedo_texture = _build_flame_particle_texture()
	flame_mesh.material = flame_material
	_storm_flame_particles.mesh = flame_mesh
	_storm_flame_particles.emitting = false
	_storm_wall.add_child(_storm_flame_particles)

func _build_flame_particle_texture() -> ImageTexture:
	const TEXTURE_SIZE := 64
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for pixel_y in TEXTURE_SIZE:
		for pixel_x in TEXTURE_SIZE:
			var u := (float(pixel_x) + 0.5) / TEXTURE_SIZE
			var v := (float(pixel_y) + 0.5) / TEXTURE_SIZE
			var half_width := lerpf(0.045, 0.43, pow(v, 0.72))
			var side_alpha := clampf(
				(half_width - absf(u - 0.5)) * 18.0, 0.0, 1.0)
			var top_fade := clampf(v / 0.16, 0.0, 1.0)
			var bottom_fade := clampf((1.0 - v) / 0.12, 0.0, 1.0)
			var flicker := 0.82 + sin(u * 37.0 + v * 29.0) * 0.18
			var alpha := side_alpha * top_fade * bottom_fade * flicker
			var heat := clampf(v * 1.25, 0.0, 1.0)
			image.set_pixel(pixel_x, pixel_y, Color(
				1.0, lerpf(0.12, 0.92, heat), 0.015, alpha))
	return ImageTexture.create_from_image(image)

func _update_navigation_fire_visual(inner_extents: Vector2) -> void:
	var visual_inner_extents := Vector2(
		maxf(inner_extents.x - OVERTIME_FIRE_VISUAL_LEAD, 0.0),
		maxf(inner_extents.y - OVERTIME_FIRE_VISUAL_LEAD, 0.0))
	if _storm_floor_material != null:
		_storm_floor_material.set_shader_parameter(
			"safe_extents", visual_inner_extents)
	var particle_points := PackedVector3Array()
	var particle_normals := PackedVector3Array()
	for sample in _storm_surface_samples:
		var offset: Vector2 = sample["offset"]
		if not _is_offset_in_fire(offset, visual_inner_extents):
			continue
		particle_points.append(sample["particle_position"])
		particle_normals.append(sample["normal"])
	if _storm_flame_particles == null:
		return
	var was_emitting := _storm_flame_particles.emitting
	if particle_points.is_empty():
		_storm_flame_particles.emitting = false
		return
	# Assign valid unsafe-floor points before enabling the emitter. Enabling a
	# directed-points emitter with an empty point array produces one fallback
	# particle at local origin, which is the otherwise-safe arena center.
	_storm_flame_particles.emission_points = particle_points
	_storm_flame_particles.emission_normals = particle_normals
	_storm_flame_particles.amount = clampi(
		particle_points.size() * 8, 192, 2600)
	if not was_emitting:
		_storm_flame_particles.emitting = true
		_storm_flame_particles.restart()

func _fire_visual_alpha_at_world_position(world_position: Vector3) -> float:
	var offset := Vector2(
		world_position.x - _overtime_center.x,
		world_position.z - _overtime_center.z)
	if _superellipse_distance(offset, _overtime_fire_outer_extents) > 1.0:
		return 0.0
	var inner_extents := _current_storm_extents()
	var visual_inner_extents := Vector2(
		maxf(inner_extents.x - OVERTIME_FIRE_VISUAL_LEAD, 0.0),
		maxf(inner_extents.y - OVERTIME_FIRE_VISUAL_LEAD, 0.0))
	return 0.82 if _is_offset_in_fire(offset, visual_inner_extents) else 0.0

func _overtime_zone_index() -> int:
	if overtime_elapsed <= OVERTIME_OPENING_APPROACH_TIME:
		return 0
	var phase_elapsed := overtime_elapsed - OVERTIME_OPENING_APPROACH_TIME
	return mini(
		floori(phase_elapsed / OVERTIME_ZONE_DURATION),
		OVERTIME_MOVEMENT_PHASE_COUNT)

func _current_storm_radius() -> float:
	var extents := _current_storm_extents()
	return maxf(extents.x, extents.y)

func _current_storm_extents() -> Vector2:
	if _overtime_outer_extents.x <= 0.0 or _overtime_outer_extents.y <= 0.0:
		_configure_overtime_extents()
	if overtime_elapsed < OVERTIME_OPENING_APPROACH_TIME:
		return _overtime_start_extents.lerp(
			_overtime_outer_extents,
			clampf(overtime_elapsed / OVERTIME_OPENING_APPROACH_TIME, 0.0, 1.0))
	# Once the opening fire reaches the play-area edge, it never pauses and
	# reaches full engulfment at the configured two-minute OT mark.
	var close_duration := \
		OVERTIME_ZONE_DURATION * float(OVERTIME_MOVEMENT_PHASE_COUNT)
	var progress := clampf(
		(overtime_elapsed - OVERTIME_OPENING_APPROACH_TIME) / close_duration,
		0.0, 1.0)
	return _overtime_outer_extents * (1.0 - progress)

func _update_storm_visual() -> void:
	if _storm_wall != null and is_instance_valid(_storm_wall):
		var inner_extents := _current_storm_extents()
		var radius := maxf(inner_extents.x, inner_extents.y)
		if _storm_visual_radius < 0.0 or absf(radius - _storm_visual_radius) >= 0.05:
			_storm_visual_radius = radius
		if _storm_fire_visual_radius < 0.0 \
				or absf(radius - _storm_fire_visual_radius) >= OVERTIME_FIRE_VISUAL_UPDATE_STEP:
			_storm_fire_visual_radius = radius
			_update_navigation_fire_visual(inner_extents)
	var zone := _overtime_zone_index()
	if zone != _last_overtime_pulse_zone:
		var alive: Array = []
		if NetworkManager.is_online():
			for actor_id in online_actor_state:
				var actor = NetworkManager.find_actor(int(actor_id))
				if actor != null and not actor.is_eliminated:
					alive.append(actor)
		else:
			alive = players.filter(func(p): return is_instance_valid(p) and not p.is_eliminated)
		_pulse_overtime_players(alive)
		_last_overtime_pulse_zone = zone

func _pulse_overtime_players(alive: Array) -> void:
	for actor in alive:
		if actor.has_method("show_overtime_pulse"):
			actor.show_overtime_pulse(1.0)

func _current_fire_exposure_limit() -> float:
	var base := maxf(float(GameConfig.overtime_fire_exposure_time), 0.1)
	# Preserve the agreed three-second minimum from zone 3 onward. If a host
	# intentionally selects less than three seconds, that stricter value wins.
	var floor := minf(base, 3.0)
	return maxf(base - float(_overtime_zone_index()), floor)

func _is_position_in_fire(world_position: Vector3) -> bool:
	# Deliberately ignore Y. A rooftop, bridge, jump pad or other elevation over
	# burning ground is still inside the fire if its horizontal position is.
	var offset := Vector2(
		world_position.x - _overtime_center.x,
		world_position.z - _overtime_center.z)
	return _is_offset_in_fire(offset, _current_storm_extents())

func _is_offset_in_fire(offset: Vector2, safe_extents: Vector2) -> bool:
	if safe_extents.x <= 0.01 or safe_extents.y <= 0.01:
		return true
	return _superellipse_distance(offset, safe_extents) > 1.0

func get_fire_warning(actor) -> Dictionary:
	var inactive := {"active": false, "remaining": 0.0, "limit": 0.0}
	if not overtime_active or actor == null or not is_instance_valid(actor):
		return inactive
	if bool(actor.get("is_eliminated")):
		return inactive
	var online_actor: bool = NetworkManager.is_online() and "actor_id" in actor
	var key = int(actor.actor_id) if online_actor else actor
	var active := _is_position_in_fire(actor.global_position)
	if not active:
		return inactive
	var limit := _current_fire_exposure_limit()
	var exposure := float(_storm_exposure.get(key, 0.0))
	return {
		"active": true,
		"remaining": maxf(limit - exposure, 0.0),
		"limit": limit,
	}

func _update_overtime_damage(delta: float, online: bool,
		can_eliminate := true) -> void:
	var limit := _current_fire_exposure_limit()
	var alive: Array = []
	if online:
		for actor_id in online_actor_state:
			var actor = NetworkManager.find_actor(int(actor_id))
			if actor != null and not actor.is_eliminated:
				alive.append(actor)
	else:
		alive = players.filter(func(p): return is_instance_valid(p) and not p.is_eliminated)
	for actor in alive:
		var key = int(actor.actor_id) if online else actor
		var outside := _is_position_in_fire(actor.global_position)
		if outside:
			_storm_safe_time[key] = 0.0
			_storm_exposure[key] = float(_storm_exposure.get(key, 0.0)) + delta
			_storm_cumulative[key] = float(_storm_cumulative.get(key, 0.0)) + delta
			if can_eliminate and float(_storm_exposure[key]) >= limit:
				if online:
					var entry: Dictionary = online_actor_state[int(actor.actor_id)]
					entry["storm_time"] = float(_storm_cumulative[key])
					online_actor_state[int(actor.actor_id)] = entry
					server_eliminate(int(actor.actor_id), -1, online_round_epoch, "FIRE", "fire", "environment")
				else:
					_elimination_time_ms[actor] = Time.get_ticks_msec()
					actor.eliminate("THE FIRE", "FIRE", "environment")
		elif float(_storm_exposure.get(key, 0.0)) > 0.0:
			_storm_safe_time[key] = float(_storm_safe_time.get(key, 0.0)) + delta
			if float(_storm_safe_time[key]) >= 1.0:
				_storm_exposure[key] = 0.0
				_storm_safe_time[key] = 0.0

func get_round_timer_text() -> String:
	if overtime_active:
		return "OT  %s" % _format_clock(floori(overtime_elapsed))
	if GameConfig.round_time_limit <= 0.0:
		return ""
	return _format_clock(ceili(maxf(GameConfig.round_time_limit - round_elapsed, 0.0)))

func _format_clock(total_seconds: int) -> String:
	total_seconds = maxi(total_seconds, 0)
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]

func _format_time_ms(value: float) -> String:
	var total_ms := maxi(roundi(value * 1000.0), 0)
	var minutes := total_ms / 60000
	var seconds := (total_ms / 1000) % 60
	var millis := total_ms % 1000
	return "%02d:%02d.%03d" % [minutes, seconds, millis]

func _update_status_label():
	var alive_count = 0
	for p in players:
		if not p.is_eliminated:
			alive_count += 1

	var hud = get_node_or_null("../CanvasLayer/MatchHUD")
	if hud != null and hud.has_method("update_match_state"):
		hud.update_match_state(round_number, set_number, alive_count, players.size())
		if hud.has_method("update_round_timer"):
			hud.update_round_timer(get_round_timer_text(), overtime_active)
		if hud.has_method("update_fire_warning"):
			hud.update_fire_warning(get_fire_warning(get_node_or_null("../player1")))

	var hud2 = get_node_or_null("../CanvasLayer/MatchHUD2")
	if hud2 != null and hud2.has_method("update_match_state"):
		hud2.update_match_state(round_number, set_number, alive_count, players.size())
		if hud2.has_method("update_round_timer"):
			hud2.update_round_timer(get_round_timer_text(), overtime_active)
		if hud2.has_method("update_fire_warning"):
			hud2.update_fire_warning(get_fire_warning(get_node_or_null("../player2")))

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
			var overtime_winner = _select_local_overtime_winner(previous_alive) if overtime_active else null
			if overtime_winner != null:
				_end_round([overtime_winner])
			else:
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
			var overtime_winner = _select_local_overtime_winner(previous_alive) if overtime_active else null
			if overtime_winner != null:
				_end_round([overtime_winner])
			else:
				_end_round(previous_alive, true)
			previous_alive = alive
			return

	if alive_teams.size() <= 1:
		_end_round(alive)
	previous_alive = alive

func _select_local_overtime_winner(candidates: Array):
	var remaining := candidates.filter(func(p): return is_instance_valid(p))
	if remaining.is_empty():
		return null
	var latest := -1
	for p in remaining:
		latest = maxi(latest, int(_elimination_time_ms.get(p, -1)))
	remaining = remaining.filter(func(p): return int(_elimination_time_ms.get(p, -1)) == latest)
	if remaining.size() == 1:
		return remaining[0]
	var least_storm := INF
	for p in remaining:
		least_storm = minf(least_storm, float(_storm_cumulative.get(p, 0.0)))
	remaining = remaining.filter(func(p):
		return is_equal_approx(float(_storm_cumulative.get(p, 0.0)), least_storm))
	if remaining.size() == 1:
		return remaining[0]
	var most_kills := -1
	for p in remaining:
		most_kills = maxi(most_kills, int(_round_kills.get(p, 0)))
	remaining = remaining.filter(func(p): return int(_round_kills.get(p, 0)) == most_kills)
	return remaining[0] if remaining.size() == 1 else null

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
		var winner_text: String = winner.get_display_name() + " wins the round!"
		if overtime_active:
			winner_text += "\nOT " + _format_time_ms(overtime_elapsed)
		_set_round_label_text(winner_text)
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
	for p in players:
		_round_kills[p] = 0
	_assign_spawn_transforms()
	for p in players:
		p.respawn(spawn_transforms[p])
	for w in get_tree().get_nodes_in_group("weapon"):
		w.reset_to_spawn()
	_apply_gun_spawn_mode()
	_spawn_marker_melee()
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

func _spawn_marker_melee() -> void:
	for node in get_tree().get_nodes_in_group("marker_melee_spawned"):
		node.free()
	var markers := get_tree().get_nodes_in_group("melee_spawn_point")
	if markers.is_empty():
		push_warning("RoundManager: map has no melee_spawn_point markers.")
		return
	var marker = markers[randi() % markers.size()]
	var melee = MeleeScene.instantiate()
	melee.name = "RoundMelee"
	melee.add_to_group("marker_melee_spawned", true)
	get_tree().current_scene.add_child(melee)
	melee.global_transform = marker.global_transform
	melee.spawn_position = melee.global_position
	melee.spawn_rotation = melee.global_rotation

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
