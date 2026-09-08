extends RefCounted

const GOLD = Color("d8d23e")
const CYAN = Color("58c9db")
const PINK = Color("e080b9")
const ORANGE = Color("e69850")
const GREEN = Color("9edc6b")
const INK = Color("152328")
const PAPER = Color("e5dfc6")
static var mats: Dictionary = {}
static var boxes: Dictionary = {}
static var heading: Font

static func material(key: String, color: Color, emission := 0.0, metal := 0.0) -> StandardMaterial3D:
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.84
	m.metallic = metal
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	mats[key] = m
	return m

static func textured(key: String, tint: Color, scale_uv := 1.0) -> StandardMaterial3D:
	var id := key + str(tint) + str(scale_uv)
	if mats.has(id):
		return mats[id]
	var m := material(id, tint)
	m.albedo_texture = load("res://art/" + key + ".png")
	m.uv1_scale = Vector3(scale_uv, scale_uv, 1)
	return m

static func box(parent: Node3D, title: String, pos: Vector3, size: Vector3,
		mat: Material, solid := false) -> MeshInstance3D:
	var mesh: BoxMesh
	if boxes.has(size):
		mesh = boxes[size]
	else:
		mesh = BoxMesh.new()
		mesh.size = size
		boxes[size] = mesh
	var obj := MeshInstance3D.new()
	obj.name = title
	obj.mesh = mesh
	obj.material_override = mat
	parent.add_child(obj)
	obj.position = pos
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = size
		shape.shape = bounds
		obj.add_child(body)
		body.add_child(shape)
	return obj

static func cylinder(parent: Node3D, title: String, pos: Vector3, radius: float,
		height: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	var obj := MeshInstance3D.new()
	obj.name = title
	obj.mesh = mesh
	obj.material_override = mat
	parent.add_child(obj)
	obj.position = pos
	return obj

static func rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var obj := cylinder(parent, "Conduit", (a + b) * 0.5, radius, a.distance_to(b), mat)
	obj.quaternion = Quaternion(Vector3.UP, (b-a).normalized())

static func label(parent: Node3D, title: String, text: String, pos: Vector3,
		size: int, color: Color, pixel := 0.008) -> Label3D:
	if heading == null:
		heading = load("res://art/heading.ttf")
	var obj := Label3D.new()
	obj.name = title
	obj.text = text
	obj.font = heading
	obj.font_size = size
	obj.pixel_size = pixel
	obj.modulate = color
	obj.outline_size = 0
	obj.no_depth_test = false
	obj.shaded = false
	parent.add_child(obj)
	obj.position = pos
	return obj

static func panel(parent: Node3D, title: String, text: String, pos: Vector3,
		size: Vector2, color: Color) -> Node3D:
	var p := Node3D.new()
	p.name = title
	parent.add_child(p)
	p.position = pos
	box(p, "Backplate", Vector3.ZERO, Vector3(size.x, size.y, 0.12), material("ink", INK))
	box(p, "Rule", Vector3(0, -size.y*0.5+0.055, 0.08), Vector3(size.x, 0.05, 0.03), material(str(color), color, 0.5))
	label(p, "Title", text, Vector3(0, 0.02, 0.08), 84, color, minf(size.x / maxf(text.length()*45.0, 1.0), 0.009))
	return p

static func lamp(parent: Node3D, pos: Vector3, color: Color, energy: float, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	parent.add_child(light)
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = false
	return light

static func ring(parent: Node3D, title: String, inner: float, outer: float,
		y: float, mat: Material, solid := false) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(64):
		var a := TAU * i / 64.0
		var b := TAU * (i+1) / 64.0
		var points := [Vector3(sin(a)*inner,y,cos(a)*inner), Vector3(sin(a)*outer,y,cos(a)*outer),
			Vector3(sin(b)*outer,y,cos(b)*outer), Vector3(sin(b)*inner,y,cos(b)*inner)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(points[idx].x,points[idx].z)*0.14)
			st.add_vertex(points[idx])
	var obj := MeshInstance3D.new()
	obj.name = title
	obj.mesh = st.commit()
	obj.material_override = mat
	parent.add_child(obj)
	if solid:
		obj.create_trimesh_collision()
	return obj
