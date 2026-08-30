class_name HatCosmeticRegistry
extends RefCounted

const FIT_PROFILE_PATH := "res://models/cosmetics/hats/hat_fit_profiles.tres"
const FitProfileSchema = preload("res://models/cosmetics/hats/hat_fit_profiles.gd")
const SkinRegistry = preload("res://player_skin_registry.gd")
const FIT_PROFILES = preload(FIT_PROFILE_PATH)

# Supabase cosmetic IDs are never treated as resource paths. Every wearable
# below maps to a fixed, shipped runtime asset and a small amount of fit data.
# The source GLBs remain in source/; large assets use optimized runtime copies.
const HATS := {
	"beta_s1_level_30_hat": {
		"display_name": "Rice Hat",
		"path": "res://models/cosmetics/hats/runtime/Ricehat_runtime.glb",
		"width": 1.20,
		"seat_depth": -0.065,
	},
	"beta_s1_ace_hat": {
		"display_name": "Pimp Hat",
		"path": "res://models/cosmetics/hats/runtime/Pimphat_final_budget.glb",
		"width": 1.10,
		"seat_depth": -0.065,
	},
	"hat_chef": {
		"display_name": "Chef Hat",
		"path": "res://models/cosmetics/hats/runtime/Chefhat.glb",
		"width": 1.10,
		"seat_depth": -0.070,
	},
	"hat_cowboy_classic": {
		"display_name": "Classic Cowboy Hat",
		"path": "res://models/cosmetics/hats/runtime/Cowboyhat.glb",
		"width": 1.5,
		"seat_depth": -0.10,
		"include_meshes": ["CowboyHat"],
	},
	"hat_cowboy_wide": {
		"display_name": "Wide-Brim Cowboy Hat",
		"path": "res://models/cosmetics/hats/runtime/Cowboyhat 2.glb",
		"width": 1.28,
		"seat_depth": -0.060,
	},
	"hat_crown": {
		"display_name": "Royal Crown",
		"path": "res://models/cosmetics/hats/runtime/Crownhat_runtime.glb",
		"width": 1.00,
		"seat_depth": -0.075,
	},
	"hat_fedora_black": {
		"display_name": "Black Fedora",
		"path": "res://models/cosmetics/hats/runtime/Fedorablackhat.glb",
		"width": 1.10,
		"seat_depth": -0.065,
		"include_meshes": ["Circle"],
	},
	"hat_fedora_white": {
		"display_name": "White Fedora",
		"path": "res://models/cosmetics/hats/runtime/FedoraWhitehat.glb",
		"width": 1.10,
		"seat_depth": -0.065,
	},
	"hat_straw_adventurer": {
		"display_name": "Straw Adventurer Hat",
		"path": "res://models/cosmetics/hats/runtime/Luffyhat.glb",
		"width": 1.24,
		"seat_depth": -0.060,
	},
	"hat_top": {
		"display_name": "Top Hat",
		"path": "res://models/cosmetics/hats/runtime/Tophat.glb",
		"width": 1.05,
		"seat_depth": -0.070,
	},
	"hat_witch": {
		"display_name": "Witch Hat",
		"path": "res://models/cosmetics/hats/runtime/Witchhat.glb",
		"width": 1.15,
		"seat_depth": -0.060,
	},
	"hat_yellow_point": {
		"display_name": "Yellow Point Hat",
		"path": "res://models/cosmetics/hats/runtime/Yellowpointhat.glb",
		"width": 1.05,
		"seat_depth": -0.070,
	},
}


static func sanitize_hat_id(value: String) -> String:
	var source := value.strip_edges().to_lower().substr(0, 64)
	var safe_id := ""
	for character in source:
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-.":
			safe_id += character
	return safe_id if HATS.has(safe_id) else ""


static func has_hat(value: String) -> bool:
	return sanitize_hat_id(value) != ""


static func display_name(value: String) -> String:
	var safe_id := sanitize_hat_id(value)
	return str(HATS[safe_id].get("display_name", "Hat")) if safe_id != "" else ""


static func runtime_path(value: String) -> String:
	var safe_id := sanitize_hat_id(value)
	return str(HATS[safe_id].get("path", "")) if safe_id != "" else ""


static func default_fit(value: String, model_id := "male") -> Dictionary:
	var safe_id := sanitize_hat_id(value)
	if safe_id == "":
		return {}
	var safe_model := _safe_model_id(str(model_id))
	var data: Dictionary = HATS[safe_id]
	var fit_by_model = data.get("fit_by_model", {})
	var model_fit: Dictionary = {}
	if fit_by_model is Dictionary:
		for fit_model_id in SkinRegistry.headwear_fit_model_chain(safe_model):
			var candidate = (fit_by_model as Dictionary).get(fit_model_id, {})
			if candidate is Dictionary and not (candidate as Dictionary).is_empty():
				model_fit = candidate as Dictionary
				break
	return {
		"width": float(model_fit.get("width", data.get("width", 0.68))),
		"seat_depth": float(model_fit.get(
			"seat_depth", data.get("seat_depth", -0.06))),
		"offset": model_fit.get("offset", data.get("offset", Vector3.ZERO)),
		"rotation_degrees": model_fit.get(
			"rotation_degrees", data.get("rotation_degrees", Vector3.ZERO)),
	}


static func resolved_fit(value: String, model_id := "male",
		transient_override: Dictionary = {}) -> Dictionary:
	var safe_model := _safe_model_id(str(model_id))
	var result := default_fit(value, safe_model)
	if result.is_empty():
		return {}
	var stored: Dictionary = {}
	if FIT_PROFILES != null:
		# Exact per-model adjustments win. Registered fallback chains preserve an
		# approved fit on compatible character heads until a dedicated adjustment
		# is authored with the fitting tool.
		for fit_model_id in SkinRegistry.headwear_fit_model_chain(safe_model):
			stored = FIT_PROFILES.fit_for(value, fit_model_id)
			if not stored.is_empty():
				break
	for key in stored:
		result[key] = stored[key]
	for key in transient_override:
		if key in ["width", "seat_depth", "offset", "rotation_degrees"]:
			result[key] = transient_override[key]
	return FitProfileSchema.normalize_fit(result)


static func instantiate_hat(value: String, model_id := "male",
		transient_override: Dictionary = {}) -> Node3D:
	var safe_id := sanitize_hat_id(value)
	if safe_id == "":
		return null
	var data: Dictionary = HATS[safe_id]
	var path := str(data.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		push_warning("HatCosmeticRegistry: runtime asset is unavailable for %s." % safe_id)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var imported := packed.instantiate() as Node3D
	if imported == null:
		return null

	var holder := Node3D.new()
	holder.name = "HatVisual"
	holder.set_meta("supabase_hat_id", safe_id)
	imported.name = "ImportedHat"
	holder.add_child(imported)
	_disable_embedded_animation(imported)
	_fit_imported_hat(imported, data, safe_id, _safe_model_id(str(model_id)),
		transient_override)
	return holder


static func _safe_model_id(value: String) -> String:
	return SkinRegistry.sanitize_model_id(value)


static func _disable_embedded_animation(root: Node3D) -> void:
	for node in root.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		player.stop()
		player.process_mode = Node.PROCESS_MODE_DISABLED


static func _fit_imported_hat(imported: Node3D, data: Dictionary,
		hat_id: String, model_id: String,
		transient_override: Dictionary = {}) -> void:
	var include_meshes: Array = data.get("include_meshes", [])
	var bounds := AABB()
	var has_bounds := false
	var meshes: Array[MeshInstance3D] = []
	if imported is MeshInstance3D:
		meshes.append(imported as MeshInstance3D)
	for node in imported.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	for mesh_instance in meshes:
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if not include_meshes.is_empty() and mesh_instance.name not in include_meshes:
			# Some delivered GLBs contain a second unrelated helper/hat mesh. Do
			# not merely exclude it from fitting; hide it from the shipped visual.
			mesh_instance.visible = false
			continue
		var relative := _relative_transform(imported, mesh_instance)
		var mesh_bounds := _transformed_aabb(mesh_instance.mesh.get_aabb(), relative)
		bounds = mesh_bounds if not has_bounds else bounds.merge(mesh_bounds)
		has_bounds = true
	if not has_bounds or bounds.size.length_squared() <= 0.000001:
		push_warning("HatCosmeticRegistry: could not measure %s." % imported.scene_file_path)
		return
	var fit := resolved_fit(hat_id, model_id, transient_override)
	var width := maxf(bounds.size.x, bounds.size.z)
	var scale_factor := float(fit.get("width", 0.68)) / maxf(width, 0.0001)
	var center := bounds.get_center()
	var offset: Vector3 = fit.get("offset", Vector3.ZERO)
	var seat_depth := float(fit.get("seat_depth", -0.06))
	imported.scale = Vector3.ONE * scale_factor
	imported.position = Vector3(
		-center.x * scale_factor,
		-bounds.position.y * scale_factor + seat_depth,
		-center.z * scale_factor) + offset
	imported.rotation_degrees = fit.get("rotation_degrees", Vector3.ZERO)


static func _relative_transform(ancestor: Node3D, descendant: Node3D) -> Transform3D:
	if ancestor == descendant:
		return Transform3D.IDENTITY
	var result := Transform3D.IDENTITY
	var current: Node = descendant
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


static func _transformed_aabb(box: AABB, transform_value: Transform3D) -> AABB:
	var first := true
	var result := AABB()
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
