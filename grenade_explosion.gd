extends Node3D

# One-shot blast: applies knockback to everyone in radius at the moment it
# detonates, then frees itself. No lingering hazard area (contrast with
# bubble_gum_trap.gd, which stays as a walk-into Area3D) and no bullet
# immunity grant — a grenade blast is meant to be riskier than a melee
# knockback hit, not safer.

@export var radius := 6.0
@export var knockback_distance := 4.0
@export var flash_lifetime := 0.3

var owner_player = null

func _ready():
	if NetworkManager.is_online():
		if multiplayer.is_server():
			var rm = get_tree().current_scene.get_node_or_null("RoundManager")
			if rm != null:
				rm.server_online_radial_knockback(global_position, int(get_meta("online_owner_actor_id", -1)), radius, knockback_distance)
	else:
		_apply_blast()
	_flash()
	await get_tree().create_timer(flash_lifetime).timeout
	queue_free()

func _apply_blast():
	for body in get_tree().get_nodes_in_group("combat_target"):
		if global_position.distance_to(body.global_position) > radius:
			continue
		if body.is_in_group("combat_decoy"):
			if body.has_method("can_be_affected_by") and not body.can_be_affected_by(owner_player):
				continue
			if body.has_method("pop_from_attack"):
				body.pop_from_attack(owner_player, "grenade")
			continue
		if not GameConfig.can_affect(owner_player, body):
			continue
		if not body.has_method("apply_knockback"):
			continue
		var direction = body.global_position - global_position
		direction.y = 0
		if direction.length() < 0.01:
			direction = Vector3.FORWARD
		body.apply_knockback(direction.normalized(), knockback_distance)
		if bool(body.get("holding_gun")):
			var blocked := false
			if body.has_method("consume_sticky_hands"):
				blocked = body.consume_sticky_hands()
			elif "melee_disarm_shields" in body and body.melee_disarm_shields > 0:
				body.melee_disarm_shields -= 1
				blocked = true
			if not blocked:
				var hold_point = body.get_hold_point()
				if hold_point != null and hold_point.get_child_count() > 0:
					var gun = hold_point.get_child(0)
					if gun.has_method("force_disarm"):
						gun.force_disarm()
					else:
						gun.drop()
					var victim: String = body.get_display_name()
					var attacker: String = owner_player.get_display_name() if owner_player != null else ""
					GameEvents.player_disarmed.emit(victim, attacker, "💥")

func _flash():
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if mesh_instance == null:
		return
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.6, 0.1, 0.6)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.6, 0.1)
	material.emission_energy_multiplier = 3.0
	mesh_instance.set_surface_override_material(0, material)
	mesh_instance.scale = Vector3.ONE * 0.3
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh_instance, "scale", Vector3.ONE * (radius * 0.5), flash_lifetime)
	tween.tween_property(material, "albedo_color:a", 0.0, flash_lifetime)
