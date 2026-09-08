extends Node
## Renders actual gameplay-camera frames; no separate cinematic camera is used.
var output: String
var frame_times: Array[float] = []

func run(lab: Node3D) -> void:
	output = ProjectSettings.globalize_path("res://../artifacts")
	if not lab.low: output += "/high"
	DirAccess.make_dir_recursive_absolute(output)
	lab.get_window().size = Vector2i(1920,1080)
	lab._action("enter",null)
	await get_tree().create_timer(1.2).timeout
	lab.pilot.controls_enabled = false
	await snap(lab,"01_arrival")
	lab.pilot.position = Vector3(-1,-0.59,4)
	lab.pilot.look.rotation = Vector3(-0.11,-0.04,0)
	await snap(lab,"02_central_pit")
	lab.pilot.position = Vector3(-5,0.02,-5)
	lab.pilot.look.rotation = Vector3(-0.05,0.5,0)
	await snap(lab,"03_locker")
	lab._open("events")
	await snap(lab,"04_events")
	lab._action("public",null)
	lab._open("locker")
	lab.session.tick(8.1)
	await snap(lab,"05_ready_anywhere")
	lab.session.cancel()
	lab._open("")
	for i in range(9): lab.session.add_friend()
	await get_tree().create_timer(2.5).timeout
	lab.pilot.respawn()
	lab.pilot.controls_enabled = false
	await snap(lab,"06_full_party")
	# Warmed rendered sample at maximum mock roster, using the Low preset.
	await get_tree().create_timer(1).timeout
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec()-start < 6000000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_times.append((now-previous)/1000.0)
		previous = now
	frame_times.sort()
	var report := {
		"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),
		"preset":"Low" if lab.low else "High",
		"window_pixels":str(lab.get_window().size),
		"render_scale":lab.get_viewport().scaling_3d_scale,
		"mock_roster":10,
		"sample_seconds":6,
		"frames":frame_times.size(),
		"frame_ms_median":frame_times[frame_times.size()/2],
		"frame_ms_p95":frame_times[int(frame_times.size()*0.95)],
		"frame_ms_max":frame_times.back(),
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),
		"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"nodes":get_tree().get_node_count(),
		"scope":"Development-machine rendered sample; not a laptop, full combat, or integrated transition benchmark."
	}
	var file := FileAccess.open(output+"/render_profile.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("LAB RENDER PROFILE: "+JSON.stringify(report))
	lab.pilot.position = Vector3(8.0,0.02,3.0)
	lab.pilot.look.rotation = Vector3(-0.08,-1.3,0)
	lab.session.rehearse("Private event")
	lab.session.accept()
	lab.pilot.controls_enabled = false
	await get_tree().create_timer(1.0).timeout
	await snap(lab,"08_departure")
	lab.session.cancel()
	lab.pilot.position = Vector3(4.0,0.02,-2.0)
	lab.pilot.look.rotation = Vector3(-0.7,1.8,0)
	await snap(lab,"09_pit_detail")
	lab.pilot.respawn()
	lab._open("local")
	lab.get_window().size = Vector2i(1280,720)
	await snap(lab,"07_setup_720p")
	get_tree().quit()

func snap(lab: Node3D, filename: String) -> void:
	lab.ui.toast_left = 0
	lab.ui.toast.visible = false
	for i in range(12): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := lab.get_viewport().get_texture().get_image()
	var error := img.save_png(output+"/"+filename+".png")
	assert(error==OK,"Screenshot save failed")
	print("LAB CAPTURE: "+filename)
