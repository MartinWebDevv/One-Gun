extends Node3D

## Deployed smoke bomb cloud: a fat vision-blocking puff that lingers, then
## dissipates. Pure concealment - no gameplay effect.

@export var cloud_radius := 4.0
@export var linger_time := 6.0
var owner_player = null

func _ready() -> void:
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 2.6
	p.preprocess = 1.2
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 2.6)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.78, 0.80, 0.55)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = m
	p.draw_pass_1 = quad
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = cloud_radius * 0.55
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, 0.15, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.6
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	p.process_material = pm
	add_child(p)
	await get_tree().create_timer(linger_time).timeout
	p.emitting = false
	await get_tree().create_timer(3.0).timeout
	queue_free()
