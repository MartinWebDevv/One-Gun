extends Node
# Temporary autoload: builds maps/test/WesternV2Map.tscn ("Western v2").
# Sunset main-street showdown town. Run via temporary [autoload] entry, then remove.

const OUT_PATH := "res://maps/test/WesternV2Map.tscn"
const A := "res://models/westernV2/"
const WA := "res://models/westernAssets/"

var rng := RandomNumberGenerator.new()
var ground_faces: PackedVector3Array
var root: Node3D

const HALF_X := 34.0
const HALF_Z := 26.0
const STREET_HALF := 9.0  # flat band |z| < 9

func _ready() -> void:
	rng.seed = 18811881
	_build()
	get_tree().quit()

func _build() -> void:
	root = Node3D.new()
	root.name = "WesternV2Map"
	_add_ground()
	_add_backdrop_and_mesas()
	_add_buildings()
	_add_landmarks()
	_add_elevation()
	_add_street_props()
	_add_scrub_scatter()
	_add_perimeter_walls()
	_add_atmosphere()
	_add_dust()
	_add_vultures()
	_add_tumbleweeds()
	add_child(root)
	_bake_navmesh()
	remove_child(root)
	_add_spawn_points()
	_add_gameplay_scaffolding()
	var packed := PackedScene.new()
	print("PACK: ", packed.pack(root))
	print("SAVE: ", ResourceSaver.save(packed, OUT_PATH))

# ---------- ground ----------

func _add_ground() -> void:
	var g: Node3D = (load(A + "WesternGround.glb") as PackedScene).instantiate()
	g.name = "Ground"
	root.add_child(g)
	g.owner = root
	var mi := _first_mesh_instance(g)
	ground_faces = mi.mesh.get_faces()
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(ground_faces)
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	body.owner = root
	col.owner = root
	print("Ground faces: ", ground_faces.size() / 3)

func height_at(x: float, z: float) -> float:
	for i in range(0, ground_faces.size(), 3):
		var a := ground_faces[i]
		var b := ground_faces[i + 1]
		var c := ground_faces[i + 2]
		var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(d) < 0.000001:
			continue
		var w1 := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
		if w1 < -0.001 or w1 > 1.001:
			continue
		var w2 := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
		if w2 < -0.001 or w1 + w2 > 1.001:
			continue
		return a.y * w1 + b.y * w2 + c.y * (1.0 - w1 - w2)
	return 0.0

# ---------- helpers ----------

func _instance_prop(scene_path: String, pos: Vector3, yrot: float, scale: float, parent: Node3D, prop_name: String) -> Node3D:
	var n: Node3D = (load(scene_path) as PackedScene).instantiate()
	n.name = prop_name
	n.transform = Transform3D(Basis(Vector3.UP, yrot).scaled(Vector3(scale, scale, scale)), pos)
	parent.add_child(n)
	_own_shallow(n)
	return n

func _own_shallow(n: Node) -> void:
	n.owner = root
	if n.scene_file_path != "":
		return
	for c in n.get_children():
		_own_shallow(c)

func _add_box_collider(parent: Node3D, pos: Vector3, size: Vector3, yrot: float, cname: String) -> void:
	var body := StaticBody3D.new()
	body.name = cname
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.transform = Transform3D(Basis(Vector3.UP, yrot), pos)
	body.add_child(col)
	parent.add_child(body)
	body.owner = root
	col.owner = root

func _combined_aabb(node: Node3D) -> AABB:
	var combined: AABB
	var first := true
	for mi in _find_all_mesh_instances(node):
		if mi.mesh == null:
			continue
		var ab: AABB = mi.transform * mi.mesh.get_aabb()
		var p: Node = mi.get_parent()
		while p != node and p is Node3D:
			ab = (p as Node3D).transform * ab
			p = p.get_parent()
		combined = ab if first else combined.merge(ab)
		first = false
	return combined

func _find_all_mesh_instances(node: Node) -> Array:
	var r: Array = []
	if node is MeshInstance3D:
		r.append(node)
	for c in node.get_children():
		r.append_array(_find_all_mesh_instances(c))
	return r

func _first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var r := _first_mesh_instance(c)
		if r:
			return r
	return null

# ---------- backdrop ----------

func _add_backdrop_and_mesas() -> void:
	var bd := Node3D.new()
	bd.name = "Backdrop"
	root.add_child(bd)
	bd.owner = root
	var desert: Node3D = (load(WA + "DesertScene.glb") as PackedScene).instantiate()
	desert.name = "DesertBackdrop"
	desert.transform = Transform3D(Basis().scaled(Vector3(220, 55, 220)), Vector3(0, -2.5, 0))
	bd.add_child(desert)
	_own_shallow(desert)
	var mesa_defs := [
		["Mesa_A.glb", -44, -30, 1.0], ["Mesa_B.glb", 40, -36, 0.9],
		["Mesa_A.glb", 48, 22, 1.2], ["Mesa_B.glb", -46, 28, 0.8],
		["Mesa_A.glb", 0, -46, 1.1], ["Mesa_B.glb", -10, 44, 1.0],
	]
	var i := 0
	for d in mesa_defs:
		_instance_prop(A + d[0], Vector3(d[1], -1.5, d[2]), rng.randf_range(0, TAU), d[3], bd, "Mesa%d" % i)
		i += 1

# ---------- buildings ----------

func _add_buildings() -> void:
	var town := Node3D.new()
	town.name = "Town"
	root.add_child(town)
	town.owner = root
	# storefront fronts face +Z after import; north row faces street (+Z), south row rotates PI
	# [file, x, w, d, h] - dims from gen_western_assets.py make_false_front calls
	var north := [
		["Storefront_Tan.glb", -18.0, 4.5, 4.0, 3.2], ["Storefront_Brown.glb", -9.5, 5.0, 4.2, 3.4],
		["Storefront_Gray.glb", -1.5, 3.8, 3.6, 3.0], ["Storefront_Red.glb", 7.0, 5.5, 4.6, 3.8],
		["Storefront_Tan.glb", 15.5, 4.5, 4.0, 3.2],
	]
	var south := [
		["Storefront_Red.glb", 3.0, 5.5, 4.6, 3.8], ["Storefront_Gray.glb", 11.5, 3.8, 3.6, 3.0],
		["Storefront_Brown.glb", 18.5, 5.0, 4.2, 3.4],
	]
	var bi := 0
	for row in [[north, -11.5, 0.0, 1.0], [south, 11.5, PI, -1.0]]:
		for b in row[0]:
			var x: float = b[1]
			var z: float = row[1]
			var w: float = b[2]
			var d: float = b[3]
			var h: float = b[4]
			var dir: float = row[3]  # +1 north row (front toward +Z / street), -1 south
			var y := height_at(x, z)
			_instance_prop(A + b[0], Vector3(x, y, z), row[2], 1.0, town, "Bldg%d" % bi)
			# split colliders: body up to true roof height (walkable top), thin
			# parapet at the street face (chest cover for anyone on the roof)
			var roof_h := h + 0.14
			_add_box_collider(town, Vector3(x, y + roof_h / 2.0, z), Vector3(w + 0.1, roof_h, d), row[2], "BldgCol%d" % bi)
			var pz := z + dir * (d / 2.0 + 0.06)
			var py := y + roof_h + 0.58
			# the two catwalk-anchor buildings get a gap in their parapet at the
			# catwalk lane (x -0.4..1.4) so players can step onto the bridge
			if x == -1.5 and dir > 0:      # Gray, north row
				_add_box_collider(town, Vector3(-2.0, py, pz), Vector3(3.05, 1.16, 0.14), row[2], "Parapet%d" % bi)
			elif x == 3.0 and dir < 0:     # Red, south row
				_add_box_collider(town, Vector3(3.68, py, pz), Vector3(4.4, 1.16, 0.14), row[2], "Parapet%d" % bi)
			else:
				_add_box_collider(town, Vector3(x, py, pz), Vector3(w + 0.24, 1.16, 0.14), row[2], "Parapet%d" % bi)
			bi += 1
	# the detailed saloon (dollhouse-scale scene: measure and scale to real size)
	var saloon: Node3D = (load("res://Scenes/weternMap/buildings/saloon/westernMap_saloon.tscn") as PackedScene).instantiate()
	saloon.name = "Saloon"
	town.add_child(saloon)
	_own_shallow(saloon)
	var sab := _combined_aabb(saloon)
	var target_h := 6.5
	var s: float = target_h / maxf(sab.size.y, 0.01)
	var sy := height_at(-8.0, 11.5)
	saloon.transform = Transform3D(Basis(Vector3.UP, 0.0).scaled(Vector3(s, s, s)), Vector3(-8.0, sy - sab.position.y * s + 0.02, 11.5))
	print("Saloon raw aabb %s -> scale %.2f" % [sab, s])
	# saloon walls with a front-door gap (front faces -Z toward street)
	var wz := 11.5
	var half_w: float = sab.size.x * s / 2.0
	var half_d: float = sab.size.z * s / 2.0
	var wall_h := target_h * 0.75
	_add_box_collider(town, Vector3(-8.0, sy + wall_h / 2.0, wz + half_d * 0.75), Vector3(half_w * 2.0, wall_h, 0.3), 0.0, "SaloonBack")
	_add_box_collider(town, Vector3(-8.0 - half_w * 0.8, sy + wall_h / 2.0, wz), Vector3(0.3, wall_h, half_d * 1.6), 0.0, "SaloonWest")
	_add_box_collider(town, Vector3(-8.0 + half_w * 0.8, sy + wall_h / 2.0, wz), Vector3(0.3, wall_h, half_d * 1.6), 0.0, "SaloonEast")
	var gap := 1.4
	var front_z := wz - half_d * 0.72
	var seg: float = (half_w * 1.6 - gap) / 2.0
	_add_box_collider(town, Vector3(-8.0 - gap / 2.0 - seg / 2.0, sy + wall_h / 2.0, front_z), Vector3(seg, wall_h, 0.3), 0.0, "SaloonFrontW")
	_add_box_collider(town, Vector3(-8.0 + gap / 2.0 + seg / 2.0, sy + wall_h / 2.0, front_z), Vector3(seg, wall_h, 0.3), 0.0, "SaloonFrontE")

func _add_landmarks() -> void:
	var lm := Node3D.new()
	lm.name = "Landmarks"
	root.add_child(lm)
	lm.owner = root
	# church at the west end, front (tower) facing east down the street
	var cy := height_at(-27.0, 0.0)
	_instance_prop(A + "Church.glb", Vector3(-27.0, cy, 0.0), -PI / 2.0, 1.0, lm, "Church")
	_add_box_collider(lm, Vector3(-26.5, cy + 1.8, 0.0), Vector3(7.2, 3.6, 5.0), 0.0, "ChurchCol")
	# clocktower at the east end (existing asset)
	var ty := height_at(27.0, 0.0)
	var tower := _instance_prop(WA + "ClockTower.glb", Vector3(27.0, ty, 0.0), PI / 2.0, 5.0, lm, "ClockTower")
	var tab := _combined_aabb(tower)
	_add_box_collider(lm, Vector3(27.0, ty + tab.size.y / 2.0, 0.0), Vector3(maxf(tab.size.x, 2.5), tab.size.y, maxf(tab.size.z, 2.5)), 0.0, "ClockTowerCol")
	# water tower behind the north row
	# (-13.5,-17.5): far enough inside that the stair bases sit on flat ground,
	# clear of the raised rim and boundary walls
	var wy := height_at(-13.5, -17.5)
	_instance_prop(A + "WaterTower.glb", Vector3(-13.5, wy, -17.5), 0.0, 1.0, lm, "WaterTower")
	for leg in [Vector2(-1.24, -1.24), Vector2(1.24, -1.24), Vector2(-1.24, 1.24), Vector2(1.24, 1.24)]:
		_add_box_collider(lm, Vector3(-13.5 + leg.x, wy + 2.6, -17.5 + leg.y), Vector3(0.3, 5.2, 0.3), 0.0, "WTLeg%d" % int(leg.angle() * 10))
	# windmill behind the south row, blades spinning
	var my := height_at(13.0, 19.0)
	var mill := _instance_prop(A + "Windmill.glb", Vector3(13.0, my, 19.0), -0.6, 1.0, lm, "Windmill")
	mill.set_script(load("res://windmill_spin.gd"))
	_add_box_collider(lm, Vector3(13.0, my + 3.4, 19.0), Vector3(1.6, 6.8, 1.6), -0.6, "WindmillCol")

# ---------- elevation network (rooftops / catwalk / tower perch) ----------

func _add_ramp_collider(parent: Node3D, pos: Vector3, size: Vector3, xrot: float, cname: String) -> void:
	var body := StaticBody3D.new()
	body.name = cname
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.transform = Transform3D(Basis(Vector3.RIGHT, xrot), pos)
	body.add_child(col)
	parent.add_child(body)
	body.owner = root
	col.owner = root

func _add_stair(parent: Node3D, base: Vector3, top_y: float, yrot: float, idx: int) -> void:
	# StairFlight ascends -Z locally (Blender +Y), rise 3.4 over run 5.1.
	var rise := top_y - base.y
	var s := rise / 3.4
	var stair := _instance_prop(A + "StairFlight.glb", base, yrot, 1.0, parent, "Stair%d" % idx)
	stair.transform = Transform3D(Basis(Vector3.UP, yrot).scaled(Vector3(1, s, 1)), base)
	# smooth ramp collider along the flight
	var run := 5.1
	var ang := atan2(rise, run)
	var ramp_len := sqrt(rise * rise + run * run) + 0.5
	var fwd := Basis(Vector3.UP, yrot) * Vector3(0, 0, -1)  # ascend direction
	var mid := base + fwd * (run / 2.0) + Vector3(0, rise / 2.0 - 0.06, 0)
	var body := StaticBody3D.new()
	body.name = "StairRamp%d" % idx
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.6, 0.14, ramp_len)
	col.shape = shape
	col.transform = Transform3D(Basis(Vector3.UP, yrot) * Basis(Vector3.RIGHT, ang), mid)
	body.add_child(col)
	parent.add_child(body)
	body.owner = root
	col.owner = root

func _add_stair_steps(parent: Node3D, base: Vector3, top_y: float, yrot: float, idx: int) -> void:
	# discrete flat step colliders: recast merges these via walkable_climb far
	# more reliably than a thin sloped box that dives under adjacent floors
	var rise := top_y - base.y
	var run := 5.1
	var steps := 12
	var fwd := Basis(Vector3.UP, yrot) * Vector3(0, 0, -1)
	for i in steps:
		var t := (i + 0.5) / steps
		var top := base.y + (i + 1) * rise / steps
		var pos := base + fwd * (t * run)
		var height := maxf(top - base.y + 0.3, 0.4)
		_add_box_collider(parent, Vector3(pos.x, top - height / 2.0, pos.z), Vector3(1.6, height, run / steps + 0.06), yrot, "Step%d_%d" % [idx, i])

func _add_elevation() -> void:
	var lv := Node3D.new()
	lv.name = "UpperLevel"
	root.add_child(lv)
	lv.owner = root
	# ---- roof access stairs (back/scrub side) ----
	# north row: Brown(-9.5, h3.4, d4.2) and Red(7.0, h3.8, d4.6)
	var ny := height_at(-9.5, -11.5)
	_add_stair(lv, Vector3(-9.5, height_at(-9.5, -18.9), -18.9), ny + 3.54, PI, 0)
	var ny2 := height_at(7.0, -11.5)
	_add_stair(lv, Vector3(7.0, height_at(7.0, -19.1), -19.1), ny2 + 3.94, PI, 1)
	# south row west: Red(3.0, h3.8, d4.6) - stairs ascend from behind (+Z side)
	var sy := height_at(3.0, 11.5)
	_add_stair(lv, Vector3(3.0, height_at(3.0, 19.1), 19.1), sy + 3.94, 0.0, 2)
	# south row east: reached from the plateau via a short ramp onto Brown(18.5, h3.4)
	var by := height_at(18.5, 11.5)
	var shelf_y := height_at(18.5, 16.2)
	var wk := _instance_prop(A + "RoofWalkway.glb", Vector3(18.5, (shelf_y + by + 3.54) / 2.0, 15.0), PI / 2.0, 1.0, lv, "ShelfRamp")
	var rr_ang := atan2(by + 3.54 - shelf_y, 3.0)
	wk.transform = Transform3D(Basis(Vector3.UP, PI / 2.0) * Basis(Vector3.RIGHT, rr_ang), Vector3(18.5, (shelf_y + by + 3.54) / 2.0, 15.0))
	_add_ramp_collider(lv, Vector3(18.5, (shelf_y + by + 3.54) / 2.0, 15.0), Vector3(1.5, 0.12, 3.8), rr_ang, "ShelfRampCol")
	# ---- roof-to-roof walkways ----
	var links := [
		# [x_mid, z, y_a, y_b, gap] between adjacent roofs (y = absolute roof top)
		# kept on the BACK lane (z +/-12.4) so the parapet-side roof lane stays clear
		[-5.2, -12.4, ny + 3.54, height_at(-1.5, -11.5) + 3.14, 4.2],
		[2.4, -12.4, height_at(-1.5, -11.5) + 3.14, ny2 + 3.94, 4.4],
		[7.7, 12.4, sy + 3.94, height_at(11.5, 11.5) + 3.14, 4.4],
		[15.0, 12.4, height_at(11.5, 11.5) + 3.14, by + 3.54, 3.4],
	]
	var wi := 0
	for l in links:
		var y_mid: float = (l[2] + l[3]) / 2.0
		var ang: float = atan2(l[3] - l[2], l[4])
		var scale_x: float = l[4] / 3.0
		var walk := _instance_prop(A + "RoofWalkway.glb", Vector3(l[0], y_mid, l[1]), 0.0, 1.0, lv, "Walk%d" % wi)
		walk.transform = Transform3D((Basis(Vector3.UP, 0.0) * Basis(Vector3(0, 0, 1), -ang)).scaled(Vector3(scale_x, 1, 1)), Vector3(l[0], y_mid, l[1]))
		var body := StaticBody3D.new()
		body.name = "WalkCol%d" % wi
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(l[4] + 0.8, 0.12, 1.5)
		col.shape = shape
		col.transform = Transform3D(Basis(Vector3(0, 0, 1), -ang), Vector3(l[0], y_mid, l[1]))
		body.add_child(col)
		lv.add_child(body)
		body.owner = root
		col.owner = root
		wi += 1
	# ---- catwalk over the gun (north Gray roof <-> south Red roof) ----
	var cat_n_y := height_at(-1.5, -11.5) + 3.14
	var cat_s_y := sy + 3.94
	var cat_x := 0.5
	var cat_mid_y := (cat_n_y + cat_s_y) / 2.0
	var cat_ang := atan2(cat_s_y - cat_n_y, 19.0)
	var cat := _instance_prop(A + "Catwalk.glb", Vector3(cat_x, cat_mid_y, 0), 0.0, 1.0, lv, "Catwalk")
	cat.transform = Transform3D(Basis(Vector3.RIGHT, -cat_ang), Vector3(cat_x, cat_mid_y, 0))
	_add_ramp_collider(lv, Vector3(cat_x, cat_mid_y - 0.05, 0), Vector3(1.6, 0.12, 20.8), -cat_ang, "CatwalkDeck")
	# rails stop short of both ends so players can step onto the open deck ends
	for side in [-1.0, 1.0]:
		_add_ramp_collider(lv, Vector3(cat_x + side * 0.78, cat_mid_y + 0.55, 0), Vector3(0.08, 1.1, 17.0), -cat_ang, "CatRail%d" % (1 if side > 0 else 0))
	# ---- water tower perch: L-shaped stairs to the platform (tower axis-aligned) ----
	# tower at (-13.5,-17.5); platform x -16.3..-10.7, z -20.3..-14.7; tank r1.32
	# leaves a 1.48m ring; the stairs arrive along the south ring at z=-15.5
	var wy := height_at(-13.5, -17.5)
	var plat_y := wy + 5.33
	var land_y := wy + 2.7
	# both flights use stepped colliders + a generously overlapping landing:
	# thin sloped ramps kept losing recast connectivity at the seams
	var f1_base := Vector3(-22.2, height_at(-22.2, -10.4), -10.4)
	var f1 := _instance_prop(A + "StairFlight.glb", f1_base, 0.0, 1.0, lv, "Stair10")
	f1.transform = Transform3D(Basis(Vector3.UP, 0.0).scaled(Vector3(1, (land_y - f1_base.y) / 3.4, 1)), f1_base)
	_add_stair_steps(lv, f1_base, land_y, 0.0, 10)
	_add_box_collider(lv, Vector3(-22.0, land_y - 0.07, -15.6), Vector3(3.2, 0.14, 2.6), 0.0, "TowerLanding")
	var f2_base := Vector3(-20.6, land_y, -15.5)
	var f2 := _instance_prop(A + "StairFlight.glb", f2_base, -PI / 2.0, 1.0, lv, "Stair11")
	f2.transform = Transform3D(Basis(Vector3.UP, -PI / 2.0).scaled(Vector3(1, (plat_y - land_y) / 3.4, 1)), f2_base)
	_add_stair_steps(lv, f2_base, plat_y, -PI / 2.0, 11)
	# platform walkable slab + tank blocker (ring 1.48m > agent diameter)
	_add_box_collider(lv, Vector3(-13.5, plat_y - 0.08, -17.5), Vector3(5.6, 0.16, 5.6), 0.0, "TowerPlatform")
	var tank := StaticBody3D.new()
	tank.name = "TankCol"
	var tcol := CollisionShape3D.new()
	var tshape := CylinderShape3D.new()
	tshape.radius = 1.32
	tshape.height = 2.2
	tcol.shape = tshape
	tcol.position = Vector3(-13.5, plat_y + 1.1, -17.5)
	tank.add_child(tcol)
	lv.add_child(tank)
	tank.owner = root
	tcol.owner = root
	# rails on 3 sides; the west edge stays open where the stairs arrive
	_add_box_collider(lv, Vector3(-10.75, plat_y + 0.55, -17.5), Vector3(0.1, 1.1, 5.6), 0.0, "TowerRailE")
	_add_box_collider(lv, Vector3(-13.5, plat_y + 0.55, -20.25), Vector3(5.6, 1.1, 0.1), 0.0, "TowerRailFar")
	_add_box_collider(lv, Vector3(-13.5, plat_y + 0.55, -14.75), Vector3(5.6, 1.1, 0.1), 0.0, "TowerRailNear")

# ---------- street props ----------

func _add_street_props() -> void:
	var props := Node3D.new()
	props.name = "StreetProps"
	root.add_child(props)
	props.owner = root
	var n := 0
	# wagon mid-street west as cover
	var wy := height_at(-13.0, 2.0)
	var wagon := _instance_prop(WA + "Wooden_Wagon.glb", Vector3(-13.0, wy, 2.0), 0.5, 1.0, props, "Wagon")
	var wab := _combined_aabb(wagon)
	_add_box_collider(props, Vector3(-13.0, wy + wab.size.y / 2.0, 2.0), Vector3(wab.size.x, wab.size.y, wab.size.z), 0.5, "WagonCol")
	# crates + barrels near porches
	var cover := [
		[WA + "Crate_Stack.glb", 12.0, -5.5, 1.0], [WA + "Wooden_Barrel.glb", 14.2, -5.2, 1.0],
		[WA + "Crate_Stack.glb", -3.0, 6.0, 0.9], [WA + "Wooden_Barrel.glb", -1.2, 6.3, 1.0],
		[WA + "Wooden_Barrel.glb", 5.5, -6.0, 1.0], [A + "HayBale_Stack.glb", 18.0, 5.5, 1.0],
		[A + "HayBale_Single.glb", -20.0, 5.0, 1.1], [A + "HayBale_Stack.glb", -9.0, -6.2, 0.9],
	]
	for c in cover:
		var y := height_at(c[1], c[2])
		var p := _instance_prop(c[0], Vector3(c[1], y, c[2]), rng.randf_range(0, TAU), c[3], props, "Cover%d" % n)
		var ab := _combined_aabb(p)
		var sz: Vector3 = ab.size * float(c[3])
		_add_box_collider(props, Vector3(c[1], y + sz.y / 2.0, c[2]), Vector3(maxf(sz.x, 0.6), sz.y, maxf(sz.z, 0.6)), 0.0, "CoverCol%d" % n)
		n += 1
	# hitching posts + troughs along the storefront line
	for hx in [-16.0, -5.0, 9.0, 16.5]:
		for side in [-1.0, 1.0]:
			var z: float = side * 6.8
			var y := height_at(hx, z)
			_instance_prop(A + "HitchingPost.glb", Vector3(hx, y, z), 0.0 if side < 0 else PI, 1.0, props, "Hitch%d" % n)
			n += 1
	for t in [[-11.0, -6.6], [6.0, 6.6]]:
		var y := height_at(t[0], t[1])
		_instance_prop(A + "Trough.glb", Vector3(t[0], y, t[1]), 0.0, 1.0, props, "Trough%d" % n)
		_add_box_collider(props, Vector3(t[0], y + 0.25, t[1]), Vector3(1.8, 0.5, 0.7), 0.0, "TroughCol%d" % n)
		n += 1
	# porch lanterns: warm emissive cube + omni light at storefront corners
	var lantern_mesh := BoxMesh.new()
	lantern_mesh.size = Vector3(0.16, 0.22, 0.16)
	var lm2 := StandardMaterial3D.new()
	lm2.albedo_color = Color(1.0, 0.75, 0.35)
	lm2.emission_enabled = true
	lm2.emission = Color(1.0, 0.62, 0.25)
	lm2.emission_energy_multiplier = 2.6
	lantern_mesh.material = lm2
	var li := 0
	for lx in [-18.0, -1.5, 7.0, 15.5, -8.0, 11.5]:
		var side: float = -1.0 if li < 4 else 1.0
		var z := side * 5.9
		var y := height_at(lx, z) + 2.5
		var mi := MeshInstance3D.new()
		mi.name = "Lantern%d" % li
		mi.mesh = lantern_mesh
		mi.position = Vector3(lx, y, z)
		props.add_child(mi)
		mi.owner = root
		var ol := OmniLight3D.new()
		ol.name = "LanternLight%d" % li
		ol.light_color = Color(1.0, 0.62, 0.28)
		ol.light_energy = 1.1
		ol.omni_range = 6.5
		ol.light_volumetric_fog_energy = 1.6
		ol.shadow_enabled = false
		ol.position = Vector3(lx, y - 0.15, z)
		props.add_child(ol)
		ol.owner = root
		li += 1

# ---------- scrub scatter ----------

func _add_scrub_scatter() -> void:
	var scrub := Node3D.new()
	scrub.name = "Scrub"
	root.add_child(scrub)
	scrub.owner = root
	# [path, count, collide, target_height_m] - source cacti are wildly oversized,
	# so normalize each model to a real-world height via its measured AABB
	var defs := [
		[WA + "Cactus.glb", 8, true, 4.0], [WA + "Barrel cactus.glb", 7, false, 0.9],
		[WA + "Pipe-organ-cactus.glb", 6, true, 3.0],
		[A + "SandRock_A.glb", 8, true, 0.0], [A + "SandRock_B.glb", 6, true, 0.0],
	]
	var n := 0
	for def in defs:
		var base_scale := 1.0
		if def[3] > 0.0:
			var probe: Node3D = (load(def[0]) as PackedScene).instantiate()
			var pab := _combined_aabb(probe)
			probe.free()
			base_scale = float(def[3]) / maxf(pab.size.y, 0.01)
			print("%s raw height %.1f -> base scale %.3f" % [def[0].get_file(), pab.size.y, base_scale])
		for i in def[1]:
			var ang := rng.randf_range(0, TAU)
			var rn := sqrt(rng.randf_range(0.3, 0.78))
			var x := cos(ang) * HALF_X * rn
			var z := sin(ang) * HALF_Z * rn
			if absf(z) < STREET_HALF + 4.0:
				continue  # keep the town band clear
			var y := height_at(x, z)
			var s: float = base_scale * rng.randf_range(0.8, 1.3)
			_instance_prop(def[0], Vector3(x, y - 0.03, z), rng.randf_range(0, TAU), s, scrub, "Scrub%d" % n)
			if def[2]:
				var ch: float = (float(def[3]) if def[3] > 0.0 else 1.2) * 1.05
				_add_box_collider(scrub, Vector3(x, y + ch / 2.0, z), Vector3(0.7, ch, 0.7), 0.0, "ScrubCol%d" % n)
			n += 1

# ---------- perimeter ----------

func _add_perimeter_walls() -> void:
	var walls := Node3D.new()
	walls.name = "BoundaryWalls"
	root.add_child(walls)
	walls.owner = root
	var segs := 20
	for i in segs:
		var ang := (i + 0.5) * TAU / segs
		var x := cos(ang) * HALF_X
		var z := sin(ang) * HALF_Z
		var y := height_at(x * 0.95, z * 0.95)
		var seg_len := TAU * (HALF_X + HALF_Z) / 2.0 / segs * 1.35
		# align the wall's length with the ellipse TANGENT (second arg must be
		# negated - the old formula made every wall a radial spike into the map)
		var facing := atan2(-x / (HALF_X * HALF_X), -z / (HALF_Z * HALF_Z))
		_add_box_collider(walls, Vector3(x, y + 6.0, z), Vector3(seg_len, 14.0, 1.0), facing, "Wall%d" % i)

# ---------- atmosphere ----------

func _add_atmosphere() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.10, 0.28)
	sky_mat.sky_horizon_color = Color(0.92, 0.44, 0.20)
	sky_mat.ground_bottom_color = Color(0.12, 0.07, 0.05)
	sky_mat.ground_horizon_color = Color(0.80, 0.42, 0.22)
	sky_mat.sun_angle_max = 25.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.25
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.82, 0.55, 0.34)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.15
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.95, 0.75, 0.55)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 90.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)
	we.owner = root
	var sun := DirectionalLight3D.new()
	sun.name = "SunsetSun"
	sun.light_color = Color(1.0, 0.68, 0.42)
	sun.light_energy = 1.15
	sun.light_volumetric_fog_energy = 1.4
	sun.shadow_enabled = true
	# low in the west, warm rake down the street
	sun.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-13), deg_to_rad(-84), 0)), Vector3(0, 18, 0))
	root.add_child(sun)
	sun.owner = root

func _add_dust() -> void:
	var dust := GPUParticles3D.new()
	dust.name = "DriftingDust"
	dust.amount = 110
	dust.lifetime = 14.0
	dust.preprocess = 14.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.85, 0.70, 0.45, 0.35)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = m
	dust.draw_pass_1 = mesh
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 1.2, 22)
	pm.direction = Vector3(1, 0.05, 0.15)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.7
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.25
	dust.process_material = pm
	dust.position = Vector3(0, 1.4, 0)
	root.add_child(dust)
	dust.owner = root

func _add_vultures() -> void:
	var flock := Node3D.new()
	flock.name = "Vultures"
	flock.set_script(load("res://bird_flock.gd"))
	flock.set("bird_scene_path", "res://models/forestAssets/Bird.glb")
	flock.set("bird_count", 3)
	flock.set("min_height", 20.0)
	flock.set("max_height", 27.0)
	root.add_child(flock)
	flock.owner = root

func _add_tumbleweeds() -> void:
	var spawner := Node3D.new()
	spawner.name = "TumbleweedSpawner"
	spawner.set_script(load("res://tumbleweed_spawner.gd"))
	spawner.set("tumbleweed_scene", load("res://tumbleweed.tscn"))
	spawner.set("max_active", 3)
	spawner.set("map_half", 22.0)
	root.add_child(spawner)
	spawner.owner = root

# ---------- spawns / gameplay ----------

func _add_spawn_points() -> void:
	# USER RULE: spawn markers are hand-placed in the editor. If the map file
	# already exists, carry its SpawnPoints subtree over verbatim - never
	# regenerate/reposition them. Initial generation happens only once.
	if _preserve_existing_spawn_points():
		return
	var sp := Node3D.new()
	sp.name = "SpawnPoints"
	root.add_child(sp)
	sp.owner = root
	for i in 8:
		var ang := i * TAU / 8.0 + 0.39
		var x := cos(ang) * HALF_X * 0.72
		var z := sin(ang) * HALF_Z * 0.72
		var y := height_at(x, z)
		var m := Marker3D.new()
		m.name = "SpawnPoint%d" % i
		m.add_to_group("spawn_point", true)
		m.transform = Transform3D(Basis(Vector3.UP, atan2(-x, -z)), Vector3(x, y + 1.5, z))
		sp.add_child(m)
		m.owner = root

func _preserve_existing_spawn_points() -> bool:
	if not ResourceLoader.exists(OUT_PATH):
		return false
	var old_scene = (load(OUT_PATH) as PackedScene).instantiate()
	var old_sp = old_scene.get_node_or_null("SpawnPoints")
	if old_sp == null:
		old_scene.free()
		return false
	old_scene.remove_child(old_sp)
	old_scene.free()
	root.add_child(old_sp)
	old_sp.owner = root
	for m in old_sp.get_children():
		m.owner = root
		if m.is_in_group("spawn_point"):
			m.remove_from_group("spawn_point")
		m.add_to_group("spawn_point", true)
	print("SpawnPoints preserved from existing map (%d markers)" % old_sp.get_child_count())
	return true
	var gun_marker := Marker3D.new()
	gun_marker.name = "gun_spawn_point"
	gun_marker.add_to_group("gun_spawn_point", true)
	gun_marker.position = Vector3(0, height_at(0, 0) + 0.8, 0)
	root.add_child(gun_marker)
	gun_marker.owner = root

func _add_gameplay_scaffolding() -> void:
	var src = (load("res://node_3d.tscn") as PackedScene).instantiate()
	var wanted := ["CanvasLayer", "SplitScreenLayer", "RoundManager", "player1", "player2", "Gun", "MeleeWeapon", "powerup", "powerup2", "item", "item2", "grenade"]
	var melee_done := false
	for child in src.get_children():
		if not (child.name in wanted):
			continue
		if child.name == "MeleeWeapon" and melee_done:
			continue
		var dup = child.duplicate()
		root.add_child(dup)
		_own_shallow(dup)
		if child.name == "MeleeWeapon":
			melee_done = true
	src.free()
	# gun: dead center of main street - high-noon duel
	var gun = root.get_node_or_null("Gun")
	if gun:
		gun.position = Vector3(0, height_at(0, 0) + 0.55, 0)
	var melee = root.get_node_or_null("MeleeWeapon")
	if melee:
		melee.position = Vector3(-23.5, height_at(-23.5, 0) + 0.6, 0)  # church steps
	var positions := {
		"item": Vector3(-16.5, 0, -21), "item2": Vector3(13, 0, 19),
		"grenade": Vector3(27, 0, 4), "powerup": Vector3(-13, 0, 2),
		"powerup2": Vector3(14, 0, 16),
	}
	for key in positions:
		var node = root.get_node_or_null(key)
		if node:
			var p: Vector3 = positions[key]
			node.position = Vector3(p.x, height_at(p.x, p.z) + (0.8 if key.begins_with("powerup") else 0.5), p.z)
	print("Scaffolding: rm=%s p1=%s gun=%s" % [root.get_node_or_null("RoundManager") != null, root.get_node_or_null("player1") != null, gun != null])

func _bake_navmesh() -> void:
	var nav_mesh := NavigationMesh.new()
	# 0.45 (not 0.6): recast erodes in whole cells, and the tower ring corridor
	# (1.48m) needs erosion under 0.5m/side to survive
	nav_mesh.agent_radius = 0.45
	nav_mesh.agent_height = 2.5
	nav_mesh.agent_max_climb = 0.7
	nav_mesh.agent_max_slope = 48.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, root)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	print("Navmesh polygons: ", nav_mesh.get_polygon_count())
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	region.navigation_mesh = nav_mesh
	root.add_child(region)
	region.owner = root
