class_name CombatPop
extends RefCounted

## Shared elimination/decoy burst. It is intentionally world-local: accessibility
## can soften the emission, but the effect never flashes the full screen.

static var _party_stream: AudioStreamWAV = null

static func spawn(world: Node, world_position: Vector3, accent: Color = Color(0.9, 0.85, 0.75)) -> void:
	if world == null:
		return
	var root := Node3D.new()
	root.name = "CombatPop"
	world.add_child(root)
	root.global_position = world_position + Vector3.UP * 1.1

	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.amount = 64
	particles.lifetime = 1.45
	particles.explosiveness = 1.0
	var confetti := BoxMesh.new()
	confetti.size = Vector3(0.055, 0.19, 0.018)
	var confetti_material := StandardMaterial3D.new()
	confetti_material.vertex_color_use_as_albedo = true
	confetti_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	confetti_material.emission_enabled = not _reduce_flashing()
	confetti_material.emission = Color(0.42, 0.42, 0.42)
	confetti_material.emission_energy_multiplier = 0.35
	confetti.material = confetti_material
	particles.draw_pass_1 = confetti
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 72.0
	process.initial_velocity_min = 4.0
	process.initial_velocity_max = 7.5
	process.gravity = Vector3(0.0, -9.2, 0.0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.38
	process.angular_velocity_min = -720.0
	process.angular_velocity_max = 720.0
	var palette := Gradient.new()
	palette.offsets = PackedFloat32Array([0.0, 0.18, 0.36, 0.55, 0.76, 1.0])
	palette.colors = PackedColorArray([
		accent, Color(0.1, 0.85, 1.0), Color(1.0, 0.2, 0.55),
		Color(1.0, 0.82, 0.08), Color(0.25, 1.0, 0.3), Color(0.7, 0.25, 1.0)])
	var palette_texture := GradientTexture1D.new()
	palette_texture.gradient = palette
	process.color_ramp = palette_texture
	particles.process_material = process
	root.add_child(particles)
	particles.emitting = true

	var party_player := AudioStreamPlayer3D.new()
	party_player.stream = _party_favor_stream()
	party_player.unit_size = 8.0
	party_player.max_distance = 45.0
	party_player.volume_db = AudioManager.SFX_VOLUME_DB - 4.0
	root.add_child(party_player)
	party_player.play()
	root.get_tree().create_timer(1.8).timeout.connect(root.queue_free)

static func _party_favor_stream() -> AudioStreamWAV:
	if _party_stream != null:
		return _party_stream
	const RATE := 22050
	const DURATION := 0.42
	var sample_count := int(RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase := 0.0
	for index in sample_count:
		var t := float(index) / RATE
		var pitch := lerpf(920.0, 360.0, t / DURATION) + sin(t * 46.0) * 80.0
		phase += TAU * pitch / RATE
		var envelope := pow(1.0 - t / DURATION, 1.35)
		var horn := sin(phase) * 0.72 + sin(phase * 2.01) * 0.20
		var pop := (randf() * 2.0 - 1.0) * maxf(1.0 - t / 0.035, 0.0) * 0.45
		data.encode_s16(index * 2, int(clampf((horn + pop) * envelope, -1.0, 1.0) * 32767.0))
	_party_stream = AudioStreamWAV.new()
	_party_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_party_stream.mix_rate = RATE
	_party_stream.stereo = false
	_party_stream.data = data
	return _party_stream

static func _reduce_flashing() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var manager := tree.root.get_node_or_null("AccessibilityManager")
	return manager != null and manager.has_method("allow_flash") and not manager.allow_flash()
