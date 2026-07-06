extends CharacterBody3D

@export var input_prefix := "p1"
@export var is_player2 := false
@export var team_id := -1
@export var use_gamepad_look := false
@export var mouse_look_sensitivity := 1.0
@export var look_sensitivity := 6.0
@export var ads_look_sensitivity_multiplier := 0.5

var gamepad_response_curve_exponent := 2.0
var gamepad_sprint_is_toggle := true
var mouse_keyboard_sprint_is_toggle := false
var max_dash_charges := 2
var invert_look_y := false

const SPEED = 10.0
const SPRINT_SPEED = 18.0
const JUMP_VELOCITY = 4.5
const MODEL_FACING_OFFSET = PI
const MAX_STAMINA = 100.0
const STAMINA_DRAIN_RATE = 25.0
const STAMINA_REGEN_RATE = 20.0
const STAMINA_REGEN_DELAY = 1.0
const DASH_SPEED = 30.0
const DASH_DURATION = 0.2
const DASH_RECHARGE_TIME = 3.0
const MAX_DASH_CHARGES_HARD_CEILING = 6
const KNOCKBACK_DURATION = 0.2
const ADS_TRANSITION_TIME = .2
const ADS_SPRING_LENGTH = 0.3
const ADS_FOV_MULTIPLIER = 0.9
const MOUSE_LOOK_BASE = 0.005

var holding_gun = false
var held_melee_weapon = null
var held_item = null
var nearby_interactables = []
var active_slot = "none"

var stamina = MAX_STAMINA
var stamina_regen_timer = 0.0
var is_sprinting = false

var dash_charges = 0
var dash_recharge_timer = 0.0
var is_dashing = false
var dash_timer = 0.0
var dash_direction = Vector3.ZERO
var dash_bonus_timer = 0.0

var active_powerup_order = []

var knockback_velocity = Vector3.ZERO
var knockback_timer = 0.0
var stagger_timer = 0.0
var bullet_immune_timer = 0.0
var melee_disarm_shields = 0

var slow_timer = 0.0
var slow_multiplier_value = 1.0

var is_eliminated = false
var _spectator: Node = null

const ANIM_SOURCE_GLB = "res://models/playerAnimations/Dance.glb"

const ANIM_IDLE            = "idle"
const ANIM_IDLE_PISTOL     = "idle_pistol"
const ANIM_IDLE_JUMPING    = "idle_jumping"
const ANIM_WALK            = "walk"
const ANIM_WALK_PISTOL     = "walk_pistol"
const ANIM_RUN             = "run"
const ANIM_RUN_PISTOL      = "run_pistol"
const ANIM_RUN_JUMPING     = "run_jumping"
const ANIM_SPRINT_ROLL     = "sprint_roll"
const ANIM_DEATH           = "death"
const ANIM_DANCE           = "dance"

const ANIM_INDICES = {
	ANIM_IDLE:         0,
	ANIM_IDLE_JUMPING: 1,
	ANIM_IDLE_PISTOL:  2,
	ANIM_WALK:         3,
	ANIM_RUN_JUMPING:  4,
	ANIM_WALK_PISTOL:  5,
	ANIM_RUN:          6,
	ANIM_RUN_PISTOL:   7,
	ANIM_SPRINT_ROLL:  8,
	ANIM_DEATH:        9,
	ANIM_DANCE:        10,
}

var model_anim_player: AnimationPlayer = null
var _current_anim: String = ""
var _anim_rotation_offset: float = 0.0

var ads_blend = 0.0
var ads_blend_target = 0.0
var ads_tween: Tween = null
var default_spring_length = 4.0
var default_spring_position = Vector3.ZERO
var default_camera_fov = 75.0

func _ready():
	if not use_gamepad_look:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_player2 and not GameConfig.split_screen_enabled:
		remove_from_group("player")
		visible = false
		set_physics_process(false)
	model_anim_player = $CharacterModel.find_child("AnimationPlayer", true, false)
	if model_anim_player != null:
		_merge_animations()
	default_spring_length = $AimPivot/SpringArm3D.spring_length
	default_spring_position = $AimPivot/SpringArm3D.position
	default_camera_fov = $AimPivot/SpringArm3D/Camera3D.fov
	_apply_match_settings()
	max_dash_charges = clamp(max_dash_charges, 0, MAX_DASH_CHARGES_HARD_CEILING)
	dash_charges = max_dash_charges
	_apply_player_prefs()
	gamepad_response_curve_exponent = max(gamepad_response_curve_exponent, 0.1)
	ads_look_sensitivity_multiplier = clamp(ads_look_sensitivity_multiplier, 0.05, 1.0)
	if not is_player2 and not PlayerPrefs.setting_changed.is_connected(_on_player_pref_changed):
		PlayerPrefs.setting_changed.connect(_on_player_pref_changed)

func _on_player_pref_changed(_key: String, _value):
	_apply_player_prefs()

func _apply_match_settings():
	max_dash_charges = GameConfig.max_dash_charges

func _apply_player_prefs():
	if is_player2:
		return
	mouse_look_sensitivity = PlayerPrefs.get_setting("mouse_sensitivity")
	look_sensitivity = PlayerPrefs.get_setting("gamepad_sensitivity")
	ads_look_sensitivity_multiplier = PlayerPrefs.get_setting("ads_sensitivity_multiplier")
	gamepad_response_curve_exponent = PlayerPrefs.get_setting("gamepad_response_curve_exponent")
	gamepad_sprint_is_toggle = PlayerPrefs.get_setting("gamepad_sprint_is_toggle")
	mouse_keyboard_sprint_is_toggle = PlayerPrefs.get_setting("mouse_keyboard_sprint_is_toggle")
	invert_look_y = PlayerPrefs.get_setting("invert_look_y")
	default_camera_fov = PlayerPrefs.get_setting("field_of_view")
	$AimPivot/SpringArm3D/Camera3D.fov = default_camera_fov

func _input(event):
	if use_gamepad_look:
		return
	if event is InputEventMouseMotion:
		var sens = MOUSE_LOOK_BASE * mouse_look_sensitivity
		if ads_blend > 0.0:
			sens *= lerp(1.0, ads_look_sensitivity_multiplier, ads_blend)
		var y_sign = -1.0 if invert_look_y else 1.0
		$AimPivot.rotate_y(-event.relative.x * sens)
		$AimPivot/SpringArm3D.rotate_x(-event.relative.y * sens * y_sign)
		$AimPivot/SpringArm3D.rotation.x = clamp($AimPivot/SpringArm3D.rotation.x, -1.2, 1.2)

func _get_movement_input_dir():
	return Input.get_vector(input_prefix + "_move_left", input_prefix + "_move_right", input_prefix + "_move_forward", input_prefix + "_move_back")

func _physics_process(delta):
	if bullet_immune_timer > 0.0:
		bullet_immune_timer -= delta

	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_multiplier_value = 1.0

	if is_eliminated:
		if not is_on_floor():
			velocity.y -= 9.8 * delta
		else:
			velocity.y = 0
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	if use_gamepad_look:
		_process_gamepad_look(delta)

	_update_aiming(delta)
	_update_active_slot_and_visuals()

	if Input.is_action_just_pressed(input_prefix + "_cycle_left"):
		_try_cycle_slot(-1)
	if Input.is_action_just_pressed(input_prefix + "_cycle_right"):
		_try_cycle_slot(1)

	if not is_on_floor():
		velocity.y -= 9.8 * delta

	if stagger_timer > 0.0:
		stagger_timer -= delta
		velocity.x = 0
		velocity.z = 0
		_stop_movement_animation()
		move_and_slide()
		_update_stamina(delta)
		_update_dash_recharge(delta)
		_update_facing()
		return

	if knockback_timer > 0.0:
		knockback_timer -= delta
		velocity.x = knockback_velocity.x
		velocity.z = knockback_velocity.z
		_stop_movement_animation()
		move_and_slide()
		_update_stamina(delta)
		_update_dash_recharge(delta)
		_update_facing()
		return

	if Input.is_action_just_pressed(input_prefix + "_jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if Input.is_action_just_pressed(input_prefix + "_interact"):
		_try_interact()

	if Input.is_action_just_pressed(input_prefix + "_fire"):
		_try_primary_action()

	if Input.is_action_just_pressed(input_prefix + "_throw"):
		if active_slot == "weapon" and held_melee_weapon != null:
			held_melee_weapon.try_throw()

	if Input.is_action_just_pressed(input_prefix + "_dash") and dash_charges > 0 and not is_dashing:
		_start_dash()

	var sprint_is_toggle = gamepad_sprint_is_toggle if use_gamepad_look else mouse_keyboard_sprint_is_toggle
	if sprint_is_toggle:
		if Input.is_action_just_pressed(input_prefix + "_sprint"):
			_toggle_sprint()
	else:
		is_sprinting = Input.is_action_pressed(input_prefix + "_sprint") and stamina > 0.0

	if is_dashing:
		dash_timer -= delta
		velocity.x = dash_direction.x * DASH_SPEED
		velocity.z = dash_direction.z * DASH_SPEED
		if dash_timer <= 0.0:
			is_dashing = false
			_current_anim = ""
	else:
		var current_speed = SPRINT_SPEED if is_sprinting else SPEED
		current_speed *= slow_multiplier_value

		var input_dir = _get_movement_input_dir()
		var direction = ($AimPivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		if direction:
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
		else:
			velocity.x = move_toward(velocity.x, 0, current_speed)
			velocity.z = move_toward(velocity.z, 0, current_speed)

		_update_animation(input_dir)

	move_and_slide()
	_update_stamina(delta)
	_update_dash_recharge(delta)
	_update_facing()

func _toggle_sprint():
	if is_sprinting:
		is_sprinting = false
	elif stamina > 0.0:
		is_sprinting = true

func _update_active_slot_and_visuals():
	var has_weapon = holding_gun or held_melee_weapon != null
	var has_item = held_item != null

	if active_slot == "weapon" and not has_weapon:
		active_slot = "item" if has_item else "none"
	elif active_slot == "item" and not has_item:
		active_slot = "weapon" if has_weapon else "none"
	elif active_slot == "none":
		if has_weapon:
			active_slot = "weapon"
		elif has_item:
			active_slot = "item"

	var hold_point = get_hold_point()
	if hold_point != null and hold_point.get_child_count() > 0:
		hold_point.get_child(0).visible = (active_slot == "weapon" and holding_gun)

	var melee_hold_point = get_melee_hold_point()
	if melee_hold_point != null and melee_hold_point.get_child_count() > 0:
		melee_hold_point.get_child(0).visible = (active_slot == "weapon" and held_melee_weapon != null)

	var item_hold_point = get_item_hold_point()
	if item_hold_point != null and item_hold_point.get_child_count() > 0:
		item_hold_point.get_child(0).visible = (active_slot == "item")

func _try_cycle_slot(direction: int):
	var occupied = []
	if holding_gun or held_melee_weapon != null:
		occupied.append("weapon")
	if held_item != null:
		occupied.append("item")
	if occupied.size() <= 1:
		return
	var idx = occupied.find(active_slot)
	if idx == -1:
		active_slot = occupied[0]
		return
	idx = (idx + direction) % occupied.size()
	if idx < 0:
		idx += occupied.size()
	active_slot = occupied[idx]

func _merge_animations():
	if not model_anim_player.has_animation_library(""):
		model_anim_player.add_animation_library("", AnimationLibrary.new())
	var lib = model_anim_player.get_animation_library("")

	var packed = load(ANIM_SOURCE_GLB)
	if packed == null:
		push_warning("AnimationMerge: could not load '%s'" % ANIM_SOURCE_GLB)
		return
	var instance = packed.instantiate()
	var source_player = instance.find_child("AnimationPlayer", true, false)
	if source_player == null:
		instance.queue_free()
		push_warning("AnimationMerge: no AnimationPlayer in source GLB")
		return

	const ONE_SHOT = [ANIM_DEATH, ANIM_DANCE, ANIM_SPRINT_ROLL]

	var source_list = source_player.get_animation_list()
	for anim_name in ANIM_INDICES:
		var idx = ANIM_INDICES[anim_name]
		if idx >= source_list.size():
			push_warning("AnimationMerge: index %d out of range for '%s'" % [idx, anim_name])
			continue
		if not lib.has_animation(anim_name):
			var anim = source_player.get_animation(source_list[idx])
			var final_anim = anim.duplicate()
			if anim_name in ONE_SHOT:
				final_anim.loop_mode = Animation.LOOP_NONE
			else:
				final_anim.loop_mode = Animation.LOOP_LINEAR
			lib.add_animation(anim_name, final_anim)

	instance.queue_free()

func _play_anim(anim_name: String):
	if model_anim_player == null:
		return
	if _current_anim == anim_name:
		return
	if not model_anim_player.has_animation(anim_name):
		push_warning("_play_anim: not found: " + anim_name)
		return
	_current_anim = anim_name
	match anim_name:
		ANIM_RUN, ANIM_RUN_JUMPING, ANIM_WALK, ANIM_WALK_PISTOL:
			_anim_rotation_offset = deg_to_rad(30.0)
		ANIM_RUN_PISTOL:
			_anim_rotation_offset = deg_to_rad(40.0)
		_:
			_anim_rotation_offset = 0.0
	model_anim_player.play(anim_name)

func _update_animation(input_dir: Vector2):
	var is_moving = input_dir.length() > 0.1

	if not is_on_floor():
		if is_sprinting:
			_play_anim(ANIM_RUN_JUMPING)
		else:
			_play_anim(ANIM_IDLE_JUMPING)
	elif is_moving and is_sprinting:
		if holding_gun:
			_play_anim(ANIM_RUN_PISTOL)
		else:
			_play_anim(ANIM_RUN)
	elif is_moving:
		if holding_gun:
			_play_anim(ANIM_WALK_PISTOL)
		else:
			_play_anim(ANIM_WALK)
	elif holding_gun:
		_play_anim(ANIM_IDLE_PISTOL)
	else:
		_play_anim(ANIM_IDLE)

func _stop_movement_animation():
	_play_anim(ANIM_IDLE)

func play_death(headshot: bool = false):
	if model_anim_player == null:
		return
	if not model_anim_player.has_animation(ANIM_DEATH):
		return
	_current_anim = ANIM_DEATH
	_anim_rotation_offset = 0.0
	model_anim_player.play(ANIM_DEATH)

func play_victory_dance():
	if model_anim_player == null:
		return
	if not model_anim_player.has_animation(ANIM_DANCE):
		return
	_current_anim = ANIM_DANCE
	_anim_rotation_offset = 0.0
	model_anim_player.play(ANIM_DANCE)

func _update_aiming(_delta):
	var ads_held = Input.is_action_pressed(input_prefix + "_ads")
	var target_blend = 1.0 if ads_held else 0.0
	if target_blend != ads_blend_target:
		ads_blend_target = target_blend
		_start_ads_tween(target_blend)

	var spring_arm = $AimPivot/SpringArm3D
	spring_arm.spring_length = lerp(default_spring_length, ADS_SPRING_LENGTH, ads_blend)
	spring_arm.position.x = lerp(default_spring_position.x, 0.0, ads_blend)
	$AimPivot/SpringArm3D/Camera3D.fov = lerp(default_camera_fov, default_camera_fov * ADS_FOV_MULTIPLIER, ads_blend)

func _start_ads_tween(target_blend: float):
	if ads_tween != null and ads_tween.is_valid():
		ads_tween.kill()
	var remaining_distance = abs(target_blend - ads_blend)
	var duration = remaining_distance * ADS_TRANSITION_TIME
	ads_tween = create_tween()
	ads_tween.set_ease(Tween.EASE_OUT if target_blend > 0.0 else Tween.EASE_IN)
	ads_tween.set_trans(Tween.TRANS_SINE)
	ads_tween.tween_property(self, "ads_blend", target_blend, duration)

func _process_gamepad_look(delta):
	var look_x = Input.get_action_strength(input_prefix + "_look_right") - Input.get_action_strength(input_prefix + "_look_left")
	var look_y = Input.get_action_strength(input_prefix + "_look_down") - Input.get_action_strength(input_prefix + "_look_up")

	look_x = sign(look_x) * pow(abs(look_x), gamepad_response_curve_exponent)
	look_y = sign(look_y) * pow(abs(look_y), gamepad_response_curve_exponent)

	var sens = look_sensitivity
	if ads_blend > 0.0:
		sens *= lerp(1.0, ads_look_sensitivity_multiplier, ads_blend)

	var y_sign = -1.0 if invert_look_y else 1.0
	$AimPivot.rotate_y(-look_x * sens * delta)
	$AimPivot/SpringArm3D.rotate_x(-look_y * sens * delta * y_sign)
	$AimPivot/SpringArm3D.rotation.x = clamp($AimPivot/SpringArm3D.rotation.x, -1.2, 1.2)

func _update_facing():
	$CharacterModel.rotation.y = $AimPivot.rotation.y + MODEL_FACING_OFFSET + _anim_rotation_offset

func get_display_name() -> String:
	if is_player2:
		return GameConfig.player2_name
	return PlayerPrefs.get_setting("player_name")

func get_aim_direction():
	return -$AimPivot/SpringArm3D.global_transform.basis.z

func get_aim_pitch():
	return $AimPivot/SpringArm3D.rotation.x

func get_hold_point():
	return $CharacterModel.find_child("GunHoldPoint", true, false)

func get_melee_hold_point():
	var melee_point = $CharacterModel.find_child("MeleeHoldPoint", true, false)
	return melee_point if melee_point != null else get_hold_point()

func get_item_hold_point():
	return $CharacterModel.find_child("ItemHoldPoint", true, false)

func get_camera():
	if _spectator != null and _spectator.has_method("get_spectator_camera"):
		return _spectator.get_spectator_camera()
	return $AimPivot/SpringArm3D/Camera3D

func apply_knockback(direction: Vector3, distance: float):
	knockback_velocity = direction * (distance / KNOCKBACK_DURATION)
	knockback_timer = KNOCKBACK_DURATION
	is_dashing = false
	is_sprinting = false

func apply_stagger(duration: float):
	stagger_timer = duration
	is_dashing = false
	is_sprinting = false

func grant_bullet_immunity(duration: float):
	bullet_immune_timer = max(bullet_immune_timer, duration)

func is_bullet_immune():
	return bullet_immune_timer > 0.0

func flash_hit():
	var meshes = _find_mesh_instances($CharacterModel)
	var entries = []
	for mesh in meshes:
		var original = mesh.get_surface_override_material(0)
		var base_color = Color.WHITE
		if original != null and original is StandardMaterial3D:
			base_color = original.albedo_color
		var flash_material = StandardMaterial3D.new()
		flash_material.albedo_color = base_color
		mesh.set_surface_override_material(0, flash_material)
		entries.append({"mesh": mesh, "material": flash_material, "original": original, "base_color": base_color})

	var tween = create_tween()
	for entry in entries:
		tween.parallel().tween_property(entry["material"], "albedo_color", Color.RED, 0.05)
	tween.tween_interval(0.05)
	for entry in entries:
		tween.parallel().tween_property(entry["material"], "albedo_color", entry["base_color"], 0.1)

	await tween.finished
	for entry in entries:
		if is_instance_valid(entry["mesh"]):
			entry["mesh"].set_surface_override_material(0, entry["original"])

func _find_mesh_instances(node: Node) -> Array:
	var result = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result

func apply_slow(duration: float, multiplier: float):
	slow_timer = duration
	slow_multiplier_value = multiplier

func apply_powerup(power_type: String, duration: float):
	match power_type:
		"extra_dash":
			if dash_bonus_timer <= 0.0:
				dash_charges += 1
			dash_bonus_timer = duration
		"extra_melee_shield":
			melee_disarm_shields = 1
	active_powerup_order.erase(power_type)
	active_powerup_order.push_front(power_type)

func get_active_powerups_for_display() -> Array:
	var result = []
	for power_type in active_powerup_order:
		match power_type:
			"extra_dash":
				if dash_bonus_timer > 0.0:
					result.append({"type": power_type, "timed": true, "time_left": dash_bonus_timer})
			"extra_melee_shield":
				if melee_disarm_shields > 0:
					result.append({"type": power_type, "timed": false, "time_left": 0.0})
	active_powerup_order = result.map(func(entry): return entry["type"])
	return result

func _start_dash():
	var input_dir = _get_movement_input_dir()
	var dir = ($AimPivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if dir == Vector3.ZERO:
		dir = get_aim_direction()
	dash_direction = dir
	dash_charges -= 1
	is_dashing = true
	is_sprinting = false
	dash_timer = DASH_DURATION

func _update_dash_recharge(delta):
	if dash_bonus_timer > 0.0:
		dash_bonus_timer -= delta
		if dash_bonus_timer <= 0.0:
			dash_charges = min(dash_charges, max_dash_charges)
	if dash_charges < max_dash_charges:
		dash_recharge_timer += delta
		if dash_recharge_timer >= DASH_RECHARGE_TIME:
			dash_charges += 1
			dash_recharge_timer = 0.0

func _update_stamina(delta):
	var is_moving = _get_movement_input_dir().length() > 0.1
	if is_sprinting and not is_moving:
		var sprint_is_toggle = gamepad_sprint_is_toggle if use_gamepad_look else mouse_keyboard_sprint_is_toggle
		if sprint_is_toggle:
			is_sprinting = false
	elif is_sprinting and is_moving:
		stamina -= STAMINA_DRAIN_RATE * delta
		stamina_regen_timer = STAMINA_REGEN_DELAY
		if stamina <= 0.0:
			stamina = 0.0
			is_sprinting = false
	elif stamina_regen_timer > 0.0:
		stamina_regen_timer -= delta
	else:
		stamina += STAMINA_REGEN_RATE * delta
		stamina = min(stamina, MAX_STAMINA)

func drain_stamina(amount):
	stamina -= amount
	stamina_regen_timer = STAMINA_REGEN_DELAY

func has_stamina():
	return stamina > 0.0

func register_interactable(obj):
	if obj not in nearby_interactables:
		nearby_interactables.append(obj)

func unregister_interactable(obj):
	nearby_interactables.erase(obj)

func _try_interact():
	for obj in nearby_interactables:
		var category = obj.get_interact_category() if obj.has_method("get_interact_category") else "weapon"
		if category == "item" and held_item == null:
			obj.pick_up(self)
			return
		if category == "weapon" and held_melee_weapon == null and not holding_gun:
			obj.pick_up(self)
			return
	if active_slot == "weapon":
		if held_melee_weapon != null:
			held_melee_weapon.drop()
			return
		if holding_gun:
			var hold_point = get_hold_point()
			if hold_point.get_child_count() > 0:
				hold_point.get_child(0).drop()
			return
	elif active_slot == "item":
		if held_item != null:
			held_item.drop()
			return

func _try_primary_action():
	if active_slot == "weapon":
		if holding_gun:
			var hold_point = get_hold_point()
			if hold_point.get_child_count() > 0:
				hold_point.get_child(0).try_fire()
		elif held_melee_weapon != null:
			held_melee_weapon.try_swing()
	elif active_slot == "item":
		if held_item != null:
			held_item.try_throw()

func eliminate(killer_name = "", weapon_icon = "💀"):
	if is_eliminated:
		return
	if holding_gun:
		var hold_point = get_hold_point()
		if hold_point != null and hold_point.get_child_count() > 0:
			hold_point.get_child(0).drop()
	if held_melee_weapon != null:
		held_melee_weapon.drop(true)
	is_eliminated = true
	velocity = Vector3.ZERO
	play_death()
	GameEvents.player_eliminated.emit(get_display_name(), killer_name, weapon_icon)
	if model_anim_player != null and model_anim_player.has_animation(ANIM_DEATH):
		await model_anim_player.animation_finished
	visible = false
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	if not ("is_bot" in self and self.is_bot):
		_spectator = load("res://spectator_controller.gd").new()
		add_child(_spectator)
		_spectator.setup(self)

func respawn(spawn_transform):
	if _spectator != null and is_instance_valid(_spectator):
		_spectator.cleanup()
		_spectator = null
	is_eliminated = false
	visible = true
	collision_layer = 0
	collision_mask = 0
	set_collision_layer_value(2, true)
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, true)
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	stamina = MAX_STAMINA
	stamina_regen_timer = 0.0
	is_sprinting = false
	dash_charges = max_dash_charges
	dash_recharge_timer = 0.0
	dash_bonus_timer = 0.0
	is_dashing = false
	knockback_timer = 0.0
	stagger_timer = 0.0
	bullet_immune_timer = 0.0
	melee_disarm_shields = 0
	active_powerup_order.clear()
	slow_timer = 0.0
	slow_multiplier_value = 1.0
	holding_gun = false
	held_melee_weapon = null
	held_item = null
	active_slot = "none"
	if ads_tween != null and ads_tween.is_valid():
		ads_tween.kill()
	ads_blend = 0.0
	ads_blend_target = 0.0
	_current_anim = ""
	if model_anim_player != null:
		model_anim_player.stop()
