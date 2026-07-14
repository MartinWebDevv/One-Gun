extends CharacterBody3D

# Online (set by round_manager's networked spawn function). Local play leaves
# these at defaults and none of the online paths run.
var is_online := false
var net_authority_id := 1
var actor_id := 1
var owner_peer_id := 1
var _is_local_online := true   # true for local play + local-authority online
var _online_name_tag: Label3D = null
var _online_crosshair_layer: CanvasLayer = null

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
const INTERACT_HOLD_DROP_TIME = 0.5
# Grace window for the grounded->airborne ANIMATION switch only. is_on_floor()
# flickers when walking over uneven Terrain3D (the body micro-bounces), which
# would thrash the walk<->jump animation. This debounces it. Purely visual —
# jump gameplay still uses raw is_on_floor().
const AIRBORNE_ANIM_GRACE = 0.12

var holding_gun = false
var held_melee_weapon = null
var held_item_1 = null
var held_item_2 = null
var nearby_interactables = []
var active_slot = "none"  # "none" | "weapon" | "item1" | "item2"

# Tracks whether the current interact press already resolved as an instant
# pickup/swap (in which case holding it longer does nothing) or is still
# eligible to become a hold-to-drop (see _try_interact()).
var interact_hold_active = false
var interact_hold_timer = 0.0

var stamina = MAX_STAMINA
var stamina_regen_timer = 0.0
var is_sprinting = false
var _airborne_grace_timer = 0.0

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

func _enter_tree() -> void:
	if is_online:
		# Replication authority and synchronizer children must exist during
		# MultiplayerSpawner's enter-tree phase. Creating them in _ready() is too
		# late for a remote pending spawn to receive its network ID reliably.
		set_multiplayer_authority(net_authority_id)
		_is_local_online = is_multiplayer_authority()
		_build_net_sync()

func _ready():
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
	GameEvents.melee_hit_landed.connect(_on_melee_hit_for_vampire)
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
	if is_online and _is_local_online and _online_crosshair_layer != null:
		_online_crosshair_layer.visible = holding_gun and active_slot == "weapon" and not is_eliminated
	# Authoritative status timers must tick on every machine, including the
	# host's puppet for a client-owned actor. Keeping this below the puppet
	# early-return made a client's post-melee bullet immunity permanent on the
	# server, so every later bullet was incorrectly ignored.
	if bullet_immune_timer > 0.0:
		bullet_immune_timer = maxf(bullet_immune_timer - delta, 0.0)
	# Remote networked puppets are driven entirely by their MultiplayerSynchronizer
	# (position/rotation/aim); skip all local input + physics so nothing fights it,
	# but still drive their locomotion animation + model facing from the synced
	# velocity/aim so they walk/run instead of sliding in a frozen pose.
	if is_online and not _is_local_online:
		_update_puppet_visuals()
		return

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
			velocity.y -= 9.8 * delta
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
			velocity.y -= 9.8 * delta
		move_and_slide()
		_update_stamina(delta)
		_update_dash_recharge(delta)
		_update_new_powerups(delta)
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
		if speed_surge_timer > 0.0:
			current_speed *= SPEED_SURGE_MULT

		var input_dir = _get_movement_input_dir()
		var direction = ($AimPivot.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		if direction:
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
		else:
			velocity.x = move_toward(velocity.x, 0, current_speed)
			velocity.z = move_toward(velocity.z, 0, current_speed)

		_update_animation(input_dir)

	var _desired_h_vel := Vector3(velocity.x, 0, velocity.z)
	move_and_slide()
	_try_step_up(_desired_h_vel, delta)
	_update_footsteps(delta)
	_update_stamina(delta)
	_update_dash_recharge(delta)
	_update_new_powerups(delta)
	_update_facing()

# One footstep sound per stride while grounded and moving; cadence follows
# sprint state. silent_steps powerup mutes them without breaking cadence.
var footstep_timer := 0.0
var silent_steps_timer := 0.0

func _update_footsteps(delta: float) -> void:
	if silent_steps_timer > 0.0:
		silent_steps_timer -= delta
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or is_dashing or hspeed < 2.0:
		footstep_timer = 0.12  # small re-arm so the first step lands naturally
		return
	footstep_timer -= delta
	if footstep_timer <= 0.0:
		if silent_steps_timer <= 0.0:
			AudioManager.play_sfx("footstep")
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
		hold_point.get_child(0).visible = (active_slot == "weapon" and holding_gun)

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
	var cfg := SceneReplicationConfig.new()
	for prop in [".:position", ".:rotation", "AimPivot:rotation", "AimPivot/SpringArm3D:rotation", ".:velocity", ".:stamina"]:
		cfg.add_property(NodePath(prop))
	sync.replication_config = cfg
	sync.set_multiplayer_authority(net_authority_id)
	add_child(sync)
	# Puppets play idle so they read as a standing character while sliding to
	# their synced positions (walk-anim sync is a later-phase polish).
	if not _is_local_online:
		call_deferred("_play_puppet_idle")

# Minimal center crosshair (dot + 4 short bars) for the local online player.
# The real HUD is stripped in online free-roam; full HUD comes in Phase 2b.
func _build_online_crosshair() -> void:
	var layer := CanvasLayer.new()
	_online_crosshair_layer = layer
	layer.name = "OnlineCrosshair"
	layer.layer = 20
	layer.visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var col := Color(1, 1, 1, 0.85)
	var gap := 5.0
	var length := 9.0
	var thick := 2.0
	# center dot
	root.add_child(_make_crosshair_bar(4.0, 4.0, 0.0, 0.0, col))
	# four bars around the gap
	root.add_child(_make_crosshair_bar(length, thick, -(gap + length * 0.5), 0.0, col))
	root.add_child(_make_crosshair_bar(length, thick, gap + length * 0.5, 0.0, col))
	root.add_child(_make_crosshair_bar(thick, length, 0.0, -(gap + length * 0.5), col))
	root.add_child(_make_crosshair_bar(thick, length, 0.0, gap + length * 0.5, col))
	add_child(layer)

func _make_crosshair_bar(w: float, h: float, ox: float, oy: float, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.5
	r.anchor_top = 0.5
	r.anchor_right = 0.5
	r.anchor_bottom = 0.5
	r.offset_left = ox - w * 0.5
	r.offset_top = oy - h * 0.5
	r.offset_right = ox + w * 0.5
	r.offset_bottom = oy + h * 0.5
	return r

func _build_online_name_tag() -> void:
	_online_name_tag = Label3D.new()
	_online_name_tag.name = "OnlineNameTag"
	_online_name_tag.position = Vector3(0.0, 2.35, 0.0)
	_online_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_online_name_tag.no_depth_test = true
	_online_name_tag.font_size = 32
	_online_name_tag.outline_size = 8
	_online_name_tag.modulate = Color(0.9, 0.95, 1.0)
	_online_name_tag.visible = not _is_local_online
	add_child(_online_name_tag)
	_update_online_name_tag()
	if not NetworkManager.lobby_changed.is_connected(_update_online_name_tag):
		NetworkManager.lobby_changed.connect(_update_online_name_tag)

func _update_online_name_tag() -> void:
	if _online_name_tag != null:
		_online_name_tag.text = get_display_name()

func _play_puppet_idle() -> void:
	if model_anim_player != null and model_anim_player.has_animation(ANIM_IDLE):
		model_anim_player.play(ANIM_IDLE)

# Remote puppet: pick idle/walk/run (and pistol variants) from the synced velocity
# so it animates while the synchronizer slides it to position; face the synced aim.
func _update_puppet_visuals() -> void:
	if model_anim_player != null and not is_eliminated:
		var speed := Vector2(velocity.x, velocity.z).length()
		if speed > (SPEED + SPRINT_SPEED) * 0.5:
			_play_anim(ANIM_RUN_PISTOL if holding_gun else ANIM_RUN)
		elif speed > 0.6:
			_play_anim(ANIM_WALK_PISTOL if holding_gun else ANIM_WALK)
		elif holding_gun:
			_play_anim(ANIM_IDLE_PISTOL)
		else:
			_play_anim(ANIM_IDLE)
	_update_facing()

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

func _is_grounded_for_anim() -> bool:
	# Debounced grounded check for animation only — see AIRBORNE_ANIM_GRACE.
	return _airborne_grace_timer > 0.0

func _update_animation(input_dir: Vector2):
	var is_moving = input_dir.length() > 0.1

	if not _is_grounded_for_anim():
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
	if is_online:
		return NetworkManager.peer_name(owner_peer_id)
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

# --- new powerup state ---
var speed_surge_timer := 0.0
const SPEED_SURGE_MULT := 1.4
var vampire_timer := 0.0
const VAMPIRE_STAMINA_REFUND := 30.0
var second_wind_ready := false
var magnet_timer := 0.0
const MAGNET_RADIUS := 4.0
const MAGNET_PULL_SPEED := 6.0
var _magnet_area: Area3D = null
var _online_magnet_request_timer := 0.0

func apply_powerup(power_type: String, duration: float):
	match power_type:
		"extra_dash":
			if dash_bonus_timer <= 0.0:
				dash_charges += 1
			dash_bonus_timer = duration
		"extra_melee_shield":
			melee_disarm_shields = 1
		"speed_surge":
			speed_surge_timer = duration
		"silent_steps":
			silent_steps_timer = duration
		"vampire_touch":
			vampire_timer = duration
		"second_wind":
			second_wind_ready = true
		"magnet_hands":
			magnet_timer = duration
			_ensure_magnet_area()
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
			"speed_surge":
				if speed_surge_timer > 0.0:
					result.append({"type": power_type, "timed": true, "time_left": speed_surge_timer})
			"silent_steps":
				if silent_steps_timer > 0.0:
					result.append({"type": power_type, "timed": true, "time_left": silent_steps_timer})
			"vampire_touch":
				if vampire_timer > 0.0:
					result.append({"type": power_type, "timed": true, "time_left": vampire_timer})
			"second_wind":
				if second_wind_ready:
					result.append({"type": power_type, "timed": false, "time_left": 0.0})
			"magnet_hands":
				if magnet_timer > 0.0:
					result.append({"type": power_type, "timed": true, "time_left": magnet_timer})
	active_powerup_order = result.map(func(entry): return entry["type"])
	return result

func _update_new_powerups(delta: float) -> void:
	if speed_surge_timer > 0.0:
		speed_surge_timer -= delta
	if vampire_timer > 0.0:
		vampire_timer -= delta
	if magnet_timer > 0.0:
		magnet_timer -= delta
		_magnet_pull(delta)

func _ensure_magnet_area() -> void:
	if _magnet_area != null:
		return
	_magnet_area = Area3D.new()
	_magnet_area.name = "MagnetArea"
	_magnet_area.collision_layer = 0
	_magnet_area.set_collision_mask_value(3, true)  # pickups live on layer 4 (bit 3)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = MAGNET_RADIUS
	col.shape = shape
	_magnet_area.add_child(col)
	add_child(_magnet_area)

func _magnet_pull(delta: float) -> void:
	if _magnet_area == null:
		return
	if NetworkManager.is_online():
		_online_magnet_request_timer -= delta
		if _online_magnet_request_timer <= 0.0 and is_multiplayer_authority():
			_online_magnet_request_timer = 0.1
			var rm = get_tree().current_scene.get_node_or_null("RoundManager")
			if rm != null:
				rm.request_online_magnet_pull(actor_id)
		return
	for body in _magnet_area.get_overlapping_bodies():
		if body == self or not (body is RigidBody3D):
			continue
		if not body.has_method("get_interact_category"):
			continue
		if "is_held" in body and body.is_held:
			continue
		var to_me := global_position + Vector3(0, 0.4, 0) - body.global_position
		if to_me.length() > 1.1:
			body.global_position += to_me.normalized() * MAGNET_PULL_SPEED * delta

func _on_melee_hit_for_vampire(hitter_name: String) -> void:
	if vampire_timer > 0.0 and hitter_name == get_display_name():
		stamina = minf(stamina + VAMPIRE_STAMINA_REFUND, MAX_STAMINA)

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

func _try_interact() -> bool:
	# Every pickup-able object (gun.gd, melee_weapon.gd, item.gd) now decides
	# for itself whether this pickup is allowed to happen instantly (empty
	# slot, or a same-category swap) and returns whether it succeeded. This
	# is what lets e.g. melee_weapon.gd refuse a pickup while the player is
	# holding the gun (see docs/GAME_RULES.md — gun is never tap-swapped
	# away) without the player needing to know every object's rules.
	for obj in nearby_interactables:
		if not obj.has_method("pick_up"):
			continue
		if obj.pick_up(self):
			return true
	return false

func _drop_active_slot():
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

func eliminate(killer_name = "", weapon_icon = "💀"):
	if is_eliminated:
		return
	# Second Wind: consume the charge, survive the hit with brief immunity.
	# Online the SERVER resolves Second Wind (round_manager.server_eliminate →
	# _net_consume_online_second_wind) before broadcasting the elimination; if
	# this local branch also ran, a stale local charge could make the victim
	# survive on their own screen while dead on every other peer.
	if second_wind_ready and not is_online:
		second_wind_ready = false
		grant_bullet_immunity(2.0)
		if has_method("flash_hit"):
			flash_hit()
		return
	if holding_gun:
		var hold_point = get_hold_point()
		if hold_point != null and hold_point.get_child_count() > 0:
			hold_point.get_child(0).drop()
	if held_melee_weapon != null:
		held_melee_weapon.drop(true)
	if held_item_1 != null:
		if NetworkManager.is_online() and held_item_1.has_method("force_online_drop_at"):
			held_item_1.force_online_drop_at(global_position + Vector3(0.3, 0.6, 0.0))
		else:
			held_item_1.drop()
	if held_item_2 != null:
		if NetworkManager.is_online() and held_item_2.has_method("force_online_drop_at"):
			held_item_2.force_online_drop_at(global_position + Vector3(-0.3, 0.6, 0.0))
		else:
			held_item_2.drop()
	is_eliminated = true
	if _online_crosshair_layer != null:
		_online_crosshair_layer.visible = false
	velocity = Vector3.ZERO
	play_death()
	GameEvents.player_eliminated.emit(get_display_name(), killer_name, weapon_icon)
	if model_anim_player != null and model_anim_player.has_animation(ANIM_DEATH):
		await model_anim_player.animation_finished
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

func respawn(spawn_transform):
	if _spectator != null and is_instance_valid(_spectator):
		_spectator.cleanup()
		_spectator = null
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
	if model_anim_player != null:
		model_anim_player.stop()
