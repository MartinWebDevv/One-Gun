extends SceneTree

# Focused render fixture for the production Arena Matchboard TAB overlay.

const MatchboardScript = preload("res://UI/arena_matchboard.gd")
const CAPTURE_ENV := "ONEGUN_MATCHBOARD_CAPTURE"
const VIEWPORT_SIZE := Vector2i(1600, 900)

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)


func _run() -> void:
	root.size = VIEWPORT_SIZE
	_check(load("res://match_hud.gd") != null,
		"MatchHUD parses with Arena Matchboard integration")
	_check(load("res://round_manager.gd") != null,
		"RoundManager parses with live matchboard metadata")
	_build_backdrop()

	var layer := CanvasLayer.new()
	layer.layer = 20
	root.add_child(layer)
	var matchboard = MatchboardScript.new()
	layer.add_child(matchboard)
	await process_frame

	var standings := _sample_standings()
	var context := {
		"official": true,
		"match_kind": "OFFICIAL BETA",
		"mode_name": "CLASSIC ONE GUN",
		"map_name": "NEON CIRCUIT",
		"round_number": 3,
		"rounds_to_win": 3,
		"timer": "01:42",
	}

	matchboard.present(standings, 2, context)
	await create_timer(0.1).timeout
	_check(matchboard.find_children(
		"MatchboardRow_*", "", true, false).size() == 6,
		"a top-five viewer sees the true top six")
	_check(matchboard.find_child("MatchboardRow_6", true, false) != null,
		"sixth place fills the final row when the viewer is top five")
	_check(matchboard.find_child("MatchboardRow_9", true, false) == null,
		"lower placements stay hidden for a top-five viewer")

	matchboard.present(standings, 9, context)
	await create_timer(0.3).timeout
	var viewer_row := matchboard.find_child("MatchboardRow_9", true, false)
	var leader_row := matchboard.find_child("MatchboardRow_1", true, false)
	_check(matchboard.find_children(
		"MatchboardRow_*", "", true, false).size() == 6,
		"the board remains capped at six competitor rows")
	_check(matchboard.find_child("MatchboardRow_6", true, false) == null,
		"an outside-top-five viewer replaces the ordinary sixth row")
	_check(viewer_row != null
			and bool(viewer_row.get_meta("viewer_row", false))
			and int(viewer_row.get_meta("placement", -1)) == 9
			and bool(viewer_row.get_meta("rank_jump", false)),
		"ninth place renders with its true rank and YOU highlight")
	_check(matchboard.find_child("ViewerPositionDivider", true, false) != null,
		"a rank jump receives the viewer-position divider")
	_check(leader_row != null and bool(leader_row.get_meta("has_one_gun", false)),
		"the current One Gun holder is marked")
	_check(matchboard.find_child("MatchStatusBadge", true, false) != null,
		"official/custom match status badge renders")

	await RenderingServer.frame_post_draw
	var capture_path := OS.get_environment(CAPTURE_ENV)
	if capture_path.is_empty():
		capture_path = ProjectSettings.globalize_path(
			"res://build/qa/arena_matchboard.png")
	DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
	var image := root.get_texture().get_image()
	var error := image.save_png(capture_path)
	_check(error == OK, "1600x900 matchboard capture saves")
	var preview := image.duplicate()
	preview.resize(800, 450, Image.INTERPOLATE_LANCZOS)
	var preview_path := capture_path.get_basename() + "_preview.jpg"
	_check(preview.save_jpg(preview_path, 0.84) == OK, "inspection preview saves")
	print("MATCHBOARD_RENDER_CAPTURE ", capture_path)
	quit(0 if _failures == 0 else 1)


func _sample_standings() -> Array:
	return [
		_entry(1, "Maverick", 2, 7, 3, true, true, true),
		_entry(2, "Sundown", 2, 5, 4, true),
		_entry(3, "Ricochet", 1, 4, 2, true),
		_entry(4, "Dusty", 1, 3, 1, false),
		_entry(5, "Rattlesnake", 0, 2, 2, true),
		_entry(6, "Calico", 0, 1, 0, false),
		_entry(7, "Longshot", 0, 1, 0, true),
		_entry(8, "Trigger", 0, 0, 1, false),
		_entry(9, "Deadeye", 0, 0, 0, true),
		_entry(10, "Bandit", 0, 0, 0, false),
	]


func _entry(actor_id: int, player_name: String, rounds: int, kills: int,
		disarms: int, alive: bool, is_host := false,
		has_gun := false) -> Dictionary:
	return {
		"actor_id": actor_id,
		"name": player_name,
		"team_id": -1,
		"sets": 0,
		"rounds": rounds,
		"kills": kills,
		"deaths": 0,
		"disarms": disarms,
		"pickups": 0,
		"melee": 0,
		"alive": alive,
		"is_host": is_host,
		"is_bot": false,
		"has_gun": has_gun,
	}


func _build_backdrop() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	root.add_child(layer)

	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.008, 0.012, 0.030, 1.0)
	layer.add_child(background)

	var arena := TextureRect.new()
	arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena.texture = load("res://UI/map_thumbnails/neon_circuit.png")
	arena.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arena.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	arena.modulate = Color(0.55, 0.62, 0.78, 0.58)
	background.add_child(arena)

	var sky_tint := ColorRect.new()
	sky_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky_tint.color = Color(0.004, 0.012, 0.038, 0.40)
	background.add_child(sky_tint)

	var top_hud := PanelContainer.new()
	top_hud.position = Vector2(32.0, 28.0)
	top_hud.size = Vector2(430.0, 70.0)
	top_hud.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(OneGunUI.color("canvas"), 0.82),
		Color(OneGunUI.color("cyan"), 0.30), 10, 1, 0, 12.0))
	background.add_child(top_hud)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", -2)
	top_hud.add_child(copy)
	copy.add_child(OneGunUI.make_heading("NEON CIRCUIT", 24, "cyan"))
	copy.add_child(OneGunUI.make_label(
		"CLASSIC ONE GUN  //  ROUND 3", 11, "muted", true))

	var objective := OneGunUI.make_label(
		"ONE GUN IN PLAY", 12, "gold", true)
	objective.anchor_left = 1.0
	objective.anchor_right = 1.0
	objective.offset_left = -220.0
	objective.offset_right = -32.0
	objective.offset_top = 40.0
	objective.offset_bottom = 64.0
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	background.add_child(objective)
