extends Node3D
const G = preload("res://geometry.gd")
const Station = preload("res://station.gd")
const Pilot = preload("res://pilot.gd")
const Interface = preload("res://interface.gd")
const Session = preload("res://session.gd")
const Avatar = preload("res://avatar.gd")
var session := Session.new()
var station: Node3D
var pilot: CharacterBody3D
var ui: CanvasLayer
var guests: Array[Node3D] = []
var nearby: Array[String] = []
var low := true
var entered := false
var previous_phase := -1
var update_left := 0.0
var shot_cooldown := 0.0
var target_tweens: Array[Tween] = []
var visitor_tweens: Array[Tween] = []
var cue: AudioStreamPlayer

func _ready() -> void:
	station = Station.new()
	add_child(station)
	pilot = Pilot.new()
	add_child(pilot)
	pilot.respawn()
	ui = Interface.new()
	ui.session = session
	add_child(ui)
	ui.action.connect(_action)
	session.changed.connect(_refresh)
	session.notice.connect(ui.show_toast)
	session.friend_added.connect(_arrive)
	session.friend_removed.connect(_remove_guest)
	station.station_entered.connect(func(id):
		if not nearby.has(id): nearby.append(id)
	)
	station.station_exited.connect(func(id): nearby.erase(id))
	for i in range(station.targets.size()): target_tweens.append(null)
	_make_cue()
	low = not OS.get_cmdline_user_args().has("--high")
	apply_quality()
	_refresh()
	_open("intro")
	if OS.get_cmdline_user_args().has("--validate"):
		_run_validation.call_deferred()
	elif OS.get_cmdline_user_args().has("--capture"):
		_run_capture.call_deferred()

func _process(delta: float) -> void:
	for i in range(guests.size()):
		if visitor_tweens[i] and visitor_tweens[i].is_running():
			guests[i].get_child(0).animate(delta,4.0)
	session.tick(delta)
	shot_cooldown = maxf(0,shot_cooldown-delta)
	update_left -= delta
	if update_left <= 0:
		update_left = 0.1
		var charge_count := 0
		for charge in pilot.charges:
			if charge<=0: charge_count += 1
		ui.update_readouts(0.1,Engine.get_frames_per_second(),charge_count,low)
		var hint := ""
		if entered and ui.page.is_empty() and not nearby.is_empty():
			match nearby.back():
				"range": hint = "LIGHT TRAINER / AIM AT A TARGET + LEFT CLICK   /   [T] RESET SCORE"
				"course": hint = "MOVEMENT LINE / SPACE TO JUMP / SHIFT TO DASH"
				"departure": hint = "DEPARTURES / [TAB] SELECT AN EVENT / [R] ACCEPT WHEN READY"
				var id: hint = "[E] "+str(id).to_upper()+"   /   SHORTCUTS WORK FROM ANYWHERE"
		ui.context.text = hint

func _input(event: InputEvent) -> void:
	if not entered: return
	if event is InputEventKey and event.pressed and not event.echo:
		# Global ready/cancel works over any local station overlay.
		if event.physical_keycode == KEY_R and session.phase == Session.Phase.FOUND:
			_action("accept",null)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_X and session.phase in [Session.Phase.SEARCHING,Session.Phase.FOUND,Session.Phase.DEPARTING]:
			_action("cancel",null)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_ESCAPE:
			if ui.page == "away": return
			_open("pause" if ui.page.is_empty() else "")
			get_viewport().set_input_as_handled()
		elif session.phase != Session.Phase.AWAY:
			match event.physical_keycode:
				KEY_TAB: _open("" if ui.page=="events" else "events")
				KEY_P: _open("" if ui.page=="party" else "party")
				KEY_L: _open("" if ui.page=="locker" else "locker")
				KEY_E:
					if ui.page.is_empty() and not nearby.is_empty() and nearby.back() in ["events","party","locker"]:
						_open(nearby.back())
				KEY_T:
					if nearby.has("range"):
						session.shots = 0
						session.hits = 0
				KEY_F1: low = not low; apply_quality()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if pilot.controls_enabled and nearby.has("range"):
			_fire_trainer()

func _action(id: String, value: Variant) -> void:
	if session.phase == Session.Phase.AWAY and id not in ["return","quit"]:
		return
	match id:
		"enter":
			entered = true
			station.open_arrivals()
			_open("")
			ui.show_toast("Welcome, STRAY. Find an event at the board, or press TAB from anywhere.")
		"close": _open("")
		"page": _open(str(value))
		"public":
			session.start_search()
			_open("")
		"accept": session.accept(); _open("")
		"cancel": session.cancel(); _open("")
		"rehearse": session.rehearse(str(value)); _open("")
		"return":
			session.return_home()
			pilot.respawn()
			_open("")
		"add_friend": session.add_friend(); _open("party")
		"remove_friend": session.remove_friend(); _open("party")
		"destination": session.destination = Session.MAPS[int(value)]; _refresh()
		"humans": session.set_local(int(value)+1,session.bots); _open("local")
		"bots": session.set_local(session.local_humans,int(value))
		"difficulty": session.difficulty = ["Easy","Normal","Hard","Expert"][int(value)]
		"preview_mask":
			ui.pending_mask = value
			pilot.avatar.tint(value)
		"confirm_mask":
			session.mask_color = ui.pending_mask
			_open("")
			ui.show_toast("Mask confirmed for this session.")
		"respawn": pilot.respawn(); _open("")
		"quality": low = not low; apply_quality()
		"sprint":
			pilot.sprint_allowed = not pilot.sprint_allowed
			ui.show_toast("Sprint practice %s. Hold CTRL to sprint when enabled." % ("ON" if pilot.sprint_allowed else "OFF"))
		"quit": get_tree().quit()

func _open(page: String) -> void:
	# Every close/switch rolls back any unconfirmed cosmetic preview.
	if ui.page == "locker": pilot.avatar.tint(session.mask_color)
	ui.show_page(page)
	pilot.controls_enabled = entered and page.is_empty() and session.phase != Session.Phase.AWAY
	var automation := OS.get_cmdline_user_args().has("--capture") or OS.get_cmdline_user_args().has("--validate")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if pilot.controls_enabled and not automation else Input.MOUSE_MODE_VISIBLE

func _refresh() -> void:
	ui.update_local_summary()
	station.party_line.text = "%s + %d" % [session.alias_name,session.guests.size()] if not session.guests.is_empty() else session.alias_name+" / SOLO"
	match session.phase:
		Session.Phase.HOME: station.event_line.text = "WELCOME, "+session.alias_name
		Session.Phase.SEARCHING: station.event_line.text = "SEARCHING / DEMO"
		Session.Phase.FOUND: station.event_line.text = "EVENT FOUND / READY?"
		Session.Phase.DEPARTING: station.event_line.text = "NEXT / "+session.destination.to_upper()
		Session.Phase.AWAY: station.event_line.text = "YOUR ROOM IS WAITING"
	if previous_phase != session.phase:
		previous_phase = session.phase
		station.set_departure(session.phase in [Session.Phase.DEPARTING,Session.Phase.AWAY],session.destination)
		if session.phase == Session.Phase.FOUND:
			if DisplayServer.get_name() != "headless": cue.play()
		if session.phase == Session.Phase.AWAY:
			_open("away")

func apply_quality() -> void:
	get_viewport().scaling_3d_scale = 0.75 if low else 1.0
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if low else Viewport.SCREEN_SPACE_AA_FXAA
	station.environment.glow_enabled = not low
	station.environment.ssao_enabled = not low
	station.environment.ssil_enabled = false
	station.environment.ssr_enabled = false
	station.environment.volumetric_fog_enabled = false
	if ui: ui.show_toast("%s / Forward+ / F1 switches quality" % ("LOW: 75% 3D scale" if low else "HIGH: full 3D scale"))

func _arrive(alias_name: String, index: int) -> void:
	var guest := Node3D.new()
	guest.name = "SimulatedVisitor_"+alias_name
	add_child(guest)
	guest.position = Vector3(0,1.2,14.1)
	var avatar := Avatar.new()
	guest.add_child(avatar)
	avatar.tint([G.CYAN,G.PINK,G.ORANGE,G.GREEN][index%4])
	var badge := G.label(guest,"Alias",alias_name,Vector3(0,2.96,0),37,G.CYAN,0.009)
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	guests.append(guest)
	var angle := -1.05+index*TAU/9.0
	var destination := Vector3(sin(angle)*4.7,-0.6,cos(angle)*4.7)
	var tween := create_tween()
	visitor_tweens.append(tween)
	tween.tween_property(guest,"position",Vector3(0,0,9.3),0.75)
	tween.tween_property(guest,"position",destination,1.65).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func(): guest.look_at(Vector3(0,-0.6,0),Vector3.UP))
	ui.show_toast(alias_name+" arrived through the service lift / SIMULATED")

func _remove_guest(index: int) -> void:
	if visitor_tweens[index] and visitor_tweens[index].is_running(): visitor_tweens[index].kill()
	visitor_tweens.remove_at(index)
	guests[index].queue_free()
	guests.remove_at(index)

func _fire_trainer() -> void:
	if shot_cooldown > 0: return
	shot_cooldown = 0.18
	session.shots += 1
	var cam: Camera3D = pilot.camera
	var center := get_viewport().get_visible_rect().size*0.5
	var origin := cam.project_ray_origin(center)
	var query := PhysicsRayQueryParameters3D.create(origin,origin+cam.project_ray_normal(center)*40,5)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider.has_meta("target_index"):
		var index: int = hit.collider.get_meta("target_index")
		session.hits += 1
		var disc: MeshInstance3D = station.target_discs[index]
		disc.material_override = G.material("hit_target",G.GREEN,0.5)
		if target_tweens[index] and target_tweens[index].is_running(): target_tweens[index].kill()
		target_tweens[index] = create_tween()
		target_tweens[index].tween_interval(0.18)
		target_tweens[index].tween_callback(func(): disc.material_override = G.material("target",G.ORANGE))
		ui.show_toast("HIT / %d of %d light-trainer shots" % [session.hits,session.shots])
	else:
		ui.show_toast("MISS / keep the target in the center of the screen")

func _make_cue() -> void:
	# One short local tone, generated in memory; no audio download or game bus.
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(11025*2)
	for i in range(11025):
		var t := float(i)/22050.0
		var frequency := 660.0 if t<0.18 else 880.0
		var value := int(sin(TAU*frequency*t)*minf(t*30,1.0)*maxf(0,1-t*2)*8000)
		samples.encode_s16(i*2,value)
	wav.data = samples
	cue = AudioStreamPlayer.new()
	cue.stream = wav
	cue.volume_db = -13
	add_child(cue)

func _run_validation() -> void:
	var validator = load("res://validation.gd").new()
	add_child(validator)
	await validator.run(self)

func _run_capture() -> void:
	var capture = load("res://capture.gd").new()
	add_child(capture)
	await capture.run(self)
