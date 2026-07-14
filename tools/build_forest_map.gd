extends Node
# Temporary autoload: builds maps/test/ForestMap.tscn ("Whispering Woods").
# Run via temporary [autoload] entry + headless --quit, then remove.

const OUT_PATH := "res://maps/test/ForestMap.tscn"
const A := "res://models/forestAssets/"

var rng := RandomNumberGenerator.new()
var ground_faces: PackedVector3Array
var root: Node3D

# arena dims (must match gen_forest_assets.py make_ground)
const HALF_X := 32.0
const HALF_Y := 24.0   # becomes Z in Godot
const POND_RX := 7.5
const POND_RZ := 5.0

func _ready() -> void:
	rng.seed = 20260709
	_build()
	get_tree().quit()

func _build() -> void:
	root = Node3D.new()
	root.name = "ForestMap"

	_add_ground()
	_add_water()
	_add_bridge_and_gun_spawn()
	_add_perimeter()
	_add_landmarks()
	_add_groves_and_scatter()
	_add_atmosphere()
	_add_particles()
	_add_birds()
	_add_ambience_audio()
	_add_pond_splash()
	_add_shooting_stars()
	# bake BEFORE gameplay scaffolding is added: collider parsing needs the root
	# in-tree, and we must not let RoundManager/player _ready() run during build
	add_child(root)
	_bake_navmesh()
	remove_child(root)
	_add_spawn_points()
	_add_gameplay_scaffolding()

	var packed := PackedScene.new()
	var err := packed.pack(root)
	print("PACK: ", err)
	err = ResourceSaver.save(packed, OUT_PATH)
	print("SAVE: ", err)

# ---------- terrain ----------

func _add_ground() -> void:
	var ps: PackedScene = load(A + "ForestGround.glb")
	var g: Node3D = ps.instantiate()
	g.name = "Ground"
	root.add_child(g)
	g.owner = root
	var mi := _first_mesh_instance(g)
	ground_faces = mi.mesh.get_faces()
	print("Ground faces: ", ground_faces.size() / 3)
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var col := CollisionShape3D.new()
	col.name = "GroundCol"
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(ground_faces)
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	body.owner = root
	col.owner = root

func height_at(x: float, z: float) -> float:
	# barycentric lookup over ground triangles (XZ plane)
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

# ---------- water ----------

func _add_water() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.05
	mesh.radial_segments = 48
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.10, 0.28, 0.42, 0.78)
	m.emission_enabled = true
	m.emission = Color(0.08, 0.30, 0.38)
	m.emission_energy_multiplier = 0.55
	m.metallic = 0.7
	m.roughness = 0.12
	mesh.material = m
	var mi := MeshInstance3D.new()
	mi.name = "PondWater"
	mi.mesh = mesh
	var bottom := height_at(0, 0)
	var water_y := bottom + 0.62
	mi.transform = Transform3D(Basis().scaled(Vector3(POND_RX * 0.97, 1, POND_RZ * 0.97)), Vector3(0, water_y, 0))
	root.add_child(mi)
	mi.owner = root
	print("Pond bottom %.2f water %.2f bank %.2f" % [bottom, water_y, height_at(0, POND_RZ + 1.0)])

# ---------- bridge ----------

func _add_bridge_and_gun_spawn() -> void:
	var ps: PackedScene = load(A + "Bridge.glb")
	var b: Node3D = ps.instantiate()
	b.name = "Bridge"
	var bank_y := maxf(height_at(0, POND_RZ + 0.6), height_at(0, -POND_RZ - 0.6))
	# span runs along X in the glb; rotate 90deg so it crosses the pond's narrow (Z) axis
	b.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0, bank_y + 0.02, 0))
	root.add_child(b)
	b.owner = root
	# 3 smooth sloped ramps (up / crown / down) - no step edges to snag on
	var span := 13.0
	var arch := 0.7
	var width := 4.2
	var bridge_cols := Node3D.new()
	bridge_cols.name = "BridgeColliders"
	root.add_child(bridge_cols)
	bridge_cols.owner = root
	var crown_y := bank_y + arch + 0.10
	var end_y := bank_y + 0.10
	var seg_z := span / 3.0
	var slope_ang := atan2(crown_y - end_y - 0.06, seg_z)
	var ramp_len := seg_z / cos(slope_ang) + 0.4
	_add_ramp_collider(bridge_cols, Vector3(0, (end_y + crown_y) / 2.0 - 0.11, -seg_z), Vector3(width - 0.2, 0.16, ramp_len), -slope_ang, "RampSouth")
	_add_box_collider(bridge_cols, Vector3(0, crown_y - 0.08, 0), Vector3(width - 0.2, 0.16, seg_z + 0.3), 0.0, "Crown")
	_add_ramp_collider(bridge_cols, Vector3(0, (end_y + crown_y) / 2.0 - 0.11, seg_z), Vector3(width - 0.2, 0.16, ramp_len), slope_ang, "RampNorth")
	# thin edge rails, raised off the deck so they never catch feet
	for side in [-1.0, 1.0]:
		for j in 3:
			var t := (j + 0.5) / 3.0
			var z := (t - 0.5) * span * 0.94
			var deck := sin(t * PI) * arch + 0.10 + bank_y
			_add_box_collider(bridge_cols, Vector3(side * (width / 2.0 - 0.05), deck + 0.78, z), Vector3(0.10, 1.05, span / 3.0), 0.0, "Rail%d_%d" % [j, (1 if side > 0 else 0)])
	# gun spawn: center of deck (arch peak + board)
	var deck_y := bank_y + arch + 0.16
	var gun_marker := Marker3D.new()
	gun_marker.name = "gun_spawn_point"
	gun_marker.add_to_group("gun_spawn_point", true)
	gun_marker.position = Vector3(0, deck_y + 0.45, 0)
	root.add_child(gun_marker)
	gun_marker.owner = root
	print("Bridge at y=%.2f deck=%.2f" % [bank_y, deck_y])

# ---------- placement helpers ----------

func _instance_prop(scene_path: String, pos: Vector3, yrot: float, scale: float, parent: Node3D, prop_name: String) -> Node3D:
	var ps: PackedScene = load(scene_path)
	var n: Node3D = ps.instantiate()
	n.name = prop_name
	var basis := Basis(Vector3.UP, yrot).scaled(Vector3(scale, scale, scale))
	n.transform = Transform3D(basis, pos)
	parent.add_child(n)
	_own(n)
	return n

func _own(n: Node) -> void:
	n.owner = root
	for c in n.get_children():
		if c.owner == null or c.owner != root:
			_own_shallow(c)

func _own_shallow(n: Node) -> void:
	n.owner = root
	# don't descend into instanced scenes' internals; they keep their own structure
	if n.scene_file_path != "":
		return
	for c in n.get_children():
		_own_shallow(c)

var _sway_cache := {}

func _apply_sway(prop: Node3D, height_ref: float) -> void:
	# Swap each surface's StandardMaterial3D for the wind_sway shader, keeping
	# its albedo. Materials are cached so identical ones are shared in the scene.
	var shader: Shader = load("res://wind_sway.gdshader")
	# overrides live on nodes inside the instanced glb; they only get packed
	# if the instance is flagged editable
	root.set_editable_instance(prop, true)
	for mi in _find_all_mesh_instances(prop):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var base := mesh.surface_get_material(si) as StandardMaterial3D
			if base == null:
				continue
			var key := "%s_%.2f" % [base.albedo_color.to_html(), height_ref]
			if not _sway_cache.has(key):
				var sm := ShaderMaterial.new()
				sm.shader = shader
				sm.set_shader_parameter("albedo_color", base.albedo_color)
				sm.set_shader_parameter("height_ref", height_ref)
				sm.set_shader_parameter("sway_strength", 0.05 if height_ref < 1.0 else 0.03)
				sm.set_shader_parameter("sway_speed", 1.6 if height_ref < 1.0 else 1.1)
				_sway_cache[key] = sm
			mi.set_surface_override_material(si, _sway_cache[key])

func _find_all_mesh_instances(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D:
		result.append(node)
	for c in node.get_children():
		result.append_array(_find_all_mesh_instances(c))
	return result

func _add_trunk_collider(parent: Node3D, pos: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "TrunkBody"
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	col.position = Vector3(pos.x, pos.y + height / 2.0, pos.z)
	body.add_child(col)
	parent.add_child(body)
	body.owner = root
	col.owner = root

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

func _oval_pos(r_norm: float, angle: float) -> Vector2:
	return Vector2(cos(angle) * HALF_X * r_norm, sin(angle) * HALF_Y * r_norm)

func _in_pond(x: float, z: float, margin: float) -> bool:
	return sqrt(pow(x / (POND_RX + margin), 2) + pow(z / (POND_RZ + margin), 2)) < 1.0

func _in_bridge_lane(x: float, z: float) -> bool:
	# keep the bridge approach lanes (north-south through center) clear
	return absf(x) < 3.5 and absf(z) < POND_RZ + 9.0

# ---------- perimeter ----------

func _add_perimeter() -> void:
	var trees := Node3D.new()
	trees.name = "PerimeterTrees"
	root.add_child(trees)
	trees.owner = root
	var variants := ["Tree_Large_A.glb", "Tree_Large_B.glb", "Tree_Large_C.glb", "Tree_Med_A.glb", "Tree_Med_B.glb"]
	var count := 46
	for i in count:
		var ang := i * TAU / count + rng.randf_range(-0.04, 0.04)
		var rn := rng.randf_range(0.86, 0.94)
		var p := _oval_pos(rn, ang)
		var y := height_at(p.x, p.y)
		var v: String = variants[i % variants.size()]
		var s := rng.randf_range(0.9, 1.3)
		_instance_prop(A + v, Vector3(p.x, y - 0.1, p.y), rng.randf_range(0, TAU), s, trees, "PTree%d" % i)
		if i % 2 == 0:
			_add_trunk_collider(trees, Vector3(p.x, y, p.y), 0.5 * s, 4.0)
	# invisible wall ring
	var walls := Node3D.new()
	walls.name = "BoundaryWalls"
	root.add_child(walls)
	walls.owner = root
	var segs := 20
	for i in segs:
		var ang := (i + 0.5) * TAU / segs
		var p := _oval_pos(1.0, ang)
		var y := height_at(p.x * 0.95, p.y * 0.95)
		var seg_len := TAU * (HALF_X + HALF_Y) / 2.0 / segs * 1.35
		# align with the ellipse TANGENT (negated second arg) - the old formula
		# produced radial wall spikes jutting into the map
		var facing := atan2(-p.x / (HALF_X * HALF_X), -p.y / (HALF_Y * HALF_Y))
		_add_box_collider(walls, Vector3(p.x, y + 6.0, p.y), Vector3(seg_len, 14.0, 1.0), facing, "Wall%d" % i)

# ---------- landmarks ----------

func _add_landmarks() -> void:
	var lm := Node3D.new()
	lm.name = "Landmarks"
	root.add_child(lm)
	lm.owner = root
	# two elder trees as opposing landmarks
	for data in [[-20.0, 9.0, "ElderWest"], [19.0, -10.0, "ElderEast"]]:
		var y := height_at(data[0], data[1])
		_instance_prop(A + "Tree_Elder.glb", Vector3(data[0], y - 0.15, data[1]), rng.randf_range(0, TAU), 1.0, lm, data[2])
		_add_trunk_collider(lm, Vector3(data[0], y, data[1]), 1.0, 5.0)
	# stone circle around the pond banks
	var stones := 7
	for i in stones:
		var ang := i * TAU / stones + 0.3
		var sx := cos(ang) * (POND_RX + 3.4)
		var sz := sin(ang) * (POND_RZ + 3.0)
		if _in_bridge_lane(sx, sz):
			continue
		var y := height_at(sx, sz)
		var v := "Standing_Stone_A.glb" if i % 2 == 0 else "Standing_Stone_B.glb"
		_instance_prop(A + v, Vector3(sx, y - 0.05, sz), ang + PI / 2.0, rng.randf_range(0.85, 1.15), lm, "Menhir%d" % i)
		_add_box_collider(lm, Vector3(sx, y + 1.4, sz), Vector3(1.3, 2.8, 0.9), ang + PI / 2.0, "MenhirCol%d" % i)
	# a lone bench facing the pond (existing asset)
	var by := height_at(11.5, 6.5)
	_instance_prop("res://models/environment/Bench_01_GLB.glb", Vector3(11.5, by, 6.5), -2.2, 1.0, lm, "PondBench")

# ---------- groves + scatter ----------

func _add_groves_and_scatter() -> void:
	var groves := Node3D.new()
	groves.name = "Groves"
	root.add_child(groves)
	groves.owner = root
	var grove_centers := [
		Vector2(-16, -11), Vector2(15, 12), Vector2(-13, 12),
		Vector2(17, -3), Vector2(-22, 1), Vector2(5, -15),
	]
	var med := ["Tree_Med_A.glb", "Tree_Med_B.glb", "Tree_Large_C.glb"]
	var idx := 0
	for gc in grove_centers:
		for t in 3:
			var px: float = gc.x + rng.randf_range(-3.5, 3.5)
			var pz: float = gc.y + rng.randf_range(-3.0, 3.0)
			if _in_pond(px, pz, 2.0) or _in_bridge_lane(px, pz):
				continue
			var y := height_at(px, pz)
			var s := rng.randf_range(0.85, 1.2)
			_instance_prop(A + med[idx % med.size()], Vector3(px, y - 0.1, pz), rng.randf_range(0, TAU), s, groves, "GTree%d" % idx)
			_add_trunk_collider(groves, Vector3(px, y, pz), 0.35 * s, 3.5)
			idx += 1
		# glowshroom cluster per grove
		var gx: float = gc.x + rng.randf_range(-2, 2)
		var gz: float = gc.y + rng.randf_range(-2, 2)
		if not (_in_pond(gx, gz, 1.0) or _in_bridge_lane(gx, gz)):
			var gy := height_at(gx, gz)
			var gv := "GlowShroom_Teal.glb" if idx % 2 == 0 else "GlowShroom_Violet.glb"
			_instance_prop(A + gv, Vector3(gx, gy, gz), rng.randf_range(0, TAU), rng.randf_range(1.2, 1.8), groves, "Glow%d" % idx)

	var scatter := Node3D.new()
	scatter.name = "Scatter"
	root.add_child(scatter)
	scatter.owner = root
	# [file, count, smin, smax, collide, sway_height_ref (0 = no sway)]
	var defs := [
		["Grass_A.glb", 26, 0.9, 1.6, false, 0.45], ["Grass_B.glb", 22, 0.9, 1.6, false, 0.35],
		["Grass_C.glb", 26, 0.9, 1.7, false, 0.55], ["Fern_A.glb", 14, 0.8, 1.4, false, 0.4],
		["Fern_B.glb", 12, 0.8, 1.4, false, 0.4], ["Flowers_Pink.glb", 9, 0.9, 1.4, false, 0.3],
		["Flowers_Blue.glb", 9, 0.9, 1.4, false, 0.3], ["Flowers_Yellow.glb", 9, 0.9, 1.4, false, 0.3],
		["Mushroom_Red_A.glb", 7, 0.9, 1.5, false, 0.0], ["Mushroom_Red_B.glb", 6, 0.9, 1.5, false, 0.0],
		["Bush_A.glb", 12, 0.9, 1.5, false, 1.2], ["Bush_B.glb", 10, 0.9, 1.4, false, 1.6],
		["Sapling_A.glb", 8, 0.9, 1.3, false, 0.0], ["Sapling_B.glb", 8, 0.9, 1.3, false, 0.0],
		["Boulder_A.glb", 6, 0.9, 1.6, true, 0.0], ["Boulder_B.glb", 5, 0.8, 1.3, true, 0.0],
		["Fallen_Log.glb", 4, 1.0, 1.3, true, 0.0], ["Stump.glb", 4, 0.9, 1.4, true, 0.0],
	]
	var n := 0
	for def in defs:
		for i in def[1]:
			var ang := rng.randf_range(0, TAU)
			var rn := sqrt(rng.randf_range(0.02, 0.72))
			var p := _oval_pos(rn, ang)
			if _in_pond(p.x, p.y, 1.2) or (_in_bridge_lane(p.x, p.y) and def[4]):
				continue
			var y := height_at(p.x, p.y)
			var s: float = rng.randf_range(def[2], def[3])
			var prop := _instance_prop(A + def[0], Vector3(p.x, y - 0.03, p.y), rng.randf_range(0, TAU), s, scatter, "S%d" % n)
			if def[5] > 0.0:
				_apply_sway(prop, def[5])
			if def[4]:
				var aabb_r := 0.9 * s
				_add_box_collider(scatter, Vector3(p.x, y + aabb_r / 2.0, p.y), Vector3(aabb_r * 1.6, aabb_r, aabb_r * 1.4), rng.randf_range(0, TAU), "SCol%d" % n)
			n += 1
	# existing assets: Rock_01 + Plant_01/02 accents
	for i in 6:
		var ang := rng.randf_range(0, TAU)
		var rn := sqrt(rng.randf_range(0.1, 0.68))
		var p := _oval_pos(rn, ang)
		if _in_pond(p.x, p.y, 1.5) or _in_bridge_lane(p.x, p.y):
			continue
		var y := height_at(p.x, p.y)
		var rs := rng.randf_range(0.8, 1.4)
		_instance_prop("res://models/environment/Rock_01_GLB.glb", Vector3(p.x, y, p.y), rng.randf_range(0, TAU), rs, scatter, "OldRock%d" % i)
		_add_box_collider(scatter, Vector3(p.x, y + 0.5 * rs, p.y), Vector3(1.5 * rs, 1.0 * rs, 1.3 * rs), rng.randf_range(0, TAU), "OldRockCol%d" % i)
	for i in 8:
		var ang := rng.randf_range(0, TAU)
		var rn := sqrt(rng.randf_range(0.1, 0.7))
		var p := _oval_pos(rn, ang)
		if _in_pond(p.x, p.y, 1.2):
			continue
		var y := height_at(p.x, p.y)
		var v := "res://models/environment/Plant_01_Art_GLB.glb" if i % 2 == 0 else "res://models/environment/Plant_02_Art_GLB.glb"
		_instance_prop(v, Vector3(p.x, y, p.y), rng.randf_range(0, TAU), rng.randf_range(0.8, 1.2), scatter, "OldPlant%d" % i)

# ---------- atmosphere ----------

func _add_atmosphere() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.06, 0.07, 0.20)
	sky_mat.sky_horizon_color = Color(0.28, 0.20, 0.42)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.05)
	sky_mat.ground_horizon_color = Color(0.20, 0.12, 0.28)
	sky_mat.sun_angle_max = 12.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.30, 0.26, 0.48)
	env.fog_density = 0.008
	env.fog_sky_affect = 0.25
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.018
	env.volumetric_fog_albedo = Color(0.55, 0.55, 0.85)
	env.volumetric_fog_emission = Color(0.05, 0.04, 0.12)
	env.volumetric_fog_emission_energy = 0.35
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 80.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)
	we.owner = root
	# moonlight
	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.light_color = Color(0.72, 0.78, 1.0)
	moon.light_energy = 1.0
	moon.light_volumetric_fog_energy = 1.6
	moon.shadow_enabled = true
	moon.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-38), deg_to_rad(28), 0)), Vector3(0, 20, 0))
	root.add_child(moon)
	moon.owner = root
	# glowshroom omni lights (over grove glow clusters)
	var lights := Node3D.new()
	lights.name = "GroveLights"
	root.add_child(lights)
	lights.owner = root
	var groves := root.get_node("Groves")
	var count := 0
	for c in groves.get_children():
		if count >= 10:
			break
		if c.name.begins_with("Glow") and c is Node3D:
			var l := OmniLight3D.new()
			l.name = "GlowLight%d" % count
			l.light_color = Color(0.25, 0.95, 0.85) if count % 2 == 0 else Color(0.72, 0.45, 1.0)
			l.light_energy = 1.6
			l.omni_range = 7.0
			l.light_volumetric_fog_energy = 2.2
			l.shadow_enabled = false
			l.position = (c as Node3D).position + Vector3(0, 1.0, 0)
			lights.add_child(l)
			l.owner = root
			count += 1
	# soft teal accent light on the pond/bridge centerpiece
	var pond_light := OmniLight3D.new()
	pond_light.name = "PondLight"
	pond_light.light_color = Color(0.35, 0.75, 0.9)
	pond_light.light_energy = 1.1
	pond_light.omni_range = 12.0
	pond_light.light_volumetric_fog_energy = 1.8
	pond_light.shadow_enabled = false
	pond_light.position = Vector3(0, height_at(0, 0) + 3.5, 0)
	root.add_child(pond_light)
	pond_light.owner = root

# ---------- particles ----------

func _add_particles() -> void:
	# falling leaves, one big gentle system over the whole arena
	var leaf_ps: PackedScene = load(A + "Leaf.glb")
	var leaf_inst := leaf_ps.instantiate()
	var leaf_mesh: Mesh = _first_mesh_instance(leaf_inst).mesh
	leaf_inst.free()
	var leaves := GPUParticles3D.new()
	leaves.name = "FallingLeaves"
	leaves.amount = 220
	leaves.lifetime = 22.0
	leaves.preprocess = 22.0
	leaves.draw_pass_1 = leaf_mesh
	var lm := ParticleProcessMaterial.new()
	lm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	lm.emission_box_extents = Vector3(28, 1.5, 21)
	lm.direction = Vector3(0, -1, 0)
	lm.spread = 20.0
	lm.initial_velocity_min = 0.25
	lm.initial_velocity_max = 0.5
	lm.gravity = Vector3(0, -0.03, 0)
	lm.angle_min = 0.0
	lm.angle_max = 360.0
	lm.angular_velocity_min = 40.0
	lm.angular_velocity_max = 140.0
	lm.turbulence_enabled = true
	lm.turbulence_noise_strength = 0.8
	lm.turbulence_influence_min = 0.06
	lm.turbulence_influence_max = 0.14
	leaves.process_material = lm
	leaves.position = Vector3(0, 9.5, 0)
	root.add_child(leaves)
	leaves.owner = root
	# fireflies: clusters near groves and the pond
	var firefly_mesh := SphereMesh.new()
	firefly_mesh.radius = 0.035
	firefly_mesh.height = 0.07
	firefly_mesh.radial_segments = 6
	firefly_mesh.rings = 3
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.85, 1.0, 0.4)
	fmat.emission_enabled = true
	fmat.emission = Color(0.75, 1.0, 0.3)
	fmat.emission_energy_multiplier = 4.5
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	firefly_mesh.material = fmat
	var spots := [Vector2(0, 0), Vector2(-16, -11), Vector2(15, 12), Vector2(-13, 12), Vector2(17, -3), Vector2(-22, 1), Vector2(5, -15)]
	var fparent := Node3D.new()
	fparent.name = "Fireflies"
	root.add_child(fparent)
	fparent.owner = root
	var fi := 0
	for s in spots:
		var flies := GPUParticles3D.new()
		flies.name = "FireflyCluster%d" % fi
		flies.amount = 18
		flies.lifetime = 9.0
		flies.preprocess = 9.0
		flies.draw_pass_1 = firefly_mesh
		var fm := ParticleProcessMaterial.new()
		fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		fm.emission_box_extents = Vector3(3.5, 1.2, 3.0)
		fm.gravity = Vector3.ZERO
		fm.initial_velocity_min = 0.15
		fm.initial_velocity_max = 0.4
		fm.spread = 180.0
		fm.turbulence_enabled = true
		fm.turbulence_noise_strength = 1.2
		fm.turbulence_influence_min = 0.25
		fm.turbulence_influence_max = 0.5
		flies.process_material = fm
		var fy := height_at(s.x, s.y)
		flies.position = Vector3(s.x, fy + 1.4, s.y)
		fparent.add_child(flies)
		flies.owner = root
		fi += 1

# ---------- birds ----------

func _add_birds() -> void:
	var flock := Node3D.new()
	flock.name = "BirdFlock"
	flock.set_script(load("res://bird_flock.gd"))
	root.add_child(flock)
	flock.owner = root

# ---------- ambience audio / splash / stars ----------

func _add_ambience_audio() -> void:
	var amb := Node.new()
	amb.name = "ForestAmbience"
	amb.set_script(load("res://forest_ambience.gd"))
	root.add_child(amb)
	amb.owner = root

func _add_pond_splash() -> void:
	var area := Area3D.new()
	area.name = "PondSplash"
	area.collision_layer = 0
	area.collision_mask = 2
	area.set_script(load("res://pond_splash.gd"))
	var water_y := height_at(0, 0) + 0.62
	area.set("water_y", water_y)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(POND_RX * 2.0, 1.6, POND_RZ * 2.0)
	col.shape = shape
	col.position = Vector3(0, water_y + 0.3, 0)
	area.add_child(col)
	root.add_child(area)
	area.owner = root
	col.owner = root

func _add_shooting_stars() -> void:
	var stars := GPUParticles3D.new()
	stars.name = "ShootingStars"
	stars.amount = 1
	stars.lifetime = 1.4
	stars.one_shot = true
	stars.emitting = false
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.07, 3.2, 0.07)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1)
	m.emission_enabled = true
	m.emission = Color(0.9, 0.95, 1.0)
	m.emission_energy_multiplier = 6.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = m
	stars.draw_pass_1 = mesh
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(-0.8, -0.35, 0.25)
	pm.spread = 8.0
	pm.initial_velocity_min = 34.0
	pm.initial_velocity_max = 48.0
	pm.gravity = Vector3.ZERO
	pm.particle_flag_align_y = true
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24, 3, 18)
	stars.process_material = pm
	stars.position = Vector3(0, 34, 0)
	stars.set_script(load("res://shooting_star.gd"))
	root.add_child(stars)
	stars.owner = root

# ---------- spawns ----------

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
		var ang := i * TAU / 8.0 + 0.42
		var p := _oval_pos(0.72, ang)
		var y := height_at(p.x, p.y)
		var m := Marker3D.new()
		m.name = "SpawnPoint%d" % i
		m.add_to_group("spawn_point", true)
		# face map center
		var look := atan2(-p.x, -p.y)
		m.transform = Transform3D(Basis(Vector3.UP, look), Vector3(p.x, y + 1.5, p.y))
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
		# re-assert persistent group membership so it survives repacking
		if m.is_in_group("spawn_point"):
			m.remove_from_group("spawn_point")
		m.add_to_group("spawn_point", true)
	print("SpawnPoints preserved from existing map (%d markers)" % old_sp.get_child_count())
	return true

# ---------- gameplay scaffolding (copied from node_3d.tscn) ----------

func _add_gameplay_scaffolding() -> void:
	var src_ps: PackedScene = load("res://node_3d.tscn")
	var src = src_ps.instantiate()
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
	# reposition pickups for this map
	# gun ON the bridge deck: gun_spawn_mode default is fixed, so the node's own
	# position is what counts (the gun_spawn_point marker only serves random mode)
	var gun = root.get_node_or_null("Gun")
	if gun:
		var bank_y := maxf(height_at(0, POND_RZ + 0.6), height_at(0, -POND_RZ - 0.6))
		gun.position = Vector3(0, bank_y + 0.7 + 0.16 + 0.35, 0)
	var melee = root.get_node_or_null("MeleeWeapon")
	if melee:
		var my := height_at(0, -(POND_RZ + 8.0))
		melee.position = Vector3(0, my + 0.6, -(POND_RZ + 8.0))
	var item1 = root.get_node_or_null("item")
	if item1:
		var iy := height_at(-16, -11)
		item1.position = Vector3(-16, iy + 0.5, -11)
	var item2 = root.get_node_or_null("item2")
	if item2:
		var iy := height_at(15, 12)
		item2.position = Vector3(15, iy + 0.5, 12)
	var gren = root.get_node_or_null("grenade")
	if gren:
		var gy := height_at(-22, 1)
		gren.position = Vector3(-22, gy + 0.5, 1)
	var pow1 = root.get_node_or_null("powerup")
	if pow1:
		var py := height_at(17, -3)
		pow1.position = Vector3(17, py + 0.8, -3)
	var pow2 = root.get_node_or_null("powerup2")
	if pow2:
		var py := height_at(-13, 12)
		pow2.position = Vector3(-13, py + 0.8, 12)
	print("Scaffolding copied: ", root.get_node_or_null("RoundManager") != null, " players: ", root.get_node_or_null("player1") != null, " gun: ", root.get_node_or_null("Gun") != null)

# ---------- navmesh ----------

func _bake_navmesh() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.6
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

# ---------- util ----------

func _first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var r := _first_mesh_instance(c)
		if r:
			return r
	return null
