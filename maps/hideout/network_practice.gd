extends "res://maps/playpen/playpen_manager.gd"
## Host authority for one shared Hideout. Normal matches retain their manager.
signal local_player_ready(actor: CharacterBody3D)
const Space = preload("res://maps/hideout/playpen_space.gd")
const ScrapSpace = preload("res://maps/hideout/scrap_space.gd")
const LocalPen = preload("res://maps/hideout/playpen.gd")
var lab: Node3D
var training: Node
var scrap: Node
var toss: Node
var cleanup: Node
var memberships: Dictionary = {}
var pending_holds: Array = []
var pending_actor_state: Dictionary = {}
const ACTOR_LOAN_FIELDS := ["dash_charges","stamina","extra_dash_charge","active_powerup_order","speed_surge_timer","silent_steps_timer","reach_timer","fast_hands_timer","second_wind_ready","sticky_hands_timer","sticky_hands_cooldown_timer","melee_disarm_shields","double_jump_shoes_active"]
var effect_lifetimes: Dictionary = {}
var local_bound := false
var snapshot_received := false
var world_check_left := 0.0
var sparring_mode := "off"
var deaths: Dictionary = {}
var departing := false

func _ready() -> void:
	call_deferred("_initialize_hideout")

func _initialize_hideout() -> void:
	lab = get_parent()
	practice_mode = true
	round_state = "live"
	online_combat_live = true
	online_round_epoch = NetworkManager.pending_match_id + 1
	online_match_over = false
	online_announcement = ""
	NetworkManager.local_match_role = "playpen_hosting" if NetworkManager.is_dedicated_server() else "playpen_loading"
	cleanup = LocalPen.new()
	add_child(cleanup)
	cleanup.set_physics_process(false)
	for path in GameConfig.ITEM_SCENES.values():
		var source=load(path).instantiate()
		if "deployed_scene" in source and source.deployed_scene!=null:
			effect_lifetimes[source.deployed_scene.resource_path]=float(source.deployed_lifetime)
		source.free()
	_setup_practice_network()
	training = load("res://maps/hideout/network_training.gd").new()
	training.name = "Training"
	add_child(training)
	training.setup(lab)
	scrap = load("res://maps/hideout/network_scrap.gd").new()
	scrap.name = "Scrap"
	add_child(scrap)
	scrap.setup(lab)
	toss = load("res://maps/hideout/network_toss.gd").new()
	toss.name = "Toss"
	add_child(toss)
	toss.setup(lab)
	NetworkManager.playpen_members_changed.connect(_reconcile_playpen_members)
	NetworkManager.lobby_changed.connect(_roster_changed)
	NetworkManager.prelaunch_countdown_changed.connect(_on_prelaunch_changed)
	get_tree().node_added.connect(_on_world_node_added)
	if NetworkManager.is_host():
		_spawn_fixed_armories()
		snapshot_received = true
	if not NetworkManager.is_dedicated_server(): NetworkManager.report_hideout_scene_ready()
	else:
		lab.station.open_arrivals()
		_reconcile_playpen_members()

func _create_online_human() -> Node:
	return preload("res://maps/hideout/network_actor.tscn").instantiate()

func _net_spawn_player(data: Dictionary) -> Node:
	var actor := super._net_spawn_player(data)
	actor.ready.connect(_actor_ready.bind(actor),CONNECT_ONE_SHOT)
	return actor

func _actor_ready(actor: CharacterBody3D) -> void:
	if actor.owner_peer_id == NetworkManager.local_id() and not NetworkManager.is_dedicated_server():
		local_bound = true
		local_player_ready.emit(actor)

func _practice_spawn_transform(_actor_id: int) -> Transform3D:
	if NetworkManager.is_host() and _actor_id==NetworkManager.local_actor_id(): return lab.session_spawn
	return Transform3D(Basis.IDENTITY,lab.spawn.position + Vector3((_actor_id%3-1)*1.8,0,-floori(_actor_id/3.0)*1.8))

func _respawn_practice_actor(actor_id: int, generation: int) -> void:
	await get_tree().create_timer(PLAYPEN_RESPAWN_TIME).timeout
	if not NetworkManager.is_host() or generation != int(_practice_respawn_generation.get(actor_id,0)) or not online_actor_state.has(actor_id): return
	online_actor_state[actor_id]["alive"] = true
	online_actor_state[actor_id]["eliminated_at_ms"] = -1
	NetworkManager.broadcast_match_rpc(self,&"_net_respawn",[actor_id,Space.RESPAWN,0.0])
	_broadcast_online_state()

func _roster_changed() -> void:
	if NetworkManager.is_host() and not departing:
		for actor in lab.get_node("NetPlayers").get_children():
			if not NetworkManager.peers.has(actor.owner_peer_id): clear_inventory(actor)
		_reconcile_playpen_members()
	training.refresh_roster()

func _process(delta: float) -> void:
	if lab == null or departing: return
	for id in pending_actor_state.keys():
		var actor=NetworkManager.find_actor(int(id))
		if actor==null: continue
		for key in ACTOR_LOAN_FIELDS: actor.set(key,pending_actor_state[id][key])
		pending_actor_state.erase(id)
	for hold in pending_holds.duplicate():
		var actor = NetworkManager.find_actor(int(hold.actor))
		if actor == null: continue
		var obj = get_node_or_null(NodePath(str(hold.path)))
		if obj != null and obj.has_method("_net_do_pickup"): obj._net_do_pickup(int(hold.actor))
		pending_holds.erase(hold)
	world_check_left -= delta
	if world_check_left > 0: return
	world_check_left = 0.1
	if not NetworkManager.is_host(): return
	_monitor_gun_refills()
	for actor in lab.get_node("NetPlayers").get_children():
		sync_actor(actor)
		if actor.position.y < -8 or not actor.position.is_finite():
			clear_inventory(actor)
			NetworkManager.broadcast_match_rpc(self,&"_net_recover_playpen_actor",[actor.actor_id,Space.RESPAWN,0.0])

func contains_actor(actor: Node3D) -> bool:
	if departing or not is_instance_valid(actor) or actor.is_eliminated: return false
	if ScrapSpace.in_room(actor.global_position): return is_instance_valid(scrap) and scrap.can_fight(actor)
	return Space.contains(actor.global_position)

func contains_object(obj: Node3D) -> bool:
	return is_instance_valid(obj) and not obj.is_queued_for_deletion() and not obj.get_meta("pen_retired",false) and Space.contains(obj.global_position)

func can_affect(a: Node, b: Node) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(b): return false
	if not contains_actor(a) or not contains_actor(b): return false
	return ScrapSpace.in_room(a.global_position) == ScrapSpace.in_room(b.global_position)

func sync_actor(actor: CharacterBody3D) -> void:
	if not NetworkManager.is_host(): return
	var current := "scrap" if ScrapSpace.in_room(actor.global_position) else "pen" if Space.contains(actor.global_position) else "hall"
	var before: String = memberships.get(actor.actor_id,"hall")
	if before != current:
		memberships[actor.actor_id] = current
		clear_inventory(actor)

func clear_inventory(actor: CharacterBody3D) -> void:
	if not NetworkManager.is_host() or not is_instance_valid(actor): return
	NetworkManager.broadcast_match_rpc(self,&"_clear_actor_gear",[actor.actor_id])

@rpc("authority","reliable","call_local")
func _clear_actor_gear(actor_id: int) -> void:
	var actor = NetworkManager.find_actor(actor_id)
	if actor == null: return
	cleanup.clear_inventory(actor)

func server_eliminate(victim_id: int, killer_id: int, epoch: int = -1, weapon_icon: String = "GUN", feedback_kind: String = "gun", lethal_kind: String = "weapon") -> void:
	var victim = NetworkManager.find_actor(victim_id)
	var attacker = NetworkManager.find_actor(killer_id)
	if not contains_actor(victim) or (attacker != null and attacker != victim and not can_affect(attacker,victim)): return
	if is_instance_valid(scrap) and scrap.is_fighter_id(victim_id):
		if not can_accept_online_combat(epoch): return
		if online_actor_state.has(victim_id):
			online_actor_state[victim_id]["alive"] = false
			online_actor_state[victim_id]["eliminated_at_ms"] = Time.get_ticks_msec()
		NetworkManager.broadcast_match_rpc(self,&"_net_eliminate",[victim_id,killer_id,weapon_icon,lethal_kind])
		scrap.finish_elimination(victim_id)
		return
	super.server_eliminate(victim_id,killer_id,epoch,weapon_icon,feedback_kind,lethal_kind)

func server_apply_online_item_effect(effect: String, target_id: int, data: Dictionary = {}) -> void:
	if not contains_actor(NetworkManager.find_actor(target_id)): return
	super.server_apply_online_item_effect(effect,target_id,data)

func _server_route_online_gun_action(sender_id: int, action: String, epoch: int, direction: Vector3, gun_instance_name: String = "", fire_origin: Vector3 = Vector3.ZERO, has_fire_origin := false) -> void:
	var actor = NetworkManager.find_actor(sender_id)
	if not contains_actor(actor): return
	if action == "pickup":
		var gun = _online_loose_gun(gun_instance_name)
		if gun == null or ScrapSpace.in_room(gun.global_position) != ScrapSpace.in_room(actor.global_position): return
	super._server_route_online_gun_action(sender_id,action,epoch,direction,gun_instance_name,fire_origin,has_fire_origin)

func _spawn_fixed_armories() -> void:
	_next_online_melee_candidate_id = 10000
	_next_online_item_id = 20000
	for bay in range(2):
		for slot in range(23):
			var at := Space.supply_position(bay,slot)
			var id := bay*100+slot
			if slot < 2:
				_gun_spawn_positions[id] = at
				_gun_spawn_generations[id] = 0
				_spawn_playpen_gun(id,0,at)
			elif slot < 7:
				var weapon: String = PLAYPEN_WEAPONS[slot-2]
				if GameConfig.is_melee_weapon_enabled(weapon):
					_spawn_online_melee({"candidate_id":id,"position":at,"identity":{"weapon_name":weapon,"effect":"normal"},"playpen_weapon_name":weapon})
			elif slot < 16:
				var item: String = PLAYPEN_ITEMS[slot-7]
				if GameConfig.is_item_enabled(item): _spawn_online_item({"item_id":id,"spawn_id":id,"item_type":item,"position":at})
			else:
				var power: String = PLAYPEN_POWERUPS[slot-16]
				if power in GameConfig.enabled_powerup_types(): _spawn_online_powerup({"powerup_id":id,"power_type":power,"position":at})

func _on_world_node_added(node: Node) -> void:
	if not lab.is_ancestor_of(node): return
	if node is RigidBody3D or (node is Node3D and ("owner_player" in node or "online_powerup_id" in node)):
		var id := node.get_instance_id()
		if cleanup.objects.has(id): return
		cleanup.objects[id]={"ref":weakref(node)}
		if not node is RigidBody3D and not node.has_meta("hideout_effect_expires"):
			node.set_meta("hideout_effect_expires",Time.get_ticks_msec()+int(float(effect_lifetimes.get(node.scene_file_path,12.0))*1000))
		node.tree_exited.connect(cleanup._object_exited.bind(id),CONNECT_DEFERRED)
		for key in ["owner_player","shooter","_thrower"]:
			if key in node:
				var owner_actor = node.get(key)
				if is_instance_valid(owner_actor) and scrap.is_fighter(owner_actor): node.set_meta("scrap_epoch",scrap.epoch)
		if node is RigidBody3D:
			node.collision_mask |= Space.BARRIER_LAYER
			node.body_entered.connect(cleanup._ordnance_contact.bind(node))
			node.ready.connect(_ground_initial.bind(node),CONNECT_ONE_SHOT)

func _ground_initial(obj: RigidBody3D) -> void:
	if not is_instance_valid(obj): return
	for label in obj.find_children("*","Label3D",true,false):
		label.no_depth_test = false
		label.visibility_range_end = 12.0
	_ground_loose_stock.call_deferred(obj)

func _ground_loose_stock(obj: Node3D) -> void:
	if not is_instance_valid(obj) or obj.is_queued_for_deletion(): return
	if "is_held" in obj and obj.is_held: return
	if obj.is_in_group("gun") or obj.is_in_group("melee") or obj.is_in_group("online_item"):
		if obj.freeze: cleanup._ground_stock(obj)

func prepare_for_match() -> void:
	if NetworkManager.is_host():
		scrap.cancel_round("MATCH STARTING")
		training.cancel_all()
		for actor in lab.get_node("NetPlayers").get_children(): clear_inventory(actor)
	departing = true
	training.set_physics_process(false)
	scrap.set_process(false)
	toss.set_physics_process(false)
	online_combat_live = false

func _on_prelaunch_changed(active: bool, _seconds: int) -> void:
	if active:
		scrap.cancel_round("MATCH STARTING")
		training.cancel_all()
		for actor in lab.get_node("NetPlayers").get_children(): clear_inventory(actor)

func request_recover() -> void:
	if NetworkManager.is_host(): _recover_actor(NetworkManager.local_actor_id())
	else: _request_recover.rpc_id(1)

@rpc("any_peer","reliable")
func _request_recover() -> void:
	if NetworkManager.is_host(): _recover_actor(NetworkManager.actor_id_for_peer(multiplayer.get_remote_sender_id()))

func _recover_actor(id: int) -> void:
	var actor = NetworkManager.find_actor(id)
	if actor == null: return
	clear_inventory(actor)
	if scrap.is_fighter_id(id): scrap.cancel_round("FIGHTER LEFT")
	training.cancel_runner(id)
	NetworkManager.broadcast_match_rpc(self,&"_net_recover_playpen_actor",[id,lab.spawn.position,0.0])

func set_sparring_mode(_mode: String) -> void:
	pass

func server_sync_hideout(peer_id: int) -> void:
	# Snapshot before admitting the peer to the scene-bound event stream.
	_receive_world.rpc_id(peer_id,_capture_world())
	training.send_snapshot(peer_id)
	scrap.send_snapshot(peer_id)
	toss.send_snapshot(peer_id)

func _capture_world() -> Dictionary:
	var rows: Array = []
	for group in ["gun","online_spawned_melee","online_item","online_powerup"]:
		for obj in get_tree().get_nodes_in_group(group):
			if not lab.is_ancestor_of(obj) or obj.is_queued_for_deletion(): continue
			var row := {"group":group,"name":str(obj.name),"position":obj.global_position,"rotation":obj.global_rotation,"visible":obj.visible,"scrap":int(obj.get_meta("scrap_epoch",-1))}
			if group == "gun":
				row["spawn_id"] = obj.playpen_spawn_id
				row["holder"] = obj.player_ref.actor_id if is_instance_valid(obj.player_ref) and obj.is_held else -1
			elif group == "online_spawned_melee":
				row["id"] = obj.online_candidate_id
				row["identity"] = {"weapon_name":obj.weapon_data.weapon_name,"effect":obj.effect_category}
				row["holder"] = obj.player_ref.actor_id if is_instance_valid(obj.player_ref) and obj.is_held else -1
			elif group == "online_item":
				row["id"] = obj.online_item_id
				row["type"] = obj.item_type
				row["holder"] = obj.player_ref.actor_id if is_instance_valid(obj.player_ref) and obj.is_held else -1
			else:
				row["id"] = obj.online_powerup_id
				row["type"] = obj.power_type
				row["collected"] = obj.collected
			if obj is RigidBody3D:
				row["frozen"]=obj.freeze
				row["velocity"]=obj.linear_velocity
				row["spin"]=obj.angular_velocity
				row["flying"]=bool(obj.get("is_in_flight")) if "is_in_flight" in obj else false
			if group=="gun":
				row["ready"]=obj.can_fire
				row["reload"]=obj.get_node("ReloadTimer").time_left
			elif group=="online_item":
				row["owner"]=obj.online_owner_actor_id
				row["forward"]=obj.deployment_forward
				row["cooking"]=obj._cook_active
				row["fuse"]=obj._cook_remaining
			rows.append(row)
	var effects: Array=[]
	for obj in get_tree().get_nodes_in_group("online_deployed"):
		if not lab.is_ancestor_of(obj) or obj.is_queued_for_deletion(): continue
		var remaining:=maxf(0.01,float(int(obj.get_meta("hideout_effect_expires",Time.get_ticks_msec()+100))-Time.get_ticks_msec())/1000.0)
		effects.append({"path":obj.scene_file_path,"id":int(obj.get_meta("online_deployed_id",-1)),"owner":int(obj.get_meta("online_owner_actor_id",-1)),"transform":obj.global_transform,"remaining":remaining,"scrap":int(obj.get_meta("scrap_epoch",-1)),"forward":obj.get("initial_forward") if "initial_forward" in obj else Vector3.FORWARD})
	var loans: Dictionary={}
	for actor in lab.get_node("NetPlayers").get_children():
		var state: Dictionary={}
		for key in ACTOR_LOAN_FIELDS: state[key]=actor.get(key)
		loans[actor.actor_id]=state
	return {"rows":rows,"effects":effects,"loans":loans,"state":_online_state_snapshot()}

@rpc("authority","reliable")
func _receive_world(snapshot: Dictionary) -> void:
	if snapshot_received: return
	snapshot_received = true
	for row in snapshot.get("rows",[]):
		var obj: Node3D
		match str(row.group):
			"gun":
				_spawn_playpen_gun(int(row.spawn_id),0,row.position)
				obj = lab.get_child(lab.get_child_count()-1)
				obj.name = str(row.name)
			"online_spawned_melee":
				_spawn_online_melee({"candidate_id":row.id,"position":row.position,"rotation":row.rotation,"identity":row.identity})
				obj = _online_melee_by_id(int(row.id))
			"online_item":
				_spawn_online_item({"item_id":row.id,"spawn_id":row.id,"item_type":row.type,"position":row.position,"rotation":row.rotation})
				obj = _online_item(int(row.id))
			"online_powerup":
				_spawn_online_powerup({"powerup_id":row.id,"power_type":row.type,"position":row.position})
				obj = _online_powerup(int(row.id))
				if row.collected: obj.collected=true; obj.hide()
		if obj == null: continue
		obj.set_meta("scrap_epoch",int(row.scrap))
		obj.visible = bool(row.visible)
		if obj is RigidBody3D:
			obj.freeze=bool(row.get("frozen",true))
			obj.linear_velocity=row.get("velocity",Vector3.ZERO)
			obj.angular_velocity=row.get("spin",Vector3.ZERO)
			if "is_in_flight" in obj: obj.is_in_flight=bool(row.get("flying",false))
		if row.group=="gun":
			obj.can_fire=bool(row.get("ready",true))
			if float(row.get("reload",0.0))>0: obj.get_node("ReloadTimer").start(float(row.reload))
		elif row.group=="online_item":
			obj.online_owner_actor_id=int(row.get("owner",-1))
			obj.deployment_forward=row.get("forward",Vector3.FORWARD)
			obj._cook_active=bool(row.get("cooking",false))
			obj._cook_remaining=float(row.get("fuse",0.0))
		if int(row.get("holder",-1)) >= 0: pending_holds.append({"path":get_path_to(obj),"actor":row.holder})
	pending_actor_state=snapshot.get("loans",{}).duplicate(true)
	for effect in snapshot.get("effects",[]): _restore_effect(effect)
	_net_apply_online_state(snapshot.get("state",{}))

func spawn_duel_gear(epoch: int, fighters: Array, gun_index: int) -> void:
	if not NetworkManager.is_host(): return
	var enabled_items: Array = []
	for key in GameConfig.ITEM_SCENES:
		if GameConfig.is_item_enabled(key): enabled_items.append(key)
	var powers: Array = GameConfig.enabled_powerup_types().filter(func(id): return id not in ["extra_life","sticky_hands"])
	var melee: Array = []
	for weapon in PLAYPEN_WEAPONS:
		if GameConfig.is_melee_weapon_enabled(weapon): melee.append(weapon)
	var plan := {"epoch":epoch,"fighters":fighters,"gun_index":gun_index,
		"melee":melee.pick_random() if not melee.is_empty() else "Stick",
		"item":enabled_items.pick_random() if not enabled_items.is_empty() else "",
		"power":powers.pick_random() if not powers.is_empty() else ""}
	NetworkManager.broadcast_match_rpc(self,&"_spawn_duel_equipment",[plan])

@rpc("authority","reliable","call_local")
func _spawn_duel_equipment(plan: Dictionary) -> void:
	var id := 80000+int(plan.epoch)*10
	var fighters: Array = plan.fighters
	_spawn_playpen_gun(id,0,ScrapSpace.STOCK_HOME)
	var gun = _online_loose_gun("PlaypenGun%d_0" % id)
	gun.set_meta("scrap_epoch",int(plan.epoch))
	gun._net_do_pickup(int(fighters[int(plan.gun_index)]))
	for i in range(2):
		_spawn_online_melee({"candidate_id":id+i,"position":ScrapSpace.MELEE_SPAWN if i==1 else ScrapSpace.STOCK_HOME,
			"identity":{"weapon_name":plan.melee,"effect":"normal"}})
		var melee = _online_melee_by_id(id+i)
		melee.set_meta("scrap_epoch",int(plan.epoch))
		melee.marker_refill_on_pickup=false
		if i==0: melee._net_do_pickup(int(fighters[1-int(plan.gun_index)]))
	if str(plan.item)!="":
		_spawn_online_item({"item_id":id,"spawn_id":id,"item_type":plan.item,"position":ScrapSpace.ITEM_SPAWN})
		var item = _online_item(id)
		item.set_meta("scrap_epoch",int(plan.epoch))
		item.marker_refill_on_pickup=false
	if str(plan.power)!="":
		_spawn_online_powerup({"powerup_id":id,"power_type":plan.power,"position":ScrapSpace.POWER_SPAWN})
		_online_powerup(id).set_meta("scrap_epoch",int(plan.epoch))
	for actor_id in fighters:
		var actor = NetworkManager.find_actor(int(actor_id))
		if actor!=null:
			actor.dash_charges=actor.max_dash_charges
			actor.stamina=actor.MAX_STAMINA

func clear_duel_gear(epoch: int, fighters: Array) -> void:
	if NetworkManager.is_host(): NetworkManager.broadcast_match_rpc(self,&"_clear_duel",[epoch,fighters])

@rpc("authority","reliable","call_local")
func _clear_duel(epoch: int, fighters: Array) -> void:
	for id in fighters: _clear_actor_gear(int(id))
	for entry in cleanup.objects.values():
		var obj: Node = entry.ref.get_ref()
		if is_instance_valid(obj) and int(obj.get_meta("scrap_epoch",-1))==epoch: cleanup._retire(obj)

func server_schedule_online_melee_refill(melee, epoch: int) -> void:
	if int(melee.get_meta("scrap_epoch",-1))<0: super.server_schedule_online_melee_refill(melee,epoch)

func server_schedule_online_item_refill(item, epoch: int) -> void:
	if int(item.get_meta("scrap_epoch",-1))<0: super.server_schedule_online_item_refill(item,epoch)

func server_schedule_playpen_gun_cleanup(gun) -> void:
	if int(gun.get_meta("scrap_epoch",-1))<0: super.server_schedule_playpen_gun_cleanup(gun)

func _respawn_playpen_powerup(id: int, power_type: String, epoch: int) -> void:
	var obj = _online_powerup(id)
	if obj!=null and int(obj.get_meta("scrap_epoch",-1))<0: super._respawn_playpen_powerup(id,power_type,epoch)


func _restore_effect(data: Dictionary) -> void:
	if not effect_lifetimes.has(str(data.path)): return
	var obj=load(str(data.path)).instantiate()
	obj.name="OnlineDeployed%d" % int(data.id)
	obj.set_meta("online_deployed_id",int(data.id))
	obj.set_meta("online_owner_actor_id",int(data.owner))
	obj.set_meta("scrap_epoch",int(data.scrap))
	obj.set_meta("hideout_effect_expires",Time.get_ticks_msec()+int(float(data.remaining)*1000))
	obj.add_to_group("online_deployed",true)
	obj.add_to_group("deployed_trap")
	if "owner_player" in obj: obj.owner_player=NetworkManager.find_actor(int(data.owner))
	if "initial_forward" in obj: obj.initial_forward=data.forward
	if "lifetime_seconds" in obj: obj.lifetime_seconds=float(data.remaining)
	obj.transform=data.transform
	lab.add_child(obj)
	_expire_restored_effect(obj,float(data.remaining))

func _expire_restored_effect(obj: Node, remaining: float) -> void:
	await get_tree().create_timer(remaining).timeout
	if is_instance_valid(obj): cleanup._retire(obj)

@rpc("authority","reliable","call_local")
func _net_eliminate(victim_id: int, killer_id: int, weapon_icon: String, lethal_kind: String = "weapon") -> void:
	super._net_eliminate(victim_id,killer_id,weapon_icon,lethal_kind)
	_clear_actor_gear(victim_id)
	lab._sync_controls()

@rpc("authority","reliable","call_local")
func _net_respawn(victim_id: int, pos: Vector3, yaw: float) -> void:
	super._net_respawn(victim_id,pos,yaw)
	lab._sync_controls()
