extends Node
# Temporary autoload: builds maps/test/CityMap.tscn ("Maple & 3rd").
# Suburban-NY city block: cross streets + ring road, enterable corner store /
# diner / brownstone-with-roof, park corner, live traffic, midday sky.

const OUT_PATH := "res://maps/test/CityMap.tscn"
const A := "res://models/cityAssets/"
const F := "res://models/forestAssets/"

const HALF_X := 38.0
const HALF_Z := 27.0

var root: Node3D

func _ready() -> void:
	_build()
	get_tree().quit()

func _build() -> void:
	root = Node3D.new()
	root.name = "CityMap"
	_add_ground_and_markings()
	_add_boundary()
	_add_corner_store()
	_add_diner()
	_add_brownstones()
	_add_perimeter_facades()
	_add_park()
	_add_street_furniture()
	_add_traffic()
	_add_effects()
	_add_atmosphere()
	add_child(root)
	_bake_navmesh()
	remove_child(root)
	_add_spawn_points()
	_add_gameplay_scaffolding()
	var packed := PackedScene.new()
	print("PACK: ", packed.pack(root))
	print("SAVE: ", ResourceSaver.save(packed, OUT_PATH))

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

func _add_marking(parent: Node3D, pos: Vector3, size: Vector3, color: Color, yrot: float, mname: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = mname
	var mesh := BoxMesh.new()
	mesh.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	mesh.material = m
	mi.mesh = mesh
	mi.transform = Transform3D(Basis(Vector3.UP, yrot), pos)
	parent.add_child(mi)
	mi.owner = root

# ---------- ground / roads ----------

func _add_ground_and_markings() -> void:
	var g: Node3D = (load(A + "CityGround.glb") as PackedScene).instantiate()
	g.name = "Ground"
	root.add_child(g)
	g.owner = root
	_add_box_collider(root, Vector3(0, -0.5, 0), Vector3(HALF_X * 2, 1.0, HALF_Z * 2), 0.0, "GroundBody")
	var marks := Node3D.new()
	marks.name = "RoadMarkings"
	root.add_child(marks)
	marks.owner = root
	var yellow := Color(0.85, 0.75, 0.25)
	var white := Color(0.85, 0.85, 0.82)
	var mi := 0
	# center dashes on the two cross streets
	for d in range(-30, 31, 4):
		if absf(float(d)) > 5.5:
			_add_marking(marks, Vector3(d, 0.02, 0), Vector3(1.6, 0.02, 0.14), yellow, 0.0, "Dash%d" % mi)
			mi += 1
	for d in range(-22, 23, 4):
		if absf(float(d)) > 5.5:
			_add_marking(marks, Vector3(0, 0.02, d), Vector3(0.14, 0.02, 1.6), yellow, 0.0, "Dash%d" % mi)
			mi += 1
	# crosswalk stripes at the intersection (4 sides)
	for side in [[-5.1, true], [5.1, true], [-5.1, false], [5.1, false]]:
		for s in 5:
			var off := -3.0 + s * 1.5
			if side[1]:
				_add_marking(marks, Vector3(off, 0.02, side[0]), Vector3(0.7, 0.02, 1.1), white, 0.0, "Cross%d_%d" % [mi, s])
			else:
				_add_marking(marks, Vector3(side[0], 0.02, off), Vector3(1.1, 0.02, 0.7), white, 0.0, "Cross%d_%d" % [mi, s])
		mi += 1
	# curbs along the cross streets (0.12 high - auto step-up)
	var curbs := Node3D.new()
	curbs.name = "Curbs"
	root.add_child(curbs)
	curbs.owner = root
	var ci := 0
	for cx in [-4.6, 4.6]:
		for seg in [[-25.0, -5.6], [5.6, 25.0]]:
			var mid: float = (seg[0] + seg[1]) / 2.0
			var length: float = seg[1] - seg[0]
			_add_box_collider(curbs, Vector3(cx, 0.06, mid), Vector3(0.25, 0.12, length), 0.0, "CurbNS%d" % ci)
			_add_marking(curbs, Vector3(cx, 0.07, mid), Vector3(0.25, 0.12, length), Color(0.62, 0.61, 0.58), 0.0, "CurbNSV%d" % ci)
			ci += 1
	for cz in [-4.6, 4.6]:
		for seg in [[-31.0, -5.6], [5.6, 31.0]]:
			var mid: float = (seg[0] + seg[1]) / 2.0
			var length: float = seg[1] - seg[0]
			_add_box_collider(curbs, Vector3(mid, 0.06, cz), Vector3(length, 0.12, 0.25), 0.0, "CurbEW%d" % ci)
			_add_marking(curbs, Vector3(mid, 0.07, cz), Vector3(length, 0.12, 0.25), Color(0.62, 0.61, 0.58), 0.0, "CurbEWV%d" % ci)
			ci += 1

func _add_boundary() -> void:
	var walls := Node3D.new()
	walls.name = "BoundaryWalls"
	root.add_child(walls)
	walls.owner = root
	_add_box_collider(walls, Vector3(0, 8, -HALF_Z), Vector3(HALF_X * 2, 16, 1), 0.0, "WallN")
	_add_box_collider(walls, Vector3(0, 8, HALF_Z), Vector3(HALF_X * 2, 16, 1), 0.0, "WallS")
	_add_box_collider(walls, Vector3(-HALF_X, 8, 0), Vector3(1, 16, HALF_Z * 2), 0.0, "WallW")
	_add_box_collider(walls, Vector3(HALF_X, 8, 0), Vector3(1, 16, HALF_Z * 2), 0.0, "WallE")

# ---------- enterable buildings ----------
# Wall-with-door collider helper: builds per-segment boxes in LOCAL space
# (front = -Z local after PI rotation handling), then rotates around pos.

func _wall_segments(parent: Node3D, pos: Vector3, yrot: float, W: float, D: float, H: float, doors: Dictionary, cname: String) -> void:
	# doors: {"front": door_center_x or null, "side_x": door_center_z or null}
	var T := 0.15
	# collider openings slightly wider/taller than the 1.8x2.6 visual door so
	# navmesh clearance (2.5 agent height, cell-quantized) passes comfortably
	var dw := 1.1
	var lintel := 2.9
	var segs := []  # [local_center, local_half]
	if doors.has("front"):
		var dx: float = doors["front"]
		segs.append([Vector3((-W + (dx - dw)) / 2.0, H / 2.0, -D + T), Vector3((dx - dw + W) / 2.0, H / 2.0, T)])
		segs.append([Vector3((dx + dw + W) / 2.0, H / 2.0, -D + T), Vector3((W - dx - dw) / 2.0, H / 2.0, T)])
		segs.append([Vector3(dx, (lintel + H) / 2.0, -D + T), Vector3(dw, (H - lintel) / 2.0, T)])
	else:
		segs.append([Vector3(0, H / 2.0, -D + T), Vector3(W, H / 2.0, T)])
	# back wall
	segs.append([Vector3(0, H / 2.0, D - T), Vector3(W, H / 2.0, T)])
	# -X wall
	segs.append([Vector3(-W + T, H / 2.0, 0), Vector3(T, H / 2.0, D)])
	# +X wall (optional side door at local z dz)
	if doors.has("side_x"):
		var dz: float = doors["side_x"]
		segs.append([Vector3(W - T, H / 2.0, (-D + (dz - dw)) / 2.0), Vector3(T, H / 2.0, (dz - dw + D) / 2.0)])
		segs.append([Vector3(W - T, H / 2.0, (dz + dw + D) / 2.0), Vector3(T, H / 2.0, (D - dz - dw) / 2.0)])
		segs.append([Vector3(W - T, (lintel + H) / 2.0, dz), Vector3(T, (H - lintel) / 2.0, dw)])
	else:
		segs.append([Vector3(W - T, H / 2.0, 0), Vector3(T, H / 2.0, D)])
	var basis := Basis(Vector3.UP, yrot)
	var i := 0
	for s in segs:
		var world_c: Vector3 = pos + basis * s[0]
		_add_box_collider(parent, world_c, s[1] * 2.0, yrot, "%s_w%d" % [cname, i])
		i += 1

func _add_corner_store() -> void:
	var b := Node3D.new()
	b.name = "CornerStoreBlock"
	root.add_child(b)
	b.owner = root
	var pos := Vector3(-11.0, 0, -10.5)
	_instance_prop(A + "CornerStore.glb", pos, 0.0, 1.0, b, "CornerStore")
	# blender front(-Y) -> godot +Z; store faces the E-W road (south) so front
	# local -Z must map to world +Z => the glb import already flips: local -D is
	# blender -Y... empirically fronts face +Z with yrot 0 (western pattern), so
	# door local z is at +D side; use yrot PI on colliders frame to match: front
	# collider frame: local -Z = world -Z at yrot 0. Buildings north of the road
	# face +Z (south), which is local +... use yrot PI for the collider frame.
	_wall_segments(b, pos, PI, 5.0, 4.0, 4.5, {"front": 2.2, "side_x": 1.0}, "StoreCol")
	# roof + interior colliders
	_add_box_collider(b, pos + Vector3(0, 4.56, 0), Vector3(10, 0.24, 8), 0.0, "StoreRoof")
	_add_box_collider(b, pos + Vector3(3.9, 0.55, 0.4 * -1), Vector3(0.9, 1.1, 3.2), 0.0, "StoreCounter")
	for i in 2:
		var sy: float = [1.6, -1.9][i]
		_add_box_collider(b, pos + Vector3(-1.0, 0.75, sy), Vector3(3.2, 1.5, 0.56), 0.0, "StoreShelf%d" % i)

func _add_diner() -> void:
	var b := Node3D.new()
	b.name = "DinerBlock"
	root.add_child(b)
	b.owner = root
	var pos := Vector3(9.5, 0, 10.5)
	_instance_prop(A + "Diner.glb", pos, PI, 1.0, b, "Diner")
	_wall_segments(b, pos, 0.0, 5.5, 3.5, 4.0, {"front": 0.0}, "DinerCol")
	_add_box_collider(b, pos + Vector3(0, 4.06, 0), Vector3(11, 0.24, 7), 0.0, "DinerRoof")
	_add_box_collider(b, pos + Vector3(-0.5, 0.55, -2.4 * -1), Vector3(5.2, 1.1, 0.9), 0.0, "DinerCounter")
	for i in 3:
		var by: float = [-1.6, 0.0, 1.6][i]
		_add_box_collider(b, pos + Vector3(4.6, 0.5, -by), Vector3(1.1, 1.0, 0.44), 0.0, "DinerBooth%d" % i)
		_add_box_collider(b, pos + Vector3(3.6, 0.48, -by), Vector3(0.76, 0.12, 1.0), 0.0, "DinerTable%d" % i)

func _add_brownstones() -> void:
	var b := Node3D.new()
	b.name = "BrownstoneRow"
	root.add_child(b)
	b.owner = root
	# NE quadrant, fronts facing the E-W road (facing -Z... north row faces +Z)
	var epos := Vector3(9.0, 0, -10.5)
	_instance_prop(A + "Brownstone_Enterable.glb", epos, 0.0, 1.0, b, "BrownstoneMain")
	var apos := Vector3(18.0, 0, -10.5)
	_instance_prop(A + "Brownstone_A.glb", apos, 0.0, 1.0, b, "BrownstoneA")
	_add_box_collider(b, apos + Vector3(0, 3.5, 0), Vector3(8, 7.0, 9), 0.0, "BrownACol")
	var bpos := Vector3(-20.0, 0, -10.5)
	_instance_prop(A + "Brownstone_B.glb", bpos, 0.0, 1.0, b, "BrownstoneB")
	_add_box_collider(b, bpos + Vector3(0, 4.5, 0), Vector3(8, 9.0, 9), 0.0, "BrownBCol")
	# enterable: wall colliders with the front door (raised - stoop) at local x +1.4
	var W := 4.0
	var D := 4.5
	var H := 8.0
	var T := 0.15
	var dw := 1.1
	# blender x -> godot x unchanged; blender y -> godot z NEGATED. The visual
	# front (door/stoop) faces +Z world, so the door gap lives on the +D side.
	var dx := 1.4
	_add_box_collider(b, epos + Vector3((-W + (dx - dw)) / 2.0, H / 2.0, D - T), Vector3(dx - dw + W, H, T * 2), 0.0, "BSCol_f0")
	_add_box_collider(b, epos + Vector3((dx + dw + W) / 2.0, H / 2.0, D - T), Vector3(W - dx - dw, H, T * 2), 0.0, "BSCol_f1")
	_add_box_collider(b, epos + Vector3(dx, 0.375, D - T), Vector3(dw * 2, 0.75, T * 2), 0.0, "BSCol_f2")
	_add_box_collider(b, epos + Vector3(dx, (3.65 + H) / 2.0, D - T), Vector3(dw * 2, H - 3.65, T * 2), 0.0, "BSCol_f3")
	_add_box_collider(b, epos + Vector3(0, H / 2.0, -D + T), Vector3(W * 2, H, T * 2), 0.0, "BSCol_back")
	_add_box_collider(b, epos + Vector3(-W + T, H / 2.0, 0), Vector3(T * 2, H, D * 2), 0.0, "BSCol_wx")
	_add_box_collider(b, epos + Vector3(W - T, H / 2.0, 0), Vector3(T * 2, H, D * 2), 0.0, "BSCol_ex")
	# stoop steps out front (+Z side; 0.25 rises, tops 0.25/0.50/0.75 = door sill)
	for i in 3:
		var step_top := 0.25 * (i + 1)
		_add_box_collider(b, epos + Vector3(dx, step_top / 2.0, D + 0.55 - i * 0.35), Vector3(2.4, step_top, 1.1 - i * 0.34), 0.0, "BSStoop%d" % i)
	# ground floor slab + interior stair steps (0.5 rises) + landing + roof strips
	_add_box_collider(b, epos + Vector3(0.6, 0.06, 0), Vector3((W - 0.75) * 2, 0.12, D * 2), 0.0, "BSFloor")
	# inner half-step below the raised door sill: splits the 0.63m drop so the
	# cell-quantized descent stays under the 0.7 nav climb limit both ways
	_add_box_collider(b, epos + Vector3(dx, 0.2, D - 0.5), Vector3(2.2, 0.4, 0.44), 0.0, "BSInnerStep")
	var steps := 8
	for i in steps:
		var t := float(i) / steps
		# flight A at godot x -2.6, running z +2.4 -> -1.2 while rising to H/2
		var top_a: float = (i + 1) * (H / 2.0 / steps)
		_add_box_collider(b, epos + Vector3(-2.6, top_a - maxf(top_a, 0.4) / 2.0, 2.4 - t * 3.6), Vector3(1.4, maxf(top_a, 0.4), 3.6 / steps + 0.06), 0.0, "BSStepA%d" % i)
		# flight B at godot x -1.1, running z -1.4 -> +2.0 rising H/2 -> H
		var top_b: float = H / 2.0 + (i + 1) * (H / 2.0 / steps)
		_add_box_collider(b, epos + Vector3(-1.1, H / 2.0 + (top_b - H / 2.0) / 2.0, -1.4 + t * 3.4), Vector3(1.5, top_b - H / 2.0, 3.4 / steps + 0.06), 0.0, "BSStepB%d" % i)
	# wide switchback landing spanning BOTH stair columns (narrow landings lose
	# nav connectivity to agent-radius erosion at the turn)
	_add_box_collider(b, epos + Vector3(-1.8, H / 2.0 - 0.1, -2.0), Vector3(3.0, 0.2, 1.5), 0.0, "BSLanding")
	# roof strips around the hatch (godot hatch: x -2.0..-0.2, z -1.2..+2.2)
	_add_box_collider(b, epos + Vector3(-3.0, H + 0.1, 0), Vector3(2.0, 0.2, D * 2), 0.0, "BSRoof0")
	_add_box_collider(b, epos + Vector3(1.9, H + 0.1, 0), Vector3(4.2, 0.2, D * 2), 0.0, "BSRoof1")
	# Roof2 extended to z 1.85 so the top step (ends z 1.81, top 8.0) meets it
	# with a 0.2 step up - never hovering over the stair headroom
	_add_box_collider(b, epos + Vector3(-1.1, H + 0.1, (1.85 + D) / 2.0), Vector3(1.8, 0.2, D - 1.85), 0.0, "BSRoof2")
	_add_box_collider(b, epos + Vector3(-1.1, H + 0.1, (-D - 2.0) / 2.0), Vector3(1.8, 0.2, D - 2.0), 0.0, "BSRoof3")
	# roof parapet ring
	for p in [[0.0, -D + 0.07, W, 0.07], [0.0, D - 0.07, W, 0.07]]:
		_add_box_collider(b, epos + Vector3(p[0], H + 0.55, p[1]), Vector3(p[2] * 2, 0.9, p[3] * 2), 0.0, "BSPar%d" % int(p[1] * 10))
	_add_box_collider(b, epos + Vector3(-W + 0.07, H + 0.55, 0), Vector3(0.14, 0.9, D * 2), 0.0, "BSParW")
	_add_box_collider(b, epos + Vector3(W - 0.07, H + 0.55, 0), Vector3(0.14, 0.9, D * 2), 0.0, "BSParE")

func _add_perimeter_facades() -> void:
	var per := Node3D.new()
	per.name = "PerimeterFacades"
	root.add_child(per)
	per.owner = root
	var north := [["Facade_Tall.glb", -30.0], ["Facade_Mid_A.glb", -20.0], ["Facade_Short.glb", -10.0], ["Facade_Mid_B.glb", 0.0], ["Facade_Tall.glb", 9.0], ["Facade_Mid_A.glb", 19.0], ["Facade_Short.glb", 29.0]]
	var fi := 0
	for f in north:
		# north edge row faces south (+Z): yrot 0; south edge row faces north: yrot PI
		var n1 := _instance_prop(A + f[0], Vector3(f[1], 0, -HALF_Z + 2.6), 0.0, 1.0, per, "FacN%d" % fi)
		_add_box_collider(per, Vector3(f[1], 5.0, -HALF_Z + 2.6), Vector3(9.5, 14.0, 5.0), 0.0, "FacNCol%d" % fi)
		var n2 := _instance_prop(A + f[0], Vector3(-f[1], 0, HALF_Z - 2.6), PI, 1.0, per, "FacS%d" % fi)
		_add_box_collider(per, Vector3(-f[1], 5.0, HALF_Z - 2.6), Vector3(9.5, 14.0, 5.0), 0.0, "FacSCol%d" % fi)
		fi += 1
	for f in [["Facade_Mid_B.glb", -18.0], ["Facade_Short.glb", -8.0], ["Facade_Tall.glb", 2.0], ["Facade_Mid_A.glb", 12.0]]:
		var e1 := _instance_prop(A + f[0], Vector3(HALF_X - 2.6, 0, f[1]), PI / 2.0, 1.0, per, "FacE%d" % fi)
		_add_box_collider(per, Vector3(HALF_X - 2.6, 5.0, f[1]), Vector3(5.0, 14.0, 9.5), 0.0, "FacECol%d" % fi)
		var w1 := _instance_prop(A + f[0], Vector3(-HALF_X + 2.6, 0, -f[1]), -PI / 2.0, 1.0, per, "FacW%d" % fi)
		_add_box_collider(per, Vector3(-HALF_X + 2.6, 5.0, -f[1]), Vector3(5.0, 14.0, 9.5), 0.0, "FacWCol%d" % fi)
		fi += 1
	# distant skyline outside the walls
	var sky := [["Skyline_A.glb", -52, -48], ["Skyline_B.glb", -20, -55], ["Skyline_C.glb", 18, -52], ["Skyline_B.glb", 50, -46], ["Skyline_A.glb", 55, 20], ["Skyline_C.glb", -55, 25], ["Skyline_B.glb", 40, 48], ["Skyline_A.glb", -35, 50]]
	var si := 0
	for s in sky:
		_instance_prop(A + s[0], Vector3(s[1], -0.5, s[2]), (si * 0.7), 1.0, per, "Sky%d" % si)
		si += 1

func _add_park() -> void:
	var park := Node3D.new()
	park.name = "Park"
	root.add_child(park)
	park.owner = root
	# fences along north (z 4.7) and east (x -4.7) edges, gaps for entrances
	var pi2 := 0
	for fx in [-22.0, -19.5, -17.0, -12.0, -9.5, -7.0]:  # gap at ~-14.5
		_instance_prop(A + "ParkFence.glb", Vector3(fx, 0, 4.8), 0.0, 1.0, park, "FenceN%d" % pi2)
		_add_box_collider(park, Vector3(fx, 0.5, 4.8), Vector3(2.4, 1.0, 0.12), 0.0, "FenceNCol%d" % pi2)
		pi2 += 1
	for fz in [6.2, 8.6, 13.4, 15.8]:  # gap at ~11
		_instance_prop(A + "ParkFence.glb", Vector3(-4.9, 0, fz), PI / 2.0, 1.0, park, "FenceE%d" % pi2)
		_add_box_collider(park, Vector3(-4.9, 0.5, fz), Vector3(0.12, 1.0, 2.4), 0.0, "FenceECol%d" % pi2)
		pi2 += 1
	# trees / bushes / grass from the forest set
	var greens := [["Tree_Med_A.glb", -19, 8, 1.0], ["Tree_Med_B.glb", -9, 13, 1.1], ["Tree_Large_C.glb", -20, 13.5, 0.9], ["Sapling_A.glb", -13, 7, 1.0], ["Bush_A.glb", -16, 11, 1.2], ["Bush_B.glb", -7, 8.5, 1.0], ["Grass_A.glb", -11, 10, 1.2], ["Grass_C.glb", -18, 6.5, 1.2], ["Fern_A.glb", -21.5, 10.5, 1.0]]
	var gi := 0
	for g in greens:
		var n := _instance_prop(F + g[0], Vector3(g[1], 0, g[2]), float(gi) * 0.9, g[3], park, "Green%d" % gi)
		if g[0].begins_with("Tree"):
			_add_box_collider(park, Vector3(g[1], 1.5, g[2]), Vector3(0.7, 3.0, 0.7), 0.0, "TreeCol%d" % gi)
		gi += 1
	# benches + hoop on a small pad
	_instance_prop("res://models/environment/Bench_01_GLB.glb", Vector3(-15, 0, 9.5), 0.6, 1.0, park, "Bench1")
	_instance_prop("res://models/environment/Bench_01_GLB.glb", Vector3(-10.5, 0, 12.5), -1.2, 1.0, park, "Bench2")
	_add_marking(park, Vector3(-14.5, 0.03, 13.5), Vector3(5.0, 0.04, 4.0), Color(0.55, 0.54, 0.52), 0.0, "CourtPad")
	var hoop := _instance_prop(A + "BasketballHoop.glb", Vector3(-14.5, 0, 15.2), PI, 1.0, park, "Hoop")
	_add_box_collider(park, Vector3(-14.5, 1.7, 15.2), Vector3(0.25, 3.4, 0.25), 0.0, "HoopCol")

func _add_street_furniture() -> void:
	var sf := Node3D.new()
	sf.name = "StreetFurniture"
	root.add_child(sf)
	sf.owner = root
	var i := 0
	# lamp posts along the cross-street sidewalks
	for lp in [[-16.0, -5.6, 0.0], [8.0, -5.6, 0.0], [22.0, -5.6, 0.0], [-16.0, 5.6, PI], [16.0, 5.6, PI], [-5.6, -16.0, PI / 2.0], [-5.6, 14.0, PI / 2.0], [5.6, -14.0, -PI / 2.0], [5.6, 20.0, -PI / 2.0], [28.0, 5.6, PI]]:
		_instance_prop(A + "LampPost.glb", Vector3(lp[0], 0, lp[1]), lp[2], 1.0, sf, "Lamp%d" % i)
		_add_box_collider(sf, Vector3(lp[0], 2.2, lp[1]), Vector3(0.22, 4.4, 0.22), 0.0, "LampCol%d" % i)
		i += 1
	# hydrants: one normal, one bursting (effects added later at the same spot)
	for h in [[-6.2, -6.2], [20.0, 6.2]]:
		_instance_prop(A + "FireHydrant.glb", Vector3(h[0], 0, h[1]), 0.0, 1.0, sf, "Hydrant%d" % i)
		_add_box_collider(sf, Vector3(h[0], 0.4, h[1]), Vector3(0.4, 0.8, 0.4), 0.0, "HydrantCol%d" % i)
		i += 1
	# traffic lights at two intersection corners
	var tl1 := _instance_prop(A + "TrafficLight.glb", Vector3(5.6, 0, -5.6), PI, 1.0, sf, "TrafficLight1")
	tl1.set_script(load("res://traffic_light_cycle.gd"))
	var tl2 := _instance_prop(A + "TrafficLight.glb", Vector3(-5.6, 0, 5.6), 0.0, 1.0, sf, "TrafficLight2")
	tl2.set_script(load("res://traffic_light_cycle.gd"))
	tl2.set("green_time", 7.0)
	_add_box_collider(sf, Vector3(5.6, 2.4, -5.6), Vector3(0.24, 4.8, 0.24), 0.0, "TLCol1")
	_add_box_collider(sf, Vector3(-5.6, 2.4, 5.6), Vector3(0.24, 4.8, 0.24), 0.0, "TLCol2")
	# trash cans, mailbox, bus shelter, dumpsters, manholes
	for t in [[-7.0, -8.5], [7.2, 6.0], [24.0, -5.9], [-5.9, 18.0]]:
		_instance_prop(A + "TrashCan.glb", Vector3(t[0], 0, t[1]), float(i), 1.0, sf, "Trash%d" % i)
		_add_box_collider(sf, Vector3(t[0], 0.45, t[1]), Vector3(0.7, 0.9, 0.7), 0.0, "TrashCol%d" % i)
		i += 1
	_instance_prop(A + "Mailbox.glb", Vector3(-6.1, 0, 6.4), 0.4, 1.0, sf, "Mailbox")
	_add_box_collider(sf, Vector3(-6.1, 0.75, 6.4), Vector3(0.75, 1.5, 0.55), 0.4, "MailboxCol")
	var bus := _instance_prop(A + "BusShelter.glb", Vector3(17.0, 0, -5.8), 0.0, 1.0, sf, "BusShelter")
	_add_box_collider(sf, Vector3(17.0, 1.15, -5.4), Vector3(3.4, 2.3, 0.15), 0.0, "BusBackCol")
	for d in [[22.5, 14.5, 0.4], [-8.5, -14.6, -0.3]]:
		_instance_prop(A + "Dumpster.glb", Vector3(d[0], 0, d[1]), d[2], 1.0, sf, "Dumpster%d" % i)
		_add_box_collider(sf, Vector3(d[0], 0.7, d[1]), Vector3(2.3, 1.4, 1.4), d[2], "DumpCol%d" % i)
		i += 1
	for mh in [[1.8, 7.0], [-1.8, -12.0]]:
		_instance_prop(A + "Manhole.glb", Vector3(mh[0], 0.02, mh[1]), 0.0, 1.0, sf, "Manhole%d" % i)
		i += 1

# ---------- traffic ----------

func _add_traffic() -> void:
	var traffic := Node3D.new()
	traffic.name = "Traffic"
	root.add_child(traffic)
	traffic.owner = root
	# ring loop (centerline x +/-28, z +/-20), clockwise
	var ring: Array[Vector3] = [Vector3(28, 0, -20), Vector3(28, 0, 20), Vector3(-28, 0, 20), Vector3(-28, 0, -20)]
	var sedan := _instance_prop(A + "Car_Sedan.glb", ring[0], 0.0, 1.0, traffic, "CarSedan")
	sedan.set_script(load("res://car_traffic.gd"))
	sedan.set("waypoints", ring)
	sedan.set("speed", 7.5)
	var van_wps: Array[Vector3] = [Vector3(-28, 0, 20), Vector3(-28, 0, -20), Vector3(28, 0, -20), Vector3(28, 0, 20)]
	var van := _instance_prop(A + "Car_Van.glb", van_wps[0], 0.0, 1.0, traffic, "CarVan")
	van.set_script(load("res://car_traffic.gd"))
	van.set("waypoints", van_wps)
	van.set("speed", 6.2)
	# taxi cuts through the intersection on the N-S street
	var taxi_wps: Array[Vector3] = [Vector3(-1.8, 0, -20), Vector3(-1.8, 0, 20), Vector3(-28, 0, 20), Vector3(-28, 0, -20)]
	var taxi := _instance_prop(A + "Car_Taxi.glb", taxi_wps[0], 0.0, 1.0, traffic, "CarTaxi")
	taxi.set_script(load("res://car_traffic.gd"))
	taxi.set("waypoints", taxi_wps)
	taxi.set("speed", 8.0)
	taxi.set("traffic_light_path", NodePath("../../StreetFurniture/TrafficLight1"))
	taxi.set("stop_zone_center", Vector3(0, 0, 0))
	taxi.set("stop_zone_radius", 9.0)

# ---------- effects ----------

func _add_effects() -> void:
	var fx := Node3D.new()
	fx.name = "Effects"
	root.add_child(fx)
	fx.owner = root
	# bursting hydrant at (20, 6.2): water arc + mist + wet patch
	var jet := GPUParticles3D.new()
	jet.name = "HydrantJet"
	jet.amount = 110
	jet.lifetime = 1.1
	jet.preprocess = 1.1
	var jm := SphereMesh.new()
	jm.radius = 0.045
	jm.height = 0.09
	jm.radial_segments = 6
	jm.rings = 3
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.75, 0.88, 1.0, 0.85)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.emission_enabled = true
	wmat.emission = Color(0.5, 0.7, 0.9)
	wmat.emission_energy_multiplier = 0.4
	jm.material = wmat
	jet.draw_pass_1 = jm
	var jp := ParticleProcessMaterial.new()
	jp.direction = Vector3(0.55, 1.0, 0.2)
	jp.spread = 7.0
	jp.initial_velocity_min = 7.0
	jp.initial_velocity_max = 9.0
	jp.gravity = Vector3(0, -9.8, 0)
	jet.process_material = jp
	jet.position = Vector3(20.0, 0.65, 6.2)
	fx.add_child(jet)
	jet.owner = root
	_add_marking(fx, Vector3(21.6, 0.015, 6.6), Vector3(4.5, 0.01, 3.5), Color(0.16, 0.16, 0.19), 0.0, "WetPatch")
	# manhole steam
	var steam := GPUParticles3D.new()
	steam.name = "ManholeSteam"
	steam.amount = 26
	steam.lifetime = 3.2
	steam.preprocess = 3.2
	var sq := QuadMesh.new()
	sq.size = Vector2(0.7, 0.7)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.85, 0.85, 0.88, 0.16)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sq.material = smat
	steam.draw_pass_1 = sq
	var sp := ParticleProcessMaterial.new()
	sp.direction = Vector3(0, 1, 0)
	sp.spread = 10.0
	sp.initial_velocity_min = 0.5
	sp.initial_velocity_max = 0.9
	sp.gravity = Vector3(0.3, 0.2, 0)
	sp.scale_min = 0.6
	sp.scale_max = 1.6
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sp.emission_sphere_radius = 0.35
	steam.process_material = sp
	steam.position = Vector3(1.8, 0.1, 7.0)
	fx.add_child(steam)
	steam.owner = root
	# paper litter skittering down the E-W street
	var paper := GPUParticles3D.new()
	paper.name = "PaperLitter"
	paper.amount = 30
	paper.lifetime = 9.0
	paper.preprocess = 9.0
	var pq := QuadMesh.new()
	pq.size = Vector2(0.16, 0.12)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.9, 0.9, 0.86)
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pq.material = pmat
	paper.draw_pass_1 = pq
	var pp := ParticleProcessMaterial.new()
	pp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pp.emission_box_extents = Vector3(30, 0.2, 3.5)
	pp.direction = Vector3(1, 0.06, 0.1)
	pp.spread = 14.0
	pp.initial_velocity_min = 1.2
	pp.initial_velocity_max = 2.6
	pp.gravity = Vector3(0, -0.5, 0)
	pp.angle_min = 0
	pp.angle_max = 360
	pp.angular_velocity_min = 90
	pp.angular_velocity_max = 240
	pp.turbulence_enabled = true
	pp.turbulence_noise_strength = 0.6
	pp.turbulence_influence_min = 0.1
	pp.turbulence_influence_max = 0.3
	paper.process_material = pp
	paper.position = Vector3(0, 0.35, 0)
	fx.add_child(paper)
	paper.owner = root
	# clouds
	var clouds := Node3D.new()
	clouds.name = "Clouds"
	clouds.set_script(load("res://cloud_drift.gd"))
	root.add_child(clouds)
	clouds.owner = root
	var cdefs := [["Cloud_A.glb", -40, 46, -20, 1.0], ["Cloud_B.glb", 10, 55, -35, 1.3], ["Cloud_C.glb", 35, 48, 10, 0.9], ["Cloud_D.glb", -15, 60, 25, 1.5], ["Cloud_B.glb", 55, 52, 30, 1.0], ["Cloud_A.glb", -60, 50, 5, 1.2]]
	var ci := 0
	for c in cdefs:
		_instance_prop(A + c[0], Vector3(c[1], c[2], c[3]), float(ci) * 1.1, c[4], clouds, "Cloud%d" % ci)
		ci += 1
	# pigeons
	var pigeons := Node3D.new()
	pigeons.name = "Pigeons"
	pigeons.set_script(load("res://bird_flock.gd"))
	pigeons.set("bird_scene_path", "res://models/forestAssets/Bird.glb")
	pigeons.set("bird_count", 4)
	pigeons.set("min_height", 9.0)
	pigeons.set("max_height", 14.0)
	root.add_child(pigeons)
	pigeons.owner = root

func _add_atmosphere() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.45, 0.75)
	sky_mat.sky_horizon_color = Color(0.68, 0.78, 0.88)
	sky_mat.ground_bottom_color = Color(0.35, 0.35, 0.35)
	sky_mat.ground_horizon_color = Color(0.62, 0.70, 0.78)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.80, 0.88)
	env.fog_density = 0.0012
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)
	we.owner = root
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-55), deg_to_rad(35), 0)), Vector3(0, 30, 0))
	root.add_child(sun)
	sun.owner = root

# ---------- spawns / gameplay / navmesh ----------

func _add_spawn_points() -> void:
	# USER RULE: hand-placed markers are preserved on every rebuild.
	if _preserve_existing_spawn_points():
		return
	var sp := Node3D.new()
	sp.name = "SpawnPoints"
	root.add_child(sp)
	sp.owner = root
	# on/near the ring road, clear of the perimeter facade colliders
	var spots := [Vector3(30, 0, 0), Vector3(-30, 0, 0), Vector3(0, 0, 22), Vector3(0, 0, -22), Vector3(28, 0, 20), Vector3(-28, 0, -20), Vector3(28, 0, -20), Vector3(-28, 0, 20)]
	var i := 0
	for s in spots:
		var m := Marker3D.new()
		m.name = "SpawnPoint%d" % i
		m.add_to_group("spawn_point", true)
		m.transform = Transform3D(Basis(Vector3.UP, atan2(-s.x, -s.z)), Vector3(s.x, 1.5, s.z))
		sp.add_child(m)
		m.owner = root
		i += 1

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
	var gun = root.get_node_or_null("Gun")
	if gun:
		gun.position = Vector3(0, 0.55, 0)  # dead center of the intersection
	var melee = root.get_node_or_null("MeleeWeapon")
	if melee:
		melee.position = Vector3(-14.5, 0.6, 13.0)  # basketball court
	var positions := {
		"item": Vector3(-11.5, 0.5, -10.0),      # corner store interior
		"item2": Vector3(9.0, 0.5, 11.5),        # diner interior
		"grenade": Vector3(10.5, 8.7, -10.5),    # brownstone roof (reward)
		"powerup": Vector3(-17.0, 0.8, 9.0),     # park
		"powerup2": Vector3(17.0, 0.8, -6.5),    # bus shelter
	}
	for key in positions:
		var node = root.get_node_or_null(key)
		if node:
			node.position = positions[key]
	var gm := Marker3D.new()
	gm.name = "gun_spawn_point"
	gm.add_to_group("gun_spawn_point", true)
	gm.position = Vector3(0, 1.0, 0)
	root.add_child(gm)
	gm.owner = root
	print("Scaffolding: rm=%s p1=%s gun=%s" % [root.get_node_or_null("RoundManager") != null, root.get_node_or_null("player1") != null, gun != null])

func _bake_navmesh() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.45
	nav_mesh.agent_height = 2.5
	# 0.8 (not 0.7): the 0.5m interior stair rises quantize to 0.5-0.75 in
	# 0.25 cells and kept severing regions right at the 0.7 limit
	nav_mesh.agent_max_climb = 0.8
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
