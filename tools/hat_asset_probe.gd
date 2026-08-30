extends Node

# All-model runtime validation for every shipped Hat. This intentionally uses
# the same registry and PlayerV2Visual socket path as gameplay, Locker, Prize
# Counter, lobby actors, spectators, decoys, and ceremony actors.

const HatRegistry = preload("res://models/cosmetics/hats/hat_cosmetic_registry.gd")
const CosmeticRegistry = preload("res://supabase/supabase_cosmetic_registry.gd")
const SkinRegistry = preload("res://player_skin_registry.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if HatRegistry.HATS.size() != 12:
		_fail("expected 12 registered hats, found %d" % HatRegistry.HATS.size())
	var hat_ids: Array = HatRegistry.HATS.keys()
	hat_ids.sort()
	for item_id_value in hat_ids:
		var item_id := str(item_id_value)
		var path := HatRegistry.runtime_path(item_id)
		if path == "" or not ResourceLoader.exists(path):
			_fail("runtime resource missing for %s: %s" % [item_id, path])
			continue
		if not CosmeticRegistry.has_local_visual(item_id, "hat") \
				or CosmeticRegistry.known_slot_for_id(item_id) != "hat":
			_fail("cosmetic registry did not expose %s as a local hat" % item_id)

	for model_id in SkinRegistry.MODEL_IDS:
		var scene := SkinRegistry.load_visual_scene(model_id)
		if scene == null:
			_fail("visual scene missing for %s" % model_id)
			continue
		var visual := scene.instantiate() as Node3D
		visual.set("build_animation_library", false)
		visual.name = "%sHatValidationVisual" % model_id.capitalize()
		add_child(visual)
		await get_tree().process_frame
		var socket := visual.call("get_headwear_socket") as Marker3D
		if socket == null:
			_fail("%s visual has no HeadwearSocket" % model_id)
			visual.queue_free()
			continue
		var character_bounds_result := _visible_bounds(visual)
		if bool(character_bounds_result.get("ok", false)):
			var character_bounds: AABB = character_bounds_result["bounds"]
			print("HAT_MODEL_BOUNDS model=%s center=%s size=%s socket=%s" % [
				model_id, str(visual.to_global(character_bounds.get_center())),
				str(character_bounds.size), str(socket.global_position)])
		var socket_height_range := SkinRegistry.headwear_socket_height_range(model_id)
		if socket.global_position.y < socket_height_range.x \
				or socket.global_position.y > socket_height_range.y:
			_fail("%s headwear socket height %.3f is outside its %.3f–%.3f contract" % [
				model_id, socket.global_position.y,
				socket_height_range.x, socket_height_range.y])
		for item_id_value in hat_ids:
			var item_id := str(item_id_value)
			visual.call("set_hat_cosmetic", item_id)
			await get_tree().process_frame
			await get_tree().process_frame
			var hats := socket.find_children("HatVisual", "Node3D", false, false)
			if hats.size() != 1:
				_fail("%s %s produced %d HatVisual nodes" % [
					model_id, item_id, hats.size()])
				continue
			var hat := hats[0] as Node3D
			if str(hat.get_meta("supabase_hat_id", "")) != item_id:
				_fail("%s %s lost its stable item ID" % [model_id, item_id])
			var bounds_result := _visible_bounds(hat)
			if not bool(bounds_result.get("ok", false)):
				_fail("%s %s has no visible mesh" % [model_id, item_id])
				continue
			var bounds: AABB = bounds_result["bounds"]
			var width := maxf(bounds.size.x, bounds.size.z)
			# Wide-brim authored silhouettes intentionally cover the ears. Keep a
			# generous but finite bound so manual fitting can enlarge them without
			# allowing an obviously accidental multi-meter scale. Fixed-look
			# characters include several materially narrower heads and share the
			# approved 0.65m-class Chef Hat budget.
			var minimum_width := 0.60 \
				if SkinRegistry.uses_fixed_texture(model_id) else 0.75
			if width < minimum_width or width > 2.50:
				_fail("%s %s fitted width %.3f is outside the headwear budget" % [
					model_id, item_id, width])
			if bounds.position.y < -0.65 or bounds.position.y > 0.15:
				_fail("%s %s is not seated on its socket: bottom %.3f" % [
					model_id, item_id, bounds.position.y])
			if bounds.size.y > 2.10:
				_fail("%s %s is implausibly tall after fitting: %.3f" % [
					model_id, item_id, bounds.size.y])
			var world_center := hat.to_global(bounds.get_center())
			print("HAT_RUNTIME_OK model=%s id=%s width=%.3f height=%.3f socket=%s center=%s" % [
				model_id, item_id, width, bounds.size.y,
				str(socket.global_position), str(world_center)])
		visual.call("set_hat_cosmetic", "")
		await get_tree().process_frame
		if socket.find_child("HatVisual", false, false) != null:
			_fail("%s visual did not clear equipped headwear" % model_id)
		visual.queue_free()
		await get_tree().process_frame

	if _failures.is_empty():
		print("HAT_COSMETICS_VALIDATION: PASS hats=%d models=%d previews=%d" % [
			HatRegistry.HATS.size(), SkinRegistry.MODEL_IDS.size(),
			HatRegistry.HATS.size() * SkinRegistry.MODEL_IDS.size()])
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("HatCosmeticsValidation: " + failure)
		get_tree().quit(1)


func _visible_bounds(root: Node3D) -> Dictionary:
	var combined := AABB()
	var has_bounds := false
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root as MeshInstance3D)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	for mesh_instance in meshes:
		if mesh_instance == null or mesh_instance.mesh == null \
				or not mesh_instance.is_visible_in_tree():
			continue
		var relative := root.global_transform.affine_inverse() \
			* mesh_instance.global_transform
		var bounds := relative * mesh_instance.mesh.get_aabb()
		combined = bounds if not has_bounds else combined.merge(bounds)
		has_bounds = true
	return {"ok": has_bounds, "bounds": combined}


func _fail(message: String) -> void:
	_failures.append(message)
