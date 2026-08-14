extends CharacterBody3D

const CombatOutline = preload("res://combat_outline.gd")

const VisibilityRules = preload("res://combat_visibility.gd")
const HitboxDebug = preload("res://hitbox_debug_visual.gd")
const OneOfUsIntroScript = preload("res://one_of_us_intro.gd")
const OneOfUsRoleVisualScript = preload("res://one_of_us_role_visual.gd")

const ProtectionIconFactory = preload("res://protection_icon_factory.gd")

# Online (set by round_manager's networked spawn function). Local play leaves
# these at defaults and none of the online paths run.
var is_online := false
var net_authority_id := 1
var actor_id := 1
var owner_peer_id := 1
var character_skin_id := PlayerSkinRegistry.DEFAULT_SKIN_ID
var _is_local_online := true   # true for local play + local-authority online
var _online_name_tag: Label3D = null
var _extra_life_icon: Sprite3D = null
var _sticky_hands_icon: Sprite3D = null
var _friendly_indicator: Label3D = null
var _gun_holder_arrow: Label3D = null
var _all_gun_hearts_label: Label3D = null
var _online_crosshair_layer: CanvasLayer = null
var flash_blind_timer := 0.0
var _flash_blind_total := 0.0

@export var input_prefix := "p1"
@export var is_player2 := false
@export var team_id := -1
@export var use_gamepad_look := false
@export var mouse_look_sensitivity := 1.0
@export var look_sensitivity := 6.0
@export var ads_look_sensitivity_multiplier := 0.5
@export var dash_recharge_time := 3.0
@export_category("Jump Tuning")
@export_range(0.0, 20.0, 0.1) var jump_velocity: float = 7

var gamepad_response_curve_exponent := 2.0
var gamepad_sprint_is_toggle := true
var mouse_keyboard_sprint_is_toggle := false
var max_dash_charges := 3
var invert_look_y := false

const SPEED = 10.0
const SPRINT_SPEED = 18.0
const MODEL_FACING_OFFSET = PI
const MAX_STAMINA = 100.0
const STAMINA_DRAIN_RATE = 25.0
const STAMINA_REGEN_RATE = 20.0
const STAMINA_REGEN_DELAY = 1.0
const DASH_SPEED = 30.0
const DASH_DURATION = 0.2
const DASH_RECHARGE_TIME = 2.0
const MAX_DASH_CHARGES_HARD_CEILING = 6
const KNOCKBACK_DURATION = 0.2
const ADS_TRANSITION_TIME = .2
const ADS_SPRING_LENGTH = 0.3
const ADS_FOV_MULTIPLIER = 0.9
const MOUSE_LOOK_BASE = 0.005
const INTERACT_HOLD_DROP_TIME = 0.5
const BASE_GRAVITY := 9.8
# Grace window for the grounded->airborne ANIMATION switch only. is_on_floor()
# flickers when walking over uneven Terrain3D (the body micro-bounces), which
# would thrash the walk<->jump animation. This debounces it. Purely visual —
# jump gameplay still uses raw is_on_floor().
const AIRBORNE_ANIM_GRACE = 0.12

var holding_gun = false
var held_melee_weapon = null
var held_item_1 = null
var held_item_2 = null
var active_decoy = null
var nearby_interactables = []
var _normal_interactables: Array = []
var _reach_interactables: Array = []
var _reach_scan_timer := 0.0
var _reach_ring: MeshInstance3D = null
var _body_hitbox_debug: HitboxDebugVisual = null
var local_view_render_layer := 0
var active_slot = "none"  # "none" | "weapon" | "item1" | "item2"
var double_jump_shoes_active := false
var all_gun_hearts := 0
var one_of_us_role := ""
var _one_of_us_visual: Node3D = null
var _one_of_us_intro_restore_pitch := 0.0
var _one_of_us_intro_input_locked := false
var _double_jump_shoe_attachments: Array[Node] = []
var _one_of_us_final_bonus_active := false


# Tracks whether the current interact press already resolved as an instant
# pickup/swap (in which case holding it longer does nothing) or is still
# eligible to become a hold-to-drop (see _try_interact()).
var interact_hold_active = false
var interact_hold_timer = 0.0

var stamina = MAX_STAMINA
var stamina_regen_timer = 0.0
var is_sprinting = false
var _airborne_grace_timer = 0.0
var _steam_boost_active := false
var _steam_fast_fall_started := false
var _steam_boost_origin_y := 0.0
var _steam_descent_height_gate := 0.0
var _steam_descent_gravity_multiplier := 1.0
var _spring_air_active := false
var _spring_direction_window := 0.0
var _spring_horizontal_boost := 4.0
var _spring_boost_committed := false
var _dash_cancelled_spring_momentum := false
const SPRING_AIR_CONTROL := 0.60
const DIRECTIONAL_LAUNCH_OPPOSING_MOMENTUM_RETENTION := 0.25
const DIRECTIONAL_LAUNCH_MIN_STREAM_RATIO := 0.40
var _directional_launch_active := false
var _directional_launch_direction := Vector3.ZERO
var _directional_launch_min_forward_speed := 0.0

var dash_charges = 0
var dash_recharge_timer = 0.0
var is_dashing = false
var dash_timer = 0.0
var dash_direction = Vector3.ZERO
var extra_dash_charge := 0

var active_powerup_order = []

var knockback_velocity = Vector3.ZERO
var knockback_timer = 0.0
var stagger_timer = 0.0
var bullet_immune_timer = 0.0
var lethal_immunity_timer = 0.0
var melee_disarm_shields = 0

var slow_timer = 0.0
var slow_multiplier_value = 1.0

var is_eliminated = false
var _spectator: Node = null
var _intro_camera: Camera3D = null
var _intro_active := false
# Invalidates the asynchronous death-animation completion when a new round
# respawns this actor before the animation has finished.
var _elimination_generation := 0

const ANIM_IDLE            = "idle"
const ANIM_IDLE_PISTOL     = "idle_pistol"
const ANIM_LONG_IDLE       = "long_idle"
const ANIM_IDLE_JUMPING    = "jump"
const ANIM_WALK            = "standard_run"
const ANIM_WALK_PISTOL     = "pistol_run"
const ANIM_RUN             = "run"
const ANIM_RUN_PISTOL      = "pistol_run"
const ANIM_RUN_JUMPING     = "running_jump"
const ANIM_FALL            = "fall"
const ANIM_PISTOL_JUMP     = "pistol_jump"
const ANIM_PISTOL_BACKWARD = "pistol_backward"
const ANIM_PISTOL_LEFT     = "pistol_strafe_left"
const ANIM_PISTOL_RIGHT    = "pistol_strafe_right"
const ANIM_MELEE_RUN       = "run_with_sword"
const ANIM_MELEE_ATTACK    = "melee"
const ANIM_THROW           = "throw_object"
const ANIM_HIT             = "hit"
const ANIM_DANCE           = "hip_hop_dance"

var model_anim_player: AnimationPlayer = null
var _current_anim: String = ""
var _anim_rotation_offset: float = 0.0
var _action_animation_time := 0.0
var _idle_animation_time := 0.0
var _victory_dance_active := false

var ads_blend = 0.0
var ads_blend_target = 0.0
var ads_tween: Tween = null
var default_spring_length = 4.0
var default_spring_position = Vector3.ZERO
var default_camera_fov = 75.0
var _camera_base_position := Vector3.ZERO
var _camera_bob_time := 0.0
var _camera_shake_time := 0.0
var _camera_shake_strength := 0.0

func _enter_tree() -> void:
	if is_online:
		# Replication authority and synchronizer children must exist during
		# MultiplayerSpawner's enter-tree phase. Creating them in _ready() is too
		# late for a remote pending spawn to receive its network ID reliably.
		# Keep the spawned actor root host-authoritative so its visibility can be
		# safely gated for late joiners. The child NetSync still belongs to the
		# controlling client and preserves responsive client-side movement.
		set_multiplayer_authority(1)
		_is_local_online = multiplayer.get_unique_id() == net_authority_id
		_build_spawn_visibility_sync()
		_build_net_sync()


func is_locally_controlled() -> bool:
	return not is_online or _is_local_online

func _ready():
	if not (is_player2 and not GameConfig.split_screen_enabled):
		add_to_group("combat_target")
	if is_online:
		# neutralize the map's root scale so online players are player-sized
		var cs = get_tree().current_scene
		var ms: float = cs.scale.x if cs is Node3D and cs.scale.x != 0.0 else 1.0
		scale = Vector3.ONE / ms
		# camera + mouse only for the local-authority player
		$AimPivot/SpringArm3D/Camera3D.current = _is_local_online
		# the full HUD is stripped online (Phase 2b); give the local player at
		# least an aiming crosshair so gun combat is usable.
		if _is_local_online:
			_build_online_crosshair()
		_build_online_name_tag()
	if not use_gamepad_look and _is_local_online:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_player2 and not GameConfig.split_screen_enabled:
		remove_from_group("player")
		visible = false
		set_physics_process(false)
	_apply_character_skin(_initial_character_skin_id())
	model_anim_player = $CharacterModel.find_child("AnimationPlayer", true, false)
	if model_anim_player != null:
		_merge_animations()
		if model_anim_player.has_animation(ANIM_IDLE):
			_current_anim = ANIM_IDLE
			model_anim_player.play(ANIM_IDLE)
			model_anim_player.advance(0.0)
			_airborne_grace_timer = AIRBORNE_ANIM_GRACE
	default_spring_length = $AimPivot/SpringArm3D.spring_length
	default_spring_position = $AimPivot/SpringArm3D.position
	default_camera_fov = $AimPivot/SpringArm3D/Camera3D.fov
	_camera_base_position = $AimPivot/SpringArm3D/Camera3D.position
	_apply_match_settings()
	max_dash_charges = clamp(max_dash_charges, 0, MAX_DASH_CHARGES_HARD_CEILING)
	dash_charges = max_dash_charges
	_apply_player_prefs()
	gamepad_response_curve_exponent = max(gamepad_response_curve_exponent, 0.1)
	GameEvents.melee_hit_landed.connect(_on_melee_hit_for_vampire)
	ads_look_sensitivity_multiplier = clamp(ads_look_sensitivity_multiplier, 0.05, 1.0)
	if not PlayerPrefs.setting_changed.is_connected(_on_player_pref_changed):
		PlayerPrefs.setting_changed.connect(_on_player_pref_changed)
	_body_hitbox_debug = HitboxDebug.new()
	_body_hitbox_debug.name = "BodyHitboxDebug"
	add_child(_body_hitbox_debug)
	_body_hitbox_debug.setup($CollisionShape3D, Color(0.05, 0.9, 1.0, 0.18))

func _on_player_pref_changed(key: String, _value):
	_apply_player_prefs()
	if key == "character_skin_id" and not is_online and not is_player2:
		_apply_character_skin(str(PlayerPrefs.get_setting("character_skin_id")))

func _apply_match_settings():
	max_dash_charges = GameConfig.max_dash_charges

func _apply_player_prefs():
	mouse_look_sensitivity = PlayerPrefs.get_setting("mouse_sensitivity")
	look_sensitivity = PlayerPrefs.get_setting("gamepad_sensitivity")
	ads_look_sensitivity_multiplier = PlayerPrefs.get_setting("ads_sensitivity_multiplier")
	gamepad_response_curve_exponent = PlayerPrefs.get_setting("gamepad_response_curve_exponent")
	gamepad_sprint_is_toggle = PlayerPrefs.get_setting("gamepad_sprint_is_toggle")
	mouse_keyboard_sprint_is_toggle = PlayerPrefs.get_setting("mouse_keyboard_sprint_is_toggle")
	invert_look_y = PlayerPrefs.get_setting("invert_look_y")
	default_camera_fov = PlayerPrefs.get_setting("field_of_view")
	$AimPivot/SpringArm3D/Camera3D.fov = default_camera_fov


func _initial_character_skin_id() -> String:
	if is_online:
		return PlayerSkinRegistry.sanitize_skin_id(character_skin_id)
	if is_player2:
		return PlayerSkinRegistry.sanitize_skin_id(str(GameConfig.player2_skin_id))
	return PlayerSkinRegistry.sanitize_skin_id(
		str(PlayerPrefs.get_setting("character_skin_id")))


func set_character_skin(requested_id: String) -> void:
	_apply_character_skin(requested_id)


func _apply_character_skin(requested_id: String) -> void:
	character_skin_id = PlayerSkinRegistry.sanitize_skin_id(requested_id)
	var visual := get_node_or_null("CharacterModel")
	if visual != null and visual.has_method("set_skin"):
		visual.set_skin(character_skin_id)


func set_one_of_us_role(role: String) -> void:
	one_of_us_role = role if role in ["us", "them"] else ""
	max_dash_charges = GameConfig.ONE_OF_US_THEM_DASH_CHARGES \
		if one_of_us_role == "them" else GameConfig.ONE_OF_US_US_DASH_CHARGES
	max_dash_charges = clampi(max_dash_charges, 0, MAX_DASH_CHARGES_HARD_CEILING)
	dash_charges = max_dash_charges if one_of_us_role == "them" \
		else mini(dash_charges, max_dash_charges)
	if _one_of_us_visual == null:
		_one_of_us_visual = OneOfUsRoleVisualScript.new()
		_one_of_us_visual.name = "OneOfUsRoleVisual"
		add_child(_one_of_us_visual)
	_one_of_us_visual.set_infected(one_of_us_role == "them")


func set_one_of_us_final_us(active: bool) -> void:
	if active and one_of_us_role == "us" and not _one_of_us_final_bonus_active:
		extra_dash_charge = maxi(extra_dash_charge, 1)
	_one_of_us_final_bonus_active = active and one_of_us_role == "us"


func play_one_of_us_intro(first_actor_id: int) -> void:
	var intro = OneOfUsIntroScript.new()
	intro.name = "OneOfUsIntro"
	add_child(intro)
	intro.play(self, first_actor_id)


func get_one_of_us_intro_display_rect() -> Rect2:
	var full_rect := get_viewport().get_visible_rect()
	if is_online or not GameConfig.split_screen_enabled:
		return full_rect
	var half_width := full_rect.size.x * 0.5
	var x_offset := half_width if is_player2 else 0.0
	return Rect2(full_rect.position + Vector2(x_offset, 0.0),
		Vector2(half_width, full_rect.size.y))


func get_gameplay_camera() -> Camera3D:
	return $AimPivot/SpringArm3D/Camera3D


func begin_one_of_us_intro_view(_first_infected: bool, cinematic_camera: Camera3D) -> void:
	_one_of_us_intro_input_locked = true
	_one_of_us_intro_restore_pitch = $AimPivot/SpringArm3D.rotation.x
	_intro_active = true
	_intro_camera = cinematic_camera
	if is_online and _intro_camera != null:
		_intro_camera.make_current()


func transition_one_of_us_intro_to_gameplay(first_infected: bool) -> void:
	_intro_active = false
	if is_online:
		get_gameplay_camera().make_current()
	if first_infected:
		var tween := create_tween()
		tween.tween_property($AimPivot/SpringArm3D, "rotation:x", 0.48, 0.20)


func end_one_of_us_intro_view() -> void:
	_one_of_us_intro_input_locked = false
	_intro_active = false
	_intro_camera = null
	if is_online:
		get_gameplay_camera().make_current()
	var tween := create_tween()
	tween.tween_property($AimPivot/SpringArm3D, "rotation:x",
		_one_of_us_intro_restore_pitch, 0.25)


func play_one_of_us_transformation() -> void:
	if _one_of_us_visual != null and _one_of_us_visual.has_method("play_transformation"):
		_one_of_us_visual.play_transformation()


func _input(event):
	if _one_of_us_intro_input_locked:
		return
	if use_gamepad_look or not _is_local_online or PauseManager.is_pause_open():
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
	# Runs for local players AND remote puppets (before the puppet early-return)
	# so everyone renders the gun holder's outline.
	_update_gun_holder_outline()
	_update_protection_icons()
	if is_online and _is_local_online and _online_crosshair_layer != null:
		_online_crosshair_layer.visible = not is_eliminated
	# Authoritative status timers must tick on every machine, including the
	# host's puppet for a client-owned actor. Keeping this below the puppet
	# early-return made a client's post-melee bullet immunity permanent on the
	# server, so every later bullet was incorrectly ignored.
	if bullet_immune_timer > 0.0:
		bullet_immune_timer = maxf(bullet_immune_timer - delta, 0.0)
	if lethal_immunity_timer > 0.0:
		lethal_immunity_timer = maxf(lethal_immunity_timer - delta, 0.0)
	_update_flash_blind(delta)
	_update_action_animation(delta)
	# Combat timers do not pause just because movement is interrupted.
	_update_new_powerups(delta)
	# Remote networked puppets are driven entirely by their MultiplayerSynchronizer
	# (position/rotation/aim); skip all local input + physics so nothing fights it,
	# but still drive their locomotion animation + model facing from the synced
	# velocity/aim so they walk/run instead of sliding in a frozen pose.
	if is_online and not _is_local_online:
		_update_puppet_visuals(delta)
		return
	if _one_of_us_intro_input_locked:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			_apply_air_gravity(delta)
		move_and_slide()
		return

	if _steam_boost_active and is_on_floor():
		_clear_steam_boost()
	_update_accessible_camera_motion(delta)

	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_multiplier_value = 1.0

	# Refresh the animation grounded-grace timer every frame (uses last
	# frame's floor state, which is fine for a purely-visual debounce).
	if is_on_floor():
		_airborne_grace_timer = AIRBORNE_ANIM_GRACE
	else:
		_airborne_grace_timer = max(_airborne_grace_timer - delta, 0.0)

	if is_eliminated:
		if not is_on_floor():
			_apply_air_gravity(delta)
		else:
			velocity.y = 0
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	if is_online and _is_local_online and PauseManager.is_pause_open():
		velocity.x = move_toward(velocity.x, 0.0, SPEED * delta)
		velocity.z = move_toward(velocity.z, 0.0, SPEED * delta)
		if not is_on_floor():
			_apply_air_gravity(delta)
		move_and_slide()
		_update_stamina(delta)
		_update_dash_recharge(delta)
		_update_facing()
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
		_apply_air_gravity(delta)

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

	if Input.is_action_just_pressed(input_prefix + "_jump"):
		if is_on_floor():
			velocity.y = jump_velocity
		elif double_jump_shoes_active:
			_request_double_jump_shoes()

	if Input.is_action_just_pressed(input_prefix + "_interact"):
		# A tap resolves as an instant pickup/swap if one is available right
		# now; only if nothing happens does holding the button start counting
		# toward a voluntary drop of the active slot (see below).
		interact_hold_active = not _try_interact()
		interact_hold_timer = 0.0

	if interact_hold_active:
		if Input.is_action_pressed(input_prefix + "_interact"):
			interact_hold_timer += delta
			if interact_hold_timer >= INTERACT_HOLD_DROP_TIME:
				_drop_active_slot()
				interact_hold_active = false
		else:
			interact_hold_active = false
			interact_hold_timer = 0.0

	if Input.is_action_just_pressed(input_prefix + "_fire"):
		var active_item = get_active_item() if active_slot in ["item1", "item2"] else null
		if active_item != null and active_item.has_method("begin_use"):
			active_item.begin_use()
		else:
			_try_primary_action()
	if Input.is_action_just_released(input_prefix + "_fire"):
		var released_item = get_active_item() if active_slot in ["item1", "item2"] else null
		if released_item != null and released_item.has_method("release_use"):
			released_item.release_use()

	if Input.is_action_just_pressed(input_prefix + "_throw"):
		if active_slot == "weapon" and held_melee_weapon != null:
			held_melee_weapon.begin_throw_preview()
	if Input.is_action_just_released(input_prefix + "_throw"):
		if active_slot == "weapon" and held_melee_weapon != null:
			held_melee_weapon.release_throw()

	if Input.is_action_just_pressed(input_prefix + "_decoy_command"):
		_toggle_active_decoy_control()

	if Input.is_action_just_pressed(input_prefix + "_dash") \
			and (dash_charges > 0 or extra_dash_charge > 0) and not is_dashing:
		_start_dash()

	var sprint_is_toggle = gamepad_sprint_is_toggle if use_gamepad_look else mouse_keyboard_sprint_is_toggle
	if not GameConfig.sprinting_enabled:
		is_sprinting = false
	elif sprint_is_toggle:
		if Input.is_action_just_pressed(input_prefix + "_sprint"):
			_toggle_sprint()
	else:
		is_sprinting = Input.is_action_pressed(input_prefix + "_sprint") and stamina > 0.0

	if is_dashing:
		dash_timer -= delta
		if _dash_cancelled_spring_momentum:
			# A dash committed during a spring-pad launch replaces that launch;
			# neither its upward speed nor its horizontal boost may leak through.
			velocity.y = 0.0
		var steer_input: Vector2 = _get_movement_input_dir()
		if steer_input.length_squared() > 0.01:
			var steer_target: Vector3 = ($AimPivot.transform.basis
				* Vector3(steer_input.x, 0.0, steer_input.y)).normalized()
			dash_direction = dash_direction.slerp(steer_target, minf(delta * 12.0, 1.0))
		velocity.x = dash_direction.x * DASH_SPEED
		velocity.z = dash_direction.z * DASH_SPEED
		if dash_timer <= 0.0:
			is_dashing = false
			_dash_cancelled_spring_momentum = false
			_current_anim = ""
	else:
		var current_speed = SPRINT_SPEED if is_sprinting else SPEED
		current_speed *= slow_multiplier_value
		if speed_surge_timer > 0.0:
			current_speed *= SPEED_SURGE_MULT
		if one_of_us_role == "them":
			current_speed *= GameConfig.ONE_OF_US_THEM_SPEED_MULTIPLIER

		var input_dir = _get_movement_input_dir()
		var flash_camera_movement := _active_flash_camera_mode()
		if flash_camera_movement:
			input_dir.x *= 0.70
		var direction = ($AimPivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		# Normal movement keeps the established digital/analog behavior. Camera
		# mode alone preserves the shortened input-vector magnitude so pure lateral
		# movement really is 30% slower instead of normalization restoring it.
		if flash_camera_movement:
			direction *= minf(input_dir.length(), 1.0)

		if _spring_air_active and not is_on_floor():
			_spring_direction_window = maxf(_spring_direction_window - delta, 0.0)
			if direction:
				# Preserve 40% of the launch trajectory while granting 60% of the
				# normal movement target each physics frame. This matches bot pads.
				velocity.x = lerpf(velocity.x, direction.x * current_speed, SPRING_AIR_CONTROL)
				velocity.z = lerpf(velocity.z, direction.z * current_speed, SPRING_AIR_CONTROL)
			if not _spring_boost_committed and _spring_direction_window > 0.0 and input_dir.length_squared() > 0.04:
				var committed_direction: Vector3 = direction.normalized()
				velocity.x += committed_direction.x * _spring_horizontal_boost
				velocity.z += committed_direction.z * _spring_horizontal_boost
				_spring_boost_committed = true
			_enforce_directional_launch_minimum()
		elif direction:
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
		else:
			if not _spring_air_active:
				velocity.x = move_toward(velocity.x, 0, current_speed)
				velocity.z = move_toward(velocity.z, 0, current_speed)

		_update_animation(input_dir, delta)

	var _desired_h_vel := Vector3(velocity.x, 0, velocity.z)
	move_and_slide()
	if _spring_air_active and is_on_floor() and velocity.y <= 0.0:
		_clear_spring_launch_state()
	_try_step_up(_desired_h_vel, delta)
	_update_footsteps(delta)
	_update_stamina(delta)
	_update_dash_recharge(delta)
	_update_facing()

func apply_steam_boost(launch_velocity: float, launch_origin_y: float,
		descent_height_gate: float, descent_gravity_multiplier: float) -> void:
	velocity.y = maxf(velocity.y, launch_velocity)
	_steam_boost_active = true
	_steam_fast_fall_started = false
	_steam_boost_origin_y = launch_origin_y
	_steam_descent_height_gate = maxf(descent_height_gate, 0.0)
	_steam_descent_gravity_multiplier = maxf(descent_gravity_multiplier, 1.0)


func apply_spring_launch(launch_velocity: float, horizontal_boost: float, direction_window: float) -> void:
	velocity.y = maxf(velocity.y, launch_velocity)
	_spring_air_active = true
	_spring_direction_window = maxf(direction_window, 0.0)
	_spring_horizontal_boost = horizontal_boost
	_spring_boost_committed = false


func apply_directional_launch(launch_velocity: Vector3) -> void:
	if launch_velocity.is_zero_approx():
		return
	# Preserve all cross-stream momentum and momentum already traveling with the
	# water. Head-on momentum is reduced before the water impulse is added so a
	# player entering against the stream is pushed back along the jet instead of
	# either stopping dead or passing straight through it.
	_clear_steam_boost()
	var launch_horizontal := Vector3(launch_velocity.x, 0.0, launch_velocity.z)
	if not launch_horizontal.is_zero_approx():
		var launch_direction := launch_horizontal.normalized()
		var current_horizontal := Vector3(velocity.x, 0.0, velocity.z)
		var parallel_speed := current_horizontal.dot(launch_direction)
		var cross_stream_velocity := current_horizontal - launch_direction * parallel_speed
		if parallel_speed < 0.0:
			parallel_speed *= DIRECTIONAL_LAUNCH_OPPOSING_MOMENTUM_RETENTION
		var combined_horizontal := cross_stream_velocity \
			+ launch_direction * parallel_speed + launch_horizontal
		velocity.x = combined_horizontal.x
		velocity.z = combined_horizontal.z
	velocity.y = maxf(velocity.y, launch_velocity.y)
	_spring_air_active = true
	_spring_direction_window = 0.0
	_spring_horizontal_boost = 0.0
	_spring_boost_committed = true
	is_dashing = false
	_dash_cancelled_spring_momentum = false
	stagger_timer = 0.0
	knockback_timer = 0.0
	knockback_velocity = Vector3.ZERO
	_directional_launch_active = not launch_horizontal.is_zero_approx()
	if _directional_launch_active:
		_directional_launch_direction = launch_horizontal.normalized()
		_directional_launch_min_forward_speed = (
			launch_horizontal.length() * DIRECTIONAL_LAUNCH_MIN_STREAM_RATIO)
		_enforce_directional_launch_minimum()


func _enforce_directional_launch_minimum() -> void:
	if not _directional_launch_active:
		return
	var current_horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var current_stream_speed := current_horizontal.dot(_directional_launch_direction)
	if current_stream_speed >= _directional_launch_min_forward_speed:
		return
	var correction := _directional_launch_direction \
		* (_directional_launch_min_forward_speed - current_stream_speed)
	velocity.x += correction.x
	velocity.z += correction.z


func _clear_spring_launch_state() -> void:
	_spring_air_active = false
	_spring_direction_window = 0.0
	_spring_horizontal_boost = 4.0
	_spring_boost_committed = false
	_directional_launch_active = false
	_directional_launch_direction = Vector3.ZERO
	_directional_launch_min_forward_speed = 0.0


func _cancel_spring_launch_for_dash() -> void:
	_clear_spring_launch_state()
	velocity = Vector3.ZERO


func _apply_air_gravity(delta: float) -> void:
	if (_steam_boost_active and not _steam_fast_fall_started
			and velocity.y <= 0.0
			and global_position.y >= _steam_boost_origin_y + _steam_descent_height_gate):
		_steam_fast_fall_started = true
	var gravity_multiplier: float = (
		_steam_descent_gravity_multiplier if _steam_fast_fall_started else 1.0)
	velocity.y -= BASE_GRAVITY * gravity_multiplier * delta


func _clear_steam_boost() -> void:
	_steam_boost_active = false
	_steam_fast_fall_started = false

# One footstep sound per stride while grounded and moving; cadence follows
# sprint state. silent_steps powerup mutes them without breaking cadence.
var footstep_timer := 0.0
var silent_steps_timer := 0.0

func _update_footsteps(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or is_dashing or hspeed < 2.0:
		footstep_timer = 0.12  # small re-arm so the first step lands naturally
		return
	footstep_timer -= delta
	if footstep_timer <= 0.0:
		if silent_steps_timer <= 0.0:
			AudioManager.play_sfx("footstep")
			GameEvents.combat_noise.emit(global_position, actor_id, "footstep", 9.0 if is_sprinting else 6.0)
		footstep_timer = 0.26 if is_sprinting else 0.38

# Walk straight over knee-height ledges (steps, boardwalks, small rocks)
# without jumping. Shape-casts the body up -> forward -> down; if a walkable
# surface sits within STEP_HEIGHT, lifts the body just enough to clear it and
# lets next frame's move_and_slide carry it forward.
const STEP_HEIGHT := 0.55
const STEP_FORWARD_PROBE := 0.25

func _try_step_up(desired_h_vel: Vector3, delta: float) -> void:
	if not is_on_floor():
		return
	var h := Vector3(desired_h_vel.x, 0, desired_h_vel.z)
	if h.length_squared() < 0.04:
		return
	var dir := h.normalized()
	# low steps (~0.2-0.4m) don't set is_on_wall on a capsule, so scan all
	# slide collisions for any steep face opposing our travel
	var blocked := false
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y < 0.7 and n.dot(dir) < -0.4:
			blocked = true
			break
	if not blocked:
		return
	var params := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()
	# 1) headroom: how far up can the body go?
	params.from = global_transform
	params.motion = Vector3.UP * STEP_HEIGHT
	var up_dist := STEP_HEIGHT
	if PhysicsServer3D.body_test_motion(get_rid(), params, result):
		up_dist = result.get_travel().y
	if up_dist < 0.03:
		return
	# 2) raised that high, does the body clear the ledge moving forward?
	var raised := global_transform
	raised.origin.y += up_dist
	var fwd := dir * maxf(h.length() * delta, STEP_FORWARD_PROBE)
	params.from = raised
	params.motion = fwd
	if PhysicsServer3D.body_test_motion(get_rid(), params, result):
		if result.get_travel().length() < fwd.length() * 0.5:
			return  # still blocked when raised: a real wall, not a step
	# 3) measure the ledge: drop back down at the forward position
	var fwd_pos := raised
	fwd_pos.origin += fwd
	params.from = fwd_pos
	params.motion = Vector3.DOWN * (up_dist + 0.1)
	if not PhysicsServer3D.body_test_motion(get_rid(), params, result):
		return  # nothing to land on within step height
	if result.get_collision_normal().angle_to(Vector3.UP) > floor_max_angle:
		return  # landing would be on a steep face, not a walkable step
	var step_h := up_dist + result.get_travel().y  # travel.y is negative
	if step_h <= 0.01 or step_h > STEP_HEIGHT:
		return
	global_position.y += step_h + 0.02

func _toggle_sprint():
	if not GameConfig.sprinting_enabled:
		is_sprinting = false
		return
	if is_sprinting:
		is_sprinting = false
	elif stamina > 0.0:
		is_sprinting = true

func _update_active_slot_and_visuals():
	var has_weapon = holding_gun or held_melee_weapon != null
	var has_item1 = held_item_1 != null
	var has_item2 = held_item_2 != null

	var active_still_valid = (
		(active_slot == "weapon" and has_weapon)
		or (active_slot == "item1" and has_item1)
		or (active_slot == "item2" and has_item2)
	)
	if not active_still_valid:
		active_slot = _first_occupied_slot()

	var hold_point = get_hold_point()
	if hold_point != null and hold_point.get_child_count() > 0:
		hold_point.get_child(0).visible = (
			active_slot == "weapon" and holding_gun and not _victory_dance_active)

	var melee_hold_point = get_melee_hold_point()
	if melee_hold_point != null and melee_hold_point.get_child_count() > 0:
		melee_hold_point.get_child(0).visible = (active_slot == "weapon" and held_melee_weapon != null)

	if held_item_1 != null:
		held_item_1.visible = (active_slot == "item1")
	if held_item_2 != null:
		held_item_2.visible = (active_slot == "item2")

func _first_occupied_slot() -> String:
	if holding_gun or held_melee_weapon != null:
		return "weapon"
	if held_item_1 != null:
		return "item1"
	if held_item_2 != null:
		return "item2"
	return "none"

func _try_cycle_slot(direction: int):
	var current_item = get_active_item() if active_slot in ["item1", "item2"] else null
	if current_item != null and current_item.has_method("is_committed_use") and current_item.is_committed_use():
		return
	if current_item != null and current_item.has_method("cancel_use"):
		current_item.cancel_use()
	var occupied = []
	if holding_gun or held_melee_weapon != null:
		occupied.append("weapon")
	if held_item_1 != null:
		occupied.append("item1")
	if held_item_2 != null:
		occupied.append("item2")
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

# Build the per-player MultiplayerSynchronizer in code (keeps online netcode
# out of the shared player.tscn). Replicates transform + aim + velocity from
# the authority peer to everyone else.
func _build_net_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "NetSync"
	sync.public_visibility = false
	sync.add_visibility_filter(Callable(NetworkManager,
		"is_gameplay_replication_visible_to_peer"))
	var cfg := SceneReplicationConfig.new()
	for prop in [".:position", ".:rotation", "AimPivot:rotation", "AimPivot/SpringArm3D:rotation", ".:velocity", ".:stamina"]:
		cfg.add_property(NodePath(prop))
	sync.replication_config = cfg
	sync.set_multiplayer_authority(net_authority_id)
	for connected_peer in multiplayer.get_peers():
		var connected_id := int(connected_peer)
		sync.set_visibility_for(connected_id,
			NetworkManager.is_gameplay_replication_visible_to_peer(connected_id))
	add_child(sync)
	sync.update_visibility()
	# Puppets play idle so they read as a standing character while sliding to
	# their synced positions (walk-anim sync is a later-phase polish).
	if not _is_local_online:
		call_deferred("_play_puppet_idle")


# Spawn visibility must remain host-authoritative even though the movement
# synchronizer is client-authoritative. Godot only lets synchronizers sharing
# the MultiplayerSpawner's authority control whether the spawned root exists.
func _build_spawn_visibility_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "SpawnVisibility"
	sync.public_visibility = false
	sync.replication_config = SceneReplicationConfig.new()
	sync.set_multiplayer_authority(1)
	sync.add_visibility_filter(Callable(NetworkManager,
		"is_gameplay_replication_visible_to_peer"))
	for connected_peer in multiplayer.get_peers():
		var connected_id := int(connected_peer)
		sync.set_visibility_for(connected_id,
			NetworkManager.is_gameplay_replication_visible_to_peer(connected_id))
	add_child(sync)
	sync.update_visibility()

# Online and local play share the exact same procedural crosshair renderer.
func _build_online_crosshair() -> void:
	var layer := CanvasLayer.new()
	_online_crosshair_layer = layer
	layer.name = "OnlineCrosshair"
	layer.layer = 20
	layer.visible = true
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var crosshair := Control.new()
	crosshair.name = "Crosshair"
	crosshair.set_script(load("res://crosshair.gd"))
	root.add_child(crosshair)
	crosshair.set_player(self)
	add_child(layer)

func _build_online_name_tag() -> void:
	var viewer = NetworkManager.find_net_player(NetworkManager.local_id())
	var friendly := viewer != null and GameConfig.teams_enabled \
		and int(viewer.get("team_id")) >= 0 and int(viewer.get("team_id")) == team_id
	_online_name_tag = Label3D.new()
	_online_name_tag.name = "OnlineNameTag"
	_online_name_tag.position = Vector3(0.0, 2.35, 0.0)
	_online_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_online_name_tag.no_depth_test = false
	_online_name_tag.font_size = 32 if friendly else 38
	_online_name_tag.outline_size = 8
	_online_name_tag.modulate = Color(0.25, 0.85, 1.0) if friendly else Color(1.0, 0.2, 0.2)
	_online_name_tag.visibility_range_end = 50.0
	_online_name_tag.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_online_name_tag.visible = not _is_local_online
	add_child(_online_name_tag)
	_friendly_indicator = Label3D.new()
	_friendly_indicator.text = "◆"
	_friendly_indicator.position = Vector3(0.0, 2.62, 0.0)
	_friendly_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_friendly_indicator.no_depth_test = true
	_friendly_indicator.font_size = 22
	_friendly_indicator.outline_size = 7
	_friendly_indicator.modulate = Color(0.2, 0.95, 1.0)
	_friendly_indicator.visible = friendly and not _is_local_online
	add_child(_friendly_indicator)
	_extra_life_icon = _make_protection_icon(
		"res://UI/icons/extra_life.svg", Vector3(-0.28, 2.78, 0.0))
	_sticky_hands_icon = _make_protection_icon(
		"res://UI/icons/sticky_hands.svg", Vector3(0.28, 2.78, 0.0))
	_gun_holder_arrow = Label3D.new()
	_gun_holder_arrow.text = "\u25bc  GUN HOLDER  \u25bc"
	_gun_holder_arrow.position = Vector3(0.0, 3.08, 0.0)
	_gun_holder_arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_gun_holder_arrow.no_depth_test = false
	_gun_holder_arrow.font_size = CombatOutline.GUN_HOLDER_MARKER_FONT_SIZE
	_gun_holder_arrow.outline_size = CombatOutline.GUN_HOLDER_MARKER_OUTLINE_SIZE
	_gun_holder_arrow.modulate = Color(1.0, 0.08, 0.08)
	_gun_holder_arrow.visible = false
	add_child(_gun_holder_arrow)
	_all_gun_hearts_label = Label3D.new()
	_all_gun_hearts_label.name = "AllGunWorldHearts"
	_all_gun_hearts_label.position = Vector3(0.0, 3.08, 0.0)
	_all_gun_hearts_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_all_gun_hearts_label.no_depth_test = false
	_all_gun_hearts_label.font_size = 34
	_all_gun_hearts_label.outline_size = 9
	_all_gun_hearts_label.modulate = Color(1.0, 0.14, 0.2)
	_all_gun_hearts_label.visibility_range_end = 50.0
	_all_gun_hearts_label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_all_gun_hearts_label.visible = false
	add_child(_all_gun_hearts_label)
	_update_online_name_tag()
	if not NetworkManager.lobby_changed.is_connected(_update_online_name_tag):
		NetworkManager.lobby_changed.connect(_update_online_name_tag)

func _update_online_name_tag() -> void:
	if _online_name_tag != null:
		_online_name_tag.text = get_display_name()

func _make_protection_icon(texture_path: String, at: Vector3) -> Sprite3D:
	var icon := Sprite3D.new()
	icon.texture = ProtectionIconFactory.texture_from_svg(texture_path)
	icon.position = at
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = false
	icon.pixel_size = 0.0025
	icon.visibility_range_end = 50.0
	icon.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	icon.visible = false
	add_child(icon)
	return icon

func _pref_color(key: String, fallback: Color) -> Color:
	var value = PlayerPrefs.get_setting(key)
	if value is Array and value.size() >= 4:
		return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return fallback

func _update_protection_icons() -> void:
	if _extra_life_icon == null or _sticky_hands_icon == null:
		return
	var viewer = NetworkManager.find_net_player(NetworkManager.local_id()) if NetworkManager.is_online() else null
	var friendly := viewer != null and GameConfig.teams_enabled and int(viewer.get("team_id")) == int(team_id)
	var spectator_view := NetworkManager.is_online() and NetworkManager.local_match_role == "spectator"
	var perception_visible := spectator_view or friendly or (viewer != null and VisibilityRules.has_visual_contact(viewer, self, false))
	if _online_name_tag != null:
		_online_name_tag.visible = not _is_local_online and perception_visible and not is_eliminated
		_online_name_tag.no_depth_test = friendly or spectator_view
	if _friendly_indicator != null:
		_friendly_indicator.visible = friendly and not _is_local_online and not is_eliminated
	var icon_size := clampf(float(PlayerPrefs.get_setting("protection_icon_size")), 0.5, 2.0)
	_extra_life_icon.scale = Vector3.ONE * icon_size
	_sticky_hands_icon.scale = Vector3.ONE * icon_size
	_extra_life_icon.modulate = _pref_color("extra_life_icon_color", Color(1.0, 0.72, 0.18))
	_sticky_hands_icon.modulate = _pref_color("sticky_hands_icon_color", Color(0.2, 1.0, 0.35))
	_extra_life_icon.visible = not _is_local_online and perception_visible and second_wind_ready and not is_eliminated
	_sticky_hands_icon.visible = not _is_local_online and perception_visible and melee_disarm_shields > 0 and not is_eliminated
	if _gun_holder_arrow != null:
		_gun_holder_arrow.visible = not _is_local_online and viewer != null \
			and GameConfig.game_mode == GameConfig.MODE_ONE_GUN \
			and holding_gun and not is_eliminated \
			and VisibilityRules.has_visual_contact(viewer, self, true)
		if _gun_holder_arrow.visible:
			var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) \
				* CombatOutline.GUN_HOLDER_MARKER_PULSE_AMOUNT
			_gun_holder_arrow.scale = Vector3.ONE * pulse

	if _all_gun_hearts_label != null:
		var show_all_gun_hearts := GameConfig.game_mode == GameConfig.MODE_ALL_GUN \
			and not is_eliminated and (_is_local_online or perception_visible)
		_all_gun_hearts_label.visible = show_all_gun_hearts
		if show_all_gun_hearts:
			var remaining := clampi(all_gun_hearts, 0, 3)
			_all_gun_hearts_label.text = "\u2665".repeat(remaining) + "\u2661".repeat(3 - remaining)


func _play_puppet_idle() -> void:
	if model_anim_player != null and model_anim_player.has_animation(ANIM_IDLE):
		model_anim_player.play(ANIM_IDLE)

# Remote puppet: pick idle/walk/run (and pistol variants) from the synced velocity
# so it animates while the synchronizer slides it to position; face the synced aim.
func _update_puppet_visuals(delta: float) -> void:
	if model_anim_player != null and not is_eliminated:
		var speed := Vector2(velocity.x, velocity.z).length()
		if speed > 0.6:
			_idle_animation_time = 0.0
			if holding_gun:
				var local_velocity: Vector3 = \
					$AimPivot.global_transform.basis.inverse() * velocity
				if local_velocity.z > absf(local_velocity.x) * 0.75:
					_play_anim(ANIM_PISTOL_BACKWARD)
				elif local_velocity.x < -0.35:
					_play_anim(ANIM_PISTOL_LEFT)
				elif local_velocity.x > 0.35:
					_play_anim(ANIM_PISTOL_RIGHT)
				else:
					_play_anim(ANIM_RUN_PISTOL)
			elif held_melee_weapon != null:
				_play_anim(ANIM_MELEE_RUN)
			else:
				_play_anim(ANIM_RUN if speed > (SPEED + SPRINT_SPEED) * 0.5 else ANIM_WALK)
		elif holding_gun:
			_idle_animation_time += delta
			_play_anim(ANIM_IDLE_PISTOL)
		else:
			_idle_animation_time += delta
			_play_anim(ANIM_LONG_IDLE if _idle_animation_time >= 8.0 else ANIM_IDLE)
	_update_facing()

func _merge_animations():
	var visual := get_node_or_null("CharacterModel")
	if visual != null and visual.has_method("ensure_animation_library"):
		model_anim_player = visual.ensure_animation_library()

func _play_anim(anim_name: String, force := false, custom_speed := 1.0):
	if model_anim_player == null:
		return
	if _action_animation_time > 0.0 and not force:
		return
	if _current_anim == anim_name:
		return
	if not model_anim_player.has_animation(anim_name):
		push_warning("_play_anim: not found: " + anim_name)
		return
	_current_anim = anim_name
	_anim_rotation_offset = 0.0
	model_anim_player.play(anim_name, 0.12, custom_speed)

func _is_grounded_for_anim() -> bool:
	# Debounced grounded check for animation only — see AIRBORNE_ANIM_GRACE.
	return _airborne_grace_timer > 0.0

func _update_animation(input_dir: Vector2, delta: float):
	if _action_animation_time > 0.0:
		return
	var is_moving = input_dir.length() > 0.1

	if not _is_grounded_for_anim():
		_idle_animation_time = 0.0
		if velocity.y < -0.5:
			_play_anim(ANIM_FALL)
		elif holding_gun:
			_play_anim(ANIM_PISTOL_JUMP)
		elif is_sprinting or is_moving:
			_play_anim(ANIM_RUN_JUMPING)
		else:
			_play_anim(ANIM_IDLE_JUMPING)
	elif is_moving:
		_idle_animation_time = 0.0
		if holding_gun:
			if input_dir.y > absf(input_dir.x) * 0.75:
				_play_anim(ANIM_PISTOL_BACKWARD)
			elif input_dir.x < -0.35:
				_play_anim(ANIM_PISTOL_LEFT)
			elif input_dir.x > 0.35:
				_play_anim(ANIM_PISTOL_RIGHT)
			else:
				_play_anim(ANIM_RUN_PISTOL)
		elif held_melee_weapon != null:
			_play_anim(ANIM_MELEE_RUN)
		elif is_sprinting:
			_play_anim(ANIM_RUN)
		else:
			_play_anim(ANIM_WALK)
	elif holding_gun:
		_idle_animation_time += delta
		_play_anim(ANIM_IDLE_PISTOL)
	else:
		_idle_animation_time += delta
		_play_anim(ANIM_LONG_IDLE if _idle_animation_time >= 8.0 else ANIM_IDLE)

func _stop_movement_animation():
	_play_anim(ANIM_IDLE)

func play_death(headshot: bool = false):
	# The authored death presentation remains the shared confetti pop. A
	# skeletal death clip can be inserted here later without touching combat.
	pass

func play_victory_dance():
	if model_anim_player == null:
		return
	if not model_anim_player.has_animation(ANIM_DANCE):
		return
	_victory_dance_active = true
	_set_held_gun_visual_visible(false)
	_current_anim = ANIM_DANCE
	_anim_rotation_offset = 0.0
	model_anim_player.play(ANIM_DANCE)


func _set_held_gun_visual_visible(show_gun: bool) -> void:
	var hold_point = get_hold_point()
	if hold_point == null:
		return
	for child in hold_point.get_children():
		if child.get("is_held") != null:
			child.visible = show_gun


func play_action_animation(animation_name: String, requested_duration := 0.0) -> void:
	if model_anim_player == null or not model_anim_player.has_animation(animation_name):
		return
	var animation := model_anim_player.get_animation(animation_name)
	var duration := requested_duration if requested_duration > 0.0 else animation.length
	var speed := animation.length / maxf(duration, 0.05)
	_action_animation_time = maxf(duration, 0.05)
	_current_anim = ""
	_play_anim(animation_name, true, speed)


func play_melee_animation(duration := 0.0) -> void:
	play_action_animation(ANIM_MELEE_ATTACK, duration)


func play_throw_animation() -> void:
	play_action_animation(ANIM_THROW, 0.85)


func play_hit_animation() -> void:
	play_action_animation(ANIM_HIT, 0.45)


func _update_action_animation(delta: float) -> void:
	if _action_animation_time <= 0.0:
		return
	_action_animation_time = maxf(_action_animation_time - delta, 0.0)
	if _action_animation_time <= 0.0:
		_current_anim = ""

func _update_aiming(_delta):
	if Input.is_action_just_pressed(input_prefix + "_ads"):
		var camera_item = get_active_item() if active_slot in ["item1", "item2"] else null
		if camera_item != null and camera_item.has_method("is_camera_mode_active") and camera_item.is_camera_mode_active():
			camera_item.cancel_use()
			ads_blend_target = 0.0
			return
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
	if is_online:
		return NetworkManager.peer_name(owner_peer_id)
	if is_player2:
		return GameConfig.player2_name
	return PlayerPrefs.get_setting("player_name")

func get_aim_direction():
	return -$AimPivot/SpringArm3D.global_transform.basis.z

func get_aim_pitch():
	return $AimPivot/SpringArm3D.rotation.x

func _dedicated_hold_point(point_name: String, local_position: Vector3) -> Marker3D:
	var point := $AimPivot.get_node_or_null(point_name) as Marker3D
	if point == null:
		point = Marker3D.new()
		point.name = point_name
		point.position = local_position
		$AimPivot.add_child(point)
	return point

func get_hold_point():
	if NetworkManager.is_dedicated_server():
		return _dedicated_hold_point("DedicatedGunHoldPoint", Vector3(0.0, 0.55, -0.45))
	return $CharacterModel.find_child("GunHoldPoint", true, false)

func get_melee_hold_point():
	if NetworkManager.is_dedicated_server():
		return _dedicated_hold_point("DedicatedMeleeHoldPoint", Vector3(0.0, 0.45, -0.55))
	var melee_point = $CharacterModel.find_child("MeleeHoldPoint", true, false)
	return melee_point if melee_point != null else get_hold_point()

func get_item_hold_point():
	if NetworkManager.is_dedicated_server():
		return _dedicated_hold_point("DedicatedItemHoldPoint", Vector3(0.0, 0.45, -0.35))
	return $CharacterModel.find_child("ItemHoldPoint", true, false)

func get_camera():
	if _intro_active and _intro_camera != null:
		return _intro_camera
	if _spectator != null and _spectator.has_method("get_spectator_camera"):
		return _spectator.get_spectator_camera()
	return $AimPivot/SpringArm3D/Camera3D

func play_match_intro(authored_start: Vector3, duration := 3.0) -> void:
	if not is_locally_controlled() or is_eliminated:
		return
	if AccessibilityManager.reduced_motion_enabled():
		_play_reduced_motion_intro(duration)
		return
	var gameplay_camera: Camera3D = $AimPivot/SpringArm3D/Camera3D
	_intro_active = true
	_intro_camera = Camera3D.new()
	_intro_camera.name = "RoundIntroCamera"
	_intro_camera.fov = gameplay_camera.fov
	get_tree().current_scene.add_child(_intro_camera)
	_intro_camera.global_position = authored_start
	if is_online:
		_intro_camera.make_current()
	var target := global_position + Vector3.UP * 1.1
	var start_offset := authored_start - target
	if Vector2(start_offset.x, start_offset.z).length() < 4.0:
		start_offset += Vector3(0.0, 7.0, -12.0)
	var elapsed := 0.0
	while elapsed < duration and is_instance_valid(_intro_camera):
		var t := clampf(elapsed / maxf(duration, 0.01), 0.0, 1.0)
		var eased := t * t * (3.0 - 2.0 * t)
		var orbit_offset := Basis(Vector3.UP, PI * eased) * start_offset
		var orbit_position := target + orbit_offset
		var settle := clampf((eased - 0.68) / 0.32, 0.0, 1.0)
		_intro_camera.global_position = orbit_position.lerp(gameplay_camera.global_position, settle)
		_intro_camera.look_at(target.lerp(global_position + Vector3.UP * 1.45, settle), Vector3.UP)
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	_intro_active = false
	if is_online:
		gameplay_camera.make_current()
	if _intro_camera != null:
		_intro_camera.queue_free()
	_intro_camera = null

func _play_reduced_motion_intro(duration: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	var fade := ColorRect.new()
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	add_child(layer)
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 0.0, maxf(duration, 0.01))
	await tween.finished
	layer.queue_free()

func apply_knockback(direction: Vector3, distance: float):
	knockback_velocity = direction * (distance / KNOCKBACK_DURATION)
	knockback_timer = KNOCKBACK_DURATION
	is_dashing = false
	is_sprinting = false
	play_hit_animation()

func apply_stagger(duration: float):
	stagger_timer = duration
	is_dashing = false
	is_sprinting = false
	play_hit_animation()

func grant_bullet_immunity(duration: float):
	bullet_immune_timer = max(bullet_immune_timer, duration)

func is_bullet_immune():
	return bullet_immune_timer > 0.0

# Pulsing red/orange surface rim on whoever holds the gun, so the gun holder is
# readable at a glance. Uses material_overlay (independent of flash_hit's
# surface overrides) with normal depth testing — walls hide it, no wallhack.
var _gun_outline_active := false
var _decoy_outline_generation := 0
var _hit_flash_generation := 0
var _hit_flash_restore_entries: Array = []

func _update_gun_holder_outline():
	# The shared material overlay cannot be hidden from only one local
	# splitscreen viewport. Local matches therefore use the per-view GUN HOLDER
	# tag, while online remote puppets keep the extra rim. The holder never sees
	# their own indicator.
	var should_outline := holding_gun and is_online and not _is_local_online \
		and GameConfig.game_mode == GameConfig.MODE_ONE_GUN
	if should_outline == _gun_outline_active:
		return
	_gun_outline_active = should_outline
	var mat: Material = null
	if should_outline:
		mat = CombatOutline.create_gun_holder_rim_material()
	for mesh in _character_outline_meshes():
		mesh.material_overlay = mat

func show_decoy_destroyer_outline(duration: float, decoy_owner = null) -> void:
	if NetworkManager.is_online() and decoy_owner != null:
		var viewer = NetworkManager.find_net_player(NetworkManager.local_id())
		var viewer_is_owner: bool = viewer == decoy_owner
		var viewer_is_teammate := (viewer != null and GameConfig.teams_enabled
			and int(viewer.get("team_id")) >= 0
			and int(viewer.get("team_id")) == int(decoy_owner.get("team_id")))
		if not viewer_is_owner and not viewer_is_teammate:
			return
	_decoy_outline_generation += 1
	var generation := _decoy_outline_generation
	var mat := CombatOutline.create_decoy_reveal_material()
	for mesh in _character_outline_meshes():
		mesh.material_overlay = mat
	await get_tree().create_timer(duration).timeout
	if generation == _decoy_outline_generation:
		_restore_outline_after_temporary_reveal()

func show_overtime_pulse(duration: float = 1.0) -> void:
	_decoy_outline_generation += 1
	var generation := _decoy_outline_generation
	var mat := CombatOutline.create_overtime_reveal_material()
	for mesh in _character_outline_meshes():
		mesh.material_overlay = mat
	await get_tree().create_timer(duration).timeout
	if generation == _decoy_outline_generation:
		_restore_outline_after_temporary_reveal()


func _restore_outline_after_temporary_reveal() -> void:
	# Clear the temporary overlay first. In local play the gun holder does not use
	# a shared mesh rim, so merely toggling the cached gun-outline flag can early
	# return and strand the reveal material on the shooter indefinitely.
	for mesh in _character_outline_meshes():
		mesh.material_overlay = null
	_gun_outline_active = false
	_update_gun_holder_outline()

func flash_hit():
	request_screen_shake(0.18, 0.14)
	if not AccessibilityManager.allow_flash():
		return
	_hit_flash_generation += 1
	var generation := _hit_flash_generation
	_restore_hit_flash_materials()
	var entries: Array = []
	var meshes = _find_mesh_instances($CharacterModel)
	for mesh in meshes:
		if mesh.mesh == null:
			continue
		for surface_index in mesh.mesh.get_surface_count():
			var original = mesh.get_surface_override_material(surface_index)
			var source = original if original != null else mesh.get_active_material(surface_index)
			var flash_material := StandardMaterial3D.new()
			var base_color := Color.WHITE
			if source is StandardMaterial3D:
				flash_material = source.duplicate(true) as StandardMaterial3D
				base_color = source.albedo_color
			flash_material.albedo_color = base_color
			mesh.set_surface_override_material(surface_index, flash_material)
			entries.append({
				"mesh": mesh,
				"surface": surface_index,
				"material": flash_material,
				"original": original,
				"base_color": base_color,
			})
	_hit_flash_restore_entries = entries

	var tween = create_tween()
	for entry in entries:
		tween.parallel().tween_property(entry["material"], "albedo_color", Color.RED, 0.05)
	tween.tween_interval(0.05)
	for entry in entries:
		tween.parallel().tween_property(entry["material"], "albedo_color", entry["base_color"], 0.1)

	await tween.finished
	if generation == _hit_flash_generation:
		_restore_hit_flash_materials()


func _restore_hit_flash_materials() -> void:
	for entry in _hit_flash_restore_entries:
		var mesh = entry.get("mesh")
		var surface := int(entry.get("surface", -1))
		if is_instance_valid(mesh) and mesh.mesh != null \
				and surface >= 0 and surface < mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, entry.get("original"))
	_hit_flash_restore_entries.clear()
	# PlayerV2Visual owns the authoritative per-instance skin bindings. Reapply
	# the selected ID after any temporary hit material so overlapping async
	# flashes cannot strand this mesh on a textureless override.
	var visual := get_node_or_null("CharacterModel")
	if visual != null and visual.has_method("set_skin"):
		visual.set_skin(character_skin_id)

func _find_mesh_instances(node: Node) -> Array:
	var result = []
	if node == null:
		return result
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result


func _character_outline_meshes() -> Array:
	var visual := get_node_or_null("CharacterModel")
	if visual != null and visual.has_method("get_character_mesh_instances"):
		return visual.get_character_mesh_instances()
	return _find_mesh_instances(visual)

func apply_slow(duration: float, multiplier: float):
	slow_timer = duration
	slow_multiplier_value = multiplier

func _active_flash_camera_mode() -> bool:
	var item = get_active_item() if active_slot in ["item1", "item2"] else null
	return item != null and item.has_method("is_camera_mode_active") and item.is_camera_mode_active()

func apply_flash_blind(duration: float) -> void:
	flash_blind_timer = maxf(flash_blind_timer, duration)
	# Treat every successful photo as a fresh presentation pass. Keeping the
	# longer remaining duration avoids a weaker re-flash shortening the effect.
	_flash_blind_total = flash_blind_timer

func _update_flash_blind(delta: float) -> void:
	if flash_blind_timer > 0.0:
		flash_blind_timer = maxf(flash_blind_timer - delta, 0.0)

# --- new powerup state ---
var speed_surge_timer := 0.0
const SPEED_SURGE_MULT := 1.4
var vampire_timer := 0.0
const VAMPIRE_STAMINA_REFUND := 30.0
var second_wind_ready := false
var reach_timer := 0.0
const REACH_PICKUP_RADIUS := 8.0
const REACH_SCAN_INTERVAL := 0.10

func _canonical_powerup_type(power_type: String) -> String:
	match power_type:
		"magnet_hands":
			return "reach"
		"extra_melee_shield":
			return "sticky_hands"
		"second_wind":
			return "extra_life"
		_:
			return power_type

func can_collect_powerup(power_type: String) -> bool:
	match _canonical_powerup_type(power_type):
		"sticky_hands":
			return melee_disarm_shields <= 0
		"extra_life":
			return not second_wind_ready
		"extra_dash":
			return extra_dash_charge <= 0
		_:
			return true

func _extend_timed_powerup(current: float, base_duration: float) -> float:
	if current <= 0.0:
		return base_duration
	return minf(current + base_duration * 0.5, base_duration * 2.0)

func apply_powerup(power_type: String, duration: float) -> bool:
	power_type = _canonical_powerup_type(power_type)
	if not can_collect_powerup(power_type):
		return false
	match power_type:
		"extra_dash":
			extra_dash_charge = 1
		"sticky_hands":
			melee_disarm_shields = 1
		"speed_surge":
			speed_surge_timer = _extend_timed_powerup(speed_surge_timer, duration)
		"silent_steps":
			silent_steps_timer = _extend_timed_powerup(silent_steps_timer, duration)
		"vampire_touch":
			vampire_timer = _extend_timed_powerup(vampire_timer, duration)
		"extra_life":
			second_wind_ready = true
		"reach":
			reach_timer = _extend_timed_powerup(reach_timer, duration)
			_ensure_reach_ring()
		_:
			return false
	active_powerup_order.erase(power_type)
	active_powerup_order.push_front(power_type)
	return true

func get_active_powerups_for_display() -> Array:
	var result = []
	for power_type in active_powerup_order:
		match power_type:
			"extra_dash":
				if extra_dash_charge > 0:
					result.append({"type": power_type, "timed": false, "time_left": 0.0})
			"sticky_hands":
				if melee_disarm_shields > 0:
					result.append({"type": power_type, "timed": false, "time_left": 0.0})
			"speed_surge":
				if speed_surge_timer > 0.0:
					result.append({"type": power_type, "timed": true, "time_left": speed_surge_timer})
			"silent_steps":
				if silent_steps_timer > 0.0:
					result.append({"type": power_type, "timed": true, "time_left": silent_steps_timer})
			"vampire_touch":
				if vampire_timer > 0.0:
					result.append({"type": power_type, "timed": true, "time_left": vampire_timer})
			"extra_life":
				if second_wind_ready:
					result.append({"type": power_type, "timed": false, "time_left": 0.0})
			"reach":
				if reach_timer > 0.0:
					result.append({"type": power_type, "timed": true, "time_left": reach_timer})
	active_powerup_order = result.map(func(entry): return entry["type"])
	return result

func _update_new_powerups(delta: float) -> void:
	if speed_surge_timer > 0.0:
		speed_surge_timer = maxf(speed_surge_timer - delta, 0.0)
	if silent_steps_timer > 0.0:
		silent_steps_timer = maxf(silent_steps_timer - delta, 0.0)
	if vampire_timer > 0.0:
		vampire_timer = maxf(vampire_timer - delta, 0.0)
	if reach_timer > 0.0:
		reach_timer = maxf(reach_timer - delta, 0.0)
		if is_locally_controlled():
			_update_reach_candidates(delta)
	elif not _reach_interactables.is_empty():
		_reach_interactables.clear()
		_rebuild_interactables()
	if _reach_ring != null:
		_reach_ring.visible = reach_timer > 0.0 and not is_eliminated



func activate_double_jump_shoes() -> void:
	if double_jump_shoes_active:
		return
	double_jump_shoes_active = true
	_refresh_double_jump_shoe_visuals()


func clear_double_jump_shoes() -> void:
	double_jump_shoes_active = false
	for attachment in _double_jump_shoe_attachments:
		if is_instance_valid(attachment):
			attachment.queue_free()
	_double_jump_shoe_attachments.clear()


func _refresh_double_jump_shoe_visuals() -> void:
	if not double_jump_shoes_active or not _double_jump_shoe_attachments.is_empty():
		return
	var visual = get_node_or_null("CharacterModel")
	if visual == null:
		return
	var attachments := [
		{"left": true, "scene": "res://models/springShoes/LeftSpringShoe.tscn"},
		{"left": false, "scene": "res://models/springShoes/RightSpringShoe.tscn"},
	]
	for definition in attachments:
		var socket: Node3D = visual.get_foot_socket(bool(definition["left"])) \
			if visual.has_method("get_foot_socket") else null
		if socket == null:
			push_warning("Double Jump Shoes: missing runtime foot socket.")
			continue
		var packed := load(definition["scene"]) as PackedScene
		if packed == null:
			continue
		var shoe := packed.instantiate() as Node3D
		socket.add_child(shoe)
		shoe.position = Vector3.ZERO
		_double_jump_shoe_attachments.append(shoe)


func _request_double_jump_shoes() -> void:
	if not double_jump_shoes_active:
		return
	if NetworkManager.is_online():
		var rm = get_tree().current_scene.get_node_or_null("RoundManager")
		if rm == null:
			return
		if not NetworkManager.is_host():
			_perform_double_jump_shoes()
		rm.request_online_double_jump(int(rm.get("online_round_epoch")))
	else:
		_perform_double_jump_shoes()


func _perform_double_jump_shoes() -> void:
	if not double_jump_shoes_active:
		return
	velocity.y = jump_velocity * GameConfig.DOUBLE_JUMP_SHOE_MULTIPLIER
	clear_double_jump_shoes()
	AudioManager.play_sfx("double_jump_boing")


func confirm_online_double_jump_shoes() -> void:
	# The owning client may already have consumed the charge optimistically.
	if double_jump_shoes_active:
		if is_locally_controlled():
			velocity.y = jump_velocity * GameConfig.DOUBLE_JUMP_SHOE_MULTIPLIER
		clear_double_jump_shoes()
		if is_locally_controlled():
			AudioManager.play_sfx("double_jump_boing")
func clear_all_powerups() -> void:
	speed_surge_timer = 0.0
	silent_steps_timer = 0.0
	vampire_timer = 0.0
	reach_timer = 0.0
	_reach_interactables.clear()
	_rebuild_interactables()
	second_wind_ready = false
	melee_disarm_shields = 0
	extra_dash_charge = 0
	active_powerup_order.clear()

func clear_overtime_protections() -> void:
	# Standard OT preserves earned timed powers and Extra Dash, but removes
	# protection from lethal damage and disarms.
	second_wind_ready = false
	melee_disarm_shields = 0
	active_powerup_order.erase("extra_life")
	active_powerup_order.erase("sticky_hands")

func consume_sticky_hands() -> bool:
	if melee_disarm_shields <= 0:
		return false
	melee_disarm_shields = 0
	active_powerup_order.erase("sticky_hands")
	return true

func consume_extra_life() -> bool:
	if not second_wind_ready:
		return false
	second_wind_ready = false
	active_powerup_order.erase("extra_life")
	lethal_immunity_timer = maxf(lethal_immunity_timer, 1.0)
	return true

func has_active_reach() -> bool:
	return reach_timer > 0.0


func set_local_view_render_layer(render_layer: int) -> void:
	local_view_render_layer = render_layer
	if _reach_ring != null:
		_reach_ring.layers = 1 << (render_layer - 1) if render_layer > 0 else 1


func _ensure_reach_ring() -> void:
	if _reach_ring != null or not is_locally_controlled():
		return
	_reach_ring = MeshInstance3D.new()
	_reach_ring.name = "ReachRadius"
	var ring := TorusMesh.new()
	ring.inner_radius = REACH_PICKUP_RADIUS - 0.07
	ring.outer_radius = REACH_PICKUP_RADIUS
	ring.rings = 64
	ring.ring_segments = 8
	_reach_ring.mesh = ring
	_reach_ring.position.y = 0.06
	_reach_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.15, 1.0, 0.35, 0.82)
	material.emission_enabled = true
	material.emission = Color(0.08, 0.8, 0.25)
	material.emission_energy_multiplier = 1.5
	_reach_ring.material_override = material
	add_child(_reach_ring)
	set_local_view_render_layer(local_view_render_layer)


func _update_reach_candidates(delta: float) -> void:
	_reach_scan_timer -= delta
	if _reach_scan_timer > 0.0:
		return
	_reach_scan_timer = REACH_SCAN_INTERVAL
	var next_candidates: Array = []
	for group_name in ["gun", "melee", "item", "powerup"]:
		for candidate in get_tree().get_nodes_in_group(group_name):
			if candidate == self or not is_instance_valid(candidate) or not candidate is Node3D:
				continue
			if not candidate.visible or global_position.distance_to(candidate.global_position) > REACH_PICKUP_RADIUS:
				continue
			# Pickup types expose different state fields. Godot 4.7.1 rejects
			# bool(null), so only read a state flag when that object owns it.
			if ("is_held" in candidate and candidate.is_held) \
					or ("is_in_flight" in candidate and candidate.is_in_flight) \
					or ("collected" in candidate and candidate.collected):
				continue
			if not VisibilityRules.has_visual_contact(self, candidate):
				continue
			if candidate.is_in_group("powerup"):
				if candidate.has_method("try_collect_for"):
					candidate.try_collect_for(self)
				continue
			next_candidates.append(candidate)
	_reach_interactables = next_candidates
	_rebuild_interactables()

func _on_melee_hit_for_vampire(hitter_name: String) -> void:
	if vampire_timer > 0.0 and hitter_name == get_display_name():
		stamina = minf(stamina + VAMPIRE_STAMINA_REFUND, MAX_STAMINA)

func _start_dash():
	var input_dir = _get_movement_input_dir()
	var dir = ($AimPivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if dir == Vector3.ZERO:
		dir = get_aim_direction()
		dir.y = 0.0
		dir = dir.normalized()
	_dash_cancelled_spring_momentum = _spring_air_active and not is_on_floor()
	if _dash_cancelled_spring_momentum:
		_cancel_spring_launch_for_dash()
	dash_direction = dir
	if dash_charges > 0:
		dash_charges -= 1
	else:
		extra_dash_charge = maxi(extra_dash_charge - 1, 0)
		if extra_dash_charge <= 0:
			active_powerup_order.erase("extra_dash")
	is_dashing = true
	is_sprinting = false
	dash_timer = DASH_DURATION

func _update_dash_recharge(delta):
	if dash_charges < max_dash_charges:
		dash_recharge_timer += delta
		if dash_recharge_timer >= dash_recharge_time:
			dash_charges += 1
			dash_recharge_timer = 0.0

func get_dash_recharge_progress() -> float:
	if dash_charges >= max_dash_charges:
		return 1.0
	return clampf(dash_recharge_timer / maxf(dash_recharge_time, 0.01), 0.0, 1.0)

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
	stamina = clampf(stamina - amount, 0.0, MAX_STAMINA)
	stamina_regen_timer = STAMINA_REGEN_DELAY

func has_stamina():
	return stamina > 0.0

func register_interactable(obj):
	if obj not in _normal_interactables:
		_normal_interactables.append(obj)
	_rebuild_interactables()

func unregister_interactable(obj):
	_normal_interactables.erase(obj)
	_rebuild_interactables()


func _rebuild_interactables() -> void:
	nearby_interactables.clear()
	for obj in _normal_interactables + _reach_interactables:
		if is_instance_valid(obj) and obj not in nearby_interactables:
			nearby_interactables.append(obj)

# Crosshair feedback is stricter than pickup eligibility: the candidate must be
# registered, visible, valid, and be the first collider on the camera ray.
func get_valid_crosshair_interactable():
	var camera: Camera3D = get_camera()
	if camera == null or nearby_interactables.is_empty(): return null
	var center := camera.get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(center)
	var ray_distance := REACH_PICKUP_RADIUS if has_active_reach() else 5.0
	var end := origin + camera.project_ray_normal(center) * ray_distance
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return null
	var collider = hit.get("collider")
	for candidate in nearby_interactables:
		if not is_instance_valid(candidate) or not candidate.is_inside_tree(): continue
		if not candidate.has_method("pick_up"): continue
		if candidate is CanvasItem and not candidate.visible: continue
		if candidate is Node3D and not candidate.visible: continue
		if collider == candidate or (candidate is Node and candidate.is_ancestor_of(collider)) or (collider is Node and collider.is_ancestor_of(candidate)):
			return candidate
	return null


func request_screen_shake(strength: float, duration: float) -> void:
	_camera_shake_strength = maxf(_camera_shake_strength, strength)
	_camera_shake_time = maxf(_camera_shake_time, duration)


func _update_accessible_camera_motion(delta: float) -> void:
	var camera: Camera3D = $AimPivot/SpringArm3D/Camera3D
	var bob_scale := AccessibilityManager.camera_bob_scale()
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horizontal_speed > 0.2 and not PauseManager.is_pause_open():
		_camera_bob_time += delta * (7.0 + horizontal_speed * 0.3)
	else:
		_camera_bob_time = 0.0
	var bob := Vector3(0.0, sin(_camera_bob_time) * 0.035 * bob_scale, 0.0)
	var shake := Vector3.ZERO
	if _camera_shake_time > 0.0:
		_camera_shake_time = maxf(_camera_shake_time - delta, 0.0)
		var strength := _camera_shake_strength * AccessibilityManager.screen_shake_scale() * minf(_camera_shake_time * 12.0, 1.0)
		shake = Vector3(randf_range(-strength, strength), randf_range(-strength, strength), 0.0)
	else:
		_camera_shake_strength = 0.0
	camera.position = _camera_base_position + bob + shake

func _try_interact() -> bool:
	# Every pickup-able object (gun.gd, melee_weapon.gd, item.gd) now decides
	# for itself whether this pickup is allowed to happen instantly (empty
	# slot, or a same-category swap) and returns whether it succeeded. This
	# is what lets e.g. melee_weapon.gd refuse a pickup while the player is
	# holding the gun (see docs/GAME_RULES.md — gun is never tap-swapped
	# away) without the player needing to know every object's rules.
	nearby_interactables = nearby_interactables.filter(func(obj):
		return is_instance_valid(obj) and obj.is_inside_tree() and obj.has_method("pick_up"))
	var ordered := nearby_interactables.duplicate()
	var crosshair_target = get_valid_crosshair_interactable()
	if crosshair_target != null:
		ordered.erase(crosshair_target)
		ordered.push_front(crosshair_target)
	else:
		var camera: Camera3D = get_camera()
		if camera != null:
			var ray_origin: Vector3 = camera.global_position
			var ray_direction: Vector3 = -camera.global_basis.z
			ordered.sort_custom(func(a, b):
				var a_offset: Vector3 = a.global_position - ray_origin
				var b_offset: Vector3 = b.global_position - ray_origin
				var a_score := a_offset.cross(ray_direction).length() + a_offset.length() * 0.02
				var b_score := b_offset.cross(ray_direction).length() + b_offset.length() * 0.02
				return a_score < b_score)
	for obj in ordered:
		if obj.pick_up(self):
			return true
	return false

func _drop_active_slot():
	var committed_item = get_active_item() if active_slot in ["item1", "item2"] else null
	if committed_item != null and committed_item.has_method("is_committed_use") and committed_item.is_committed_use():
		return
	match active_slot:
		"weapon":
			if holding_gun:
				var hold_point = get_hold_point()
				if hold_point.get_child_count() > 0:
					var gun = hold_point.get_child(0)
					if NetworkManager.is_online() and gun.has_method("request_online_drop"):
						gun.request_online_drop()
					else:
						gun.drop()
			elif held_melee_weapon != null:
				if NetworkManager.is_online() and held_melee_weapon.has_method("request_online_drop"):
					held_melee_weapon.request_online_drop()
				else:
					held_melee_weapon.drop()
		"item1":
			if held_item_1 != null:
				if NetworkManager.is_online() and held_item_1.has_method("request_online_drop"):
					held_item_1.request_online_drop()
				else:
					held_item_1.drop()
		"item2":
			if held_item_2 != null:
				if NetworkManager.is_online() and held_item_2.has_method("request_online_drop"):
					held_item_2.request_online_drop()
				else:
					held_item_2.drop()

func can_pick_up_item() -> bool:
	return held_item_1 == null or held_item_2 == null

func assign_item(item_obj) -> void:
	if held_item_1 == null:
		held_item_1 = item_obj
	elif held_item_2 == null:
		held_item_2 = item_obj

func clear_item_slot(item_obj) -> void:
	if held_item_1 == item_obj:
		held_item_1 = null
	elif held_item_2 == item_obj:
		held_item_2 = null

func get_active_item():
	if active_slot == "item1":
		return held_item_1
	if active_slot == "item2":
		return held_item_2
	# Active slot isn't an item slot right now (e.g. weapon is active) —
	# default to the first item slot as the swap target.
	return held_item_1

func _try_primary_action():
	if active_slot == "weapon":
		if holding_gun:
			var hold_point = get_hold_point()
			if hold_point.get_child_count() > 0:
				hold_point.get_child(0).try_fire()
		elif held_melee_weapon != null:
			held_melee_weapon.try_swing()
	elif active_slot == "item1":
		if held_item_1 != null:
			held_item_1.try_throw()
	elif active_slot == "item2":
		if held_item_2 != null:
			held_item_2.try_throw()

func _toggle_active_decoy_control() -> void:
	# Decoy control is a latched mode: one press enables mirroring and the next
	# press releases it. The action is never polled as a held input.
	if active_decoy == null or not is_instance_valid(active_decoy):
		return
	if active_decoy.has_method("request_control_toggle"):
		active_decoy.request_control_toggle(self)
	else:
		active_decoy.toggle_control()

func _consume_local_all_gun_heart() -> bool:
	if all_gun_hearts <= 0:
		return true
	all_gun_hearts -= 1
	if all_gun_hearts > 0:
		lethal_immunity_timer = maxf(
			lethal_immunity_timer, GameConfig.ALL_GUN_HIT_PROTECTION_TIME)
		flash_hit()
		return false
	return true


func eliminate(killer_name = "", weapon_icon = "💀", lethal_kind := "weapon", killer_actor_id: int = -1):
	if is_eliminated:
		return
	_clear_steam_boost()
	if lethal_kind == "weapon" and lethal_immunity_timer > 0.0:
		return
	if not is_online and GameConfig.game_mode == GameConfig.MODE_ONE_OF_US \
			and lethal_kind == "weapon" \
			and not has_meta("one_of_us_elimination_resolution"):
		var round_manager = get_tree().current_scene.get_node_or_null("RoundManager")
		if round_manager != null \
				and round_manager.has_method("try_resolve_local_one_of_us_gun_hit") \
				and round_manager.try_resolve_local_one_of_us_gun_hit(
					self, str(killer_name), killer_actor_id):
			return
	# Extra Life: consume the charge, survive the hit with brief immunity.
	# Online the SERVER resolves Extra Life (round_manager.server_eliminate →
	if not is_online and GameConfig.game_mode == GameConfig.MODE_ALL_GUN \
			and lethal_kind == "weapon":
		if not _consume_local_all_gun_heart():
			return
	elif GameConfig.game_mode == GameConfig.MODE_ALL_GUN \
			and lethal_kind == "environment":
		all_gun_hearts = 0
	# _net_consume_online_second_wind) before broadcasting the elimination; if
	# this local branch also ran, a stale local charge could make the victim
	# survive on their own screen while dead on every other peer.
	if lethal_kind == "weapon" and second_wind_ready and not is_online:
		consume_extra_life()
		if has_method("flash_hit"):
			flash_hit()
		return
	if holding_gun:
		var hold_point = get_hold_point()
		if hold_point != null and hold_point.get_child_count() > 0:
			var held_gun = hold_point.get_child(0)
			if bool(held_gun.get("is_overtime_gun")):
				holding_gun = false
				held_gun.queue_free()
			else:
				held_gun.drop()
	if held_melee_weapon != null:
		held_melee_weapon.drop(true)
	if held_item_1 != null:
		if held_item_1.has_method("discard_on_owner_death"):
			held_item_1.discard_on_owner_death()
		else:
			held_item_1.queue_free()
	if held_item_2 != null:
		if held_item_2.has_method("discard_on_owner_death"):
			held_item_2.discard_on_owner_death()
		else:
			held_item_2.queue_free()
	held_item_1 = null
	held_item_2 = null
	active_decoy = null
	clear_double_jump_shoes()
	clear_all_powerups()
	_elimination_generation += 1
	is_eliminated = true
	if _online_crosshair_layer != null:
		_online_crosshair_layer.visible = false
	velocity = Vector3.ZERO
	CombatPop.spawn(get_tree().current_scene, global_position)
	GameEvents.player_eliminated.emit(get_display_name(), killer_name, weapon_icon)
	GameEvents.actor_eliminated.emit(int(actor_id), killer_actor_id, str(weapon_icon))
	visible = false
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	# Only the machine that owns this player gets a spectator cam. Online, this
	# node also exists as a puppet on every other peer — creating a spectator there
	# would hijack that machine's camera away from its own local player.
	if not ("is_bot" in self and self.is_bot) and _is_local_online:
		_spectator = load("res://spectator_controller.gd").new()
		add_child(_spectator)
		_spectator.setup(self)


func set_transient_spectator_filter(role: String) -> void:
	if _spectator != null and is_instance_valid(_spectator) \
			and _spectator.has_method("set_role_filter"):
		_spectator.set_role_filter(role)

func respawn(spawn_transform):
	_elimination_generation += 1
	_hit_flash_generation += 1
	_restore_hit_flash_materials()
	_apply_character_skin(character_skin_id)
	_victory_dance_active = false
	if _spectator != null and is_instance_valid(_spectator):
		_spectator.cleanup()
		_spectator = null
	# Online the spectator made another camera current (no splitscreen manager
	# to hand it back) — reclaim the view for the local player's own camera.
	if is_online and _is_local_online:
		$AimPivot/SpringArm3D/Camera3D.make_current()
	is_eliminated = false
	if _online_crosshair_layer != null:
		_online_crosshair_layer.visible = false
	# eliminate() disabled physics processing; re-enable it or the respawned
	# player (and its remote puppet) is frozen in place and can never move.
	set_physics_process(true)
	visible = true
	collision_layer = 0
	collision_mask = 0
	set_collision_layer_value(2, true)
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, true)
	# Movement math (see _physics_process) assumes the BODY yaw stays 0 and all
	# look rotation lives on AimPivot — so transfer the spawn marker's yaw to the
	# pivot instead of the body, or WASD axes end up offset from the camera.
	global_transform = Transform3D(Basis(), spawn_transform.origin)
	$AimPivot.rotation = Vector3(0, spawn_transform.basis.get_euler().y, 0)
	$AimPivot/SpringArm3D.rotation.x = 0.0
	velocity = Vector3.ZERO
	_clear_steam_boost()
	_clear_spring_launch_state()
	_dash_cancelled_spring_momentum = false
	stamina = MAX_STAMINA
	stamina_regen_timer = 0.0
	is_sprinting = false
	dash_charges = max_dash_charges
	dash_recharge_timer = 0.0
	extra_dash_charge = 0
	_one_of_us_final_bonus_active = false
	is_dashing = false
	knockback_timer = 0.0
	stagger_timer = 0.0
	bullet_immune_timer = 0.0
	lethal_immunity_timer = 0.0
	clear_double_jump_shoes()
	clear_all_powerups()
	slow_timer = 0.0
	all_gun_hearts = GameConfig.ALL_GUN_MAX_HEARTS \
		if GameConfig.game_mode == GameConfig.MODE_ALL_GUN else 0
	slow_multiplier_value = 1.0
	holding_gun = false
	held_melee_weapon = null
	held_item_1 = null
	held_item_2 = null
	active_slot = "none"
	interact_hold_active = false
	interact_hold_timer = 0.0
	if ads_tween != null and ads_tween.is_valid():
		ads_tween.kill()
	ads_blend = 0.0
	ads_blend_target = 0.0
	_current_anim = ""
	_action_animation_time = 0.0
	_idle_animation_time = 0.0
	if model_anim_player != null:
		model_anim_player.stop()
