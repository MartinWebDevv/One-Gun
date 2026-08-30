extends Node

## Five-word variation of the approved smooth-shot startup preview.
##
## The approved scene is composed as an unmodified child so its stage, cats,
## camera route, Blue hand socket, gun grip, recoil, and logo handoff remain
## identical. This wrapper owns the elimination caption timing and can either
## retain its standalone comparison end card or fade into an exported scene.

const SMOOTH_SHOT_SCENE = preload(
	"res://cinematics/startup/startup_intro_preview_smooth_shot.tscn")

const WARM_WHITE := Color(0.96, 0.95, 0.91)
const GOLD := Color(1.0, 0.68, 0.16)
const ACTOR_REVEAL_ORDER: Array[String] = [
	"blue", "orange", "pink", "green", "yellow", "purple",
]
const ELIMINATION_ORDER: Array[String] = [
	"green", "pink", "purple", "orange", "yellow",
]
const ELIMINATION_DELAYS: Array[float] = [0.30, 0.24, 0.17, 0.17, 0.30]
const DEATH_WORDS: Array[String] = ["BE", "THE", "LAST", "ONE", "STANDING"]
const HANDOFF_FADE_DURATION := 0.04
const HANDOFF_SCENE_CHANGE_DELAY := 0.05
const SOURCE_RICH_TEXT_FONT_SLOTS: Array[String] = [
	"normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font",
]

enum PreviewState {
	LOADING,
	CINEMATIC,
	TITLE,
	END_CARD,
}

@export var show_preview_controls := true
@export var autoplay := true
@export var caption_font: Font = null
@export_range(48, 112, 1) var caption_font_size := 82
@export_range(0, 40, 1) var caption_word_spacing := 18
@export var apply_caption_font_to_all_labels := false
@export_file("*.tscn") var handoff_scene_path := ""
@export var allow_replay_input := true
@export var escape_quits_preview := true

var _state := PreviewState.LOADING
var _sequence_generation := 0
var _source: Node = null
var _death_phrase: HBoxContainer = null
var _death_word_labels: Array[Label] = []
var _word_tweens: Array[Tween] = []
var _revealed_word_count := 0
var _handoff_preload_path := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_source = SMOOTH_SHOT_SCENE.instantiate()
	_source.set("show_preview_controls", show_preview_controls)
	_source.set("autoplay", false)
	_source.set_process_input(false)
	add_child(_source)
	# The approved child has its own standalone preview input handler. Disable it
	# again after entering the tree so it can never consume the title click before
	# this production wrapper routes that click to the configured handoff scene.
	_source.set_process_input(false)
	_source.set_process_unhandled_input(false)
	_source.set_process_unhandled_key_input(false)
	_apply_caption_font_to_source_labels()
	_build_death_phrase()
	if not await _wait_for_source_preparation():
		push_error("Five-word startup preview could not prepare the approved smooth-shot scene.")
		return
	_begin_handoff_preload()
	if autoplay:
		_start_preview()


func _input(event: InputEvent) -> void:
	if not _is_deliberate_press(event):
		return
	get_viewport().set_input_as_handled()
	if allow_replay_input and event is InputEventKey \
			and (event as InputEventKey).keycode == KEY_R:
		_start_preview()
		return
	if escape_quits_preview and event.is_action("ui_cancel"):
		get_tree().quit()
		return
	# The smooth-shot child owns the visible title transition. Treat its TITLE
	# state as authoritative too, so the first click after the logo never gets
	# mistaken for a late cinematic-skip input while this wrapper awaits it.
	if _state == PreviewState.TITLE or _source_is_at_title():
		_state = PreviewState.TITLE
		_show_unlinked_handoff()
	elif _state == PreviewState.CINEMATIC:
		_show_title_immediately()


func _is_deliberate_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return key_event.pressed and not key_event.echo
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	return false


func _source_is_at_title() -> bool:
	return _source != null and int(_source.get("_state")) == PreviewState.TITLE


func _begin_handoff_preload() -> void:
	if handoff_scene_path == "" or not ResourceLoader.exists(handoff_scene_path):
		return
	_handoff_preload_path = handoff_scene_path
	if ResourceLoader.has_cached(_handoff_preload_path):
		return
	var error := ResourceLoader.load_threaded_request(_handoff_preload_path)
	if error != OK:
		_handoff_preload_path = ""


func _wait_for_source_preparation() -> bool:
	# The source deliberately prepares only the shared idle clips plus Blue's
	# firing pose. Give that asynchronous one-time work ample room on a slower PC.
	for _frame_index in 300:
		var actors := _source.get("_actors") as Dictionary
		if actors.size() == ACTOR_REVEAL_ORDER.size():
			return true
		await get_tree().process_frame
	return false


func _apply_caption_font_to_source_labels() -> void:
	if not apply_caption_font_to_all_labels or caption_font == null:
		return
	var pending: Array[Node] = [_source]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Label:
			(node as Label).add_theme_font_override("font", caption_font)
		elif node is RichTextLabel:
			var rich_text := node as RichTextLabel
			for font_slot in SOURCE_RICH_TEXT_FONT_SLOTS:
				rich_text.add_theme_font_override(font_slot, caption_font)
		for child in node.get_children():
			pending.append(child)


func _build_death_phrase() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "FiveWordCaptionLayer"
	# The approved scene's flashes, fades, logo, and prompts remain on layer 10.
	# Layer 9 puts this text over the 3D stage but beneath those transitions.
	canvas.layer = 9
	add_child(canvas)

	_death_phrase = HBoxContainer.new()
	_death_phrase.name = "BeTheLastOneStanding"
	_death_phrase.alignment = BoxContainer.ALIGNMENT_CENTER
	_death_phrase.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_phrase.anchor_left = 0.08
	_death_phrase.anchor_top = 0.0
	_death_phrase.anchor_right = 0.92
	_death_phrase.anchor_bottom = 0.18
	_death_phrase.add_theme_constant_override("separation", caption_word_spacing)
	canvas.add_child(_death_phrase)

	for word in DEATH_WORDS:
		var label := Label.new()
		label.name = "%sWord" % word.capitalize()
		label.text = word
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", caption_font_size)
		if caption_font != null:
			label.add_theme_font_override("font", caption_font)
		label.add_theme_color_override("font_color",
			GOLD if word == "LAST" or word == "ONE" else WARM_WHITE)
		label.add_theme_color_override(
			"font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
		label.add_theme_constant_override("outline_size", 12)
		label.modulate.a = 0.0
		_death_phrase.add_child(label)
		_death_word_labels.append(label)


func _start_preview() -> void:
	if _source == null or _death_word_labels.size() != DEATH_WORDS.size():
		return
	_sequence_generation += 1
	_stop_word_tweens()
	_source.set("_sequence_generation", _sequence_generation)
	_source.call("_stop_active_tweens")
	_source.call("_cleanup_combat_pops")
	_source.set("_state", PreviewState.CINEMATIC)
	_source.call("_reset_presentation")
	var source_phrase := _source.get("_phrase") as RichTextLabel
	if source_phrase != null:
		source_phrase.visible = true
	_reset_death_phrase()
	_state = PreviewState.CINEMATIC
	_run_sequence(_sequence_generation)


func _reset_death_phrase() -> void:
	_revealed_word_count = 0
	_death_phrase.visible = true
	_death_phrase.modulate = Color.WHITE
	for label in _death_word_labels:
		label.modulate = Color(1.0, 1.0, 1.0, 0.0)
		label.scale = Vector2.ONE


func _run_sequence(generation: int) -> void:
	if not await _wait_for(0.35, generation):
		return
	var stage := _source.get("_stage") as Node3D
	var gun_pivot := _source.get("_gun_pivot") as Node3D
	var logo := _source.get("_logo") as TextureRect
	var camera := _source.get("_camera") as Camera3D
	if stage == null or gun_pivot == null or logo == null or camera == null:
		return

	stage.visible = true
	gun_pivot.visible = true
	_source.call("_show_phrase", "ONE [color=#ffad29]GUN[/color]")
	_source_tween(logo, "modulate:a", 0.0, 0.30)
	_source_tween(camera, "transform", _camera_transform(
		Vector3(0.0, 1.92, 5.75), Vector3(0.0, 1.25, 0.0)),
		_motion_time(0.95))
	_source_tween(gun_pivot, "rotation:y", PI * 0.72, _motion_time(1.10))

	if not await _wait_for(1.18, generation):
		return
	_source.call("_show_phrase", "ONE [color=#ffad29]SHOT[/color]")
	_source_tween(camera, "transform", _camera_transform(
		Vector3(2.85, 1.70, 4.35), Vector3(0.0, 1.30, 0.0)),
		_motion_time(0.34))
	_source_tween(gun_pivot, "rotation:y", PI * 1.10, _motion_time(0.42))

	if not await _wait_for(0.64, generation):
		return
	AudioManager.play_sfx("gun_shot", 1.0, 0.86)
	_source.call("_fire_gunshot_flash")

	if not await _wait_for(0.16, generation):
		return
	_source.call("_show_phrase", "EVERYONE [color=#ffad29]WANTS IT[/color]")
	_source_tween(camera, "transform", _camera_transform(
		Vector3(0.0, 4.20, 10.45), Vector3(0.0, 1.05, 0.15)),
		_motion_time(0.32))
	for actor_id in ACTOR_REVEAL_ORDER:
		_source.call("_reveal_actor", actor_id)
		if not await _wait_for(0.10, generation):
			return

	# The approved version displayed "LAST ONE" here. In this variation the
	# frame clears, then each confetti elimination contributes exactly one word.
	if not await _wait_for(0.82, generation):
		return
	var source_phrase := _source.get("_phrase") as RichTextLabel
	if source_phrase != null:
		_source_tween(source_phrase, "modulate:a", 0.0, 0.16)

	if not await _wait_for(0.34, generation):
		return
	for index in ELIMINATION_ORDER.size():
		_source.call("_eliminate_actor", ELIMINATION_ORDER[index])
		_reveal_death_word(index)
		if not await _wait_for(ELIMINATION_DELAYS[index], generation):
			return

	# Hide the source caption before its approved final-shot method attempts to
	# display its original last-standing card. The new full sentence remains in
	# the same screen band while Blue takes the exact same gun and fires it.
	if source_phrase != null:
		source_phrase.visible = false
	_fade_death_phrase(generation)
	await _source.call("_blue_takes_and_fires_smoothly", generation)
	if generation == _sequence_generation:
		_state = PreviewState.TITLE


func _reveal_death_word(index: int) -> void:
	if index < 0 or index >= _death_word_labels.size():
		return
	var label := _death_word_labels[index]
	_revealed_word_count = index + 1
	label.pivot_offset = label.size * 0.5
	if bool(_source.get("_reduced_motion")):
		label.modulate.a = 1.0
		label.scale = Vector2.ONE
		return
	label.modulate.a = 0.0
	label.scale = Vector2(0.68, 0.68)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_word_tweens.append(tween)


func _fade_death_phrase(generation: int) -> void:
	if not await _wait_for(0.34, generation):
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_death_phrase, "modulate:a", 0.0, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_word_tweens.append(tween)


func _show_title_immediately() -> void:
	_sequence_generation += 1
	_stop_word_tweens()
	_death_phrase.modulate.a = 0.0
	_source.set("_sequence_generation", _sequence_generation)
	_source.call("_show_title_immediately")
	var source_phrase := _source.get("_phrase") as RichTextLabel
	if source_phrase != null:
		source_phrase.visible = true
	_state = PreviewState.TITLE


func _show_unlinked_handoff() -> void:
	if _state != PreviewState.TITLE:
		return
	if handoff_scene_path != "":
		_start_scene_handoff()
		return
	_sequence_generation += 1
	_source.set("_sequence_generation", _sequence_generation)
	_source.call("_show_unlinked_handoff")
	_state = PreviewState.END_CARD


func _start_scene_handoff() -> void:
	_sequence_generation += 1
	_stop_word_tweens()
	_source.set("_sequence_generation", _sequence_generation)
	_source.call("_stop_active_tweens")
	_state = PreviewState.END_CARD
	_run_scene_handoff(_sequence_generation)


func _run_scene_handoff(generation: int) -> void:
	var screen_fade := _source.get("_screen_fade") as ColorRect
	if screen_fade != null:
		_source.call("_tween_property", screen_fade, NodePath("color:a"), 1.0,
			HANDOFF_FADE_DURATION, Tween.TRANS_QUAD, Tween.EASE_IN_OUT)
		if not await _wait_for(HANDOFF_SCENE_CHANGE_DELAY, generation):
			return
	var packed_scene := _prepared_handoff_scene()
	var error := get_tree().change_scene_to_packed(packed_scene) \
		if packed_scene != null else get_tree().change_scene_to_file(handoff_scene_path)
	if error == OK:
		return
	push_error("Startup intro could not open handoff scene '%s' (error %d)." % [
		handoff_scene_path, error])
	if screen_fade != null:
		screen_fade.color.a = 0.0
	_state = PreviewState.TITLE
	_source.call("_start_prompt_pulse")


func _prepared_handoff_scene() -> PackedScene:
	if _handoff_preload_path == handoff_scene_path:
		if ResourceLoader.has_cached(_handoff_preload_path):
			return load(_handoff_preload_path) as PackedScene
		var status := ResourceLoader.load_threaded_get_status(_handoff_preload_path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS \
				or status == ResourceLoader.THREAD_LOAD_LOADED:
			return ResourceLoader.load_threaded_get(_handoff_preload_path) as PackedScene
	return load(handoff_scene_path) as PackedScene


func _wait_for(seconds: float, generation: int) -> bool:
	await get_tree().create_timer(seconds, true, false, true).timeout
	return generation == _sequence_generation


func _motion_time(normal_time: float) -> float:
	return float(_source.call("_motion_time", normal_time))


func _camera_transform(position: Vector3, target: Vector3) -> Transform3D:
	var result: Transform3D = _source.call("_camera_transform", position, target)
	return result


func _source_tween(object: Object, property: String, final_value: Variant,
		duration: float, transition := Tween.TRANS_QUAD,
		ease := Tween.EASE_IN_OUT) -> void:
	_source.call("_tween_property", object, NodePath(property), final_value,
		duration, transition, ease)


func _stop_word_tweens() -> void:
	for tween in _word_tweens:
		if tween != null:
			tween.kill()
	_word_tweens.clear()
