extends Node

# Data, runtime integration, and editor-scene validation for the Hat Fitting
# Tool. This never saves to the live fit-profile resource.

const HatRegistry = preload("res://models/cosmetics/hats/hat_cosmetic_registry.gd")
const FitProfileSchema = preload("res://models/cosmetics/hats/hat_fit_profiles.gd")
const SkinRegistry = preload("res://player_skin_registry.gd")
const ToolScene = preload("res://tools/hat_fitting_tool.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_validate_profile_round_trip()
	_validate_registry_fits()
	_validate_transient_runtime_fit()
	await _validate_tool_scene()
	if _failures.is_empty():
		print("HAT_FITTING_TOOL_VALIDATION: PASS hats=%d models=%d previews=%d" % [
			HatRegistry.HATS.size(), SkinRegistry.MODEL_IDS.size(),
			HatRegistry.HATS.size() * SkinRegistry.MODEL_IDS.size()])
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("HatFittingToolValidation: " + failure)
	get_tree().quit(1)


func _validate_profile_round_trip() -> void:
	var profile: Resource = FitProfileSchema.new()
	var requested := {
		"width": 1.234,
		"seat_depth": -0.087,
		"offset": Vector3(0.012, -0.021, 0.034),
		"rotation_degrees": Vector3(3.0, -7.5, 1.0),
	}
	for model_id in SkinRegistry.MODEL_IDS:
		_check(profile.call("set_fit", "hat_top", model_id, requested),
			"profile rejected a complete %s fit" % model_id)
		_check(profile.call("has_fit", "hat_top", model_id),
			"profile did not report its saved %s fit" % model_id)
		var returned: Dictionary = profile.call("fit_for", "hat_top", model_id)
		_check(_fits_equal(requested, returned),
			"profile did not round-trip all %s fit properties" % model_id)
	_check(not profile.call("set_fit", "hat_top", "unknown_model", requested),
		"profile accepted an unknown character model")
	var temp_path := "user://hat_fitting_tool_validation.tres"
	var save_error := ResourceSaver.save(profile, temp_path)
	_check(save_error == OK, "temporary profile could not be saved")
	if save_error == OK:
		var loaded := ResourceLoader.load(
			temp_path, "", ResourceLoader.CACHE_MODE_REPLACE)
		for model_id in SkinRegistry.MODEL_IDS:
			_check(loaded != null and loaded.call("has_fit", "hat_top", model_id),
				"saved %s profile could not be reloaded" % model_id)
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	if FileAccess.file_exists(absolute_temp):
		DirAccess.remove_absolute(absolute_temp)
	for model_id in SkinRegistry.MODEL_IDS:
		_check(profile.call("clear_fit", "hat_top", model_id),
			"profile could not clear a saved %s override" % model_id)
		_check(not profile.call("has_fit", "hat_top", model_id),
			"cleared %s profile still returned an override" % model_id)


func _validate_registry_fits() -> void:
	_check(ResourceLoader.exists(HatRegistry.FIT_PROFILE_PATH),
		"live fit-profile resource is missing")
	_check(HatRegistry.HATS.size() == 12,
		"expected 12 registered hats, found %d" % HatRegistry.HATS.size())
	for model_id in SkinRegistry.MODEL_IDS:
		_check(SkinRegistry.MODEL_SCENES.has(model_id),
			"%s is registered without a visual scene" % model_id)
		_check(SkinRegistry.has_headwear_profile(model_id),
			"%s is registered without an explicit headwear profile" % model_id)
		var socket_range := SkinRegistry.headwear_socket_height_range(model_id)
		_check(socket_range.x > 0.0 and socket_range.y > socket_range.x,
			"%s has an invalid headwear socket-height range" % model_id)
		var chain := SkinRegistry.headwear_fit_model_chain(model_id)
		_check(not chain.is_empty() and chain[0] == model_id,
			"%s has an invalid headwear fit chain" % model_id)
		_check(model_id == SkinRegistry.DEFAULT_MODEL_ID or chain.size() > 1,
			"%s must explicitly inherit a compatible Hat fit model" % model_id)
		_check(chain.is_empty() or chain[-1] == SkinRegistry.DEFAULT_MODEL_ID,
			"%s Hat fit chain does not resolve to the default model" % model_id)
	for hat_id_value in HatRegistry.HATS.keys():
		var hat_id := str(hat_id_value)
		for model_id in SkinRegistry.MODEL_IDS:
			var base := HatRegistry.default_fit(hat_id, model_id)
			var resolved := HatRegistry.resolved_fit(hat_id, model_id)
			_check(_is_complete_fit(base), "%s %s base fit is incomplete" % [
				model_id, hat_id])
			_check(_is_complete_fit(resolved), "%s %s resolved fit is incomplete" % [
				model_id, hat_id])
			var hat := HatRegistry.instantiate_hat(hat_id, model_id)
			_check(hat != null, "%s %s could not instantiate" % [model_id, hat_id])
			if hat != null:
				_check(hat.find_child("ImportedHat", true, false) != null,
					"%s %s has no fitted ImportedHat" % [model_id, hat_id])
				hat.free()

	# Exercise the real shared profile merge in memory, then restore it before
	# any UI scene is created. The live .tres is never written by this test.
	var snapshot: Dictionary = HatRegistry.FIT_PROFILES.fits.duplicate(true)
	var probe_model := SkinRegistry.MODEL_IDS[-1]
	var probe_fit := HatRegistry.default_fit("hat_top", probe_model)
	probe_fit["offset"] = Vector3(0.023, -0.014, 0.031)
	_check(HatRegistry.FIT_PROFILES.set_fit("hat_top", probe_model, probe_fit),
		"shared profile rejected an in-memory integration fit")
	_check((HatRegistry.resolved_fit("hat_top", probe_model)["offset"] as Vector3) \
		.is_equal_approx(probe_fit["offset"] as Vector3),
		"saved profile override did not merge into runtime fit resolution")
	HatRegistry.FIT_PROFILES.set("fits", snapshot)
	HatRegistry.FIT_PROFILES.emit_changed()

	# Prove the declared fallback works for a model with no exact override.
	snapshot = HatRegistry.FIT_PROFILES.fits.duplicate(true)
	var inherited_model := SkinRegistry.MODEL_IDS[-1]
	var fallback_model := SkinRegistry.headwear_fit_fallback_model_id(inherited_model)
	if fallback_model != "":
		HatRegistry.FIT_PROFILES.clear_fit("hat_top", inherited_model)
		var fallback_fit := HatRegistry.default_fit("hat_top", fallback_model)
		fallback_fit["offset"] = Vector3(-0.031, 0.016, -0.027)
		_check(HatRegistry.FIT_PROFILES.set_fit(
			"hat_top", fallback_model, fallback_fit),
			"fallback model rejected the inheritance probe")
		_check((HatRegistry.resolved_fit("hat_top", inherited_model)["offset"] as Vector3) \
			.is_equal_approx(fallback_fit["offset"] as Vector3),
			"%s did not inherit its declared %s Hat fit" % [
				inherited_model, fallback_model])
	HatRegistry.FIT_PROFILES.set("fits", snapshot)
	HatRegistry.FIT_PROFILES.emit_changed()


func _validate_transient_runtime_fit() -> void:
	var hat_id := "hat_top"
	var model_id := "male"
	var base: Dictionary = HatRegistry.resolved_fit(hat_id, model_id)
	var base_hat := HatRegistry.instantiate_hat(hat_id, model_id, base)
	if base_hat == null:
		_fail("transient-fit reference hat could not instantiate")
		return
	var base_import := base_hat.find_child("ImportedHat", true, false) as Node3D
	if base_import == null:
		_fail("transient-fit reference has no ImportedHat")
		base_hat.free()
		return

	var delta := Vector3(0.037, -0.019, 0.052)
	var offset_fit := base.duplicate(true)
	offset_fit["offset"] = (base["offset"] as Vector3) + delta
	var offset_hat := HatRegistry.instantiate_hat(hat_id, model_id, offset_fit)
	var offset_import := offset_hat.find_child(
		"ImportedHat", true, false) as Node3D if offset_hat != null else null
	_check(offset_import != null and offset_import.position.is_equal_approx(
		base_import.position + delta),
		"transient position offset did not reach the runtime hat")

	var scale_fit := base.duplicate(true)
	scale_fit["width"] = float(base["width"]) * 1.1
	var scale_hat := HatRegistry.instantiate_hat(hat_id, model_id, scale_fit)
	var scale_import := scale_hat.find_child(
		"ImportedHat", true, false) as Node3D if scale_hat != null else null
	_check(scale_import != null and is_equal_approx(
		scale_import.scale.x / base_import.scale.x, 1.1),
		"transient width did not scale the runtime hat")

	var rotation_fit := base.duplicate(true)
	rotation_fit["rotation_degrees"] = Vector3(5.0, -12.0, 2.5)
	var rotation_hat := HatRegistry.instantiate_hat(hat_id, model_id, rotation_fit)
	var rotation_import := rotation_hat.find_child(
		"ImportedHat", true, false) as Node3D if rotation_hat != null else null
	_check(rotation_import != null and rotation_import.rotation_degrees.is_equal_approx(
		Vector3(5.0, -12.0, 2.5)),
		"transient rotation did not reach the runtime hat")

	base_hat.free()
	if offset_hat != null:
		offset_hat.free()
	if scale_hat != null:
		scale_hat.free()
	if rotation_hat != null:
		rotation_hat.free()


func _validate_tool_scene() -> void:
	var tool := ToolScene.instantiate() as Control
	add_child(tool)
	await _wait_frames(4)
	var hat_picker := tool.find_child("HatPicker", true, false) as OptionButton
	var model_picker := tool.find_child("ModelPicker", true, false) as OptionButton
	var width_spin := tool.find_child("WidthSpin", true, false) as SpinBox
	var viewport := tool.find_child("HatFitViewport", true, false) as SubViewport
	var save_selected := tool.find_child(
		"SaveSelectedFitButton", true, false) as Button
	_check(hat_picker != null and hat_picker.item_count == 12,
		"tool does not expose all 12 hats")
	_check(model_picker != null \
		and model_picker.item_count == SkinRegistry.MODEL_IDS.size(),
		"tool does not expose every registered character model")
	if model_picker != null:
		for index in SkinRegistry.MODEL_IDS.size():
			_check(str(model_picker.get_item_metadata(index)) \
				== SkinRegistry.MODEL_IDS[index],
				"tool model picker order drifted at index %d" % index)
	_check(width_spin != null and viewport != null,
		"tool is missing its live fit control or isolated preview")
	_check(tool.get("_manual_hat") != null,
		"tool did not mount the first real hat on the first real model")
	_check(save_selected != null and save_selected.disabled,
		"tool enabled Save This Fit before a draft changed")

	if width_spin != null:
		width_spin.value += 0.01
		await _wait_frames(3)
		var dirty: Dictionary = tool.get("_dirty_keys")
		_check(dirty.size() == 1,
			"editing one fit did not create exactly one in-memory draft")
		_check(tool.get("_manual_hat") != null,
			"live preview disappeared after editing a fit")
		_check(save_selected != null and not save_selected.disabled,
			"Save This Fit did not enable after creating a valid draft")
		tool.call("_revert_selected")
		await _wait_frames(2)
		dirty = tool.get("_dirty_keys")
		_check(dirty.is_empty(),
			"Revert Unsaved did not discard the current in-memory draft")
		# Copy a deliberately distinct draft so this remains meaningful even when
		# the destination already owns an exact fit equal to the source's saved fit.
		width_spin.value += 0.02
		await _wait_frames(2)
		var source_hat := str(tool.get("_current_hat"))
		tool.call("_copy_to_next_model")
		await _wait_frames(4)
		dirty = tool.get("_dirty_keys")
		_check(str(tool.get("_current_model")) == "female"
			and dirty.has("%s|female" % source_hat),
			"Copy to Next Model did not switch to/save-enable the female draft")
		_check(save_selected != null and not save_selected.disabled,
			"copied female draft could not be saved with Save This Fit")
		tool.call("_revert_selected")
		await _wait_frames(2)
		tool.call("_copy_to_next_model")
		await _wait_frames(4)
		dirty = tool.get("_dirty_keys")
		var third_model := SkinRegistry.MODEL_IDS[2]
		_check(str(tool.get("_current_model")) == third_model
			and dirty.has("%s|%s" % [source_hat, third_model]),
			"Copy to Next Model did not reach the entitlement model")
		_check(tool.get("_visual") != null and tool.get("_manual_hat") != null,
			"entitlement-model preview did not load a character and Hat")
		tool.call("_revert_selected")
		await _wait_frames(2)

	if model_picker != null:
		# Copy above intentionally moved the live preview through the registered list.
		_check(str(tool.get("_current_model")) == SkinRegistry.MODEL_IDS[2],
			"model picker did not switch the fitting context to the third model")
		_check(tool.get("_visual") != null and tool.get("_manual_hat") != null,
			"third-model preview did not load a character and Hat")
		var idle_player := tool.get("_idle_player") as AnimationPlayer
		_check(idle_player != null and idle_player.current_animation == "idle"
			and idle_player.is_playing(),
			"fitting tool did not animate the hat with the shared idle")

	var camera := tool.get("_camera") as Camera3D
	var before := camera.transform if camera != null else Transform3D.IDENTITY
	tool.call("_set_camera_view", "top")
	_check(camera != null and not camera.transform.is_equal_approx(before),
		"Top view did not reposition the preview camera")
	tool.queue_free()
	await _wait_frames(3)


func _is_complete_fit(fit: Dictionary) -> bool:
	return fit.has("width") and fit.has("seat_depth") and fit.has("offset") \
		and fit.has("rotation_degrees") and fit["offset"] is Vector3 \
		and fit["rotation_degrees"] is Vector3


func _fits_equal(a: Dictionary, b: Dictionary) -> bool:
	return is_equal_approx(float(a.get("width", 0.0)), float(b.get("width", 0.0))) \
		and is_equal_approx(float(a.get("seat_depth", 0.0)),
			float(b.get("seat_depth", 0.0))) \
		and (a.get("offset", Vector3.ZERO) as Vector3).is_equal_approx(
			b.get("offset", Vector3.ZERO) as Vector3) \
		and (a.get("rotation_degrees", Vector3.ZERO) as Vector3).is_equal_approx(
			b.get("rotation_degrees", Vector3.ZERO) as Vector3)


func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
