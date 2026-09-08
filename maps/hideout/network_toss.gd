extends "res://maps/hideout/trickshot_toss.gd"
var send_left := 0.0
var initialized := false

func setup(preview: Node3D) -> void:
	super.setup(preview)
	initialized = true

func throw_ball() -> bool:
	if not lab.controls_enabled: return false
	if NetworkManager.is_host(): return _throw_for(NetworkManager.local_actor_id(),lab.pilot.get_aim_direction())
	_request_throw.rpc_id(1,lab.pilot.get_aim_direction())
	return true

@rpc("any_peer","reliable")
func _request_throw(direction: Vector3) -> void:
	if NetworkManager.is_host(): _throw_for(NetworkManager.actor_id_for_peer(multiplayer.get_remote_sender_id()),direction)

func _throw_for(id: int, direction: Vector3) -> bool:
	var actor = NetworkManager.find_actor(id)
	if actor == null or actor.is_eliminated or flying or not direction.is_finite() or direction.length_squared()<0.8 or direction.length_squared()>1.2: return false
	if actor.position.distance_to(ORIGIN+Vector3(0,1,0))>5.0: return false
	ball.position = actor.position+Vector3(0,0.65,0)+direction*0.6
	velocity = direction*10.5+Vector3.UP*3.0
	flying = true
	flight_left = 6.0
	banked = false
	attempts += 1
	set_physics_process(true)
	_publish()
	return true

func _physics_process(delta: float) -> void:
	if not NetworkManager.is_host(): return
	super._physics_process(delta)
	send_left -= delta
	if send_left <= 0:
		send_left = 0.1
		_publish()

func reset_ball() -> void:
	super.reset_ball()
	if initialized and NetworkManager.is_host(): _publish()

func _snapshot() -> Dictionary:
	return {"position":ball.position,"velocity":velocity,"flying":flying,"score":score,"attempts":attempts}

func _publish() -> void:
	NetworkManager.broadcast_match_rpc(self,&"_receive",[_snapshot()])

func send_snapshot(id: int) -> void:
	_receive.rpc_id(id,_snapshot())

@rpc("authority","reliable","call_local")
func _receive(data: Dictionary) -> void:
	if not NetworkManager.is_host():
		ball.position = data.position
		velocity = data.velocity
		flying = data.flying
	score = int(data.score)
	attempts = int(data.attempts)
	label.text = "%d POINTS / %d THROWS / AIM + INTERACT" % [score,attempts]
