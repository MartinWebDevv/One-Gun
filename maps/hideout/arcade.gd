extends RefCounted
## Authoring-only service arcade. Baked into station.tscn; no runtime rebuild.
const G = preload("res://maps/hideout/geometry.gd")
const SERVICES = ["locker", "prize_counter", "profile", "progression"]
const CENTERS = [-21.9, -7.3, 7.3, 21.9]
var station: Node3D
var arcade: Node3D
var ink := G.material("arcade_ink", Color("245e63"), 0, 0.3)
var painted := G.material("arcade_green", Color("36a7a5"), 0, 0.2)
var mortar := G.material("arcade_mortar", Color("adad98"))
var stone := G.material("arcade_stone", Color("cce2d5"))
var cream := G.material("arcade_cream", Color("f0dec0"))
var brass := G.material("arcade_brass", Color("efbf65"), 0, 0.55)
var timber := G.material("arcade_timber", Color("a26f4b"))
var timber_light := G.material("arcade_timber_light", Color("be9164"))
var lamp_mat := G.material("arcade_lamp", Color("ffe2af"), 1.1)

func build(target: Node3D) -> void:
	station = target
	arcade = Node3D.new()
	arcade.name = "PlayerHubArcade"
	station.root_geo.add_child(arcade)
	arcade.position = Vector3(-26.4, 0, 0)
	arcade.rotation.y = PI/2
	# Local +Z faces the room; +X follows the west wall towards Events.
	G.box(arcade,"ServiceBacking",Vector3(0,2.4,-0.12),Vector3(59.3,4.8,0.28),ink,true)
	G.box(arcade,"ArcadeSoffit",Vector3(0,4.97,1.72),Vector3(59.3,0.24,3.9),ink)
	G.box(arcade,"CanopyFascia",Vector3(0,5.26,3.65),Vector3(59.4,0.64,0.25),G.material("hub_coral",Color("e9806b")))
	G.box(arcade,"CanopyCap",Vector3(0,5.64,1.75),Vector3(59.5,0.15,4.18),brass)
	G.box(arcade,"CanopyLip",Vector3(0,4.96,3.86),Vector3(59.4,0.09,0.08),brass)
	for x in [-29.4,-14.6,0.0,14.6,29.4]:
		G.box(arcade,"BayPartition",Vector3(x,2.0,1.45),Vector3(0.22,4,2.9),painted,true)
		G.box(arcade,"ArcadePier",Vector3(x,2.4,3.25),Vector3(0.55,4.8,0.65),mortar,true)
		G.box(arcade,"PierFoot",Vector3(x,0.24,3.25),Vector3(0.78,0.48,0.86),ink)
		for course in range(13):
			G.box(arcade,"PierCourse",Vector3(x,0.65+course*0.315,3.25),Vector3(0.63,0.285,0.73),stone if course%3 else cream)
		G.box(arcade,"PierCapital",Vector3(x,4.78,3.25),Vector3(0.93,0.22,0.97),stone)
	G.panel(arcade,"PlayerHubSign","PLAYER HUB",Vector3(0,7.45,6.8),Vector2(16,1.55),G.PINK).get_node("Title").font_size = 140
	for x in [-7.1,7.1]:
		G.rod(arcade,Vector3(x,8.2,6.8),Vector3(x,10.35,6.8),0.055,brass)
		G.box(arcade,"CeilingAnchor",Vector3(x,10.39,6.8),Vector3(0.65,0.14,0.65),ink)
	G.label(arcade,"AppearanceGroup","01   /   APPEARANCE",Vector3(-14,5.29,3.8),58,G.PAPER,0.0075)
	G.label(arcade,"CareerGroup","02   /   CAREER",Vector3(14,5.29,3.8),58,G.PAPER,0.0075)
	# Wall-to-wall apron; same world-aligned metre grid as Party/Events.
	preload("res://maps/hideout/service_floor.gd").build(station.root_geo,"HubServiceFloor",Vector2i(-27,-30),Vector2i(8,60),self)
	G.box(arcade,"ApronBorder",Vector3(0,0.032,7.03),Vector3(59.4,0.018,0.09),brass)
	for i in range(4):
		var bay := Node3D.new()
		bay.name = SERVICES[i].to_pascal_case()+"Bay"
		arcade.add_child(bay)
		bay.position.x = CENTERS[i]
		_build_bay(bay,i)
		var approach := Marker3D.new()
		approach.name = SERVICES[i].to_pascal_case()+"Approach"
		station.add_child(approach)
		approach.position = arcade.to_global(Vector3(CENTERS[i],1.09,4.55))
		approach.rotation.y = PI/2
		station._zone(SERVICES[i],arcade.to_global(Vector3(CENTERS[i],1,3.95)),Vector3(3.4,4,4.8))
		G.lamp(station,arcade.to_global(Vector3(CENTERS[i],4.3,2.5)),Color("ffdfb2"),1.65,6.4)
	# Placed at the south end, visible when arriving; not another interaction station.
	var endcap := Node3D.new()
	arcade.add_child(endcap)
	endcap.position = Vector3(-29.3,2.4,1.5)
	endcap.rotation.y = -PI/2
	G.panel(endcap,"ArcadeEndDirectory","PLAYER HUB",Vector3.ZERO,Vector2(2.4,0.55),G.PINK)
	G.label(endcap,"DirectoryServices","LOCKER  /  PRIZES\nPROFILE  /  PROGRESSION",Vector3(0,-0.62,0.09),30,G.PAPER,0.006)

func _build_bay(bay: Node3D, index: int) -> void:
	var titles := ["LOCKER", "PRIZE COUNTER", "PROFILE", "PROGRESSION"]
	G.box(bay,"RecessTiles",Vector3(0,2.35,0.075),Vector3(13.3,4.5,0.13),cream)
	# Regular seams make the material scale readable from the gameplay camera.
	for row in range(9): G.box(bay,"TileJoint",Vector3(0,0.35+row*0.45,0.15),Vector3(13.3,0.018,0.012),mortar)
	for col in range(19): G.box(bay,"TileJoint",Vector3(-6.075+col*0.675,2.3,0.15),Vector3(0.015,4.3,0.012),mortar)
	G.box(bay,"LowerWainscot",Vector3(0,0.67,0.18),Vector3(13.3,1.25,0.16),painted)
	G.box(bay,"DadoRail",Vector3(0,1.34,0.28),Vector3(13.3,0.075,0.08),brass)
	G.box(bay,"BayHeader",Vector3(0,4.35,3.3),Vector3(12.8,0.72,0.13),ink)
	G.label(bay,"ServiceName",titles[index],Vector3(0,4.36,3.38),105,G.PAPER,0.0075)
	G.box(bay,"CeilingLight",Vector3(0,4.78,2.0),Vector3(2.6,0.08,0.32),lamp_mat)
	var status := G.label(bay,SERVICES[index].to_pascal_case()+"Status","",Vector3(0,3.78,3.39),36,G.PINK,0.007)
	status.set_meta("service_id",SERVICES[index])
	G.box(bay,"ServiceThreshold",Vector3(0,0.035,3.6),Vector3(4.8,0.02,0.055),brass)
	# Furnished wings fill the frontage without stretching character-scale props.
	for side in [-1.0,1.0]:
		var wing := Vector3(side*4.8,0,0.8)
		if index == 0:
			_bench(bay,wing+Vector3(0,0,0.5),2.6)
			G.box(bay,"WardrobeWing",wing+Vector3(0,2.7,-0.45),Vector3(2.5,1.6,0.4),painted)
			for hook in [-0.8,0.0,0.8]: G.rod(bay,wing+Vector3(hook,2.7,-0.18),wing+Vector3(hook,2.7,0.12),0.025,brass)
		elif index == 1:
			G.box(bay,"DisplaySideboard",wing+Vector3(0,0.68,0),Vector3(2.7,1.36,1.1),painted,true)
			G.box(bay,"SideboardTop",wing+Vector3(0,1.42,0),Vector3(2.9,0.14,1.3),timber)
			for parcel in [-0.65,0.65]: G.box(bay,"WrappedPrize",wing+Vector3(parcel,1.78,-0.1),Vector3(0.8,0.55,0.65),cream)
		else:
			_bench(bay,wing+Vector3(0,0,0.5),2.6)
			G.panel(bay,"CareerWing","YOUR RECORD" if index==2 else "KEEP GOING",wing+Vector3(0,2.75,-0.4),Vector2(2.65,1.2),G.PAPER)
	match index:
		0: _locker(bay)
		1: _prizes(bay)
		2: _profile(bay)
		3: _progression(bay)

func _locker(bay: Node3D) -> void:
	for i in range(3):
		var x := -2.0+i*1.08
		G.box(bay,"PersonalLocker",Vector3(x,1.79,0.57),Vector3(1.03,3.45,0.79),ink,true)
		G.box(bay,"InsetDoor",Vector3(x,1.8,0.99),Vector3(0.93,3.29,0.08),painted)
		G.box(bay,"NameHolder",Vector3(x,2.62,1.05),Vector3(0.49,0.24,0.04),brass)
		G.label(bay,"LockerNumber","0%d" % (i+1),Vector3(x,2.62,1.08),28,G.INK,0.006)
		G.box(bay,"Latch",Vector3(x+0.29,1.55,1.12),Vector3(0.075,0.26,0.12),brass)
		for y in [2.99,3.1,3.21,0.35,0.46]: G.box(bay,"Vent",Vector3(x,y,1.04),Vector3(0.58,0.032,0.02),ink)
	G.box(bay,"DressingFrame",Vector3(1.89,2.4,0.29),Vector3(1.5,2.35,0.25),timber)
	G.box(bay,"DressingGlass",Vector3(1.89,2.4,0.43),Vector3(1.23,2.09,0.04),G.material("smoked_dressing_glass",Color("526e72"),0,0.85))
	for x in [1.02,2.76]:
		G.box(bay,"DressingLampMount",Vector3(x,2.4,0.5),Vector3(0.12,2.14,0.13),brass)
		G.box(bay,"DressingLight",Vector3(x,2.4,0.6),Vector3(0.075,1.9,0.08),lamp_mat)
	_bench(bay,Vector3(1.8,0,1.0),1.7)
	G.label(bay,"LockerCaption","MAKE IT YOURS",Vector3(1.9,3.79,0.3),38,G.INK,0.006)
	_hat(bay,"Fedorablackhat.glb",Vector3(-2,3.56,0.62),0.7)

func _prizes(bay: Node3D) -> void:
	G.box(bay,"TicketWindowFrame",Vector3(-0.7,2.46,0.39),Vector3(3.8,2.63,0.35),timber,true)
	G.box(bay,"TicketWindowDark",Vector3(-0.7,2.45,0.6),Vector3(3.46,2.31,0.09),ink)
	for x in [-2.1,-1.65,-1.2,-0.75,-0.3,0.15,0.6]:
		G.rod(bay,Vector3(x,1.47,0.77),Vector3(x,3.55,0.77),0.022,brass)
	G.box(bay,"ServiceSlot",Vector3(-0.7,1.57,0.85),Vector3(1.9,0.38,0.13),ink)
	G.label(bay,"PrizeWindowCaption","THE GOOD STUFF",Vector3(-0.7,2.92,0.88),46,G.PAPER,0.0065)
	G.label(bay,"PrizeWindowDetail","OUTFITS  /  COSMETICS",Vector3(-0.7,2.44,0.88),29,G.PAPER,0.006)
	G.box(bay,"PrizeCounterBase",Vector3(-0.55,0.65,1.38),Vector3(4.15,1.3,1.05),painted,true)
	G.box(bay,"PrizeCounterTop",Vector3(-0.55,1.35,1.36),Vector3(4.45,0.16,1.35),timber)
	for x in [-2.1,-1.3,-0.5,0.3,1.1]: G.box(bay,"CounterPanelTrim",Vector3(x,0.64,1.92),Vector3(0.06,1.04,0.035),brass)
	G.box(bay,"CollectionTray",Vector3(-0.6,1.46,1.5),Vector3(0.95,0.08,0.5),brass)
	G.box(bay,"DisplayCabinet",Vector3(2.18,0.62,0.87),Vector3(1.13,1.24,1.02),ink,true)
	for y in [1.3,2.43,3.53]: G.box(bay,"DisplayShelf",Vector3(2.18,y,0.87),Vector3(1.22,0.09,1.1),timber)
	for x in [1.58,2.79]: G.box(bay,"CabinetUpright",Vector3(x,2.43,0.87),Vector3(0.05,2.3,1.06),brass)
	_hat(bay,"Crownhat_runtime.glb",Vector3(2.18,1.38,0.85),0.82)
	_hat(bay,"Fedorablackhat.glb",Vector3(2.18,2.51,0.85),0.84)

func _profile(bay: Node3D) -> void:
	G.box(bay,"PortraitFrame",Vector3(-1.55,2.65,0.43),Vector3(2.05,2.4,0.3),timber)
	G.box(bay,"PortraitMat",Vector3(-1.55,2.65,0.6),Vector3(1.85,2.2,0.07),ink)
	var portrait := MeshInstance3D.new()
	portrait.name = "IdentityPortrait"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.75,1.97)
	portrait.mesh = quad
	var portrait_material := StandardMaterial3D.new()
	portrait_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Saved identity is assigned at runtime without changing a UI texture importer.
	portrait.visible = false
	portrait.material_override = portrait_material
	portrait.set_meta("live_visual",true)
	bay.add_child(portrait)
	portrait.position = Vector3(-1.55,2.65,0.66)
	G.label(bay,"IdentityAlias","STRAY",Vector3(1.18,3.2,0.35),66,G.INK,0.007)
	G.label(bay,"IdentityCaption","YOUR RECORD\nSTATS  /  IDENTITY",Vector3(1.18,2.43,0.35),35,G.INK,0.0065)
	G.box(bay,"RecordCabinet",Vector3(2.0,0.79,0.65),Vector3(1.4,1.58,0.9),painted,true)
	for y in [0.28,0.77,1.26]:
		G.box(bay,"RecordDrawer",Vector3(2,y,1.13),Vector3(1.29,0.44,0.055),ink)
		G.box(bay,"DrawerHandle",Vector3(2,y,1.19),Vector3(0.32,0.06,0.1),brass)
	G.box(bay,"IdentityDesk",Vector3(-0.42,0.69,1.5),Vector3(2.6,1.38,0.8),painted,true)
	var top := G.box(bay,"SlopedIdentityDesk",Vector3(-0.42,1.48,1.57),Vector3(2.8,0.14,1.24),timber)
	top.rotation.x = 0.17
	var terminal := G.box(bay,"IdentityTerminal",Vector3(-0.42,1.66,1.39),Vector3(1.56,0.075,0.69),ink)
	terminal.rotation.x = 0.17
	G.box(bay,"TerminalStatus",Vector3(-0.42,1.72,1.15),Vector3(0.62,0.04,0.035),brass)

func _progression(bay: Node3D) -> void:
	G.box(bay,"CareerBoardFrame",Vector3(0,2.97,0.43),Vector3(5.25,1.64,0.28),timber)
	G.box(bay,"CareerBoard",Vector3(0,2.97,0.6),Vector3(5.03,1.43,0.06),ink)
	G.label(bay,"CareerCaption","THE ROAD AHEAD",Vector3(0,3.42,0.65),39,G.PAPER,0.0065)
	G.box(bay,"CareerRoute",Vector3(0,2.94,0.68),Vector3(4.1,0.037,0.035),brass)
	for i in range(5):
		var badge := G.cylinder(bay,"MilestoneSymbol",Vector3(-2+i,2.94,0.73),0.13,0.06,brass)
		badge.rotation.x = PI/2
	G.label(bay,"ProgressionCaption","LEVELS  /  REWARDS  /  MILESTONES",Vector3(0,2.51,0.68),27,G.PAPER,0.006)
	G.box(bay,"TrophyShelf",Vector3(0,1.81,0.63),Vector3(5.1,0.13,0.8),timber)
	for x in [-2.0,0.0,2.0]:
		G.box(bay,"MementoBase",Vector3(x,1.94,0.58),Vector3(0.4,0.15,0.37),ink)
		var plaque := G.box(bay,"MementoPlaque",Vector3(x,2.14,0.58),Vector3(0.24,0.29,0.075),brass)
		plaque.rotation.z = -0.15 if x<0 else 0.15
	_bench(bay,Vector3(0,0,1.05),4.8)

func _bench(parent: Node3D, pos: Vector3, width: float) -> void:
	var bench := Node3D.new()
	parent.add_child(bench)
	bench.position = pos
	# One uncomplicated collision box; individual slats are visual only.
	G.box(bench,"BenchSupport",Vector3(0,0.35,0),Vector3(width,0.7,0.58),ink,true)
	for i in range(4): G.box(bench,"TimberSlat",Vector3(0,0.74,-0.3+i*0.2),Vector3(width+0.12,0.09,0.18),timber if i%2 else timber_light)
	for x in [-width*0.4,width*0.4]:
		G.rod(bench,Vector3(x,0.76,-0.36),Vector3(x,1.39,-0.36),0.035,ink)
	for y in [1.04,1.27]: G.box(bench,"BackSlat",Vector3(0,y,-0.38),Vector3(width,0.17,0.08),timber_light)

func _hat(parent: Node3D, filename: String, pos: Vector3, width: float) -> void:
	# Reuse optimized cosmetic meshes as inert displays; no inventory actors/scripts.
	var packed := load("res://models/cosmetics/hats/runtime/"+filename) as PackedScene
	var source := packed.instantiate() as Node3D
	var bounds := AABB()
	var pieces: Array[MeshInstance3D] = []
	var transforms: Array[Transform3D] = []
	for child in source.find_children("*","MeshInstance3D",true,false):
		var mesh_node := child as MeshInstance3D
		var transform := mesh_node.transform
		var ancestor := mesh_node.get_parent()
		while ancestor != source:
			if ancestor is Node3D: transform = ancestor.transform * transform
			ancestor = ancestor.get_parent()
		var piece_bounds: AABB = transform * mesh_node.get_aabb()
		bounds = piece_bounds if pieces.is_empty() else bounds.merge(piece_bounds)
		pieces.append(mesh_node)
		transforms.append(transform)
	var scale_factor := width / maxf(bounds.size.x,0.01)
	var offset := Vector3(-bounds.get_center().x,-bounds.position.y,-bounds.get_center().z)
	var display := Node3D.new()
	display.name = "CosmeticDisplay"
	parent.add_child(display)
	display.position = pos
	display.scale = Vector3.ONE * scale_factor
	for i in range(pieces.size()):
		var piece := MeshInstance3D.new()
		piece.name = "HatMesh"
		piece.mesh = pieces[i].mesh
		piece.material_override = pieces[i].material_override
		for surface in range(piece.mesh.get_surface_count()):
			piece.set_surface_override_material(surface,pieces[i].get_surface_override_material(surface))
		piece.set_meta("live_visual",true) # Preserve imported multi-surface materials.
		display.add_child(piece)
		piece.transform = transforms[i]
		piece.position += offset
	source.free()
