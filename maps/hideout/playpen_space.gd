extends RefCounted
## One continuous practice complex beyond the main concourse's north wall.
const G = preload("res://maps/hideout/geometry.gd")
const BARRIER_LAYER := 1 << 19
const BARRIER_Z := -30.2
const FLOOR_Y := -1.2
const RESPAWN := Vector3(17,1.09,-28.3)
const BAY_CENTERS := [-0.5,34.5]

static func contains(point: Vector3) -> bool:
	if contains_scrap(point): return true
	if not point.is_finite() or point.y < -5 or point.y > 8.2: return false
	if point.z <= BARRIER_Z+0.01 and point.z >= -34.1 and point.x>10.15 and point.x<23.85: return true
	if point.x > -9.7 and point.x < 43.7 and point.z < -33.9 and point.z > -78.7: return true
	if point.x >= 43.7 and point.x < 159.7 and point.z < -36.3 and point.z > -73.7: return true
	return point.x > -91.7 and point.x <= -9.7 and point.z < -35.3 and point.z > -78.7

static func contains_scrap(point: Vector3) -> bool:
	if not point.is_finite() or point.y< -5 or point.y>10.2: return false
	if point.x> -10 and point.x<44 and point.z< -85 and point.z> -135: return true
	return point.x>13 and point.x<21 and point.z>= -85 and point.z< -78.7 and point.y<6.9

static func supply_position(bay: int, slot: int) -> Vector3:
	return Vector3(BAY_CENTERS[bay]+(slot%8-3.5)*1.95,FLOOR_Y+0.3,-73.5+(slot/8)*2.6)

static func occlude(root: Node3D, at: Vector3, size: Vector3) -> void:
	var node := OccluderInstance3D.new()
	node.name="SolidWallOccluder"
	var box := BoxOccluder3D.new()
	box.size=size-Vector3.ONE*0.06
	node.occluder=box
	root.add_child(node)
	node.position=at

static func wall(root: Node3D, title: String, at: Vector3, size: Vector3, mat: Material) -> void:
	G.box(root,title,at,size,mat,true)
	occlude(root,at,size)

static func build(station: Node3D) -> void:
	var kit := preload("res://maps/hideout/arcade.gd").new()
	var root := Node3D.new()
	root.name="PlayPenArchitecture"
	station.root_geo.add_child(root)
	for data in [[Vector3(-8.6,5.2,-30),Vector3(36.8,10.4,0.7)],[Vector3(25.6,5.2,-30),Vector3(2.8,10.4,0.7)],[Vector3(17,8.8,-30),Vector3(14.4,3.2,0.7)]]:
		occlude(root,data[0],data[1])
	# Entrance finishes sit against the north wall, not out in the concourse.
	for x in [9.85,24.15]:
		G.box(root,"PortalTrim",Vector3(x,3.5,-29.57),Vector3(0.22,7,0.12),kit.brass)
		wall(root,"EntryReturn",Vector3(x,3.5,-32),Vector3(0.3,7,3.8),kit.cream)
	G.box(root,"EntryCeiling",Vector3(17,7.1,-32),Vector3(14.5,0.2,4.2),kit.ink,true)
	G.panel(root,"PlayPenHeader","PLAY PEN",Vector3(17,6.4,-29.48),Vector2(13.8,0.9),G.ORANGE)
	G.label(root,"PlayPenRule","GEAR STAYS INSIDE",Vector3(17,5.55,-29.46),53,G.PAPER,0.008)
	G.box(root,"EntryLanding",Vector3(17,-0.2,-30.18),Vector3(14,0.4,0.65),kit.stone,true)
	for i in range(6):
		var y := -0.2*(i+1)
		var z := -30.73-i*0.55
		G.box(root,"ArenaStep",Vector3(17,y-0.12,z),Vector3(14,0.24,0.56),kit.stone,true)
		G.box(root,"StepNose",Vector3(17,y+0.017,z+0.26),Vector3(14,0.025,0.065),kit.brass)
	var barrier := StaticBody3D.new()
	barrier.name="PlayPenOrdnanceBarrier"
	barrier.collision_layer=BARRIER_LAYER
	barrier.collision_mask=0
	station.add_child(barrier)
	barrier.position=Vector3(17,3.5,BARRIER_Z)
	var shape := BoxShape3D.new()
	shape.size=Vector3(14.5,8,0.3)
	var collision := CollisionShape3D.new()
	collision.shape=shape
	barrier.add_child(collision)
	G.box(root,"BarrierFloor",Vector3(17,0.035,BARRIER_Z),Vector3(14,0.04,0.35),G.material("pen_line",G.ORANGE))
	var line := G.label(root,"BarrierFloorText","COMBAT AREA / GEAR CLEARED ON EXIT",Vector3(17,0.05,-29.65),46,G.ORANGE,0.011)
	line.rotation.x=-PI/2
	G.panel(root,"HallExitSign","MAIN HALL / GEAR CLEARED ON EXIT",Vector3(17,5.3,-32),Vector2(12,0.7),G.CYAN).rotation.y=PI
	G.box(root,"ArenaFoundation",Vector3(17,-1.55,-56.5),Vector3(55,0.7,45),G.material("pen_floor",Color("e4d5c4")),true)
	# Shared side walls have real openings into the two training rooms.
	for section in [[-10.0,-36.5,5.0],[-10.0,-56.5,22.0],[-10.0,-76.5,5.0],[44.0,-43.0,18.0],[44.0,-67.0,24.0]]:
		var length: float=section[2]
		# East doorway is -59..-51; west entry -45.5..-39, exit -74..-67.5.
		if section[0]==44.0:
			length=17.0 if section[1]==-43.0 else 20.0
			section[1]=-42.5 if section[1]==-43.0 else -69.0
		wall(root,"ArenaSideSection",Vector3(section[0],3,section[1]),Vector3(0.6,8.4,length),kit.cream)
	for door in [[-10.0,-42.25,6.5],[-10.0,-70.75,6.5],[44.0,-55.0,8.0]]:
		wall(root,"TrainingDoorLintel",Vector3(door[0],6.65,door[1]),Vector3(0.6,1.1,door[2]),kit.painted)
	for x in [1.5,32.5]: wall(root,"ArenaBack",Vector3(x,3,-79),Vector3(23,8.4,0.6),kit.cream)
	wall(root,"ScrapLintel",Vector3(17,6.3,-79),Vector3(8,1.8,0.6),kit.painted)
	for x in [0.0,34.0]: wall(root,"ArenaEntryShoulder",Vector3(x,3,-34),Vector3(20,8.4,0.6),kit.painted)
	G.box(root,"ArenaRoof",Vector3(17,7.4,-56.5),Vector3(55,0.4,46),kit.ink,true)
	for z in [-40.0,-52.0,-64.0,-76.0]:
		G.box(root,"ArenaRoofRib",Vector3(17,7.04,z),Vector3(54,0.38,0.35),kit.brass)
		for x in [2.0,32.0]:
			G.box(root,"ArenaPractical",Vector3(x,6.82,z),Vector3(3.6,0.1,0.4),kit.lamp_mat)
			G.lamp(station,Vector3(x,6.2,z),Color("ffe0b2"),1.4,14)
	var court := G.material("pen_court",Color("cab8ce"))
	G.box(root,"PracticeCourt",Vector3(17,-1.185,-52),Vector3(44,0.025,26),court)
	for x in [-5.0,39.0]: G.box(root,"CourtSideline",Vector3(x,-1.16,-52),Vector3(0.12,0.025,26),kit.cream)
	for z in [-39.0,-65.0]: G.box(root,"CourtEndline",Vector3(17,-1.16,z),Vector3(44,0.025,0.12),kit.cream)
	G.ring(root,"PracticeCircle",5.8,5.95,-1.15,kit.cream).position=Vector3(17,0,-52)
	for z in [-42.0,-62.0]:
		var text := G.label(root,"CourtStencil","PLAY PEN" if z>-50 else "FLOOR LOOT",Vector3(17,-1.145,z),92,G.PAPER,0.023)
		text.rotation.x=-PI/2
	for x in [1.5,32.5]: G.box(root,"ArmoryBackWainscot",Vector3(x,0.15,-78.63),Vector3(23,2.7,0.1),kit.painted)
	for bay in range(BAY_CENTERS.size()):
		var x: float=BAY_CENTERS[bay]
		G.box(root,"SupplyApron",Vector3(x,-1.19,-70.8),Vector3(16,0.01,9),kit.stone)
		G.panel(root,"SupplyHeader","ARMORY / 0%d" % (bay+1),Vector3(x,3.75,-78.58),Vector2(14,0.8),G.CYAN)
		G.label(root,"SupplyRule","FLOOR SUPPLIES / REFILL 2s",Vector3(x,2.83,-78.54),35,G.PAPER,0.008)
		G.box(root,"ArmoryCanopy",Vector3(x,4.8,-77.7),Vector3(16.2,0.2,2.5),kit.painted)
		G.box(root,"ArmoryCanopyTrim",Vector3(x,4.8,-76.4),Vector3(16.2,0.24,0.09),kit.brass)
	for at in [Vector3(3,-0.25,-48),Vector3(31,-0.25,-48),Vector3(8,-0.25,-59),Vector3(26,-0.25,-59)]:
		G.box(root,"ArenaCover",at,Vector3(5,1.9,1.5),kit.painted,true)
		G.box(root,"CoverTop",at+Vector3(0,0.99,0),Vector3(5.2,0.1,1.65),kit.timber)
	G.panel(root,"SparringTerminal","SPARRING PARTNER",Vector3(8.5,2.8,-34.4),Vector2(5.1,0.65),G.CYAN).rotation.y=PI
	station._zone("sparring",Vector3(8.5,0,-36.5),Vector3(5,4,3))
	var spawn := Marker3D.new()
	spawn.name="PlayPenRespawn"
	station.add_child(spawn)
	spawn.position=RESPAWN
	preload("res://maps/hideout/training_space.gd").build(station)
