extends Node3D
## Shared front end. Only explicit host/join actions open a network session.
const G = preload("res://maps/hideout/geometry.gd")
const Session = preload("res://maps/hideout/session.gd")
const HUB_PAGES = ["hub", "locker", "profile", "prize_counter", "progression"]
@onready var station: Node3D = $Station
@onready var spawn: Marker3D = $ArrivalSpawn
var pilot: CharacterBody3D
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
var controls_enabled := false
var automation := false
var added_actions: Array[StringName] = []
var previous_escape: Callable
var previous_mouse_mode: Input.MouseMode
var update_left := 0.0
var activities_ready := false
var closing := false
var previous_disable_3d := false
var session_spawn := Transform3D.IDENTITY
var waiting_for_match := false
var departing := false
var invite_notification: Control
var joining_friend := false

func _ready() -> void:
	automation = OS.get_cmdline_user_args().has("--hideout-test")
	session_spawn = spawn.global_transform
	waiting_for_match = NetworkManager.is_online() and NetworkManager.lobby_in_progress
	get_viewport().use_occlusion_culling = true
	previous_mouse_mode = Input.mouse_mode
	previous_disable_3d = get_viewport().disable_3d
	previous_escape = PauseManager.escape_override
	PauseManager.set_escape_override(_escape)
	ui = preload("res://maps/hideout/interface.gd").new()
	ui.session = session
	add_child(ui)
	ui.action.connect(_action)
	hub_layer = CanvasLayer.new()
	hub_layer.layer = 40
	add_child(hub_layer)
	_register_shortcuts()
	station.station_entered.connect(func(id):
		if not nearby.has(id): nearby.append(id))
	station.station_exited.connect(func(id): nearby.erase(id))
	session.changed.connect(_refresh)
	NetworkManager.lobby_changed.connect(session.refresh)
	NetworkManager.lobby_readiness_changed.connect(session.refresh)
	NetworkManager.match_config_received.connect(_config_changed)
	NetworkManager.prelaunch_countdown_changed.connect(_prelaunch_changed)
	NetworkManager.server_disconnected.connect(_host_left)
	NetworkManager.lobby_notice.connect(ui.show_toast)
	SocialManager.invite_received.connect(_invite_received)
	session.refresh()
	if NetworkManager.is_online() and not NetworkManager.lobby_in_progress:
		playpen = load("res://maps/hideout/network_practice.gd").new()
		playpen.name = "RoundManager"
		add_child(playpen)
		playpen.local_player_ready.connect(_bind_online_pilot)
	else:
		pilot = preload("res://player.tscn").instantiate()
		pilot.set_script(preload("res://maps/hideout/preview_actor.gd"))
		pilot.name = "Player"
		pilot.position = spawn.position
		add_child(pilot)
		if not waiting_for_match: _setup_local_activities()
		_finish_arrival()
	if HideoutSession.return_message != "":
		ui.show_toast(HideoutSession.return_message)
		HideoutSession.return_message = ""
	GraphicsQualityManager.apply_subtree(self)
	if NetworkManager.lobby_in_progress:
		ui.show_toast("A match is in progress. Open the Game Board to watch.")

func _setup_local_activities() -> void:
	playpen = preload("res://maps/hideout/playpen.gd").new()
	playpen.name = "ContainedPlayPen"
	add_child(playpen)
	playpen.setup(self)
	training = preload("res://maps/hideout/training.gd").new()
	add_child(training)
	training.setup(self)
	scrap = preload("res://maps/hideout/scrap_yard.gd").new()
	add_child(scrap)
	scrap.setup(self)
	toss = preload("res://maps/hideout/trickshot_toss.gd").new()
	add_child(toss)
	toss.setup(self)
	ui.training = training
	ui.scrap = scrap
	activities_ready = true

func _bind_online_pilot(actor: CharacterBody3D) -> void:
	pilot = actor
	training = playpen.training
	scrap = playpen.scrap
	toss = playpen.toss
	ui.training = training
	ui.scrap = scrap
	activities_ready = true
	_finish_arrival()

func _finish_arrival() -> void:
	pilot.get_gameplay_camera().make_current()
	station.open_arrivals()
	_update_identity()
	_sync_controls()

func _process(delta: float) -> void:
	update_left -= delta
	if update_left > 0: return
	update_left = 0.1
	ui.update_readouts(0.1, Engine.get_frames_per_second(), pilot.dash_charges if is_instance_valid(pilot) else 0, false)
	if not is_instance_valid(pilot): return
	var hint := ""
	if controls_enabled and not nearby.is_empty():
		var id: String = nearby.back()
		hint = "%s / %s" % [_interaction_hint(), str(id).replace("_", " ").to_upper()]
		if id == "departure": hint = "MATCH STATUS / OPEN THE GAME BOARD"
		elif str(id).begins_with("range_") and activities_ready: hint = _interaction_hint()+" / "+training.range_hint(int(str(id).get_slice("_", 1)))
	ui.context.text = hint
	station.set_active_service(nearby.back() if controls_enabled and not nearby.is_empty() else "")
	if not NetworkManager.is_online() and pilot.position.y < -8: _reset_position()

func _register_shortcuts() -> void:
	for entry in [["lobby_events",KEY_TAB],["lobby_hub",KEY_H],["lobby_party",KEY_P],["lobby_locker",KEY_L],["lobby_accept",KEY_R]]:
		var id := StringName("p1_"+str(entry[0]))
		if InputMap.has_action(id): continue
		InputMap.add_action(id)
		var key := InputEventKey.new()
		key.physical_keycode = entry[1]
		InputMap.action_add_event(id,key)
		added_actions.append(id)

func _pressed(event: InputEvent, suffix: String) -> bool:
	if not InputMap.has_action("p1_"+suffix): _register_shortcuts()
	return event.is_action_pressed("p1_"+suffix) and not event.is_echo()

func _input(event: InputEvent) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or OnlineChat.is_typing(): return
	if is_instance_valid(native_overlay) or not is_instance_valid(pilot): return
	var used := true
	if _pressed(event,"lobby_events"): _open("events")
	elif _pressed(event,"lobby_party"): _open("party")
	elif _pressed(event,"lobby_hub"): _open("hub")
	elif _pressed(event,"lobby_locker"): _open("locker")
	elif _pressed(event,"lobby_accept"): _action("ready",null)
	elif _pressed(event,"interact") and controls_enabled and not nearby.is_empty():
		var id: String = nearby.back()
		if id == "toss" and activities_ready: toss.throw_ball()
		elif str(id).begins_with("range_") and activities_ready: training.cycle_distance(int(str(id).get_slice("_",1)))
		elif id == "departure": _open("events")
		else: _open(id)
	else: used = false
	if used: get_viewport().set_input_as_handled()

func _interaction_hint() -> String:
	for event in InputMap.action_get_events("p1_interact"):
		if event is InputEventKey: return "["+event.as_text_physical_keycode()+"] INTERACT"
	return "INTERACT"

func _escape() -> void:
	if is_instance_valid(native_overlay):
		match native_page:
			"settings": native_overlay.request_cancel_close()
			"match_setup": native_overlay._on_back_button_pressed()
			"online": native_overlay.handle_cancel()
			"locker": native_overlay._cancel()
			_: native_overlay._close()
		return
	_open("pause" if ui.page.is_empty() else "")

func _action(id: String, value: Variant) -> void:
	match id:
		"close": _open("")
		"page": _open(str(value))
		"solo","local":
			if NetworkManager.is_online(): return
			GameConfig.split_screen_enabled = id == "local"
			session.refresh()
			_open_native("match_setup")
		"host":
			if not NetworkManager.is_online(): _open_native("online",false,"private")
		"browse":
			if not NetworkManager.is_online(): _open_native("online")
		"queue":
			if not NetworkManager.is_online(): _open_native("online",false,"matchmaking")
		"ready":
			if NetworkManager.is_online() and not NetworkManager.lobby_in_progress:
				if NetworkManager.can_manage_lobby(): _open_native("match_setup")
				else: NetworkManager.set_local_lobby_ready(not NetworkManager.is_peer_lobby_ready(NetworkManager.local_id()))
		"cancel":
			if NetworkManager.can_manage_lobby(): NetworkManager.cancel_prelaunch()
		"leave": _open("confirm_leave")
		"confirm_leave":
			HideoutSession.return_message = "You left the Hideout."
			NetworkManager.leave_online_to_main_menu()
		"quit": _open("confirm_quit")
		"confirm_quit": get_tree().quit()
		"respawn": _reset_position(); _open("")
		"sparring": playpen.set_sparring_mode(str(value)); _open("")
		"range_distance": training.set_distance(value.x,value.y)
		"range_reset_hits": training.reset_hits(); _open("range_settings")
		"course_restart": training.restart_trial()
		"course_tab": training.board_tab=str(value); _open("course_board")
		"course_category": training.board_assisted=bool(value); _open("course_board")
		"scrap_join": scrap.join_round(str(value))
		"scrap_coin": scrap.choose(str(value),pilot.actor_id if NetworkManager.is_online() else scrap.fighters[1].actor_id)
		"scrap_leave": scrap.leave()
		"scrap_watch": _open("")
		"access":
			if NetworkManager.can_manage_lobby(): NetworkManager.set_lobby_privacy(str(value))

func _open(page: String) -> void:
	if page in HUB_PAGES or page in ["settings","friends","match_setup","release_notes"]:
		_open_native(page)
		return
	if not activities_ready and page in ["scrap","agility","course_board","range_settings","sparring"]:
		ui.show_toast("The match is in progress. Open the Game Board to spectate.")
		return
	if page == "course_board": training.refresh_roster()
	ui.show_page(page)
	_sync_controls()

func _open_native(page: String, from_hub := false, online_page := "") -> void:
	if is_instance_valid(native_overlay): return
	ui.show_page("")
	native_page = page
	return_to_hub = from_hub
	match page:
		"hub":
			native_overlay = preload("res://UI/lobby_player_hub_overlay.gd").new()
			native_overlay.configure("home")
			native_overlay.destination_requested.connect(_hub_destination)
		"locker":
			native_overlay = preload("res://UI/themed_locker_overlay.gd").new()
			native_overlay.configure(NetworkManager.is_online(), 2 if GameConfig.split_screen_enabled and not NetworkManager.is_online() else 1)
		"profile","prize_counter":
			native_overlay = preload("res://UI/player_hub_overlay.gd").new()
			native_overlay.configure(page)
		"progression": native_overlay = preload("res://UI/progression_road_overlay.gd").new()
		"settings":
			native_overlay = preload("res://player_settings.tscn").instantiate()
			native_overlay.is_overlay = true
			native_overlay.settings_closed.connect(_native_closed)
		"friends":
			native_overlay = preload("res://UI/social_overlay.gd").new()
			native_overlay.join_requested.connect(_join_friend)
			SocialManager.set_foreground_ui_active(true)
		"match_setup": native_overlay = preload("res://maps/hideout/match_board.gd").new()
		"online":
			if not NetworkManager.is_online(): HideoutSession.remember_home()
			native_overlay = preload("res://UI/online_play_overlay.gd").new()
			native_overlay.close_requested.connect(_native_closed)
			native_overlay.session_started.connect(_session_started)
		"release_notes":
			native_overlay = load("res://UI/hideout_release_notes.gd").new()
		_: return
	if native_overlay.has_signal("closed"): native_overlay.closed.connect(_native_closed)
	hub_layer.add_child(native_overlay)
	native_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if page == "online": native_overlay.open(online_page)
	_sync_controls()

func _native_closed() -> void:
	var old := native_overlay
	native_overlay = null
	native_page = ""
	if is_instance_valid(old): old.queue_free()
	SocialManager.set_foreground_ui_active(false)
	if not NetworkManager.is_online(): HideoutSession.restore_home()
	_update_identity()
	session.refresh()
	var reopen := return_to_hub
	return_to_hub = false
	if reopen: _open_native("hub")
	else: _sync_controls()

func _hub_destination(destination: String) -> void:
	return_to_hub = false
	_native_closed()
	_open_native(destination,true)

func _sync_controls() -> void:
	controls_enabled = not departing and (activities_ready or waiting_for_match) and ui.page.is_empty() and not is_instance_valid(native_overlay) and not NetworkManager._prelaunch_active and is_instance_valid(pilot) and not pilot.is_eliminated and (not is_instance_valid(scrap) or not scrap.pilot_locked())
	if is_instance_valid(pilot):
		if pilot.is_online: pilot.external_input_blocked = not controls_enabled
		else: pilot.set_physics_process(controls_enabled)
		pilot.set_process_input(controls_enabled and not automation)
	ui.shell.visible = not is_instance_valid(native_overlay)
	get_viewport().disable_3d = previous_disable_3d or is_instance_valid(native_overlay)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if controls_enabled and not automation and not PlayerPrefs.is_using_controller() else Input.MOUSE_MODE_VISIBLE

func _refresh() -> void:
	if not is_instance_valid(ui): return
	station.party_line.text = "%d HERE / %s" % [session.member_count(), session.alias_name]
	station.event_line.text = session.destination.to_upper()
	station.set_departure(NetworkManager._prelaunch_active,session.destination)
	if ui.page in ["events","party","private"]: ui.show_page(ui.page)

func _config_changed() -> void:
	if NetworkManager.pending_map_path != "": HideoutSession.selected_map = NetworkManager.pending_map_path
	session.refresh()

func _prelaunch_changed(_active: bool, _seconds: int) -> void:
	session.refresh()
	_sync_controls()

func _update_identity() -> void:
	if not is_instance_valid(pilot): return
	_register_shortcuts()
	ui.help.text = "SAVED MOVEMENT CONTROLS    "+_interaction_hint()+"    TAB GAME BOARD    H PLAYER HUB    P SQUAD    L LOCKER    ESC MENU"
	var model := str(PlayerPrefs.get_setting("character_model_id"))
	var skin := str(PlayerPrefs.get_setting("character_skin_id"))
	if not NetworkManager.is_online(): pilot.set_character_appearance(model,skin)
	station.set_profile_identity(NetworkManager.local_name(),model,skin)

func _reset_position() -> void:
	if not is_instance_valid(pilot): return
	if NetworkManager.is_online():
		playpen.request_recover()
		return
	if is_instance_valid(scrap) and scrap.state != scrap.State.IDLE: scrap.leave()
	if training: training.cancel_trial()
	playpen.deaths.erase(pilot.actor_id)
	playpen.clear_inventory(pilot)
	if pilot.is_eliminated: pilot.respawn(spawn.global_transform)
	pilot.global_transform = spawn.global_transform
	pilot.velocity = Vector3.ZERO
	pilot.get_node("AimPivot").rotation = Vector3(-0.08,0,0)
	nearby.clear()

func _session_started() -> void:
	if NetworkManager.match_server_mode: return
	HideoutSession.remember_home()
	GameConfig.split_screen_enabled = false
	if NetworkManager.is_host():
		NetworkManager.broadcast_match_config(GameConfig.snapshot_for_network(),HideoutSession.selected_map)
	_upgrade_to_network.call_deferred()

func _upgrade_to_network() -> void:
	if not NetworkManager.is_online(): return
	if NetworkManager.lobby_in_progress:
		get_tree().change_scene_to_file(HideoutSession.SCENE)
		return
	if is_instance_valid(pilot): session_spawn=pilot.global_transform
	return_to_hub=false
	_native_closed()
	activities_ready=false
	controls_enabled=false
	for controller in [training,scrap]:
		if not is_instance_valid(controller): continue
		for field in ["hud","banner","coin_visual"]:
			if field in controller and is_instance_valid(controller.get(field)): controller.get(field).queue_free()
	# Keep the authored world resident. Opening hosting must not block ENet
	# behind another complete scene build.
	for node in get_children():
		if node in [station,spawn,ui,hub_layer]: continue
		remove_child(node)
		node.queue_free()
	pilot=null
	training=null
	scrap=null
	toss=null
	nearby.clear()
	await get_tree().process_frame
	playpen=load("res://maps/hideout/network_practice.gd").new()
	playpen.name="RoundManager"
	add_child(playpen)
	playpen.local_player_ready.connect(_bind_online_pilot)
	session.refresh()

func _join_friend(lobby: Dictionary) -> void:
	if NetworkManager.is_online():
		var dialog := AcceptDialog.new()
		dialog.dialog_text = "Leave this Hideout before joining another. Everyone here can play together using Play Here on the Game Board."
		hub_layer.add_child(dialog)
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered(Vector2i(520,170))
		return
	if joining_friend: return
	var address := str(lobby.get("address",""))
	if address.is_empty(): return
	joining_friend = true
	HideoutSession.remember_home()
	NetworkManager.connection_succeeded.connect(_friend_joined,CONNECT_ONE_SHOT)
	NetworkManager.connection_failed.connect(_friend_join_failed,CONNECT_ONE_SHOT)
	if not NetworkManager.join_game(address,int(lobby.get("port",NetworkManager.DEFAULT_PORT))): _friend_join_failed()

func _friend_joined() -> void:
	joining_friend = false
	if NetworkManager.connection_failed.is_connected(_friend_join_failed): NetworkManager.connection_failed.disconnect(_friend_join_failed)
	_session_started()

func _friend_join_failed() -> void:
	joining_friend = false
	if NetworkManager.connection_succeeded.is_connected(_friend_joined): NetworkManager.connection_succeeded.disconnect(_friend_joined)
	HideoutSession.restore_home()
	ui.show_toast("Could not join that Hideout. Your own room is still here.")

func _invite_received(invite: Dictionary) -> void:
	if not is_instance_valid(invite_notification):
		invite_notification = preload("res://UI/components/lobby_invite_notification.gd").new()
		hub_layer.add_child(invite_notification)
		invite_notification.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		invite_notification.offset_left=-484
		invite_notification.offset_right=-24
		invite_notification.offset_top=94
		invite_notification.join_requested.connect(_join_friend)
	invite_notification.present(invite)
	if ui.page.is_empty() and not is_instance_valid(native_overlay): _open("party")

func _host_left() -> void:
	if closing: return
	closing = true
	HideoutSession.return_home("The host disconnected. You are back in your own Hideout.")

func apply_quality() -> void:
	GraphicsQualityManager.apply_subtree(self)
	if is_instance_valid(scrap): scrap.apply_quality()

func _exit_tree() -> void:
	closing = true
	get_viewport().disable_3d = previous_disable_3d
	if PauseManager.escape_override == Callable(self,"_escape"): PauseManager.set_escape_override(previous_escape)
	for action in added_actions:
		if InputMap.has_action(action): InputMap.erase_action(action)
	Input.mouse_mode = previous_mouse_mode


func prepare_for_match() -> void:
	departing = true
	if is_instance_valid(native_overlay):
		return_to_hub = false
		_native_closed()
	ui.show_page("")
	if is_instance_valid(playpen): playpen.prepare_for_match()
	_sync_controls()
