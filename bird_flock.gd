extends Node3D

## Ambient birds circling above the map on elliptical orbits. Pure transform
## animation - no physics, no collision. Wings flap with periodic glides.

@export var bird_scene_path: String = "res://models/forestAssets/Bird.glb"
@export var bird_count: int = 5
@export var min_height: float = 13.0
@export var max_height: float = 17.0

var _birds: Array = []

class BirdState:
	var node: Node3D
	var wing_l: Node3D
	var wing_r: Node3D
	var radius_x: float
	var radius_z: float
	var height: float
	var speed: float
	var phase: float
	var direction: float
	var bob_phase: float
	var flap_phase: float
	var glide_timer: float
	var gliding := false

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var ps: PackedScene = load(bird_scene_path)
	if ps == null:
		return
	for i in bird_count:
		var b := BirdState.new()
		b.node = ps.instantiate()
		b.node.name = "Bird%d" % i
		add_child(b.node)
		b.wing_l = b.node.find_child("Wing_L", true, false)
		b.wing_r = b.node.find_child("Wing_R", true, false)
		b.radius_x = rng.randf_range(14.0, 26.0)
		b.radius_z = b.radius_x * rng.randf_range(0.6, 0.85)
		b.height = rng.randf_range(min_height, max_height)
		b.speed = rng.randf_range(0.12, 0.28)
		b.phase = rng.randf_range(0.0, TAU)
		b.direction = 1.0 if rng.randf() > 0.4 else -1.0
		b.bob_phase = rng.randf_range(0.0, TAU)
		b.flap_phase = rng.randf_range(0.0, TAU)
		b.glide_timer = rng.randf_range(2.0, 6.0)
		_birds.append(b)

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for b in _birds:
		b.phase += b.speed * b.direction * delta
		var x: float = cos(b.phase) * b.radius_x
		var z: float = sin(b.phase) * b.radius_z
		var y: float = b.height + sin(t * 0.7 + b.bob_phase) * 0.8
		b.node.position = Vector3(x, y, z)
		# face along the flight tangent
		var tangent: Vector3 = Vector3(-sin(b.phase) * b.radius_x, 0, cos(b.phase) * b.radius_z) * b.direction
		if tangent.length_squared() > 0.001:
			b.node.basis = Basis.looking_at(tangent.normalized(), Vector3.UP)
		# flap with glide pauses
		b.glide_timer -= delta
		if b.glide_timer <= 0.0:
			b.gliding = not b.gliding
			b.glide_timer = randf_range(1.5, 4.0) if b.gliding else randf_range(3.0, 7.0)
		var target_flap: float = 0.0
		if not b.gliding:
			b.flap_phase += delta * 11.0
			target_flap = sin(b.flap_phase) * 0.6
		else:
			target_flap = 0.15
		if b.wing_l:
			b.wing_l.rotation.y = -target_flap * 0.0
			b.wing_l.rotation.z = lerp_angle(b.wing_l.rotation.z, target_flap, 0.5)
		if b.wing_r:
			b.wing_r.rotation.z = lerp_angle(b.wing_r.rotation.z, -target_flap, 0.5)
