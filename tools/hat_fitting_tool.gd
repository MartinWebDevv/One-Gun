extends Control

# Developer-only visual fitter for every shipped Hat on every registered
# character model. Run res://tools/hat_fitting_tool.tscn from the Godot editor. Drafts
# stay in memory until Save is pressed; source GLBs are never modified.

const HatRegistry = preload("res://models/cosmetics/hats/hat_cosmetic_registry.gd")
const SkinRegistry = preload("res://player_skin_registry.gd")
const FitProfileSchema = preload("res://models/cosmetics/hats/hat_fit_profiles.gd")
const PROFILE_PATH := HatRegistry.FIT_PROFILE_PATH

var _profile: Resource = HatRegistry.FIT_PROFILES
var _hat_ids: Array[String] = []
var _hat_picker: OptionButton
var _model_picker: OptionButton
var _status_label: Label
var _selection_label: Label
var _save_selected_button: OneGunButton
var _save_all_button: OneGunButton
var _clear_override_button: OneGunConfirmButton
var _spin: Dictionary = {}
var _loading_controls := false

var _current_hat := ""
var _current_model := SkinRegistry.DEFAULT_MODEL_ID
var _drafts: Dictionary = {}
var _dirty_keys: Dictionary = {}
var _preview_refresh_pending := false

var _viewport: SubViewport
var _viewport_container: SubViewportContainer
var _world: Node3D
var _character_pivot: Node3D
var _visual: Node3D
var _manual_hat: Node3D
var _camera: Camera3D
var _idle_player: AnimationPlayer
var _idle_enabled := true
var _dragging := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hat_ids.assign(HatRegistry.HATS.keys())
	_hat_ids.sort_custom(func(a: String, b: String) -> bool:
		return HatRegistry.display_name(a).naturalnocasecmp_to(
			HatRegistry.display_name(b)) < 0)
	_build_interface()
	_build_preview_world()
	_populate_pickers()
	if not _hat_ids.is_empty():
		_current_hat = _hat_ids[0]
	_select_current_fit()
	_update_save_availability()
	UICapture.maybe_capture(self, "hat_fitting_tool", 2.0)


func _process(delta: float) -> void:
	if _character_pivot == null:
		return
	var look_axis := Input.get_axis("p1_look_left", "p1_look_right")
	if absf(look_axis) > 0.18:
		_character_pivot.rotate_y(-look_axis * delta * 1.7)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_S and event.ctrl_pressed:
		get_viewport().set_input_as_handled()
		_save_all_dirty()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _dirty_keys.is_empty():
			get_tree().quit()
		else:
			_set_status("UNSAVED FITS REMAIN — SAVE THEM OR CLICK EXIT TOOL TWICE", true)


func _build_interface() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.003, 0.008, 0.022)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(side, 20)
	add_child(outer)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	outer.add_child(page)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	page.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var eyebrow := OneGunUI.make_label(
		"ONE GUN  //  DEVELOPER COSMETIC TOOLS", 12, "cyan", true)
	titles.add_child(eyebrow)
	titles.add_child(OneGunUI.make_heading("HAT FITTING TOOL", 34, "gold"))
	var subtitle := OneGunUI.make_label(
		"LIVE PER-HAT / PER-MODEL POSITION, ROTATION, SIZE, AND SEATING — SOURCE GLBS STAY UNTOUCHED",
		12, "muted", true)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(subtitle)
	var exit_button := OneGunConfirmButton.new()
	exit_button.name = "ExitToolButton"
	exit_button.text = "EXIT TOOL"
	exit_button.confirm_text = "CONFIRM EXIT"
	exit_button.variant = "red"
	exit_button.custom_minimum_size = Vector2(170, 52)
	exit_button.tooltip_text = "Press twice. Unsaved drafts will be discarded."
	exit_button.confirmed.connect(func() -> void: get_tree().quit())
	header.add_child(exit_button)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	page.add_child(body)
	_build_preview_panel(body)
	_build_controls_panel(body)

	_status_label = OneGunUI.make_label("READY", 12, "green", true)
	_status_label.name = "FitToolStatus"
	_status_label.custom_minimum_size.y = 26
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_status_label)


func _build_preview_panel(parent: Control) -> void:
	var panel := OneGunCabinet.new()
	panel.name = "HatPreviewCabinet"
	panel.variant = OneGunCabinet.Variant.CABINET
	panel.content_padding = 14
	panel.custom_minimum_size = Vector2(680, 560)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.55
	# OneGunCabinet creates its Content node in _ready(), so it must enter the
	# scene tree before callers can populate get_content().
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.get_content().add_child(column)
	_selection_label = OneGunUI.make_heading("HAT PREVIEW", 20, "text_bright")
	_selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_selection_label)

	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", OneGunUI.style_box(
		Color(0.006, 0.014, 0.038), Color(OneGunUI.color("cyan"), 0.55),
		12, 1, 0, 0.0))
	column.add_child(frame)
	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "HatFitViewportContainer"
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport_container.gui_input.connect(_on_preview_gui_input)
	frame.add_child(_viewport_container)

	var views := HBoxContainer.new()
	views.alignment = BoxContainer.ALIGNMENT_CENTER
	views.add_theme_constant_override("separation", 7)
	column.add_child(views)
	for entry in [["FRONT", "front"], ["SIDE", "side"], ["TOP", "top"],
			["FULL BODY", "full"], ["RESET SPIN", "reset"]]:
		var button := OneGunButton.new()
		button.text = entry[0]
		button.variant = "navy"
		button.font_size = 12
		button.custom_minimum_size = Vector2(108, 42)
		button.pressed.connect(_set_camera_view.bind(entry[1]))
		views.add_child(button)
	var idle := CheckButton.new()
	idle.name = "IdlePreviewToggle"
	idle.text = "PLAY IDLE"
	idle.button_pressed = true
	idle.focus_mode = Control.FOCUS_ALL
	idle.toggled.connect(_toggle_idle)
	views.add_child(idle)

	var help := OneGunUI.make_label(
		"DRAG THE MODEL OR USE THE RIGHT STICK TO ROTATE  •  USE TOP + SIDE VIEWS BEFORE SAVING",
		11, "cyan", true)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)


func _build_controls_panel(parent: Control) -> void:
	var panel := OneGunCabinet.new()
	panel.name = "HatControlsCabinet"
	panel.variant = OneGunCabinet.Variant.SECTION
	panel.content_padding = 14
	panel.custom_minimum_size = Vector2(510, 560)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	parent.add_child(panel)
	var shell := VBoxContainer.new()
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_constant_override("separation", 8)
	panel.get_content().add_child(shell)
	shell.add_child(OneGunUI.make_heading("FIT CONTROLS", 22, "gold"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = 470
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 9)
	scroll.add_child(controls)

	_hat_picker = OneGunUI.make_dropdown()
	_hat_picker.name = "HatPicker"
	_hat_picker.custom_minimum_size.y = 44
	_hat_picker.item_selected.connect(_on_hat_selected)
	controls.add_child(_labeled_control("HAT", _hat_picker))
	_model_picker = OneGunUI.make_dropdown()
	_model_picker.name = "ModelPicker"
	_model_picker.custom_minimum_size.y = 44
	_model_picker.item_selected.connect(_on_model_selected)
	controls.add_child(_labeled_control("CHARACTER MODEL", _model_picker))

	controls.add_child(_section_label("SIZE & SEATING", "gold"))
	_add_spin_control(controls, "width", "TARGET HAT WIDTH", 0.25, 3.0, 0.01, " m")
	_add_spin_control(controls, "seat_depth", "SEAT DEPTH  (MORE NEGATIVE = LOWER)",
		-1.0, 1.0, 0.005, " m")

	controls.add_child(_section_label("LOCAL POSITION OFFSET", "cyan"))
	_add_spin_control(controls, "offset_x", "X  LEFT / RIGHT", -2.0, 2.0, 0.005, " m")
	_add_spin_control(controls, "offset_y", "Y  UP / DOWN FINE ADJUST", -2.0, 2.0, 0.005, " m")
	_add_spin_control(controls, "offset_z", "Z  FORWARD / BACK", -2.0, 2.0, 0.005, " m")

	controls.add_child(_section_label("LOCAL ROTATION", "purple"))
	_add_spin_control(controls, "rotation_x", "PITCH X", -180.0, 180.0, 0.5, "°")
	_add_spin_control(controls, "rotation_y", "YAW Y", -180.0, 180.0, 0.5, "°")
	_add_spin_control(controls, "rotation_z", "ROLL Z", -180.0, 180.0, 0.5, "°")

	var utility_row := HBoxContainer.new()
	utility_row.add_theme_constant_override("separation", 7)
	shell.add_child(utility_row)
	utility_row.add_child(_action_button("REVERT UNSAVED", "navy", _revert_selected))
	utility_row.add_child(_action_button("RESET TO BASE", "purple", _reset_selected_to_base))
	utility_row.add_child(_action_button("COPY TO NEXT MODEL", "blue", _copy_to_next_model))

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 7)
	shell.add_child(save_row)
	_save_selected_button = _action_button("SAVE THIS FIT", "gold", _save_selected)
	_save_selected_button.name = "SaveSelectedFitButton"
	_save_selected_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_save_selected_button)
	_save_all_button = _action_button("SAVE ALL DRAFTS", "green", _save_all_dirty)
	_save_all_button.name = "SaveAllFitsButton"
	_save_all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_save_all_button)

	_clear_override_button = OneGunConfirmButton.new()
	_clear_override_button.name = "ClearSavedOverrideButton"
	_clear_override_button.text = "REMOVE SAVED OVERRIDE"
	_clear_override_button.confirm_text = "CONFIRM — USE REGISTRY BASE"
	_clear_override_button.variant = "red"
	_clear_override_button.custom_minimum_size.y = 44
	_clear_override_button.confirmed.connect(_clear_saved_override)
	shell.add_child(_clear_override_button)
	var path_label := OneGunUI.make_label(
		"SAVES TO: models/cosmetics/hats/hat_fit_profiles.tres", 10, "muted", true)
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shell.add_child(path_label)


func _labeled_control(text: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.add_child(OneGunUI.make_label(text, 11, "cyan", true))
	box.add_child(control)
	return box


func _section_label(text: String, role: String) -> Label:
	var label := OneGunUI.make_heading(text, 15, role)
	label.add_theme_constant_override("outline_size", 1)
	return label


func _add_spin_control(parent: VBoxContainer, key: String, label_text: String,
		minimum: float, maximum: float, step: float, suffix: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := OneGunUI.make_label(label_text, 11, "text", true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var spin := SpinBox.new()
	spin.name = "%sSpin" % key.to_pascal_case()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.update_on_text_changed = true
	spin.suffix = suffix
	spin.custom_minimum_size = Vector2(150, 38)
	spin.value_changed.connect(func(_value: float) -> void: _on_fit_value_changed())
	row.add_child(spin)
	parent.add_child(row)
	_spin[key] = spin


func _action_button(text: String, variant: String, callback: Callable) -> OneGunButton:
	var button := OneGunButton.new()
	button.text = text
	button.variant = variant
	button.font_size = 11
	button.custom_minimum_size = Vector2(142, 44)
	button.pressed.connect(callback)
	return button


func _build_preview_world() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "HatFitViewport"
	_viewport.size = Vector2i(1024, 768)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.own_world_3d = true
	_viewport_container.add_child(_viewport)
	_world = Node3D.new()
	_world.name = "HatFitWorld"
	_viewport.add_child(_world)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.040, 0.085)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.46, 0.58, 0.90)
	environment.ambient_light_energy = 0.75
	environment_node.environment = environment
	_world.add_child(environment_node)
	_build_podium()

	_character_pivot = Node3D.new()
	_character_pivot.name = "FittingCharacterPivot"
	_world.add_child(_character_pivot)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -28, 0)
	key.light_color = Color(1.0, 0.84, 0.67)
	key.light_energy = 2.2
	key.shadow_enabled = true
	_world.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(2.2, 2.8, 2.5)
	fill.light_color = Color(0.18, 0.62, 1.0)
	fill.light_energy = 3.0
	fill.omni_range = 7.0
	_world.add_child(fill)
	_camera = Camera3D.new()
	_camera.fov = 38.0
	_world.add_child(_camera)
	_camera.current = true
	_set_camera_view("front")


func _build_podium() -> void:
	var podium := MeshInstance3D.new()
	podium.name = "FittingPodium"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.05
	mesh.bottom_radius = 1.18
	mesh.height = 0.20
	mesh.radial_segments = 48
	podium.mesh = mesh
	podium.position.y = -0.10
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.025, 0.055, 0.13)
	material.metallic = 0.72
	material.roughness = 0.24
	podium.material_override = material
	_world.add_child(podium)


func _populate_pickers() -> void:
	_hat_picker.clear()
	for hat_id in _hat_ids:
		_hat_picker.add_item(HatRegistry.display_name(hat_id).to_upper())
		_hat_picker.set_item_metadata(_hat_picker.item_count - 1, hat_id)
	_model_picker.clear()
	for model_id in SkinRegistry.MODEL_IDS:
		_model_picker.add_item(SkinRegistry.model_display_name(model_id).to_upper())
		_model_picker.set_item_metadata(_model_picker.item_count - 1, model_id)
	_model_picker.select(maxi(SkinRegistry.MODEL_IDS.find(_current_model), 0))


func _on_hat_selected(index: int) -> void:
	if index < 0 or index >= _hat_picker.item_count:
		return
	_current_hat = str(_hat_picker.get_item_metadata(index))
	_select_current_fit()


func _on_model_selected(index: int) -> void:
	if index < 0 or index >= _model_picker.item_count:
		return
	_current_model = str(_model_picker.get_item_metadata(index))
	_replace_visual()
	_select_current_fit()


func _select_current_fit() -> void:
	if _current_hat == "":
		return
	if _visual == null:
		_replace_visual()
	var fit := _current_draft()
	_write_controls(fit)
	_queue_preview_refresh()
	_refresh_labels()
	_update_save_availability()


func _replace_visual() -> void:
	var scene := SkinRegistry.load_visual_scene(_current_model)
	if scene == null:
		_set_status("MODEL SCENE IS MISSING", true)
		return
	if _visual != null and is_instance_valid(_visual):
		_visual.free()
	_visual = scene.instantiate() as Node3D
	if _visual == null:
		_set_status("MODEL COULD NOT BE INSTANTIATED", true)
		return
	_visual.name = "FittingCharacter"
	_visual.set("build_animation_library", false)
	_character_pivot.add_child(_visual)
	_visual.call("set_skin", "blue")
	_idle_player = _visual.call("ensure_animations", ["idle"]) as AnimationPlayer
	if _idle_player != null and _idle_player.has_animation("idle"):
		_idle_player.play("idle", 0.0)
		_idle_player.advance(0.12)
		if not _idle_enabled:
			_idle_player.pause()
	_manual_hat = null


func _current_key() -> String:
	return "%s|%s" % [_current_hat, _current_model]


func _split_key(value: String) -> PackedStringArray:
	return value.split("|", false, 1)


func _current_draft() -> Dictionary:
	var key := _current_key()
	if _drafts.has(key):
		return (_drafts[key] as Dictionary).duplicate(true)
	return HatRegistry.resolved_fit(_current_hat, _current_model)


func _write_controls(fit: Dictionary) -> void:
	_loading_controls = true
	(_spin["width"] as SpinBox).value = float(fit.get("width", 1.0))
	(_spin["seat_depth"] as SpinBox).value = float(fit.get("seat_depth", -0.06))
	var offset: Vector3 = fit.get("offset", Vector3.ZERO)
	(_spin["offset_x"] as SpinBox).value = offset.x
	(_spin["offset_y"] as SpinBox).value = offset.y
	(_spin["offset_z"] as SpinBox).value = offset.z
	var rotation: Vector3 = fit.get("rotation_degrees", Vector3.ZERO)
	(_spin["rotation_x"] as SpinBox).value = rotation.x
	(_spin["rotation_y"] as SpinBox).value = rotation.y
	(_spin["rotation_z"] as SpinBox).value = rotation.z
	_loading_controls = false


func _read_controls() -> Dictionary:
	return FitProfileSchema.normalize_fit({
		"width": (_spin["width"] as SpinBox).value,
		"seat_depth": (_spin["seat_depth"] as SpinBox).value,
		"offset": Vector3(
			(_spin["offset_x"] as SpinBox).value,
			(_spin["offset_y"] as SpinBox).value,
			(_spin["offset_z"] as SpinBox).value),
		"rotation_degrees": Vector3(
			(_spin["rotation_x"] as SpinBox).value,
			(_spin["rotation_y"] as SpinBox).value,
			(_spin["rotation_z"] as SpinBox).value),
	})


func _on_fit_value_changed() -> void:
	if _loading_controls or _current_hat == "":
		return
	var key := _current_key()
	var fit := _read_controls()
	_drafts[key] = fit
	var saved := HatRegistry.resolved_fit(_current_hat, _current_model)
	if _fits_equal(fit, saved):
		_dirty_keys.erase(key)
	else:
		_dirty_keys[key] = true
	_queue_preview_refresh()
	_refresh_labels()
	_update_save_availability()


func _queue_preview_refresh() -> void:
	if _preview_refresh_pending:
		return
	_preview_refresh_pending = true
	_refresh_preview_hat.call_deferred()


func _refresh_preview_hat() -> void:
	_preview_refresh_pending = false
	if _visual == null or _current_hat == "":
		return
	var socket := _visual.call("get_headwear_socket") as Marker3D
	if socket == null:
		_set_status("THE SELECTED MODEL HAS NO HEADWEAR SOCKET", true)
		return
	if _manual_hat != null and is_instance_valid(_manual_hat):
		_manual_hat.free()
	_manual_hat = HatRegistry.instantiate_hat(
		_current_hat, _current_model, _current_draft())
	if _manual_hat == null:
		_set_status("HAT ASSET COULD NOT BE LOADED", true)
		return
	socket.add_child(_manual_hat)


func _refresh_labels() -> void:
	if _selection_label != null:
		_selection_label.text = "%s  •  %s" % [
			HatRegistry.display_name(_current_hat).to_upper(),
			SkinRegistry.model_display_name(_current_model).to_upper()]
	var key := _current_key()
	if _dirty_keys.has(key):
		_set_status("UNSAVED DRAFT  •  %d TOTAL UNSAVED FIT(S)" % _dirty_keys.size(), true)
	elif _profile.has_fit(_current_hat, _current_model):
		_set_status("SAVED OVERRIDE ACTIVE  •  %d TOTAL UNSAVED FIT(S)" % _dirty_keys.size(), false)
	else:
		var inherited_from := ""
		var chain := SkinRegistry.headwear_fit_model_chain(_current_model)
		for index in range(1, chain.size()):
			if _profile.has_fit(_current_hat, chain[index]):
				inherited_from = chain[index]
				break
		if inherited_from != "":
			_set_status("INHERITING SAVED %s FIT  •  SAVE A %s DRAFT TO CUSTOMIZE" % [
				SkinRegistry.model_display_name(inherited_from).to_upper(),
				SkinRegistry.model_display_name(_current_model).to_upper()], false)
		else:
			_set_status("USING REGISTRY BASE  •  %d TOTAL UNSAVED FIT(S)" % _dirty_keys.size(), false)


func _update_save_availability() -> void:
	var can_write := OS.has_feature("editor")
	if _save_selected_button != null:
		_save_selected_button.disabled = not can_write or not _dirty_keys.has(_current_key())
		_save_selected_button.tooltip_text = "Run this scene from the Godot editor to save." \
			if not can_write else "Save only this hat/model fit."
	if _save_all_button != null:
		_save_all_button.disabled = not can_write or _dirty_keys.is_empty()
	if _clear_override_button != null:
		_clear_override_button.disabled = not can_write \
			or not _profile.has_fit(_current_hat, _current_model)


func _save_selected() -> void:
	_save_keys([_current_key()])


func _save_all_dirty() -> void:
	_save_keys(_dirty_keys.keys())


func _save_keys(keys: Array) -> void:
	if not OS.has_feature("editor"):
		_set_status("SAVE BLOCKED — RUN THIS TOOL FROM THE GODOT EDITOR", true)
		return
	if keys.is_empty():
		_set_status("NO UNSAVED FITS TO SAVE", false)
		return
	var snapshot: Dictionary = _profile.fits.duplicate(true)
	var saved_keys: Array[String] = []
	for key_value in keys:
		var key := str(key_value)
		if not _drafts.has(key):
			continue
		var parts := _split_key(key)
		if parts.size() != 2 or not _profile.set_fit(
				parts[0], parts[1], _drafts[key]):
			_profile.fits = snapshot
			_set_status("SAVE ABORTED — INVALID FIT DATA", true)
			return
		saved_keys.append(key)
	var error := ResourceSaver.save(_profile, PROFILE_PATH)
	if error != OK:
		_profile.fits = snapshot
		_profile.emit_changed()
		_set_status("SAVE FAILED: %s" % error_string(error).to_upper(), true)
		return
	for key in saved_keys:
		_dirty_keys.erase(key)
		_drafts.erase(key)
	_set_status("SAVED %d FIT(S) SAFELY" % saved_keys.size(), false)
	_write_controls(_current_draft())
	_queue_preview_refresh()
	_update_save_availability()


func _revert_selected() -> void:
	var key := _current_key()
	_drafts.erase(key)
	_dirty_keys.erase(key)
	_write_controls(_current_draft())
	_queue_preview_refresh()
	_refresh_labels()
	_update_save_availability()


func _reset_selected_to_base() -> void:
	var fit := HatRegistry.default_fit(_current_hat, _current_model)
	_write_controls(fit)
	_on_fit_value_changed()
	_set_status("REGISTRY BASE LOADED AS AN UNSAVED DRAFT", true)


func _copy_to_next_model() -> void:
	if SkinRegistry.MODEL_IDS.size() < 2:
		_set_status("NO OTHER REGISTERED MODEL IS AVAILABLE", true)
		return
	var current_index := maxi(SkinRegistry.MODEL_IDS.find(_current_model), 0)
	var other := SkinRegistry.MODEL_IDS[(current_index + 1) % SkinRegistry.MODEL_IDS.size()]
	var target_key := "%s|%s" % [_current_hat, other]
	_drafts[target_key] = _read_controls()
	var saved := HatRegistry.resolved_fit(_current_hat, other)
	# A copied fit is deliberately materialized as an exact per-model override,
	# even when it currently matches an inherited fit.
	if _profile.has_fit(_current_hat, other) \
			and _fits_equal(_drafts[target_key], saved):
		_dirty_keys.erase(target_key)
	else:
		_dirty_keys[target_key] = true
	_current_model = other
	var picker_index := SkinRegistry.MODEL_IDS.find(other)
	if picker_index >= 0:
		_model_picker.select(picker_index)
	_replace_visual()
	_select_current_fit()
	_set_status("COPIED AS AN UNSAVED %s DRAFT — REVIEW IT BEFORE SAVING" %
		SkinRegistry.model_display_name(other).to_upper(), true)
	_update_save_availability()


func _clear_saved_override() -> void:
	if not OS.has_feature("editor") or not _profile.has_fit(
			_current_hat, _current_model):
		return
	var snapshot: Dictionary = _profile.fits.duplicate(true)
	if not _profile.clear_fit(_current_hat, _current_model):
		return
	var error := ResourceSaver.save(_profile, PROFILE_PATH)
	if error != OK:
		_profile.fits = snapshot
		_profile.emit_changed()
		_set_status("COULD NOT REMOVE OVERRIDE: %s" % error_string(error).to_upper(), true)
		return
	var key := _current_key()
	_drafts.erase(key)
	_dirty_keys.erase(key)
	_write_controls(_current_draft())
	_queue_preview_refresh()
	_set_status("SAVED OVERRIDE REMOVED — REGISTRY BASE RESTORED", false)
	_update_save_availability()


func _toggle_idle(enabled: bool) -> void:
	_idle_enabled = enabled
	if _idle_player == null or not _idle_player.has_animation("idle"):
		return
	if enabled:
		_idle_player.play("idle", 0.0)
	else:
		_idle_player.pause()


func _set_camera_view(view: String) -> void:
	if _camera == null:
		return
	match view:
		"side":
			_camera.look_at_from_position(
				Vector3(5.25, 2.25, 0.0), Vector3(0.0, 2.12, 0.0), Vector3.UP)
		"top":
			_camera.look_at_from_position(
				Vector3(0.0, 5.80, 0.08), Vector3(0.0, 1.90, 0.0),
				Vector3(0.0, 0.0, -1.0))
		"full":
			_camera.look_at_from_position(
				Vector3(0.0, 1.35, 6.60), Vector3(0.0, 1.20, 0.0), Vector3.UP)
		"reset":
			if _character_pivot != null:
				_character_pivot.rotation = Vector3.ZERO
			_camera.look_at_from_position(
				Vector3(0.0, 2.25, 5.40), Vector3(0.0, 2.12, 0.0), Vector3.UP)
		_:
			_camera.look_at_from_position(
				Vector3(0.0, 2.25, 5.40), Vector3(0.0, 2.12, 0.0), Vector3.UP)


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_viewport_container.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_character_pivot.rotate_y(event.relative.x * 0.012)
		_viewport_container.accept_event()


func _fits_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() and b.is_empty()
	var a_offset: Vector3 = a.get("offset", Vector3.ZERO)
	var b_offset: Vector3 = b.get("offset", Vector3.ZERO)
	var a_rotation: Vector3 = a.get("rotation_degrees", Vector3.ZERO)
	var b_rotation: Vector3 = b.get("rotation_degrees", Vector3.ZERO)
	return is_equal_approx(float(a.get("width", 0.0)), float(b.get("width", 0.0))) \
		and is_equal_approx(float(a.get("seat_depth", 0.0)), float(b.get("seat_depth", 0.0))) \
		and a_offset.is_equal_approx(b_offset) \
		and a_rotation.is_equal_approx(b_rotation)


func _set_status(message: String, error: bool) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.add_theme_color_override(
		"font_color", OneGunUI.color("red" if error else "green"))
