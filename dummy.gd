extends CharacterBody3D

const ProtectionIconFactory = preload("res://protection_icon_factory.gd")

# Online bots are spawned on every peer, but only peer 1 (the host) runs AI
# and physics.  Clients receive a lightweight puppet through NetSync.
var is_online := false
var net_authority_id := 1
var actor_id := -1
var owner_peer_id := 1
var online_display_name := "Bot"
var _is_online_authority := true
var _online_name_tag: Label3D = null
var _extra_life_icon: Sprite3D = null
var _sticky_hands_icon: Sprite3D = null
var _friendly_indicator: Label3D = null

@export_enum("easy", "medium", "hard", "expert") var ai_difficulty := "easy"
@export var arrive_distance := 1.0
@export var melee_range := 2.0
@export var is_bot := true
@export var team_id := -1
@export var dash_recharge_time := 3.0

const KNOCKBACK_DURATION = 0.2
const BASE_MOVE_SPEED := 3.0
const BASE_FIRE_COOLDOWN_MIN := 1.5
const BASE_FIRE_COOLDOWN_MAX := 2.5

const MAX_STAMINA := 100.0
const STAMINA_REGEN_RATE := 20.0
const STAMINA_REGEN_DELAY := 1.5

const DASH_SPEED := 28.0
const DASH_DURATION := 0.18
const DASH_RECHARGE_TIME := 3.0
const MAX_DASH_CHARGES := 2
const BASE_GRAVITY := 9.8
const NAV_PATH_HEIGHT_OFFSET := 1.0

const ITEM_THROW_RANGE_EASY    := 999.0
const ITEM_THROW_RANGE_MEDIUM  := 12.0
const ITEM_THROW_RANGE_HARD    := 999.0
const ITEM_THROW_RANGE_EXPERT  := 999.0

const TIER_PROFILES = {
	"easy": {
		"reaction_time_min": 0.4,
		"reaction_time_max": 0.8,
		"gun_shoot_cone_degrees": 12.0,
		"move_speed_mult": 0.85,
		"fire_cooldown_mult": 1.2,
		"can_retreat": false,
		"prefers_melee_tier": false,
		"can_dash": false,
		"dash_defensive": false,
		"dash_aggressive": false,
	},
	"medium": {
		"reaction_time_min": 0.25,
		"reaction_time_max": 0.45,
		"gun_shoot_cone_degrees": 6.0,
		"move_speed_mult": 1.0,
		"fire_cooldown_mult": 1.0,
		"can_retreat": false,
		"prefers_melee_tier": false,
		"can_dash": true,
		"dash_defensive": true,
		"dash_aggressive": false,
	},
	"hard": {
		"reaction_time_min": 0.1,
		"reaction_time_max": 0.2,
		"gun_shoot_cone_degrees": 2.5,
		"move_speed_mult": 1.1,
		"fire_cooldown_mult": 0.85,
		"can_retreat": true,
		"prefers_melee_tier": false,
		"can_dash": true,
		"dash_defensive": true,
		"dash_aggressive": true,
	},
	"expert": {
		"reaction_time_min": 0.05,
		"reaction_time_max": 0.12,
		"gun_shoot_cone_degrees": 0.5,
		"move_speed_mult": 1.15,
		"fire_cooldown_mult": 0.7,
		"can_retreat": true,
		"prefers_melee_tier": true,
		"can_dash": true,
		"dash_defensive": true,
		"dash_aggressive": true,
	},
}

const RETREAT_ENTER_STAMINA := 20.0
const RETREAT_EXIT_STAMINA := 50.0

var reaction_time_min := 0.3
var reaction_time_max := 0.6
var gun_shoot_cone_degrees := 0.0
var move_speed := BASE_MOVE_SPEED
var fire_cooldown_min := BASE_FIRE_COOLDOWN_MIN
var fire_cooldown_max := BASE_FIRE_COOLDOWN_MAX
var can_retreat := false
var prefers_melee_tier := false
var can_dash := false
var dash_defensive := false
var dash_aggressive := false

var holding_gun = false
var held_melee_weapon = null
var held_item = null
var nearby_interactables = []
var stamina = MAX_STAMINA
var stamina_regen_timer := 0.0
var is_eliminated = false

# -- Animation --
const ANIM_SOURCE_GLB  = "res://models/playerAnimations/Dance.glb"
const ANIM_IDLE        = "idle"
const ANIM_IDLE_PISTOL = "idle_pistol"
const ANIM_WALK        = "walk"
const ANIM_WALK_PISTOL = "walk_pistol"
const ANIM_DEATH       = "death"

const ANIM_INDICES = {
	ANIM_IDLE:        0,
	ANIM_IDLE_PISTOL: 2,
	ANIM_WALK:        3,
	ANIM_WALK_PISTOL: 5,
	ANIM_DEATH:       9,
}

var model_anim_player: AnimationPlayer = null
var _current_anim: String = ""

var target_player = null
var fire_cooldown = 0.0
var movement_target_position = null

var current_objective_type = "idle"
var reaction_timer = 0.0
var is_retreating = false
var next_path_point: Vector3 = Vector3.ZERO
var has_line_of_sight = false

var knockback_velocity = Vector3.ZERO
var knockback_timer = 0.0
var stagger_timer = 0.0
var bullet_immune_timer = 0.0
var lethal_immunity_timer = 0.0

var melee_disarm_shields = 0
var slow_timer = 0.0
var slow_multiplier_value = 1.0

var dash_charges := MAX_DASH_CHARGES
var dash_recharge_timer := 0.0
var is_dashing := false
var dash_timer := 0.0
var dash_velocity := Vector3.ZERO
var dash_cooldown := 0.0
var extra_dash_charge := 0

var item_throw_cooldown := 0.0

var active_powerup_order: Array = []
var magnet_timer := 0.0
var silent_steps_timer := 0.0
const MAGNET_RADIUS := 4.0
const MAGNET_PULL_SPEED := 6.0
var _magnet_area: Area3D = null
var _online_magnet_request_timer := 0.0
var _steam_boost_active := false
var _steam_fast_fall_started := false
var _steam_boost_origin_y := 0.0
var _steam_descent_height_gate := 0.0
var _steam_descent_gravity_multiplier := 1.0

func _enter_tree() -> void:
	if is_online:
		set_multiplayer_authority(net_authority_id)
		_is_online_authority = is_multiplayer_authority()
		_build_net_sync()

func _ready():
	add_to_group("combat_target")
	_apply_tier_profile()
	GameEvents.melee_hit_landed.connect(func(hitter_name):
		if vampire_timer > 0.0 and hitter_name == get_display_name():
			stamina = minf(stamina + 30.0, MAX_STAMINA)
	)
	var nav_agent: NavigationAgent3D = $NavigationAgent3D
	nav_agent.path_desired_distance = 0.8
	# Baked floor points sit roughly one metre above the CharacterBody origin.
	# Offset returned path points to the body's movement plane so the agent can
	# recognize reached waypoints and continue through the complete path.
	nav_agent.path_height_offset = NAV_PATH_HEIGHT_OFFSET
	nav_agent.target_desired_distance = arrive_distance
	var model_node = get_node_or_null("new guy one gun model orange running")
	if model_node != null:
		model_anim_player = model_node.find_child("AnimationPlayer", true, false)
		if model_anim_player != null:
			_merge_animations()
	if model_anim_player == null:
		push_warning("Dummy: AnimationPlayer not found.")
	if is_online:
		# Neutralize the map's root scale so online bots are the same size as
		# online humans (character_body_3d.gd does the identical fix).
		var cs = get_tree().current_scene
		var ms: float = cs.scale.x if cs is Node3D and cs.scale.x != 0.0 else 1.0
		scale = Vector3.ONE / ms
		_build_online_name_tag()
	if not is_online and GameConfig.bot_count < 1:
		remove_from_group("player")
		visible = false
		set_physics_process(false)

func _build_net_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "NetSync"
	var cfg := SceneReplicationConfig.new()
	for prop in [".:position", ".:rotation", ".:velocity", ".:stamina"]:
		cfg.add_property(NodePath(prop))
	sync.replication_config = cfg
	sync.set_multiplayer_authority(net_authority_id)
	add_child(sync)

func _build_online_name_tag() -> void:
	var viewer = NetworkManager.find_net_player(NetworkManager.local_id())
	var friendly := viewer != null and GameConfig.teams_enabled \
		and int(viewer.get("team_id")) >= 0 and int(viewer.get("team_id")) == team_id
	_online_name_tag = Label3D.new()
	_online_name_tag.name = "OnlineNameTag"
	_online_name_tag.position = Vector3(0.0, 2.6, 0.0)
	_online_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_online_name_tag.no_depth_test = false
	_online_name_tag.font_size = 32 if friendly else 38
	_online_name_tag.outline_size = 8
	_online_name_tag.modulate = Color(0.25, 0.85, 1.0) if friendly else Color(1.0, 0.2, 0.2)
	_online_name_tag.visibility_range_end = 50.0
	_online_name_tag.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_online_name_tag.text = get_display_name()
	add_child(_online_name_tag)
	_friendly_indicator = Label3D.new()
	_friendly_indicator.text = "◆"
	_friendly_indicator.position = Vector3(0.0, 2.87, 0.0)
	_friendly_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_friendly_indicator.no_depth_test = true
	_friendly_indicator.font_size = 22
	_friendly_indicator.outline_size = 7
	_friendly_indicator.modulate = Color(0.2, 0.95, 1.0)
	_friendly_indicator.visible = friendly
	add_child(_friendly_indicator)
	_extra_life_icon = _make_protection_icon(
		"res://UI/icons/extra_life.svg", Vector3(-0.28, 3.03, 0.0))
	_sticky_hands_icon = _make_protection_icon(
		"res://UI/icons/sticky_hands.svg", Vector3(0.28, 3.03, 0.0))

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
	var icon_size := clampf(float(PlayerPrefs.get_setting("protection_icon_size")), 0.5, 2.0)
	_extra_life_icon.scale = Vector3.ONE * icon_size
	_sticky_hands_icon.scale = Vector3.ONE * icon_size
	_extra_life_icon.modulate = _pref_color("extra_life_icon_color", Color(1.0, 0.72, 0.18))
	_sticky_hands_icon.modulate = _pref_color("sticky_hands_icon_color", Color(0.2, 1.0, 0.35))
	_extra_life_icon.visible = second_wind_ready and not is_eliminated
	_sticky_hands_icon.visible = melee_disarm_shields > 0 and not is_eliminated

func _apply_tier_profile():
	var profile = TIER_PROFILES.get(ai_difficulty, TIER_PROFILES["easy"])
	reaction_time_min  = profile["reaction_time_min"]
	reaction_time_max  = profile["reaction_time_max"]
	if reaction_time_min > reaction_time_max:
		var tmp = reaction_time_min
		reaction_time_min = reaction_time_max
		reaction_time_max = tmp
	gun_shoot_cone_degrees = profile["gun_shoot_cone_degrees"]
	move_speed             = BASE_MOVE_SPEED * profile["move_speed_mult"]
	fire_cooldown_min      = BASE_FIRE_COOLDOWN_MIN * profile["fire_cooldown_mult"]
	fire_cooldown_max      = BASE_FIRE_COOLDOWN_MAX * profile["fire_cooldown_mult"]
	can_retreat            = profile["can_retreat"]
	prefers_melee_tier     = profile["prefers_melee_tier"]
	can_dash               = profile["can_dash"]
	dash_defensive         = profile["dash_defensive"]
	dash_aggressive        = profile["dash_aggressive"]

# ============================================================
# Animation
# ============================================================

func _merge_animations():
	if not model_anim_player.has_animation_library(""):
		model_anim_player.add_animation_library("", AnimationLibrary.new())
	var lib = model_anim_player.get_animation_library("")

	var packed = load(ANIM_SOURCE_GLB)
	if packed == null:
		push_warning("Dummy AnimationMerge: could not load '%s'" % ANIM_SOURCE_GLB)
		return
	var instance = packed.instantiate()
	var source_player = instance.find_child("AnimationPlayer", true, false)
	if source_player == null:
		instance.queue_free()
		push_warning("Dummy AnimationMerge: no AnimationPlayer in source GLB")
		return

	var source_list = source_player.get_animation_list()
	for anim_name in ANIM_INDICES:
		var idx = ANIM_INDICES[anim_name]
		if idx >= source_list.size():
			continue
		if not lib.has_animation(anim_name):
			var anim = source_player.get_animation(source_list[idx])
			var final_anim = anim.duplicate()
			if anim_name == ANIM_DEATH:
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
		return
	_current_anim = anim_name
	model_anim_player.play(anim_name)

func _update_animation():
	var is_moving = Vector2(velocity.x, velocity.z).length() > 0.5
	if is_moving:
		if holding_gun:
			_play_anim(ANIM_WALK_PISTOL)
		else:
			_play_anim(ANIM_WALK)
	else:
		if holding_gun:
			_play_anim(ANIM_IDLE_PISTOL)
		else:
			_play_anim(ANIM_IDLE)

func _stop_movement_animation():
	if holding_gun:
		_play_anim(ANIM_IDLE_PISTOL)
	else:
		_play_anim(ANIM_IDLE)

# ============================================================
# Physics
# ============================================================

func _physics_process(delta):
	# Before the puppet early-return so remote copies also show the outline.
	_update_gun_holder_outline()
	_update_protection_icons()
	if bullet_immune_timer > 0.0:
		bullet_immune_timer = maxf(bullet_immune_timer - delta, 0.0)
	if lethal_immunity_timer > 0.0:
		lethal_immunity_timer = maxf(lethal_immunity_timer - delta, 0.0)
	if speed_surge_timer > 0.0:
		speed_surge_timer -= delta
	if vampire_timer > 0.0:
		vampire_timer -= delta
	if magnet_timer > 0.0:
		magnet_timer = maxf(magnet_timer - delta, 0.0)
		_magnet_pull(delta)
	if silent_steps_timer > 0.0:
		silent_steps_timer = maxf(silent_steps_timer - delta, 0.0)

	if is_online and not _is_online_authority:
		_update_online_puppet_visuals()
		return
	if _steam_boost_active and is_on_floor():
		_clear_steam_boost()

	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_multiplier_value = 1.0

	if is_eliminated:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	_update_stamina(delta)
	_update_dash_recharge(delta)

	if not is_on_floor():
		_apply_air_gravity(delta)
	else:
		velocity.y = 0

	if stagger_timer > 0.0:
		stagger_timer -= delta
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	if knockback_timer > 0.0:
		knockback_timer -= delta
		velocity.x = knockback_velocity.x
		velocity.z = knockback_velocity.z
		move_and_slide()
		return

	if is_dashing:
		dash_timer -= delta
		velocity.x = dash_velocity.x
		velocity.z = dash_velocity.z
		if dash_timer <= 0.0:
			is_dashing = false
		move_and_slide()
		return

	_update_target()
	_decide_objective(delta)
	_move_toward_objective()
	_update_facing()
	_update_animation()
	if reaction_timer <= 0.0:
		_try_auto_pickup()
	_update_combat(delta)
	_update_item_behavior(delta)
	if can_dash:
		_update_dash_behavior(delta)

	var _desired_h_vel := Vector3(velocity.x, 0, velocity.z)
	move_and_slide()
	_try_step_up(_desired_h_vel, delta)


func apply_steam_boost(launch_velocity: float, launch_origin_y: float,
		descent_height_gate: float, descent_gravity_multiplier: float) -> void:
	velocity.y = maxf(velocity.y, launch_velocity)
	_steam_boost_active = true
	_steam_fast_fall_started = false
	_steam_boost_origin_y = launch_origin_y
	_steam_descent_height_gate = maxf(descent_height_gate, 0.0)
	_steam_descent_gravity_multiplier = maxf(descent_gravity_multiplier, 1.0)


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

# Walk straight over knee-height ledges without jumping - kept in sync by hand
# with character_body_3d.gd's _try_step_up (bots are a separate controller).
const STEP_HEIGHT := 0.55
const STEP_FORWARD_PROBE := 0.25

func _try_step_up(desired_h_vel: Vector3, delta: float) -> void:
	if not is_on_floor():
		return
	var h := Vector3(desired_h_vel.x, 0, desired_h_vel.z)
	if h.length_squared() < 0.04:
		return
	var dir := h.normalized()
	# low steps don't set is_on_wall on a capsule; scan slide collisions
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
	params.from = global_transform
	params.motion = Vector3.UP * STEP_HEIGHT
	var up_dist := STEP_HEIGHT
	if PhysicsServer3D.body_test_motion(get_rid(), params, result):
		up_dist = result.get_travel().y
	if up_dist < 0.03:
		return
	var raised := global_transform
	raised.origin.y += up_dist
	var fwd := dir * maxf(h.length() * delta, STEP_FORWARD_PROBE)
	params.from = raised
	params.motion = fwd
	if PhysicsServer3D.body_test_motion(get_rid(), params, result):
		if result.get_travel().length() < fwd.length() * 0.5:
			return
	var fwd_pos := raised
	fwd_pos.origin += fwd
	params.from = fwd_pos
	params.motion = Vector3.DOWN * (up_dist + 0.1)
	if not PhysicsServer3D.body_test_motion(get_rid(), params, result):
		return
	if result.get_collision_normal().angle_to(Vector3.UP) > floor_max_angle:
		return
	var step_h := up_dist + result.get_travel().y
	if step_h <= 0.01 or step_h > STEP_HEIGHT:
		return
	global_position.y += step_h + 0.02

# ============================================================
# Stamina
# ============================================================

func _update_stamina(delta):
	if stamina_regen_timer > 0.0:
		stamina_regen_timer -= delta
		return
	if stamina < MAX_STAMINA:
		stamina = min(stamina + STAMINA_REGEN_RATE * delta, MAX_STAMINA)

func drain_stamina(amount):
	stamina = clampf(stamina - amount, 0.0, MAX_STAMINA)
	stamina_regen_timer = STAMINA_REGEN_DELAY

func has_stamina():
	return stamina > 0.0

# ============================================================
# Dash
# ============================================================

func _update_dash_recharge(delta):
	if dash_cooldown > 0.0:
		dash_cooldown -= delta
	if dash_charges < MAX_DASH_CHARGES:
		dash_recharge_timer += delta
		if dash_recharge_timer >= dash_recharge_time:
			dash_charges += 1
			dash_recharge_timer = 0.0

func get_dash_recharge_progress() -> float:
	if dash_charges >= MAX_DASH_CHARGES:
		return 1.0
	return clampf(dash_recharge_timer / maxf(dash_recharge_time, 0.01), 0.0, 1.0)

func _update_dash_behavior(delta):
	if (dash_charges <= 0 and extra_dash_charge <= 0) or dash_cooldown > 0.0 or target_player == null:
		return

	var to_target = target_player.global_position - global_position
	to_target.y = 0
	var dist = to_target.length()

	match ai_difficulty:
		"medium":
			if holding_gun and dist < 4.0:
				_execute_dash(-to_target.normalized())
		"hard":
			if holding_gun and dist < 4.0:
				_execute_dash(-to_target.normalized())
			elif not holding_gun and held_melee_weapon != null and dist < melee_range * 1.5:
				if randf() < 0.3:
					_execute_dash(to_target.normalized())
		"expert":
			if holding_gun and dist < 4.0:
				_execute_dash(-to_target.normalized())
			elif not holding_gun and held_melee_weapon != null:
				if dist < melee_range * 1.2:
					_execute_dash(to_target.normalized())
				elif dist < 6.0 and has_line_of_sight:
					if randf() < 0.5:
						_execute_dash(to_target.normalized())

func _execute_dash(direction: Vector3):
	if direction.length() < 0.01:
		return
	dash_velocity = direction.normalized() * DASH_SPEED
	dash_timer = DASH_DURATION
	if dash_charges > 0:
		dash_charges -= 1
	else:
		extra_dash_charge = 0
		active_powerup_order.erase("extra_dash")
	dash_cooldown = 0.8
	is_dashing = true

# ============================================================
# Item behavior
# ============================================================

func _update_item_behavior(delta):
	if item_throw_cooldown > 0.0:
		item_throw_cooldown -= delta
		return
	if held_item == null or target_player == null:
		return
	if not held_item.has_method("try_throw"):
		return

	var to_target = target_player.global_position - global_position
	var dist = to_target.length()
	var should_throw := false

	match ai_difficulty:
		"easy":
			should_throw = randf() < 0.02
		"medium":
			should_throw = dist <= ITEM_THROW_RANGE_MEDIUM
		"hard":
			var guns = get_tree().get_nodes_in_group("gun")
			if guns.size() > 0 and guns[0].is_held:
				var holder = guns[0].player_ref
				if holder != null and holder != self:
					should_throw = global_position.distance_to(holder.global_position) < 20.0
		"expert":
			var guns = get_tree().get_nodes_in_group("gun")
			var holder_dist = INF
			if guns.size() > 0 and guns[0].is_held and guns[0].player_ref != self:
				holder_dist = global_position.distance_to(guns[0].player_ref.global_position)
			should_throw = (holder_dist < 15.0) or (dist < 5.0 and not target_player.holding_gun)

	if should_throw:
		held_item.try_throw()
		item_throw_cooldown = 2.0

# ============================================================
# Objective / navigation
# ============================================================

func _update_target():
	var players = get_tree().get_nodes_in_group("combat_target")
	var closest = null
	var closest_dist = INF
	for p in players:
		if p == self:
			continue
		if "is_eliminated" in p and p.is_eliminated:
			continue
		if not GameConfig.can_affect(self, p):
			continue
		if p.has_method("can_be_affected_by") and not p.can_be_affected_by(self):
			continue
		var dist = global_position.distance_to(p.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = p
	target_player = closest

func _decide_objective(delta):
	var new_target_pos = null
	var new_type = "idle"

	_update_retreat_state()

	if is_retreating and target_player != null:
		new_target_pos = _get_retreat_position()
		new_type = "retreat"
	elif holding_gun:
		if target_player != null:
			new_target_pos = _get_gunner_position()
			new_type = "gunner_position"
	else:
		var guns = get_tree().get_nodes_in_group("gun")
		if guns.size() > 0:
			var gun_node = guns[0]
			if not gun_node.is_held:
				new_target_pos = gun_node.global_position
				new_type = "get_gun"
			elif held_melee_weapon == null and held_item == null:
				var best_melee = _find_best_melee_weapon()
				var best_powerup = _find_nearest_powerup()
				if best_melee != null and best_powerup != null:
					var md = global_position.distance_to(best_melee.global_position)
					var pd = global_position.distance_to(best_powerup.global_position)
					if pd < md * 0.6:
						new_target_pos = best_powerup.global_position
						new_type = "get_powerup"
					else:
						new_target_pos = best_melee.global_position
						new_type = "get_melee"
				elif best_melee != null:
					new_target_pos = best_melee.global_position
					new_type = "get_melee"
				elif best_powerup != null:
					new_target_pos = best_powerup.global_position
					new_type = "get_powerup"
			elif held_item != null and target_player != null:
				new_target_pos = _get_approach_position(target_player.global_position)
				new_type = "use_item"
			elif held_melee_weapon != null:
				if target_player != null:
					new_target_pos = _get_approach_position(target_player.global_position)
					new_type = "chase_target"

	if new_type != current_objective_type:
		current_objective_type = new_type
		reaction_timer = randf_range(reaction_time_min, reaction_time_max)

	if reaction_timer > 0.0:
		reaction_timer -= delta
		return

	movement_target_position = new_target_pos

func _find_nearest_powerup() -> Node:
	var powerups = get_tree().get_nodes_in_group("powerup")
	var closest = null
	var closest_dist = INF
	for pu in powerups:
		if not pu.visible or bool(pu.get("collected")):
			continue
		var dist = global_position.distance_to(pu.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = pu
	return closest

const GUNNER_IDEAL_RANGE := 10.0
const GUNNER_TOO_CLOSE := 5.0
var _strafe_angle := 0.0
var _strafe_direction := 1.0

func _get_gunner_position() -> Vector3:
	var to_target = target_player.global_position - global_position
	to_target.y = 0
	var dist = to_target.length()

	_strafe_angle += get_physics_process_delta_time() * 0.8 * _strafe_direction
	if _strafe_angle > PI or _strafe_angle < -PI:
		_strafe_direction *= -1.0
		_strafe_angle = clamp(_strafe_angle, -PI, PI)

	var to_target_norm = to_target.normalized() if dist > 0.01 else -global_transform.basis.z
	var lateral = to_target_norm.cross(Vector3.UP).normalized()

	if dist < GUNNER_TOO_CLOSE:
		return global_position - to_target_norm * 3.0
	elif dist > GUNNER_IDEAL_RANGE:
		return global_position + to_target_norm * 2.0 + lateral * _strafe_direction
	else:
		return global_position + lateral * _strafe_direction * 2.0

var _approach_offset_timer := 0.0
var _approach_offset := Vector3.ZERO

func _get_approach_position(target_pos: Vector3) -> Vector3:
	_approach_offset_timer -= get_physics_process_delta_time()
	if _approach_offset_timer <= 0.0:
		_approach_offset_timer = randf_range(0.8, 1.5)
		var right = (target_pos - global_position).cross(Vector3.UP).normalized()
		_approach_offset = right * randf_range(-2.5, 2.5)
	return target_pos + _approach_offset

func _update_retreat_state():
	if not can_retreat:
		is_retreating = false
		return
	if is_retreating:
		if stamina >= RETREAT_EXIT_STAMINA:
			is_retreating = false
	else:
		if stamina < RETREAT_ENTER_STAMINA:
			is_retreating = true

func _get_retreat_position() -> Vector3:
	var away_from_threat = global_position - target_player.global_position
	away_from_threat.y = 0
	if away_from_threat.length() < 0.01:
		away_from_threat = -global_transform.basis.z
	return global_position + away_from_threat.normalized() * 5.0

func _find_best_melee_weapon():
	var melees = get_tree().get_nodes_in_group("melee")
	var available = []
	for m in melees:
		if m.is_held or m.is_in_flight or not m.visible:
			continue
		available.append(m)
	if available.size() == 0:
		return null
	if not prefers_melee_tier:
		var closest = null
		var closest_dist = INF
		for m in available:
			var dist = global_position.distance_to(m.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = m
		return closest
	var best = null
	var best_score = -INF
	for m in available:
		var dist = global_position.distance_to(m.global_position)
		var tier_value = m.tier if "tier" in m else 1
		var score = float(tier_value) * 3.0 - dist
		if score > best_score:
			best_score = score
			best = m
	return best

const NAV_TARGET_UPDATE_INTERVAL := 0.2
var _nav_update_timer := 0.0

func _move_toward_objective():
	if reaction_timer > 0.0 or movement_target_position == null:
		velocity.x = 0
		velocity.z = 0
		_stop_movement_animation()
		return

	var dist_to_final = global_position.distance_to(movement_target_position)
	if dist_to_final < arrive_distance:
		velocity.x = 0
		velocity.z = 0
		_stop_movement_animation()
		return

	var nav_agent: NavigationAgent3D = $NavigationAgent3D

	_nav_update_timer -= get_physics_process_delta_time()
	if _nav_update_timer <= 0.0:
		_nav_update_timer = NAV_TARGET_UPDATE_INTERVAL
		var snapped_target = _snap_to_navmesh(movement_target_position, nav_agent)
		nav_agent.target_position = snapped_target

	if nav_agent.is_navigation_finished():
		velocity.x = 0
		velocity.z = 0
		_stop_movement_animation()
		return

	next_path_point = nav_agent.get_next_path_position()
	var to_next = next_path_point - global_position
	to_next.y = 0

	if to_next.length() < 0.05:
		velocity.x = 0
		velocity.z = 0
		_stop_movement_animation()
		return

	var dir = to_next.normalized()
	var speed = move_speed * slow_multiplier_value
	if speed_surge_timer > 0.0:
		speed *= SPEED_SURGE_MULT
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

func _snap_to_navmesh(point: Vector3, nav_agent: NavigationAgent3D) -> Vector3:
	var map = nav_agent.get_navigation_map()
	if map == RID():
		return point
	return NavigationServer3D.map_get_closest_point(map, point)

const FACING_SMOOTH_SPEED := 8.0
var _smoothed_face_point: Vector3 = Vector3.ZERO
var _has_smoothed_face_point := false

func _update_facing():
	var face_point = null
	if movement_target_position != null and reaction_timer <= 0.0:
		var dist = global_position.distance_to(movement_target_position)
		if dist >= arrive_distance:
			face_point = next_path_point
	if face_point == null and target_player != null:
		face_point = target_player.global_position

	if face_point == null:
		return

	if not _has_smoothed_face_point:
		_smoothed_face_point = face_point
		_has_smoothed_face_point = true
	else:
		var t = clamp(FACING_SMOOTH_SPEED * get_physics_process_delta_time(), 0.0, 1.0)
		_smoothed_face_point = _smoothed_face_point.lerp(face_point, t)

	var dir = _smoothed_face_point - global_position
	dir.y = 0
	if dir.length() > 0.01:
		look_at(global_position + dir, Vector3.UP)

# ============================================================
# Pickup
# ============================================================

func _try_auto_pickup():
	if nearby_interactables.size() == 0:
		return
	if not holding_gun:
		for obj in nearby_interactables:
			if obj.is_in_group("gun"):
				obj.pick_up(self)
				return
	if held_melee_weapon == null and not holding_gun:
		for obj in nearby_interactables:
			var category = obj.get_interact_category() if obj.has_method("get_interact_category") else "weapon"
			if category == "weapon":
				obj.pick_up(self)
				return
	if held_item == null:
		for obj in nearby_interactables:
			var category = obj.get_interact_category() if obj.has_method("get_interact_category") else "weapon"
			if category == "item":
				obj.pick_up(self)
				return

# ============================================================
# Combat
# ============================================================

func _update_combat(delta):
	if target_player == null:
		return
	_update_line_of_sight()
	if holding_gun:
		if not has_line_of_sight:
			return
		fire_cooldown -= delta
		if fire_cooldown <= 0.0:
			var hold_point = get_hold_point()
			if hold_point.get_child_count() > 0:
				hold_point.get_child(0).try_fire()
			fire_cooldown = randf_range(fire_cooldown_min, fire_cooldown_max)
	elif held_melee_weapon != null:
		var dist = global_position.distance_to(target_player.global_position)
		if dist <= melee_range:
			held_melee_weapon.try_swing()

func _update_line_of_sight():
	has_line_of_sight = false
	if target_player == null:
		return
	var from = global_position + Vector3.UP * 0.5
	var to = target_player.global_position + Vector3.UP * 0.5
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid(), target_player.get_rid()]
	query.collision_mask = 1
	var result = space_state.intersect_ray(query)
	has_line_of_sight = result.is_empty()

# ============================================================
# Interactable registration
# ============================================================

func register_interactable(obj):
	if obj not in nearby_interactables:
		nearby_interactables.append(obj)

func unregister_interactable(obj):
	nearby_interactables.erase(obj)

# ============================================================
# Accessors
# ============================================================

func get_hold_point():
	return $GunHoldPoint

func get_melee_hold_point():
	var melee_point = get_node_or_null("MeleeHoldPoint")
	return melee_point if melee_point != null else $GunHoldPoint

func get_item_hold_point():
	return $ItemHoldPoint

func get_display_name() -> String:
	if is_online:
		return online_display_name
	return name

func _update_online_puppet_visuals() -> void:
	if model_anim_player == null or is_eliminated:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 0.6:
		_play_anim(ANIM_WALK_PISTOL if holding_gun else ANIM_WALK)
	else:
		_play_anim(ANIM_IDLE_PISTOL if holding_gun else ANIM_IDLE)

func get_aim_direction():
	if target_player == null:
		return -global_transform.basis.z
	return (target_player.global_position - global_position).normalized()

func get_gun_fire_direction() -> Vector3:
	var true_direction = get_aim_direction()
	if gun_shoot_cone_degrees <= 0.0:
		return true_direction
	return _apply_cone_spread(true_direction, gun_shoot_cone_degrees)

func _apply_cone_spread(direction: Vector3, max_angle_degrees: float) -> Vector3:
	var max_angle_radians = deg_to_rad(max_angle_degrees)
	var arbitrary = Vector3.UP
	if abs(direction.dot(arbitrary)) > 0.99:
		arbitrary = Vector3.RIGHT
	var perpendicular_axis = direction.cross(arbitrary).normalized()
	var spread_axis = perpendicular_axis.rotated(direction, randf_range(0.0, TAU))
	var spread_angle = randf_range(0.0, max_angle_radians)
	return direction.rotated(spread_axis, spread_angle)

func get_aim_pitch():
	return 0.0

func get_camera():
	return null

# ============================================================
# Effects received
# ============================================================

func apply_knockback(direction: Vector3, distance: float):
	knockback_velocity = direction * (distance / KNOCKBACK_DURATION)
	knockback_timer = KNOCKBACK_DURATION

func apply_stagger(duration: float):
	stagger_timer = duration

func grant_bullet_immunity(duration: float):
	bullet_immune_timer = max(bullet_immune_timer, duration)

func is_bullet_immune():
	return bullet_immune_timer > 0.0

func apply_slow(duration: float, multiplier: float):
	slow_timer = duration
	slow_multiplier_value = multiplier

var speed_surge_timer := 0.0
const SPEED_SURGE_MULT := 1.4
var vampire_timer := 0.0
var second_wind_ready := false

func _canonical_powerup_type(power_type: String) -> String:
	match power_type:
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
	active_powerup_order.erase(power_type)
	active_powerup_order.push_front(power_type)
	match power_type:
		"sticky_hands":
			melee_disarm_shields = 1
		"extra_dash":
			extra_dash_charge = 1
		"speed_surge":
			speed_surge_timer = _extend_timed_powerup(speed_surge_timer, duration)
		"vampire_touch":
			vampire_timer = _extend_timed_powerup(vampire_timer, duration)
		"extra_life":
			second_wind_ready = true
		"magnet_hands":
			magnet_timer = _extend_timed_powerup(magnet_timer, duration)
			_ensure_magnet_area()
		"silent_steps":
			silent_steps_timer = _extend_timed_powerup(silent_steps_timer, duration)
		_:
			active_powerup_order.erase(power_type)
			return false
	return true

func clear_all_powerups() -> void:
	speed_surge_timer = 0.0
	vampire_timer = 0.0
	magnet_timer = 0.0
	silent_steps_timer = 0.0
	second_wind_ready = false
	melee_disarm_shields = 0
	extra_dash_charge = 0
	active_powerup_order.clear()

func _ensure_magnet_area() -> void:
	if _magnet_area != null:
		return
	_magnet_area = Area3D.new()
	_magnet_area.name = "MagnetArea"
	_magnet_area.collision_layer = 0
	_magnet_area.set_collision_mask_value(3, true)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = MAGNET_RADIUS
	collision.shape = shape
	_magnet_area.add_child(collision)
	add_child(_magnet_area)

func _magnet_pull(delta: float) -> void:
	if _magnet_area == null:
		return
	if NetworkManager.is_online():
		_online_magnet_request_timer -= delta
		if _online_magnet_request_timer <= 0.0 and multiplayer.is_server():
			_online_magnet_request_timer = 0.1
			var rm = get_tree().current_scene.get_node_or_null("RoundManager")
			if rm != null:
				rm.request_online_magnet_pull(actor_id)
		return
	for body in _magnet_area.get_overlapping_bodies():
		if not body is RigidBody3D or not body.has_method("get_interact_category"):
			continue
		if "is_held" in body and body.is_held:
			continue
		var to_bot := global_position + Vector3.UP * 0.4 - body.global_position
		if to_bot.length() > 1.1:
			body.global_position += to_bot.normalized() * MAGNET_PULL_SPEED * delta

func clear_overtime_protections() -> void:
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

func can_pick_up_item() -> bool:
	return held_item == null

func assign_item(item_obj) -> void:
	held_item = item_obj

func clear_item_slot(item_obj) -> void:
	if held_item == item_obj:
		held_item = null

func get_active_item():
	return held_item

# ============================================================
# Visual
# ============================================================

# Red inverted-hull outline while this bot holds the gun (matches the player
# version in character_body_3d.gd — material_overlay, depth-tested, no wallhack).
var _gun_outline_active := false
var _decoy_outline_generation := 0

func _update_gun_holder_outline():
	if holding_gun == _gun_outline_active:
		return
	_gun_outline_active = holding_gun
	var mat: StandardMaterial3D = null
	if holding_gun:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.95, 0.12, 0.12)
		mat.grow = true
		mat.grow_amount = 0.02
		mat.cull_mode = BaseMaterial3D.CULL_FRONT
	# Scope to the character model only — _find_mesh_instances(self) would also
	# sweep the held gun's meshes and leave a stale overlay on it after a drop.
	var model = get_node_or_null("new guy one gun model orange running")
	for mesh in _find_mesh_instances(model if model != null else self):
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
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.05, 0.05)
	mat.grow = true
	mat.grow_amount = 0.025
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.no_depth_test = true
	var model = get_node_or_null("new guy one gun model orange running")
	for mesh in _find_mesh_instances(model if model != null else self):
		mesh.material_overlay = mat
	await get_tree().create_timer(duration).timeout
	if generation == _decoy_outline_generation:
		_gun_outline_active = not holding_gun
		_update_gun_holder_outline()

func show_overtime_pulse(duration: float = 1.0) -> void:
	_decoy_outline_generation += 1
	var generation := _decoy_outline_generation
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.03, 0.03)
	mat.grow = true
	mat.grow_amount = 0.03
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.no_depth_test = true
	var model = get_node_or_null("new guy one gun model orange running")
	for mesh in _find_mesh_instances(model if model != null else self):
		mesh.material_overlay = mat
	await get_tree().create_timer(duration).timeout
	if generation == _decoy_outline_generation:
		_gun_outline_active = not holding_gun
		_update_gun_holder_outline()

func flash_hit():
	if not AccessibilityManager.allow_flash():
		return
	var meshes = _find_mesh_instances(self)
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

# ============================================================
# Round lifecycle
# ============================================================

func eliminate(killer_name = "", weapon_icon = "💀", lethal_kind := "weapon"):
	if is_eliminated:
		return
	_clear_steam_boost()
	if lethal_kind == "weapon" and lethal_immunity_timer > 0.0:
		return
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
	if held_item != null:
		if held_item.has_method("discard_on_owner_death"):
			held_item.discard_on_owner_death()
		else:
			held_item.queue_free()
	held_item = null
	clear_all_powerups()
	is_eliminated = true
	_current_anim = ""
	CombatPop.spawn(get_tree().current_scene, global_position)
	visible = false
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	GameEvents.player_eliminated.emit(get_display_name(), killer_name, weapon_icon)

func respawn(spawn_transform):
	is_eliminated = false
	_current_anim = ""
	if model_anim_player != null:
		model_anim_player.stop()
	visible = true
	collision_layer = 0
	collision_mask = 0
	set_collision_layer_value(2, true)
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, true)
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	_clear_steam_boost()
	stamina = MAX_STAMINA
	stamina_regen_timer = 0.0
	holding_gun = false
	held_melee_weapon = null
	held_item = null
	nearby_interactables.clear()
	target_player = null
	fire_cooldown = 0.0
	movement_target_position = null
	current_objective_type = "idle"
	reaction_timer = 0.0
	is_retreating = false
	knockback_timer = 0.0
	stagger_timer = 0.0
	bullet_immune_timer = 0.0
	lethal_immunity_timer = 0.0
	clear_all_powerups()
	slow_timer = 0.0
	slow_multiplier_value = 1.0
	dash_charges = MAX_DASH_CHARGES
	extra_dash_charge = 0
	dash_recharge_timer = 0.0
	is_dashing = false
	dash_cooldown = 0.0
	item_throw_cooldown = 0.0
	_approach_offset_timer = 0.0
	_approach_offset = Vector3.ZERO
	_strafe_angle = 0.0
