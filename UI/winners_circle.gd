class_name OneGunWinnersCircle
extends CanvasLayer

# Full-screen, presentation-only match results. Gameplay actors remain in the
# hidden match world; the podium uses lightweight visual copies with no
# physics, AI, inventory, or replication.

const SkinRegistry = preload("res://player_skin_registry.gd")
const CosmeticRegistry = preload("res://supabase/supabase_cosmetic_registry.gd")
const RewardPreview = preload("res://match_reward_preview.gd")
const StageBlockoutScene = preload("res://UI/winners_circle_stage_blockout.tscn")

const MINIMUM_VIEW_TIME := 10.0
const AUTO_RETURN_TIME := 25.0
const GUN_MODEL_PATH := "res://models/weaponModels/water_gun.glb"
const TROPHY_MODEL_PATH := "res://models/rewards/winners_circle_trophy.glb"

signal ready_changed(ready: bool)
signal force_return_requested
signal local_return_requested

var _result: Dictionary = {}
var _entries: Array = []
var _viewer_actor_ids: Array[int] = []
var _online := false
var _host_view := false
var _started_msec := 0
var _return_deadline_msec := -1
var _return_signal_sent := false
var _root: Control
var _stage_viewport: SubViewport
var _ready_button: OneGunButton
var _host_return_button: OneGunButton
var _ready_count_label: Label
var _auto_return_label: Label
var _standing_ready_labels: Dictionary = {}
var _local_ready_buttons: Dictionary = {}
var _local_ready_actor_ids: Dictionary = {}
var _performers: Array[Dictionary] = []
var _stage_blockout: Node3D
var _trophy_root: Node3D
var _confetti: GPUParticles3D
var _full_stats_overlay: Control


func _ready() -> void:
	layer = 300
	process_mode = Node.PROCESS_MODE_ALWAYS


func present(result: Dictionary, viewer_actor_ids: Array,
		online: bool, host_view: bool) -> void:
	if _root != null:
		return
	_result = result.duplicate(true)
	_entries = _result.get("entries", []).duplicate(true)
	for value in viewer_actor_ids:
		var actor_id := int(value)
		if actor_id >= 0 and actor_id not in _viewer_actor_ids:
			_viewer_actor_ids.append(actor_id)
	_online = online
	_host_view = host_view
	_started_msec = Time.get_ticks_msec()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_interface()
	_run_presentation_sequence()


func set_ready_peers(ready_peer_ids: Array,
		required_peer_ids: Array = []) -> void:
	var ready_lookup := {}
	for value in ready_peer_ids:
		ready_lookup[int(value)] = true
	var required_lookup := {}
	for value in required_peer_ids:
		required_lookup[int(value)] = true
	var restrict_to_required := not required_peer_ids.is_empty()
	var ready_count := 0
	var participant_count := 0
	for entry_value in _entries:
		var entry: Dictionary = entry_value
		var peer_id := int(entry.get("peer_id", -1))
		if peer_id <= 0 or bool(entry.get("is_bot", false)):
			continue
		var connected := not restrict_to_required or required_lookup.has(peer_id)
		if connected:
			participant_count += 1
		var is_ready := ready_lookup.has(peer_id)
		if connected and is_ready:
			ready_count += 1
		var status_label := _standing_ready_labels.get(peer_id) as Label
		if status_label != null:
			status_label.text = "LEFT" if not connected else (
				"READY" if is_ready else "—")
			status_label.add_theme_color_override(
				"font_color", OneGunUI.color("green") if connected and is_ready \
				else OneGunUI.color("muted"))
	if _ready_count_label != null:
		_ready_count_label.text = "%d / %d PLAYERS READY" % [ready_count, participant_count]
	if _ready_button != null:
		var local_peer_id := int(_result.get("local_peer_id", -1))
		var local_ready := ready_lookup.has(local_peer_id)
		_ready_button.set_pressed_no_signal(local_ready)
		_ready_button.text = "READY  ✓" if local_ready else "READY"
		_ready_button.variant = "green" if local_ready else "gold"


func start_return_countdown(seconds: float) -> void:
	if _return_deadline_msec >= 0:
		return
	_return_deadline_msec = Time.get_ticks_msec() + int(maxf(seconds, 0.25) * 1000.0)
	if _ready_button != null:
		_ready_button.disabled = true
	if _host_return_button != null:
		_host_return_button.disabled = true
	for button_value in _local_ready_buttons.values():
		var button := button_value as Button
		if button != null:
			button.disabled = true


func _process(_delta: float) -> void:
	if _root == null:
		return
	var now := Time.get_ticks_msec()
	var elapsed := float(now - _started_msec) / 1000.0
	var controls_unlocked := elapsed >= MINIMUM_VIEW_TIME and _return_deadline_msec < 0
	if _ready_button != null:
		_ready_button.disabled = not controls_unlocked
	if _host_return_button != null:
		_host_return_button.disabled = not controls_unlocked
	for button_value in _local_ready_buttons.values():
		var button := button_value as Button
		if button != null:
			button.disabled = not controls_unlocked
	if _return_deadline_msec >= 0:
		var remaining := maxf(float(_return_deadline_msec - now) / 1000.0, 0.0)
		if _auto_return_label != null:
			_auto_return_label.text = "RETURNING TO LOBBY IN %d" % maxi(ceili(remaining), 0)
		if not _online and remaining <= 0.0 and not _return_signal_sent:
			_return_signal_sent = true
			local_return_requested.emit()
		return
	var auto_remaining := maxf(AUTO_RETURN_TIME - elapsed, 0.0)
	if _auto_return_label != null:
		_auto_return_label.text = "AUTO RETURN IN %d" % maxi(ceili(auto_remaining), 0)
	if not _online and auto_remaining <= 0.0 and not _return_signal_sent:
		_return_signal_sent = true
		local_return_requested.emit()


func _build_interface() -> void:
	_root = Control.new()
	_root.name = "WinnersCircleRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.008, 0.014, 0.044, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(side, 16)
	_root.add_child(outer)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	outer.add_child(column)
	_build_header(column)

	var main_row := HBoxContainer.new()
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 12)
	column.add_child(main_row)
	_build_stage_panel(main_row)
	_build_standings_panel(main_row)
	_build_personal_results(column)
	_build_controls(column)
	_build_full_stats_overlay()

	_root.modulate.a = 0.0
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_root, "modulate:a", 1.0,
		0.12 if _reduced_motion() else 0.35)


func _build_header(parent: VBoxContainer) -> void:
	var header := VBoxContainer.new()
	header.custom_minimum_size.y = 70.0
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(header)
	var title := OneGunUI.make_heading("WINNERS CIRCLE", 44, "gold")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var mode_name := str(_result.get("mode_name", "CLASSIC ONE GUN"))
	var status := "OFFICIAL BETA" if bool(_result.get("official", false)) else "CUSTOM MATCH"
	var subtitle := OneGunUI.make_label("%s  •  %s" % [status, mode_name], 17,
		"green" if bool(_result.get("official", false)) else "muted", true)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(subtitle)


func _build_stage_panel(parent: HBoxContainer) -> void:
	var cabinet := OneGunCabinet.new()
	cabinet.name = "PodiumStageCabinet"
	cabinet.variant = OneGunCabinet.Variant.CABINET
	cabinet.content_padding = 6
	cabinet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cabinet.size_flags_stretch_ratio = 1.75
	cabinet.custom_minimum_size = Vector2(690.0, 390.0)
	parent.add_child(cabinet)
	var container := SubViewportContainer.new()
	container.name = "PodiumStage"
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cabinet.get_content().add_child(container)
	_build_stage_world(container)


func _build_standings_panel(parent: HBoxContainer) -> void:
	var cabinet := OneGunCabinet.new()
	cabinet.name = "FinalStandingsCabinet"
	cabinet.variant = OneGunCabinet.Variant.CABINET
	cabinet.content_padding = 16
	cabinet.custom_minimum_size.x = 460.0
	cabinet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cabinet.size_flags_stretch_ratio = 0.85
	parent.add_child(cabinet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	cabinet.get_content().add_child(column)
	var heading := OneGunUI.make_heading("━━  FINAL STANDINGS  ━━", 28, "gold")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	column.add_child(_make_standings_header(false))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	for entry_value in _entries:
		var entry: Dictionary = entry_value
		rows.add_child(_make_standings_row(entry, false))
	var full_stats := OneGunButton.new()
	full_stats.name = "FullStatsButton"
	full_stats.text = "FULL STATS"
	full_stats.variant = "navy"
	full_stats.custom_minimum_size.y = 50.0
	full_stats.pressed.connect(_show_full_stats)
	column.add_child(full_stats)


func _make_standings_header(full: bool) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 38.0
	var fields := [
		["PLACE", 58.0], ["PLAYER", 175.0], ["RW", 42.0],
		["K", 34.0], ["DIS", 42.0], ["READY", 62.0],
	]
	if full:
		fields = [
			["PLACE", 58.0], ["PLAYER", 220.0], ["RW", 48.0],
			["2ND", 48.0], ["3RD", 48.0], ["K", 48.0], ["D", 48.0],
			["DIS", 58.0], ["PICK", 58.0], ["MELEE", 70.0],
		]
	for field in fields:
		var label := OneGunUI.make_label(str(field[0]), 14, "muted", true)
		label.custom_minimum_size.x = float(field[1])
		if str(field[0]) == "PLAYER":
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(label)
	return row


func _make_standings_row(entry: Dictionary, full: bool) -> Control:
	var panel := PanelContainer.new()
	var placement := int(entry.get("placement", 0))
	var border_role := "gold" if placement == 1 else "border"
	var background := OneGunUI.color("face_raised")
	if placement == 1:
		background = OneGunUI.color("gold").darkened(0.72)
	elif placement == 2:
		background = Color(0.19, 0.22, 0.30)
	elif placement == 3:
		background = Color(0.28, 0.17, 0.09)
	panel.add_theme_stylebox_override("panel", OneGunUI.style_box(
		background, OneGunUI.color(border_role), 8, 2, 0, 5.0))
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 52.0
	panel.add_child(row)
	var values: Array = [
		[_ordinal(placement), 58.0],
		[_entry_display_name(entry), 175.0],
		[str(int(entry.get("round_wins", 0))), 42.0],
		[str(int(entry.get("kills", 0))), 34.0],
		[str(int(entry.get("disarms", 0))), 42.0],
	]
	if full:
		values = [
			[_ordinal(placement), 58.0], [_entry_display_name(entry), 220.0],
			[str(int(entry.get("round_wins", 0))), 48.0],
			[str(int(entry.get("runner_up_finishes", 0))), 48.0],
			[str(int(entry.get("third_place_finishes", 0))), 48.0],
			[str(int(entry.get("kills", 0))), 48.0],
			[str(int(entry.get("deaths", 0))), 48.0],
			[str(int(entry.get("disarms", 0))), 58.0],
			[str(int(entry.get("pickups", 0))), 58.0],
			[str(int(entry.get("melee", 0))), 70.0],
		]
	var column_index := 0
	for value in values:
		var label := OneGunUI.make_label(str(value[0]), 16,
			"gold" if placement == 1 else "text", placement <= 3)
		label.custom_minimum_size.x = float(value[1])
		if column_index == 1:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(label)
		column_index += 1
	if not full:
		var ready := OneGunUI.make_label("—", 15, "muted", true)
		ready.custom_minimum_size.x = 62.0
		ready.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(ready)
		var peer_id := int(entry.get("peer_id", -1))
		if peer_id > 0 and not bool(entry.get("is_bot", false)):
			_standing_ready_labels[peer_id] = ready
	return panel


func _build_personal_results(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "PersonalResults"
	row.custom_minimum_size.y = 164.0
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var found := false
	for actor_id in _viewer_actor_ids:
		var entry := _entry_for_actor(actor_id)
		if entry.is_empty():
			continue
		found = true
		row.add_child(_make_personal_card(entry))
	if not found:
		var spectator := OneGunCabinet.new()
		spectator.variant = OneGunCabinet.Variant.SECTION
		spectator.content_padding = 12
		spectator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spectator)
		var label := OneGunUI.make_heading("SPECTATING — MATCH RESULTS", 19, "muted")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		spectator.get_content().add_child(label)


func _make_personal_card(entry: Dictionary) -> Control:
	var cabinet := OneGunCabinet.new()
	cabinet.variant = OneGunCabinet.Variant.SECTION
	cabinet.content_padding = 10
	cabinet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cabinet.set_meta("personal_entry", entry.duplicate(true))
	cabinet.ready.connect(_finish_personal_card.bind(cabinet), CONNECT_ONE_SHOT)
	return cabinet


func _finish_personal_card(cabinet: OneGunCabinet) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	cabinet.get_content().add_child(column)
	var entry: Dictionary = cabinet.get_meta("personal_entry", {})
	var heading := OneGunUI.make_heading("YOUR RESULT — %s" % _ordinal(
		int(entry.get("placement", 0))), 25, "gold" if int(entry.get("placement", 0)) <= 3 else "text")
	column.add_child(heading)
	var stats := OneGunUI.make_label(
		"ROUND WINS  %d     KILLS  %d     DISARMS  %d" % [
			int(entry.get("round_wins", 0)), int(entry.get("kills", 0)),
			int(entry.get("disarms", 0))], 18, "text", true)
	column.add_child(stats)
	var reward := RewardPreview.for_actor(
		_result, int(entry.get("actor_id", -1)))
	var rewards := OneGunUI.make_label(RewardPreview.summary_text(reward), 16,
		"green" if bool(_result.get("official", false)) else "muted", true)
	column.add_child(rewards)


func _build_controls(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 60.0
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	_ready_count_label = OneGunUI.make_label("0 / 0 PLAYERS READY", 16, "muted", true)
	_ready_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ready_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_ready_count_label)
	_auto_return_label = OneGunUI.make_label("AUTO RETURN IN 25", 16, "muted", true)
	_auto_return_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_auto_return_label)

	if _online:
		var local_peer_id := int(_result.get("local_peer_id", -1))
		var is_participant := false
		for entry_value in _entries:
			var entry: Dictionary = entry_value
			if int(entry.get("peer_id", -1)) == local_peer_id \
					and not bool(entry.get("is_bot", false)):
				is_participant = true
				break
		if is_participant:
			_ready_button = OneGunButton.new()
			_ready_button.name = "ReadyButton"
			_ready_button.text = "READY"
			_ready_button.variant = "gold"
			_ready_button.toggle_mode = true
			_ready_button.disabled = true
			_ready_button.custom_minimum_size = Vector2(170.0, 52.0)
			_ready_button.toggled.connect(func(value: bool) -> void: ready_changed.emit(value))
			row.add_child(_ready_button)
		if _host_view:
			_host_return_button = OneGunButton.new()
			_host_return_button.name = "HostReturnButton"
			_host_return_button.text = "RETURN ALL NOW"
			_host_return_button.variant = "purple"
			_host_return_button.disabled = true
			_host_return_button.custom_minimum_size = Vector2(205.0, 52.0)
			_host_return_button.pressed.connect(func() -> void: force_return_requested.emit())
			row.add_child(_host_return_button)
	else:
		_ready_count_label.text = "LOCAL PLAYERS READY"
		for actor_id in _viewer_actor_ids:
			if _entry_for_actor(actor_id).is_empty():
				continue
			var button := OneGunButton.new()
			button.text = "P%d READY" % actor_id
			button.variant = "gold"
			button.toggle_mode = true
			button.disabled = true
			button.custom_minimum_size = Vector2(165.0, 52.0)
			button.toggled.connect(_on_local_ready_toggled.bind(actor_id, button))
			row.add_child(button)
			_local_ready_buttons[actor_id] = button
			_local_ready_actor_ids[actor_id] = false


func _build_full_stats_overlay() -> void:
	_full_stats_overlay = Control.new()
	_full_stats_overlay.name = "FullStatsOverlay"
	_full_stats_overlay.z_index = 50
	_full_stats_overlay.visible = false
	_full_stats_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_full_stats_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_full_stats_overlay.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 54)
	_full_stats_overlay.add_child(margin)
	var cabinet := OneGunCabinet.new()
	cabinet.variant = OneGunCabinet.Variant.CABINET
	cabinet.content_padding = 18
	margin.add_child(cabinet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	cabinet.get_content().add_child(column)
	var heading := OneGunUI.make_heading("COMPLETE MATCH RESULTS", 27, "gold")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	column.add_child(_make_standings_header(true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 5)
	scroll.add_child(rows)
	for entry_value in _entries:
		rows.add_child(_make_standings_row(entry_value, true))
	var close := OneGunButton.new()
	close.text = "BACK TO WINNERS CIRCLE"
	close.variant = "gold"
	close.custom_minimum_size.y = 48.0
	close.pressed.connect(func() -> void: _full_stats_overlay.visible = false)
	column.add_child(close)


func _show_full_stats() -> void:
	if _full_stats_overlay != null:
		_full_stats_overlay.visible = true


func _on_local_ready_toggled(value: bool, actor_id: int,
		button: OneGunButton) -> void:
	_local_ready_actor_ids[actor_id] = value
	button.text = "P%d READY  ✓" % actor_id if value else "P%d READY" % actor_id
	button.variant = "green" if value else "gold"
	var ready_count := 0
	for is_ready in _local_ready_actor_ids.values():
		if bool(is_ready):
			ready_count += 1
	_ready_count_label.text = "%d / %d LOCAL PLAYERS READY" % [
		ready_count, _local_ready_actor_ids.size()]
	if ready_count == _local_ready_actor_ids.size() and ready_count > 0:
		start_return_countdown(3.0)


func _build_stage_world(container: SubViewportContainer) -> void:
	_stage_viewport = SubViewport.new()
	_stage_viewport.name = "WinnersCircleViewport"
	_stage_viewport.size = Vector2i(960, 540)
	_stage_viewport.own_world_3d = true
	_stage_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_stage_viewport)
	_stage_blockout = StageBlockoutScene.instantiate() as Node3D
	if _stage_blockout == null:
		push_error("Winners Circle stage blockout failed to instantiate")
		return
	_stage_viewport.add_child(_stage_blockout)
	_stage_blockout.call("configure", _entries, _result)
	_performers = _stage_blockout.call("performer_records")
	_trophy_root = _stage_blockout.call("trophy_root") as Node3D
	_confetti = _stage_blockout.call("confetti") as GPUParticles3D


func _build_legacy_stage_world(container: SubViewportContainer) -> void:
	_stage_viewport = SubViewport.new()
	_stage_viewport.name = "WinnersCircleViewport"
	_stage_viewport.size = Vector2i(960, 540)
	_stage_viewport.own_world_3d = true
	_stage_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_stage_viewport)

	var world := Node3D.new()
	world.name = "WinnersCircleWorld"
	_stage_viewport.add_child(world)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.008, 0.016, 0.055)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.52, 0.61, 0.92)
	environment.ambient_light_energy = 0.78
	world_environment.environment = environment
	world.add_child(world_environment)

	_build_stage_backdrop(world)
	var podium_data := [
		{"entry_index": 1, "x": -3.15, "height": 0.82, "z": 0.30,
			"color": Color(0.48, 0.54, 0.66), "rank": "2"},
		{"entry_index": 0, "x": 0.0, "height": 1.28, "z": 0.0,
			"color": OneGunUI.color("gold"), "rank": "1"},
		{"entry_index": 2, "x": 3.15, "height": 0.62, "z": 0.48,
			"color": Color(0.66, 0.34, 0.13), "rank": "3"},
	]
	for data in podium_data:
		var entry_index := int(data["entry_index"])
		if entry_index >= _entries.size():
			continue
		_build_podium_competitor(world, _entries[entry_index], data)
	_build_ceremonial_gun(world)
	if bool(_result.get("trophy_awarded", false)):
		_build_trophy(world)
	_build_confetti(world)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, -24.0, 0.0)
	key.light_color = Color(1.0, 0.84, 0.64)
	key.light_energy = 2.15
	key.shadow_enabled = false
	world.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0.0, 3.6, -2.0)
	rim.light_color = Color(0.28, 0.38, 1.0)
	rim.light_energy = 4.0
	rim.omni_range = 12.0
	rim.shadow_enabled = false
	world.add_child(rim)
	var champion_light := OmniLight3D.new()
	champion_light.position = Vector3(0.0, 3.3, 2.0)
	champion_light.light_color = OneGunUI.color("gold")
	champion_light.light_energy = 3.2
	champion_light.omni_range = 6.5
	champion_light.shadow_enabled = false
	world.add_child(champion_light)

	var camera := Camera3D.new()
	camera.name = "WinnersCircleCamera"
	camera.fov = 41.0
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 4.15, 14.8),
		Vector3(0.0, 2.15, 0.0), Vector3.UP)
	camera.current = true


func _build_stage_backdrop(world: Node3D) -> void:
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(18.0, 11.0)
	floor.mesh = floor_mesh
	floor.material_override = _stage_material(Color(0.018, 0.035, 0.09),
		Color(0.02, 0.08, 0.24), 0.55)
	world.add_child(floor)
	var back := MeshInstance3D.new()
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(15.5, 7.2, 0.24)
	back.mesh = back_mesh
	back.position = Vector3(0.0, 3.25, -2.5)
	back.material_override = _stage_material(Color(0.022, 0.025, 0.085),
		Color(0.11, 0.04, 0.26), 0.30)
	world.add_child(back)
	var marquee := Label3D.new()
	marquee.text = "★  WINNERS CIRCLE  ★"
	marquee.position = Vector3(0.0, 6.05, -2.25)
	marquee.font_size = 58
	marquee.outline_size = 12
	marquee.modulate = OneGunUI.color("gold")
	marquee.outline_modulate = Color(0.08, 0.025, 0.0)
	world.add_child(marquee)


func _build_podium_competitor(world: Node3D, entry: Dictionary,
		data: Dictionary) -> void:
	var x := float(data["x"])
	var height := float(data["height"])
	var z := float(data["z"])
	var color: Color = data["color"]
	var podium := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.55, height, 2.05)
	podium.mesh = box
	podium.position = Vector3(x, height * 0.5, z)
	podium.material_override = _stage_material(color.darkened(0.34), color, 0.72)
	world.add_child(podium)
	var rank_label := Label3D.new()
	rank_label.text = str(data["rank"])
	rank_label.position = Vector3(x, height * 0.52, z + 1.04)
	rank_label.font_size = 76
	rank_label.outline_size = 12
	rank_label.modulate = color.lightened(0.22)
	rank_label.outline_modulate = Color(0.02, 0.02, 0.04)
	world.add_child(rank_label)

	var pivot := Node3D.new()
	pivot.position = Vector3(x, height + 0.02, z)
	world.add_child(pivot)
	var model_id := SkinRegistry.sanitize_model_id(str(entry.get("model_id", "male")))
	var visual_scene := SkinRegistry.load_visual_scene(model_id)
	if visual_scene != null:
		var visual := visual_scene.instantiate() as Node3D
		if visual != null:
			visual.set("model_id", model_id)
			visual.set("skin_id", SkinRegistry.sanitize_skin_id(
				str(entry.get("skin_id", "blue"))))
			visual.set("build_animation_library", false)
			pivot.add_child(visual)
			var cosmetics := CosmeticRegistry.sanitize_loadout(entry.get("cosmetics", {}))
			var move_id := str(cosmetics.get("emote", ""))
			var move_animation := CosmeticRegistry.local_victory_animation(move_id)
			var requested := ["idle", "long_idle"]
			if move_animation != "":
				requested.append(move_animation)
			var animation_player := visual.call("ensure_animations", requested) as AnimationPlayer
			_performers.append({
				"animation_player": animation_player,
				"animation": move_animation,
			})
	var nameplate := Label3D.new()
	nameplate.text = _entry_display_name(entry)
	nameplate.position = Vector3(x, height + 2.75, z + 0.12)
	nameplate.font_size = 35
	nameplate.outline_size = 10
	nameplate.modulate = color.lightened(0.18)
	nameplate.outline_modulate = Color(0.015, 0.02, 0.05)
	world.add_child(nameplate)


func _build_ceremonial_gun(world: Node3D) -> void:
	if _entries.is_empty():
		return
	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(3.3, 1.65, 0.18)
	frame.mesh = frame_mesh
	frame.position = Vector3(0.0, 4.35, -2.08)
	frame.material_override = _stage_material(Color(0.07, 0.035, 0.01),
		OneGunUI.color("gold"), 0.85)
	world.add_child(frame)
	if not ResourceLoader.exists(GUN_MODEL_PATH):
		return
	var gun_scene := load(GUN_MODEL_PATH) as PackedScene
	if gun_scene == null:
		return
	var gun := gun_scene.instantiate() as Node3D
	if gun == null:
		return
	gun.name = "CeremonialOneGun"
	gun.position = Vector3(0.0, 4.35, -1.92)
	gun.rotation_degrees = Vector3(-8.0, 180.0, 18.0)
	gun.scale = Vector3.ONE * 0.0032
	world.add_child(gun)
	var champion: Dictionary = _entries[0]
	var cosmetics := CosmeticRegistry.sanitize_loadout(champion.get("cosmetics", {}))
	CosmeticRegistry.apply_gun_skin_to_display(
		gun, str(cosmetics.get("gun_skin", "")))


func _build_trophy(world: Node3D) -> void:
	_trophy_root = Node3D.new()
	_trophy_root.name = "VictoryTrophy"
	_trophy_root.position = Vector3(0.0, 6.8, 1.35)
	_trophy_root.visible = false
	world.add_child(_trophy_root)
	if ResourceLoader.exists(TROPHY_MODEL_PATH):
		var trophy_scene := load(TROPHY_MODEL_PATH) as PackedScene
		if trophy_scene != null:
			var trophy := trophy_scene.instantiate() as Node3D
			if trophy != null:
				_trophy_root.add_child(trophy)
				return
	_build_placeholder_trophy(_trophy_root)


func _build_placeholder_trophy(parent: Node3D) -> void:
	var gold := _stage_material(Color(0.72, 0.39, 0.04),
		OneGunUI.color("gold"), 0.92)
	var cup := MeshInstance3D.new()
	var cup_mesh := SphereMesh.new()
	cup_mesh.radius = 0.42
	cup_mesh.height = 0.62
	cup.mesh = cup_mesh
	cup.scale = Vector3(1.0, 0.62, 0.72)
	cup.position.y = 0.72
	cup.material_override = gold
	parent.add_child(cup)
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.09
	stem_mesh.bottom_radius = 0.13
	stem_mesh.height = 0.48
	stem.mesh = stem_mesh
	stem.position.y = 0.26
	stem.material_override = gold
	parent.add_child(stem)
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.72, 0.18, 0.52)
	base.mesh = base_mesh
	base.position.y = -0.05
	base.material_override = _stage_material(Color(0.05, 0.025, 0.01),
		Color(0.54, 0.28, 0.03), 0.75)
	parent.add_child(base)


func _build_confetti(world: Node3D) -> void:
	_confetti = GPUParticles3D.new()
	_confetti.name = "WinnerConfetti"
	_confetti.position = Vector3(0.0, 6.6, 0.0)
	_confetti.amount = 40
	_confetti.lifetime = 3.0
	_confetti.one_shot = true
	_confetti.explosiveness = 0.92
	_confetti.emitting = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(4.8, 0.2, 1.8)
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 38.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 3.0
	process.gravity = Vector3(0.0, -2.8, 0.0)
	_confetti.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.16)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = OneGunUI.color("gold")
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = material
	_confetti.draw_pass_1 = quad
	world.add_child(_confetti)


func _stage_material(albedo: Color, emission: Color,
		metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.metallic = metallic
	material.roughness = 0.28
	if emission.a > 0.0 and emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = Color(emission.r, emission.g, emission.b)
		material.emission_energy_multiplier = 0.42
	return material


func _run_presentation_sequence() -> void:
	await get_tree().create_timer(2.35, true).timeout
	if not is_inside_tree():
		return
	for performer in _performers:
		var animation_player := performer.get("animation_player") as AnimationPlayer
		if animation_player == null:
			continue
		var animation_name := str(performer.get("animation", ""))
		if _reduced_motion() or animation_name == "" \
				or not animation_player.has_animation(animation_name):
			if animation_player.has_animation("long_idle"):
				animation_player.play("long_idle", 0.0)
			elif animation_player.has_animation("idle"):
				animation_player.play("idle", 0.0)
		else:
			animation_player.play(animation_name, 0.0)
	if _confetti != null and not _reduced_motion():
		_confetti.restart()
	await get_tree().create_timer(4.0, true).timeout
	if is_inside_tree() and _trophy_root != null:
		_drop_trophy()


func _drop_trophy() -> void:
	_trophy_root.visible = true
	var target_y := float(_trophy_root.get_meta("landing_y", 1.68))
	if _reduced_motion():
		_trophy_root.position.y = target_y
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_trophy_root, "position:y", target_y, 0.82) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _entry_for_actor(actor_id: int) -> Dictionary:
	for entry_value in _entries:
		var entry: Dictionary = entry_value
		if int(entry.get("actor_id", -1)) == actor_id:
			return entry
	return {}


func _entry_display_name(entry: Dictionary) -> String:
	var display_name := str(entry.get("name", "Player")).strip_edges()
	var handle := str(entry.get("account_handle", "")).strip_edges()
	if handle != "":
		return "%s  @%s" % [display_name, handle.trim_prefix("@")]
	if bool(entry.get("duplicate_name", false)):
		return "%s  ·  P%d" % [display_name, int(entry.get("actor_id", 0))]
	return display_name


func _ordinal(value: int) -> String:
	if value <= 0:
		return "—"
	var last_two := value % 100
	if last_two in [11, 12, 13]:
		return "%dTH" % value
	match value % 10:
		1: return "%dST" % value
		2: return "%dND" % value
		3: return "%dRD" % value
	return "%dTH" % value


func _reduced_motion() -> bool:
	var accessibility := get_node_or_null("/root/AccessibilityManager")
	return accessibility != null and accessibility.reduced_motion_enabled()
