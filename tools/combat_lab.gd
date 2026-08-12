extends Node3D

const PLAYER_SCENE := preload("res://player.tscn")
const BOT_SCENE := preload("res://DummyModel.tscn")
const GUN_SCENE := preload("res://gun.tscn")
const MELEE_SCENE := preload("res://melee_weapon.tscn")
const POWERUP_SCENE := preload("res://powerup.tscn")

var player = null
var spawn_cursor := Vector3(-8.0, 0.6, 10.0)
var _status: Label = null
var _player2 = null
var _player2_container: SubViewportContainer = null
var _player2_view_camera: Camera3D = null
var _player2_layer: CanvasLayer = null
var _menu_open := true
var _controls_panel: PanelContainer = null

func _ready() -> void:
	if not OS.is_debug_build() and not Engine.is_editor_hint():
		get_tree().change_scene_to_file("res://main_menu.tscn")
		return
	GameConfig.split_screen_enabled = false
	_build_environment()
	_spawn_player_and_targets()
	_spawn_test_racks()
	_build_player_hud()
	_build_controls()
	_set_menu_open(true)

func _process(_delta: float) -> void:
	if _player2 != null and is_instance_valid(_player2) and _player2_view_camera != null:
		_player2_view_camera.global_transform = _player2.get_camera().global_transform
		_player2_view_camera.fov = _player2.get_camera().fov

func _unhandled_input(event: InputEvent) -> void:
	var toggle_requested := event.is_action_pressed("ui_cancel")
	if event is InputEventKey and event.pressed and not event.echo:
		toggle_requested = toggle_requested or event.keycode == KEY_F1
	if not toggle_requested:
		return
	_set_menu_open(not _menu_open)
	get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _set_menu_open(value: bool) -> void:
	_menu_open = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _menu_open else Input.MOUSE_MODE_CAPTURED
	if player != null and is_instance_valid(player):
		player.set_process_input(not _menu_open)
		player.set_physics_process(not _menu_open)
	if _player2 != null and is_instance_valid(_player2):
		_player2.set_process_input(not _menu_open)
		_player2.set_physics_process(not _menu_open)
	if _status != null:
		_status.text = ("TUNING MODE - cursor released. Press F1 or Escape to enter the range."
			if _menu_open else
			"LIVE RANGE - press F1 or Escape to release the cursor and tune settings.")

func _build_environment() -> void:
	_make_box("Floor", Vector3(110.0, 0.5, 28.0), Vector3(45.0, -0.25, 0.0), Color(0.12, 0.15, 0.2))
	for distance in [10, 25, 50, 100]:
		_make_box("Range%d" % distance, Vector3(0.12, 0.03, 28.0),
			Vector3(float(distance), 0.02, 0.0), Color(0.15, 0.8, 1.0))
		var label := Label3D.new()
		label.text = "%d UNITS" % distance
		label.position = Vector3(float(distance), 0.2, -10.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 42
		label.modulate = Color(0.2, 0.9, 1.0)
		add_child(label)
	_make_box("CoverWall", Vector3(0.6, 4.0, 8.0), Vector3(18.0, 2.0, 6.0), Color(0.35, 0.38, 0.45))
	_make_box("DoorLeft", Vector3(0.6, 4.0, 3.0), Vector3(35.0, 2.0, 5.5), Color(0.4, 0.3, 0.2))
	_make_box("DoorRight", Vector3(0.6, 4.0, 3.0), Vector3(35.0, 2.0, -5.5), Color(0.4, 0.3, 0.2))
	var ramp := _make_box("Ramp", Vector3(9.0, 0.5, 5.0), Vector3(25.0, 1.2, -8.0), Color(0.25, 0.28, 0.35))
	ramp.rotation.z = deg_to_rad(-14.0)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.shadow_enabled = true
	add_child(light)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.045, 0.075)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.78)
	env.ambient_light_energy = 0.7
	environment.environment = env
	add_child(environment)

func _make_box(node_name: String, size: Vector3, at: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	add_child(body)
	return body

func _spawn_player_and_targets() -> void:
	player = PLAYER_SCENE.instantiate()
	player.name = "CombatLabPlayer"
	add_child(player)
	player.global_position = Vector3.ZERO
	for config in [
		{"name": "Stationary Target", "position": Vector3(10, 0, 0), "difficulty": "easy", "stationary": true},
		{"name": "Moving Target", "position": Vector3(25, 0, 3), "difficulty": "medium"},
		{"name": "Dashing Target", "position": Vector3(50, 0, -3), "difficulty": "expert"},
	]:
		var bot = BOT_SCENE.instantiate()
		bot.name = config["name"]
		bot.ai_difficulty = config["difficulty"]
		add_child(bot)
		bot.global_position = config["position"]
		if bool(config.get("stationary", false)):
			bot.call_deferred("set_physics_process", false)

func _spawn_test_racks() -> void:
	var gun = GUN_SCENE.instantiate()
	add_child(gun)
	gun.global_position = Vector3(3.0, 0.7, -6.0)
	gun.spawn_position = gun.global_position
	var melee = MELEE_SCENE.instantiate()
	add_child(melee)
	melee.global_position = Vector3(6.0, 0.7, -6.0)
	melee.spawn_position = melee.global_position
	var power_types := ["extra_dash", "sticky_hands", "speed_surge", "silent_steps",
		"vampire_touch", "extra_life", "reach"]
	for i in power_types.size():
		var powerup = POWERUP_SCENE.instantiate()
		powerup.fixed_power_type = power_types[i]
		powerup.power_type = power_types[i]
		add_child(powerup)
		powerup.global_position = Vector3(3.0 + i * 2.2, 0.8, 9.0)
		powerup.spawn_position = powerup.global_position
	for item_type in GameConfig.ITEM_SCENES:
		var packed = load(GameConfig.ITEM_SCENES[item_type])
		if packed == null:
			continue
		var item = packed.instantiate()
		add_child(item)
		item.global_position = spawn_cursor
		item.spawn_position = spawn_cursor
		spawn_cursor.x += 2.4

func _build_player_hud() -> void:
	_build_hud_for(player, self, "CombatHUD", 10)

func _build_hud_for(target_player, parent: Node, hud_name: String, layer_index: int) -> void:
	var layer := CanvasLayer.new()
	layer.name = hud_name
	layer.layer = layer_index
	parent.add_child(layer)

	var crosshair := Control.new()
	crosshair.name = "Crosshair"
	crosshair.set_script(load("res://crosshair.gd"))
	layer.add_child(crosshair)
	crosshair.force_visible_without_weapon = true
	crosshair.set_player(target_player)

	var stamina := ProgressBar.new()
	stamina.name = "StaminaBar"
	stamina.min_value = 0.0
	stamina.max_value = 100.0
	stamina.show_percentage = false
	stamina.set_script(load("res://stamina_bar.gd"))
	layer.add_child(stamina)
	stamina.set_player(target_player)

	var dash_display := HBoxContainer.new()
	dash_display.name = "DashCharges"
	dash_display.set_script(load("res://dash_charges.gd"))
	layer.add_child(dash_display)
	dash_display.set_player(target_player)

	var inventory := HBoxContainer.new()
	inventory.name = "InventorySlots"
	inventory.add_child(_make_inventory_slot("WeaponSlot"))
	inventory.add_child(_make_inventory_slot("ItemSlot"))
	inventory.add_child(_make_inventory_slot("ItemSlot2"))
	inventory.set_script(load("res://inventory_slots.gd"))
	layer.add_child(inventory)
	inventory.set_player(target_player)

func _make_inventory_slot(slot_name: String) -> Control:
	var slot := Control.new()
	slot.name = slot_name
	slot.custom_minimum_size = Vector2(80, 80)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var background := ColorRect.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(background)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(icon)
	var label := Label.new()
	label.name = "NameLabel"
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot.add_child(label)
	var hold_bar := ProgressBar.new()
	hold_bar.name = "HoldBar"
	hold_bar.anchor_right = 1.0
	hold_bar.offset_bottom = 6.0
	hold_bar.max_value = 1.0
	hold_bar.show_percentage = false
	hold_bar.visible = false
	slot.add_child(hold_bar)
	return slot

func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CombatLabControls"
	layer.layer = 20
	add_child(layer)
	var panel := PanelContainer.new()
	_controls_panel = panel
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -396.0
	panel.offset_right = -16.0
	panel.offset_top = 16.0
	panel.custom_minimum_size = Vector2(360, 0)
	panel.add_theme_stylebox_override("panel", ThemeManager.panel(
		Color(0.035, 0.045, 0.08, 0.94), ThemeManager.ACCENT_GOLD, 12, 2))
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var title := Label.new()
	title.text = "COMBAT LAB  •  TEMPORARY TUNING"
	title.add_theme_font_size_override("font_size", 20)
	ThemeManager.embolden(title)
	column.add_child(title)
	_status = Label.new()
	_status.text = "10 / 25 / 50 / 100 unit lanes • stationary / moving / dashing targets"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	var mouse_toggle := Button.new()
	mouse_toggle.text = "TOGGLE TUNING / LIVE CONTROLS  [F1]"
	mouse_toggle.pressed.connect(func(): _set_menu_open(not _menu_open))
	column.add_child(mouse_toggle)
	_add_tuning_slider(column, "Bullet Speed", 50.0, 400.0, 10.0, 200.0,
		_set_bullet_speed)
	_add_tuning_slider(column, "Reload Time", 0.2, 5.0, 0.1, 2.0,
		_set_reload_time)
	_add_tuning_slider(column, "Dash Recharge", 0.25, 8.0, 0.25, 3.0,
		func(value): player.dash_recharge_time = value)
	_add_tuning_slider(column, "Loose Gun Return", 1.0, 12.0, 0.5, 5.0,
		_set_gun_return_time)
	_add_tuning_slider(column, "Powerup Duration", 1.0, 30.0, 1.0, 5.0,
		_set_powerup_duration)
	var effect_picker := OptionButton.new()
	for effect in ["normal", "knockback", "stagger", "slow"]:
		effect_picker.add_item(effect.capitalize())
	effect_picker.item_selected.connect(func(index):
		for melee in get_tree().get_nodes_in_group("melee"):
			melee.effect_category = ["normal", "knockback", "stagger", "slow"][index])
	column.add_child(effect_picker)
	var protection_row := HBoxContainer.new()
	for config in [["GIVE EXTRA LIFE", "extra_life"], ["GIVE STICKY HANDS", "sticky_hands"]]:
		var give := Button.new()
		give.text = config[0]
		give.pressed.connect(func(): player.apply_powerup(config[1], 5.0))
		protection_row.add_child(give)
	var clear := Button.new()
	clear.text = "CLEAR"
	clear.pressed.connect(func(): player.clear_all_powerups())
	protection_row.add_child(clear)
	column.add_child(protection_row)
	var team_toggle := CheckButton.new()
	team_toggle.text = "Teams Enabled"
	team_toggle.toggled.connect(func(value): GameConfig.teams_enabled = value)
	column.add_child(team_toggle)
	var friendly_toggle := CheckButton.new()
	friendly_toggle.text = "Friendly Fire"
	friendly_toggle.toggled.connect(func(value): GameConfig.friendly_fire_enabled = value)
	column.add_child(friendly_toggle)
	var lethal_toggle := CheckButton.new()
	lethal_toggle.text = "Melee Can Eliminate"
	lethal_toggle.toggled.connect(func(value):
		GameConfig.melee_eliminates_anyone = value
		GameConfig.melee_eliminates_gunholder = value)
	column.add_child(lethal_toggle)
	var split := Button.new()
	split.text = "TOGGLE SPLITSCREEN P2"
	split.pressed.connect(_toggle_player_two)
	column.add_child(split)
	var reset := Button.new()
	reset.text = "INSTANT RESET"
	reset.pressed.connect(func(): get_tree().reload_current_scene())
	column.add_child(reset)
	var exit := Button.new()
	exit.text = "RETURN TO MAIN MENU"
	exit.pressed.connect(func(): get_tree().change_scene_to_file("res://main_menu.tscn"))
	column.add_child(exit)

func _add_tuning_slider(parent: VBoxContainer, label_text: String, minimum: float,
		maximum: float, step: float, initial: float, changed: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 135.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(changed)
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = str(initial)
	value_label.custom_minimum_size.x = 55.0
	row.add_child(value_label)
	slider.value_changed.connect(func(value): value_label.text = "%.2f" % value)
	parent.add_child(row)

func _set_bullet_speed(value: float) -> void:
	for gun in get_tree().get_nodes_in_group("gun"):
		gun.projectile_speed = value

func _set_reload_time(value: float) -> void:
	for gun in get_tree().get_nodes_in_group("gun"):
		gun.reload_time = value
		gun.get_node("ReloadTimer").wait_time = value

func _set_gun_return_time(value: float) -> void:
	for gun in get_tree().get_nodes_in_group("gun"):
		gun.loose_return_time = value

func _set_powerup_duration(value: float) -> void:
	for powerup in get_tree().get_nodes_in_group("powerup"):
		powerup.effect_duration = value

func _toggle_player_two() -> void:
	if _player2 != null and is_instance_valid(_player2):
		_player2.queue_free()
		_player2 = null
		if _player2_container != null:
			_player2_container.queue_free()
			_player2_container = null
		if _player2_layer != null:
			_player2_layer.queue_free()
			_player2_layer = null
		GameConfig.split_screen_enabled = false
		return
	GameConfig.split_screen_enabled = true
	_player2 = PLAYER_SCENE.instantiate()
	_player2.name = "CombatLabPlayer2"
	_player2.is_player2 = true
	_player2.input_prefix = "p2"
	_player2.use_gamepad_look = true
	add_child(_player2)
	_player2.global_position = Vector3(0.0, 0.0, 3.0)
	_player2.set_process_input(not _menu_open)
	_player2.set_physics_process(not _menu_open)
	_player2.get_camera().current = false
	_player2_container = SubViewportContainer.new()
	_player2_container.anchor_left = 0.5
	_player2_container.anchor_right = 1.0
	_player2_container.anchor_top = 0.0
	_player2_container.anchor_bottom = 1.0
	_player2_container.stretch = true
	var viewport := SubViewport.new()
	viewport.world_3d = get_world_3d()
	viewport.size = Vector2i(640, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_player2_container.add_child(viewport)
	_player2_view_camera = Camera3D.new()
	viewport.add_child(_player2_view_camera)
	_player2_view_camera.current = true
	_build_hud_for(_player2, viewport, "Player2HUD", 10)
	_player2_layer = CanvasLayer.new()
	_player2_layer.layer = 5
	_player2_layer.add_child(_player2_container)
	add_child(_player2_layer)
