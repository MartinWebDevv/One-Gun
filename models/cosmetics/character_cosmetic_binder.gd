class_name CharacterCosmeticBinder
extends RefCounted

const SkinRegistry = preload("res://player_skin_registry.gd")
const WearableRegistry = preload("res://models/cosmetics/wearable_cosmetic_registry.gd")

var _visual: Node3D = null
var _skeleton: Skeleton3D = null
var _model_id := SkinRegistry.DEFAULT_MODEL_ID
var _sockets: Dictionary = {}
var _active_visuals: Dictionary = {}
var _active_ids: Dictionary = {}


func configure(visual: Node3D, skeleton: Skeleton3D, model_id: String) -> void:
	_visual = visual
	_skeleton = skeleton
	_model_id = SkinRegistry.sanitize_model_id(model_id)
	# Keep the established public socket available to previews and fitting tools,
	# even when no Hat is equipped.
	_ensure_socket("headwear")


func set_loadout(raw_loadout) -> void:
	var loadout: Dictionary = raw_loadout if raw_loadout is Dictionary else {}
	for slot in WearableRegistry.WEARABLE_SLOTS:
		set_slot(slot, str(loadout.get(slot, "")))


func set_slot(slot: String, item_id: String) -> void:
	var safe_slot := WearableRegistry.sanitize_slot(slot)
	if safe_slot == "":
		return
	var safe_id := WearableRegistry.sanitize_item_id(item_id)
	if not WearableRegistry.has_local_visual(safe_id, safe_slot):
		safe_id = ""
	if str(_active_ids.get(safe_slot, "")) == safe_id \
			and (safe_id == "" or is_instance_valid(_active_visuals.get(safe_slot))):
		return
	_clear_slot(safe_slot)
	_active_ids[safe_slot] = safe_id
	if safe_id == "" or _visual == null or _skeleton == null:
		return
	var data := WearableRegistry.definition(safe_id, safe_slot, _model_id)
	var wearable := WearableRegistry.instantiate_visual(
		safe_id, safe_slot, _model_id)
	if data.is_empty() or wearable == null:
		return
	var mode := str(data.get("mode", WearableRegistry.MODE_RIGID))
	if mode == WearableRegistry.MODE_RIGID:
		var socket := _ensure_socket(str(data.get("socket", "")))
		if socket == null:
			wearable.free()
			return
		socket.add_child(wearable)
	elif mode == WearableRegistry.MODE_SKINNED:
		_visual.add_child(wearable)
		if not _bind_skinned_visual(wearable):
			wearable.free()
			return
	else:
		push_warning("CharacterCosmeticBinder: unsupported attachment mode '%s'." % mode)
		wearable.free()
		return
	_active_visuals[safe_slot] = wearable


func get_socket(socket_name: String) -> Marker3D:
	return _sockets.get(socket_name) as Marker3D


func attachment_mode(item_id: String, slot: String) -> String:
	return str(WearableRegistry.definition(item_id, slot, _model_id).get("mode", ""))


func _clear_slot(slot: String) -> void:
	var current = _active_visuals.get(slot)
	if is_instance_valid(current):
		(current as Node).free()
	_active_visuals.erase(slot)


func _ensure_socket(socket_name: String) -> Marker3D:
	if _sockets.has(socket_name) and is_instance_valid(_sockets[socket_name]):
		return _sockets[socket_name] as Marker3D
	if _skeleton == null:
		return null
	var bone_name := WearableRegistry.socket_bone(socket_name)
	var bone_index := _skeleton.find_bone(bone_name)
	if bone_name == "" or bone_index < 0:
		push_warning("CharacterCosmeticBinder: socket '%s' has no compatible bone on %s." \
			% [socket_name, _model_id])
		return null
	var attachment := BoneAttachment3D.new()
	attachment.name = "%sBoneAttachment" % _node_name(socket_name)
	attachment.bone_name = bone_name
	_skeleton.add_child(attachment)
	# Give newly-created runtime sockets the correct transform immediately; the
	# BoneAttachment3D takes over on the next skeleton update.
	attachment.transform = _skeleton.get_bone_global_pose(bone_index)
	var marker := Marker3D.new()
	marker.name = "%sSocket" % _node_name(socket_name)
	attachment.add_child(marker)
	if socket_name == "headwear":
		marker.global_transform = _headwear_reference_transform(bone_index)
	_sockets[socket_name] = marker
	return marker


func _headwear_reference_transform(head_index: int) -> Transform3D:
	var head_transform := _skeleton.global_transform \
		* _skeleton.get_bone_global_pose(head_index)
	var visual_basis := _visual.global_basis.orthonormalized()
	return Transform3D(visual_basis, head_transform.origin
		+ visual_basis.y * SkinRegistry.headwear_socket_height(_model_id)
		+ visual_basis.z * SkinRegistry.headwear_socket_forward(_model_id))


func _bind_skinned_visual(root: Node3D) -> bool:
	var skinned_meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D and (root as MeshInstance3D).skin != null:
		skinned_meshes.append(root as MeshInstance3D)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.skin != null:
			skinned_meshes.append(mesh_instance)
	if skinned_meshes.is_empty():
		push_warning("CharacterCosmeticBinder: skinned wearable has no skinned mesh.")
		return false
	for mesh_instance in skinned_meshes:
		var missing := missing_skin_bones(mesh_instance.skin, _skeleton)
		if not missing.is_empty():
			push_warning("CharacterCosmeticBinder: wearable is incompatible with %s; missing binds: %s" \
				% [_model_id, ", ".join(missing)])
			return false
	for mesh_instance in skinned_meshes:
		mesh_instance.skeleton = mesh_instance.get_path_to(_skeleton)
	return true


static func missing_skin_bones(skin: Skin, skeleton: Skeleton3D) -> Array[String]:
	var missing: Array[String] = []
	if skin == null or skeleton == null:
		missing.append("<missing skin or skeleton>")
		return missing
	for bind_index in skin.get_bind_count():
		var bind_name := str(skin.get_bind_name(bind_index))
		if bind_name == "":
			missing.append("<unnamed bind %d>" % bind_index)
		elif skeleton.find_bone(bind_name) < 0:
			missing.append(bind_name)
	return missing


static func _node_name(value: String) -> String:
	var result := ""
	for part in value.split("_", false):
		result += part.capitalize()
	return result
