extends Node

const PREVIEW_SCENE = preload("res://cinematics/startup/startup_intro_arena_chase_final.tscn")
const MAX_SAFE_CAMERA_SPEED := 34.1
const MAX_SAFE_TURN_SPEED := 300.6


func _ready() -> void:
	var preview := PREVIEW_SCENE.instantiate()
	preview.set("show_preview_controls", false)
	add_child(preview)
	while int(preview.get("_state")) != 1:
		await get_tree().process_frame
	var started_at := Time.get_ticks_msec()
	var samples := 0
	while int(preview.get("_state")) != 2 \
			and Time.get_ticks_msec() - started_at < 15_000:
		await get_tree().process_frame
		samples += 1
	var maximum_speed := float(preview.get("_maximum_observed_camera_speed"))
	var maximum_turn_speed := float(preview.get("_maximum_observed_turn_speed"))
	var passed := int(preview.get("_state")) == 2 and samples >= 60 \
		and maximum_speed <= MAX_SAFE_CAMERA_SPEED \
		and maximum_turn_speed <= MAX_SAFE_TURN_SPEED
	if passed:
		print("STARTUP_ARENA_CHASE_MOTION_VALIDATION: PASS samples=%d speed=%.2f turn=%.2f" % [
			samples, maximum_speed, maximum_turn_speed])
	else:
		push_error("STARTUP_ARENA_CHASE_MOTION_VALIDATION: FAIL state=%s samples=%d speed=%.2f turn=%.2f" % [
			preview.get("_state"), samples, maximum_speed, maximum_turn_speed])
	preview.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if passed else 1)

