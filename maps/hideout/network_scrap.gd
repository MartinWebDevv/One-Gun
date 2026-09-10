extends Node
## One host-owned duel; spectators never acquire fighter capabilities.
signal round_changed
const Space = preload("res://maps/hideout/scrap_space.gd")
const Coin = preload("res://maps/hideout/scrap_coin.gd")
enum State { IDLE, CALLING, FLIPPING, COUNTDOWN, ACTIVE, RESULT, RETURNING }
var lab: Node3D
var manager: Node
var state := State.IDLE
var fighter_ids: Array = []
var epoch := 0
var time_left := 0.0
var call_side := ""
var coin_side := ""
var gun_index := -1
var result_text := ""
const Standings=preload("res://maps/hideout/scrap_standings.gd")
var wins_board: Label3D
var board: Label3D
var banner: Label
var jumbotron: Node3D
var coin_visual: Control
var rng := RandomNumberGenerator.new()
var update_left := 0.0
var presented_state := -1
var presented_fighters: Array = []
var presented_positioning := false
var pending_arrivals: Dictionary = {}
var positioning := false
var pending_equipment: Dictionary = {}
var equipment_waiting := false
var winner_id := -1
var transition: CanvasLayer
var pending_returns: Dictionary = {}

func setup(preview: Node3D) -> void:
	lab = preview
	manager = get_parent()
	rng.randomize()
	transition=preload("res://maps/hideout/scrap_transition.gd").new()
	add_child(transition)
	board = lab.station.find_child("ScrapStatus",true,false)
	wins_board=lab.station.find_child("ScrapWinsRows",true,false)
	NetworkManager.lobby_changed.connect(_refresh_standings)
	_refresh_standings()
	banner = lab.ui._label("",27,lab.ui.G.GOLD)
	lab.ui.shell.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.offset_left=-470
	banner.offset_right=470
	banner.offset_top=178
	banner.offset_bottom=280
	banner.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	jumbotron=preload("res://maps/hideout/scrap_jumbotron.gd").new()
	jumbotron.name="ScrapJumbotron"
	lab.add_child(jumbotron)
	coin_visual = Coin.new()
	lab.ui.shell.add_child(coin_visual)
	coin_visual.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	coin_visual.offset_left=-90
	coin_visual.offset_right=90
	coin_visual.offset_top=260
	coin_visual.offset_bottom=440

func is_fighter_id(id: int) -> bool:
	return id in fighter_ids and state != State.IDLE

func is_fighter(actor: Node) -> bool:
	return is_instance_valid(actor) and is_fighter_id(actor.actor_id)

func can_fight(actor: Node3D) -> bool:
	return state==State.ACTIVE and is_fighter(actor) and not actor.is_eliminated and Space.in_ring(actor.global_position)

func pilot_locked() -> bool:
	return is_fighter_id(NetworkManager.local_actor_id()) and state in [State.CALLING,State.FLIPPING,State.COUNTDOWN,State.RESULT,State.RETURNING]

func can_call(id: int) -> bool:
	return state==State.CALLING and fighter_ids.size()==2 and fighter_ids[1]==id and not positioning

func join_round(_which: String) -> bool:
	_request("join","",epoch)
	return true

func choose(side: String, caller_id: int) -> bool:
	if caller_id != NetworkManager.local_actor_id() or not can_call(caller_id): return false
	_request("call",side,epoch)
	return true

func leave() -> void:
	_request("leave","",epoch)

func _request(action: String, value: String, request_epoch: int) -> void:
	if NetworkManager.is_host(): _accept(NetworkManager.local_actor_id(),action,value,request_epoch)
	else: _request_action.rpc_id(1,action,value,request_epoch)

@rpc("any_peer","reliable")
func _request_action(action: String, value: String, request_epoch: int) -> void:
	if NetworkManager.is_host():
		_accept(NetworkManager.actor_id_for_peer(multiplayer.get_remote_sender_id()),action,value,request_epoch)

func _accept(id: int, action: String, value: String, request_epoch: int) -> void:
	if NetworkManager._prelaunch_active: return
	# Two guests may click the idle board before the first signup reaches them.
	var concurrent_join := action=="join" and state==State.CALLING and fighter_ids.size()==1 and request_epoch==epoch-1
	if request_epoch != epoch and not concurrent_join: return
	var actor = NetworkManager.find_actor(id)
	if actor == null: return
	if state==State.RETURNING and is_fighter_id(id) and pending_returns.has(id):
		if action=="return_ready" and pending_returns[id]=="fade":
			pending_returns[id]="placed"
			_place_returning_fighter(id)
		elif action=="returned" and pending_returns[id]=="placed":
			pending_returns.erase(id)
			if pending_returns.is_empty(): _finish_return()
		return
	if actor.is_eliminated: return
	if action=="join":
		if state not in [State.IDLE,State.CALLING] or fighter_ids.size()>=2 or id in fighter_ids: return
		if not Space.at_terminal(actor.global_position):
			_notice(id,"Use the Join the Scrap screen in front of the arena.")
			return
		if state==State.IDLE:
			epoch += 1
			state = State.CALLING
			call_side=""
			coin_side=""
			result_text=""
			gun_index=-1
			winner_id=-1
		fighter_ids.append(id)
		manager.clear_inventory(actor)
		manager.training.cancel_runner(id)
		manager.memberships[id]="scrap"
		time_left=45.0
		pending_arrivals[id] = Time.get_ticks_msec()+12000
		positioning = true
		_publish()
	elif action=="arrived":
		_accept_arrival(id,request_epoch)
	elif action=="equipped" and state==State.COUNTDOWN and pending_equipment.has(id):
		pending_equipment.erase(id)
		if pending_equipment.is_empty():
			equipment_waiting=false
			time_left=3.0
			_publish()
	elif action=="call":
		if not can_call(id) or value not in ["heads","tails"]: return
		call_side=value
		coin_side="heads" if rng.randi_range(0,1)==0 else "tails"
		gun_index=1 if coin_side==call_side else 0
		state=State.FLIPPING
		time_left=2.0
		_publish()
	elif action=="leave" and is_fighter_id(id): cancel_round("FIGHTER LEFT")

func _position_fighter(id: int, duel_epoch: int, index: int) -> void:
	if duel_epoch!=epoch or not is_fighter_id(id) or index<0 or index>=Space.STARTS.size(): return
	var actor = NetworkManager.find_actor(id)
	if actor==null: return
	actor.recover_from_invalid_position(Space.STARTS[index],-PI/2 if index==0 else PI/2)
	if id!=NetworkManager.local_actor_id(): return
	# The owning client must apply the teleport before the host proceeds.
	await get_tree().physics_frame
	if not is_inside_tree() or duel_epoch!=epoch or state!=State.CALLING: return
	_request("arrived","",duel_epoch)

func _accept_arrival(id: int, duel_epoch: int) -> void:
	if duel_epoch!=epoch or state!=State.CALLING or not pending_arrivals.has(id): return
	pending_arrivals.erase(id)
	positioning = not pending_arrivals.is_empty()
	_publish()

func _notice(id: int, message: String) -> void:
	var peer := NetworkManager.peer_id_for_actor(id)
	if peer == NetworkManager.local_id(): lab.ui.show_toast(message)
	elif peer > 0: _receive_notice.rpc_id(peer,message)

@rpc("authority","reliable")
func _receive_notice(message: String) -> void:
	lab.ui.show_toast(message)

func _process(delta: float) -> void:
	if lab == null: return
	if state!=State.IDLE:
		if not equipment_waiting: time_left=maxf(0,time_left-delta)
		if NetworkManager.is_host():
			if state in [State.CALLING,State.FLIPPING,State.COUNTDOWN,State.ACTIVE]:
				for id in fighter_ids:
					var actor = NetworkManager.find_actor(int(id))
					# Client-owned transforms can briefly replay the pre-teleport position.
					# Enforce ring bounds once placement, coin and countdown have completed.
					if actor==null or not NetworkManager.peers.has(actor.owner_peer_id) or (state==State.ACTIVE and not Space.in_ring(actor.position)):
						cancel_round("DUEL CANCELLED / FIGHTER LEFT")
						break
			for id in pending_arrivals:
				if Time.get_ticks_msec()>int(pending_arrivals[id]):
					cancel_round("DUEL CANCELLED / PLAYER DID NOT ARRIVE")
					break
			for id in pending_equipment:
				if Time.get_ticks_msec()>int(pending_equipment[id]):
					cancel_round("DUEL CANCELLED / EQUIPMENT NOT READY")
					break
			if time_left<=0 and not equipment_waiting:
				match state:
					State.CALLING: cancel_round("NO CHALLENGER / CALL TIMED OUT")
					State.FLIPPING: _prepare_countdown()
					State.COUNTDOWN: _begin_combat()
					State.RESULT: _return_fighters()
					State.RETURNING:
						for id in pending_returns: _place_returning_fighter(int(id))
						_finish_return()
	update_left-=delta
	if update_left<=0:
		update_left=0.1
		var next_text:=status_text()
		var names: Array=[]
		for id in fighter_ids: names.append(NetworkManager.peer_name(NetworkManager.peer_id_for_actor(int(id))))
		jumbotron.present(names if state==State.ACTIVE else [],next_text,coin_side,state==State.FLIPPING,state in [State.FLIPPING,State.COUNTDOWN],time_left)
		if board.text!=next_text: board.text=next_text
		var local_fighter := is_fighter_id(NetworkManager.local_actor_id())
		banner.visible=local_fighter
		if banner.text!=next_text: banner.text=next_text
		coin_visual.show_coin(local_fighter and state in [State.FLIPPING,State.COUNTDOWN],state==State.FLIPPING,time_left,coin_side)

func _prepare_countdown() -> void:
	state=State.COUNTDOWN
	time_left=3.0
	equipment_waiting=true
	for id in fighter_ids: pending_equipment[id]=Time.get_ticks_msec()+12000
	_publish()
	# Instantiate/attach gear while input is locked, before the three-second count.
	# Each movement owner acknowledges its local gear before combat may unlock.
	manager.spawn_duel_gear(epoch,fighter_ids,gun_index)

func equipment_prepared(duel_epoch: int) -> void:
	if duel_epoch!=epoch or state!=State.COUNTDOWN: return
	if is_fighter_id(NetworkManager.local_actor_id()): _request("equipped","",duel_epoch)

func _begin_combat() -> void:
	for id in fighter_ids:
		var actor = NetworkManager.find_actor(int(id))
		if actor==null or not Space.in_ring(actor.global_position):
			cancel_round("DUEL CANCELLED / PLAYER DID NOT ARRIVE")
			return
	state=State.ACTIVE
	time_left=0
	_publish()

func finish_elimination(victim: int) -> void:
	if not NetworkManager.is_host() or state!=State.ACTIVE or not is_fighter_id(victim): return
	var winner: int = fighter_ids[1] if fighter_ids[0]==victim else fighter_ids[0]
	winner_id=winner
	Standings.award(str(winner),NetworkManager.peer_name(NetworkManager.peer_id_for_actor(winner)))
	result_text = NetworkManager.peer_name(NetworkManager.peer_id_for_actor(winner))+" WINS"
	_finish()

func cancel_round(message: String) -> void:
	if not NetworkManager.is_host() or state==State.IDLE or state==State.RESULT: return
	result_text=message
	_finish()

func _finish() -> void:
	pending_arrivals.clear()
	pending_equipment.clear()
	equipment_waiting=false
	positioning=false
	state=State.RESULT
	time_left=3.0
	manager.clear_duel_gear(epoch,fighter_ids)
	_publish()

func _return_fighters() -> void:
	state=State.RETURNING
	time_left=8.0
	for id in fighter_ids:
		if NetworkManager.find_actor(int(id))!=null: pending_returns[id]="fade"
	_publish()
	if pending_returns.is_empty(): _finish_return()

func _place_returning_fighter(id: int) -> void:
	var index := fighter_ids.find(id)
	if index<0 or NetworkManager.find_actor(id)==null: return
	NetworkManager.broadcast_match_rpc(manager,&"_net_respawn",[id,Space.TERMINAL_USE+Vector3(-1.5 if index==0 else 1.5,0,1),0.0])
	if manager.online_actor_state.has(id): manager.online_actor_state[id]["alive"]=true

func return_placed(id: int) -> void:
	if state!=State.RETURNING or id!=NetworkManager.local_actor_id(): return
	var expected := epoch
	await get_tree().physics_frame
	if state==State.RETURNING and epoch==expected: _request("returned","",expected)

func _fade_for_return(expected: int) -> void:
	var local_fighter := is_fighter_id(NetworkManager.local_actor_id())
	if state!=State.RETURNING or epoch!=expected or not local_fighter: return
	await transition.fade(1.0,local_fighter)
	if state==State.RETURNING and epoch==expected and is_fighter_id(NetworkManager.local_actor_id()):
		_request("return_ready","",expected)

func _finish_return() -> void:
	pending_returns.clear()
	manager._broadcast_online_state()
	fighter_ids.clear()
	state=State.IDLE
	_publish()

func status_text() -> String:
	match state:
		State.IDLE: return "JOIN THE SCRAP / ONE ROUND"
		State.CALLING: return "GETTING FIGHTERS READY" if positioning else "WAITING FOR A CHALLENGER" if fighter_ids.size()<2 else "SECOND PLAYER / HEADS OR TAILS?"
		State.FLIPPING: return "CALL: "+call_side.to_upper()+" / FLIPPING"
		State.COUNTDOWN: return coin_side.to_upper()+" / PREPARING GEAR" if equipment_waiting else coin_side.to_upper()+" / STARTING IN %d" % ceili(time_left)
		State.ACTIVE: return "SCRAP! / ONE ROUND"
		State.RESULT: return result_text+" / RETURNING IN %d" % ceili(time_left)
		State.RETURNING: return "RETURNING TO THE SCRAP YARD"
	return ""

func _snapshot() -> Dictionary:
	return {"state":state,"fighters":fighter_ids,"epoch":epoch,"remaining":time_left,"call":call_side,"coin":coin_side,"gun":gun_index,"result":result_text,"positioning":positioning,"equipment_waiting":equipment_waiting,"wins":HideoutSession.scrap_lobby_wins,"winner":winner_id}

func _publish() -> void:
	NetworkManager.broadcast_match_rpc(self,&"_receive",[_snapshot()])

func send_snapshot(peer: int) -> void:
	_receive.rpc_id(peer,_snapshot())

@rpc("authority","reliable","call_local")
func _receive(data: Dictionary) -> void:
	var changed: bool = presented_state!=int(data.state) or presented_fighters!=data.fighters or presented_positioning!=bool(data.get("positioning",false))
	var was_fighter := NetworkManager.local_actor_id() in presented_fighters
	var previous_fighters := presented_fighters.duplicate()
	presented_positioning=bool(data.get("positioning",false))
	presented_state=int(data.state)
	presented_fighters=data.fighters.duplicate()
	state=int(data.state)
	fighter_ids=data.fighters.duplicate()
	epoch=int(data.epoch)
	time_left=float(data.remaining)
	call_side=str(data.call)
	coin_side=str(data.coin)
	gun_index=int(data.gun)
	result_text=str(data.result)
	winner_id=int(data.get("winner",-1))
	positioning=bool(data.get("positioning",false))
	equipment_waiting=bool(data.get("equipment_waiting",false))
	HideoutSession.scrap_lobby_wins=data.get("wins",{}).duplicate(true)
	_refresh_standings()
	if not is_fighter_id(NetworkManager.local_actor_id()) and not was_fighter:
		transition.reset()
	if not is_fighter_id(NetworkManager.local_actor_id()): coin_visual.hide()
	if changed:
		if state==State.RESULT and winner_id>=0:
			var winner=NetworkManager.find_actor(winner_id)
			if is_instance_valid(winner): winner.play_victory_dance()
		if state==State.RETURNING and is_fighter_id(NetworkManager.local_actor_id()):
			_fade_for_return(epoch)
		elif state==State.IDLE and was_fighter: transition.fade(0.0,was_fighter)
		var local_fighter := is_fighter_id(NetworkManager.local_actor_id())
		if local_fighter and state==State.CALLING:
			lab._open("scrap")
		elif (local_fighter or was_fighter) and lab.ui.page=="scrap":
			# Signup must release input before combat and reveal the shared coin.
			lab._open("")
		elif lab.ui.page=="scrap": lab.ui.show_page("scrap")
		if state==State.CALLING:
			for index in fighter_ids.size():
				if fighter_ids[index] not in previous_fighters:
					_position_fighter(int(fighter_ids[index]),epoch,index)
	lab._sync_controls()
	round_changed.emit()

func _refresh_standings() -> void:
	Standings.render(wins_board,true)

func apply_quality() -> void:
	pass
