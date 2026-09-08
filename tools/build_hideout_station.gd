extends SceneTree
## Rebuild the editable production station from its authoring scripts.
func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--bake-live-lobby"):
		quit(1)
		return
	_bake.call_deferred()
func _bake() -> void:
	var station := preload("res://maps/hideout/station.gd").new()
	root.add_child(station)
	station.environment.glow_enabled=true
	station.environment.ssao_enabled=true
	_own(station,station)
	var packed := PackedScene.new()
	var result := packed.pack(station)
	if result==OK: result=ResourceSaver.save(packed,"res://maps/hideout/station.tscn")
	print("HIDEOUT STATION BAKE: ",error_string(result))
	quit(0 if result==OK else 1)
func _own(node: Node, scene_root: Node) -> void:
	if node!=scene_root: node.owner=scene_root
	for key in node.get_meta_list():
		if str(key).begins_with("one_gun_quality_"): node.remove_meta(key)
	for child in node.get_children(): _own(child,scene_root)
