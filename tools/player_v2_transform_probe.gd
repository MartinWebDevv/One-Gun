extends Node

const SOURCES := {
	"master": "res://models/player_v2/OGCatModelV2_Rigged.glb",
	"idle_fbx": "res://models/player_v2/animations/Idle.fbx",
	"standard_run_fbx": "res://models/player_v2/animations/Standard Run.fbx",
	"run_fbx": "res://models/player_v2/animations/Running.fbx",
	"jump_fbx": "res://models/player_v2/animations/Jumping.fbx",
	"melee_fbx": "res://models/player_v2/animations/melee.fbx",
}


func _ready() -> void:
	for label in SOURCES:
		_probe_source(label, str(SOURCES[label]))
	_probe_runtime.call_deferred()


func _probe_source(label: String, path: String) -> void:
	var packed := load(path) as PackedScene
	var instance := packed.instantiate()
	add_child(instance)
	print("PROBE_SOURCE ", label)
	_print_nodes(instance, instance)
	var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	_print_skin_binds(label, instance, skeleton)
	var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("PROBE_AP ", label, " path=", instance.get_path_to(player),
		" root=", player.root_node)
	if player != null:
		for animation_name in player.get_animation_list():
			if animation_name == "RESET":
				continue
			var animation := player.get_animation(animation_name)
			print("PROBE_ANIM ", label, " name=", animation_name,
				" length=", animation.length)
			_print_hips_tracks(animation)
			player.play(animation_name)
			player.advance(minf(animation.length * 0.25, 0.2))
			_print_bones(label + "_animated", skeleton)
			break
	instance.queue_free()


func _probe_runtime() -> void:
	await get_tree().process_frame
	var packed := load("res://models/player_v2/player_v2_visual.tscn") as PackedScene
	var visual := packed.instantiate()
	add_child(visual)
	await get_tree().process_frame
	var player := visual.call("ensure_animation_library") as AnimationPlayer
	var skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
	for animation_name in ["idle", "standard_run", "jump", "melee"]:
		player.play(animation_name)
		player.advance(minf(player.get_animation(animation_name).length * 0.25, 0.2))
		_print_bones("runtime_" + animation_name, skeleton)
		_print_bounds("runtime_" + animation_name, visual)
	get_tree().quit(0)


func _print_nodes(root: Node, node: Node) -> void:
	if node is Node3D:
		var node_3d := node as Node3D
		print("PROBE_NODE ", root.get_path_to(node), " pos=", node_3d.position,
			" rot_deg=", node_3d.rotation_degrees, " scale=", node_3d.scale)
	for child in node.get_children():
		_print_nodes(root, child)


func _print_skin_binds(label: String, root: Node, skeleton: Skeleton3D) -> void:
	var mesh_instance := root.find_child("*", true, false) as MeshInstance3D
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		mesh_instance = candidate as MeshInstance3D
		if mesh_instance.skin != null:
			break
	if mesh_instance == null or mesh_instance.skin == null:
		print("PROBE_SKIN ", label, " missing")
		return
	var skin := mesh_instance.skin
	print("PROBE_SKIN ", label, " binds=", skin.get_bind_count(),
		" mesh_aabb=", mesh_instance.mesh.get_aabb(),
		" mesh_transform=", mesh_instance.transform,
		" skeleton_path=", mesh_instance.skeleton)
	for bind_index in skin.get_bind_count():
		var bone_index := skin.get_bind_bone(bind_index)
		var bind_name := str(skin.get_bind_name(bind_index))
		var resolved_name := bind_name
		if resolved_name.is_empty() and bone_index >= 0:
			resolved_name = skeleton.get_bone_name(bone_index)
		if resolved_name not in ["mixamorig_Hips", "mixamorig_Spine",
				"mixamorig_Head", "mixamorig_LeftToeBase"]:
			continue
		var pose := skin.get_bind_pose(bind_index)
		var skeleton_index := skeleton.find_bone(resolved_name)
		print("PROBE_BIND ", label, " ", resolved_name,
			" bind_bone=", bone_index, " bind_name=", bind_name,
			" pose=", pose,
			" rest=", skeleton.get_bone_global_rest(skeleton_index))


func _print_hips_tracks(animation: Animation) -> void:
	for track_index in animation.get_track_count():
		var path_text := str(animation.track_get_path(track_index))
		if not path_text.ends_with(":mixamorig_Hips"):
			continue
		var first_value = animation.track_get_key_value(track_index, 0) \
			if animation.track_get_key_count(track_index) > 0 else null
		var sample_time := minf(animation.length * 0.25, 0.2)
		var sample_value = animation.position_track_interpolate(
			track_index, sample_time) \
			if animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D \
			else animation.rotation_track_interpolate(track_index, sample_time)
		print("PROBE_HIPS_TRACK type=", animation.track_get_type(track_index),
			" path=", path_text, " first=", first_value,
			" sample_time=", sample_time, " sample=", sample_value)


func _print_bones(label: String, skeleton: Skeleton3D) -> void:
	for bone_name in ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_Head",
			"mixamorig_LeftFoot", "mixamorig_RightFoot",
			"mixamorig_LeftToeBase", "mixamorig_RightToeBase"]:
		var index := skeleton.find_bone(bone_name)
		var pose := skeleton.get_bone_pose(index)
		var global_pose := skeleton.get_bone_global_pose(index)
		var world_pose := skeleton.global_transform * global_pose
		print("PROBE_BONE ", label, " ", bone_name,
			" local_pos=", pose.origin,
			" local_rot_deg=", pose.basis.get_euler() * 180.0 / PI,
			" global_pos=", global_pose.origin,
			" global_rot_deg=", global_pose.basis.get_euler() * 180.0 / PI,
			" world_pos=", world_pose.origin,
			" world_rot_deg=", world_pose.basis.orthonormalized().get_euler() * 180.0 / PI)


func _print_bounds(label: String, root: Node3D) -> void:
	var combined := AABB()
	var found := false
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		var world_bounds := mesh_instance.global_transform * mesh_instance.get_aabb()
		combined = world_bounds if not found else combined.merge(world_bounds)
		found = true
	print("PROBE_BOUNDS ", label, " ", combined)
