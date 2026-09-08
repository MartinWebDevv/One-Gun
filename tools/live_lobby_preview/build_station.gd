extends Node
## Authoring helper; rebuilds station.tscn. The saved scene stays visible/editable in Godot.
func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--bake-live-lobby"):
		push_error("Station rebuild requires --bake-live-lobby")
		get_tree().quit(1)
		return
	var station := preload("res://tools/live_lobby_preview/station.gd").new()
	add_child(station)
	station.environment.glow_enabled = true
	station.environment.ssao_enabled = true
	_own(station,station)
	var packed := PackedScene.new()
	var result := packed.pack(station)
	if result == OK: result = ResourceSaver.save(packed,"res://tools/live_lobby_preview/station.tscn")
	print("LIVE LOBBY STATION BAKE: ",error_string(result))
	get_tree().quit(0 if result == OK else 1)

func _own(node: Node, root: Node) -> void:
	if node != root: node.owner = root
	for key in node.get_meta_list():
		if str(key).begins_with("one_gun_quality_"): node.remove_meta(key)
	for child in node.get_children(): _own(child,root)
