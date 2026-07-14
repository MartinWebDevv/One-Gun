extends Area3D

## Watches the pond for players/bots wading through and spawns small splash
## bursts at the water line as they move.

@export var water_y: float = 0.0
@export var splash_spacing: float = 0.9  # meters moved between splashes

var _last_splash_pos := {}

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_last_splash_pos[body] = body.global_position
	_splash_at(body.global_position)

func _on_body_exited(body: Node3D) -> void:
	_last_splash_pos.erase(body)

func _physics_process(_delta: float) -> void:
	for body in _last_splash_pos.keys():
		if not is_instance_valid(body):
			_last_splash_pos.erase(body)
			continue
		var last: Vector3 = _last_splash_pos[body]
		if body.global_position.distance_to(last) >= splash_spacing:
			_last_splash_pos[body] = body.global_position
			_splash_at(body.global_position)

func _splash_at(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.55
	p.explosiveness = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.92, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.5, 0.85, 1.0)
	m.emission_energy_multiplier = 1.6
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = m
	p.draw_pass_1 = mesh
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 55.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.6
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	p.process_material = pm
	p.position = Vector3(pos.x, water_y + 0.06, pos.z) - global_position
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
