extends Node
## Local F6 practice lifecycle. No ENet, round manager, rewards or map transition.
const Space = preload("res://maps/hideout/playpen_space.gd")
const Actor = preload("res://maps/hideout/preview_actor.gd")
const Legacy = preload("res://maps/playpen/playpen_manager.gd")
const G = preload("res://maps/hideout/geometry.gd")
const GunScene = preload("res://gun.tscn")
const MeleeScene = preload("res://melee_weapon.tscn")
const PowerScene = preload("res://powerup.tscn")
const PlayerScene = preload("res://player.tscn")
var lab: Node3D
var slots: Array[Dictionary] = []
var objects: Dictionary = {}
var effect_lifetimes: Dictionary = {}
var members: Dictionary = {}
var deaths: Dictionary = {}
var opponent: CharacterBody3D
var sparring_mode := "target"
var recovery_left := 0.0
var fire_left := 1.0
var respawns := 0
var exits := 0
var hud: Label
var clock := 0.0
var stock_left := 0.0
var closing := false

func setup(preview: Node3D) -> void:
	lab=preview
	process_physics_priority=10000
	lab.pilot.pen=self
	get_tree().node_added.connect(_node_added)
	GameEvents.actor_eliminated.connect(_actor_eliminated)
	GameEvents.melee_marker_refill_requested.connect(_marker_refill)
	GameEvents.item_marker_refill_requested.connect(_marker_refill)
	for bay in range(Space.BAY_CENTERS.size()):
		for i in range(23):
			var kind := "gun" if i<2 else ("melee" if i<7 else ("item" if i<16 else "power"))
			var identity: String = "gun" if i<2 else (Legacy.PLAYPEN_WEAPONS[i-2] if i<7 else (Legacy.PLAYPEN_ITEMS[i-7] if i<16 else Legacy.PLAYPEN_POWERUPS[i-16]))
			var enabled := true
			if kind=="item": enabled=GameConfig.is_item_enabled(identity)
			if kind=="power": enabled=identity in GameConfig.enabled_powerup_types()
			slots.append({"kind":kind,"identity":identity,"position":Space.supply_position(bay,i),"stock":null,"due":0.0,"enabled":enabled})
			_spawn_stock(slots.size()-1)
	opponent=PlayerScene.instantiate()
	opponent.set_script(Actor)
	opponent.name="SparringPartner"
	opponent.pen=self
	opponent.is_sparring=true
	opponent.actor_id=9001
	opponent.input_prefix="p2"
	opponent.position=Vector3(17,-0.11,-55)
	lab.add_child(opponent)
	opponent.set_character_appearance("female","orange")
	opponent.set_cosmetic_loadout({})
	opponent.get_gameplay_camera().current=false
	lab.pilot.get_gameplay_camera().make_current()
	var badge := G.label(opponent,"SparringName","SPARRING / TARGET",Vector3(0,2.7,0),38,G.CYAN,0.008)
	badge.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	set_sparring_mode("target")
	hud=Label.new()
	hud.add_theme_font_override("font",load("res://fonts/cinematic/barlow_condensed/BarlowCondensed-ExtraBold.ttf"))
	hud.add_theme_font_size_override("font_size",22)
	hud.add_theme_color_override("font_color",G.PAPER)
	hud.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	lab.ui.shell.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hud.offset_left=-530
	hud.offset_right=-34
	hud.offset_top=100
	hud.offset_bottom=290
	hud.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	sync_actor(lab.pilot)
	sync_actor(opponent)

func contains_actor(actor: Node3D) -> bool:
	if is_instance_valid(lab.scrap) and lab.scrap.Space.in_room(actor.global_position):
		return lab.scrap.can_fight(actor)
	return Space.contains(actor.global_position)

func contains_object(obj: Node3D) -> bool:
	return not obj.is_queued_for_deletion() and not obj.get_meta("pen_retired",false) and Space.contains(obj.global_position)

func sync_actor(actor: CharacterBody3D) -> void:
	var id := actor.get_instance_id()
	var inside: bool = contains_actor(actor) and not actor.is_eliminated and (actor!=opponent or sparring_mode!="off")
	var was_inside: bool = members.get(id,false)
	if inside == was_inside and members.has(id): return
	members[id]=inside
	if inside:
		actor.add_to_group("player")
		actor.add_to_group("combat_target")
		if actor==lab.pilot: lab.ui.show_toast("PLAY PEN / Gear and combat stay inside. Leave across the orange line.")
	else:
		actor.remove_from_group("player")
		actor.remove_from_group("combat_target")
		clear_inventory(actor)
		if actor==lab.pilot and was_inside and not actor.is_eliminated:
			exits+=1
			var area_name: String="SCRAP YARD" if is_instance_valid(lab.scrap) and lab.scrap.Space.in_room(actor.position) else "MAIN HALL"
			lab.ui.show_toast(area_name+" / Weapons, items and powerups cleared.")

func clear_inventory(actor: CharacterBody3D) -> void:
	var carried: Array=[]
	for child in actor.get_hold_point().get_children():
		if child is RigidBody3D: carried.append(child)
	for obj in [actor.held_melee_weapon,actor.held_item_1,actor.held_item_2,actor.active_decoy]:
		if is_instance_valid(obj) and not carried.has(obj): carried.append(obj)
	actor.holding_gun=false
	actor.held_melee_weapon=null
	actor.held_item_1=null
	actor.held_item_2=null
	actor.active_decoy=null
	actor.active_slot="none"
	actor.interact_hold_active=false
	actor.interact_hold_timer=0.0
	actor._manual_pickup_request_active=false
	actor.nearby_interactables.clear()
	actor._normal_interactables.clear()
	actor._reach_interactables.clear()
	actor.clear_all_powerups()
	actor.clear_double_jump_shoes()
	actor._clear_spring_launch_state()
	actor._clear_steam_boost()
	actor.slow_timer=0.0
	actor.slow_multiplier_value=1.0
	actor.stagger_timer=0.0
	actor.knockback_timer=0.0
	actor.knockback_velocity=Vector3.ZERO
	actor.flash_blind_timer=0.0
	actor.lethal_immunity_timer=0.0
	actor.bullet_immune_timer=0.0
	actor.dash_charges=mini(actor.dash_charges,actor.max_dash_charges)
	actor.velocity.y=minf(actor.velocity.y,actor.jump_velocity)
	for obj in carried: _retire(obj)
	# Already-thrown gear cannot be operated remotely after its owner leaves.
	for entry in objects.values():
		var obj: Node = entry.ref.get_ref()
		if not is_instance_valid(obj) or obj.is_queued_for_deletion(): continue
		for key in ["shooter","owner_player","_thrower"]:
			if key in obj and obj.get(key)==actor:
				_retire(obj)
				break

func _node_added(node: Node) -> void:
	if closing or not is_instance_valid(lab) or not lab.is_ancestor_of(node): return
	if node is RigidBody3D or (node is Node3D and "owner_player" in node):
		var id := node.get_instance_id()
		if objects.has(id): return # Reparenting a held item does not create a new loan.
		if is_instance_valid(lab.scrap): lab.scrap.tag_object(node)
		var is_effect := not node is RigidBody3D
		var expiry := 0.0
		if is_effect and not (node.has_method("manages_deployed_lifetime") and node.manages_deployed_lifetime()):
			# Marker items free themselves after use. Own their normal generic timer here.
			expiry=clock+float(effect_lifetimes.get(node.scene_file_path,12.0))
		objects[id]={"ref":weakref(node),"loose_since":-1.0,"effect":is_effect,"expires":expiry}
		node.tree_exited.connect(_object_exited.bind(id),CONNECT_DEFERRED)
		if node is RigidBody3D: node.collision_mask |= Space.BARRIER_LAYER
		if node.is_node_ready(): _object_ready(node)
		else: node.ready.connect(_object_ready.bind(node),CONNECT_ONE_SHOT)
		if is_effect and (not Space.contains(node.global_position) or (is_instance_valid(lab.scrap) and not lab.scrap.object_allowed(node))):
			# Grenades resolve their blast in _ready. Reject an outside effect first.
			node.set_script(null)
			_retire(node)

func _object_exited(id: int) -> void:
	if not objects.has(id): return
	var obj: Node=objects[id].ref.get_ref()
	if not is_instance_valid(obj) or not obj.is_inside_tree(): objects.erase(id)

func _object_ready(obj: Node) -> void:
	if not is_instance_valid(obj) or obj.is_queued_for_deletion(): return
	for label in obj.find_children("*","Label3D",true,false):
		label.no_depth_test=false
		label.visibility_range_end=12.0
	if obj is RigidBody3D:
		obj.collision_mask |= Space.BARRIER_LAYER
		obj.body_entered.connect(_ordnance_contact.bind(obj))

func _ordnance_contact(body: Node, obj: Node) -> void:
	if body.name in ["PlayPenOrdnanceBarrier","ScrapSpectatorBarrier"]: _retire(obj)

func _retire(obj: Node) -> void:
	if not is_instance_valid(obj) or obj.is_queued_for_deletion(): return
	obj.set_meta("pen_retired",true)
	obj.set_process(false)
	obj.set_physics_process(false)
	if "_cook_active" in obj: obj._cook_active=false
	if "_fuse_generation" in obj: obj._fuse_generation+=1
	if "swing_tween" in obj and obj.swing_tween and obj.swing_tween.is_running(): obj.swing_tween.kill()
	if obj is Node3D: obj.hide()
	if obj is CollisionObject3D:
		obj.collision_layer=0
		obj.collision_mask=0
	obj.queue_free()

func _spawn_stock(index: int) -> void:
	var slot: Dictionary=slots[index]
	if not slot.enabled: return
	var obj: Node3D
	match slot.kind:
		"gun": obj=GunScene.instantiate(); obj.playpen_spawn_id=index; obj.loose_return_time=Legacy.PLAYPEN_REFILL_TIME
		"melee": obj=MeleeScene.instantiate(); obj.marker_refill_on_pickup=true
		"item": obj=load(GameConfig.ITEM_SCENES[slot.identity]).instantiate(); obj.marker_refill_on_pickup=true; obj.respawn_after_deploy_time=Legacy.PLAYPEN_REFILL_TIME
		"power": obj=PowerScene.instantiate(); obj.fixed_power_type=slot.identity; obj.respawn_time=Legacy.PLAYPEN_REFILL_TIME
	obj.name="PenSupply%d" % index
	obj.set_meta("pen_slot",index)
	obj.set_meta("pen_stock",true)
	obj.position=slot.position
	if slot.kind=="item" and "deployed_scene" in obj and obj.deployed_scene!=null:
		effect_lifetimes[obj.deployed_scene.resource_path]=obj.deployed_lifetime
	lab.add_child(obj)
	if slot.kind=="melee": obj.apply_weapon_data(MeleeWeaponRegistry.get_weapon_data_by_name(slot.identity),"normal")
	if obj is RigidBody3D:
		_ground_stock(obj)
		obj.freeze=true
		obj.linear_velocity=Vector3.ZERO
		obj.angular_velocity=Vector3.ZERO
	if slot.kind=="power":
		for label in obj.find_children("*","Label3D",true,false):
			label.no_depth_test=false
			label.visibility_range_end=12.0
		objects[obj.get_instance_id()]={"ref":weakref(obj),"loose_since":-1.0,"effect":false,"expires":0.0}
		obj.tree_exited.connect(_object_exited.bind(obj.get_instance_id()),CONNECT_DEFERRED)
	slot.stock=weakref(obj)
	slot.due=0.0

func _ground_stock(obj: Node3D) -> void:
	var bottom := INF
	# The melee root also owns transient hitbox debug geometry. Only its authored
	# weapon model defines where it rests on the ground.
	var visual: Node=obj._model_instance if obj.is_in_group("melee") and is_instance_valid(obj._model_instance) else obj
	var meshes := visual.find_children("*","MeshInstance3D",true,false)
	if visual is MeshInstance3D: meshes.append(visual)
	for child in meshes:
		if child.mesh==null or not child.is_visible_in_tree(): continue
		# A fixed melee identity replaces its ready-time random model. Its old
		# subtree is queued for deletion until the end of this frame.
		var ancestor: Node=child
		var retiring := false
		while ancestor!=obj and ancestor!=null:
			if ancestor.is_queued_for_deletion(): retiring=true; break
			ancestor=ancestor.get_parent()
		if retiring: continue
		var bounds: AABB=child.global_transform*child.get_aabb()
		bottom=minf(bottom,bounds.position.y)
	if is_finite(bottom): obj.global_position.y+=Space.FLOOR_Y+0.025-bottom
	if "spawn_position" in obj: obj.spawn_position=obj.global_position

func _marker_refill(obj: Node) -> void:
	if obj.has_meta("pen_slot"): _vacate_stock(int(obj.get_meta("pen_slot")),obj)

func _vacate_stock(index: int, obj: Node) -> void:
	var slot: Dictionary=slots[index]
	if slot.stock==null or slot.stock.get_ref()!=obj: return
	obj.set_meta("pen_stock",false)
	slot.stock=null
	slot.due=clock+Legacy.PLAYPEN_REFILL_TIME

func _physics_process(delta: float) -> void:
	if lab==null: return
	clock+=delta
	sync_actor(lab.pilot)
	for entry in objects.values():
		var obj: Node3D=entry.ref.get_ref()
		if not is_instance_valid(obj) or obj.is_queued_for_deletion(): continue
		var held: bool="is_held" in obj and obj.is_held
		if held: entry.loose_since=-1.0; continue
		if not Space.contains(obj.global_position): _retire(obj); continue
		if is_instance_valid(lab.scrap) and not lab.scrap.object_allowed(obj): _retire(obj); continue
		if obj.has_meta("scrap_epoch"): continue
		if entry.effect:
			if entry.expires>0 and clock>=entry.expires: _retire(obj)
			continue
		if obj.get_meta("pen_stock",false): continue
		if obj.is_in_group("gun") or obj.is_in_group("melee") or obj.is_in_group("item"):
			if ("is_in_flight" in obj and obj.is_in_flight) or ("_flying" in obj and obj._flying): continue
			if entry.loose_since<0.0: entry.loose_since=clock
			elif clock-entry.loose_since>=Legacy.PLAYPEN_REFILL_TIME: _retire(obj)
	stock_left-=delta
	if stock_left<=0:
		stock_left=0.1
		for i in range(slots.size()):
			var slot: Dictionary=slots[i]
			if not slot.enabled: continue
			var stock: Node=slot.stock.get_ref() if slot.stock!=null else null
			if is_instance_valid(stock) and not stock.is_queued_for_deletion():
				if "is_held" in stock and stock.is_held: _vacate_stock(i,stock)
			elif slot.stock!=null:
				slot.stock=null
				slot.due=clock+Legacy.PLAYPEN_REFILL_TIME
			elif slot.due>0 and clock>=slot.due: _spawn_stock(i)
		_update_hud()
	recovery_left-=delta
	if recovery_left<=0:
		recovery_left=0.25
		for actor in [lab.pilot,opponent]:
			if not is_instance_valid(actor) or actor.is_eliminated: continue
			if not actor.position.is_finite() or actor.position.y < -5:
				clear_inventory(actor)
				actor.respawn(Transform3D(Basis.IDENTITY,Space.RESPAWN))
				lab._sync_controls()

func _actor_eliminated(actor_id: int, _killer: int, _icon: String) -> void:
	var actor: CharacterBody3D=lab.pilot if actor_id==lab.pilot.actor_id else (opponent if is_instance_valid(opponent) and actor_id==opponent.actor_id else null)
	if actor==null: return
	if is_instance_valid(lab.scrap) and lab.scrap.is_fighter(actor): return
	clear_inventory(actor)
	members[actor.get_instance_id()]=false
	actor.remove_from_group("player")
	actor.remove_from_group("combat_target")
	var generation: int=int(deaths.get(actor_id,0))+1
	deaths[actor_id]=generation
	if actor==lab.pilot:
		lab.ui.show_toast("PLAY PEN / Respawning at the entrance line in 2 seconds.")
		lab._sync_controls.call_deferred()
	_respawn_after(actor,actor_id,generation)

func _respawn_after(actor: CharacterBody3D, actor_id: int, generation: int) -> void:
	await get_tree().create_timer(Legacy.PLAYPEN_RESPAWN_TIME).timeout
	if closing or not is_instance_valid(actor) or deaths.get(actor_id)!=generation: return
	var spawn := Space.RESPAWN if actor==lab.pilot else Vector3(19,-0.11,-36)
	actor.respawn(Transform3D(Basis.IDENTITY,spawn))
	members.erase(actor.get_instance_id())
	sync_actor(actor)
	if actor==lab.pilot:
		respawns+=1
		lab.pilot.get_gameplay_camera().make_current()
		lab._sync_controls()
	else: set_sparring_mode(sparring_mode)

func set_sparring_mode(mode: String) -> void:
	sparring_mode=mode
	if not is_instance_valid(opponent): return
	opponent.visible=mode!="off" and not opponent.is_eliminated
	opponent.collision_layer=2 if opponent.visible else 0
	opponent.collision_mask=3 if opponent.visible else 0
	opponent.get_node("SparringName").text="SPARRING / "+mode.to_upper()
	if mode!="duel": clear_inventory(opponent)
	if mode=="duel" and not opponent.holding_gun and not opponent.is_eliminated:
		for slot in slots:
			var gun: Node=slot.stock.get_ref() if slot.stock!=null else null
			if slot.kind=="gun" and is_instance_valid(gun) and not gun.is_held:
				gun.pick_up(opponent)
				opponent.active_slot="weapon"
				opponent._update_active_slot_and_visuals()
				break
	members.erase(opponent.get_instance_id())
	sync_actor(opponent)
	if mode=="off":
		opponent.remove_from_group("player")
		opponent.remove_from_group("combat_target")
	fire_left=1.5

func tick_sparring(actor: CharacterBody3D, delta: float) -> void:
	if sparring_mode=="off" or actor.is_eliminated: return
	if not lab.controls_enabled or not contains_actor(lab.pilot):
		actor.velocity=Vector3.ZERO
		actor._play_anim("idle",false)
		return
	actor._update_new_powerups(delta)
	actor._update_action_animation(delta)
	actor.lethal_immunity_timer=maxf(0,actor.lethal_immunity_timer-delta)
	actor.knockback_timer=maxf(0,actor.knockback_timer-delta)
	actor.stagger_timer=maxf(0,actor.stagger_timer-delta)
	actor.velocity.x=actor.knockback_velocity.x if actor.knockback_timer>0 else 0.0
	actor.velocity.z=actor.knockback_velocity.z if actor.knockback_timer>0 else 0.0
	if not actor.is_on_floor(): actor.velocity.y-=9.8*delta
	actor.move_and_slide()
	if not Space.contains(actor.position):
		actor.respawn(Transform3D(Basis.IDENTITY,Vector3(19,-0.11,-36)))
	actor.get_node("CharacterModel").look_at(Vector3(lab.pilot.position.x,actor.get_node("CharacterModel").global_position.y,lab.pilot.position.z),Vector3.UP,true)
	actor._play_anim("idle_pistol" if actor.holding_gun else "idle",false)
	fire_left-=delta
	if sparring_mode=="duel" and fire_left<=0 and actor.stagger_timer<=0 and actor.holding_gun:
		var gun: Node=actor.get_hold_point().get_child(0)
		if gun.can_fire:
			gun.try_fire()
			fire_left=Legacy.PLAYPEN_REFILL_TIME

func _update_hud() -> void:
	if hud==null: return
	# Inventory and powerups already have the real player widgets; avoid a second
	# text HUD competing with the compact Friends/shortcut controls.
	hud.hide()

func _exit_tree() -> void:
	closing=true
	if get_tree().node_added.is_connected(_node_added): get_tree().node_added.disconnect(_node_added)
