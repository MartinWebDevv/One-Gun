extends Node
func _ready() -> void:
 run.call_deferred()
func run() -> void:
 get_window().mode = Window.MODE_WINDOWED
 get_window().size = Vector2i(1280,720)
 GameConfig.split_screen_enabled = true
 GameConfig.bot_configs.clear()
 for i in 8: GameConfig.bot_configs.append({"difficulty":"expert","team_id":i % 4})
 GameConfig.teams_enabled = true
 PlayerPrefs.settings["player_name"] = "WWWWWWWWWWWWWWWWWWWWWWWW"
 PlayerPrefs.settings["ui_scale"] = 1.25
 PlayerPrefs.settings["text_size"] = "large"
 GameConfig.player2_name = "WWWWWWWWWWWWWWWWWWWWWWWW"
 AccessibilityManager.apply_all()
 var lobby := preload("res://game_setup.tscn").instantiate()
 add_child(lobby)
 await get_tree().create_timer(3).timeout
 await RenderingServer.frame_post_draw
 var out := ProjectSettings.globalize_path("res://artifacts/quality_pass_20260907/roster_captures")
 DirAccess.make_dir_recursive_absolute(out)
 get_viewport().get_texture().get_image().save_png(out.path_join("roster_720_large.png"))
 lobby._show_local_loading()
 await get_tree().process_frame
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png(out.path_join("local_loading.png"))
 lobby._cancel_local_load()
 print("ROSTER_CAPTURE_COMPLETE")
 lobby.queue_free()
 await get_tree().process_frame
 get_tree().quit()
