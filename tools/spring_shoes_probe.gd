extends SceneTree

func _init() -> void:
	var packed := load("res://models/springShoes/SpringShoes.tscn") as PackedScene
	if packed == null:
		push_error("Could not load SpringShoes.tscn")
		quit(1)
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	_print_tree(instance, "")
	quit()

func _print_tree(node: Node, indent: String) -> void:
	var extra := ""
	if node is Node3D:
		extra += " pos=" + str((node as Node3D).position) + " scale=" + str((node as Node3D).scale)
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		extra += " aabb=" + str((node as MeshInstance3D).mesh.get_aabb())
	print(indent + node.name + " [" + node.get_class() + "]" + extra)
	for child in node.get_children():
		_print_tree(child, indent + "  ")
