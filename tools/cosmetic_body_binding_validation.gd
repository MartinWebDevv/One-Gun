extends Node

const SkinRegistry = preload("res://player_skin_registry.gd")
const CosmeticBinder = preload("res://models/cosmetics/character_cosmetic_binder.gd")
const WearableRegistry = preload("res://models/cosmetics/wearable_cosmetic_registry.gd")
const TEST_HAT := "hat_top"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for model_id in SkinRegistry.MODEL_IDS:
		await _validate_model(model_id)
	_validate_skin_contract()
	if _failures.is_empty():
		print("COSMETIC_BODY_BINDING_VALIDATION: PASS models=%d rigid=1 skinned-contract=1" \
			% SkinRegistry.MODEL_IDS.size())
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("CosmeticBodyBindingValidation: " + failure)
		get_tree().quit(1)


func _validate_model(model_id: String) -> void:
	var packed := SkinRegistry.load_visual_scene(model_id)
	_check(packed != null, "%s visual scene is unavailable" % model_id)
	if packed == null:
		return
	var visual := packed.instantiate() as Node3D
	visual.set("build_animation_library", false)
	add_child(visual)
	await get_tree().process_frame
	visual.call("set_wearable_cosmetic", "hat", TEST_HAT)
	await get_tree().process_frame
	var socket := visual.call("get_cosmetic_socket", "headwear") as Marker3D
	_check(socket != null, "%s has no semantic headwear socket" % model_id)
	if socket == null:
		visual.queue_free()
		await get_tree().process_frame
		return
	var attachment := socket.get_parent() as BoneAttachment3D
	_check(attachment != null, "%s headwear is not owned by BoneAttachment3D" % model_id)
	_check(attachment != null and attachment.bone_name == "mixamorig_Head",
		"%s headwear is not bound to mixamorig_Head" % model_id)
	var hat := socket.find_child("HatVisual", false, false) as Node3D
	_check(hat != null, "%s did not mount the test Hat" % model_id)
	_check(str(visual.call("cosmetic_attachment_mode", TEST_HAT, "hat")) \
			== WearableRegistry.MODE_RIGID,
		"%s Hat did not resolve through the rigid wearable contract" % model_id)

	var skeleton := visual.call("get_skeleton") as Skeleton3D
	var head_index := skeleton.find_bone("mixamorig_Head") if skeleton != null else -1
	_check(head_index >= 0, "%s has no compatible head bone" % model_id)
	if skeleton != null and head_index >= 0:
		var before := socket.global_transform
		var original_rotation := skeleton.get_bone_pose_rotation(head_index)
		skeleton.set_bone_pose_rotation(head_index,
			original_rotation * Quaternion(Vector3.FORWARD, 0.25))
		await get_tree().process_frame
		await get_tree().process_frame
		var after := socket.global_transform
		_check(not before.is_equal_approx(after),
			"%s socket did not follow an animated head pose" % model_id)
		_check(attachment == null or attachment.transform.is_equal_approx(
				skeleton.get_bone_global_pose(head_index)),
			"%s BoneAttachment3D drifted from the live head pose" % model_id)
		skeleton.set_bone_pose_rotation(head_index, original_rotation)
	visual.queue_free()
	await get_tree().process_frame


func _validate_skin_contract() -> void:
	var packed := SkinRegistry.load_visual_scene(SkinRegistry.DEFAULT_MODEL_ID)
	var visual := packed.instantiate() as Node3D if packed != null else null
	if visual == null:
		_check(false, "default visual unavailable for skinned-garment contract")
		return
	visual.set("build_animation_library", false)
	add_child(visual)
	var skeleton := visual.call("get_skeleton") as Skeleton3D
	var compatible := Skin.new()
	compatible.add_named_bind("mixamorig_Head", Transform3D.IDENTITY)
	_check(CosmeticBinder.missing_skin_bones(compatible, skeleton).is_empty(),
		"matching named Skin binds were rejected")
	var garment_root := Node3D.new()
	garment_root.name = "SyntheticGarment"
	visual.add_child(garment_root)
	var garment_mesh := MeshInstance3D.new()
	garment_mesh.mesh = BoxMesh.new()
	garment_mesh.skin = compatible
	garment_root.add_child(garment_mesh)
	var live_binder = visual.get("_cosmetic_binder")
	_check(live_binder != null \
			and bool(live_binder.call("_bind_skinned_visual", garment_root)),
		"compatible garment mesh was not redirected to the live skeleton")
	_check(garment_mesh.skeleton == garment_mesh.get_path_to(skeleton),
		"garment MeshInstance3D did not retain the live Skeleton3D path")
	var incompatible := Skin.new()
	incompatible.add_named_bind("not_a_character_bone", Transform3D.IDENTITY)
	_check(CosmeticBinder.missing_skin_bones(incompatible, skeleton) \
			== ["not_a_character_bone"],
		"missing garment bones were not rejected")
	visual.queue_free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
