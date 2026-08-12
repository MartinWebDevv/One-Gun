extends Node

const CUSTOMIZATION_SCRIPT = preload("res://UI/character_customization_overlay.gd")

var _failed := false
var _overlay = null
var _output_dir := ""
var _prefix := "customization"


func _ready() -> void:
	_output_dir = OS.get_environment("ONEGUN_CUSTOMIZATION_CAPTURE_DIR")
	_prefix = OS.get_environment("ONEGUN_CUSTOMIZATION_CAPTURE_PREFIX")
	if _prefix.is_empty():
		_prefix = "customization"
	_run.call_deferred()


func _run() -> void:
	var requested_window := OS.get_environment("ONEGUN_CUSTOMIZATION_WINDOW")
	if requested_window.contains("x"):
		var parts := requested_window.split("x")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(parts[0].to_int(), parts[1].to_int()))
			await _wait_frames(3)
	var original_p1 := str(PlayerPrefs.get_setting("character_skin_id"))
	var original_p2 := str(GameConfig.player2_skin_id)
	_overlay = CUSTOMIZATION_SCRIPT.new()
	_overlay.configure(false, 2)
	add_child(_overlay)
	await _wait_frames(18)

	_check(_overlay.find_children("*", "SubViewport", true, false).size() == 1,
		"customization should use one shared preview viewport")
	_check(_overlay.find_children("ColorCard_*", "", true, false).size() == 13,
		"customization should show all 13 color cards")
	for row_index in 3:
		var row = _overlay.find_child("ColorRow%d" % (row_index + 1), true, false)
		var expected := 5 if row_index < 2 else 3
		_check(row != null and row.get_child_count() == expected,
			"color row %d should contain %d cards" % [row_index + 1, expected])
	_check(_overlay.find_child("LockedSkins", true, false).get_child_count() == 5,
		"locked Skins preview should stay visible")
	_check(_overlay.find_child("Player1Tab", true, false) != null
		and _overlay.find_child("Player2Tab", true, false) != null,
		"split-screen customization should show P1/P2 tabs")
	_check(_overlay.find_child("Randomize", true, false) != null
		and _overlay.find_child("Default", true, false) != null
		and _overlay.find_child("Confirm", true, false) != null,
		"action bar should contain Randomize, Default, and Confirm")

	for skin in PlayerSkinRegistry.SKINS:
		_check(PlayerSkinRegistry.load_portrait(str(skin["id"])) != null,
			"portrait missing for %s" % str(skin["id"]))

	var preview = _overlay.find_child("PreviewCharacter", true, false)
	var animation_player := preview.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer if preview != null else null
	_check(preview != null and animation_player != null
		and animation_player.current_animation == "idle",
		"shared preview should show an evaluated Idle pose")

	_overlay.call("_select_skin", "salmon")
	_check(str(PlayerPrefs.get_setting("character_skin_id")) == original_p1,
		"P1 preview selection leaked before Confirm")
	_overlay.call("_default_active_skin")
	_check(str(_overlay._pending_skin_ids.get(0, "")) == "blue",
		"Default should set the pending P1 color to Blue")
	_check(str(PlayerPrefs.get_setting("character_skin_id")) == original_p1,
		"Default changed the stored P1 color before Confirm")

	await _capture("%s_p1.png" % _prefix)
	_overlay.call("_set_active_slot", 1)
	_overlay.call("_select_skin", "salmon")
	await _wait_frames(4)
	_check(str(GameConfig.player2_skin_id) == original_p2,
		"P2 preview selection leaked before Confirm")
	await _capture("%s_p2.png" % _prefix)

	var canvas := _overlay.find_child("CustomizationCanvas", true, false) as Control
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	_check(canvas != null and _rect_fits(canvas.get_global_rect(), viewport_rect),
		"responsive customization canvas extends out of frame")
	for control_name in ["CharacterPreviewPanel", "CharacterCustomizationCabinet",
			"Back", "Randomize", "Default", "Confirm"]:
		var control := _overlay.find_child(control_name, true, false) as Control
		_check(control != null and _rect_fits(control.get_global_rect(), viewport_rect),
			"%s extends out of frame" % control_name)

	var roster_row := OneGunRosterRow.new()
	add_child(roster_row)
	roster_row.visible = false
	roster_row.set_human("Remote Player", false, false,
		OneGunRosterRow.ReadyState.READY, "purple")
	await get_tree().process_frame
	var roster_portraits := roster_row.find_children(
		"PlayerPortrait", "", true, false)
	var roster_portrait = roster_portraits[0] \
		if not roster_portraits.is_empty() else null
	_check(roster_portrait != null and roster_portrait.visible
		and roster_portrait.skin_id == "purple" and roster_portrait.texture != null,
		"human lobby row did not resolve the synchronized skin portrait")
	roster_row.queue_free()

	_overlay.call("_cancel")
	await get_tree().process_frame
	_check(str(PlayerPrefs.get_setting("character_skin_id")) == original_p1
		and str(GameConfig.player2_skin_id) == original_p2,
		"Cancel failed to preserve both confirmed colors")

	var confirm_overlay = CUSTOMIZATION_SCRIPT.new()
	confirm_overlay.configure(false, 2)
	add_child(confirm_overlay)
	await _wait_frames(3)
	confirm_overlay.call("_set_active_slot", 1)
	confirm_overlay.call("_select_skin", "cyan")
	confirm_overlay.call("_confirm")
	await get_tree().process_frame
	_check(str(GameConfig.player2_skin_id) == "cyan",
		"Confirm did not commit the pending P2 color")
	GameConfig.player2_skin_id = original_p2
	if _failed:
		get_tree().quit(1)
	else:
		print("CHARACTER_CUSTOMIZATION_VALIDATION_OK colors=13 rows=5/5/3 portraits=online-ready")
		get_tree().quit(0)


func _capture(file_name: String) -> void:
	if _output_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_output_dir)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _output_dir.path_join(file_name)
	var error := image.save_png(path)
	_check(error == OK, "could not save capture %s" % path)
	if error == OK:
		print("CHARACTER_CUSTOMIZATION_CAPTURE ", path)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("CharacterCustomizationValidation: %s" % message)


func _rect_fits(inner: Rect2, outer: Rect2) -> bool:
	const TOLERANCE := 1.0
	return inner.position.x >= outer.position.x - TOLERANCE \
		and inner.position.y >= outer.position.y - TOLERANCE \
		and inner.end.x <= outer.end.x + TOLERANCE \
		and inner.end.y <= outer.end.y + TOLERANCE


func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame
