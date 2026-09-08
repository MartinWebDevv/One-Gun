extends RefCounted
## Recessed entrance: the sliding threshold belongs to the south wall.
const G = preload("res://maps/hideout/geometry.gd")
const SPAWN := Vector3(0,2.29,35.5)
const DOOR_Z := 30.0

static func build(station: Node3D) -> void:
	var root := Node3D.new()
	root.name="ArrivalArchitecture"
	station.root_geo.add_child(root)
	G.box(root,"ArrivalHallFloor",Vector3(0,0.95,36.6),Vector3(9.2,0.5,13.5),station.concrete,true)
	G.box(root,"ArrivalHallRoof",Vector3(0,6.65,36.6),Vector3(9.6,0.3,13.8),station.steel,true)
	for x in [-4.7,4.7]:
		G.box(root,"ArrivalHallWall",Vector3(x,3.75,36.65),Vector3(0.4,5.5,13.7),station.tile,true)
		G.box(root,"HallGuideStripe",Vector3(x-signf(x)*0.22,2.1,36.5),Vector3(0.035,0.15,13),station.gold)
	G.box(root,"ArrivalHallEnd",Vector3(0,3.8,43.3),Vector3(9.6,5.6,0.4),station.tile,true)
	# Raised landing and six shallow treads terminate at the wall's door plane.
	G.box(root,"ArrivalLanding",Vector3(0,0.6,29.4),Vector3(8.8,1.2,1.2),station.concrete,true)
	for i in range(6):
		G.box(root,"ArrivalStair",Vector3(0,(i+1)*0.1,25.95+i*0.52),Vector3(8.8,(i+1)*0.2,0.53),station.concrete,true)
		G.box(root,"ArrivalStairNose",Vector3(0,(i+1)*0.2+0.018,25.69+i*0.52),Vector3(8.8,0.025,0.06),station.gold)
	for x in [-4.5,4.5]:
		G.box(root,"ArrivalFrame",Vector3(x,3.75,29.7),Vector3(0.2,5.1,0.2),station.steel,true)
	G.box(root,"ArrivalHeader",Vector3(0,6.3,29.7),Vector3(9.2,0.35,0.25),station.steel,true)
	G.panel(root,"ArrivalSign","WELCOME HOME",Vector3(0,6.3,29.5),Vector2(8.8,0.75),G.CYAN).rotation.y=PI
	G.panel(root,"InsideWelcome","THE HIDEOUT",Vector3(0,5.9,30.5),Vector2(8.3,0.65),G.CYAN)
	G.label(root,"ArrivalWait","WELCOME / DOORS OPEN AUTOMATICALLY",Vector3(0,5.23,30.5),40,G.PAPER,0.007)
	for label in root.find_children("*","Label3D",true,false): label.set_draw_flag(Label3D.FLAG_DOUBLE_SIDED,false)
	for z in [33.0,39.5]:
		G.box(root,"HallLight",Vector3(0,6.4,z),Vector3(3.2,0.08,0.35),station.warm)
		G.lamp(station,Vector3(0,5.7,z),Color("ffdfb2"),1.3,8)
	for i in range(2):
		var door := G.box(station,"ArrivalDoor%d" % i,Vector3(-2.15+i*4.3,3.65,DOOR_Z),Vector3(4.3,4.9,0.16),station.steel,true)
		for side in [-1,1]:
			G.box(door,"DoorGlass",Vector3(0,0.6,side*0.115),Vector3(1.6,1.4,0.04),station.dark)
			G.box(door,"CautionStripe",Vector3(0,-0.5,side*0.115),Vector3(4.2,0.16,0.04),station.gold)
		station.doors.append(door)
