extends RefCounted
## Cosmetic geometry only: no colliders, lights, scripts or networking at runtime.
const G=preload("res://maps/hideout/geometry.gd")
static func build(station: Node3D) -> void:
	var root:=Node3D.new()
	root.name="ClubhouseDetails"
	station.root_geo.add_child(root)
	var plum:=G.material("club_planter",Color("51415f"))
	var soil:=G.material("club_soil",Color("352c49"))
	var leaf:=G.material("club_leaf",Color("749b82"))
	var leaf_light:=G.material("club_leaf_light",Color("9bcbb3"))
	# Keep every planter tucked beside walls, away from door thresholds and the pit.
	for at in [Vector3(-17,0,-25.5),Vector3(25,0,-24),Vector3(-24,0,25),Vector3(24,0,25)]:
		G.cylinder(root,"Planter",at+Vector3(0,0.6,0),0.75,1.2,plum)
		G.cylinder(root,"PlanterSoil",at+Vector3(0,1.21,0),0.66,0.035,soil)
		for i in range(7):
			var angle:=i*TAU/7
			var tip: Vector3=at+Vector3(sin(angle)*0.55,1.7+(i%3)*0.35,cos(angle)*0.55)
			G.rod(root,at+Vector3(0,1.2,0),tip,0.06,leaf)
			var blade:=G.box(root,"Leaf",tip,Vector3(0.32,0.95,0.09),leaf_light if i%2 else leaf)
			blade.rotation=Vector3(0,angle,0.4)
	for side in [-1,1]:
		for i in range(4):
			var angle: float=(0.75+i*0.24)*side
			var cushion:=Node3D.new()
			root.add_child(cushion)
			cushion.position=Vector3(sin(angle)*10.9,0,cos(angle)*10.9)
			cushion.rotation.y=angle
			G.box(cushion,"BackCushion",Vector3(0,0.96,0.21),Vector3(1.62,0.52,0.16),G.material("club_upholstery",Color("705b87")))
			G.box(cushion,"Pillow",Vector3(0.5,0.83,0.08),Vector3(0.36,0.38,0.16),G.material("club_pillow",Color("f3aa7c")))
