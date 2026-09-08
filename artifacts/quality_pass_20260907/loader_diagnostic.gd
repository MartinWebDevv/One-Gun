extends Node
func _ready() -> void:
 run.call_deferred()
func run() -> void:
 var lobby := preload("res://game_setup.tscn").instantiate()
 add_child(lobby)
 for i in 15:
  await get_tree().create_timer(1).timeout
  var preview = lobby._map_preview
  print("LOAD_DIAG ",i," ticket=",preview._load_ticket," generation=",preview._load_generation," index=",preview._current_index," requested=",preview._requested_index," map=",preview._current_map," processing=",SceneLoadManager.is_processing()," jobs=",SceneLoadManager._jobs)
  for job in SceneLoadManager._jobs: print("STATUS ",ResourceLoader.load_threaded_get_status(job.path))
 get_tree().quit()
