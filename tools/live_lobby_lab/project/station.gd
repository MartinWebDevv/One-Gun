extends Node3D

const G = preload("res://geometry.gd")
signal station_entered(id: String)
signal station_exited(id: String)
var event_line: Label3D
var party_line: Label3D
var departure_line: Label3D
var doors: Array[Node3D] = []
var departure_door: Node3D
var targets: Array[StaticBody3D] = []
var target_discs: Array[MeshInstance3D] = []
var environment: Environment
var arrival_tween: Tween
var departure_tween: Tween
var concrete: Material
var tile: Material
var steel: Material
var dark: Material
var gold: Material
var warm: Material
var root_geo: Node3D

func _ready() -> void:
	name = "Station"
	concrete = G.textured("concrete", Color("b8b3a1"), 2.0)
	tile = G.textured("tile", Color("cbd1bf"), 2.0)
	steel = G.material("steel", Color("334b4d"), 0, 0.55)
	dark = G.material("dark", Color("192a2d"))
	gold = G.material("paint_gold", G.GOLD)
	warm = G.material("warm_glass", Color("ffd99a"), 1.4)
	root_geo = Node3D.new()
	root_geo.name = "Architecture"
	add_child(root_geo)
	_build_shell()
	_build_pit()
	_build_event_board()
	_build_locker()
	_build_range()
	_build_party()
	_build_arrivals()
	_build_departure()
	_build_outskirts()
	_build_lighting()
	_batch_static_meshes()

func _build_shell() -> void:
	G.box(root_geo, "Foundation", Vector3(0,-0.95,0), Vector3(35,0.7,35), concrete, true)
	G.ring(root_geo, "Concourse", 8.2, 24.0, 0.0, G.textured("floor",Color("c0bda5"),1), true)
	G.box(root_geo, "NorthWall", Vector3(0,4.2,-17), Vector3(34,8.4,0.7), tile, true)
	G.box(root_geo, "WestWall", Vector3(-17,4.2,0), Vector3(0.7,8.4,34), tile, true)
	G.box(root_geo, "EastNorth", Vector3(17,4.2,-10), Vector3(0.7,8.4,14), tile, true)
	G.box(root_geo, "EastSouth", Vector3(17,4.2,10), Vector3(0.7,8.4,14), tile, true)
	G.box(root_geo, "EastLintel", Vector3(17,7,0), Vector3(0.7,2.8,6), concrete, true)
	G.box(root_geo, "SouthWall", Vector3(0,4.2,17), Vector3(34,8.4,0.7), tile, true)
	for x in [-16.45,16.45]:
		if x>0:
			for z in [-10.0,10.0]:
				G.box(root_geo,"WallPlinth",Vector3(x,0.75,z),Vector3(0.2,1.5,14),steel)
				G.box(root_geo,"ServiceStripe",Vector3(x,3.1,z),Vector3(0.07,0.24,14),gold)
		else:
			G.box(root_geo,"WallPlinth",Vector3(x,0.75,0),Vector3(0.2,1.5,34),steel)
			G.box(root_geo,"ServiceStripe",Vector3(x,3.1,0),Vector3(0.07,0.24,34),gold)
	for z in [-16.5,16.5]:
		G.box(root_geo,"WallPlinth",Vector3(0,0.75,z),Vector3(34,1.5,0.2),steel)
		G.box(root_geo,"ServiceStripe",Vector3(0,3.1,z),Vector3(34,0.24,0.07),gold)
	# Repeated structural ribs give a subway silhouette without high-poly assets.
	for z in [-15.5,-8.0,0.0,8.0,15.5]:
		for x in [-15.4,15.4]:
			if x>0 and is_zero_approx(z): continue # Departure opening replaces this pier.
			G.box(root_geo,"ColumnFoot",Vector3(x,0.25,z),Vector3(1.15,0.5,1.15),concrete,true)
			G.box(root_geo,"RivetedColumn",Vector3(x,3.6,z),Vector3(0.55,7.2,0.7),steel,true)
			G.box(root_geo,"ColumnFace",Vector3(x,2.3,z+0.37),Vector3(0.36,1.15,0.035),gold)
		for i in range(16):
			var a := PI * i / 16.0
			var b := PI * (i+1) / 16.0
			G.rod(root_geo,Vector3(cos(a)*15.5,6.3+sin(a)*3.4,z),Vector3(cos(b)*15.5,6.3+sin(b)*3.4,z),0.15,steel)
	for x in [-12.0,-7.0,0.0,7.0,12.0]:
		G.rod(root_geo,Vector3(x,8.2,-17),Vector3(x,8.2,17),0.08,dark)
	# Ceiling is faceted, opaque and shadow-free on Low.
	for i in range(12):
		var x := -16.5+i*3.0
		G.box(root_geo,"VaultPanel",Vector3(x,10.0-absf(x)*0.15,0),Vector3(3.04,0.25,34),concrete)
	for x in [-13.0,13.0]:
		G.rod(root_geo,Vector3(x,6.8,-16),Vector3(x,6.8,16),0.13,G.material("copper",Color("73513d"),0,0.3))
	for z in [-12.0,2.0,12.0]:
		G.box(root_geo,"Drain",Vector3(-12,0.012,z),Vector3(1,0.025,2.5),dark)
		for i in range(8):
			G.box(root_geo,"DrainSlat",Vector3(-12,0.035,z-1.05+i*0.3),Vector3(0.95,0.025,0.06),steel)

func _build_pit() -> void:
	for i in range(3):
		var radius := 5.8 + i*0.8
		var y := -0.4+i*0.2
		G.ring(root_geo,"PitStep",radius,radius+0.8,y,G.material("pit_tread",Color("6e796e")),true)
		G.ring(root_geo,"StepNosing",radius,radius+0.19,y+0.027,gold)
	var seal := G.box(root_geo,"PaintedOneGunSeal",Vector3(0,-0.587,0),Vector3(7.4,0.02,7.4),G.textured("floor_seal",Color.WHITE))
	# A PlaneMesh keeps the seal on top with undistorted UVs.
	var plane := PlaneMesh.new()
	plane.size = Vector2(7.4,7.4)
	seal.mesh = plane
	for side in [-1,1]:
		for i in range(4):
			var angle: float = (0.75+i*0.24)*side
			var pos := Vector3(sin(angle)*8.5,0,cos(angle)*8.5)
			var bench := Node3D.new()
			root_geo.add_child(bench)
			bench.position = pos
			bench.rotation.y = angle
			G.box(bench,"BenchSeat",Vector3(0,0.58,0),Vector3(1.8,0.16,0.65),G.material("seat",Color("7b493a")),true)
			G.box(bench,"BenchBack",Vector3(0,1.0,0.3),Vector3(1.8,0.65,0.1),steel)
			for x in [-0.65,0.65]:
				G.box(bench,"BenchFoot",Vector3(x,0.25,0),Vector3(0.1,0.5,0.5),steel)
	for side in [-1,1]:
		for i in range(7):
			var a: float = side*(1.32+i*0.14)
			var b: float = side*(1.32+(i+1)*0.14)
			var p := Vector3(sin(a)*8.4,1.0,cos(a)*8.4)
			var q := Vector3(sin(b)*8.4,1.0,cos(b)*8.4)
			G.rod(root_geo,p,q,0.055,steel)
			G.rod(root_geo,p-Vector3(0,0.95,0),p,0.04,steel)

func _build_event_board() -> void:
	G.box(root_geo,"BoardSteelFrame",Vector3(0,4.6,-15.95),Vector3(10.8,5.3,0.4),steel,true)
	G.box(root_geo,"BoardScreen",Vector3(0,4.65,-15.68),Vector3(9.9,4.5,0.13),dark)
	G.label(root_geo,"BoardTitle","ONE GUN / UNLISTED",Vector3(0,6.14,-15.57),110,G.GOLD,0.008)
	G.label(root_geo,"BoardSubline","NO NAMES. NO FACES. ONE GUN.",Vector3(0,5.24,-15.57),43,G.PAPER,0.008)
	event_line = G.label(root_geo,"EventStatus","WELCOME, STRAY",Vector3(0,4.3,-15.54),80,G.GREEN,0.008)
	G.label(root_geo,"BoardRoute","01  SELECT EVENT      02  READY      03  DEPART",Vector3(0,3.35,-15.54),39,G.PAPER,0.008)
	G.label(root_geo,"BoardOffline","OFFLINE REHEARSAL / NO LIVE EVENT",Vector3(0,2.81,-15.54),28,G.CYAN,0.008)
	for x in [-5.0,5.0]:
		G.box(root_geo,"Marquee",Vector3(x,4.5,-15.35),Vector3(0.08,4.7,0.07),gold)
	G.box(root_geo,"EventDesk",Vector3(0,0.68,-9.5),Vector3(4.2,1.36,1.5),steel,true)
	G.box(root_geo,"DeskTop",Vector3(0,1.42,-9.5),Vector3(4.4,0.16,1.65),concrete)
	G.panel(root_geo,"EventTerminal","EVENTS  [TAB]",Vector3(0,1.98,-9.8),Vector2(3.5,0.85),G.GOLD)
	G.box(root_geo,"ControlSlab",Vector3(0,1.57,-9.1),Vector3(1.9,0.1,0.6),dark)
	for x in [-0.6,0.0,0.6]:
		G.cylinder(root_geo,"PhysicalButton",Vector3(x,1.65,-9.1),0.12,0.08,gold)
	_zone("events",Vector3(0,1,-7.8),Vector3(6,4,3.5))

func _build_locker() -> void:
	var bay := Node3D.new()
	root_geo.add_child(bay)
	bay.position = Vector3(-10.7,0,-12.0)
	bay.rotation.y = 0.2
	G.box(bay,"LockerRecess",Vector3(0,2.4,-0.5),Vector3(6.7,4.8,1),dark,true)
	G.panel(bay,"LockerSign","LOCKER / [L]",Vector3(0,5.0,0.1),Vector2(6.3,0.9),G.PINK)
	for i in range(5):
		var x := -2.5+i*1.25
		G.box(bay,"LockerDoor",Vector3(x,1.95,0.06),Vector3(1.14,3.75,0.2),steel,true)
		G.box(bay,"DoorNumberPatch",Vector3(x,3.0,0.18),Vector3(0.5,0.48,0.03),dark)
		G.label(bay,"LockerNumber","0%d" % (i+1),Vector3(x,3.0,0.21),44,G.PINK)
		G.box(bay,"Handle",Vector3(x+0.34,1.7,0.22),Vector3(0.08,0.4,0.14),gold)
		for y in [2.37,2.52,2.67]:
			G.box(bay,"Vent",Vector3(x,y,0.18),Vector3(0.7,0.045,0.04),dark)
	G.ring(bay,"TryOnFloor",1.5,1.57,0.024,G.material("pink_paint",G.PINK))
	_zone("locker",Vector3(-10.7,1,-9.8),Vector3(7,4,4))
	G.lamp(self,Vector3(-11,3.6,-9),G.PINK,0.8,6)

func _build_range() -> void:
	G.panel(root_geo,"RangeSign","PRACTICE / 03",Vector3(10.5,5.0,-9.0),Vector2(7,1),G.ORANGE)
	for x in [7.0,14.0]:
		G.box(root_geo,"RangeSideWall",Vector3(x,2.3,-13),Vector3(0.4,4.6,7),concrete,true)
	G.box(root_geo,"Backstop",Vector3(10.5,2.25,-16.5),Vector3(6.8,4.5,0.4),dark,true)
	G.box(root_geo,"FiringLine",Vector3(10.5,0.024,-8.5),Vector3(6.4,0.035,0.12),G.material("orange_paint",G.ORANGE))
	G.label(root_geo,"RangeHint","LIGHT TRAINER / AIM + CLICK",Vector3(10.5,3.97,-9.0),35,G.PAPER)
	for i in range(3):
		var x := 8.4+i*2.1
		G.box(root_geo,"LaneMark",Vector3(x,0.012,-12.2),Vector3(0.04,0.02,6.8),gold)
		var target := StaticBody3D.new()
		target.name = "PracticeTarget%d" % i
		target.collision_layer = 4
		target.collision_mask = 0
		add_child(target)
		target.position = Vector3(x,2.3,-15.7)
		target.set_meta("target_index",i)
		var shape := CollisionShape3D.new()
		var shape_data := BoxShape3D.new()
		shape_data.size = Vector3(1.45,1.45,0.22)
		shape.shape = shape_data
		target.add_child(shape)
		var disc := G.cylinder(target,"Target",Vector3.ZERO,0.72,0.14,G.material("target",G.ORANGE))
		disc.rotation.x = PI/2
		var inner := G.cylinder(target,"TargetRing",Vector3(0,0,0.09),0.49,0.03,dark)
		inner.rotation.x = PI/2
		var bull := G.cylinder(target,"Bullseye",Vector3(0,0,0.12),0.20,0.04,G.material("target_white",G.PAPER))
		bull.rotation.x = PI/2
		G.rod(root_geo,Vector3(x,3.0,-15.7),Vector3(x,4.6,-15.7),0.03,steel)
		targets.append(target)
		target_discs.append(disc)
	_zone("range",Vector3(10.5,1.2,-11.3),Vector3(7.8,5,9.5))
	G.lamp(self,Vector3(10.5,4,-12),Color("ffcf96"),2,9)

func _build_party() -> void:
	var p := Node3D.new()
	root_geo.add_child(p)
	p.position = Vector3(-13,0,0)
	p.rotation.y = PI/2
	G.box(p,"PartyConsole",Vector3(0,1,0),Vector3(4.3,2,0.9),steel,true)
	G.panel(p,"PartySign","YOUR PEOPLE / [P]",Vector3(0,3.8,0),Vector2(5.5,0.9),G.CYAN)
	G.box(p,"PartyMonitor",Vector3(0,2.45,0.05),Vector3(3.9,1.4,0.2),dark)
	party_line = G.label(p,"PartyStatus","STRAY / SOLO",Vector3(0,2.5,0.18),60,G.CYAN,0.006)
	G.label(p,"PartyCaption","ALIASES ONLY. MAKE YOURSELF AT HOME.",Vector3(0,1.25,0.5),24,G.PAPER,0.006)
	_zone("party",Vector3(-10.4,1,0),Vector3(4.5,4,5))
	G.lamp(self,Vector3(-11.7,3.5,0),G.CYAN,0.8,5)
	var map_panel := G.box(root_geo,"OldTransitDiagram",Vector3(-16.57,4,6),Vector3(0.07,2.7,5.4),G.textured("route_map",Color.WHITE))
	map_panel.rotation.y = 0

func _build_arrivals() -> void:
	G.box(root_geo,"ArrivalLanding",Vector3(0,0.45,14.8),Vector3(7,1.5,4.2),concrete,true)
	for i in range(6):
		G.box(root_geo,"ArrivalStair",Vector3(0,(i+1)*0.1,9.85+i*0.52),Vector3(6.6,(i+1)*0.2,0.53),concrete,true)
		G.box(root_geo,"ArrivalStairNose",Vector3(0,(i+1)*0.2+0.016,9.61+i*0.52),Vector3(6.6,0.02,0.06),gold)
	for x in [-5.7,5.7]:
		G.box(root_geo,"ArrivalFrame",Vector3(x,3.6,13.25),Vector3(0.4,5,0.5),steel,true)
	G.box(root_geo,"ArrivalHeader",Vector3(0,6.0,13.25),Vector3(11.8,0.4,0.5),steel,true)
	var entrance_sign := G.panel(root_geo,"ArrivalSign","UNLISTED / ARRIVALS",Vector3(0,6.0,13.0),Vector2(6.3,0.75),G.CYAN)
	entrance_sign.rotation.y = PI
	for i in range(2):
		var door := G.box(self,"ArrivalDoor%d" % i,Vector3(-2.7+i*5.4,3.55,13.25),Vector3(5.35,4.65,0.15),steel,true)
		G.box(door,"DoorGlass",Vector3(0,0.6,-0.11),Vector3(2.3,1.4,0.08),dark)
		G.box(door,"CautionStripe",Vector3(0,-0.45,-0.10),Vector3(5.3,0.22,0.05),gold)
		doors.append(door)

func open_arrivals() -> void:
	if arrival_tween and arrival_tween.is_running():
		arrival_tween.kill()
	arrival_tween = create_tween().set_parallel(true)
	for i in range(doors.size()):
		arrival_tween.tween_property(doors[i],"position:x",-8.5 if i==0 else 8.5,0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _build_departure() -> void:
	var bay := Node3D.new()
	root_geo.add_child(bay)
	bay.position = Vector3(16.5,0,0)
	bay.rotation.y = -PI/2
	G.box(bay,"DepartureFloor",Vector3(0,-0.25,-2),Vector3(6,0.5,5),concrete,true)
	G.box(bay,"DepartureEnd",Vector3(0,2.7,-4),Vector3(6,5.4,0.5),dark,true)
	for x in [-3.0,3.0]:
		G.box(bay,"TunnelJamb",Vector3(x,2.7,-2),Vector3(0.4,5.4,5),steel,true)
	G.box(bay,"TunnelRoof",Vector3(0,5.5,-2),Vector3(6,0.4,5),steel,true)
	G.panel(bay,"DepartureSign","DEPARTURES / 01",Vector3(0,5.8,0.85),Vector2(6.8,0.8),G.GOLD)
	departure_line = G.label(bay,"DepartureStatus","AWAITING AN EVENT",Vector3(0,4.9,0.9),40,G.PAPER)
	departure_door = G.box(self,"DepartureShutter",Vector3(16.15,2.1,0),Vector3(0.18,4.2,5.7),steel,true)
	for y in range(13):
		G.box(departure_door,"ShutterRib",Vector3(-0.11,-1.9+y*0.3,0),Vector3(0.06,0.065,5.7),dark)
	G.box(root_geo,"DepartureFloorLine",Vector3(13.7,0.025,0),Vector3(3.7,0.03,0.12),gold)
	_zone("departure",Vector3(13.2,1,0),Vector3(4,4,6))

func set_departure(active: bool, destination: String) -> void:
	departure_line.text = destination.to_upper() if active else "AWAITING AN EVENT"
	departure_line.modulate = G.GREEN if active else G.PAPER
	if departure_tween and departure_tween.is_running():
		departure_tween.kill()
	departure_tween = create_tween()
	departure_tween.tween_property(departure_door,"position:y",6.4 if active else 2.1,0.8)

func _build_outskirts() -> void:
	# Parkour corner is optional and can be reached directly from the concourse.
	G.panel(root_geo,"MovementSign","MOVE / JUMP / DASH",Vector3(11.4,4.2,15.8),Vector2(7,0.9),G.ORANGE).rotation.y = PI
	for i in range(5):
		var pos := Vector3(8.7+(i%2)*3.2,0.25+i*0.18,6.5+i*1.8)
		G.box(root_geo,"MovementBlock",pos,Vector3(2.0,0.5+i*0.36,1.2),concrete,true)
		G.box(root_geo,"MovementPaint",pos+Vector3(0,0.26+i*0.18,0),Vector3(1.95,0.035,1.1),gold)
	_zone("course",Vector3(10.5,1.5,10.2),Vector3(8,5,9))
	G.panel(root_geo,"ExpansionSign","LINE 02 / SEALED",Vector3(-11.5,4.6,16.48),Vector2(7,0.9),G.PAPER).rotation.y = PI
	G.box(root_geo,"SealedTunnel",Vector3(-11.5,2.1,16.5),Vector3(5.8,4.2,0.2),dark,true)
	var posters := G.box(root_geo,"CompetitorPosters",Vector3(-16.56,3.0,-7),Vector3(0.06,3.8,3.8),G.textured("posters",Color.WHITE))
	posters.rotation.y = 0
	var notice := G.panel(root_geo,"Graffiti","THE CITY ABOVE\nDOESN'T KNOW.",Vector3(-8.7,2.9,-16.54),Vector2(5,1.4),G.PINK)
	notice.rotation.z = -0.045
	G.label(root_geo,"AliasTag","STRAY / ECHO / STATIC / MOTH",Vector3(9.7,0.9,-16.23),32,G.PINK)
	for x in [-14.5,-7.5]:
		G.box(root_geo,"ShippingCrate",Vector3(x,0.4,12),Vector3(1.6,0.8,1.2),steel,true)
		G.box(root_geo,"PatchedCrateBand",Vector3(x,0.4,12.62),Vector3(1.6,0.11,0.03),gold)
	G.panel(root_geo,"JukeboxSign","RADIO / OFF AIR",Vector3(-14,2.2,10),Vector2(2.9,0.65),G.CYAN)
	G.box(root_geo,"RadioCabinet",Vector3(-14,0.9,10),Vector3(1.7,1.8,0.8),steel,true)
	for y in [0.55,1.3]:
		var speaker := G.cylinder(root_geo,"Speaker",Vector3(-14,y,10.43),0.29,0.08,dark)
		speaker.rotation.x = PI/2

func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	environment = Environment.new()
	we.environment = environment
	add_child(we)
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("1c2729")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b1bdb0")
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	environment.ssao_enabled = true
	for pos in [Vector3(-7,6.3,-6),Vector3(7,6.3,-6),Vector3(-7,6.3,7),Vector3(7,6.3,7),Vector3(0,6.8,-13)]:
		G.box(root_geo,"PracticalHousing",pos,Vector3(2.4,0.2,0.7),steel)
		G.box(root_geo,"WarmPractical",pos-Vector3(0,0.12,0),Vector3(2.15,0.08,0.5),warm)
		G.lamp(self,pos-Vector3(0,0.35,0),Color("ffdab0"),2.0,13)
	var key := DirectionalLight3D.new()
	add_child(key)
	key.rotation_degrees = Vector3(-65,-25,0)
	key.light_color = Color("efd5ad")
	key.light_energy = 0.6
	key.shadow_enabled = false

func _zone(id: String, pos: Vector3, size: Vector3) -> void:
	var area := Area3D.new()
	area.name = id.capitalize()+"Interaction"
	area.collision_layer = 0
	area.collision_mask = 2
	add_child(area)
	area.position = pos
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	area.add_child(shape)
	area.body_entered.connect(func(_body): station_entered.emit(id))
	area.body_exited.connect(func(_body): station_exited.emit(id))

func _batch_static_meshes() -> void:
	# One surface per material per quadrant, simple colliders retained separately.
	# Animated doors, targets and text live outside this static visual batch.
	var batches: Dictionary = {}
	var meshes := root_geo.find_children("*","MeshInstance3D",true,false)
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		var mat: Material = mesh_node.material_override
		var p: Vector3 = mesh_node.global_position
		var key := str(mat.get_instance_id())+"/"+str(p.x>0)+"/"+str(p.z>0)
		if not batches.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[key] = [st,mat]
		var surface: SurfaceTool = batches[key][0]
		surface.append_from(mesh_node.mesh,0,mesh_node.global_transform)
		mesh_node.mesh = null
	for key in batches:
		var mesh_node := MeshInstance3D.new()
		mesh_node.name = "StaticBatch"
		var surface: SurfaceTool = batches[key][0]
		mesh_node.mesh = surface.commit()
		mesh_node.material_override = batches[key][1]
		add_child(mesh_node)
