extends Node3D
## F6-only presentation preview. No match start, host/join, or scene-change calls.
const G = preload("res://tools/live_lobby_preview/geometry.gd")
const Interface = preload("res://tools/live_lobby_preview/interface.gd")
const Session = preload("res://tools/live_lobby_preview/session.gd")
const Hub = preload("res://UI/lobby_player_hub_overlay.gd")
const Locker = preload("res://UI/themed_locker_overlay.gd")
const AccountPanel = preload("res://UI/player_hub_overlay.gd")
const Progression = preload("res://UI/progression_road_overlay.gd")
const HUB_PAGES = ["hub", "locker", "profile", "prize_counter", "progression"]

@onready var station: Node3D = $Station
@onready var pilot: CharacterBody3D = $Player
@onready var spawn: Marker3D = $ArrivalSpawn
var session := Session.new()
var playpen: Node
var training: Node
var scrap: Node
var toss: Node
var ui: CanvasLayer
var hub_layer: CanvasLayer
var native_overlay: Control
var native_page := ""
var return_to_hub := false
var guests: Array[Node3D] = []
var resident_visuals: Dictionary = {}
var visitor_tweens: Array[Tween] = []
var nearby: Array[String] = []
var low := false
var previous_phase := -1
var update_left := 0.0
var controls_enabled := false
var automation := false
var added_actions: Array[StringName] = []
var previous_escape: Callable
var previous_mouse_mode: Input.MouseMode
var cue: AudioStreamPlayer

func _ready() -> void:
	automation = OS.get_cmdline_user_args().has("--live-lobby-validate") or OS.get_cmdline_user_args().has("--live-lobby-capture")
	get_viewport().use_occlusion_culling = true
	previous_mouse_mode = Input.mouse_mode
	previous_escape = PauseManager.escape_override
	PauseManager.set_escape_override(_escape)
	_register_shortcuts()
	session.alias_name = str(PlayerPrefs.get_setting("player_name")).strip_edges()
	if session.alias_name.is_empty(): session.alias_name = "STRAY"
	ui = Interface.new()
	ui.session = session
	add_child(ui)
	ui.action.connect(_action)
	hub_layer = CanvasLayer.new()
	hub_layer.layer = 30
	add_child(hub_layer)
	session.changed.connect(_refresh)
	session.notice.connect(ui.show_toast)
	session.friend_added.connect(_arrive)
	session.friend_removed.connect(_remove_guest)
	station.station_entered.connect(func(id):
		if not nearby.has(id): nearby.append(id)
	)
	station.station_exited.connect(func(id): nearby.erase(id))
	playpen = preload("res://tools/live_lobby_preview/playpen.gd").new()
	playpen.name = "ContainedPlayPen"
	add_child(playpen)
	playpen.setup(self)
	training=preload("res://tools/live_lobby_preview/training.gd").new()
	training.name="PracticeTraining"
	add_child(training)
	training.setup(self)
	ui.training=training
	scrap=preload("res://tools/live_lobby_preview/scrap_yard.gd").new()
	scrap.name="ScrapYard"
	add_child(scrap)
	scrap.setup(self)
	ui.scrap=scrap
	toss=preload("res://tools/live_lobby_preview/trickshot_toss.gd").new()
	toss.name="TrickshotToss"
	add_child(toss)
	toss.setup(self)
	_make_cue()
	_update_identity()
	_reset_position()
	_refresh()
	_open("")
	station.open_arrivals()
	ui.show_toast("Welcome to your Hideout. Invite Only / TAB: Game Board / P: Squad.")
	if automation:
		_run_automation.call_deferred()

func _process(delta: float) -> void:
	session.tick(delta)
	update_left -= delta
	if update_left > 0: return
	update_left = 0.1
	ui.update_readouts(0.1,Engine.get_frames_per_second(),pilot.dash_charges,low)
	var hint := ""
	if controls_enabled and not nearby.is_empty():
		match nearby.back():
			"toss": hint = _interaction_hint()+" / TOSS A SOFT BALL - AIM AT A BASKET"
			"scrap": hint = _interaction_hint()+" / THE SCRAP YARD - JOIN OR WATCH"
			"sparring": hint = _interaction_hint()+" / SPARRING PARTNER"
			"departure": hint = "MATCH STATUS / [TAB] GAME BOARD / WALKING HERE NEVER STARTS A MATCH"
			var id:
				if str(id).begins_with("range_"): hint=_interaction_hint()+" / "+training.range_hint(int(str(id).get_slice("_",1)))
				else: hint = "%s  /  %s" % [_interaction_hint(),str(id).replace("_"," ").to_upper()]
	station.set_active_service(nearby.back() if controls_enabled and not nearby.is_empty() else "")
	ui.help.text = "SAVED MOVEMENT CONTROLS     %s     TAB  GAME BOARD     H  PLAYER HUB     P  SQUAD     L  LOCKER     ESC  MENU" % _interaction_hint()
	ui.context.text = hint
	if controls_enabled and pilot.position.y < -8: _reset_position()

func _register_shortcuts() -> void:
	for entry in [["lobby_events",KEY_TAB],["lobby_hub",KEY_H],["lobby_party",KEY_P],["lobby_locker",KEY_L],["lobby_accept",KEY_R],["lobby_cancel",KEY_X],["lobby_quality",KEY_F1]]:
		var id := StringName(pilot.input_prefix+"_"+str(entry[0]))
		if InputMap.has_action(id): continue
		InputMap.add_action(id)
		var key := InputEventKey.new()
		key.physical_keycode = entry[1]
		InputMap.action_add_event(id,key)
		if not added_actions.has(id): added_actions.append(id)

func _pressed(event: InputEvent, suffix: String) -> bool:
	# PlayerPrefs rebuilds InputMap on device refresh and when shared menus initialize.
	if suffix.begins_with("lobby_") and not InputMap.has_action(pilot.input_prefix+"_"+suffix):
		_register_shortcuts()
	return event.is_action_pressed(pilot.input_prefix+"_"+suffix) and not event.is_echo()

func _input(event: InputEvent) -> void:
	if automation and OS.get_cmdline_user_args().has("--live-lobby-capture"): return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if _pressed(event,"lobby_accept") and session.phase == Session.Phase.FOUND:
		_action("accept",null)
		get_viewport().set_input_as_handled()
		return
	if _pressed(event,"lobby_cancel") and session.phase in [Session.Phase.SEARCHING,Session.Phase.FOUND,Session.Phase.DEPARTING]:
		_action("cancel",null)
		get_viewport().set_input_as_handled()
		return
	# The existing full-screen menus own their own keyboard/controller navigation.
	if is_instance_valid(native_overlay) or session.phase == Session.Phase.AWAY: return
	var used := true
	if _pressed(event,"lobby_events"): _open("" if ui.page=="events" else "events")
	elif _pressed(event,"lobby_hub"): _open("hub")
	elif _pressed(event,"lobby_party"): _open("" if ui.page=="party" else "party")
	elif _pressed(event,"lobby_locker"): _open("locker")
	elif _pressed(event,"interact") and controls_enabled and not nearby.is_empty():
		var id: String = nearby.back()
		if id=="toss": toss.throw_ball()
		elif id.begins_with("range_"): training.cycle_distance(int(id.get_slice("_",1)))
		elif id in HUB_PAGES or id in ["events","party","sparring","course_board","scrap"]: _open(id)
	elif _pressed(event,"lobby_quality"): _action("quality",null)
	else: used = false
	if used: get_viewport().set_input_as_handled()

func _interaction_hint() -> String:
	var events := InputMap.action_get_events(pilot.input_prefix+"_interact")
	for event in events:
		if event is InputEventKey: return "["+event.as_text_physical_keycode()+"] INTERACT"
	return "INTERACT"

func _escape() -> void:
	if is_instance_valid(native_overlay):
		if native_page == "locker": native_overlay._cancel()
		else: native_overlay._close()
		return
	if session.phase == Session.Phase.AWAY: return
	_open("pause" if ui.page.is_empty() else "")

func _action(id: String, value: Variant) -> void:
	if session.phase == Session.Phase.AWAY and id not in ["return","quit"]: return
	match id:
		"close": _open("")
		"page": _open(str(value))
		"public": session.set_access(2); _open("private")
		"access": session.set_access(int(value)); _open("private")
		"ready": session.request_ready(); _open("events")
		"confirm_others": session.simulate_confirmations(); _open("events")
		"start_match": session.start_match(); _open("")
		"host_start": session.start_match(true); _open("")
		"join_lobby": session.request_join(str(value)); _open("events")
		"leave_together": session.leave_together(); _open("party")
		"public_visitor": session.add_public_visitor(); _open("private")
		"accept": session.accept() # Keep a cosmetic preview open until its own close/confirm.
		"cancel": session.cancel()
		"rehearse": session.rehearse(str(value)); _open("")
		"return": session.return_home(); _reset_position(); _open("")
		"add_friend": session.add_friend(); _open("party")
		"remove_friend": session.remove_friend(); _open("party")
		"destination": session.set_destination(int(value)); _refresh()
		"humans": session.set_local(int(value)+1,session.bots); _open("local")
		"bots": session.set_local(session.local_humans,int(value)); _open("private")
		"difficulty": session.difficulty = ["Easy","Normal","Hard","Expert"][int(value)]
		"respawn": _reset_position(); _open("")
		"quality": low = not low; apply_quality()
		"sparring": playpen.set_sparring_mode(str(value)); _open("")
		"range_distance": training.set_distance(value.x,value.y)
		"range_reset_hits": training.reset_hits(); _open("range_settings")
		"course_restart": training.restart_trial()
		"course_tab": training.board_tab=str(value); _open("course_board")
		"course_category": training.board_assisted=bool(value); _open("course_board")
		"scrap_join": scrap.join_round(str(value))
		"scrap_coin": scrap.choose(str(value),scrap.fighters[1].actor_id)
		"scrap_leave": scrap.leave()
		"scrap_watch": _open(""); pilot.position=scrap.Space.FOYER+Vector3(0,0,-3)
		"quit": get_tree().quit()

func _open(page: String) -> void:
	if page in HUB_PAGES:
		_open_native(page)
		return
	if page=="course_board": training.refresh_roster()
	ui.show_page(page)
	_sync_controls()
	if page == "pause" and session.phase == Session.Phase.FOUND and PlayerPrefs.is_using_controller():
		ui.ready_panel.show()
		ui.ready_accept.grab_focus()

func _sync_controls() -> void:
	controls_enabled = ui.page.is_empty() and not is_instance_valid(native_overlay) and session.phase != Session.Phase.AWAY and not pilot.is_eliminated and (not is_instance_valid(scrap) or not scrap.pilot_locked())
	pilot.set_physics_process(controls_enabled)
	pilot.set_process_input(controls_enabled and not automation)
	if not controls_enabled:
		pilot.velocity = Vector3.ZERO
		pilot._play_anim("idle",true)
	ui.shell.visible = not is_instance_valid(native_overlay)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if controls_enabled and not automation and not PlayerPrefs.is_using_controller() else Input.MOUSE_MODE_VISIBLE

func _open_native(page: String, from_hub := false) -> void:
	if is_instance_valid(native_overlay): return
	ui.show_page("")
	native_page = page
	return_to_hub = from_hub
	match page:
		"hub":
			native_overlay = Hub.new()
			native_overlay.configure("home")
			native_overlay.destination_requested.connect(_hub_destination)
		"locker":
			native_overlay = Locker.new()
			native_overlay.configure(false,1)
			native_overlay.skin_changed.connect(func(slot: int, skin: String):
				if slot == 0: pilot.set_character_skin(skin)
			)
		"profile","prize_counter":
			native_overlay = AccountPanel.new()
			native_overlay.configure(page)
		"progression": native_overlay = Progression.new()
		_: return
	native_overlay.closed.connect(_native_closed)
	hub_layer.add_child(native_overlay)
	_sync_controls()

func _hub_destination(destination: String) -> void:
	if destination not in HUB_PAGES: return
	native_overlay.queue_free()
	native_overlay = null
	_open_native(destination,true)

func _native_closed() -> void:
	native_overlay = null
	native_page = ""
	# The locker updates PlayerPrefs when confirmed, and emits change signals on cancel.
	pilot.set_character_appearance(str(PlayerPrefs.get_setting("character_model_id")),str(PlayerPrefs.get_setting("character_skin_id")))
	_update_identity()
	var reopen := return_to_hub
	return_to_hub = false
	if session.phase == Session.Phase.AWAY: _open("away")
	elif reopen: _open_native("hub")
	else: _sync_controls()

func _update_identity() -> void:
	session.alias_name = str(PlayerPrefs.get_setting("player_name")).strip_edges()
	if session.alias_name.is_empty(): session.alias_name = "STRAY"
	station.set_profile_identity(session.alias_name,str(PlayerPrefs.get_setting("character_model_id")),str(PlayerPrefs.get_setting("character_skin_id")))
	_refresh()

func _reset_position() -> void:
	if is_instance_valid(scrap) and scrap.state!=scrap.State.IDLE: scrap.leave()
	if training: training.cancel_trial()
	if is_instance_valid(playpen):
		playpen.deaths.erase(pilot.actor_id)
		playpen.clear_inventory(pilot)
	if pilot.is_eliminated: pilot.respawn(spawn.global_transform)
	pilot.global_transform = spawn.global_transform
	pilot.velocity = Vector3.ZERO
	pilot.get_node("AimPivot").rotation = Vector3(-0.08,0,0)
	nearby.clear()

func _refresh() -> void:
	_sync_residents()
	ui.update_local_summary()
	if ui.page in ["events","private","join","party"]: ui.show_page(ui.page)
	station.party_line.text = "%s + %d" % [session.alias_name,session.guests.size()] if not session.guests.is_empty() else session.alias_name+" / SOLO"
	match session.phase:
		Session.Phase.HOME: station.event_line.text = "WELCOME, "+session.alias_name
		Session.Phase.SEARCHING: station.event_line.text = "SEARCHING / DEMO"
		Session.Phase.FOUND: station.event_line.text = "READY CHECK / GAME BOARD"
		Session.Phase.DEPARTING: station.event_line.text = "NEXT / "+session.destination.to_upper()
		Session.Phase.AWAY: station.event_line.text = "YOUR ROOM IS WAITING"
	if previous_phase == session.phase: return
	previous_phase = session.phase
	station.set_departure(session.phase in [Session.Phase.DEPARTING,Session.Phase.AWAY],session.destination)
	if session.phase == Session.Phase.FOUND and DisplayServer.get_name() != "headless": cue.play()
	if session.phase == Session.Phase.AWAY:
		if is_instance_valid(scrap): scrap.leave()
		# Do not discard pending changes in the real locker. Finish/close that UI first.
		ui.show_page("away")
		_sync_controls()

func apply_quality() -> void:
	GraphicsQualityManager.apply_subtree(self)
	station.environment = station.get_node("WorldEnvironment").environment
	if low:
		get_viewport().scaling_3d_scale = 0.75
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		station.environment.glow_enabled = false
		station.environment.ssao_enabled = false
	else:
		GraphicsQualityManager.APPLIER.apply_viewport(get_viewport(),PlayerPrefs.settings)
	if is_instance_valid(scrap): scrap.apply_quality()
	ui.show_toast("%s / Forward+ / F1 switches preview quality" % ("LOW: 75% 3D scale" if low else "YOUR SAVED QUALITY"))

func _arrive(alias_name: String, index: int) -> void:
	var guest := Node3D.new()
	guest.name = "SimulatedVisitor_"+alias_name
	add_child(guest)
	guest.position = Vector3(0,1.2,27.0)
	# Public base characters share the game's rigs/materials without granting inventory.
	var model_id: String = PlayerSkinRegistry.PUBLIC_MODEL_IDS[index%2]
	var visual: Node3D = PlayerSkinRegistry.load_visual_scene(model_id).instantiate()
	visual.build_animation_library = false
	visual.skin_id = PlayerSkinRegistry.skin_id_at((index+2)%PlayerSkinRegistry.skin_count())
	guest.add_child(visual)
	visual.ensure_animations(["idle","standard_run"])
	var anim: AnimationPlayer = visual.get_animation_player()
	if anim.has_animation("standard_run"): anim.play("standard_run")
	var badge := G.label(guest,"Alias",alias_name,Vector3(0,3.1,0),37,G.CYAN,0.009)
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	guests.append(guest)
	var angle := -1.05+index*TAU/9.0
	var destination := Vector3(sin(angle)*6.0,-0.6,cos(angle)*6.0)
	var tween := create_tween()
	visitor_tweens.append(tween)
	tween.tween_property(guest,"position",Vector3(0,0,21.7),1.0)
	tween.tween_property(guest,"position",Vector3(0,0,10.3),1.45)
	tween.tween_property(guest,"position",destination,1.2).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		guest.look_at(Vector3(0,-0.6,0),Vector3.UP,true)
		if anim.has_animation("idle"): anim.play("idle")
	)
	ui.show_toast(alias_name+" arrived through the entry hall / SIMULATED")

func _remove_guest(index: int) -> void:
	if visitor_tweens[index] and visitor_tweens[index].is_running(): visitor_tweens[index].kill()
	visitor_tweens.remove_at(index)
	guests[index].queue_free()
	guests.remove_at(index)

func _make_cue() -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(11025*2)
	for i in range(11025):
		var t := float(i)/22050.0
		var frequency := 660.0 if t<0.18 else 880.0
		samples.encode_s16(i*2,int(sin(TAU*frequency*t)*minf(t*30,1.0)*maxf(0,1-t*2)*8000))
	wav.data = samples
	cue = AudioStreamPlayer.new()
	cue.stream = wav
	cue.volume_db = -13
	add_child(cue)

func _run_automation() -> void:
	get_tree().create_timer(300).timeout.connect(func():
		push_error("Live lobby automated check timed out")
		get_tree().quit(2)
	)
	await get_tree().process_frame
	var filename := "validation.gd" if OS.get_cmdline_user_args().has("--live-lobby-validate") else "capture.gd"
	var runner: Node = load("res://tools/live_lobby_preview/"+filename).new()
	add_child(runner)
	await runner.run(self)

func _exit_tree() -> void:
	if PauseManager.escape_override == Callable(self,"_escape"):
		PauseManager.set_escape_override(previous_escape)
	for action in added_actions:
		if InputMap.has_action(action): InputMap.erase_action(action)
	Input.mouse_mode = previous_mouse_mode

func _sync_residents() -> void:
	for person in resident_visuals.keys():
		if person not in session.residents:
			resident_visuals[person].queue_free()
			resident_visuals.erase(person)
	for i in range(session.residents.size()):
		var person: String=session.residents[i]
		if resident_visuals.has(person): continue
		var visitor:=Node3D.new()
		visitor.name="SimulatedLobbyResident"
		add_child(visitor)
		var angle: float=2.5+i*0.45
		visitor.position=Vector3(sin(angle)*6.1,-0.6,cos(angle)*6.1)
		var visual: Node3D=PlayerSkinRegistry.load_visual_scene("male").instantiate()
		visual.build_animation_library=false
		visual.skin_id=PlayerSkinRegistry.skin_id_at((i+4)%PlayerSkinRegistry.skin_count())
		visitor.add_child(visual)
		visual.ensure_animations(["idle"])
		var anim: AnimationPlayer=visual.get_animation_player()
		if anim.has_animation("idle"): anim.play("idle")
		var badge:=G.label(visitor,"ResidentName",person+" / LOBBY",Vector3(0,3.1,0),35,G.ORANGE,0.008)
		badge.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		visitor.look_at(Vector3(0,-0.6,0),Vector3.UP,true)
		resident_visuals[person]=visitor
