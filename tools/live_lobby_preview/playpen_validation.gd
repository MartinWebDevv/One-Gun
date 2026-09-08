extends RefCounted
const Space = preload("res://tools/live_lobby_preview/playpen_space.gd")

func run(lab: Node3D, test: Node) -> void:
	var pen: Node=lab.playpen
	var player: CharacterBody3D=lab.pilot
	pen.set_sparring_mode("off")
	await test.settle(3)
	test.check(not pen.opponent.visible and not pen.opponent.is_in_group("combat_target"),"disabled sparring partner stays out of target scans")
	pen.set_sparring_mode("target")
	test.check(pen.opponent.visible and pen.opponent.is_in_group("combat_target"),"re-enabling the partner restores target registration")
	var scene := lab.get_tree().current_scene
	test.check(pen.slots.size()==46,"Play Pen defines two complete outer armories")
	test.check(lab.get_tree().get_nodes_in_group("gun").size()==4,"Play Pen starts with four real guns on the armory floor")
	test.check(not lab.station.has_node("CourseInteraction"),"separate movement area has been removed")
	player.position=Vector3(17,1.12,-27.2)
	player.velocity=Vector3.ZERO
	player.get_node("AimPivot").rotation=Vector3.ZERO
	lab._sync_controls()
	await test.settle(5)
	test.check(not player.in_playpen(),"main side of the barrier is outside combat")
	await test.move_for(lab,"move_forward",0.65)
	test.check(player.in_playpen() and player.is_in_group("combat_target"),"real controller walks through the barrier into Play Pen")
	await test.move_for(lab,"move_forward",0.6)
	test.check(player.position.z < -36 and absf(player.position.y+0.11)<0.15,"entry hall passes through the north wall and descends to the arena floor")
	test.check(lab.get_tree().current_scene==scene,"walking into Play Pen keeps the same scene and camera")
	await lab.get_tree().create_timer(0.15).timeout
	test.check(pen.hud.is_visible_in_tree() and pen.hud.get_global_rect().intersects(lab.get_viewport().get_visible_rect()),"Play Pen inventory readout is visible within the viewport")
	# Use the shared pickup APIs, with the same explicit-request flag as Interact.
	player.position=Vector3(-0.5,-0.11,-70)
	player.velocity=Vector3.ZERO
	await test.settle(3)
	var gun: Node=_stock(pen,"gun")
	_pick(player,gun)
	test.check(player.holding_gun and gun.player_ref==player,"actual Play Pen gun enters the real weapon slot")
	var grenade: Node=_stock(pen,"item","grenade")
	var camera_item: Node=_stock(pen,"item","flash_camera")
	if grenade!=null: _pick(player,grenade)
	if camera_item!=null: _pick(player,camera_item)
	test.check((grenade==null or player.held_item_1==grenade) and (camera_item==null or player.held_item_2==camera_item),"enabled items occupy both real inventory slots")
	for power in GameConfig.enabled_powerup_types():
		test.check(player.apply_powerup(power,5.0),"practice applies enabled powerup: "+power)
	player.activate_double_jump_shoes()
	if grenade!=null:
		grenade.begin_use()
		test.check(grenade._cook_active,"grenade can be primed inside Play Pen")
	player.position=Space.RESPAWN
	pen.sync_actor(player)
	test.check(_empty(player),"crossing back clears gun, both item slots, powers and shoes immediately")
	await test.settle(4)
	test.check(not is_instance_valid(gun) and not is_instance_valid(grenade) and not is_instance_valid(camera_item),"exit destroys carried gear instead of dropping it in the main hall")
	test.check(not player.is_in_group("combat_target") and not player.is_in_group("player"),"main-hall actor is excluded from practice target scans")
	# Main-hall protection covers more than lethal hits.
	player.eliminate("TEST","GUN","weapon",9001)
	player.apply_knockback(Vector3.RIGHT,4.0)
	player.apply_slow(5.0,0.2)
	player.apply_stagger(5.0)
	player.apply_flash_blind(5.0)
	player.apply_spring_launch(15.0,4.0,1.0)
	test.check(not player.is_eliminated and player.knockback_timer==0 and player.slow_timer==0 and player.stagger_timer==0 and player.flash_blind_timer==0,"damage, knockback, slows, traps and flash cannot affect the main hall")
	test.check(not player.apply_powerup("speed_surge",5.0),"powerups cannot be collected from outside the boundary")
	# A real grenade within blast distance cannot push the player across the line.
	var blast: Node3D=load("res://grenade_explosion.tscn").instantiate()
	blast.position=Vector3(17,0.5,-31.2)
	blast.owner_player=pen.opponent
	lab.add_child(blast)
	test.check(player.knockback_timer==0,"real grenade blast inside the line cannot affect a nearby main-hall player")
	# Reject a blast whose spawn point crossed the line before its _ready damage scan.
	var outside_blast: Node3D=load("res://grenade_explosion.tscn").instantiate()
	outside_blast.position=Space.RESPAWN
	outside_blast.owner_player=pen.opponent
	lab.add_child(outside_blast)
	await test.settle(3)
	test.check(not is_instance_valid(outside_blast) and player.knockback_timer==0,"outside one-shot effects are rejected before applying damage")
	# Test actual projectile collision, not just a position predicate.
	var bullet: RigidBody3D=load("res://bullet.tscn").instantiate()
	bullet.position=Vector3(17,2,-34.2)
	lab.add_child(bullet)
	bullet.launch(Vector3.BACK,pen.opponent)
	await lab.get_tree().create_timer(0.15).timeout
	test.check(not is_instance_valid(bullet) and not player.is_eliminated,"the permeable player barrier stops an actual outgoing bullet")
	# Walk out carrying a melee weapon, rather than teleporting through the check.
	player.position=Vector3(17,1.12,-33.2)
	player.velocity=Vector3.ZERO
	player.get_node("AimPivot").rotation=Vector3.ZERO
	await test.settle(4)
	var melee: Node=_stock(pen,"melee","Sword")
	_pick(player,melee)
	test.check(player.held_melee_weapon==melee,"real melee pickup works inside the practice area")
	await test.move_for(lab,"move_back",0.55)
	test.check(not player.in_playpen() and _empty(player) and not is_instance_valid(melee),"ordinary walking over the exit line removes carried melee")
	await lab.get_tree().create_timer(2.2).timeout
	# A thrown melee weapon meets the same ordnance barrier.
	player.position=Vector3(17,1.12,-33.2)
	player.velocity=Vector3.ZERO
	player.get_node("AimPivot").rotation=Vector3(0,PI,0)
	await test.settle(3)
	melee=_stock(pen,"melee","Sword")
	_pick(player,melee)
	melee.throw()
	await lab.get_tree().create_timer(0.35).timeout
	test.check(not is_instance_valid(melee),"thrown melee cannot leave the Play Pen")
	var boomerang: Node=_stock(pen,"item","boomerang")
	if boomerang!=null:
		_pick(player,boomerang)
		boomerang.throw()
		await lab.get_tree().create_timer(0.5).timeout
		test.check(not is_instance_valid(boomerang),"script-driven boomerang flight cannot cross into the main hall")
	pen.clear_inventory(player)
	# Shoot the real sparring actor with the real gun/bullet path.
	player.position=Vector3(17,-0.11,-49)
	player.velocity=Vector3.ZERO
	player.get_node("AimPivot").rotation=Vector3.ZERO
	pen.opponent.position=Vector3(17,-0.11,-55)
	pen.opponent.velocity=Vector3.ZERO
	await test.settle(6)
	gun=_stock(pen,"gun")
	_pick(player,gun)
	player.active_slot="weapon"
	player._update_active_slot_and_visuals()
	player.set_physics_process(false)
	var aim_camera: Camera3D=player.get_gameplay_camera()
	var camera_transform := aim_camera.global_transform
	aim_camera.look_at(pen.opponent.global_position+Vector3.UP*0.1,Vector3.UP)
	gun.try_fire()
	await lab.get_tree().create_timer(0.25).timeout
	test.check(pen.opponent.is_eliminated,"real gunfire eliminates the sparring actor inside Play Pen")
	aim_camera.global_transform=camera_transform
	lab._sync_controls()
	await lab.get_tree().create_timer(2.0).timeout
	test.check(not pen.opponent.is_eliminated and pen.opponent.position.z > -38,"eliminated sparring actor returns at the entrance barrier")
	pen.clear_inventory(player)
	# The optional duel partner fires back through the same gun implementation.
	player.position=Vector3(17,-0.11,-49)
	player.velocity=Vector3.ZERO
	pen.opponent.position=Vector3(17,-0.11,-55)
	pen.opponent.velocity=Vector3.ZERO
	pen.set_sparring_mode("duel")
	await test.settle(4)
	pen.fire_left=0.0
	var deadline := Time.get_ticks_msec()+4500
	while not player.is_eliminated and Time.get_ticks_msec()<deadline:
		await lab.get_tree().physics_frame
	test.check(player.is_eliminated,"sparring gunfire can kill the real player inside Play Pen")
	test.check(player._spectator==null,"practice death keeps the current view rather than creating a match spectator")
	await lab.get_tree().create_timer(2.15).timeout
	test.check(not player.is_eliminated and player.position.distance_to(Space.RESPAWN)<0.3,"player respawns after two seconds at the barrier line")
	test.check(_empty(player) and lab.controls_enabled,"respawn restores walking with no retained practice inventory")
	pen.set_sparring_mode("target")
	# Rapid return/respawn must invalidate a pending delayed recovery.
	player.position=Vector3(17,1.12,-33.2)
	pen.sync_actor(player)
	player.eliminate("TEST","GUN","weapon",9001)
	lab._reset_position()
	await lab.get_tree().create_timer(2.15).timeout
	test.check(player.position.z>20,"manual reset cancels a stale Play Pen respawn timer")
	# A marker item disappears on use; its deployed trap must still expire normally.
	var trap_item: Node=_stock(pen,"item","bear_trap")
	if trap_item!=null:
		player.position=Vector3(17,-0.11,-49)
		pen.sync_actor(player)
		_pick(player,trap_item)
		var trap_lifetime: float=trap_item.deployed_lifetime
		trap_item._spawn_deployed(Vector3(0,-1.19,-52),-1,-1)
		var deployed_trap: Node
		for entry in pen.objects.values():
			var candidate: Node=entry.ref.get_ref()
			if is_instance_valid(candidate) and candidate.scene_file_path==trap_item.deployed_scene.resource_path: deployed_trap=candidate
		trap_item.queue_free()
		player.held_item_1=null
		test.check(is_instance_valid(deployed_trap),"actual marker item deploys its trap inside Play Pen")
		await lab.get_tree().create_timer(trap_lifetime+0.2).timeout
		test.check(not is_instance_valid(deployed_trap),"deployed trap retains its normal cleanup lifetime after its source item is freed")
	# Repeated entry/exit cannot accumulate carried or loose copies.
	for cycle in range(8):
		player.position=Vector3(17,-0.11,-36)
		pen.sync_actor(player)
		player.apply_powerup("speed_surge",5.0)
		player.position=Space.RESPAWN
		pen.sync_actor(player)
		test.check(_empty(player),"repeated boundary exit clears state: %d" % (cycle+1))
	await lab.get_tree().create_timer(2.4).timeout
	var stock_count := 0
	var expected := 0
	for slot in pen.slots:
		if not slot.enabled: continue
		expected+=1
		if slot.stock!=null and is_instance_valid(slot.stock.get_ref()): stock_count+=1
	test.check(stock_count==expected,"fixed armories refill without losing any enabled supply slot")
	test.check(pen.objects.size()<=expected,"repeated use and exits leave no accumulating combat objects")
	test.check(lab.get_tree().current_scene==scene and not NetworkManager.is_online(),"combat, deaths and exits stay in this offline F6 scene")
	lab._reset_position()
	lab._sync_controls()

func _stock(pen: Node, kind: String, identity := "") -> Node:
	for slot in pen.slots:
		if slot.kind!=kind or (not identity.is_empty() and slot.identity!=identity) or slot.stock==null: continue
		var obj: Node=slot.stock.get_ref()
		if is_instance_valid(obj) and not obj.is_queued_for_deletion(): return obj
	return null

func _pick(actor: CharacterBody3D, obj: Node) -> void:
	assert(obj!=null,"Expected enabled supply is missing")
	actor._manual_pickup_request_active=true
	obj.pick_up(actor)
	actor._manual_pickup_request_active=false

func _empty(actor: CharacterBody3D) -> bool:
	return not actor.holding_gun and actor.held_melee_weapon==null and actor.held_item_1==null and actor.held_item_2==null and not actor.double_jump_shoes_active and actor.get_active_powerups_for_display().is_empty()
