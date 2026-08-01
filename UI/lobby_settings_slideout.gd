class_name OneGunLobbySettingsSlideout
extends OneGunCabinet

# Transactional Phase 3 settings cabinet. Every control edits `_pending`; the
# live GameConfig is touched only after APPLY. This keeps Cancel, Escape and
# switching between the two connected panels lossless and predictable.

signal applied(values: Dictionary)
signal closed

enum Kind { BOT, MATCH }

const DIFFICULTIES := ["easy", "medium", "hard", "expert"]
const MATCH_TABS := ["GENERAL", "COMBAT", "SPAWNS", "PRESETS"]

@export var panel_kind: Kind = Kind.MATCH
@export var maximum_bots := 9
@export var online_mode := false

var _pending: Dictionary = {}
var _original: Dictionary = {}
var _body: VBoxContainer
var _tab_bar: OneGunTabBar
var _selected_tab := 0
var _apply_button: OneGunButton
var _pending_label: Label
var _first_focus: Control


func _ready() -> void:
	super()
	variant = OneGunCabinet.Variant.CABINET
	content_padding = OneGunUI.SPACE_L
	show_bolts = true
	_pending = GameConfig.snapshot_for_preset().duplicate(true)
	_original = _pending.duplicate(true)
	_build_ui()


func has_changes() -> bool:
	return _pending != _original


func focus_first() -> void:
	if _first_focus != null and is_instance_valid(_first_focus):
		_first_focus.grab_focus.call_deferred()


func close_without_applying() -> void:
	closed.emit()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	get_content().add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	root.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	var title_text := "BOT SETTINGS" if panel_kind == Kind.BOT else "MATCH SETTINGS"
	titles.add_child(OneGunUI.make_heading(title_text, OneGunUI.TEXT_XL, "gold"))
	var subtitle := "Build the roster before the match starts." if panel_kind == Kind.BOT else "Tune the rules without changing the live lobby until Apply."
	var subtitle_label := OneGunUI.make_label(subtitle, OneGunUI.TEXT_S, "muted")
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(subtitle_label)
	var close_button := OneGunButton.new()
	close_button.name = "CloseSettings"
	close_button.variant = "navy"
	close_button.text = "CLOSE"
	close_button.font_size = OneGunUI.TEXT_S
	close_button.tooltip_text = "Discard pending changes and close"
	close_button.pressed.connect(close_without_applying)
	header.add_child(close_button)

	if panel_kind == Kind.MATCH:
		_tab_bar = OneGunTabBar.new()
		_tab_bar.tabs = PackedStringArray(MATCH_TABS)
		_tab_bar.tab_selected.connect(_on_tab_selected)
		root.add_child(_tab_bar)
		_first_focus = _tab_bar.get_child(0) as Control if _tab_bar.get_child_count() > 0 else null

	var well := OneGunCabinet.new()
	well.variant = OneGunCabinet.Variant.WELL
	well.content_padding = OneGunUI.SPACE_M
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(well)
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well.get_content().add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

	_pending_label = OneGunUI.make_label("", OneGunUI.TEXT_XS, "muted")
	_pending_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_pending_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	root.add_child(footer)
	var reset := OneGunButton.new()
	reset.name = "ResetPending"
	reset.variant = "navy"
	reset.text = "RESET"
	reset.tooltip_text = "Restore defaults in this pending panel; Apply is still required"
	reset.pressed.connect(_on_reset_pressed)
	footer.add_child(reset)
	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_spacer)
	var cancel := OneGunButton.new()
	cancel.name = "CancelPending"
	cancel.variant = "navy"
	cancel.text = "CANCEL"
	cancel.tooltip_text = "Discard every pending change"
	cancel.pressed.connect(close_without_applying)
	footer.add_child(cancel)
	_apply_button = OneGunButton.new()
	_apply_button.name = "ApplySettings"
	_apply_button.variant = "gold"
	_apply_button.text = "APPLY"
	_apply_button.tooltip_text = "Commit these settings to the lobby"
	_apply_button.pressed.connect(_on_apply_pressed)
	footer.add_child(_apply_button)

	_rebuild_body()
	_refresh_pending_state()


func _on_tab_selected(index: int) -> void:
	_selected_tab = index
	_rebuild_body()


func _rebuild_body() -> void:
	_first_focus = _tab_bar.get_child(0) as Control if _tab_bar != null and _tab_bar.get_child_count() > 0 else null
	for child in _body.get_children():
		child.free()
	if panel_kind == Kind.BOT:
		_build_bot_settings()
	else:
		match _selected_tab:
			0: _build_general_tab()
			1: _build_combat_tab()
			2: _build_spawns_tab()
			3: _build_presets_tab()
	_refresh_pending_state()


func _build_bot_settings() -> void:
	_add_section_heading("ROSTER CAPACITY", "Ten total player slots. Up to %d bots fit the current roster." % maximum_bots)
	_add_int_stepper("BOT COUNT", int((_pending.get("bot_configs", []) as Array).size()), 0, maximum_bots,
		"Bots plus human players may never exceed ten.", _on_bot_count_changed)

	var set_all := _add_dropdown("SET ALL DIFFICULTY", DIFFICULTIES, "easy",
		"Applies one difficulty to every pending bot.", _on_set_all_difficulty)
	set_all.disabled = (_pending.get("bot_configs", []) as Array).is_empty()

	_add_divider()
	var bots: Array = _pending.get("bot_configs", [])
	if bots.is_empty():
		var empty := OneGunStatusPanel.new()
		_body.add_child(empty)
		empty.show_empty("NO BOTS ADDED", "Use the bot-count stepper above to add opponents.")
		return
	for index in bots.size():
		var section := OneGunCabinet.new()
		section.variant = OneGunCabinet.Variant.SECTION
		section.content_padding = OneGunUI.SPACE_M
		_body.add_child(section)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", OneGunUI.SPACE_S)
		section.get_content().add_child(column)
		column.add_child(OneGunUI.make_heading("BOT %02d" % (index + 1), OneGunUI.TEXT_M, "cyan"))
		_add_dropdown_to(column, "DIFFICULTY", DIFFICULTIES,
			str(bots[index].get("difficulty", "easy")),
			"Easy learns the arena; Expert pressures the objective aggressively.",
			func(value: String) -> void:
				(_pending["bot_configs"] as Array)[index]["difficulty"] = value
				_mark_changed())
		if bool(_pending.get("teams_enabled", false)) and not online_mode:
			var teams := ["no team", "team 1", "team 2", "team 3", "team 4"]
			var team_id := int(bots[index].get("team_id", -1))
			_add_dropdown_to(column, "TEAM", teams, teams[clampi(team_id + 1, 0, 4)],
				"Team assignment is available when Teams is enabled.",
				func(value: String) -> void:
					(_pending["bot_configs"] as Array)[index]["team_id"] = teams.find(value) - 1
					_mark_changed())


func _build_general_tab() -> void:
	_add_section_heading("MATCH FLOW", "Core structure, timing and team rules.")
	_add_toggle("TEAMS ENABLED", bool(_pending.get("teams_enabled", false)),
		"Group players into teams. Online team assignment is not implemented yet.",
		func(value: bool) -> void:
			_pending["teams_enabled"] = value if not online_mode else false
			if not value:
				_pending["friendly_fire_enabled"] = false
			_mark_changed()
			_rebuild_body(), online_mode)
	_add_toggle("FRIENDLY FIRE", bool(_pending.get("friendly_fire_enabled", false)),
		"Allow teammates to affect one another.",
		func(value: bool) -> void:
			_pending["friendly_fire_enabled"] = value
			_mark_changed(), online_mode or not bool(_pending.get("teams_enabled", false)))
	_add_float_spin("ROUND TIME LIMIT", float(_pending.get("round_time_limit", 0.0)), 0.0, 900.0, 1.0, "SECONDS",
		"Set any whole-second duration. Zero disables the round timer.",
		func(value: float) -> void: _pending["round_time_limit"] = value; _mark_changed())
	_add_toggle("CHAOS OT", bool(_pending.get("chaos_overtime_enabled", false)),
		"At overtime, remove all tools and powerups and give every survivor a gun. Off keeps the one-gun disarm rules.",
		func(value: bool) -> void: _pending["chaos_overtime_enabled"] = value; _mark_changed())
	_add_float_spin("FIRE EXPOSURE TIME", float(_pending.get("overtime_fire_exposure_time", 5.0)), 0.5, 15.0, 0.5, "SECONDS",
		"Zone 1 time allowed in overtime fire. Later zones remove one second, down to a three-second floor or this value when lower.",
		func(value: float) -> void: _pending["overtime_fire_exposure_time"] = value; _mark_changed())
	_add_int_stepper("ROUNDS PER SET", int(_pending.get("rounds_per_set", 3)), 1, 20,
		"Rounds required to win a set.", func(value: int) -> void: _pending["rounds_per_set"] = value; _mark_changed())
	_add_int_stepper("SETS PER MATCH", int(_pending.get("sets_per_match", 3)), 1, 20,
		"Sets required to win the match.", func(value: int) -> void: _pending["sets_per_match"] = value; _mark_changed())


func _build_combat_tab() -> void:
	_add_section_heading("COMBAT RULES", "Tune disarms, melee lethality and movement resources.")
	_add_toggle("MELEE ELIMINATES GUN HOLDER", bool(_pending.get("melee_eliminates_gunholder", false)),
		"A melee hit immediately eliminates the current gun holder.",
		func(value: bool) -> void: _pending["melee_eliminates_gunholder"] = value; _mark_changed())
	_add_toggle("MELEE ELIMINATES ANYONE", bool(_pending.get("melee_eliminates_anyone", false)),
		"A melee hit can immediately eliminate any player.",
		func(value: bool) -> void: _pending["melee_eliminates_anyone"] = value; _mark_changed())
	_add_toggle("MELEE EFFECTS HIT ANYONE", bool(_pending.get("melee_effects_hit_anyone", true)),
		"Allow non-elimination melee effects to affect players beyond the gun holder.",
		func(value: bool) -> void: _pending["melee_effects_hit_anyone"] = value; _mark_changed())
	_add_toggle("MELEE WEAPON BREAKING", bool(_pending.get("melee_weapon_breaking", true)),
		"A swing begun at zero stamina is allowed, then temporarily breaks the melee weapon.",
		func(value: bool) -> void: _pending["melee_weapon_breaking"] = value; _mark_changed())
	_add_float_spin("DISARM LOCK TIME", float(_pending.get("disarm_lock_time", 3.0)), 0.0, 10.0, 0.5, "SECONDS",
		"How long a disarmed player waits before taking the gun again.",
		func(value: float) -> void: _pending["disarm_lock_time"] = value; _mark_changed())
	_add_int_stepper("MAX DASH CHARGES", int(_pending.get("max_dash_charges", 2)), 0, 6,
		"Maximum dash charges granted at spawn.", func(value: int) -> void: _pending["max_dash_charges"] = value; _mark_changed())


func _build_spawns_tab() -> void:
	_add_section_heading("SPAWNS & ITEMS", "Control weapon timing and every implemented item type.")
	_add_dropdown("GUN SPAWN MODE", ["center", "random"], str(_pending.get("gun_spawn_mode", "center")),
		"Choose a fixed center spawn or a random authored gun marker.",
		func(value: String) -> void: _pending["gun_spawn_mode"] = value; _mark_changed())
	_add_float_spin("MELEE SPAWN DELAY", float(_pending.get("melee_spawn_delay", 0.0)), 0.0, 15.0, 0.5, "SECONDS",
		"Delay before the one melee weapon can be picked up.",
		func(value: float) -> void: _pending["melee_spawn_delay"] = value; _mark_changed())
	_add_float_spin("DROPPED MELEE DESPAWN", float(_pending.get("dropped_melee_despawn_time", 3.0)), 0.0, 30.0, 0.5, "SECONDS",
		"Zero leaves a dropped melee weapon in place indefinitely.",
		func(value: float) -> void: _pending["dropped_melee_despawn_time"] = value; _mark_changed())
	_add_divider()
	_add_toggle("HAZARDS ENABLED", bool(_pending.get("hazards_enabled", true)),
		"Master switch for all hazard items.", func(value: bool) -> void: _pending["hazards_enabled"] = value; _mark_changed())
	_add_toggle("CONSUMABLES ENABLED", bool(_pending.get("consumables_enabled", true)),
		"Master switch for all consumable items.", func(value: bool) -> void: _pending["consumables_enabled"] = value; _mark_changed())
	var registry: Dictionary = _pending.get("item_registry", {})
	for item_name in registry.keys():
		var entry: Dictionary = registry[item_name]
		var category := str(entry.get("category", "item")).to_upper()
		_add_toggle(str(item_name).replace("_", " ").to_upper(), bool(entry.get("enabled", true)),
			"%s item. The category master switch still takes precedence." % category,
			func(value: bool) -> void:
				(_pending["item_registry"] as Dictionary)[item_name]["enabled"] = value
				_mark_changed())


func _build_presets_tab() -> void:
	_add_section_heading("RULESET PRESETS", "Five disk-backed slots. Loading edits pending values; Apply still commits them.")
	for slot_index in GameConfig.MAX_PRESET_SLOTS:
		var section := OneGunCabinet.new()
		section.variant = OneGunCabinet.Variant.SECTION
		section.content_padding = OneGunUI.SPACE_M
		_body.add_child(section)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", OneGunUI.SPACE_S)
		section.get_content().add_child(column)
		var name_field := _make_line_edit("Preset %d" % (slot_index + 1), 24)
		name_field.name = "PresetName%d" % slot_index
		name_field.text = "" if GameConfig.is_preset_slot_empty(slot_index) else GameConfig.get_preset_slot_name(slot_index)
		column.add_child(name_field)
		var error := OneGunInlineError.new()
		column.add_child(error)
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", OneGunUI.SPACE_S)
		column.add_child(actions)
		var slot_is_empty := GameConfig.is_preset_slot_empty(slot_index)
		var perform_save := func() -> void:
			error.clear()
			if not GameConfig.save_preset_values(slot_index, name_field.text, _pending):
				error.show_error("Enter a preset name (1-24 characters).")
				name_field.grab_focus()
				return
			_rebuild_body()
		var save: OneGunButton
		if slot_is_empty:
			save = OneGunButton.new()
			save.text = "SAVE"
			save.pressed.connect(perform_save)
		else:
			var confirm_save := OneGunConfirmButton.new()
			confirm_save.text = "UPDATE"
			confirm_save.confirm_text = "CONFIRM UPDATE"
			confirm_save.confirmed.connect(perform_save)
			save = confirm_save
		save.variant = "gold"
		save.tooltip_text = "Save the current pending rules to this slot"
		actions.add_child(save)
		var load := OneGunButton.new()
		load.variant = "blue"
		load.text = "LOAD"
		load.disabled = GameConfig.is_preset_slot_empty(slot_index)
		load.tooltip_text = "Load this slot into pending settings"
		load.pressed.connect(func() -> void:
			var values := GameConfig.get_preset_slot_values(slot_index)
			if values.is_empty():
				return
			_pending = values
			_mark_changed()
			_rebuild_body())
		actions.add_child(load)
		var action_spacer := Control.new()
		action_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(action_spacer)
		var remove := OneGunConfirmButton.new()
		remove.variant = "navy"
		remove.text = "DELETE"
		remove.confirm_text = "CONFIRM DELETE"
		remove.disabled = GameConfig.is_preset_slot_empty(slot_index)
		remove.tooltip_text = "Press twice to permanently delete this preset"
		remove.confirmed.connect(func() -> void:
			GameConfig.delete_preset_slot(slot_index)
			_rebuild_body())
		actions.add_child(remove)


func _add_section_heading(title: String, description: String) -> void:
	_body.add_child(OneGunUI.make_heading(title, OneGunUI.TEXT_L, "gold"))
	var desc := OneGunUI.make_label(description, OneGunUI.TEXT_S, "muted")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(desc)


func _add_divider() -> void:
	_body.add_child(HSeparator.new())


func _make_setting_row(label_text: String, tooltip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", OneGunUI.SPACE_M)
	row.tooltip_text = tooltip
	var label := OneGunUI.make_label(label_text, OneGunUI.TEXT_S, "text", true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var help := OneGunHelpIcon.new()
	help.tooltip_text = tooltip
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(help)
	return row


func _add_toggle(label_text: String, value: bool, tooltip: String, callback: Callable,
		disabled := false) -> OneGunToggle:
	var row := _make_setting_row(label_text, tooltip)
	_body.add_child(row)
	var toggle := OneGunToggle.new()
	toggle.button_pressed = value
	toggle.disabled = disabled
	toggle.tooltip_text = tooltip
	toggle.toggled.connect(callback)
	row.add_child(toggle)
	if _first_focus == null and not disabled:
		_first_focus = toggle
	return toggle


func _add_int_stepper(label_text: String, value: int, min_value: int, max_value: int,
		tooltip: String, callback: Callable) -> OneGunStepper:
	var row := _make_setting_row(label_text, tooltip)
	_body.add_child(row)
	var stepper := OneGunStepper.new()
	stepper.min_value = min_value
	stepper.max_value = max_value
	stepper.value = value
	stepper.tooltip_text = tooltip
	stepper.value_changed.connect(callback)
	row.add_child(stepper)
	if _first_focus == null and stepper.get_child_count() > 0:
		_first_focus = stepper.get_child(0) as Control
	return stepper


func _add_float_spin(label_text: String, value: float, min_value: float, max_value: float,
		step: float, suffix: String, tooltip: String, callback: Callable) -> SpinBox:
	var row := _make_setting_row(label_text, tooltip)
	_body.add_child(row)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.suffix = " " + suffix
	spin.custom_minimum_size = Vector2(150, 42)
	spin.tooltip_text = tooltip
	spin.value_changed.connect(callback)
	row.add_child(spin)
	if _first_focus == null:
		_first_focus = spin
	return spin


func _add_dropdown(label_text: String, options: Array, current: String, tooltip: String,
		callback: Callable) -> OptionButton:
	return _add_dropdown_to(_body, label_text, options, current, tooltip, callback)


func _add_dropdown_to(parent: VBoxContainer, label_text: String, options: Array, current: String,
		tooltip: String, callback: Callable) -> OptionButton:
	var row := _make_setting_row(label_text, tooltip)
	parent.add_child(row)
	var dropdown := OneGunUI.make_dropdown()
	for option in options:
		dropdown.add_item(str(option).capitalize())
	var selected_index := options.find(current)
	dropdown.select(maxi(selected_index, 0))
	dropdown.tooltip_text = tooltip
	dropdown.item_selected.connect(func(index: int) -> void: callback.call(str(options[index])))
	row.add_child(dropdown)
	if _first_focus == null:
		_first_focus = dropdown
	return dropdown


func _make_line_edit(placeholder: String, max_length: int) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = max_length
	field.custom_minimum_size = Vector2(0, 44)
	field.add_theme_font_size_override("font_size", OneGunUI.TEXT_M)
	field.add_theme_color_override("font_color", OneGunUI.color("text"))
	field.add_theme_color_override("font_placeholder_color", OneGunUI.color("muted"))
	var normal := OneGunUI.style_box(OneGunUI.color("well"), OneGunUI.color("border"), OneGunUI.RADIUS_INPUT, OneGunUI.BORDER_THIN, 0, 10)
	field.add_theme_stylebox_override("normal", normal)
	field.add_theme_stylebox_override("focus", OneGunUI.focus_ring(normal))
	return field


func _on_bot_count_changed(value: int) -> void:
	var bots: Array = _pending.get("bot_configs", []).duplicate(true)
	while bots.size() < value:
		bots.append({"difficulty": "easy", "team_id": -1})
	while bots.size() > value:
		bots.pop_back()
	_pending["bot_configs"] = bots
	_mark_changed()
	_rebuild_body()


func _on_set_all_difficulty(value: String) -> void:
	for bot in _pending.get("bot_configs", []):
		bot["difficulty"] = value
	_mark_changed()
	_rebuild_body()


func _on_reset_pressed() -> void:
	if panel_kind == Kind.BOT:
		_pending["bot_configs"] = GameConfig.default_match_settings()["bot_configs"].duplicate(true)
	else:
		var bots: Array = _pending.get("bot_configs", []).duplicate(true)
		_pending = GameConfig.default_match_settings()
		_pending["bot_configs"] = bots
	_mark_changed()
	_rebuild_body()


func _on_apply_pressed() -> void:
	applied.emit(_pending.duplicate(true))


func _mark_changed() -> void:
	_refresh_pending_state()


func _refresh_pending_state() -> void:
	if _pending_label == null or _apply_button == null:
		return
	var dirty := has_changes()
	_pending_label.text = "PENDING CHANGES — APPLY TO COMMIT" if dirty else "NO PENDING CHANGES"
	_pending_label.add_theme_color_override("font_color", OneGunUI.color("gold" if dirty else "muted"))
	_apply_button.disabled = not dirty
