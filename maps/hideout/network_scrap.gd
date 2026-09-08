extends Node
## One host-owned duel; spectators never acquire fighter capabilities.
signal round_changed
const Space = preload("res://maps/hideout/scrap_space.gd")
const Coin = preload("res://maps/hideout/scrap_coin.gd")
enum State { IDLE, CALLING, FLIPPING, COUNTDOWN, ACTIVE, RESULT }
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
var board: Label3D
var banner: Label
var coin_visual: Control
var rng := RandomNumberGenerator.new()
var update_left := 0.0
var presented_state := -1
var presented_fighters: Array = []

func setup(preview: Node3D) -> void:
	lab = preview
	manager = get_parent()
	rng.randomize()
	board = lab.station.find_child("ScrapStatus",true,false)
	banner = lab.ui._label("",27,lab.ui.G.GOLD)
	lab.ui.shell.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.offset_left=-470
	banner.offset_right=470
	banner.offset_top=178
	banner.offset_bottom=280
	banner.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
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
	return is_fighter_id(NetworkManager.local_actor_id()) and state in [State.CALLING,State.FLIPPING,State.COUNTDOWN,State.RESULT]

func can_call(id: int) -> bool:
	return state==State.CALLING and fighter_ids.size()==2 and fighter_ids[1]==id

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
	if request_epoch != epoch or NetworkManager._prelaunch_active: return
	var actor = NetworkManager.find_actor(id)
	if actor == null or actor.is_eliminated: return
	if action=="join":
		if state not in [State.IDLE,State.CALLING] or fighter_ids.size()>=2 or id in fighter_ids: return
		if not Space.in_room(actor.position):
			_notice(id,"Enter the Scrap Yard to join a duel.")
			return
		if state==State.IDLE:
			epoch += 1
			state = State.CALLING
			call_side=""
			coin_side=""
			result_text=""
			gun_index=-1
		fighter_ids.append(id)
		manager.clear_inventory(actor)
		manager.training.cancel_runner(id)
		manager.memberships[id]="scrap"
		time_left=45.0
		NetworkManager.broadcast_match_rpc(manager,&"_net_recover_playpen_actor",[id,Space.STARTS[fighter_ids.size()-1],-PI/2 if fighter_ids.size()==1 else PI/2])
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
		time_left=maxf(0,time_left-delta)
		if NetworkManager.is_host():
			if state in [State.CALLING,State.FLIPPING,State.COUNTDOWN,State.ACTIVE]:
				for id in fighter_ids:
					var actor = NetworkManager.find_actor(int(id))
					if actor==null or not Space.in_ring(actor.position):
						cancel_round("DUEL CANCELLED / FIGHTER LEFT")
						break
			if time_left<=0:
				match state:
					State.CALLING: cancel_round("NO CHALLENGER / CALL TIMED OUT")
					State.FLIPPING: state=State.COUNTDOWN; time_left=3.0; _publish()
					State.COUNTDOWN: _begin_combat()
					State.RESULT: _return_fighters()
	update_left-=delta
	if update_left<=0:
		update_left=0.1
		board.text=status_text()
		var local_fighter := is_fighter_id(NetworkManager.local_actor_id())
		banner.visible=local_fighter
		banner.text=status_text()
		coin_visual.show_coin(local_fighter and state in [State.FLIPPING,State.COUNTDOWN],state==State.FLIPPING,time_left,coin_side)

func _begin_combat() -> void:
	state=State.ACTIVE
	time_left=0
	_publish()
	manager.spawn_duel_gear(epoch,fighter_ids,gun_index)

func finish_elimination(victim: int) -> void:
	if not NetworkManager.is_host() or state!=State.ACTIVE or not is_fighter_id(victim): return
	var winner: int = fighter_ids[1] if fighter_ids[0]==victim else fighter_ids[0]
	result_text = NetworkManager.peer_name(NetworkManager.peer_id_for_actor(winner))+" WINS"
	_finish()

func cancel_round(message: String) -> void:
	if not NetworkManager.is_host() or state==State.IDLE or state==State.RESULT: return
	result_text=message
	_finish()

func _finish() -> void:
	state=State.RESULT
	time_left=6.0
	manager.clear_duel_gear(epoch,fighter_ids)
	_publish()

func _return_fighters() -> void:
	for id in fighter_ids:
		var actor = NetworkManager.find_actor(int(id))
		if actor == null: continue
		NetworkManager.broadcast_match_rpc(manager,&"_net_respawn",[id,Space.FOYER+Vector3(0,0,1),0.0])
		if manager.online_actor_state.has(id): manager.online_actor_state[id]["alive"]=true
	manager._broadcast_online_state()
	fighter_ids.clear()
	state=State.IDLE
	_publish()

func status_text() -> String:
	match state:
		State.IDLE: return "JOIN THE SCRAP / ONE ROUND"
		State.CALLING: return "WAITING FOR A CHALLENGER" if fighter_ids.size()<2 else "SECOND PLAYER / HEADS OR TAILS?"
		State.FLIPPING: return "CALL: "+call_side.to_upper()+" / FLIPPING"
		State.COUNTDOWN: return coin_side.to_upper()+" / STARTING IN %d" % ceili(time_left)
		State.ACTIVE: return "SCRAP! / ONE ROUND"
		State.RESULT: return result_text
	return ""

func _snapshot() -> Dictionary:
	return {"state":state,"fighters":fighter_ids,"epoch":epoch,"remaining":time_left,"call":call_side,"coin":coin_side,"gun":gun_index,"result":result_text}

func _publish() -> void:
	NetworkManager.broadcast_match_rpc(self,&"_receive",[_snapshot()])

func send_snapshot(peer: int) -> void:
	_receive.rpc_id(peer,_snapshot())

@rpc("authority","reliable","call_local")
func _receive(data: Dictionary) -> void:
	var changed: bool = presented_state!=int(data.state) or presented_fighters!=data.fighters
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
	if changed and lab.ui.page=="scrap": lab.ui.show_page("scrap")
	lab._sync_controls()
	round_changed.emit()

func apply_quality() -> void:
	pass
