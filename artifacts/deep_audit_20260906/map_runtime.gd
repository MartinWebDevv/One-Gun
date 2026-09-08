extends Node3D
const OUT := "res://artifacts/deep_audit_20260906/maps"
var rows: Array = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	PlayerPrefs.settings.merge(PlayerSettingsApplier.QUALITY_PRESETS.low, true)
	PlayerPrefs.settings["quality_preset"] = "low"
	PlayerPrefs.settings["fps_limit"] = 0
	PlayerPrefs.settings["vsync_enabled"] = false
	PlayerSettingsApplier.apply_video(PlayerPrefs.settings,get_tree(),false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1920,1080)
	Engine.max_fps = 0
	GameConfig.split_screen_enabled = false
	GameConfig.bot_configs.clear()
	for i in range(9): GameConfig.bot_configs.append({"difficulty":"expert","team_id":-1})
	GameConfig.round_time_limit = 180.0
	GameConfig.rounds_per_set = 99
	print("MAP_AUDIT_GPU ",RenderingServer.get_video_adapter_name())
	var wrapper := get_tree().current_scene
	for cycle in range(2):
		for index in MapRegistry.map_count():
			var data := MapRegistry.get_map(index)
			var start := Time.get_ticks_usec()
			var packed := load(str(data.scene_path)) as PackedScene
			var loaded := Time.get_ticks_usec()
			var arena := packed.instantiate() as Node3D
			get_tree().root.add_child(arena)
			get_tree().current_scene = arena
			var instantiated := Time.get_ticks_usec()
			await get_tree().create_timer(8.0).timeout
			var row := {"map":data.name,"cycle":cycle,"load_ms":(loaded-start)/1000.0,"instantiate_ms":(instantiated-loaded)/1000.0,"nodes":_node_count(arena),"actors":get_tree().get_nodes_in_group("player").size(),"gun_count":get_tree().get_nodes_in_group("gun").size(),"spawns":get_tree().get_nodes_in_group("spawn_point").size(),"nav_polygons":0,"meshes":arena.find_children("*","MeshInstance3D",true,false).size(),"occluders":arena.find_children("*","OccluderInstance3D",true,false).size()}
			for nav in arena.find_children("*","NavigationRegion3D",true,false):
				if nav.navigation_mesh != null: row.nav_polygons += nav.navigation_mesh.get_polygon_count()
			var times: Array[float] = []
			var previous := Time.get_ticks_usec()
			var end := previous+6000000
			while Time.get_ticks_usec()<end:
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				times.append((now-previous)/1000.0)
				previous=now
			times.sort()
			row["frame_median_ms"] = times[times.size()/2]
			row["frame_p95_ms"] = times[mini(times.size()-1,int(times.size()*0.95))]
			row["frame_max_ms"] = times[-1]
			row["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			row["render_primitives"] = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			row["static_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0
			row["video_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0
			row["resources"] = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
			if cycle == 0:
				await RenderingServer.frame_post_draw
				var shot := get_viewport().get_texture().get_image()
				shot.save_png(OUT+"/%d_gameplay.png"%index)
			get_tree().current_scene = wrapper
			arena.queue_free()
			arena=null
			packed=null
			await get_tree().create_timer(1.0).timeout
			row["after_nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
			row["after_resources"] = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
			row["after_static_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0
			row["after_video_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0
			rows.append(row)
			print("MAP_AUDIT ",JSON.stringify(row))
			var file := FileAccess.open(OUT+"/runtime.json",FileAccess.WRITE)
			file.store_string(JSON.stringify(rows,"\t")); file.close()
	print("MAP_RUNTIME_AUDIT_COMPLETE")
	get_tree().quit()

func _node_count(node:Node)->int:
	var count:=1
	for child in node.get_children():count+=_node_count(child)
	return count

