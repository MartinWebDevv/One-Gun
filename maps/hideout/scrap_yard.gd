extends Node
## Isolated round authority. No RoundManager, networking, rewards, or shared-rule writes.
signal round_changed
const Space=preload("res://maps/hideout/scrap_space.gd")
const Actor=preload("res://maps/hideout/scrap_actor.gd")
const PlayerScene=preload("res://player.tscn")
enum State { IDLE, CALLING, FLIPPING, COUNTDOWN, ACTIVE, RESULT }
var lab: Node3D
var state: State=State.IDLE
var fighters: Array[CharacterBody3D]=[]
var epoch:=0
var time_left:=0.0
var call_side:=""
var coin_side:=""
var gun_index:=-1
var result_text:=""
var mode:="solo"
var items: Array[WeakRef]=[]
var saved_sparring:="target"
const Standings=preload("res://maps/hideout/scrap_standings.gd")
var wins_board: Label3D
var board: Label3D
var banner: Label
var split_layer: CanvasLayer
var split_views: Array[SubViewport]=[]
var split_cameras: Array[Camera3D]=[]
var rng:=RandomNumberGenerator.new()
var update_left:=0.0
const Coin=preload("res://maps/hideout/scrap_coin.gd")
var coin_visual: Control
var split_coins: Array[Control]=[]
var split_huds: Array[Label]=[]
var split_reticles: Array[Label]=[]
var default_disable_3d:=false
var spectators: Array[Dictionary]=[]
var pad_check:=0.0

func setup(preview: Node3D) -> void:
	lab=preview
	rng.randomize()
	board=lab.station.find_child("ScrapStatus",true,false)
	wins_board=lab.station.find_child("ScrapWinsRows",true,false)
	Standings.render(wins_board,false)
	banner=lab.ui._label("",27,lab.ui.G.GOLD)
	lab.ui.shell.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.offset_left=-480
	banner.offset_right=480
	banner.offset_top=178
	banner.offset_bottom=340
	banner.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	banner.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	banner.hide()
	coin_visual=Coin.new()
	lab.ui.shell.add_child(coin_visual)
	coin_visual.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	coin_visual.offset_left=-90
	coin_visual.offset_right=90
	coin_visual.offset_top=170
	coin_visual.offset_bottom=350
	coin_visual.hide()
	GameEvents.actor_eliminated.connect(_eliminated)

func is_fighter(actor: Node) -> bool:
	return fighters.has(actor) and state!=State.IDLE

func can_fight(actor: Node3D) -> bool:
	return state==State.ACTIVE and fighters.has(actor) and not actor.is_eliminated and Space.in_ring(actor.global_position)

func pilot_locked() -> bool:
	return is_fighter(lab.pilot) and state in [State.CALLING,State.FLIPPING,State.COUNTDOWN,State.RESULT]

func join_round(which: String) -> bool:
	if state!=State.IDLE or lab.session.phase!=lab.session.Phase.HOME: return false
	if which not in ["solo","local","watch"]: return false
	lab.training.cancel_trial()
	saved_sparring=lab.playpen.sparring_mode
	lab.playpen.set_sparring_mode("off")
	mode=which
	epoch+=1
	state=State.CALLING
	call_side=""
	coin_side=""
	result_text=""
	gun_index=-1
	lab.playpen.clear_inventory(lab.pilot)
	if which=="solo":
		fighters.append(_make_actor(true,0))
		fighters.append(lab.pilot) # User is second joiner and calls the coin.
	elif which=="local":
		fighters.append(lab.pilot)
		fighters.append(_make_actor(false,1))
	else:
		fighters.append(_make_actor(true,0))
		fighters.append(_make_actor(true,1))
	for i in range(2):
		var actor: CharacterBody3D=fighters[i]
		lab.playpen.deaths.erase(actor.actor_id)
		actor.respawn(Transform3D(Basis.IDENTITY,Space.STARTS[i]))
		actor.velocity=Vector3.ZERO
		actor.get_node("AimPivot").rotation=Vector3(-0.08,-PI/2 if i==0 else PI/2,0)
		if actor!=lab.pilot: actor.rival=fighters[1-i]
		lab.playpen.sync_actor(actor)
	if which=="watch":
		lab.pilot.position=Space.FOYER+Vector3(0,0,-3)
		choose("heads",fighters[1].actor_id)
	elif which=="local": _start_split()
	lab.pilot.get_gameplay_camera().make_current()
	lab._open("scrap" if state==State.CALLING else "")
	gather_spectators()
	_refresh()
	return true

func _make_actor(bot: bool, index: int) -> CharacterBody3D:
	var actor: CharacterBody3D=PlayerScene.instantiate()
	actor.set_script(Actor)
	actor.name="ScrapFighter%d" % index
	actor.pen=lab.playpen
	actor.duel=self
	actor.demo_bot=bot
	actor.is_sparring=bot
	actor.is_bot=bot
	actor.is_player2=true
	actor.input_prefix="p2" if index==1 else "p2"
	actor.actor_id=9100+index
	actor.label_name="PLAYER 2" if not bot else "SCRAP BOT %d" % (index+1)
	actor.position=Space.STARTS[index]
	lab.add_child(actor)
	if bot:
		actor.set_character_appearance("female","orange" if index==1 else "purple")
		actor.set_cosmetic_loadout({})
	actor.get_gameplay_camera().current=false
	return actor

func choose(side: String, caller_id: int) -> bool:
	if state!=State.CALLING or side not in ["heads","tails"] or caller_id!=fighters[1].actor_id: return false
	call_side=side
	coin_side="heads" if rng.randi_range(0,1)==0 else "tails"
	gun_index=1 if coin_side==call_side else 0
	state=State.FLIPPING
	time_left=2.0
	lab._open("")
	_refresh()
	return true

func _process(delta: float) -> void:
	_update_split()
	_update_coin()
	if split_layer:
		pad_check-=delta
		if pad_check<=0: pad_check=0.5; _route_p2()
	if state in [State.FLIPPING,State.COUNTDOWN]:
		time_left-=delta
		if time_left<=0:
			if state==State.FLIPPING: state=State.COUNTDOWN; time_left=3.0
			else: _begin_combat()
			_refresh()
	elif state==State.ACTIVE:
		for actor in fighters:
			if not Space.in_ring(actor.position):
				finish("ROUND CANCELLED / FIGHTER LEFT THE RING")
				break
	update_left-=delta
	if update_left<=0:
		update_left=0.1
		_refresh()

func _begin_combat() -> void:
	state=State.ACTIVE
	for actor in fighters:
		actor.dash_charges=actor.max_dash_charges
		actor.stamina=actor.MAX_STAMINA
		lab.playpen.members.erase(actor.get_instance_id())
		lab.playpen.sync_actor(actor)
	var gun: Node3D=_spawn(load("res://gun.tscn"),Space.STOCK_HOME)
	gun.loose_return_time=5.0
	gun._local_pickup(fighters[gun_index])
	var melee: Node3D=_melee(Space.STOCK_HOME)
	melee._local_pickup(fighters[1-gun_index])
	_melee(Space.MELEE_SPAWN)
	for actor in fighters:
		actor.active_slot="weapon"
		actor._update_active_slot_and_visuals()
	var pool: Array=[]
	for identity in GameConfig.ITEM_SCENES:
		if GameConfig.is_item_enabled(identity): pool.append(identity)
	if not pool.is_empty():
		var item: Node3D=_spawn(load(GameConfig.ITEM_SCENES[pool[rng.randi_range(0,pool.size()-1)]]),Space.ITEM_SPAWN)
		if "marker_refill_on_pickup" in item: item.marker_refill_on_pickup=false
		lab.playpen._ground_stock(item)
	var powers: Array=GameConfig.enabled_powerup_types().filter(func(id): return id not in ["extra_life","sticky_hands"])
	if not powers.is_empty():
		var power: Node3D=load("res://powerup.tscn").instantiate()
		power.fixed_power_type=powers[rng.randi_range(0,powers.size()-1)]
		power.respawn_time=3600.0
		_add_stock(power,Space.POWER_SPAWN)
	lab._sync_controls()
	_refresh()

func _spawn(scene: PackedScene, at: Vector3) -> Node3D:
	var obj: Node3D=scene.instantiate()
	_add_stock(obj,at)
	return obj

func _add_stock(obj: Node3D, at: Vector3) -> void:
	obj.position=at
	obj.set_meta("scrap_epoch",epoch)
	lab.add_child(obj)
	items.append(weakref(obj))
	if obj is RigidBody3D:
		lab.playpen._ground_stock(obj)
		obj.freeze=true

func _melee(at: Vector3) -> Node3D:
	var melee: Node3D=_spawn(load("res://melee_weapon.tscn"),at)
	melee.apply_weapon_data(MeleeWeaponRegistry.get_random_weapon_data(),"normal")
	lab.playpen._ground_stock(melee)
	return melee

func tag_object(obj: Node3D) -> void:
	if state!=State.ACTIVE: return
	for key in ["shooter","owner_player","_thrower","player_ref"]:
		if key in obj and fighters.has(obj.get(key)): obj.set_meta("scrap_epoch",epoch)

func object_allowed(obj: Node3D) -> bool:
	# Bullet.launch() assigns its shooter after tree entry; resolve ownership here too.
	if not obj.has_meta("scrap_epoch"): tag_object(obj)
	if obj.has_meta("scrap_epoch"):
		return state==State.ACTIVE and obj.get_meta("scrap_epoch")==epoch and Space.in_ring(obj.global_position)
	return not Space.in_room(obj.global_position)

func _eliminated(id: int, _killer: int, _icon: String) -> void:
	if state!=State.ACTIVE: return
	for i in range(fighters.size()):
		if fighters[i].actor_id==id:
			var winner:=fighters[1-i]
			if not winner.is_bot and mode!="watch":
				Standings.award("local:"+str(winner.actor_id),winner.get_display_name())
				Standings.render(wins_board,false)
			finish(winner.get_display_name()+" WINS")
			return

func finish(message: String) -> void:
	if state==State.IDLE or state==State.RESULT: return
	state=State.RESULT
	result_text=message
	for actor in fighters:
		lab.playpen.clear_inventory(actor)
		actor.remove_from_group("player")
		actor.remove_from_group("combat_target")
	for ref in items:
		if is_instance_valid(ref.get_ref()): lab.playpen._retire(ref.get_ref())
	items.clear()
	for entry in lab.playpen.objects.values():
		var obj: Node=entry.ref.get_ref()
		if is_instance_valid(obj) and obj.has_meta("scrap_epoch"): lab.playpen._retire(obj)
	lab._sync_controls.call_deferred()
	_show_result.call_deferred()

func _show_result() -> void:
	if state==State.RESULT: lab._open("scrap")

func leave() -> void:
	if state==State.IDLE: return
	finish("ROUND CANCELLED")
	_stop_split()
	for actor in fighters:
		lab.playpen.members.erase(actor.get_instance_id())
		if actor==lab.pilot:
			actor.respawn(Transform3D(Basis.IDENTITY,Space.FOYER))
		else: actor.queue_free()
	fighters.clear()
	for entry in spectators:
		if is_instance_valid(entry.node):
			entry.node.transform=entry.transform
			entry.node.visible=entry.visible
	spectators.clear()
	state=State.IDLE
	lab.playpen.set_sparring_mode(saved_sparring)
	lab.pilot.get_gameplay_camera().make_current()
	lab._open("")
	_refresh()

func tick_bot(actor: CharacterBody3D, delta: float) -> void:
	var target: CharacterBody3D=actor.rival
	if not is_instance_valid(target) or target.is_eliminated: return
	actor._update_new_powerups(delta)
	actor._update_action_animation(delta)
	for key in ["lethal_immunity_timer","bullet_immune_timer","stagger_timer","knockback_timer"]:
		actor.set(key,maxf(0,float(actor.get(key))-delta))
	actor.stamina=minf(actor.MAX_STAMINA,actor.stamina+actor.STAMINA_REGEN_RATE*delta)
	# A disarm turns the sole loose gun into the next objective, even while
	# carrying melee. Otherwise two melee users can chase forever in the large ring.
	var loose_gun: Node3D=null
	if not actor.holding_gun:
		for ref in items:
			var obj: Node=ref.get_ref()
			if is_instance_valid(obj) and not obj.is_queued_for_deletion() and obj.is_in_group("gun") and not obj.is_held:
				loose_gun=obj
				break
		if is_instance_valid(loose_gun) and actor.nearby_interactables.has(loose_gun):
			if loose_gun.pick_up(actor):
				actor.active_slot="weapon"
				actor._update_active_slot_and_visuals()
				loose_gun=null
	var offset: Vector3=target.position-actor.position
	offset.y=0
	var distance:=offset.length()
	var destination: Vector3=loose_gun.global_position if is_instance_valid(loose_gun) else target.position
	var travel:=destination-actor.position
	travel.y=0
	var direction:=travel.normalized()
	if direction.is_zero_approx(): direction=Vector3.RIGHT if actor.actor_id%2 else Vector3.LEFT
	var aim: Vector3=actor.get_hold_point().global_position
	var ray:=PhysicsRayQueryParameters3D.create(aim,target.position+Vector3.UP*0.3,3,[actor.get_rid()])
	var hit:=actor.get_world_3d().direct_space_state.intersect_ray(ray)
	var clear: bool=hit.get("collider")==target
	var path_clear: bool=clear
	if is_instance_valid(loose_gun):
		var path:=PhysicsRayQueryParameters3D.create(actor.position+Vector3.UP*0.5,destination+Vector3.UP*0.5,1,[actor.get_rid()])
		var obstacle:=actor.get_world_3d().direct_space_state.intersect_ray(path)
		path_clear=obstacle.is_empty() or obstacle.get("collider")==loose_gun
	if not path_clear: direction=direction.rotated(Vector3.UP,0.9 if actor.actor_id%2 else -0.9)
	var speed: float=actor.SPEED*(0.55 if actor.holding_gun else 0.8)
	if actor.holding_gun and clear:
		direction=direction.rotated(Vector3.UP,PI/2)*0.5 + direction*(1.0 if distance>6 else -0.6)
	if actor.stagger_timer>0: speed=0
	actor.velocity.x=direction.x*speed
	actor.velocity.z=direction.z*speed
	if actor.knockback_timer>0:
		actor.velocity.x=actor.knockback_velocity.x
		actor.velocity.z=actor.knockback_velocity.z
	if not actor.is_on_floor(): actor.velocity.y-=actor.BASE_GRAVITY*delta
	elif actor.is_on_wall(): actor.velocity.y=actor.jump_velocity
	actor.move_and_slide()
	var model: Node3D=actor.get_node("CharacterModel")
	var facing:=Vector3(target.position.x,model.global_position.y,target.position.z)
	if model.global_position.distance_squared_to(facing)>0.0001: model.look_at(facing,Vector3.UP,true)
	actor._play_anim("standard_run" if speed>0 else "idle",false)
	if actor.holding_gun and clear and actor.stagger_timer<=0:
		for obj in actor.get_hold_point().get_children():
			if obj.is_in_group("gun"): obj.try_fire(); break
	elif is_instance_valid(actor.held_melee_weapon) and distance<2.4:
		actor._try_primary_action()

func _refresh() -> void:
	var text:="ONE ROUND / JOIN OR WATCH"
	match state:
		State.CALLING: text="PLAYER 2 CALLS / HEADS OR TAILS"
		State.FLIPPING: text="PLAYER 2 CALLED "+call_side.to_upper()
		State.COUNTDOWN: text="%s / %s GETS THE GUN\nSTARTS IN %d" % [coin_side.to_upper(),fighters[gun_index].get_display_name(),ceili(time_left)]
		State.ACTIVE: text="ONE ROUND / FIGHT!"
		State.RESULT: text=result_text
	if board: board.text=text
	banner.visible=not split_layer and Space.in_room(lab.pilot.position) and lab.ui.page.is_empty() and state!=State.IDLE
	banner.offset_top=360 if state in [State.FLIPPING,State.COUNTDOWN] else 178
	banner.text="THE SCRAP YARD\n"+text
	if split_layer:
		for label in split_layer.find_children("CoinCopy*","Label",true,false): label.text=text
	round_changed.emit()

func _start_split() -> void:
	default_disable_3d=lab.get_viewport().disable_3d
	split_layer=CanvasLayer.new()
	split_layer.layer=5
	lab.add_child(split_layer)
	var row:=HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation",2)
	split_layer.add_child(row)
	for i in range(2):
		var container:=SubViewportContainer.new()
		container.stretch=true
		container.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(container)
		var view:=SubViewport.new()
		view.world_3d=lab.get_world_3d()
		view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		view.use_occlusion_culling=true
		container.add_child(view)
		GraphicsQualityManager.APPLIER.apply_viewport(view,PlayerPrefs.settings)
		var camera:=Camera3D.new()
		view.add_child(camera)
		camera.current=true
		split_views.append(view)
		split_cameras.append(camera)
		var text: Label=lab.ui._label("",24,lab.ui.G.GOLD)
		text.name="CoinCopy%d" % i
		container.add_child(text)
		text.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		text.offset_left=-260
		text.offset_right=260
		text.offset_top=390
		text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var coin:=Coin.new()
		container.add_child(coin)
		coin.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		coin.offset_left=-90
		coin.offset_right=90
		coin.offset_top=195
		coin.offset_bottom=375
		split_coins.append(coin)
		var reticle: Label=lab.ui._label("+",28,lab.ui.G.PAPER)
		container.add_child(reticle)
		reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		reticle.offset_left=-10
		reticle.offset_top=-20
		reticle.offset_right=10
		reticle.offset_bottom=20
		reticle.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		split_reticles.append(reticle)
		var hud: Label=lab.ui._label("",21,lab.ui.G.PAPER)
		container.add_child(hud)
		hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		hud.offset_left=30
		hud.offset_right=-30
		hud.offset_top=-220
		hud.offset_bottom=-100
		hud.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		hud.add_theme_color_override("font_shadow_color",Color.BLACK)
		hud.add_theme_constant_override("shadow_offset_x",2)
		hud.add_theme_constant_override("shadow_offset_y",2)
		split_huds.append(hud)
	for node in [lab.ui.reticle]: node.hide()
	apply_quality()
	lab.get_viewport().disable_3d=true
	_route_p2()

func _update_split() -> void:
	if not split_layer or fighters.size()!=2: return
	for i in range(2):
		var source: Camera3D=fighters[i].get_gameplay_camera()
		split_cameras[i].global_transform=source.global_transform
		split_cameras[i].fov=source.fov
		var actor: CharacterBody3D=fighters[i]
		var weapon: String="GUN" if actor.holding_gun else (actor.held_melee_weapon.get_display_name() if is_instance_valid(actor.held_melee_weapon) else "EMPTY")
		var first: String=actor.held_item_1.get_display_name() if is_instance_valid(actor.held_item_1) else "EMPTY"
		var second: String=actor.held_item_2.get_display_name() if is_instance_valid(actor.held_item_2) else "EMPTY"
		split_huds[i].text="%s / %s\nDASH %d / STAMINA %d%%\nITEM 1: %s / ITEM 2: %s" % [actor.get_display_name(),weapon,actor.dash_charges,roundi(actor.stamina/actor.MAX_STAMINA*100),first,second]
		split_huds[i].visible=lab.ui.page.is_empty()
		split_reticles[i].visible=state==State.ACTIVE and lab.ui.page.is_empty()
	fighters[1].set_process_input(state==State.ACTIVE and lab.controls_enabled and not lab.automation)

func _stop_split() -> void:
	if split_layer:
		split_layer.queue_free()
		split_layer=null
		split_views.clear()
		split_cameras.clear()
		split_coins.clear()
		split_huds.clear()
		split_reticles.clear()
		for node in [lab.ui.reticle]: node.show()
		lab.get_viewport().disable_3d=default_disable_3d
		PlayerPrefs.refresh_input_devices()

func _exit_tree() -> void:
	if split_layer:
		lab.get_viewport().disable_3d=default_disable_3d
		PlayerPrefs.refresh_input_devices()

func _route_p2() -> void:
	var pads:=Input.get_connected_joypads()
	pads.sort()
	var slot:=1 if PlayerPrefs.is_using_controller("p1") else 0
	var device: int=pads[slot] if pads.size()>slot else PlayerPrefs.UNASSIGNED_JOYPAD_DEVICE
	PlayerPrefs._set_gamepad_device("p2_",device)

func gather_spectators() -> void:
	var visitors: Array=[]
	visitors.append_array(lab.guests)
	visitors.append_array(lab.resident_visuals.values())
	for tween in lab.visitor_tweens:
		if tween and tween.is_running(): tween.kill()
	var limit:=7 if mode=="watch" else 8
	for i in range(visitors.size()):
		var visitor: Node3D=visitors[i]
		spectators.append({"node":visitor,"transform":visitor.transform,"visible":visitor.visible})
		visitor.visible=i<limit
		if i>=limit: continue
		visitor.position=Space.spectator_position(i)
		visitor.look_at(Space.CENTER,Vector3.UP,true)

func _update_coin() -> void:
	var active: bool=state in [State.FLIPPING,State.COUNTDOWN] and lab.ui.page.is_empty()
	coin_visual.show_coin(active and not split_layer,state==State.FLIPPING,time_left,coin_side)
	for coin in split_coins: coin.show_coin(active,state==State.FLIPPING,time_left,coin_side)

func apply_quality() -> void:
	for view in split_views:
		GraphicsQualityManager.APPLIER.apply_viewport(view,PlayerPrefs.settings)
		if lab.low:
			view.scaling_3d_scale=0.75
			view.msaa_3d=Viewport.MSAA_DISABLED
			view.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
