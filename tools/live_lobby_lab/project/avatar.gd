extends Node3D
## Lightweight masked stand-in. No live character, skin registry or loadout code.
const G = preload("res://geometry.gd")
var body_mat: StandardMaterial3D
var mask_mat: StandardMaterial3D
var left_leg: Node3D
var right_leg: Node3D
var left_arm: Node3D
var right_arm: Node3D
var phase := 0.0

func _ready() -> void:
	body_mat = G.material("runner_body",Color("54666b")).duplicate()
	mask_mat = G.material("runner_mask",G.GOLD).duplicate()
	var boots := G.material("runner_boots",Color("182b30"))
	# The stand-in matches the game's ~2.65m rendered actor envelope.
	_soft(self,"Jacket",Vector3(0,1.57,0),Vector3(0.89,1.06,0.61),body_mat)
	G.box(self,"Hem",Vector3(0,1.13,0),Vector3(0.98,0.19,0.6),boots)
	_soft(self,"Hood",Vector3(0,2.26,0),Vector3(0.80,0.80,0.76),boots)
	G.box(self,"Mask",Vector3(0,2.26,-0.38),Vector3(0.62,0.53,0.12),mask_mat)
	for x in [-0.16,0.16]:
		var eye := G.box(self,"MaskEye",Vector3(x,2.32,-0.455),Vector3(0.19,0.085,0.025),boots)
		eye.rotation.z = -0.15 if x < 0 else 0.15
	G.box(self,"MaskMark",Vector3(0,2.1,-0.46),Vector3(0.08,0.08,0.025),boots)
	for x in [-0.25,0.25]:
		var leg := Node3D.new()
		add_child(leg)
		leg.position = Vector3(x,1.04,0)
		_soft(leg,"Trouser",Vector3(0,-0.41,0),Vector3(0.37,0.9,0.41),body_mat)
		G.box(leg,"Boot",Vector3(0,-0.9,-0.09),Vector3(0.39,0.28,0.58),boots)
		if x < 0: left_leg = leg
		else: right_leg = leg
	for x in [-0.6,0.6]:
		var arm := Node3D.new()
		add_child(arm)
		arm.position = Vector3(x,1.96,0)
		_soft(arm,"Sleeve",Vector3(0,-0.35,0),Vector3(0.34,0.8,0.37),body_mat)
		G.box(arm,"Glove",Vector3(0,-0.8,-0.05),Vector3(0.27,0.28,0.31),boots)
		if x < 0: left_arm = arm
		else: right_arm = arm
	G.box(self,"JacketBackPatch",Vector3(0,1.7,0.294),Vector3(0.53,0.48,0.03),mask_mat)
	G.label(self,"BackNumber","01",Vector3(0,1.7,0.32),42,G.INK,0.009)

func tint(color: Color) -> void:
	mask_mat.albedo_color = color

func animate(delta: float, speed: float) -> void:
	phase += delta * (9.0 if speed > 0.2 else 1.5)
	var swing := sin(phase) * minf(speed/10.0,1.0) * 0.55
	left_leg.rotation.x = swing
	right_leg.rotation.x = -swing
	left_arm.rotation.x = -swing*0.75
	right_arm.rotation.x = swing*0.75

func _soft(parent: Node3D, title: String, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = size.x*0.5
	mesh.height = maxf(size.y,size.x)
	mesh.radial_segments = 12
	mesh.rings = 4
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	node.material_override = mat
	parent.add_child(node)
	node.position = pos
	node.scale.z = size.z/size.x