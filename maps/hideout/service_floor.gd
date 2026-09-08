extends RefCounted
## Both service wings use the same metre grid, palette and joint width.
const G = preload("res://maps/hideout/geometry.gd")

static func build(parent: Node3D, title: String, origin: Vector2i, cells: Vector2i, kit: RefCounted) -> void:
	var root := Node3D.new()
	root.name=title
	parent.add_child(root)
	G.box(root,"Grout",Vector3(origin.x+cells.x*0.5,0.013,origin.y+cells.y*0.5),Vector3(cells.x,0.018,cells.y),kit.mortar)
	for x in range(origin.x,origin.x+cells.x):
		for z in range(origin.y,origin.y+cells.y):
			G.box(root,"ServiceTile",Vector3(x+0.5,0.026,z+0.5),Vector3(0.975,0.008,0.975),kit.stone if posmod(x+z,2) else kit.cream)
