extends Node3D

const G = preload("res://maps/hideout/geometry.gd")
signal station_entered(id: String)
signal station_exited(id: String)
var event_line: Label3D
var party_line: Label3D
var departure_line: Label3D
var doors: Array[Node3D] = []
var departure_door: Node3D
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
var service_status: Dictionary = {}
var active_service := ""
var identity_portrait: MeshInstance3D
var identity_alias: Label3D

func _ready() -> void:
	name = "Station"
	if has_node("Architecture"):
		_bind_baked_scene()
		return
	concrete = G.material("hall_cream",Color("f4e5d2"))
	tile = G.material("hall_aqua",Color("705b87"))
	steel = G.material("steel", Color("51415f"), 0, 0.55)
	dark = G.material("dark", Color("352c49"))
	gold = G.material("paint_gold", G.GOLD)
	warm = G.material("warm_glass", Color("ffd99a"), 1.4)
	root_geo = Node3D.new()
	root_geo.name = "Architecture"
	add_child(root_geo)
	_build_shell()
	_build_pit()
	_build_event_board()
	_build_player_hub()
	_build_playpen()
	preload("res://maps/hideout/scrap_space.gd").build(self)
	_build_arrivals()
	_build_departure()
	preload("res://maps/hideout/clubhouse_decor.gd").build(self)
	_build_lighting()
	_bind_service_visuals()
	if not OS.get_cmdline_user_args().has("--bake-live-lobby"):
		_batch_static_meshes()

func _build_shell() -> void:
	G.box(root_geo,"Foundation",Vector3(0,-0.95,0),Vector3(55,0.7,61),concrete,true)
	preload("res://maps/hideout/bounded_concourse.gd").build(root_geo,G.material("concourse_cream",Color("e5d7c5")))
	G.box(root_geo,"NorthWallWest",Vector3(-8.6,5.2,-30),Vector3(36.8,10.4,0.7),tile,true)
	G.box(root_geo,"NorthWallEast",Vector3(25.6,5.2,-30),Vector3(2.8,10.4,0.7),tile,true)
	G.box(root_geo,"PlayPenLintel",Vector3(17,8.8,-30),Vector3(14.4,3.2,0.7),concrete,true)
	G.box(root_geo,"WestWall",Vector3(-27,5.2,0),Vector3(0.7,10.4,60),tile,true)
	for x in [-15.8,15.8]:
		G.box(root_geo,"SouthWall",Vector3(x,5.2,30),Vector3(22.4,10.4,0.7),tile,true)
	G.box(root_geo,"ArrivalWallLintel",Vector3(0,8.35,30),Vector3(9.2,4.1,0.7),concrete,true)
	for z in [-16.5,16.5]:
		G.box(root_geo,"EastWall",Vector3(27,5.2,z),Vector3(0.7,10.4,27),tile,true)
	G.box(root_geo,"EastLintel",Vector3(27,8.0,0),Vector3(0.7,4.8,6),concrete,true)
	for x in [-26.45,26.45]:
		for z in ([-16.5,16.5] if x>0 else [0.0]):
			var length := 27.0 if x>0 else 60.0
			G.box(root_geo,"WallPlinth",Vector3(x,0.75,z),Vector3(0.2,1.5,length),steel)
			G.box(root_geo,"ServiceStripe",Vector3(x,3.1,z),Vector3(0.07,0.24,length),gold)
	for z in [-30.0,30.0]:
		G.box(root_geo,"VaultEndWall",Vector3(0,12.5,z),Vector3(54,4.2,0.7),concrete,true)
	for x in [-15.8,15.8]:
		G.box(root_geo,"WallPlinth",Vector3(x,0.75,29.5),Vector3(22.4,1.5,0.2),steel)
		G.box(root_geo,"ServiceStripe",Vector3(x,3.1,29.5),Vector3(22.4,0.24,0.07),gold)
	for z in [-27.5,-14.0,0.0,14.0,27.5]:
		for x in [-25.4,25.4]:
			if x<0 or is_zero_approx(z): continue
			G.box(root_geo,"ColumnFoot",Vector3(x,0.25,z),Vector3(1.15,0.5,1.15),concrete,true)
			G.box(root_geo,"RivetedColumn",Vector3(x,4.6,z),Vector3(0.55,9.2,0.7),steel,true)
			G.box(root_geo,"ColumnFace",Vector3(x,2.3,z+0.37),Vector3(0.36,1.15,0.035),gold)
		for i in range(20):
			var a := PI*i/20.0
			var b := PI*(i+1)/20.0
			G.rod(root_geo,Vector3(cos(a)*25.5,8.3+sin(a)*5.0,z),Vector3(cos(b)*25.5,8.3+sin(b)*5.0,z),0.18,steel)
	for i in range(18):
		var x := -25.5+i*3.0
		G.box(root_geo,"VaultPanel",Vector3(x,13.9-absf(x)*0.18,0),Vector3(3.04,0.25,60),concrete)
	for x in [-21.0,21.0]:
		G.rod(root_geo,Vector3(x,8.5,-29),Vector3(x,8.5,29),0.13,G.material("copper",Color("73513d"),0,0.3))
	for z in [-15.0,3.0,16.0]:
		G.box(root_geo,"Drain",Vector3(-16,0.012,z),Vector3(1,0.025,2.5),dark)
		for i in range(8):
			G.box(root_geo,"DrainSlat",Vector3(-16,0.035,z-1.05+i*0.3),Vector3(0.95,0.025,0.06),steel)
	# Painted routes connect destinations across the wider concourse.
	for x in [-11.4,11.4]:
		for z in [-19.0,18.0]:
			G.box(root_geo,"Wayfinding",Vector3(x,0.026,z),Vector3(0.12,0.026,8),gold)

func _build_pit() -> void:
	for i in range(3):
		var radius := 7.2 + i*1.0
		var y := -0.4+i*0.2
		G.ring(root_geo,"PitStep",radius,radius+1.0,y,G.material("pit_tread",Color("d9c5b4")),true)
		G.ring(root_geo,"StepNosing",radius,radius+0.19,y+0.027,gold)
	var seal := G.box(root_geo,"PaintedOneGunSeal",Vector3(0,-0.587,0),Vector3(7.4,0.02,7.4),G.textured("floor_seal",Color.WHITE))
	# A PlaneMesh keeps the seal on top with undistorted UVs.
	var plane := PlaneMesh.new()
	plane.size = Vector2(7.4,7.4)
	seal.mesh = plane
	for side in [-1,1]:
		for i in range(4):
			var angle: float = (0.75+i*0.24)*side
			var pos := Vector3(sin(angle)*10.9,0,cos(angle)*10.9)
			var bench := Node3D.new()
			root_geo.add_child(bench)
			bench.position = pos
			bench.rotation.y = angle
			G.box(bench,"BenchSeat",Vector3(0,0.58,0),Vector3(1.8,0.16,0.65),G.material("seat",Color("705b87")),true)
			G.box(bench,"BenchBack",Vector3(0,1.0,0.3),Vector3(1.8,0.65,0.1),steel)
			for x in [-0.65,0.65]:
				G.box(bench,"BenchFoot",Vector3(x,0.25,0),Vector3(0.1,0.5,0.5),steel)
	for side in [-1,1]:
		for i in range(7):
			var a: float = side*(1.32+i*0.14)
			var b: float = side*(1.32+(i+1)*0.14)
			var p := Vector3(sin(a)*10.6,1.0,cos(a)*10.6)
			var q := Vector3(sin(b)*10.6,1.0,cos(b)*10.6)
			G.rod(root_geo,p,q,0.055,steel)
			G.rod(root_geo,p-Vector3(0,0.95,0),p,0.04,steel)

func _build_event_board() -> void:
	preload("res://maps/hideout/dispatch.gd").build(self)

func _build_playpen() -> void:
	preload("res://maps/hideout/playpen_space.gd").build(self)

func _build_arrivals() -> void:
	preload("res://maps/hideout/arrival_space.gd").build(self)

func open_arrivals(wait_seconds := 1.4) -> void:
	if arrival_tween and arrival_tween.is_running(): arrival_tween.kill()
	arrival_tween=create_tween().set_parallel(true)
	for i in range(doors.size()):
		arrival_tween.tween_property(doors[i],"position:x",-6.65 if i==0 else 6.65,0.85).set_delay(wait_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _build_departure() -> void:
	var bay := Node3D.new()
	root_geo.add_child(bay)
	bay.position = Vector3(26.5,0,0)
	bay.rotation.y = -PI/2
	G.box(bay,"DepartureFloor",Vector3(0,-0.25,-2),Vector3(6,0.5,5),concrete,true)
	G.box(bay,"DepartureEnd",Vector3(0,2.7,-4),Vector3(6,5.4,0.5),dark,true)
	for x in [-3.0,3.0]:
		G.box(bay,"TunnelJamb",Vector3(x,2.7,-2),Vector3(0.4,5.4,5),steel,true)
	G.box(bay,"TunnelRoof",Vector3(0,5.5,-2),Vector3(6,0.4,5),steel,true)
	G.panel(bay,"DepartureSign","MATCH STATUS",Vector3(0,5.8,0.85),Vector2(6.8,0.8),G.GOLD)
	departure_line = G.label(bay,"DepartureStatus","CHOOSE AT THE GAME BOARD",Vector3(0,4.9,0.9),40,G.PAPER)
	departure_door = G.box(self,"DepartureShutter",Vector3(26.15,2.1,0),Vector3(0.18,4.2,5.7),steel,true)
	for y in range(13):
		G.box(departure_door,"ShutterRib",Vector3(-0.11,-1.9+y*0.3,0),Vector3(0.06,0.065,5.7),dark)
	G.box(root_geo,"DepartureFloorLine",Vector3(23.7,0.025,0),Vector3(3.7,0.03,0.12),gold)
	_zone("departure",Vector3(23.2,1,0),Vector3(4,4,6))

func set_departure(active: bool, destination: String) -> void:
	departure_line.text = destination.to_upper() if active else "CHOOSE AT THE GAME BOARD"
	departure_line.modulate = G.GREEN if active else G.PAPER
	if departure_tween and departure_tween.is_running():
		departure_tween.kill()
	departure_tween = create_tween()
	departure_tween.tween_property(departure_door,"position:y",6.4 if active else 2.1,0.8)

func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	environment = Environment.new()
	we.environment = environment
	add_child(we)
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("352c49")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff5e4")
	environment.ambient_light_energy = 0.85
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	environment.ssao_enabled = true
	for pos in [Vector3(-8,7,-9),Vector3(8,7,-9),Vector3(-8,7,12),Vector3(8,7,12),Vector3(0,7.8,-23),Vector3(17,7,17)]:
		G.box(root_geo,"PracticalHousing",pos,Vector3(2.4,0.2,0.7),steel)
		G.box(root_geo,"WarmPractical",pos-Vector3(0,0.12,0),Vector3(2.15,0.08,0.5),warm)
		G.lamp(self,pos-Vector3(0,0.35,0),Color("ffdab0"),2.0,16)
	var key := DirectionalLight3D.new()
	add_child(key)
	key.rotation_degrees = Vector3(-65,-25,0)
	key.light_color = Color("fff4e2")
	key.light_energy = 0.8
	key.shadow_enabled = false

func _zone(id: String, pos: Vector3, size: Vector3) -> void:
	var area := Area3D.new()
	area.name = id.capitalize()+"Interaction"
	area.collision_layer = 0
	area.collision_mask = 2
	add_child(area)
	area.position = pos
	area.set_meta("station_id",id)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	area.add_child(shape)
	area.body_entered.connect(func(body):
		if body==get_parent().get("pilot"): station_entered.emit(id))
	area.body_exited.connect(func(body):
		if body==get_parent().get("pilot"): station_exited.emit(id))

func _batch_static_meshes() -> void:
	# Separate room/material batches keep the walled Play Pen independently culled.
	# Animated doors and text live outside this static visual batch.
	var batches: Dictionary = {}
	var meshes := root_geo.find_children("*","MeshInstance3D",true,false)
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or mesh_node.has_meta("live_visual"): continue
		var mat: Material = mesh_node.material_override
		if mat == null or mesh_node.mesh.get_surface_count() != 1: continue
		var p: Vector3 = mesh_node.global_position
		var room := "hall"
		var ancestor: Node=mesh_node.get_parent()
		while ancestor!=null and ancestor!=root_geo:
			if ancestor.name=="PlayPenArchitecture":
				room="pen"+str(p.z < -34)+"/"+str(p.z < -62)
				break
			if ancestor.name in ["RangeArchitecture","AgilityArchitecture","ArrivalArchitecture","ScrapArchitecture"]:
				room=str(ancestor.name)+"/"+str(floori(p.x/20.0))+"/"+str(floori(p.z/20.0))
				break
			ancestor=ancestor.get_parent()
		var key := room+"/"+str(mat.get_instance_id())+"/"+str(p.x>0)+"/"+str(p.z>0)
		if not batches.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[key] = [st,mat]
		var surface: SurfaceTool = batches[key][0]
		surface.append_from(mesh_node.mesh,0,global_transform.affine_inverse() * mesh_node.global_transform)
		mesh_node.mesh = null
	for key in batches:
		var mesh_node := MeshInstance3D.new()
		mesh_node.name = "StaticBatch"
		var surface: SurfaceTool = batches[key][0]
		mesh_node.mesh = surface.commit()
		mesh_node.material_override = batches[key][1]
		add_child(mesh_node)


func _bind_baked_scene() -> void:
	root_geo = $Architecture
	event_line = find_child("EventStatus",true,false)
	party_line = find_child("PartyStatus",true,false)
	departure_line = find_child("DepartureStatus",true,false)
	departure_door = $DepartureShutter
	environment = $WorldEnvironment.environment
	for i in range(2): doors.append(get_node("ArrivalDoor%d" % i))
	for child in get_children():
		if child is Area3D and child.has_meta("station_id"):
			var id: String = child.get_meta("station_id")
			child.body_entered.connect(func(body):
				if body==get_parent().get("pilot"): station_entered.emit(id))
			child.body_exited.connect(func(body):
				if body==get_parent().get("pilot"): station_exited.emit(id))
	_bind_service_visuals()
	_batch_static_meshes()

func _build_player_hub() -> void:
	preload("res://maps/hideout/arcade.gd").new().build(self)

func _bind_service_visuals() -> void:
	identity_portrait = find_child("IdentityPortrait",true,false)
	identity_alias = find_child("IdentityAlias",true,false)
	if identity_portrait:
		identity_portrait.material_override = identity_portrait.material_override.duplicate()
	for label in root_geo.find_children("*","Label3D",true,false):
		if label.has_meta("service_id"):
			service_status[str(label.get_meta("service_id"))] = label

func set_active_service(id: String) -> void:
	var next := id if service_status.has(id) else ""
	if active_service == next: return
	active_service = next
	for service in service_status:
		service_status[service].text = "INTERACT" if service == next else ""

func set_profile_identity(alias_name: String, model_id: String, skin_id: String) -> void:
	if identity_alias:
		identity_alias.text = alias_name.to_upper().left(15)
	if identity_portrait:
		var portrait := PlayerSkinRegistry.load_portrait(skin_id,model_id)
		identity_portrait.visible = portrait != null
		# Copy only the current portrait into a runtime texture. Godot otherwise
		# auto-converts the shared UI PNG importer when a 3D material references it.
		identity_portrait.material_override.albedo_texture = ImageTexture.create_from_image(portrait.get_image()) if portrait else null
