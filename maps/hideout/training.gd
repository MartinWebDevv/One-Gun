extends Node
## Preview range, flow-course controller, and replaceable local records provider.
const Space = preload("res://maps/hideout/training_space.gd")
const Target = preload("res://maps/hideout/range_target.gd")
const G = preload("res://maps/hideout/geometry.gd")
const Loadout = preload("res://maps/hideout/course_loadout.gd")
const Records = preload("res://maps/hideout/course_records.gd")
var records: RefCounted
var board_tab := "lobby"
var board_assisted := false
var board_leader: Label3D
var board_rows: Label3D
var board_footer: Label3D
var runner_id := ""
var run_rules := ""
var assisted := false
var selected_powerup := false
var board_tick := 0.0
var last_finish_text := ""
var lab: Node3D
var targets: Array[StaticBody3D]=[]
var range_indices := [0,0,0]
var hits := [0,0,0]
var range_labels: Array[Label3D]=[]
var running := false
var elapsed := 0.0
var best := -1.0
var last_time := -1.0
var next_gate := 1
var falls := 0
var recovery := Space.RECOVERY[0]
var hud: Label
var hud_left := 0.0
var show_result := 0.0
var status := "ENTER THE START DOOR"

func setup(preview: Node3D) -> void:
	lab=preview
	process_physics_priority=9000
	for i in range(3):
		var dummy := Target.new()
		dummy.name="RangeTarget%d" % i
		dummy.training=self
		dummy.lane=i
		lab.add_child(dummy)
		targets.append(dummy)
		range_labels.append(lab.station.find_child("RangeStatus%d" % i,true,false))
		set_distance(i,0)
	for area in lab.station.find_children("*","Area3D",true,false):
		if area.has_meta("course_gate"):
			area.body_entered.connect(_gate_entered.bind(int(area.get_meta("course_gate"))))
	hud=Label.new()
	lab.ui.shell.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hud.offset_left=-265
	hud.offset_right=265
	hud.offset_top=92
	hud.offset_bottom=225
	hud.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.add_theme_font_override("font",load("res://fonts/cinematic/barlow_condensed/BarlowCondensed-ExtraBold.ttf"))
	hud.add_theme_font_size_override("font_size",25)
	hud.add_theme_color_override("font_color",G.GREEN)
	board_leader=lab.station.find_child("CourseBoardLeader",true,false)
	board_rows=lab.station.find_child("CourseBoardRows",true,false)
	board_footer=lab.station.find_child("CourseBoardFooter",true,false)
	var local := Records.new()
	local.configure("" if lab.automation or NetworkManager.is_online() else "user://hideout/course_records.json")
	set_records_provider(local)
	lab.session.changed.connect(refresh_roster)


func set_distance(lane: int, index: int) -> void:
	if lane<0 or lane>=3 or index<0 or index>=Space.DISTANCES.size(): return
	range_indices[lane]=index
	targets[lane].position=Vector3(Space.FIRING_X+Space.DISTANCES[index],Space.FLOOR_Y,Space.LANE_Z[lane])
	targets[lane].reset_physics_interpolation()
	_refresh_lane(lane)

func cycle_distance(lane: int) -> void:
	set_distance(lane,(int(range_indices[lane])+1)%Space.DISTANCES.size())
	lab.ui.show_toast("LANE %d / %d metres" % [lane+1,Space.DISTANCES[range_indices[lane]]])

func target_hit(lane: int) -> void:
	hits[lane]+=1
	_refresh_lane(lane)

func reset_hits() -> void:
	hits=[0,0,0]
	for lane in range(3): _refresh_lane(lane)

func _refresh_lane(lane: int) -> void:
	if is_instance_valid(range_labels[lane]):
		range_labels[lane].text="%d m / %d HITS" % [Space.DISTANCES[range_indices[lane]],hits[lane]]

func range_hint(lane: int) -> String:
	return "LANE %d / %d m > %d m" % [lane+1,Space.DISTANCES[range_indices[lane]],Space.DISTANCES[(int(range_indices[lane])+1)%Space.DISTANCES.size()]]

func _gate_entered(body: Node3D, index: int) -> void:
	if body!=lab.pilot or body.is_eliminated or not lab.controls_enabled: return
	if index==0:
		if not running: start_trial()
		return
	if not running or index!=next_gate: return
	if index==Space.COURSE_GATES.size()-1:
		running=false
		last_time=elapsed
		if best<0 or last_time<best: best=last_time
		show_result=12
		status="FINISHED / "+format_time(last_time)
		last_finish_text="%s / %s / %s" % [lab.session.alias_name,"POWER-UP" if assisted else "STANDARD",format_time(last_time)]
		records.submit_completed_run(run_rules+("/powerup" if assisted else "/standard"),runner_id,roundi(last_time*1000),falls)
		Loadout.clear(lab.pilot)
		lab.ui.show_toast("AGILITY / %s / %d falls / %s run" % [format_time(last_time),falls,"Power-Up" if assisted else "Standard"])
	else:
		recovery=Space.RECOVERY[index]
		next_gate+=1

func start_trial() -> void:
	refresh_roster()
	runner_id=viewer_id()
	run_rules=movement_key()
	assisted=selected_powerup
	Loadout.start(lab.pilot,assisted)
	running=true
	elapsed=0
	next_gate=1
	falls=0
	recovery=Space.RECOVERY[0]
	status="RUNNING"
	show_result=0

func cancel_trial(message := "RUN CANCELLED") -> void:
	if running:
		running=false
		status=message
		show_result=5
		Loadout.clear(lab.pilot)

func can_select_mode(actor: Node3D, powered: bool) -> bool:
	var at: Vector3=Space.Course.MODE_BUTTONS[1 if powered else 0]
	return is_instance_valid(actor) and not actor.is_eliminated and absf(actor.position.x-at.x)<3.2 and absf(actor.position.z-at.z)<1.65

func select_mode(powered: bool) -> void:
	if not can_select_mode(lab.pilot,powered): return
	cancel_trial()
	selected_powerup=powered
	Loadout.clear(lab.pilot)
	lab.ui.show_toast(("POWER-UP RUN" if powered else "STANDARD RUN")+" READY / CROSS THE START LINE")

func restart_trial() -> void:
	cancel_trial()
	if lab.pilot.is_eliminated: return
	lab.pilot.position=Vector3(-8,-0.11,-42.25)
	lab.pilot.velocity=Vector3.ZERO
	lab.pilot.get_node("AimPivot").rotation=Vector3(0,PI/2,0)
	lab.pilot.reset_physics_interpolation()
	lab.playpen.sync_actor(lab.pilot)
	lab._open("")

func _physics_process(delta: float) -> void:
	if lab==null: return
	show_result=maxf(0,show_result-delta)
	var actor: CharacterBody3D=lab.pilot
	if actor.is_eliminated: cancel_trial("DEATH / RUN CANCELLED")
	elif running:
		# Only the marked finish may complete a run. Backtracking cannot submit a time.
		if viewer_id()!=runner_id or movement_key()!=run_rules or (not Space.in_course(actor.position) and not (actor.position.x< -7 and actor.position.z< -67.5 and actor.position.z> -74)): cancel_trial()
		elif lab.controls_enabled: elapsed+=delta
	if Space.in_course(actor.position) and actor.position.y < -2.0 and not actor.is_eliminated:
		if running:
			elapsed+=2.0
			falls+=1
		actor.position=recovery if running else Space.RECOVERY[0]
		actor.velocity=Vector3.ZERO
		actor.reset_physics_interpolation()
		lab.ui.show_toast("AGILITY / Fall +2s / Returned to checkpoint" if running else "AGILITY / Returned to entry")
	board_tick-=delta
	if board_tick<=0:
		board_tick=0.2
		_render_wall_records()
		preload("res://maps/hideout/course_board_ui.gd").refresh_live(lab.ui,self)
	hud_left-=delta
	if hud_left<=0:
		hud_left=0.05
		hud.visible=lab.ui.page.is_empty() and (running or show_result>0 or Space.in_course(actor.position))
		hud.text="AGILITY / "+(format_time(elapsed) if running else status)
		if running: hud.text+="\nCHECKPOINT %d / 5   |   FALLS %d" % [next_gate-1,falls]
		if running: hud.text+=" / "+("POWER-UP" if assisted else "STANDARD")
		var personal: int=records.personal_best(records_bucket(assisted),viewer_id())
		if personal>=0: hud.text+="\nYOUR BEST / "+format_time(personal/1000.0)

static func format_time(seconds: float) -> String:
	var milliseconds := roundi(seconds*1000)
	return "%02d:%02d.%03d" % [milliseconds/60000,(milliseconds/1000)%60,milliseconds%1000]

func set_records_provider(provider: RefCounted) -> void:
	if records and records.changed.is_connected(_refresh_records): records.changed.disconnect(_refresh_records)
	records=provider
	records.changed.connect(_refresh_records)
	refresh_roster()
	_refresh_records()

func viewer_id() -> String:
	var account := SupabaseManager.current_user_id()
	return "account:"+account.sha256_text() if not account.is_empty() else "local:profile"

func refresh_roster() -> void:
	if records==null: return
	var roster: Array=[{"id":viewer_id(),"name":lab.session.alias_name}]
	for i in range(lab.session.guests.size()): roster.append({"id":"rehearsal:"+str(i),"name":lab.session.guests[i]})
	for person in lab.session.residents: roster.append({"id":"resident:"+str(person),"name":person})
	records.set_members(roster)

func movement_key() -> String:
	return "%s/dash%d/sprint%d/jump%.3f" % [Space.Course.COURSE_ID,GameConfig.max_dash_charges,int(GameConfig.sprinting_enabled),lab.pilot.jump_velocity]

func records_bucket(with_assists: bool) -> String:
	return movement_key()+("/powerup" if with_assists else "/standard")

func rules_caption() -> String:
	return "%d DASHES / SPRINT %s / JUMP %.1f" % [GameConfig.max_dash_charges,"ON" if GameConfig.sprinting_enabled else "OFF",lab.pilot.jump_velocity]

func _movement_assisted() -> bool:
	var actor: CharacterBody3D=lab.pilot
	return actor.speed_surge_timer>0 or actor.double_jump_shoes_active or actor.extra_dash_charge>0 or not is_equal_approx(actor.slow_multiplier_value,1.0) or actor._spring_air_active or actor._directional_launch_active

func live_status(id: String, powered: bool) -> String:
	if running and id==runner_id and powered==assisted:
		return "RUNNING %s / CP %d / %d FALLS" % [format_time(elapsed),next_gate-1,falls]
	return ""

func _render_wall_records() -> void:
	if not is_instance_valid(board_leader): return
	for powered in [false,true]:
		var lines: PackedStringArray=["POWER-UP RUN" if powered else "STANDARD"]
		var rows: Array=records.lobby_rows(records_bucket(powered))
		for i in mini(rows.size(),10):
			var row: Dictionary=rows[i]
			var value: String=format_time(row.time_ms/1000.0) if row.time_ms>=0 else "NO FINISH"
			var live:=live_status(str(row.id),powered)
			if not live.is_empty(): value=live.get_slice(" / ",0)
			lines.append("%02d  %s  %s" % [i+1,str(row.name).left(16),value])
		if rows.is_empty(): lines.append("WAITING FOR RUNNERS")
		var target: Label3D=board_rows if powered else board_leader
		var text: String="\n".join(lines)
		if target.text!=text: target.text=text
	if board_footer:
		board_footer.text="LAST FINISH / "+last_finish_text if not last_finish_text.is_empty() else "%d PLAYERS / INTERACT FOR BEST, LAST RUN & FINISHES" % records.members.size()

func _refresh_records() -> void:
	_render_wall_records()
	if lab.ui.page=="course_board": preload("res://maps/hideout/course_board_ui.gd").refresh_live(lab.ui,self)
