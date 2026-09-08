extends RefCounted
const G = preload("res://tools/live_lobby_preview/geometry.gd")

static func build(station: Node3D) -> void:
	var kit := preload("res://tools/live_lobby_preview/arcade.gd").new()
	var root := Node3D.new()
	root.name = "EventsAndParty"
	station.root_geo.add_child(root)
	root.position = Vector3(-4,0,-29.45)
	G.box(root,"DispatchBacking",Vector3(0,2.7,0),Vector3(26,5.4,0.35),kit.cream,true)
	G.box(root,"DispatchSoffit",Vector3(0,5.25,2),Vector3(26.2,0.25,4.6),kit.ink)
	G.box(root,"DispatchCanopy",Vector3(0,5.6,4.12),Vector3(26.4,0.6,0.28),G.material("hub_coral",Color("e9806b")))
	G.box(root,"DispatchCap",Vector3(0,5.98,2),Vector3(26.6,0.12,4.85),kit.brass)
	for x in [-12.5,-2.6,12.5]:
		G.box(root,"PierCore",Vector3(x,2.6,3.8),Vector3(0.6,5.2,0.7),kit.mortar,true)
		for i in range(15): G.box(root,"PierCourse",Vector3(x,0.3+i*0.33,3.8),Vector3(0.69,0.30,0.8),kit.stone)
	preload("res://tools/live_lobby_preview/service_floor.gd").build(station.root_geo,"DispatchServiceFloor",Vector2i(-19,-30),Vector2i(28,8),kit)
	for definition in [["SQUAD",-8.0,9.3,G.CYAN],["GAME BOARD",5.25,14.5,G.GOLD]]:
		G.panel(root,str(definition[0])+"Sign",definition[0],Vector3(definition[1],5.64,4.29),Vector2(definition[2],0.67),definition[3])
		G.box(root,"WarmServiceLight",Vector3(definition[1],5.06,2.4),Vector3(3.4,0.07,0.32),kit.lamp_mat)
		G.lamp(station,root.to_global(Vector3(definition[1],4.6,2.8)),Color("ffdfb2"),1.6,8)
	# Party's pinboard and seating use the same timber and inset framing as Hub.
	G.box(root,"PartyBoardFrame",Vector3(-8.0,3.2,0.35),Vector3(8.8,2.8,0.3),kit.timber)
	G.box(root,"PartyBoard",Vector3(-8.0,3.2,0.54),Vector3(8.5,2.5,0.1),kit.ink)
	station.party_line = G.label(root,"PartyStatus","STRAY / SOLO",Vector3(-8.0,3.52,0.62),70,G.CYAN,0.008)
	G.label(root,"PartyCaption","GATHER YOUR PEOPLE",Vector3(-8.0,2.66,0.62),45,G.PAPER,0.007)
	_counter(root,Vector3(-8.0,0,2.5),7.0,kit)
	G.panel(root,"PartyControl","SQUAD  [P]",Vector3(-8.0,1.76,2.38),Vector2(2.7,0.55),G.CYAN)
	# The event board is recessed into the service wall rather than a loose kiosk.
	G.box(root,"EventFrame",Vector3(5.25,3.1,0.35),Vector3(12.3,3.55,0.3),kit.timber)
	G.box(root,"EventBoard",Vector3(5.25,3.1,0.54),Vector3(12.0,3.25,0.1),kit.ink)
	G.label(root,"BoardTitle","YOUR HIDEOUT",Vector3(5.25,4.28,0.65),96,G.GOLD,0.008)
	station.event_line = G.label(root,"EventStatus","WELCOME, STRAY",Vector3(5.25,3.35,0.65),78,G.GREEN,0.008)
	G.label(root,"BoardRoute","PLAY HERE   /   FIND A LOBBY",Vector3(5.25,2.55,0.65),42,G.PAPER,0.007)
	G.label(root,"BoardOffline","OFFLINE REHEARSAL",Vector3(5.25,1.95,0.65),32,G.CYAN,0.007)
	_counter(root,Vector3(5.25,0,2.5),9.6,kit)
	G.panel(root,"EventControl","GAME BOARD  [TAB]",Vector3(5.25,1.76,2.38),Vector2(3.2,0.55),G.GOLD)
	for service in [["party",-12.0],["events",1.25]]:
		station._zone(service[0],Vector3(service[1],1,-23.85),Vector3(6,4,4))
		var approach := Marker3D.new()
		approach.name = str(service[0]).to_pascal_case()+"Approach"
		station.add_child(approach)
		approach.position = Vector3(service[1],1.09,-23.85)

static func _counter(root: Node3D, pos: Vector3, width: float, kit: RefCounted) -> void:
	G.box(root,"CounterBase",pos+Vector3(0,0.65,0),Vector3(width,1.3,1.05),kit.painted,true)
	G.box(root,"TimberCounter",pos+Vector3(0,1.37,0),Vector3(width+0.3,0.14,1.45),kit.timber)
	for i in range(int(width)):
		G.box(root,"CounterPanel",pos+Vector3(-width/2+0.5+i,0.65,0.55),Vector3(0.06,1.05,0.045),kit.brass)
