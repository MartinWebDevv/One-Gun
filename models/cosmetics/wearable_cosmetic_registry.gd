class_name WearableCosmeticRegistry
extends RefCounted

const SkinRegistry = preload("res://player_skin_registry.gd")
const HatRegistry = preload("res://models/cosmetics/hats/hat_cosmetic_registry.gd")

const MODE_RIGID := "rigid"
const MODE_SKINNED := "skinned"
const WEARABLE_SLOTS: Array[String] = [
	"hat", "shirt", "pants", "shoes", "accessory",
]

# Rigid cosmetics follow one animated bone. Skinned cosmetics contain a Skin
# whose named binds are redirected to the character's live Skeleton3D. Add new
# locally shipped items here; backend IDs are never treated as resource paths.
#
# Example rigid definition:
# "glasses_round": {
#     "slot": "accessory", "mode": MODE_RIGID, "socket": "face",
#     "path_by_model": {"male": "res://...", "female": "res://..."},
# }
# Example deforming garment definition:
# "shirt_denim": {
#     "slot": "shirt", "mode": MODE_SKINNED,
#     "path_by_model": {"male": "res://...", "female": "res://..."},
# }
const WEARABLES := {}

const SOCKET_BONES := {
	"headwear": "mixamorig_Head",
	"face": "mixamorig_Head",
	"neck": "mixamorig_Neck",
	"chest": "mixamorig_Spine2",
	"back": "mixamorig_Spine2",
	"hips": "mixamorig_Hips",
	"left_foot": "mixamorig_LeftFoot",
	"right_foot": "mixamorig_RightFoot",
}


static func sanitize_slot(value: String) -> String:
	var safe := value.strip_edges().to_lower()
	return safe if safe in WEARABLE_SLOTS else ""


static func sanitize_item_id(value: String) -> String:
	var source := value.strip_edges().to_lower().substr(0, 64)
	var result := ""
	for character in source:
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-.":
			result += character
	return result


static func has_local_visual(item_id: String, slot := "") -> bool:
	var safe_id := sanitize_item_id(item_id)
	var safe_slot := sanitize_slot(slot)
	if safe_slot == "hat":
		return HatRegistry.has_hat(safe_id)
	if not WEARABLES.has(safe_id):
		return false
	var data: Dictionary = WEARABLES[safe_id]
	if safe_slot != str(data.get("slot", "")):
		return false
	if str(data.get("path", "")) != "":
		return true
	var by_model = data.get("path_by_model", {})
	if by_model is Dictionary:
		for path_value in (by_model as Dictionary).values():
			if str(path_value) != "":
				return true
	return false


static func slot_for_id(item_id: String) -> String:
	var safe_id := sanitize_item_id(item_id)
	if HatRegistry.has_hat(safe_id):
		return "hat"
	return str((WEARABLES.get(safe_id, {}) as Dictionary).get("slot", "")) \
		if WEARABLES.has(safe_id) else ""


static func definition(item_id: String, slot: String, model_id: String) -> Dictionary:
	var safe_id := sanitize_item_id(item_id)
	var safe_slot := sanitize_slot(slot)
	var safe_model := SkinRegistry.sanitize_model_id(model_id)
	if safe_slot == "hat" and HatRegistry.has_hat(safe_id):
		return {
			"id": safe_id,
			"slot": "hat",
			"mode": MODE_RIGID,
			"socket": "headwear",
			"model_id": safe_model,
		}
	if not WEARABLES.has(safe_id):
		return {}
	var data: Dictionary = WEARABLES[safe_id]
	if str(data.get("slot", "")) != safe_slot:
		return {}
	var path := _runtime_path(data, safe_model)
	if path == "" or not ResourceLoader.exists(path):
		return {}
	var result := data.duplicate(true)
	result["id"] = safe_id
	result["model_id"] = safe_model
	result["path"] = path
	return result


static func instantiate_visual(item_id: String, slot: String,
		model_id: String) -> Node3D:
	var data := definition(item_id, slot, model_id)
	if data.is_empty():
		return null
	var safe_id := str(data["id"])
	if str(data["slot"]) == "hat":
		return HatRegistry.instantiate_hat(safe_id, model_id)
	var packed := load(str(data.get("path", ""))) as PackedScene
	if packed == null:
		return null
	var imported := packed.instantiate() as Node3D
	if imported == null:
		return null
	var holder := Node3D.new()
	holder.name = "%sVisual" % str(data["slot"]).capitalize()
	holder.set_meta("one_gun_cosmetic_id", safe_id)
	holder.set_meta("one_gun_cosmetic_slot", str(data["slot"]))
	holder.set_meta("one_gun_attachment_mode", str(data.get("mode", MODE_RIGID)))
	imported.name = "ImportedWearable"
	holder.add_child(imported)
	_disable_embedded_animation(imported)
	_apply_local_transform(imported, data, SkinRegistry.sanitize_model_id(model_id))
	return holder


static func socket_bone(socket_name: String) -> String:
	return str(SOCKET_BONES.get(socket_name, ""))


static func _runtime_path(data: Dictionary, model_id: String) -> String:
	var by_model = data.get("path_by_model", {})
	if by_model is Dictionary:
		var safe_model := SkinRegistry.sanitize_model_id(model_id)
		var exact := str((by_model as Dictionary).get(safe_model, ""))
		if exact != "":
			return exact
	return str(data.get("path", ""))


static func _apply_local_transform(imported: Node3D, data: Dictionary,
		model_id: String) -> void:
	var fit: Dictionary = {}
	var by_model = data.get("transform_by_model", {})
	if by_model is Dictionary:
		var candidate = (by_model as Dictionary).get(model_id, {})
		if candidate is Dictionary:
			fit = candidate
	imported.position = fit.get("position", data.get("position", Vector3.ZERO))
	imported.rotation_degrees = fit.get(
		"rotation_degrees", data.get("rotation_degrees", Vector3.ZERO))
	var scale_value = fit.get("scale", data.get("scale", Vector3.ONE))
	imported.scale = scale_value if scale_value is Vector3 \
		else Vector3.ONE * float(scale_value)


static func _disable_embedded_animation(root: Node3D) -> void:
	for node in root.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		player.stop()
		player.process_mode = Node.PROCESS_MODE_DISABLED
