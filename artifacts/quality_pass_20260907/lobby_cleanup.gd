extends Node
func _ready() -> void:
 run.call_deferred()
func run() -> void:
 for i in 5:
  var menu := preload("res://game_setup.tscn").instantiate()
  add_child(menu)
  for frame in 4: await get_tree().process_frame
  menu.queue_free()
  for frame in 4: await get_tree().process_frame
  print("LOBBY_CLEANUP ", i, " nodes=",Performance.get_monitor(Performance.OBJECT_NODE_COUNT)," orphans=",Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)," resources=",Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
 get_tree().quit()
