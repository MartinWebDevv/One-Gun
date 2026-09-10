extends SceneTree
## Keep the project-default Theme resource in sync with its runtime source.
func _initialize() -> void:
	var builder:=preload("res://theme_manager.gd").new()
	builder._build_fonts()
	var result:=ResourceSaver.save(builder._build_theme(),"res://one_gun_theme.tres")
	builder.free()
	print("FRONTEND THEME BAKE: ",error_string(result))
	quit(0 if result==OK else 1)
