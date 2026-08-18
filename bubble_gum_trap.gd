extends Area3D

@export var slow_duration := 4.0
@export var slow_multiplier := 0.5
@export var lifetime_seconds := 5.0

var owner_player = null

func _ready():
	add_to_group("hazard")
	body_entered.connect(_on_body_entered)
	collision_layer = 0
	set_collision_mask_value(2, true)
	_build_chewed_gum_splat()
	_expire_after_lifetime()

func manages_deployed_lifetime() -> bool:
	return true


func _expire_after_lifetime() -> void:
	await get_tree().create_timer(lifetime_seconds).timeout
	if is_inside_tree():
		queue_free()


func _build_chewed_gum_splat() -> void:
	# Keep presentation and gameplay footprint aligned at roughly 4.5m wide.
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null:
		var gum_shape := CylinderShape3D.new()
		gum_shape.radius = 2.25
		gum_shape.height = 0.18
		collision.position = Vector3(0.0, 0.07, 0.0)
		collision.scale = Vector3.ONE
		collision.shape = gum_shape
	var legacy_mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if legacy_mesh != null:
		legacy_mesh.visible = false
	var splat := Node3D.new()
	splat.scale = Vector3(4.5 / 3.5, 1.0, 4.5 / 3.5)
	splat.name = "ChewedGumSplat"
	add_child(splat)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.34, 0.83, 1.0)
	material.roughness = 0.36
	material.metallic = 0.08
	material.emission_enabled = true
	material.emission = Color(0.12, 0.015, 0.09, 1.0)
	material.emission_energy_multiplier = 0.55
	var center := CylinderMesh.new()
	center.top_radius = 1.42
	center.bottom_radius = 1.68
	center.height = 0.16
	center.radial_segments = 18
	_add_gum_piece(splat, center, Vector3(0.0, 0.06, 0.0), Vector3.ONE,
		0.0, material)
	var lobe := SphereMesh.new()
	lobe.radius = 0.5
	lobe.height = 1.0
	lobe.radial_segments = 12
	lobe.rings = 6
	_add_gum_piece(splat, lobe, Vector3(1.43, 0.055, 0.12),
		Vector3(0.82, 0.13, 0.58), 0.1, material)
	_add_gum_piece(splat, lobe, Vector3(-1.39, 0.05, -0.25),
		Vector3(0.62, 0.11, 0.86), -0.2, material)
	_add_gum_piece(splat, lobe, Vector3(0.26, 0.045, 1.46),
		Vector3(0.46, 0.09, 0.86), 0.35, material)
	_add_gum_piece(splat, lobe, Vector3(-0.40, 0.04, -1.48),
		Vector3(0.52, 0.08, 0.67), -0.4, material)
	_add_gum_piece(splat, lobe, Vector3(1.48, 0.035, -0.74),
		Vector3(0.88, 0.07, 0.20), 0.62, material)
	_add_gum_piece(splat, lobe, Vector3(-1.48, 0.035, 0.98),
		Vector3(0.24, 0.07, 0.28), -0.15, material)


func _add_gum_piece(parent: Node3D, mesh: PrimitiveMesh, at: Vector3,
		piece_scale: Vector3, yaw: float, material: Material) -> void:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = material
	piece.position = at
	piece.scale = piece_scale
	piece.rotation.y = yaw
	parent.add_child(piece)


func _on_body_entered(body):
	if not body.is_in_group("combat_target"):
		return
	if body.is_in_group("combat_decoy") and body.has_method("can_be_affected_by") \
			and not body.can_be_affected_by(owner_player):
		return
	if not GameConfig.can_affect(owner_player, body):
		return
	if body.is_in_group("combat_decoy"):
		if body.has_method("apply_slow"):
			body.apply_slow(slow_duration, slow_multiplier)
		return
	if NetworkManager.is_online():
		if multiplayer.is_server():
			var rm = get_tree().current_scene.get_node_or_null("RoundManager")
			var actor_id = body.get("actor_id")
			if rm != null and actor_id != null:
				rm.server_apply_online_item_effect("slow", int(actor_id), {"duration": slow_duration, "multiplier": slow_multiplier})
		return
	if body.has_method("apply_slow"):
		body.apply_slow(slow_duration, slow_multiplier)
