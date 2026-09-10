extends RefCounted
const G = preload("res://maps/hideout/geometry.gd")
const PenSpace = preload("res://maps/hideout/playpen_space.gd")
const CENTER := Vector3(17,-1.2,-110)
const RADIUS := 15.0
const ROOM_SIZE := Vector2(54,50)
const WALL_HEIGHT := 11.2
const ROOM_FRONT_Z := -85.0
const ROOM_BACK_Z := -135.0
const STOCK_HOME := Vector3(17,-0.8,-97)
const MELEE_SPAWN := Vector3(17,-0.8,-122)
const ITEM_SPAWN := Vector3(9,-0.7,-104)
const POWER_SPAWN := Vector3(25,-0.7,-116)
const FOYER := Vector3(17,-0.11,-84)
const TERMINAL := Vector3(17,-1.2,-91.5)
const TERMINAL_USE := Vector3(17,-0.11,-89.8)
const STARTS := [Vector3(6,-0.11,-110),Vector3(28,-0.11,-110)]

static func at_terminal(p: Vector3) -> bool:
	return p.is_finite() and absf(p.x-TERMINAL_USE.x)<=2.5 and absf(p.z-TERMINAL_USE.z)<=2.0 and absf(p.y-TERMINAL_USE.y)<=2.0

static func in_room(p: Vector3) -> bool:
	return PenSpace.contains_scrap(p)

static func in_ring(p: Vector3) -> bool:
	return p.is_finite() and Vector2(p.x-CENTER.x,p.z-CENTER.z).length()<RADIUS and p.y> -5 and p.y<10.0

static func build(station: Node3D) -> void:
	var kit=preload("res://maps/hideout/arcade.gd").new()
	var root:=Node3D.new()
	root.name="ScrapArchitecture"
	station.root_geo.add_child(root)
	var coral:=G.material("scrap_coral",Color("f3aa7c"))
	var violet:=G.material("scrap_seats",Color("705b87"))
	var floor_mat:=G.material("scrap_floor",Color("e4d5c4"))
	G.box(root,"ScrapFoundation",Vector3(CENTER.x,-1.55,CENTER.z),Vector3(ROOM_SIZE.x,0.7,ROOM_SIZE.y),floor_mat,true)
	G.box(root,"ScrapFoyerFloor",Vector3(17,-1.55,-82),Vector3(8,0.7,6),floor_mat,true)
	for x in [13.0,21.0]: PenSpace.wall(root,"FoyerWall",Vector3(x,2.7,-82),Vector3(0.35,7.8,6),kit.painted)
	for x in [-10.0,44.0]: PenSpace.wall(root,"ScrapSideWall",Vector3(x,4.4,CENTER.z),Vector3(0.5,WALL_HEIGHT,ROOM_SIZE.y),kit.painted)
	PenSpace.wall(root,"ScrapBackWall",Vector3(CENTER.x,4.4,ROOM_BACK_Z),Vector3(ROOM_SIZE.x,WALL_HEIGHT,0.5),kit.painted)
	for x in [1.5,32.5]: PenSpace.wall(root,"ScrapFrontWall",Vector3(x,4.4,ROOM_FRONT_Z),Vector3(23,WALL_HEIGHT,0.5),kit.cream)
	PenSpace.wall(root,"ScrapFrontLintel",Vector3(17,8.3,ROOM_FRONT_Z),Vector3(8,3.4,0.5),kit.cream)
	G.box(root,"ScrapRoof",Vector3(CENTER.x,10.15,CENTER.z),Vector3(ROOM_SIZE.x,0.3,ROOM_SIZE.y),kit.cream,true)
	G.box(root,"ScrapFoyerRoof",Vector3(17,6.75,-82),Vector3(8,0.3,6),kit.cream,true)
	G.panel(root,"ScrapEntrance","THE SCRAP YARD",Vector3(17,4.7,-78.55),Vector2(14.4,1.1),G.ORANGE)
	G.label(root,"ScrapEntranceInfo","QUICK 1V1 / JOIN OR WATCH",Vector3(17,3.6,-78.5),58,G.PAPER,0.008)
	# Freestanding terminal faces arrivals, clear of both routes to the stands.
	var terminal := Node3D.new()
	terminal.name = "ScrapJoinTerminal"
	root.add_child(terminal)
	terminal.position = TERMINAL
	G.box(terminal,"Base",Vector3(0,0.1,0),Vector3(1.8,0.2,1.1),kit.brass,true)
	G.box(terminal,"Pedestal",Vector3(0,0.85,0),Vector3(0.5,1.5,0.2),kit.painted,true)
	G.box(terminal,"ScreenCase",Vector3(0,1.85,0),Vector3(2.8,1.5,0.3),coral,true)
	G.box(terminal,"Screen",Vector3(0,1.85,0.17),Vector3(2.55,1.25,0.05),G.material("scrap_terminal_screen",Color("352c49")))
	G.label(terminal,"JoinTitle","JOIN THE SCRAP",Vector3(0,2.04,0.21),42,G.GOLD,0.006)
	G.label(terminal,"JoinDetail","1V1 / ONE ROUND",Vector3(0,1.68,0.21),28,G.PAPER,0.006)
	G.label(root,"ScrapFoyerRoute","STANDS  <    >  STANDS",Vector3(17,4.3,-85.45),48,G.CYAN,0.007)
	station._zone("scrap",TERMINAL_USE,Vector3(5,4,4))
	G.panel(root,"ScrapScoreboard","THE SCRAP YARD",Vector3(17,6.8,ROOM_BACK_Z+0.5),Vector2(23,1.5),G.GOLD)
	G.label(root,"ScrapStatus","ONE ROUND / COIN FLIP START",Vector3(17,5.2,ROOM_BACK_Z+0.55),72,G.PAPER,0.013)
	var wins_board:=Node3D.new()
	wins_board.name="ScrapWinsBoard"
	root.add_child(wins_board)
	wins_board.position=Vector3(1.5,3.5,ROOM_FRONT_Z-0.35)
	wins_board.rotation.y=PI
	G.box(wins_board,"Frame",Vector3.ZERO,Vector3(17,6.3,0.18),kit.timber)
	G.box(wins_board,"Face",Vector3(0,0,0.12),Vector3(16.6,5.9,0.08),kit.ink)
	G.label(wins_board,"Title","SCRAP YARD / LOBBY WINS",Vector3(0,2.48,0.19),76,G.GOLD,0.008)
	G.label(wins_board,"ScrapWinsRows","FIRST WIN TAKES THE LEAD",Vector3(0,1.75,0.2),44,G.PAPER,0.007).vertical_alignment=VERTICAL_ALIGNMENT_TOP
	G.label(wins_board,"Footer","THIS HIDEOUT / RESETS IN A NEW LOBBY",Vector3(0,-2.65,0.2),36,G.CYAN,0.008)
	G.ring(root,"RingLine",RADIUS-0.45,RADIUS-0.2,-1.17,kit.brass).position=Vector3(CENTER.x,0,CENTER.z)
	G.ring(root,"CoinEmblem",2.3,2.5,-1.17,kit.brass).position=Vector3(CENTER.x,0,CENTER.z)
	var glass:=G.material("scrap_clear_guard",Color(0.36,0.78,0.8,0.10))
	glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode=BaseMaterial3D.CULL_DISABLED
	var segment_length: float=2.0*(RADIUS+0.3)*tan(PI/48.0)
	for i in range(48):
		var angle: float=(i+0.5)*TAU/48.0
		var wall:=Node3D.new()
		root.add_child(wall)
		wall.position=CENTER+Vector3(sin(angle)*(RADIUS+0.3),0,cos(angle)*(RADIUS+0.3))
		wall.rotation.y=angle
		G.box(wall,"RingBoundary",Vector3(0,0.48,0),Vector3(segment_length+0.04,0.96,0.28),kit.cream,true)
		G.box(wall,"WatchRail",Vector3(0,1.55,0),Vector3(segment_length+0.06,0.1,0.13),kit.brass)
		G.box(wall,"ClearGuard",Vector3(0,1.0,0),Vector3(segment_length,1.0,0.07),glass)
		# Continuous full-height collision also blocks jumping/throwing over the spectator rail.
		var guard:=StaticBody3D.new()
		guard.name="ScrapSpectatorBarrier"
		guard.collision_layer=1 | PenSpace.BARRIER_LAYER
		guard.collision_mask=0
		wall.add_child(guard)
		var shape:=CollisionShape3D.new()
		var bounds:=BoxShape3D.new()
		bounds.size=Vector3(segment_length+0.08,WALL_HEIGHT,0.2)
		shape.shape=bounds
		shape.position.y=WALL_HEIGHT*0.5
		guard.add_child(shape)
	for side in [-1,1]:
		for row in range(3):
			var x: float=CENTER.x+side*(18.5+row*2.4)
			var y: float=-1.2+row*0.4
			G.box(root,"StandTier",Vector3(x,y-0.2,CENTER.z),Vector3(2.4,0.4,34),floor_mat,true)
			G.box(root,"StandSeat",Vector3(x,y+0.5,CENTER.z),Vector3(0.8,0.2,32),violet,true)
			G.box(root,"StandBack",Vector3(x+side*0.36,y+0.83,CENTER.z),Vector3(0.14,0.65,32),kit.timber,true)
	for data in [[Vector3(17,0,-110),Vector3(1.5,2.4,5.5),0.0],[Vector3(10.5,0,-118),Vector3(5,2.4,0.9),-0.45],[Vector3(23.5,0,-102),Vector3(5,2.4,0.9),-0.45]]:
		var cover:=G.box(root,"DuelCover",data[0],data[1],coral,true)
		cover.rotation.y=data[2]
	for z in [-100.5,-119.5]: G.box(root,"JumpHurdle",Vector3(17,-0.79,z),Vector3(4.5,0.82,0.75),kit.brass,true)
	for at in STARTS:
		G.ring(root,"FighterStart",0.95,1.1,-1.16,coral).position=Vector3(at.x,0,at.z)
	for data in [[Vector3(ITEM_SPAWN.x,-1.16,ITEM_SPAWN.z),"ITEM",G.GOLD],[Vector3(POWER_SPAWN.x,-1.16,POWER_SPAWN.z),"POWER",G.PINK],[Vector3(MELEE_SPAWN.x,-1.16,MELEE_SPAWN.z),"MELEE",G.CYAN]]:
		G.ring(root,"ScrapSpawnMark",0.62,0.75,-1.16,G.material(str(data[2]),data[2])).position=Vector3(data[0].x,0,data[0].z)
		var mark:=G.label(root,"ScrapSpawnLabel",data[1],data[0]+Vector3(0,0.015,1),36,data[2],0.008)
		mark.rotation.x=-PI/2
	for z in [-94.0,-110.0,-126.0]:
		G.box(root,"ScrapLight",Vector3(17,9.7,z),Vector3(10,0.1,0.5),kit.lamp_mat)
		G.lamp(station,Vector3(17,8.9,z),Color("fff1d8"),2.2,23)

static func spectator_position(index: int) -> Vector3:
	return Vector3(-0.7 if index%2==0 else 34.7,-1.2,-100.0-floori(index/2.0)*6.0)
