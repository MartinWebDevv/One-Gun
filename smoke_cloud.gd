class_name OneGunSmokeCloud
extends Node3D

# Irregular cover rather than a spherical dome. Horizontal radius drives the
# footprint independently from the raised presentation/concealment profile.
@export var cloud_radius := 5.0
@export var cloud_half_height := 4.2
@export var expand_time := 1.5
@export var full_time := 6.0
@export var collapse_time := 1.5
var owner_player = null
var current_radius := 0.0
var age := 0.0
var _particles: GPUParticles3D
var _wisp_root: Node3D
var _smoke_texture: Texture2D
static var _shared_smoke_texture: Texture2D


func _ready() -> void:
	add_to_group("combat_smoke")
	if _shared_smoke_texture == null:
		_shared_smoke_texture = _build_smoke_texture()
	_smoke_texture = _shared_smoke_texture
	_build_opaque_wisps()
	_build_particles()
	_update_radius(0.01)


func _build_opaque_wisps() -> void:
	_wisp_root = Node3D.new()
	_wisp_root.name = "OpaqueSmokeWisps"
	add_child(_wisp_root)
	var materials: Array[StandardMaterial3D] = [
		_build_smoke_material(Color(0.49, 0.52, 0.56, 1.0)),
		_build_smoke_material(Color(0.52, 0.55, 0.59, 1.0)),
		_build_smoke_material(Color(0.46, 0.49, 0.53, 1.0)),
	]
	# Golden-angle placement creates a broad irregular stack of overlapping
	# camera-facing cards without falling back to a solid primitive.
	const WISP_COUNT := 22
	var added_height := maxf(cloud_half_height - 2.2, 0.0)
	for index in WISP_COUNT:
		var ratio := (float(index) + 0.5) / float(WISP_COUNT)
		var ring := sqrt(ratio) * 0.82
		var angle := float(index) * 2.399963
		var wisp := MeshInstance3D.new()
		wisp.name = "SmokeWisp_%02d" % index
		var quad := QuadMesh.new()
		quad.size = Vector2(
			2.7 + 0.9 * (0.5 + 0.5 * sin(float(index) * 1.71)),
			1.8 + 0.9 * (0.5 + 0.5 * cos(float(index) * 1.13))
				+ added_height)
		quad.material = materials[index % materials.size()]
		wisp.mesh = quad
		wisp.position = Vector3(
			cos(angle) * cloud_radius * ring,
			0.65 + added_height * 0.5
				+ 1.05 * (0.5 + 0.5 * sin(float(index) * 0.83)),
			sin(angle) * cloud_radius * ring)
		wisp.rotation.z = sin(float(index) * 1.37) * 0.22
		wisp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_wisp_root.add_child(wisp)


func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "MovingSmokeWisps"
	_particles.amount = 480
	_particles.lifetime = 3.2
	_particles.preprocess = 3.2
	_particles.randomness = 0.7
	var added_height := maxf(cloud_half_height - 2.2, 0.0)
	_particles.position.y = 1.0 + added_height * 0.5
	_particles.visibility_aabb = AABB(
		Vector3(-cloud_radius, -0.5, -cloud_radius),
		Vector3(cloud_radius * 2.0, cloud_half_height + 1.0, cloud_radius * 2.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(1.65, 1.15 + added_height * 0.7)
	quad.material = _build_smoke_material(
		Color(0.58, 0.62, 0.66, 0.94), true)
	_particles.draw_pass_1 = quad
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(
		cloud_radius * 0.78, cloud_half_height * 0.33, cloud_radius * 0.78)
	process_material.direction = Vector3.UP
	process_material.spread = 180.0
	process_material.initial_velocity_min = 0.08
	process_material.initial_velocity_max = 0.42
	process_material.gravity = Vector3(0, 0.08, 0)
	process_material.scale_min = 0.75
	process_material.scale_max = 1.55
	process_material.angle_min = -180.0
	process_material.angle_max = 180.0
	process_material.turbulence_enabled = true
	process_material.turbulence_noise_strength = 0.48
	process_material.turbulence_influence_min = 0.04
	process_material.turbulence_influence_max = 0.14
	_particles.process_material = process_material
	add_child(_particles)


func _build_smoke_material(tint: Color, soft_edges := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	if soft_edges:
		# Only the animated outer wisps blend at their feathered edges. Hundreds
		# overlap around the alpha-scissored inner field, so the center remains
		# visually opaque while the silhouette regains a smoky falloff.
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		# The inner field is cutout/depth-writing: scenery can never bleed through
		# its visible irregular silhouettes.
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.34
	material.albedo_color = tint
	material.albedo_texture = _smoke_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _build_smoke_texture() -> Texture2D:
	const TEXTURE_SIZE := 192
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / float(TEXTURE_SIZE)
			var centered := (uv - Vector2(0.5, 0.5)) * Vector2(2.0, 2.35)
			var angle := atan2(centered.y, centered.x)
			var edge_noise := sin(angle * 7.0 + 0.6) * 0.055 \
				+ sin(angle * 13.0 - 1.3) * 0.028 \
				+ sin((uv.x * 9.0 + uv.y * 7.0) * TAU) * 0.018
			var distance := centered.length()
			var alpha := 1.0 - smoothstep(
				0.67 + edge_noise, 0.96 + edge_noise, distance)
			image.set_pixel(
				x, y, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _process(delta: float) -> void:
	age += delta
	var total := expand_time + full_time + collapse_time
	if age < expand_time:
		_update_radius(cloud_radius * clampf(
			age / maxf(expand_time, 0.01), 0.0, 1.0))
	elif age < expand_time + full_time:
		_update_radius(cloud_radius)
	elif age < total:
		var collapse_progress := (
			age - expand_time - full_time) / maxf(collapse_time, 0.01)
		_update_radius(cloud_radius * (
			1.0 - clampf(collapse_progress, 0.0, 1.0)))
	else:
		queue_free()


func _update_radius(radius: float) -> void:
	current_radius = maxf(radius, 0.01)
	var growth := clampf(
		current_radius / maxf(cloud_radius, 0.01), 0.01, 1.0)
	if _particles != null:
		_particles.scale = Vector3.ONE * growth
		_particles.emitting = current_radius > 0.08
	if _wisp_root != null:
		_wisp_root.scale = Vector3.ONE * growth
		_wisp_root.visible = current_radius > 0.08


func contains_point(world_point: Vector3) -> bool:
	return _normalized_smoke_point(world_point).length_squared() <= 1.0


func blocks_segment(from: Vector3, to: Vector3) -> bool:
	var local_from := _normalized_smoke_point(from)
	var local_to := _normalized_smoke_point(to)
	var segment := local_to - local_from
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return local_from.length_squared() <= 1.0
	var t := clampf(-local_from.dot(segment) / length_squared, 0.0, 1.0)
	return (local_from + segment * t).length_squared() <= 1.0


func _normalized_smoke_point(world_point: Vector3) -> Vector3:
	var local := world_point - global_position
	var horizontal_radius := maxf(current_radius, 0.01)
	var vertical_radius := maxf(
		cloud_half_height * current_radius / maxf(cloud_radius, 0.01), 0.01)
	return Vector3(
		local.x / horizontal_radius,
		local.y / vertical_radius,
		local.z / horizontal_radius)
