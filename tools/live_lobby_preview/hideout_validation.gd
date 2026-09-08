extends RefCounted
const Session=preload("res://tools/live_lobby_preview/session.gd")

func run(lab: Node3D, test: Node) -> void:
	var s:=Session.new()
	test.check(s.access=="Invite Only" and s.is_host,"Hideout begins private without a separate hosting step")
	s.set_local(1,9)
	s.add_friend(); s.add_friend()
	test.check(s.bots==7,"inviting friends releases bot capacity without exceeding ten occupants")
	test.check(s.guests.size()==2 and s.is_host,"invited squad friends share the existing Hideout")
	test.check(not s.add_public_visitor(),"private Hideout refuses a public visitor")
	s.set_access(2); s.add_public_visitor()
	test.check(s.residents.size()==1 and s.guests.size()==2,"public visitors do not become traveling squad members")
	test.check(not s.request_join("patch"),"browser refuses a lobby without capacity for the entire squad")
	test.check(s.request_join("sunny"),"leader can request a lobby with room for everyone")
	s.accept()
	test.check(s.is_host and s.phase==Session.Phase.FOUND,"local confirmation alone cannot move unconfirmed squad members")
	s.simulate_confirmations()
	test.check(not s.is_host and s.host_alias=="SUNNY" and s.guests.size()==2 and s.residents==["SUNNY","BEAN"],"confirmed squad arrives together and remains distinct from destination occupants")
	test.check(not s.set_access(0) and not s.set_destination(2),"visiting squad leader cannot change the destination host's settings")
	s.request_ready(); s.accept(); s.simulate_confirmations()
	test.check(not s.start_match(),"visiting squad leader cannot start another host's match")
	s.start_match(true); s.tick(3.1); s.return_home()
	test.check(not s.is_host and s.host_alias=="SUNNY","match return preserves the visited lobby")
	s.leave_together()
	test.check(s.is_host and s.guests.size()==2 and s.residents.is_empty(),"leaving together brings only the squad home")
	s.request_join("sunny"); s.accept()
	s.directory[0].capacity=3
	s.simulate_confirmations()
	test.check(s.is_host and s.phase==Session.Phase.HOME and s.guests.size()==2,"capacity change at commit cancels travel without splitting the squad")
	s.request_ready(); s.accept()
	test.check(not s.start_match(),"host cannot launch before all occupants confirm")
	s.simulate_confirmations()
	test.check(s.phase==Session.Phase.FOUND,"all ready does not automatically launch")
	test.check(s.start_match(),"host explicitly starts a three-second countdown")
	s.cancel()
	test.check(s.phase==Session.Phase.HOME and s.guests.size()==2,"countdown cancellation preserves the squad")
	# New room has a clear middle path; floor supplies remain only in the outer bays.
	test.check(lab.playpen.slots.size()==46 and lab.playpen.slots.all(func(slot):return absf(slot.position.x-17)>8),"two outer supply bays leave the central approach clear")
	var scrap: Node=lab.scrap
	lab.playpen.set_sparring_mode("off")
	lab._open("")
	lab.pilot.position=scrap.Space.FOYER
	lab.playpen.sync_actor(lab.pilot)
	test.check(not lab.pilot.in_playpen(),"Scrap foyer and spectator space are noncombat")
	test.check(scrap.join_round("solo"),"solo F6 test joins player as second caller against a bot")
	test.check(not scrap.choose("heads",scrap.fighters[0].actor_id),"first joiner cannot call the coin")
	scrap.choose("heads",scrap.fighters[1].actor_id)
	test.check(not scrap.choose("tails",scrap.fighters[1].actor_id),"coin call cannot be changed or rerolled after commitment")
	scrap.time_left=0; scrap._process(0.01)
	test.check(scrap.state==scrap.State.COUNTDOWN and not lab.pilot.in_playpen(),"coin reveal precedes countdown with combat locked")
	scrap.time_left=0; scrap._process(0.01)
	for actor in scrap.fighters: actor.set_physics_process(false)
	await test.settle(2)
	var weapons: Array=lab.get_tree().get_nodes_in_group("gun").filter(func(obj):return obj.has_meta("scrap_epoch") and not obj.is_queued_for_deletion())
	var melee: Array=lab.get_tree().get_nodes_in_group("melee").filter(func(obj):return obj.has_meta("scrap_epoch") and not obj.is_queued_for_deletion())
	test.check(weapons.size()==1 and melee.size()==2,"Scrap round contains exactly one gun and two melee weapons")
	test.check(scrap.fighters[scrap.gun_index].holding_gun and is_instance_valid(scrap.fighters[1-scrap.gun_index].held_melee_weapon),"coin winner receives the gun; other fighter receives melee")
	test.check(scrap.gun_index==(1 if scrap.coin_side==scrap.call_side else 0),"second player's correct or incorrect call determines complementary equipment")
	var powers: Array=lab.get_tree().get_nodes_in_group("powerup").filter(func(obj):return obj.has_meta("scrap_epoch"))
	test.check(powers.all(func(obj):return obj.power_type not in ["extra_life","sticky_hands"]),"Scrap power pool excludes Extra Life and Sticky Hands")
	var direct:=PhysicsRayQueryParameters3D.create(scrap.fighters[0].position+Vector3.UP*0.3,scrap.fighters[1].position+Vector3.UP*0.3,1)
	test.check(not lab.get_world_3d().direct_space_state.intersect_ray(direct).is_empty(),"central cover blocks the opening spawn-to-spawn shot")
	var rail:=PhysicsRayQueryParameters3D.create(Vector3(17,2,-97),Vector3(17,2,-92),scrap.Space.PenSpace.BARRIER_LAYER)
	test.check(not lab.get_world_3d().direct_space_state.intersect_ray(rail).is_empty(),"spectator boundary blocks projectiles above the handrail")
	var foreign: Node3D=load("res://melee_weapon.tscn").instantiate()
	foreign.position=Vector3(6,-0.5,-108)
	lab.add_child(foreign)
	test.check(not scrap.object_allowed(foreign),"foreign practice gear cannot be adopted by an active duel")
	await test.settle(3)
	test.check(not is_instance_valid(foreign),"foreign gear is removed from the ring")
	var loser: CharacterBody3D=scrap.fighters[1-scrap.gun_index]
	var winner: CharacterBody3D=scrap.fighters[scrap.gun_index]
	winner.position=Vector3(6,-0.11,-108)
	loser.position=Vector3(6,-0.11,-112)
	for actor in [winner,loser]:
		actor.bullet_immune_timer=0.0
		actor.lethal_immunity_timer=0.0
		actor.velocity=Vector3.ZERO
	await test.settle(3)
	var camera: Camera3D=winner.get_gun_fire_camera()
	if camera: camera.look_at(loser.position+Vector3.UP*0.1,Vector3.UP)
	weapons[0].try_fire()
	await lab.get_tree().create_timer(0.4).timeout
	test.check(loser.is_eliminated,"real Scrap gunfire resolves a lethal hit through the existing projectile")
	await test.settle(3)
	test.check(scrap.state==scrap.State.RESULT and not lab.playpen.deaths.has(loser.actor_id),"one elimination ends the round without Play Pen respawn")
	scrap.leave()
	await test.settle(4)
	test.check(scrap.fighters.is_empty() and not lab.pilot.holding_gun and lab.pilot.held_melee_weapon==null,"returning to foyer removes fighters and duel inventory")
	test.check(lab.get_tree().get_nodes_in_group("gun").all(func(obj):return not obj.has_meta("scrap_epoch")),"duel gun and loose equipment are released after the round")
	scrap.join_round("local")
	await test.settle(3)
	test.check(scrap.split_views.size()==2 and scrap.split_views.all(func(view):return view.world_3d==lab.get_world_3d()),"local two-player preview has two cameras in the same live arena")
	test.check(scrap.fighters[1].input_prefix=="p2" and not scrap.fighters[1].demo_bot,"second local fighter uses the real P2 controller")
	scrap.choose("tails",scrap.fighters[1].actor_id)
	scrap.time_left=0; scrap._process(0.01)
	scrap.time_left=0; scrap._process(0.01)
	var p2: CharacterBody3D=scrap.fighters[1]
	var p2_start: Vector3=p2.position
	for i in range(20):
		Input.action_press("p2_move_right")
		await lab.get_tree().physics_frame
	Input.action_release("p2_move_right")
	test.check(p2.position.distance_to(p2_start)>0.8,"local P2 moves with the existing p2 input actions")
	test.check(scrap.split_reticles.size()==2 and scrap.split_huds.size()==2 and not lab.ui.reticle.visible,"each split view has its own centered reticle and inventory HUD")
	scrap.leave()
	await test.settle(4)
	test.check(scrap.split_views.is_empty() and not lab.get_viewport().disable_3d,"leaving split-screen frees views and restores the normal camera")
	scrap.join_round("watch")
	scrap.time_left=0; scrap._process(0.01)
	scrap.time_left=0; scrap._process(0.01)
	test.check(lab.pilot.is_bullet_immune() and not lab.pilot.in_playpen(),"watching player cannot receive duel combat damage")
	var duel_gun: Node=null
	for ref in scrap.items:
		var stock: Node=ref.get_ref()
		if is_instance_valid(stock) and stock.is_in_group("gun"): duel_gun=stock
	var recovered:=[false]
	var recovery_listener:=func(actor_id: int):
		if scrap.fighters.any(func(actor):return actor.actor_id==actor_id): recovered[0]=true
	GameEvents.actor_gun_picked_up.connect(recovery_listener)
	duel_gun.force_disarm()
	var deadline:=Time.get_ticks_msec()+20000
	while scrap.state==scrap.State.ACTIVE and Time.get_ticks_msec()<deadline:
		await lab.get_tree().physics_frame
	GameEvents.actor_gun_picked_up.disconnect(recovery_listener)
	test.check(recovered[0],"demo fighters recover the single gun after a forced disarm")
	if scrap.state==scrap.State.ACTIVE:
		for actor in scrap.fighters:
			var ray:=PhysicsRayQueryParameters3D.create(actor.get_hold_point().global_position,actor.rival.position+Vector3.UP*0.3,3,[actor.get_rid()])
			var hit:=lab.get_world_3d().direct_space_state.intersect_ray(ray)
			print("SCRAP BOT DIAGNOSTIC: ",actor.actor_id," at ",actor.position," gun ",actor.holding_gun," velocity ",actor.velocity," stagger ",actor.stagger_timer," sight ",hit.get("collider")," aim origin ",actor.get_hold_point().global_position)
		if is_instance_valid(duel_gun): print("SCRAP GUN DIAGNOSTIC: ",duel_gun.global_position," fire ",duel_gun.can_fire," held ",duel_gun.is_held," ray ",duel_gun._calculate_fire_ray() if duel_gun.is_held else {})
	test.check(scrap.state==scrap.State.RESULT and scrap.result_text.ends_with(" WINS"),"autonomous spectator duel reaches a one-round winner using real combat")
	scrap.leave()
	for i in range(3):
		scrap.join_round("solo"); scrap.leave(); await test.settle(3)
	test.check(lab.find_children("ScrapFighter*","CharacterBody3D",true,false).is_empty(),"repeated duel entry/cancel does not retain fighters")
	lab._open("")
	lab.pilot.position=lab.toss.ORIGIN+Vector3(0,1.09,0)
	await test.settle(5)
	test.check(lab.nearby.has("toss") and lab.toss.throw_ball(),"central pit toss uses the nearby Interact station")
	lab.toss.flight_left=0
	lab.toss._physics_process(0.016)
	test.check(not lab.toss.flying and not lab.toss.is_physics_processing(),"soft ball resets and stops processing after its throw")
	lab.toss.flying=true
	lab.toss.ball.position=lab.toss.GOALS[0]+Vector3.UP*0.05
	lab.toss.velocity=Vector3.DOWN*5
	lab.toss.flight_left=2
	lab.toss.banked=false
	lab.toss._physics_process(0.02)
	test.check(lab.toss.score==1 and not lab.toss.flying,"a descending ball through a basket scores and resets")
	lab.toss.flying=true
	lab.toss.ball.position=Vector3(11,1,0)
	lab.toss.velocity=Vector3.RIGHT
	lab.toss._physics_process(0.02)
	test.check(not lab.toss.flying,"central toy resets before leaving its social activity area")
	lab._reset_position()
