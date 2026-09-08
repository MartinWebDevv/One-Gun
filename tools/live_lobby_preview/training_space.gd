extends RefCounted
const G = preload("res://tools/live_lobby_preview/geometry.gd")
const DISTANCES := [5,10,15,25,30,40,50,75,90,100]
const LANE_Z := [-43.0,-55.0,-67.0]
const FIRING_X := 54.0
const FLOOR_Y := -1.2
const Course = preload("res://tools/live_lobby_preview/agility_space.gd")
const COURSE_GATES = Course.COURSE_GATES
const RECOVERY = Course.RECOVERY

static func in_course(at: Vector3) -> bool:
	return Course.contains(at)

static func build(station: Node3D) -> void:
	var kit := preload("res://tools/live_lobby_preview/arcade.gd").new()
	_range(station,kit)
	Course.build(station,kit)

static func _wall(root: Node3D, title: String, at: Vector3, size: Vector3, material: Material) -> void:
	G.box(root,title,at,size,material,true)
	var occluder := OccluderInstance3D.new()
	var box := BoxOccluder3D.new()
	box.size=size-Vector3.ONE*0.06
	occluder.occluder=box
	root.add_child(occluder)
	occluder.position=at

static func _range(station: Node3D, kit: RefCounted) -> void:
	var root := Node3D.new()
	root.name="RangeArchitecture"
	station.root_geo.add_child(root)
	G.box(root,"RangeFloor",Vector3(102,-1.45,-55),Vector3(116,0.5,38),kit.stone,true)
	G.box(root,"RangeRoof",Vector3(102,7.4,-55),Vector3(116,0.4,38),kit.ink,true)
	for z in [-36.0,-74.0]: _wall(root,"RangeOuterWall",Vector3(102,3,z),Vector3(116,8.4,0.6),kit.cream)
	_wall(root,"RangeBackstop",Vector3(160,3,-55),Vector3(0.6,8.4,38),kit.painted)
	# Lane partitions begin at the firing line, leaving a shared rear walkway.
	for z in [-49.0,-61.0]:
		_wall(root,"LanePartition",Vector3(107,1.3,z),Vector3(106,5,0.2),kit.painted)
		G.box(root,"LanePartitionCap",Vector3(107,3.85,z),Vector3(106,0.1,0.28),kit.brass)
	for x in [56.0,76.0,96.0,116.0,136.0,156.0]:
		G.box(root,"RangeCeilingRib",Vector3(x,7.02,-55),Vector3(0.22,0.25,38),kit.brass)
		for z in LANE_Z: G.box(root,"RangePractical",Vector3(x,6.84,z),Vector3(3,0.1,0.4),kit.lamp_mat)
		G.lamp(station,Vector3(x,6.2,-55),Color("ffe0b2"),1.4,26)
	for lane in range(3):
		var z: float=LANE_Z[lane]
		G.box(root,"FiringLine",Vector3(FIRING_X,-1.17,z),Vector3(0.2,0.03,11.7),kit.brass)
		G.box(root,"TargetRail",Vector3(107,-1.17,z),Vector3(106,0.03,0.08),kit.brass)
		for distance in DISTANCES:
			G.box(root,"RangeDistanceTick",Vector3(FIRING_X+distance,-1.17,z),Vector3(0.08,0.03,11.6),kit.mortar)
			var tick := G.label(root,"DistanceStencil",str(distance)+" m",Vector3(FIRING_X+distance,-1.14,z+4.4),38,G.INK,0.018)
			tick.rotation=Vector3(-PI/2,0,-PI/2)
			tick.visibility_range_end=24.0
		G.box(root,"RangeControlPlinth",Vector3(48.2,-0.55,z+3.8),Vector3(0.6,1.3,1.2),kit.painted,true)
		var control := G.panel(root,"RangeConsole%d" % lane,"LANE %d" % (lane+1),Vector3(47.8,1.15,z+3.8),Vector2(3.2,0.8),G.CYAN)
		control.rotation.y=-PI/2
		var status := G.label(root,"RangeStatus%d" % lane,"5 m / 0 HITS",Vector3(47.75,0.4,z+3.8),42,G.PAPER,0.009)
		status.rotation.y=-PI/2
		var hint := G.label(root,"RangeNext","INTERACT / NEXT DISTANCE",Vector3(47.75,-0.1,z+3.8),28,G.CYAN,0.007)
		hint.rotation.y=-PI/2
		station._zone("range_%d" % lane,Vector3(46.3,0,z+3.8),Vector3(3,4,3.2))
		var marker := Marker3D.new()
		marker.name="RangeFiringPosition%d" % lane
		station.add_child(marker)
		marker.position=Vector3(FIRING_X,-0.11,z)
		marker.rotation.y=-PI/2
	_door(root,"FIRING RANGE",44,-55,8,G.CYAN,kit,-PI/2)
	var direction := G.label(root,"RangeGuide","3 LANES  /  5 TO 100 METRES",Vector3(43.56,4.2,-55),42,G.PAPER,0.009)
	direction.rotation.y=-PI/2

static func _door(root: Node3D, title: String, x: float, z: float, width: float, color: Color, kit: RefCounted, yaw: float) -> void:
	for side in [-1,1]: G.box(root,"DoorJamb",Vector3(x,2.3,z+side*(width/2-0.12)),Vector3(0.18,7,0.18),kit.brass)
	var sign := G.panel(root,title.to_pascal_case(),title,Vector3(x+(-0.45 if x>0 else 0.45),5.3,z),Vector2(width-0.3,0.8),color)
	sign.rotation.y=yaw
