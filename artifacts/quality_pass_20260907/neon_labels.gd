extends Node3D
func _ready() -> void:
 run.call_deferred()
func run() -> void:
 get_window().mode=Window.MODE_WINDOWED
 get_window().size=Vector2i(1600,900)
 var map := preload("res://maps/test/SpaceStationPrototype.tscn").instantiate()
 for child in map.get_children():
  if child.name in preload("res://lobby_map_preview.gd").STRIP_NAMES: child.free()
 add_child(map)
 var camera := Camera3D.new()
 camera.fov=60
 add_child(camera)
 camera.current=true
 var out := ProjectSettings.globalize_path("res://artifacts/quality_pass_20260907/neon_labels")
 DirAccess.make_dir_recursive_absolute(out)
 for label in map.get_node("ZoneLabels").get_children():
  camera.global_position=label.global_position+label.global_basis.z.normalized()*14-Vector3.UP*1.5
  camera.look_at(label.global_position)
  for frame in 8: await get_tree().process_frame
  await RenderingServer.frame_post_draw
  get_viewport().get_texture().get_image().save_png(out.path_join(str(label.name)+".png"))
 print("NEON_LABEL_CAPTURE: PASS seven viewpoints")
 get_tree().quit()
