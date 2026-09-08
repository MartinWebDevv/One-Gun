extends "res://maps/hideout/training.gd"
## Host clocks/checkpoints for every runner. UI pages remain viewer-local.
var manager: Node
var runners: Dictionary = {}
var initializing := true
var sync_left := 0.0
var personal_store: RefCounted
var personal_key := ""
var displayed_time := 0.0
var state_dirty := false
var selected_modes: Dictionary = {}
var live_times: Dictionary = {}
var received_at := 0

func setup(preview: Node3D) -> void:
	manager = get_parent()
	super.setup(preview)
	initializing = false
	records.configure("")
	records.lobby_times = HideoutSession.course_lobby_times.duplicate(true)
	records.lobby_details = HideoutSession.course_lobby_details.duplicate(true)
	personal_store = Records.new()
	personal_store.configure("" if lab.automation else "user://hideout/online_course_records.json")
	var account := SupabaseManager.current_user_id()
	personal_key = "account:"+account.sha256_text() if account != "" else "local:profile"
	personal_store.set_members([{"id":personal_key,"name":NetworkManager.local_name()}])
	_refresh_records()

func movement_key() -> String:
	var jump := 7.0 if not is_instance_valid(lab.pilot) else float(lab.pilot.jump_velocity)
	return "%s/dash%d/sprint%d/jump%.3f" % [Space.Course.COURSE_ID,GameConfig.max_dash_charges,int(GameConfig.sprinting_enabled),jump]

func rules_caption() -> String:
	return "%d DASHES / SPRINT %s" % [GameConfig.max_dash_charges,"ON" if GameConfig.sprinting_enabled else "OFF"]

func viewer_id() -> String:
	return str(NetworkManager.local_actor_id())

func refresh_roster() -> void:
	if records == null: return
	var roster: Array = []
	for id in NetworkManager.peer_ids_sorted():
		roster.append({"id":str(NetworkManager.actor_id_for_peer(id)),"name":NetworkManager.peer_name(id)})
	records.set_members(roster)

func set_distance(lane: int, index: int) -> void:
	if initializing: super.set_distance(lane,index); return
	if lane < 0 or lane >= 3 or index < 0 or index >= Space.DISTANCES.size(): return
	if NetworkManager.is_host(): _set_range(lane,index)
	else: _request_range.rpc_id(1,lane,index)

@rpc("any_peer","reliable")
func _request_range(lane: int, index: int) -> void:
	if NetworkManager.is_host() and NetworkManager.is_peer_in_playpen(multiplayer.get_remote_sender_id()):
		_set_range(lane,index)

func _set_range(lane: int, index: int) -> void:
	if lane < 0 or lane >= 3 or index < 0 or index >= Space.DISTANCES.size(): return
	super.set_distance(lane,index)
	_publish()

func target_hit(lane: int) -> void:
	if not NetworkManager.is_host() or lane < 0 or lane >= 3: return
	hits[lane] += 1
	_refresh_lane(lane)
	_publish()

func reset_hits() -> void:
	if NetworkManager.is_host(): _reset_hits()
	else: _request_reset_hits.rpc_id(1)

@rpc("any_peer","reliable")
func _request_reset_hits() -> void:
	if NetworkManager.is_host() and NetworkManager.is_peer_in_playpen(multiplayer.get_remote_sender_id()): _reset_hits()

func _reset_hits() -> void:
	hits = [0,0,0]
	_publish()

func select_mode(powered: bool) -> void:
	if NetworkManager.is_host(): _select_mode(NetworkManager.local_actor_id(),powered)
	else: _request_mode.rpc_id(1,powered)

@rpc("any_peer","reliable")
func _request_mode(powered: bool) -> void:
	if NetworkManager.is_host(): _select_mode(NetworkManager.actor_id_for_peer(multiplayer.get_remote_sender_id()),powered)

func _select_mode(id: int, powered: bool) -> void:
	var actor=NetworkManager.find_actor(id)
	if not can_select_mode(actor,powered): return
	cancel_runner(id)
	selected_modes[id]=powered
	NetworkManager.broadcast_match_rpc(self,&"_course_loadout",[id,powered,false])

@rpc("authority","reliable","call_local")
func _course_loadout(id: int, powered: bool, start: bool) -> void:
	var actor=NetworkManager.find_actor(id)
	if actor==null: return
	if start: Loadout.start(actor,powered)
	else: Loadout.clear(actor)
	if id==NetworkManager.local_actor_id() and not start:
		selected_powerup=powered
		lab.ui.show_toast(("POWER-UP RUN" if powered else "STANDARD RUN")+" READY / CROSS THE START LINE")

func _gate_entered(body: Node3D, index: int) -> void:
	if not NetworkManager.is_host() or not body is CharacterBody3D or not "actor_id" in body or body.is_eliminated: return
	var id: int = body.actor_id
	if index == 0:
		if not runners.has(id):
			refresh_roster()
			var powered: bool=selected_modes.get(id,false)
			runners[id] = {"start":Time.get_ticks_msec(),"penalty":0,"next":1,"falls":0,"rules":movement_key(),"assisted":powered,"recovery":Space.RECOVERY[0]}
			NetworkManager.broadcast_match_rpc(self,&"_course_loadout",[id,powered,true])
			_publish(false)
		return
	if not runners.has(id) or int(runners[id].next) != index: return
	var run: Dictionary = runners[id]
	if index == Space.COURSE_GATES.size()-1:
		var time_ms := maxi(1,Time.get_ticks_msec()-int(run.start)+int(run.penalty))
		var bucket: String = run.rules+("/powerup" if bool(run.assisted) else "/standard")
		runners.erase(id)
		refresh_roster()
		last_finish_text="%s / %s / %s" % [NetworkManager.peer_name(NetworkManager.peer_id_for_actor(id)),"POWER-UP" if bool(run.assisted) else "STANDARD",format_time(time_ms/1000.0)]
		if not records.submit_completed_run(bucket,str(id),time_ms,int(run.falls)):
			NetworkManager.broadcast_match_rpc(self,&"_clear_run_powers",[id])
			push_warning("Course finish rejected: invalid time or missing roster member")
			_publish()
			return
		NetworkManager.broadcast_match_rpc(self,&"_finished",[id,bucket,time_ms])
		_publish()
	else:
		run.next = index+1
		run.recovery = Space.RECOVERY[index]

func _assisted(actor: Node) -> bool:
	return actor.speed_surge_timer>0 or actor.double_jump_shoes_active or actor.extra_dash_charge>0 or not is_equal_approx(actor.slow_multiplier_value,1.0) or actor._spring_air_active or actor._directional_launch_active

func _physics_process(delta: float) -> void:
	if initializing: return
	if NetworkManager.is_host():
		for id in runners.keys():
			var actor = NetworkManager.find_actor(int(id))
			if actor == null or actor.is_eliminated or movement_key()!=str(runners[id].rules):
				cancel_runner(int(id))
				continue
			var p: Vector3 = actor.position
			if not Space.in_course(p) and not (p.x < -7 and p.z < -67.5 and p.z > -74):
				cancel_runner(int(id))
				continue

		for actor in lab.get_node("NetPlayers").get_children():
			if Space.in_course(actor.position) and actor.position.y < -2 and not actor.is_eliminated:
				var at: Vector3 = Space.RECOVERY[0]
				if runners.has(actor.actor_id):
					runners[actor.actor_id].penalty += 2000
					runners[actor.actor_id].falls += 1
					at = runners[actor.actor_id].recovery
				NetworkManager.broadcast_match_rpc(manager,&"_net_recover_playpen_actor",[actor.actor_id,at,PI/2])
		sync_left -= delta
		if sync_left <= 0:
			sync_left = 0.1
			if not runners.is_empty() or state_dirty: _publish(false)
	board_tick-=delta
	if board_tick<=0:
		board_tick=0.2
		_render_wall_records()
		preload("res://maps/hideout/course_board_ui.gd").refresh_live(lab.ui,self)
	show_result = maxf(0,show_result-delta)
	if not is_instance_valid(lab.pilot): return
	var run: Dictionary = runners.get(NetworkManager.local_actor_id(),{})
	running = not run.is_empty()
	displayed_time += delta if running else 0.0
	hud.visible = lab.ui.page.is_empty() and (running or show_result > 0)
	hud.text = "AGILITY / "+(format_time(displayed_time) if running else status)
	if running: hud.text += "\n%s / CHECKPOINT %d / 5 / FALLS %d" % ["POWER-UP" if bool(run.assisted) else "STANDARD",int(run.next)-1,int(run.falls)]

func _snapshot(include_records := true) -> Dictionary:
	var times: Dictionary = {}
	for id in runners: times[id] = Time.get_ticks_msec()-int(runners[id].start)+int(runners[id].penalty)
	var data := {"indices":range_indices,"hits":hits,"runners":runners,"times":times,"last_finish":last_finish_text}
	if include_records:
		data["records"]=records.lobby_times
		data["details"]=records.lobby_details
	return data

func _publish(include_records := true) -> void:
	state_dirty = false
	NetworkManager.broadcast_match_rpc(self,&"_receive",[_snapshot(include_records)])

func send_snapshot(id: int) -> void:
	_receive.rpc_id(id,_snapshot())

@rpc("authority","reliable","call_local")
func _receive(data: Dictionary) -> void:
	var records_changed: bool = data.has("records") and (records.lobby_times!=data.records or records.lobby_details!=data.get("details",{}))
	for lane in range(3):
		if range_indices[lane]!=data.indices[lane]: super.set_distance(lane,int(data.indices[lane]))
	range_indices = data.indices.duplicate()
	for lane in range(3):
		if int(data.hits[lane])>int(hits[lane]): targets[lane].flash_hit()
		if int(data.hits[lane])!=int(hits[lane]):
			hits[lane]=int(data.hits[lane])
			_refresh_lane(lane)
	if not NetworkManager.is_host(): runners = data.runners.duplicate(true)
	if data.has("records"):
		records.lobby_times = data.records.duplicate(true)
		records.lobby_details = data.get("details",{}).duplicate(true)
		HideoutSession.course_lobby_times = records.lobby_times.duplicate(true)
		HideoutSession.course_lobby_details = records.lobby_details.duplicate(true)
	live_times=data.times.duplicate()
	received_at=Time.get_ticks_msec()
	last_finish_text=str(data.get("last_finish",""))
	displayed_time = float(data.times.get(NetworkManager.local_actor_id(),0))/1000.0
	if records_changed: _refresh_records()

@rpc("authority","reliable","call_local")
func _finished(id: int, bucket: String, time_ms: int) -> void:
	var actor=NetworkManager.find_actor(id)
	if actor!=null: Loadout.clear(actor)
	if id != NetworkManager.local_actor_id(): return
	personal_store.submit_completed_run(bucket,personal_key,time_ms)
	if not records.personal_times.has(bucket): records.personal_times[bucket] = {}
	records.personal_times[bucket][viewer_id()] = personal_store.personal_best(bucket,personal_key)
	last_time = time_ms/1000.0
	status = "FINISHED / "+format_time(last_time)
	show_result = 12
	lab.ui.show_toast(status)
	_refresh_records()

func _refresh_records() -> void:
	if personal_store != null and records != null:
		for bucket in personal_store.personal_times:
			records.personal_times[bucket] = {viewer_id():personal_store.personal_best(bucket,personal_key)}
	super._refresh_records()

func cancel_runner(id: int) -> void:
	if NetworkManager.is_host() and runners.has(id):
		runners.erase(id)
		NetworkManager.broadcast_match_rpc(self,&"_clear_run_powers",[id])
		_publish(false)

@rpc("authority","reliable","call_local")
func _clear_run_powers(id: int) -> void:
	var actor=NetworkManager.find_actor(id)
	if actor!=null: Loadout.clear(actor)

func live_status(id: String, powered: bool) -> String:
	var run: Dictionary=runners.get(int(id),{})
	if run.is_empty() or bool(run.assisted)!=powered: return ""
	var ms: int=Time.get_ticks_msec()-int(run.start)+int(run.penalty) if NetworkManager.is_host() else int(live_times.get(int(id),0))+Time.get_ticks_msec()-received_at
	return "RUNNING %s / CP %d / %d FALLS" % [format_time(ms/1000.0),int(run.next)-1,int(run.falls)]

func cancel_all() -> void:
	if NetworkManager.is_host():
		for id in runners.keys(): cancel_runner(int(id))

func cancel_trial(_message := "RUN CANCELLED") -> void:
	if NetworkManager.is_host(): cancel_runner(NetworkManager.local_actor_id())
	else: _request_cancel.rpc_id(1)

@rpc("any_peer","reliable")
func _request_cancel() -> void:
	if NetworkManager.is_host(): cancel_runner(NetworkManager.actor_id_for_peer(multiplayer.get_remote_sender_id()))

func restart_trial() -> void:
	if NetworkManager.is_host(): _restart(NetworkManager.local_actor_id())
	else: _request_restart.rpc_id(1)
	lab._open("")

@rpc("any_peer","reliable")
func _request_restart() -> void:
	if NetworkManager.is_host(): _restart(NetworkManager.actor_id_for_peer(multiplayer.get_remote_sender_id()))

func _restart(id: int) -> void:
	var actor = NetworkManager.find_actor(id)
	if actor == null or actor.is_eliminated: return
	cancel_runner(id)
	manager.clear_inventory(actor)
	NetworkManager.broadcast_match_rpc(manager,&"_net_recover_playpen_actor",[id,Vector3(-8,-0.11,-42.25),PI/2])
