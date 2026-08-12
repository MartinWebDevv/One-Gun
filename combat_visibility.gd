class_name CombatVisibility
extends RefCounted

static func smoke_blocks(tree: SceneTree, from: Vector3, to: Vector3) -> bool:
	if tree == null:
		return false
	for cloud in tree.get_nodes_in_group("combat_smoke"):
		if is_instance_valid(cloud) and cloud.has_method("blocks_segment") and cloud.blocks_segment(from, to):
			return true
	return false


static func has_visual_contact(viewer: Node3D, target: Node3D, check_geometry := true) -> bool:
	if viewer == null or target == null or not is_instance_valid(viewer) or not is_instance_valid(target):
		return false
	var from := viewer.global_position + Vector3.UP * 0.5
	var to := target.global_position + Vector3.UP * 0.5
	if smoke_blocks(viewer.get_tree(), from, to):
		return false
	if not check_geometry:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if viewer is CollisionObject3D:
		query.exclude.append(viewer.get_rid())
	if target is CollisionObject3D:
		query.exclude.append(target.get_rid())
	query.collision_mask = 1
	return viewer.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
