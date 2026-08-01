class_name CombatPop
extends RefCounted

## Shared elimination/decoy burst. It is intentionally world-local: accessibility
## can soften the emission, but the effect never flashes the full screen.

static func spawn(world: Node, world_position: Vector3, accent: Color = Color(0.9, 0.85, 0.75)) -> void:
	if world == null:
		return
	var root := Node3D.new()
	root.name = "CombatPop"
	world.add_child(root)
	root.global_position = world_position + Vector3.UP * 1.1

	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.amount = 28
	particles.lifetime = 0.55
	particles.explosiveness = 1.0
	var shard := SphereMesh.new()
	shard.radius = 0.055
	shard.height = 0.11
	shard.radial_segments = 6
	shard.rings = 3
	var shard_material := StandardMaterial3D.new()
	shard_material.albedo_color = accent
	shard_material.emission_enabled = true
	shard_material.emission = accent
	shard_material.emission_energy_multiplier = 1.6 if _reduce_flashing() else 3.2
	shard_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shard.material = shard_material
	particles.draw_pass_1 = shard
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 85.0
	process.initial_velocity_min = 2.5
	process.initial_velocity_max = 5.0
	process.gravity = Vector3(0.0, -7.0, 0.0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.55
	particles.process_material = process
	root.add_child(particles)
	particles.emitting = true

	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	var flash_material := StandardMaterial3D.new()
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(accent.r, accent.g, accent.b, 0.45 if _reduce_flashing() else 0.8)
	flash_material.emission_enabled = true
	flash_material.emission = accent
	flash_material.emission_energy_multiplier = 1.2 if _reduce_flashing() else 4.0
	sphere.material = flash_material
	flash.mesh = sphere
	root.add_child(flash)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 4.0, 0.22)
	tween.tween_property(flash_material, "albedo_color:a", 0.0, 0.22)
	root.get_tree().create_timer(0.7).timeout.connect(root.queue_free)

static func _reduce_flashing() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var manager := tree.root.get_node_or_null("AccessibilityManager")
	return manager != null and manager.has_method("allow_flash") and not manager.allow_flash()
