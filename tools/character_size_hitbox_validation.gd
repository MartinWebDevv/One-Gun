extends Node

const PLAYER_SCENE = preload("res://player.tscn")
const SkinRegistry = preload("res://player_skin_registry.gd")

const BASELINE_MODELS: Array[String] = ["male", "female"]
const EXPECTED_CAPSULE_RADIUS := 0.495
const EXPECTED_CAPSULE_HEIGHT := 2.3266993
const EXPECTED_CAPSULE_POSITION_Y := 0.07334959
const VISUAL_HEIGHT_TOLERANCE := 0.015
const VISUAL_GROUND_TOLERANCE := 0.015

var _failed := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var actor := PLAYER_SCENE.instantiate() as CharacterBody3D
	actor.set("is_online", true)
	actor.set("character_model_id", "male")
	add_child(actor)
	await get_tree().process_frame
	actor.set_physics_process(false)

	var collision := actor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var capsule := collision.shape as CapsuleShape3D if collision != null else null
	_check(collision != null and capsule != null,
		"player uses the shared CapsuleShape3D body collider")
	if capsule == null:
		get_tree().quit(1)
		return
	_check(is_equal_approx(capsule.radius, EXPECTED_CAPSULE_RADIUS)
			and is_equal_approx(capsule.height, EXPECTED_CAPSULE_HEIGHT)
			and is_equal_approx(collision.position.y, EXPECTED_CAPSULE_POSITION_Y),
		"player capsule dimensions match the approved cat hitbox")
	var collision_instance_id := collision.get_instance_id()
	var capsule_instance_id := capsule.get_instance_id()

	var measured := {}
	for model_id in SkinRegistry.MODEL_IDS:
		actor.call("set_character_model", model_id)
		await get_tree().process_frame
		await get_tree().process_frame
		var visual := actor.get_node_or_null("CharacterModel") as Node3D
		var animation_player := visual.call(
			"ensure_animations", ["idle"]) as AnimationPlayer \
			if visual != null else null
		if animation_player != null:
			animation_player.play("idle")
			animation_player.advance(0.0)
		var skeleton := visual.call("get_skeleton") as Skeleton3D \
			if visual != null else null
		if skeleton != null:
			skeleton.force_update_all_bone_transforms()
		var bounds := _combined_bounds_in_actor_space(actor, visual)
		measured[model_id] = bounds
		var registered_bounds := SkinRegistry.idle_actor_bounds(model_id)
		var current_collision := actor.get_node_or_null(
			"CollisionShape3D") as CollisionShape3D
		var current_capsule := current_collision.shape as CapsuleShape3D \
			if current_collision != null else null
		_check(visual != null and bounds.size != Vector3.ZERO,
			"%s has measurable runtime visual bounds" % model_id)
		_check(bounds.position.distance_to(registered_bounds.position) <= 0.02
				and bounds.size.distance_to(registered_bounds.size) <= 0.02,
			"%s measured bounds drifted from its presentation envelope" % model_id)
		_check(current_collision != null and current_capsule != null
				and current_collision.get_instance_id() == collision_instance_id
				and current_capsule.get_instance_id() == capsule_instance_id
				and is_equal_approx(
					current_capsule.radius, EXPECTED_CAPSULE_RADIUS)
				and is_equal_approx(
					current_capsule.height, EXPECTED_CAPSULE_HEIGHT)
				and is_equal_approx(current_collision.position.y,
					EXPECTED_CAPSULE_POSITION_Y),
			"%s keeps the exact shared cat hitbox while its visual swaps" % model_id)
		print("CHARACTER_SIZE model=%s bounds=%s bottom=%.4f top=%.4f" % [
			model_id, bounds, bounds.position.y, bounds.end.y])

	var baseline_height := 0.0
	var baseline_bottom := 0.0
	for model_id in BASELINE_MODELS:
		var bounds: AABB = measured.get(model_id, AABB())
		baseline_height += bounds.size.y
		baseline_bottom += bounds.position.y
	baseline_height /= float(BASELINE_MODELS.size())
	baseline_bottom /= float(BASELINE_MODELS.size())
	var capsule_bottom := collision.position.y - capsule.height * 0.5
	for model_id in SkinRegistry.DEVELOPER_GIFT_MODEL_IDS:
		var bounds: AABB = measured.get(model_id, AABB())
		_check(absf(bounds.size.y - baseline_height)
				<= VISUAL_HEIGHT_TOLERANCE,
			"%s visual height %.4f does not match cat midpoint %.4f" % [
				model_id, bounds.size.y, baseline_height])
		_check(absf(bounds.position.y - capsule_bottom)
				<= VISUAL_GROUND_TOLERANCE,
			"%s visual bottom %.4f is not grounded at capsule bottom %.4f" % [
				model_id, bounds.position.y, capsule_bottom])
	print("CHARACTER_SIZE_BASELINE height=%.4f bottom=%.4f capsule_bottom=%.4f capsule_top=%.4f" % [
		baseline_height, baseline_bottom,
		capsule_bottom,
		collision.position.y + capsule.height * 0.5])

	actor.queue_free()
	await get_tree().process_frame
	if _failed:
		get_tree().quit(1)
		return
	print("CHARACTER_SIZE_HITBOX_VALIDATION: PASS models=%d shared_capsule=true" % \
		SkinRegistry.MODEL_IDS.size())
	get_tree().quit(0)


func _combined_bounds_in_actor_space(actor: Node3D, visual: Node3D) -> AABB:
	var result := AABB()
	var found := false
	if actor == null or visual == null:
		return result
	var actor_inverse := actor.global_transform.affine_inverse()
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var bounds := _skinned_bounds_in_actor_space(
			actor_inverse, mesh_instance)
		result = bounds if not found else result.merge(bounds)
		found = true
	return result


func _skinned_bounds_in_actor_space(actor_inverse: Transform3D,
		mesh_instance: MeshInstance3D) -> AABB:
	var skeleton := mesh_instance.get_node_or_null(
		mesh_instance.skeleton) as Skeleton3D
	if mesh_instance.skin == null or skeleton == null:
		return actor_inverse * mesh_instance.global_transform \
			* mesh_instance.get_aabb()
	var skin := mesh_instance.skin
	var bind_transforms: Array[Transform3D] = []
	var skeleton_to_actor := actor_inverse * skeleton.global_transform
	for bind_index in skin.get_bind_count():
		var bone_index := skin.get_bind_bone(bind_index)
		if bone_index < 0:
			bone_index = skeleton.find_bone(str(skin.get_bind_name(bind_index)))
		var bind_transform := Transform3D.IDENTITY
		if bone_index >= 0:
			bind_transform = skeleton_to_actor \
				* skeleton.get_bone_global_pose(bone_index) \
				* skin.get_bind_pose(bind_index)
		bind_transforms.append(bind_transform)

	var result := AABB()
	var found := false
	for surface_index in mesh_instance.mesh.get_surface_count():
		var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
		var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
		if vertices.is_empty() or bones.is_empty() or weights.is_empty():
			continue
		var surface_format: int = mesh_instance.mesh.surface_get_format(surface_index)
		var influences := 8 if (surface_format \
			& Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0 else 4
		for vertex_index in vertices.size():
			var skinned := Vector3.ZERO
			var total_weight := 0.0
			for influence_index in influences:
				var array_index := vertex_index * influences + influence_index
				if array_index >= bones.size() or array_index >= weights.size():
					continue
				var weight := weights[array_index]
				var bind_index := bones[array_index]
				if weight <= 0.000001 or bind_index < 0 \
						or bind_index >= bind_transforms.size():
					continue
				skinned += bind_transforms[bind_index] * vertices[vertex_index] \
					* weight
				total_weight += weight
			if total_weight <= 0.000001:
				continue
			if not is_equal_approx(total_weight, 1.0):
				skinned /= total_weight
			if not found:
				result = AABB(skinned, Vector3.ZERO)
				found = true
			else:
				result = result.expand(skinned)
	if found:
		return result
	return actor_inverse * mesh_instance.global_transform \
		* mesh_instance.get_aabb()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("CHARACTER SIZE/HITBOX: %s" % message)
