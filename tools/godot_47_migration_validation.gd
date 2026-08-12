extends Node

# Focused regression coverage for the 4.7.1 migration fixes. Run this scene
# once normally (solo) and once with ONEGUN_MIGRATION_SPLIT=1 (splitscreen).

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_split: bool = bool(GameConfig.split_screen_enabled)
	var original_bots: Array = GameConfig.bot_configs.duplicate(true)
	var split_enabled := OS.get_environment("ONEGUN_MIGRATION_SPLIT") == "1"
	GameConfig.split_screen_enabled = split_enabled
	GameConfig.bot_configs = []

	var arena := (load("res://maps/test/CityMap.tscn") as PackedScene).instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame

	var layer = arena.get_node_or_null("SplitScreenLayer")
	_check(layer != null, "CityMap has no SplitScreenLayer")
	if layer != null:
		var container_2 := layer.get_node("ViewportRow/SubViewportContainer2") as SubViewportContainer
		var viewport_2 := layer.get_node("ViewportRow/SubViewportContainer2/SubViewport2") as SubViewport
		var player_1 = arena.get_node_or_null("player1")
		var player_2 = arena.get_node_or_null("player2")
		_check(player_1 != null and player_1.get_camera() != null,
			"player 1 did not provide a camera")
		if split_enabled:
			_check(container_2.visible, "splitscreen hid player 2's viewport")
			_check(viewport_2.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
				"splitscreen disabled player 2's viewport renderer")
			_check(layer.player2 == player_2, "splitscreen did not retain player 2")
			_check(player_2 != null and player_2.get_camera() != null,
				"player 2 did not provide a camera")
		else:
			_check(not container_2.visible, "solo play left player 2's viewport visible")
			_check(viewport_2.render_target_update_mode == SubViewport.UPDATE_DISABLED,
				"solo play still renders the hidden second 3D viewport")
			_check(layer.player2 == null, "solo play retained the unused player 2 reference")

		# Scene transitions can invalidate a source camera for one frame. The
		# synchronizer must safely ignore that transient state.
		var camera_less_player := Node.new()
		layer.player1 = camera_less_player
		layer._process(0.0)
		layer.player1 = player_1
		camera_less_player.free()

	arena.queue_free()
	await get_tree().process_frame

	# Changing bot count emits from the stepper that the callback replaces. This
	# reproduces the signal-time free that Godot 4.7 flags as crash-prone.
	var slideout := OneGunLobbySettingsSlideout.new()
	slideout.panel_kind = OneGunLobbySettingsSlideout.Kind.BOT
	add_child(slideout)
	await get_tree().process_frame
	await get_tree().process_frame
	var steppers := slideout.find_children("*", "OneGunStepper", true, false)
	_check(not steppers.is_empty(), "bot settings did not create a stepper")
	if not steppers.is_empty():
		var stepper := steppers[0] as OneGunStepper
		var next_value := mini(stepper.value + 1, stepper.max_value)
		stepper.value = next_value
		await get_tree().process_frame
		_check((slideout._pending.get("bot_configs", []) as Array).size() == next_value,
			"bot stepper signal did not rebuild the pending roster safely")
	slideout.queue_free()

	GameConfig.split_screen_enabled = original_split
	GameConfig.bot_configs = original_bots
	await get_tree().process_frame
	if _failures.is_empty():
		print("GODOT 4.7 MIGRATION VALIDATION (%s): PASS" % (
			"SPLITSCREEN" if split_enabled else "SOLO"))
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("GODOT 4.7 MIGRATION VALIDATION: " + failure)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
