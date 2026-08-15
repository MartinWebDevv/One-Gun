extends CharacterBody3D

const CombatOutline = preload("res://combat_outline.gd")

const ProtectionIconFactory = preload("res://protection_icon_factory.gd")
const VisibilityRules = preload("res://combat_visibility.gd")
const HitboxDebug = preload("res://hitbox_debug_visual.gd")
const OneOfUsRoleVisualScript = preload("res://one_of_us_role_visual.gd")

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
var _gun_holder_arrow: Label3D = null
var _all_gun_hearts_label: Label3D = null

@export_enum("easy", "medium", "hard", "expert") var ai_difficulty := "easy"
@export var arrive_distance := 1.0
@export var melee_range := 2.0
@export var is_bot := true
@export var team_id := -1
@export var dash_recharge_time := 3.0

const KNOCKBACK_DURATION = 0.2
const BASE_MOVE_SPEED := 10.0
const SPRINT_SPEED := 18.0
const SPRINT_DRAIN_RATE := 25.0
const BASE_FIRE_COOLDOWN_MIN := 1.5
const BASE_FIRE_COOLDOWN_MAX := 2.5

const MAX_STAMINA := 100.0
const STAMINA_REGEN_RATE := 20.0
const STAMINA_REGEN_DELAY := 1.5

const DASH_SPEED := 30.0
const DASH_DURATION := 0.2
const DASH_RECHARGE_TIME := 3.0
const MAX_DASH_CHARGES := 3
const BASE_GRAVITY := 9.8
const NAV_PATH_HEIGHT_OFFSET := 1.0
const SPRING_AIR_CONTROL := 0.60

const ITEM_THROW_RANGE_EASY    := 10.0
const ITEM_THROW_RANGE_MEDIUM  := 12.0
const ITEM_THROW_RANGE_HARD    := 20.0
const ITEM_THROW_RANGE_EXPERT  := 15.0

const TIER_PROFILES = {
	"easy": {
		"reaction_time_min": 0.55,
		"reaction_time_max": 0.85,
		"gun_shoot_cone_degrees": 10.0,
		"move_speed_mult": 1.0,
		"fire_cooldown_mult": 1.2,
		"can_retreat": false,
		"can_dash": true,
		"dash_defensive": false,
		"dash_aggressive": false,
		"decision_min": 1.5, "decision_max": 2.5, "commitment": 1.0,
		"memory": 1.0, "blind_fire": 0.05, "fire_margin": 1.5,
		"reload_min": 0.4, "reload_max": 0.7,
	},
	"medium": {
		"reaction_time_min": 0.35,
		"reaction_time_max": 0.55,
		"gun_shoot_cone_degrees": 6.0,
		"move_speed_mult": 1.0,
		"fire_cooldown_mult": 1.0,
		"can_retreat": false,
		"can_dash": true,
		"dash_defensive": true,
		"dash_aggressive": false,
		"decision_min": 1.0, "decision_max": 1.75, "commitment": 0.75,
		"memory": 1.8, "blind_fire": 0.2, "fire_margin": 1.0,
		"reload_min": 0.2, "reload_max": 0.45,
	},
	"hard": {
		"reaction_time_min": 0.2,
		"reaction_time_max": 0.35,
		"gun_shoot_cone_degrees": 3.0,
		"move_speed_mult": 1.0,
		"fire_cooldown_mult": 0.85,
		"can_retreat": true,
		"can_dash": true,
		"dash_defensive": true,
		"dash_aggressive": true,
		"decision_min": 0.6, "decision_max": 1.2, "commitment": 0.5,
		"memory": 2.8, "blind_fire": 0.4, "fire_margin": 0.65,
		"reload_min": 0.1, "reload_max": 0.3,
	},
	"expert": {
		"reaction_time_min": 0.12,
		"reaction_time_max": 0.25,
		"gun_shoot_cone_degrees": 1.5,
		"move_speed_mult": 1.0,
		"fire_cooldown_mult": 0.7,
		"can_retreat": true,
		"can_dash": true,
		"dash_defensive": true,
		"dash_aggressive": true,
		"decision_min": 0.35, "decision_max": 0.8, "commitment": 0.35,
		"memory": 4.0, "blind_fire": 0.62, "fire_margin": 0.35,
		"reload_min": 0.05, "reload_max": 0.2,
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
var can_dash := false
var dash_defensive := false
var dash_aggressive := false
var decision_time_min := 1.0
var decision_time_max := 1.75
var target_commitment_duration := 0.75
var target_memory_duration := 1.8
var blind_fire_chance := 0.2
var fire_safety_margin := 1.0
var reload_hesitation_min := 0.2
var reload_hesitation_max := 0.45

var holding_gun = false
var held_melee_weapon = null
var held_item = null
var nearby_interactables = []
var _normal_interactables: Array = []
var _reach_interactables: Array = []
var _reach_scan_timer := 0.0
var _body_hitbox_debug: HitboxDebugVisual = null
var stamina = MAX_STAMINA
var stamina_regen_timer := 0.0
var is_eliminated = false
var double_jump_shoes_active := false
var all_gun_hearts := 0
var one_of_us_role := ""
var _one_of_us_visual: Node3D = null
var _double_jump_shoe_attachments: Array[Node] = []
var _one_of_us_final_bonus_active := false

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
var flash_blind_timer := 0.0
var _flash_blind_total := 0.0
var _hit_flash_generation := 0
var _hit_flash_restore_entries: Array = []

var max_dash_charges := MAX_DASH_CHARGES
var dash_charges := MAX_DASH_CHARGES
var dash_recharge_timer := 0.0
var is_dashing := false
var dash_timer := 0.0
var dash_velocity := Vector3.ZERO
var dash_cooldown := 0.0
var extra_dash_charge := 0
var _dash_cancelled_spring_momentum := false

var item_throw_cooldown := 0.0
var item_throw_decision_timer := 0.0
var is_sprinting := false
var _target_commitment_timer := 0.0
var _objective_decision_timer := 0.0
var _last_known_target_position := Vector3.ZERO
var _target_memory_timer := 0.0
var _post_reload_hesitation := 0.0
var _gun_was_reloading := false
var _fire_escape_committed := false
var _fire_safe_timer := 0.0
var _bot_footstep_timer := 0.0

var active_powerup_order: Array = []
var reach_timer := 0.0
var silent_steps_timer := 0.0
const REACH_PICKUP_RADIUS := 8.0
const REACH_SCAN_INTERVAL := 0.10
var _steam_boost_active := false
var _steam_fast_fall_started := false
var _steam_boost_origin_y := 0.0
var _steam_descent_height_gate := 0.0
var _steam_descent_gravity_multiplier := 1.0
var _spring_air_active := false
var _spring_direction_window := 0.0
var _spring_horizontal_boost := 4.0
var _spring_boost_committed := false
const DIRECTIONAL_LAUNCH_OPPOSING_MOMENTUM_RETENTION := 0.25
const DIRECTIONAL_LAUNCH_MIN_STREAM_RATIO := 0.40
var _directional_launch_active := false
var _directional_launch_direction := Vector3.ZERO
var _directional_launch_min_forward_speed := 0.0

func _enter_tree() -> void:
	if is_online:
		set_multiplayer_authority(net_authority_id)
		_is_online_authority = is_multiplayer_authority()
		_build_spawn_visibility_sync()
		_build_net_sync()


func is_locally_controlled() -> bool:
	return not is_online or _is_online_authority


func set_one_of_us_role(role: String) -> void:
	one_of_us_role = role if role in ["us", "them"] else ""
	max_dash_charges = GameConfig.ONE_OF_US_THEM_DASH_CHARGES \
		if one_of_us_role == "them" else GameConfig.ONE_OF_US_US_DASH_CHARGES
	max_dash_charges = clampi(max_dash_charges, 0, 6)
	dash_charges = max_dash_charges if one_of_us_role == "them" \
		else mini(dash_charges, max_dash_charges)
	if _one_of_us_visual == null:
		_one_of_us_visual = OneOfUsRoleVisualScript.new()
		_one_of_us_visual.name = "OneOfUsRoleVisual"
		add_child(_one_of_us_visual)
	_one_of_us_visual.set_infected(one_of_us_role == "them")



func play_one_of_us_transformation() -> void:
	if _one_of_us_visual != null and _one_of_us_visual.has_method("play_transformation"):
		_one_of_us_visual.play_transformation()

func set_one_of_us_final_us(active: bool) -> void:
	if active and one_of_us_role == "us" and not _one_of_us_final_bonus_active:
		extra_dash_charge = maxi(extra_dash_charge, 1)
	_one_of_us_final_bonus_active = active and one_of_us_role == "us"
func _ready():
	add_to_group("combat_target")
	_body_hitbox_debug = HitboxDebug.new()
	_body_hitbox_debug.name = "BodyHitboxDebug"
	add_child(_body_hitbox_debug)
	_body_hitbox_debug.setup($CollisionShape3D, Color(0.05, 0.9, 1.0, 0.18))
	max_dash_charges = clampi(GameConfig.max_dash_charges, 0, 6)
	dash_charges = max_dash_charges
	_apply_tier_profile()
	GameEvents.melee_hit_landed.connect(func(hitter_name):
		if vampire_timer > 0.0 and hitter_name == get_display_name():
			stamina = minf(stamina + 30.0, MAX_STAMINA)
	)
	if not GameEvents.combat_noise.is_connected(_on_combat_noise):
		GameEvents.combat_noise.connect(_on_combat_noise)
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
	sync.public_visibility = false
	sync.add_visibility_filter(Callable(NetworkManager,
		"is_gameplay_replication_visible_to_peer"))
	var cfg := SceneReplicationConfig.new()
	for prop in [".:position", ".:rotation", ".:velocity", ".:stamina"]:
		cfg.add_property(NodePath(prop))
	sync.replication_config = cfg
	sync.set_multiplayer_authority(net_authority_id)
	for connected_peer in multiplayer.get_peers():
		var connected_id := int(connected_peer)
		sync.set_visibility_for(connected_id,
			NetworkManager.is_gameplay_replication_visible_to_peer(connected_id))
	add_child(sync)
	sync.update_visibility()


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
	_gun_holder_arrow = Label3D.new()
	_gun_holder_arrow.text = "\u25bc  GUN HOLDER  \u25bc"
	_gun_holder_arrow.position = Vector3(0.0, 3.33, 0.0)
	_gun_holder_arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_gun_holder_arrow.no_depth_test = false
	_gun_holder_arrow.font_size = CombatOutline.GUN_HOLDER_MARKER_FONT_SIZE
	_gun_holder_arrow.outline_size = CombatOutline.GUN_HOLDER_MARKER_OUTLINE_SIZE
	_gun_holder_arrow.modulate = Color(1.0, 0.08, 0.08)
	_gun_holder_arrow.visible = false
	add_child(_gun_holder_arrow)
	_all_gun_hearts_label = Label3D.new()
	_all_gun_hearts_label.name = "AllGunWorldHearts"
	_all_gun_hearts_label.position = Vector3(0.0, 3.33, 0.0)
	_all_gun_hearts_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_all_gun_hearts_label.no_depth_test = false
	_all_gun_hearts_label.font_size = 34
	_all_gun_hearts_label.outline_size = 9
	_all_gun_hearts_label.modulate = Color(1.0, 0.14, 0.2)
	_all_gun_hearts_label.visibility_range_end = 50.0
	_all_gun_hearts_label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_all_gun_hearts_label.visible = false
	add_child(_all_gun_hearts_label)

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
		_online_name_tag.visible = perception_visible and not is_eliminated
		_online_name_tag.no_depth_test = friendly or spectator_view
	if _friendly_indicator != null:
		_friendly_indicator.visible = friendly and not is_eliminated
	var icon_size := clampf(float(PlayerPrefs.get_setting("protection_icon_size")), 0.5, 2.0)
	_extra_life_icon.scale = Vector3.ONE * icon_size
	_sticky_hands_icon.scale = Vector3.ONE * icon_size
	_extra_life_icon.modulate = _pref_color("extra_life_icon_color", Color(1.0, 0.72, 0.18))
	_sticky_hands_icon.modulate = _pref_color("sticky_hands_icon_color", Color(0.2, 1.0, 0.35))
	_extra_life_icon.visible = perception_visible and second_wind_ready and not is_eliminated
	_sticky_hands_icon.visible = perception_visible and melee_disarm_shields > 0 and not is_eliminated
	if _gun_holder_arrow != null:
		_gun_holder_arrow.visible = viewer != null and holding_gun and not is_eliminated \
			and GameConfig.game_mode == GameConfig.MODE_ONE_GUN \
			and VisibilityRules.has_visual_contact(viewer, self, true)
		if _gun_holder_arrow.visible:
			var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) \
				* CombatOutline.GUN_HOLDER_MARKER_PULSE_AMOUNT
			_gun_holder_arrow.scale = Vector3.ONE * pulse

	if _all_gun_hearts_label != null:
		var show_all_gun_hearts := GameConfig.game_mode == GameConfig.MODE_ALL_GUN \
			and not is_eliminated and perception_visible
		_all_gun_hearts_label.visible = show_all_gun_hearts
		if show_all_gun_hearts:
			var remaining := clampi(all_gun_hearts, 0, 3)
			_all_gun_hearts_label.text = "\u2665".repeat(remaining) + "\u2661".repeat(3 - remaining)
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
	can_dash               = profile["can_dash"]
	dash_defensive         = profile["dash_defensive"]
	dash_aggressive        = profile["dash_aggressive"]
	decision_time_min      = profile["decision_min"]
	decision_time_max      = profile["decision_max"]
	target_commitment_duration = profile["commitment"]
	target_memory_duration = profile["memory"]
	blind_fire_chance      = profile["blind_fire"]
	fire_safety_margin     = profile["fire_margin"]
	reload_hesitation_min  = profile["reload_min"]
	reload_hesitation_max  = profile["reload_max"]

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
	if flash_blind_timer > 0.0:
		flash_blind_timer = maxf(flash_blind_timer - delta, 0.0)
	if speed_surge_timer > 0.0:
		speed_surge_timer -= delta
	if vampire_timer > 0.0:
		vampire_timer -= delta
	if reach_timer > 0.0:
		reach_timer = maxf(reach_timer - delta, 0.0)
		if not is_online or _is_online_authority:
			_update_reach_candidates(delta)
	elif not _reach_interactables.is_empty():
		_reach_interactables.clear()
		_rebuild_interactables()
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
	_target_commitment_timer = maxf(_target_commitment_timer - delta, 0.0)
	_target_memory_timer = maxf(_target_memory_timer - delta, 0.0)
	_objective_decision_timer = maxf(_objective_decision_timer - delta, 0.0)
	_post_reload_hesitation = maxf(_post_reload_hesitation - delta, 0.0)

	if not is_on_floor():
		_apply_air_gravity(delta)
		if double_jump_shoes_active and velocity.y <= 1.5:
			_request_double_jump_shoes()
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
		if _dash_cancelled_spring_momentum:
			velocity.y = 0.0
		velocity.x = dash_velocity.x
		velocity.z = dash_velocity.z
		if dash_timer <= 0.0:
			is_dashing = false
			_dash_cancelled_spring_momentum = false
		move_and_slide()
		return

	_update_target(delta)
	_update_line_of_sight()
	_decide_objective(delta)
	var pre_spring_horizontal := Vector3(velocity.x, 0.0, velocity.z)
	_move_toward_objective()
	if _spring_air_active and not is_on_floor():
		_spring_direction_window = maxf(_spring_direction_window - delta, 0.0)
		var desired_horizontal := Vector3(velocity.x, 0.0, velocity.z)
		velocity.x = lerpf(pre_spring_horizontal.x, desired_horizontal.x, SPRING_AIR_CONTROL)
		velocity.z = lerpf(pre_spring_horizontal.z, desired_horizontal.z, SPRING_AIR_CONTROL)
		if not _spring_boost_committed and _spring_direction_window > 0.0 and desired_horizontal.length_squared() > 0.04:
			var committed_direction := desired_horizontal.normalized()
			velocity.x += committed_direction.x * _spring_horizontal_boost
			velocity.z += committed_direction.z * _spring_horizontal_boost
			_spring_boost_committed = true
		_enforce_directional_launch_minimum()
	_update_bot_sprint(delta)
	_update_facing()
	_update_animation()
	if reaction_timer <= 0.0:
		_try_auto_pickup()
	_update_combat(delta)
	_update_item_behavior(delta)
	if can_dash:
		_update_dash_behavior(delta)
	_update_bot_footsteps(delta)

	var _desired_h_vel := Vector3(velocity.x, 0, velocity.z)
	move_and_slide()
	if _spring_air_active and is_on_floor() and velocity.y <= 0.0:
		_clear_spring_launch_state()
	_try_step_up(_desired_h_vel, delta)


func _update_bot_footsteps(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or is_dashing or horizontal_speed < 2.0:
		_bot_footstep_timer = 0.12
		return
	_bot_footstep_timer -= delta
	if _bot_footstep_timer <= 0.0:
		if silent_steps_timer <= 0.0:
			GameEvents.combat_noise.emit(global_position, actor_id, "footstep", 9.0 if is_sprinting else 6.0)
		_bot_footstep_timer = 0.26 if is_sprinting else 0.38


func _on_combat_noise(world_position: Vector3, source_actor_id: int, kind: String, loudness: float) -> void:
	if source_actor_id == actor_id or is_eliminated or global_position.distance_to(world_position) > loudness:
		return
	var source = NetworkManager.find_actor(source_actor_id) if NetworkManager.is_online() else null
	if source != null and GameConfig.teams_enabled and int(source.get("team_id")) == int(team_id):
		return
	if target_player != null and has_line_of_sight:
		return
	var error_radius: float = float({"easy": 3.0, "medium": 2.0, "hard": 1.1, "expert": 0.6}.get(ai_difficulty, 2.0))
	var approximate := world_position + Vector3(randf_range(-error_radius, error_radius), 0.0, randf_range(-error_radius, error_radius))
	_last_known_target_position = approximate
	_target_memory_timer = maxf(_target_memory_timer, target_memory_duration * (1.0 if kind != "footstep" else 0.65))
	if current_objective_type not in ["get_gun", "escape_fire"]:
		movement_target_position = approximate
		current_objective_type = "investigate_noise"


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


func _update_bot_sprint(delta: float) -> void:
	if not GameConfig.sprinting_enabled or is_dashing:
		is_sprinting = false
		return
	var objective_distance := global_position.distance_to(movement_target_position) if movement_target_position != null else 0.0
	var reserve: float = float({"easy": 10.0, "medium": 30.0, "hard": 42.0, "expert": 50.0}.get(ai_difficulty, 30.0))
	is_sprinting = objective_distance > 8.0 and stamina > reserve
	if is_sprinting:
		stamina = maxf(stamina - SPRINT_DRAIN_RATE * delta, 0.0)
		stamina_regen_timer = STAMINA_REGEN_DELAY
		if stamina <= 0.0:
			is_sprinting = false

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
	if dash_charges < max_dash_charges:
		dash_recharge_timer += delta
		if dash_recharge_timer >= dash_recharge_time:
			dash_charges += 1
			dash_recharge_timer = 0.0

func get_dash_recharge_progress() -> float:
	if dash_charges >= max_dash_charges:
		return 1.0
	return clampf(dash_recharge_timer / maxf(dash_recharge_time, 0.01), 0.0, 1.0)

func _update_dash_behavior(delta):
	if (dash_charges <= 0 and extra_dash_charge <= 0) or dash_cooldown > 0.0 or target_player == null:
		return

	var to_target = target_player.global_position - global_position
	to_target.y = 0
	var dist = to_target.length()

	match ai_difficulty:
		"easy":
			if holding_gun and dist < 2.5 and randf() < delta * 0.6:
				_execute_dash(-to_target.normalized())
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
	_dash_cancelled_spring_momentum = _spring_air_active and not is_on_floor()
	if _dash_cancelled_spring_momentum:
		_cancel_spring_launch_for_dash()
	dash_velocity = direction.normalized() * DASH_SPEED
	if _dash_cancelled_spring_momentum:
		velocity = dash_velocity
	dash_timer = DASH_DURATION
	if dash_charges > 0:
		dash_charges -= 1
	else:
		extra_dash_charge = maxi(extra_dash_charge - 1, 0)
		if extra_dash_charge <= 0:
			active_powerup_order.erase("extra_dash")
	dash_cooldown = 0.8
	is_dashing = true

# ============================================================
# Item behavior
# ============================================================

func _update_item_behavior(delta):
	if item_throw_cooldown > 0.0:
		item_throw_cooldown = maxf(item_throw_cooldown - delta, 0.0)
		return
	if item_throw_decision_timer > 0.0:
		item_throw_decision_timer = maxf(item_throw_decision_timer - delta, 0.0)
		return
	if held_item == null or target_player == null:
		return
	if not held_item.has_method("try_throw"):
		return

	# Item decisions happen on real-time intervals instead of once per rendered
	# frame. Difficulty changes how quickly the bot reassesses the throw, while
	# every tier keeps the same base movement speed.
	match ai_difficulty:
		"easy":
			item_throw_decision_timer = randf_range(1.2, 2.0)
		"medium":
			item_throw_decision_timer = randf_range(0.7, 1.2)
		"hard":
			item_throw_decision_timer = randf_range(0.4, 0.8)
		_:
			item_throw_decision_timer = randf_range(0.25, 0.55)

	var to_target = target_player.global_position - global_position
	var dist = to_target.length()
	var should_throw := false

	match ai_difficulty:
		"easy":
			should_throw = dist <= ITEM_THROW_RANGE_EASY
		"medium":
			should_throw = dist <= ITEM_THROW_RANGE_MEDIUM
		"hard":
			var guns = get_tree().get_nodes_in_group("gun")
			if guns.size() > 0 and guns[0].is_held:
				var holder = guns[0].player_ref
				if holder != null and holder != self:
					should_throw = global_position.distance_to(holder.global_position) < ITEM_THROW_RANGE_HARD
		"expert":
			var guns = get_tree().get_nodes_in_group("gun")
			var holder_dist = INF
			if guns.size() > 0 and guns[0].is_held and guns[0].player_ref != self:
				holder_dist = global_position.distance_to(guns[0].player_ref.global_position)
			should_throw = (holder_dist < ITEM_THROW_RANGE_EXPERT) or (dist < 5.0 and not target_player.holding_gun)

	if should_throw:
		held_item.try_throw()
		item_throw_cooldown = 2.0

# ============================================================
# Objective / navigation
# ============================================================

func _update_target(_delta: float):
	var current_valid := _is_valid_enemy_target(target_player)
	if current_valid and VisibilityRules.has_visual_contact(self, target_player):
		_last_known_target_position = target_player.global_position
		_target_memory_timer = target_memory_duration
	var best = null
	var best_score := INF
	var persistent_mode := GameConfig.game_mode in [GameConfig.MODE_ALL_GUN, GameConfig.MODE_ONE_OF_US]
	for candidate in get_tree().get_nodes_in_group("combat_target"):
		if not _is_valid_enemy_target(candidate):
			continue
		if not persistent_mode and not VisibilityRules.has_visual_contact(self, candidate):
			continue
		var score := global_position.distance_to(candidate.global_position)
		if bool(candidate.get("holding_gun")):
			score -= 1000.0
		if score < best_score:
			best_score = score
			best = candidate
	if current_valid and _target_commitment_timer > 0.0:
		var critical_switch := best != null and bool(best.get("holding_gun")) and not bool(target_player.get("holding_gun"))
		if not critical_switch:
			return
	if best != null and best != target_player:
		target_player = best
		_last_known_target_position = best.global_position
		_target_memory_timer = target_memory_duration
		_target_commitment_timer = target_commitment_duration
	elif not current_valid or (_target_memory_timer <= 0.0 and best == null):
		target_player = best


func _is_valid_enemy_target(candidate) -> bool:
	if candidate == null or not is_instance_valid(candidate) or candidate == self:
		return false
	if "is_eliminated" in candidate and candidate.is_eliminated:
		return false
	if GameConfig.teams_enabled and int(team_id) >= 0 and int(candidate.get("team_id")) == int(team_id):
		return false
	if candidate.has_method("can_be_affected_by") and not candidate.can_be_affected_by(self):
		return false
	if GameConfig.game_mode == GameConfig.MODE_ONE_OF_US:
		var my_role := str(one_of_us_role)
		var candidate_role := str(candidate.get("one_of_us_role"))
		if my_role != "" and candidate_role != "" and my_role == candidate_role:
			return false
	return true

func _decide_objective(delta):
	var new_target_pos = null
	var new_type = "idle"
	var fire_escape = _fire_escape_objective(delta)
	if fire_escape != null:
		movement_target_position = fire_escape
		current_objective_type = "escape_fire"
		reaction_timer = 0.0
		return
	if _objective_decision_timer > 0.0 and movement_target_position != null and _current_objective_still_valid():
		return
	_objective_decision_timer = 0.0
	_objective_decision_timer = randf_range(decision_time_min, decision_time_max)

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
			if not gun_node.is_held and _is_navigation_reachable(gun_node.global_position):
				new_target_pos = gun_node.global_position
				new_type = "get_gun"
			elif held_melee_weapon == null and held_item == null:
				var best_melee = _find_best_melee_weapon()
				var best_powerup = _find_nearest_powerup()
				var best_item = _find_nearest_item()
				var options := []
				if best_melee != null: options.append({"node": best_melee, "type": "get_melee", "weight": 1.0})
				if best_powerup != null: options.append({"node": best_powerup, "type": "get_powerup", "weight": 0.7 if ai_difficulty in ["hard", "expert"] else 1.0})
				if best_item != null: options.append({"node": best_item, "type": "get_item", "weight": 0.85})
				var best_score := INF
				for option in options:
					var score := global_position.distance_to(option["node"].global_position) * float(option["weight"])
					if score < best_score:
						best_score = score
						new_target_pos = option["node"].global_position
						new_type = str(option["type"])
				if options.is_empty() and target_player != null:
					new_target_pos = _get_approach_position(target_player.global_position if has_line_of_sight else _last_known_target_position)
					new_type = "chase_target"
			elif held_item != null and target_player != null:
				new_target_pos = _get_approach_position(target_player.global_position)
				new_type = "use_item"
			elif held_melee_weapon != null:
				if target_player != null:
					new_target_pos = _get_approach_position(target_player.global_position if has_line_of_sight else _last_known_target_position)
					new_type = "chase_target"

	if new_type != current_objective_type:
		current_objective_type = new_type
		reaction_timer = randf_range(reaction_time_min, reaction_time_max)

	if reaction_timer > 0.0:
		reaction_timer -= delta
		return

	movement_target_position = new_target_pos


func _current_objective_still_valid() -> bool:
	match current_objective_type:
		"get_gun":
			for gun in get_tree().get_nodes_in_group("gun"):
				if is_instance_valid(gun) and not bool(gun.get("is_held")) \
						and gun.global_position.distance_to(movement_target_position) <= 2.0:
					return true
			return false
		"get_melee":
			return _has_available_objective_near("melee", movement_target_position)
		"get_powerup":
			return _has_available_objective_near("powerup", movement_target_position)
		"get_item":
			return _has_available_objective_near("item", movement_target_position)
		"chase_target", "gunner_position", "retreat", "use_item":
			return _is_valid_enemy_target(target_player)
		"investigate_noise":
			return _target_memory_timer > 0.0
		_:
			return movement_target_position != null


func _has_available_objective_near(group_name: StringName, target_position: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(node) or not node.visible:
			continue
		if group_name == &"powerup" and bool(node.get("collected")):
			continue
		if group_name != &"powerup" and (bool(node.get("is_held")) or bool(node.get("is_in_flight"))):
			continue
		if node.global_position.distance_to(target_position) <= 2.0:
			return true
	return false


func _fire_escape_objective(delta: float):
	var rm = get_tree().current_scene.get_node_or_null("RoundManager")
	if rm == null or not rm.has_method("get_fire_warning"):
		_fire_escape_committed = false
		_fire_safe_timer = 0.0
		return null
	var warning: Dictionary = rm.get_fire_warning(self)
	if bool(warning.get("active", false)):
		_fire_safe_timer = 0.0
		var can_finish_chase := false
		if target_player != null and bool(target_player.get("holding_gun")):
			var target_distance := global_position.distance_to(target_player.global_position)
			var escape_position: Vector3 = rm.get_bot_fire_escape_position(global_position, 0.75)
			var return_time := global_position.distance_to(escape_position) / maxf(move_speed, 0.1)
			can_finish_chase = target_distance <= 3.5 and float(warning.get("remaining", 0.0)) > return_time + fire_safety_margin
		if can_finish_chase:
			return null
		_fire_escape_committed = true
	if _fire_escape_committed:
		if not bool(warning.get("active", false)):
			_fire_safe_timer += delta
			if _fire_safe_timer >= 1.0:
				_fire_escape_committed = false
				return null
		var escape_position: Vector3 = rm.get_bot_fire_escape_position(global_position, 0.9)
		if not _is_navigation_reachable(escape_position):
			_fire_escape_committed = false
			return null
		return escape_position
	return null

func _find_nearest_powerup() -> Node:
	var powerups = get_tree().get_nodes_in_group("powerup")
	var closest = null
	var closest_dist = INF
	for pu in powerups:
		if not pu.visible or bool(pu.get("collected")):
			continue
		if not can_collect_powerup(str(pu.get("power_type"))):
			continue
		if not _is_navigation_reachable(pu.global_position):
			continue
		var dist = global_position.distance_to(pu.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = pu
	return closest


func _find_nearest_item() -> Node:
	var closest = null
	var closest_dist := INF
	for item in get_tree().get_nodes_in_group("item"):
		if not is_instance_valid(item) or not item.visible or bool(item.get("is_held")) or bool(item.get("is_in_flight")):
			continue
		if not _is_navigation_reachable(item.global_position):
			continue
		var distance := global_position.distance_to(item.global_position)
		if distance < closest_dist:
			closest_dist = distance
			closest = item
	return closest


func _is_navigation_reachable(world_position: Vector3) -> bool:
	var nav_agent: NavigationAgent3D = $NavigationAgent3D
	var navigation_map := nav_agent.get_navigation_map()
	if navigation_map == RID():
		return true
	var closest_point := NavigationServer3D.map_get_closest_point(navigation_map, world_position)
	if closest_point.distance_to(world_position) > 2.0:
		return false
	var path := NavigationServer3D.map_get_path(navigation_map, global_position, closest_point, true)
	return path.size() >= 2 or global_position.distance_to(closest_point) <= arrive_distance

const GUNNER_IDEAL_RANGE := 10.0
const GUNNER_TOO_CLOSE := 5.0
var _strafe_angle := 0.0
var _strafe_direction := 1.0

func _get_gunner_position() -> Vector3:
	var to_target = target_player.global_position - global_position
	to_target.y = 0
	var dist = to_target.length()

	var ideal_range := GUNNER_IDEAL_RANGE
	var too_close := GUNNER_TOO_CLOSE
	if GameConfig.game_mode == GameConfig.MODE_ONE_OF_US and one_of_us_role == "us":
		# Survivors keep distance from Them instead of advancing into their
		# enlarged sword reach, but still strafe and fire whenever sight opens.
		ideal_range = 15.0
		too_close = 9.0

	_strafe_angle += get_physics_process_delta_time() * 0.8 * _strafe_direction
	if _strafe_angle > PI or _strafe_angle < -PI:
		_strafe_direction *= -1.0
		_strafe_angle = clamp(_strafe_angle, -PI, PI)

	var to_target_norm = to_target.normalized() if dist > 0.01 else -global_transform.basis.z
	var lateral = to_target_norm.cross(Vector3.UP).normalized()

	if dist < too_close:
		return global_position - to_target_norm * 5.0 + lateral * _strafe_direction
	elif dist > ideal_range:
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
		var spread := 2.5
		if GameConfig.teams_enabled:
			match ai_difficulty:
				"medium": spread = 3.0
				"hard": spread = 4.0
				"expert": spread = 5.0
		var side := -1.0 if actor_id % 2 == 0 else 1.0
		_approach_offset = right * (side * randf_range(spread * 0.55, spread) if ai_difficulty in ["hard", "expert"] else randf_range(-spread, spread))
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
		if not _is_navigation_reachable(m.global_position):
			continue
		available.append(m)
	if available.size() == 0:
		return null
	var closest = null
	var closest_dist = INF
	for m in available:
		var dist = global_position.distance_to(m.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = m
	return closest

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
	var to_next: Vector3 = next_path_point - global_position
	var next_height_delta: float = to_next.y
	to_next.y = 0

	if to_next.length() < 0.05:
		velocity.x = 0
		velocity.z = 0
		_stop_movement_animation()
		return

	var dir = to_next.normalized()
	var speed = (SPRINT_SPEED if is_sprinting else move_speed) * slow_multiplier_value
	if speed_surge_timer > 0.0:
		speed *= SPEED_SURGE_MULT
	if one_of_us_role == "them":
		speed *= GameConfig.ONE_OF_US_THEM_SPEED_MULTIPLIER
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_maybe_follow_authored_jump(next_height_delta)


func _maybe_follow_authored_jump(height_delta: float) -> void:
	# Navigation links and obvious low ledges are the only intentional bot
	# jumps. Ordinary flat paths never trigger this, preventing bunny hopping.
	if not is_on_floor():
		return
	if height_delta > 0.25 and height_delta <= 1.1:
		velocity.y = 5.5

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
	if flash_blind_timer > 0.0:
		has_line_of_sight = false
		return
	if target_player == null:
		return
	_update_line_of_sight()
	if holding_gun:
		var hold_point = get_hold_point()
		var held_gun = hold_point.get_child(0) if hold_point.get_child_count() > 0 else null
		if held_gun == null:
			return
		if not bool(held_gun.get("can_fire")):
			_gun_was_reloading = true
			return
		if _gun_was_reloading:
			_gun_was_reloading = false
			_post_reload_hesitation = randf_range(reload_hesitation_min, reload_hesitation_max)
		if _post_reload_hesitation > 0.0:
			return
		if not has_line_of_sight and (_target_memory_timer <= 0.0 or randf() > blind_fire_chance):
			return
		fire_cooldown -= delta
		if fire_cooldown <= 0.0:
			held_gun.try_fire()
			fire_cooldown = randf_range(fire_cooldown_min, fire_cooldown_max)
	elif held_melee_weapon != null:
		var dist = global_position.distance_to(target_player.global_position)
		var attack_range := 4.5 if GameConfig.game_mode == GameConfig.MODE_ONE_OF_US and one_of_us_role == "them" else melee_range
		if dist <= attack_range:
			held_melee_weapon.try_swing()

func _update_line_of_sight():
	has_line_of_sight = false
	if target_player == null:
		return
	has_line_of_sight = VisibilityRules.has_visual_contact(self, target_player)
	if has_line_of_sight:
		_last_known_target_position = target_player.global_position
		_target_memory_timer = target_memory_duration

# ============================================================
# Interactable registration
# ============================================================

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
	var aim_position: Vector3 = target_player.global_position if has_line_of_sight else _last_known_target_position
	return (aim_position - global_position).normalized()

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

func apply_flash_blind(duration: float) -> void:
	flash_blind_timer = maxf(flash_blind_timer, duration)
	_flash_blind_total = flash_blind_timer
	has_line_of_sight = false
	reaction_timer = maxf(reaction_timer, minf(duration, 1.0))

var speed_surge_timer := 0.0
const SPEED_SURGE_MULT := 1.4
var vampire_timer := 0.0
var second_wind_ready := false

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
		"reach":
			reach_timer = _extend_timed_powerup(reach_timer, duration)
		"silent_steps":
			silent_steps_timer = _extend_timed_powerup(silent_steps_timer, duration)
		_:
			active_powerup_order.erase(power_type)
			return false
	return true

func get_active_powerups_for_display() -> Array:
	var result: Array = []
	for power_type in active_powerup_order:
		match power_type:
			"extra_dash":
				if extra_dash_charge > 0: result.append({"type": power_type, "timed": false, "time_left": 0.0})
			"sticky_hands":
				if melee_disarm_shields > 0: result.append({"type": power_type, "timed": false, "time_left": 0.0})
			"speed_surge":
				if speed_surge_timer > 0.0: result.append({"type": power_type, "timed": true, "time_left": speed_surge_timer})
			"silent_steps":
				if silent_steps_timer > 0.0: result.append({"type": power_type, "timed": true, "time_left": silent_steps_timer})
			"vampire_touch":
				if vampire_timer > 0.0: result.append({"type": power_type, "timed": true, "time_left": vampire_timer})
			"extra_life":
				if second_wind_ready: result.append({"type": power_type, "timed": false, "time_left": 0.0})
			"reach":
				if reach_timer > 0.0: result.append({"type": power_type, "timed": true, "time_left": reach_timer})
	active_powerup_order = result.map(func(entry): return entry["type"])
	return result

func clear_all_powerups() -> void:
	speed_surge_timer = 0.0
	vampire_timer = 0.0
	reach_timer = 0.0
	_reach_interactables.clear()
	_rebuild_interactables()
	silent_steps_timer = 0.0
	second_wind_ready = false
	melee_disarm_shields = 0
	extra_dash_charge = 0
	active_powerup_order.clear()


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
	var definitions := [
		{"scene": "res://models/springShoes/LeftSpringShoe.tscn", "x": -0.22},
		{"scene": "res://models/springShoes/RightSpringShoe.tscn", "x": 0.22},
	]
	for definition in definitions:
		var packed := load(str(definition["scene"])) as PackedScene
		if packed == null:
			continue
		var attachment := Node3D.new()
		attachment.name = "DoubleJumpShoeAttachment"
		add_child(attachment)
		attachment.position = Vector3(float(definition["x"]), 0.12, -0.03)
		attachment.add_child(packed.instantiate())
		_double_jump_shoe_attachments.append(attachment)


func _request_double_jump_shoes() -> void:
	if not double_jump_shoes_active or is_on_floor():
		return
	if NetworkManager.is_online():
		var rm = get_tree().current_scene.get_node_or_null("RoundManager")
		if rm != null and multiplayer.is_server():
			rm._server_request_online_double_jump(actor_id,
				int(rm.get("online_round_epoch")))
	else:
		_perform_double_jump_shoes()


func _perform_double_jump_shoes() -> void:
	if not double_jump_shoes_active:
		return
	velocity.y = 7.0 * GameConfig.DOUBLE_JUMP_SHOE_MULTIPLIER
	clear_double_jump_shoes()
	AudioManager.play_sfx("double_jump_boing")


func confirm_online_double_jump_shoes() -> void:
	if not double_jump_shoes_active:
		return
	if _is_online_authority:
		velocity.y = 7.0 * GameConfig.DOUBLE_JUMP_SHOE_MULTIPLIER
		AudioManager.play_sfx("double_jump_boing")
	clear_double_jump_shoes()

func has_active_reach() -> bool:
	return reach_timer > 0.0


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
			# Guns, melee, items, and powerups do not share every state field.
			# Guard each one so a missing property never becomes bool(null).
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

# Pulsing red/orange surface rim while this bot holds the gun (matches the player
# version in character_body_3d.gd — material_overlay, depth-tested, no wallhack).
var _gun_outline_active := false
var _decoy_outline_generation := 0

func _update_gun_holder_outline():
	var should_outline := holding_gun and GameConfig.game_mode == GameConfig.MODE_ONE_GUN
	if should_outline == _gun_outline_active:
		return
	_gun_outline_active = should_outline
	var mat: Material = null
	if should_outline:
		mat = CombatOutline.create_gun_holder_rim_material()
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
	var mat := CombatOutline.create_decoy_reveal_material()
	var model = get_node_or_null("new guy one gun model orange running")
	for mesh in _find_mesh_instances(model if model != null else self):
		mesh.material_overlay = mat
	await get_tree().create_timer(duration).timeout
	if generation == _decoy_outline_generation:
		_restore_outline_after_temporary_reveal()

func show_overtime_pulse(duration: float = 1.0) -> void:
	_decoy_outline_generation += 1
	var generation := _decoy_outline_generation
	var mat := CombatOutline.create_overtime_reveal_material()
	var model = get_node_or_null("new guy one gun model orange running")
	for mesh in _find_mesh_instances(model if model != null else self):
		mesh.material_overlay = mat
	await get_tree().create_timer(duration).timeout
	if generation == _decoy_outline_generation:
		_restore_outline_after_temporary_reveal()


func _restore_outline_after_temporary_reveal() -> void:
	var model = get_node_or_null("new guy one gun model orange running")
	for mesh in _find_mesh_instances(model if model != null else self):
		mesh.material_overlay = null
	_gun_outline_active = false
	_update_gun_holder_outline()

func flash_hit():
	if not AccessibilityManager.allow_flash():
		return
	_hit_flash_generation += 1
	var generation := _hit_flash_generation
	_restore_hit_flash_materials()
	var meshes = _find_mesh_instances(self)
	var entries: Array = []
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

func _find_mesh_instances(node: Node) -> Array:
	var result = []
	if node == null:
		return result
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result

# ============================================================
# Round lifecycle
# ============================================================

func eliminate(killer_name = "", weapon_icon = "💀", lethal_kind := "weapon", killer_actor_id: int = -1):
	_perform_eliminate(killer_name, weapon_icon, lethal_kind, killer_actor_id)

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


func _perform_eliminate(killer_name, weapon_icon, lethal_kind, killer_actor_id) -> void:
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
	if not is_online and GameConfig.game_mode == GameConfig.MODE_ALL_GUN \
			and lethal_kind == "weapon":
		if not _consume_local_all_gun_heart():
			return
	elif GameConfig.game_mode == GameConfig.MODE_ALL_GUN \
			and lethal_kind == "environment":
		all_gun_hearts = 0
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
	clear_double_jump_shoes()
	is_eliminated = true
	_current_anim = ""
	CombatPop.spawn(get_tree().current_scene, global_position)
	visible = false
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	GameEvents.player_eliminated.emit(get_display_name(), killer_name, weapon_icon)
	GameEvents.actor_eliminated.emit(int(actor_id), killer_actor_id, str(weapon_icon))

func respawn(spawn_transform):
	_hit_flash_generation += 1
	_restore_hit_flash_materials()
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
	_clear_spring_launch_state()
	_dash_cancelled_spring_momentum = false
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
	clear_double_jump_shoes()
	slow_timer = 0.0
	all_gun_hearts = GameConfig.ALL_GUN_MAX_HEARTS \
		if GameConfig.game_mode == GameConfig.MODE_ALL_GUN else 0
	slow_multiplier_value = 1.0
	dash_charges = max_dash_charges
	extra_dash_charge = 0
	_one_of_us_final_bonus_active = false
	dash_recharge_timer = 0.0
	is_dashing = false
	dash_cooldown = 0.0
	item_throw_cooldown = 0.0
	item_throw_decision_timer = randf_range(0.15, 0.45)
	_approach_offset_timer = 0.0
	_approach_offset = Vector3.ZERO
	_strafe_angle = 0.0
