extends Node
var world: Node3D
var camera: Camera3D
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	reparent(get_tree().root)
	PlayerPrefs.settings["quality_preset"]="low"
	PlayerPrefs.settings["shadow_quality"]="low"
	PlayerPrefs.settings["effects_quality"]="low"
	PlayerPrefs.settings["render_scale"]=0.75
	PlayerPrefs.settings["anti_aliasing"]="off"
	PlayerPrefs.settings["display_mode"]="windowed"
	PlayerPrefs.settings["resolution"]=[1920,1080]
	preload("res://UI/player_settings_applier.gd").apply_video(PlayerPrefs.settings,get_tree())
	get_tree().change_scene_to_file("res://maps/hideout/hideout.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	world=get_tree().current_scene
	camera=Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	var results := {}
	for pose in [["entry",Vector3(17,2,-88),Vector3(17,1,-111)],["ring",Vector3(6,1,-110),Vector3(24,0,-110)],["stands",Vector3(-3,2,-110),Vector3(17,0,-110)]]:
		camera.position=pose[1]
		camera.look_at(pose[2])
		results[pose[0]]=await _sample()
	var before:=Time.get_ticks_usec()
	world.scrap.join_round("watch")
	results["join_ms"]=(Time.get_ticks_usec()-before)/1000.0
	camera.make_current()
	results["countdown_and_start"]=await _sample(7.0,false)
	results["duel"]=await _sample()
	var label := "baseline"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile-label="): label=arg.trim_prefix("--profile-label=")
	var file := FileAccess.open("res://artifacts/hideout_migration/scrap_"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "))
	file.close()
	print("SCRAP_PROFILE ",JSON.stringify(results))
	get_tree().quit()
func _sample(seconds := 3.0, warm := true) -> Dictionary:
	if warm: await get_tree().create_timer(1.0).timeout
	var frames: Array[float]=[]
	var process_ms := 0.0
	var physics_ms := 0.0
	var draws := 0.0
	var prior := Time.get_ticks_usec()
	var until := prior+int(seconds*1000000)
	while Time.get_ticks_usec()<until:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now-prior)/1000.0)
		prior=now
		process_ms+=Performance.get_monitor(Performance.TIME_PROCESS)*1000
		physics_ms+=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
		draws+=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	frames.sort()
	return {"max_ms":frames.back(),"median_ms":frames[frames.size()/2],"p95_ms":frames[int(frames.size()*0.95)],"p99_ms":frames[int(frames.size()*0.99)],"process_ms":process_ms/frames.size(),"physics_ms":physics_ms/frames.size(),"draw_calls":draws/frames.size()}
