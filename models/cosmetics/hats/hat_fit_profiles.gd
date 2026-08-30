class_name HatFitProfiles
extends Resource

# Editor-authored fit overrides. Source GLBs and the registry's conservative
# defaults remain untouched; this resource contains only deliberate per-model
# adjustments made with the Hat Fitting Tool.

const SkinRegistry = preload("res://player_skin_registry.gd")
const FIT_KEYS := ["width", "seat_depth", "offset", "rotation_degrees"]

@export var fits: Dictionary = {}


func fit_for(hat_id: String, model_id: String) -> Dictionary:
	var safe_hat := _safe_hat_key(hat_id)
	var safe_model := _safe_model_key(model_id)
	if safe_hat == "" or safe_model == "":
		return {}
	var per_hat = fits.get(safe_hat, {})
	if not per_hat is Dictionary:
		return {}
	var value = (per_hat as Dictionary).get(safe_model, {})
	return _normalized_fit(value) if value is Dictionary else {}


func has_fit(hat_id: String, model_id: String) -> bool:
	return not fit_for(hat_id, model_id).is_empty()


func set_fit(hat_id: String, model_id: String, value: Dictionary) -> bool:
	var safe_hat := _safe_hat_key(hat_id)
	var safe_model := _safe_model_key(model_id)
	if safe_hat == "" or safe_model == "":
		return false
	var normalized := _normalized_fit(value)
	if normalized.size() != FIT_KEYS.size():
		return false
	var next := fits.duplicate(true)
	var per_hat: Dictionary = next.get(safe_hat, {}).duplicate(true) \
		if next.get(safe_hat, {}) is Dictionary else {}
	per_hat[safe_model] = normalized
	next[safe_hat] = per_hat
	fits = next
	emit_changed()
	return true


func clear_fit(hat_id: String, model_id: String) -> bool:
	var safe_hat := _safe_hat_key(hat_id)
	var safe_model := _safe_model_key(model_id)
	if safe_hat == "" or safe_model == "" or not fits.has(safe_hat):
		return false
	var next := fits.duplicate(true)
	var per_hat = next.get(safe_hat, {})
	if not per_hat is Dictionary or not (per_hat as Dictionary).has(safe_model):
		return false
	(per_hat as Dictionary).erase(safe_model)
	if (per_hat as Dictionary).is_empty():
		next.erase(safe_hat)
	else:
		next[safe_hat] = per_hat
	fits = next
	emit_changed()
	return true


static func normalize_fit(value: Dictionary) -> Dictionary:
	return _normalized_fit(value)


static func _normalized_fit(value: Dictionary) -> Dictionary:
	if value.is_empty():
		return {}
	var offset_value = value.get("offset", Vector3.ZERO)
	var rotation_value = value.get("rotation_degrees", Vector3.ZERO)
	var offset: Vector3 = offset_value if offset_value is Vector3 else Vector3.ZERO
	var rotation: Vector3 = rotation_value if rotation_value is Vector3 else Vector3.ZERO
	return {
		"width": clampf(float(value.get("width", 1.0)), 0.25, 3.0),
		"seat_depth": clampf(float(value.get("seat_depth", -0.06)), -1.0, 1.0),
		"offset": Vector3(
			clampf(offset.x, -2.0, 2.0),
			clampf(offset.y, -2.0, 2.0),
			clampf(offset.z, -2.0, 2.0)),
		"rotation_degrees": Vector3(
			clampf(rotation.x, -180.0, 180.0),
			clampf(rotation.y, -180.0, 180.0),
			clampf(rotation.z, -180.0, 180.0)),
	}


static func _safe_hat_key(value: String) -> String:
	var source := value.strip_edges().to_lower().substr(0, 64)
	var result := ""
	for character in source:
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-.":
			result += character
	return result


static func _safe_model_key(value: String) -> String:
	var safe := value.strip_edges().to_lower()
	return safe if safe in SkinRegistry.MODEL_IDS else ""
