extends Node

const ProgressionOverlay = preload("res://UI/progression_road_overlay.gd")

var _failed := false


func _ready() -> void:
	OS.set_environment("ONEGUN_UI_CAPTURE", "validation")
	OS.set_environment("ONEGUN_UI_CAPTURE_STATE", "progression")
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failed = true
	push_error("PROGRESSION ROAD PREVIEW: %s" % message)


func _run() -> void:
	await get_tree().process_frame
	var prefs = get_tree().root.get_node("PlayerPrefs")
	var original_model = prefs.settings.get("character_model_id", "male")
	prefs.settings["character_model_id"] = "male"
	var overlay = ProgressionOverlay.new()
	get_tree().root.add_child(overlay)
	for _frame in 8:
		await get_tree().process_frame
	var progression_back := overlay.find_child(
		"ProgressionBackButton", true, false) as Button
	var progression_canvas := overlay.find_child(
		"ProgressionRoadCanvas", true, false) as Control
	_check(progression_back != null and progression_canvas != null
			and progression_back.text == "BACK"
			and str(progression_back.get("variant")) == "navy"
			and progression_back.get_global_rect().get_center().x
				< progression_canvas.get_global_rect().get_center().x
			and progression_back.get_global_rect().get_center().y
				> progression_canvas.get_global_rect().get_center().y,
		"Progression uses the blue bottom-left Back control")

	var rice_button := overlay.find_child(
		"CosmeticMilestoneLevel10", true, false) as Button
	var token_card := overlay.find_child(
		"CosmeticMilestoneLevel5", true, false) as Button
	var pimp_button := overlay.find_child(
		"CosmeticMilestoneTrophy5", true, false) as Button
	_check(rice_button != null and rice_button.focus_mode == Control.FOCUS_ALL,
		"Level 10 Rice Hat milestone is clickable and controller-focusable")
	_check(token_card == null,
		"Gun Token milestones remain informational instead of opening a cosmetic preview")
	_check(pimp_button != null and pimp_button.focus_mode == Control.FOCUS_ALL,
		"Trophy 5 Pimp Hat milestone is clickable and controller-focusable")

	if rice_button != null:
		rice_button.grab_focus()
		rice_button.pressed.emit()
		for _frame in 10:
			await get_tree().process_frame
		var popup = overlay.get("_cosmetic_preview") as Control
		_check(popup != null and popup.find_child(
			"CosmeticPreviewWindow", true, false) != null,
			"Rice Hat milestone opens the small reward preview window")
		_check(popup != null and popup.find_child(
			"CosmeticPreviewCharacter", true, false) != null,
			"Rice Hat preview instantiates the player's character model")
		var rice_visual = popup.find_child("HatVisual", true, false) if popup != null else null
		_check(rice_visual != null and str(rice_visual.get_meta(
			"supabase_hat_id", "")) == "beta_s1_level_30_hat",
			"Rice Hat preview equips the actual Level 10 reward model")
		var preview_pivot := popup.find_child(
			"CosmeticPreviewCharacterPivot", true, false) as Node3D if popup != null else null
		var preview_camera := popup.find_child(
			"CosmeticPreviewCamera", true, false) as Camera3D if popup != null else null
		if preview_pivot != null and preview_camera != null:
			var rotation_before := preview_pivot.rotation.y
			var camera_before: Transform3D = preview_camera.global_transform
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			popup.call("_on_preview_gui_input", press)
			var drag := InputEventMouseMotion.new()
			drag.relative = Vector2(30.0, 0.0)
			popup.call("_on_preview_gui_input", drag)
			_check(not is_equal_approx(preview_pivot.rotation.y, rotation_before),
				"reward preview rotates when dragged")
			_check(preview_camera.global_transform.is_equal_approx(camera_before),
				"drag rotation leaves the reward-preview camera and background fixed")
		var close_button := popup.find_child(
			"CosmeticPreviewCloseButton", true, false) as Button if popup != null else null
		var preview_window := popup.find_child(
			"CosmeticPreviewWindow", true, false) as Control if popup != null else null
		_check(close_button != null and preview_window != null
				and close_button.has_focus() and close_button.text == "BACK"
				and str(close_button.get("variant")) == "navy"
				and close_button.get_global_rect().get_center().x
					< preview_window.get_global_rect().get_center().x
				and close_button.get_global_rect().get_center().y
					> preview_window.get_global_rect().get_center().y,
			"reward preview focuses its blue bottom-left Back control")
		overlay.call("_close_cosmetic_preview")
		await get_tree().process_frame
		_check(overlay.get("_cosmetic_preview") == null and is_instance_valid(overlay),
			"closing the reward preview returns to the progression screen")

	var pending_art_button := overlay.find_child(
		"CosmeticMilestoneTrophy1", true, false) as Button
	_check(pending_art_button != null,
		"art-pending cosmetic milestone remains previewable")
	if pending_art_button != null:
		pending_art_button.pressed.emit()
		for _frame in 10:
			await get_tree().process_frame
		var popup = overlay.get("_cosmetic_preview") as Control
		var character = popup.find_child(
			"CosmeticPreviewCharacter", true, false) if popup != null else null
		var pivot = popup.find_child(
			"CosmeticPreviewCharacterPivot", true, false) as Node3D if popup != null else null
		var idle_player = character.call("get_animation_player") as AnimationPlayer \
			if character != null else null
		_check(character != null and pivot != null \
			and pivot.position.is_equal_approx(Vector3(0.0, 0.20, 0.0)),
			"art-pending reward uses the centered podium character fallback")
		_check(idle_player != null and idle_player.current_animation == "idle" \
			and idle_player.is_playing(),
			"art-pending reward plays the shared idle instead of showing a T-pose")
		overlay.call("_close_cosmetic_preview")
		await get_tree().process_frame

	prefs.settings["character_model_id"] = "female"
	if pimp_button != null:
		pimp_button.pressed.emit()
		for _frame in 10:
			await get_tree().process_frame
		var popup = overlay.get("_cosmetic_preview") as Control
		var character = popup.find_child(
			"CosmeticPreviewCharacter", true, false) if popup != null else null
		var pimp_visual = popup.find_child("HatVisual", true, false) if popup != null else null
		_check(character != null and str(character.get("model_id")) == "female",
			"reward preview uses the player's selected Female character model")
		_check(pimp_visual != null and str(pimp_visual.get_meta(
			"supabase_hat_id", "")) == "beta_s1_ace_hat",
			"Pimp Hat preview equips the actual Trophy 5 reward model")
		var cancel := InputEventAction.new()
		cancel.action = "ui_cancel"
		cancel.pressed = true
		overlay.call("_unhandled_input", cancel)
		await get_tree().process_frame
		_check(overlay.get("_cosmetic_preview") == null and is_instance_valid(overlay),
			"controller Back closes only the preview, not the progression road")

	prefs.settings["character_model_id"] = original_model
	overlay.queue_free()
	await get_tree().process_frame
	if _failed:
		push_error("PROGRESSION ROAD PREVIEW VALIDATION FAILED")
		get_tree().quit(1)
		return
	print("PROGRESSION ROAD PREVIEW VALIDATION: PASS")
	get_tree().quit(0)
