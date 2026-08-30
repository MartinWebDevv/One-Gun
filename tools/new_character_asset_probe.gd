extends SceneTree

const ASSETS := {
	"eye_wizard": "res://models/player_v2/characterSkins/Eye_Wizard.glb",
	"mr_mushroom": "res://models/player_v2/characterSkins/Mr_Mushroom.glb",
	"mr_poop": "res://models/player_v2/characterSkins/Mr_Poop.glb",
	"mr_salt": "res://models/player_v2/characterSkins/Mr_Salt.glb",
	"spooky_witch": "res://models/player_v2/characterSkins/Spooky_Witch.glb",
}
const REQUIRED_BONES := [
	"mixamorig_Hips", "mixamorig_Head", "mixamorig_RightHand",
	"mixamorig_LeftFoot", "mixamorig_RightFoot",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var failed := false
	for model_id in ASSETS:
		var path := str(ASSETS[model_id])
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("NEW_CHARACTER_ASSET_PROBE missing %s" % path)
			failed = true
			continue
		var instance := packed.instantiate() as Node3D
		root.add_child(instance)
		var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
		var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var bounds_result := _visible_bounds(instance)
		var missing: Array[String] = []
		for bone_name in REQUIRED_BONES:
			if skeleton == null or skeleton.find_bone(bone_name) < 0:
				missing.append(bone_name)
		var mesh_count := 0
		var skinned_mesh_count := 0
		var surface_count := 0
		var bind_names := {}
		for node in instance.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			mesh_count += 1
			if mesh_instance.mesh != null:
				surface_count += mesh_instance.mesh.get_surface_count()
			if mesh_instance.skin != null:
				skinned_mesh_count += 1
				for bind_index in mesh_instance.skin.get_bind_count():
					bind_names[str(mesh_instance.skin.get_bind_name(bind_index))] = true
		var animation_names: Array[String] = []
		if player != null:
			for animation_name in player.get_animation_list():
				animation_names.append(str(animation_name))
		var bounds := bounds_result.get("bounds", AABB()) as AABB
		var head_rest := Vector3.ZERO
		var hips_rest := Vector3.ZERO
		if skeleton != null:
			var head_index := skeleton.find_bone("mixamorig_Head")
			var hips_index := skeleton.find_bone("mixamorig_Hips")
			if head_index >= 0:
				head_rest = skeleton.get_bone_global_rest(head_index).origin
			if hips_index >= 0:
				hips_rest = skeleton.get_bone_global_rest(hips_index).origin
		print("NEW_CHARACTER_ASSET model=%s file_bytes=%d bones=%d binds=%d meshes=%d skinned=%d surfaces=%d missing=%s bounds_pos=%s bounds_size=%s head_rest=%s hips_rest=%s animations=%s" % [
			model_id, FileAccess.get_file_as_bytes(path).size(),
			skeleton.get_bone_count() if skeleton != null else 0,
			bind_names.size(), mesh_count, skinned_mesh_count, surface_count,
			str(missing), str(bounds.position), str(bounds.size),
			str(head_rest), str(hips_rest), str(animation_names)])
		if skeleton == null or not missing.is_empty() or skinned_mesh_count == 0:
			failed = true
		instance.queue_free()
		await process_frame
	print("NEW_CHARACTER_ASSET_PROBE: %s" % ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)


func _visible_bounds(root_node: Node3D) -> Dictionary:
	var result := AABB()
	var has_bounds := false
	for node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or not mesh_instance.visible:
			continue
		var transformed := _transformed_aabb(
			mesh_instance.mesh.get_aabb(), _relative_transform(root_node, mesh_instance))
		result = transformed if not has_bounds else result.merge(transformed)
		has_bounds = true
	return {"ok": has_bounds, "bounds": result}


func _relative_transform(ancestor: Node3D, descendant: Node3D) -> Transform3D:
	if ancestor == descendant:
		return Transform3D.IDENTITY
	var result := Transform3D.IDENTITY
	var current: Node = descendant
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _transformed_aabb(box: AABB, transform_value: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	for x in [0.0, 1.0]:
		for y in [0.0, 1.0]:
			for z in [0.0, 1.0]:
				var point := transform_value * (box.position + Vector3(
					box.size.x * x, box.size.y * y, box.size.z * z))
				if first:
					result = AABB(point, Vector3.ZERO)
					first = false
				else:
					result = result.expand(point)
	return result
