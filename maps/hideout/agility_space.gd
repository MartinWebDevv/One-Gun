extends RefCounted
## Run/dash/jump circuit, sized for the unchanged 10 m/s controller.
const G = preload("res://maps/hideout/geometry.gd")
const COURSE_ID := "flow_circuit_v2"
const COURSE_GATES := [Vector3(-12.5,0,-42.25),Vector3(-40,0,-42.25),Vector3(-60,0,-42.25),Vector3(-82,0,-57),Vector3(-62,0,-70.75),Vector3(-37,0,-70.75),Vector3(-8.5,0,-70.75)]
const RECOVERY := [Vector3(-16,-0.11,-42.25),Vector3(-41,-0.11,-42.25),Vector3(-62,-0.11,-42.25),Vector3(-82,-0.11,-60),Vector3(-60,-0.11,-70.75),Vector3(-36,-0.11,-70.75),Vector3(-8.5,-0.11,-70.75)]

static func contains(at: Vector3) -> bool:
	return at.x < -10.3 and at.x > -91.7 and at.z < -35.3 and at.z > -78.7

static func build(station: Node3D, kit: RefCounted) -> void:
	var root := Node3D.new()
	root.name="AgilityArchitecture"
	station.root_geo.add_child(root)
	G.box(root,"CourseCatchFloor",Vector3(-51,-4.8,-57),Vector3(82,0.5,44),kit.ink,true)
	G.box(root,"CourseRoof",Vector3(-51,7.4,-57),Vector3(82,0.4,44),kit.ink,true)
	for z in [-35.0,-79.0]: _wall(root,"CourseEndWall",Vector3(-51,3,z),Vector3(82,8.4,0.6),kit.cream)
	_wall(root,"CourseBackWall",Vector3(-92,3,-57),Vector3(0.6,8.4,44),kit.cream)
	_wall(root,"CourseRouteDivider",Vector3(-41,3,-57),Vector3(54,8.4,10),kit.painted)
	# A round inner apex gives a generous, continuous 180-degree turn.
	var nose := G.cylinder(root,"RoundedTurnApex",Vector3(-68,3,-57),5,8.4,kit.painted)
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius=5
	cylinder.height=8.4
	collider.shape=cylinder
	nose.add_child(body)
	body.add_child(collider)
	_floor(root,"LaunchRun",Vector2(-46,-52),Vector2(36,17),kit.stone)
	_floor(root,"WideLanding",Vector2(-70,-52),Vector2(16,17),kit.stone)
	_floor(root,"SweepingTurn",Vector2(-92,-79),Vector2(22,44),kit.stone)
	_floor(root,"ReturnRun",Vector2(-70,-79),Vector2(60,17),kit.stone)
	# One deliberate vault, then an 8 m gap with a full 16 m landing.
	G.box(root,"VaultDeck",Vector3(-33,-0.75,-43.5),Vector3(4,0.9,16.2),kit.painted,true)
	for x in [-31.0,-35.0]: G.box(root,"VaultEdge",Vector3(x,-0.28,-43.5),Vector3(0.08,0.04,16.2),kit.brass)
	for x in [-46.0,-54.0]: G.box(root,"GapEdge",Vector3(x,-1.16,-43.5),Vector3(0.16,0.03,16.6),kit.brass)
	# Low cover creates broad racing lines; jumping the apex is a legitimate option.
	for at in [Vector3(-54,-0.6,-64.7),Vector3(-44,-0.6,-76.3)]:
		G.box(root,"CornerCutCover",at,Vector3(4,1.2,5.2),kit.painted,true)
		G.box(root,"CoverEdge",at+Vector3(0,0.63,0),Vector3(4.1,0.04,5.3),kit.brass)
	# Knee-height transitions use One Gun's existing 0.55 m step-up behavior.
	for data in [[-32.5,0.4],[-29.5,0.8],[-26.5,0.4]]:
		G.box(root,"FlowStep",Vector3(data[0],-1.2+data[1]/2,-70.5),Vector3(3,data[1],16.4),kit.painted,true)
		G.box(root,"FlowStepEdge",Vector3(data[0]-1.47,-1.18+data[1],-70.5),Vector3(0.06,0.03,16.4),kit.brass)
	# A continuous visible racing line, with room to choose tighter or safer lines.
	for x in [-18,-24,-40,-58,-64]: _arrow(root,Vector3(x,-1.14,-42.25),PI/2,kit)
	for i in range(9):
		var angle := -PI/2-i*PI/8
		var at := Vector3(-68+cos(angle)*14,-1.14,-57+sin(angle)*14)
		_arrow(root,at,-angle,kit)
	for x in [-64,-58,-48,-38,-22,-16]: _arrow(root,Vector3(x,-1.14,-70.75),-PI/2,kit)
	for location in [Vector3(-23,6.3,-43),Vector3(-44,6.3,-43),Vector3(-64,6.3,-43),Vector3(-84,6.3,-57),Vector3(-64,6.3,-71),Vector3(-43,6.3,-71),Vector3(-22,6.3,-71)]:
		G.lamp(station,location,Color("ffe0b2"),1.4,19)
		G.box(root,"CoursePractical",location+Vector3(0,0.55,0),Vector3(3.4,0.1,0.4),kit.lamp_mat)
	_door(root,"AGILITY / START",-42.25,G.GREEN,kit)
	_door(root,"AGILITY / FINISH",-70.75,G.ORANGE,kit)
	var rules := G.label(root,"CourseRules","RUN / JUMP / DASH",Vector3(-9.55,4.2,-42.25),40,G.PAPER,0.009)
	rules.rotation.y=PI/2
	for i in range(COURSE_GATES.size()):
		var at: Vector3=COURSE_GATES[i]
		var area := Area3D.new()
		area.name="AgilityGate%d" % i
		area.collision_layer=0
		area.collision_mask=2
		area.set_meta("course_gate",i)
		station.add_child(area)
		area.position=at+Vector3(0,2,0)
		var shape := BoxShape3D.new()
		shape.size=Vector3(1,8,16.5) if i!=3 else Vector3(20,8,1)
		if i in [0,6]: shape.size.z=6.2
		var gate := CollisionShape3D.new()
		gate.shape=shape
		area.add_child(gate)
		G.box(root,"CheckpointLine",at+Vector3(0,-1.16,0),Vector3(0.12,0.03,14) if i!=3 else Vector3(18,0.03,0.12),kit.brass)
	for data in [[Vector3(-21,-1.14,-42),"01 / LAUNCH"],[Vector3(-41,-1.14,-42),"02 / JUMP + LAND"],[Vector3(-85,-1.14,-56),"03 / SWEEP"],[Vector3(-63,-1.14,-71),"04 / CUT THE CORNERS"],[Vector3(-22,-1.14,-71),"05 / FINISH BURST"]]:
		var label := G.label(root,"CourseStage",data[1],data[0],42,G.INK,0.018)
		label.rotation=Vector3(-PI/2,0,PI/2 if data[0].z>-60 else -PI/2)
		label.visibility_range_end=30
	_board(station,root,kit)

static func _board(station: Node3D, root: Node3D, kit: RefCounted) -> void:
	var board := Node3D.new()
	board.name="CourseRecordBoard"
	root.add_child(board)
	board.position=Vector3(-9.47,2.2,-56.5)
	board.rotation.y=PI/2
	G.box(board,"BoardFrame",Vector3.ZERO,Vector3(16,5.4,0.2),kit.timber)
	G.box(board,"BoardFace",Vector3(0,0,0.13),Vector3(15.6,5,0.1),kit.ink)
	G.label(board,"BoardTitle","AGILITY / LOBBY BEST",Vector3(0,1.96,0.2),92,G.GREEN,0.008)
	G.box(board,"BoardRule",Vector3(0,1.45,0.22),Vector3(14.4,0.05,0.03),kit.brass)
	G.label(board,"CourseBoardLeader","SET THE FIRST TIME",Vector3(0,0.68,0.24),96,G.PAPER,0.009)
	G.label(board,"CourseBoardRows","NO COMPLETED RUNS",Vector3(0,-0.55,0.24),52,G.PAPER,0.008)
	G.label(board,"CourseBoardFooter","INTERACT / LOBBY  |  YOUR BEST  |  WORLD",Vector3(0,-2,0.24),40,G.CYAN,0.008)
	station._zone("course_board",Vector3(-6.8,1,-56.5),Vector3(4.5,4,14))
	var approach := Marker3D.new()
	approach.name="CourseBoardApproach"
	station.add_child(approach)
	approach.position=Vector3(-5,-0.11,-56.5)
	approach.rotation.y=PI/2

static func _floor(root: Node3D, title: String, at: Vector2, size: Vector2, mat: Material) -> void:
	G.box(root,title,Vector3(at.x+size.x/2,-1.45,at.y+size.y/2),Vector3(size.x,0.5,size.y),mat,true)

static func _wall(root: Node3D, title: String, at: Vector3, size: Vector3, mat: Material) -> void:
	G.box(root,title,at,size,mat,true)
	var instance := OccluderInstance3D.new()
	var shape := BoxOccluder3D.new()
	shape.size=size-Vector3.ONE*0.06
	instance.occluder=shape
	root.add_child(instance)
	instance.position=at

static func _door(root: Node3D, title: String, z: float, color: Color, kit: RefCounted) -> void:
	for side in [-1,1]: G.box(root,"DoorJamb",Vector3(-10,2.3,z+side*3.13),Vector3(0.18,7,0.18),kit.brass)
	G.panel(root,title.to_pascal_case(),title,Vector3(-9.55,5.3,z),Vector2(6.2,0.8),color).rotation.y=PI/2

static func _arrow(root: Node3D, at: Vector3, yaw: float, kit: RefCounted) -> void:
	var arrow := Node3D.new()
	root.add_child(arrow)
	arrow.position=at
	arrow.rotation.y=yaw
	for side in [-1,1]:
		var stroke := G.box(arrow,"RacingChevron",Vector3(side*0.38,0,0.38),Vector3(0.12,0.03,1.1),kit.brass)
		stroke.rotation.y=side*-PI/4
