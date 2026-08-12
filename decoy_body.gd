extends CharacterBody3D

## Runtime decoy actor.
##
## World movement belongs exclusively to this CharacterBody3D. The visual gait
## is procedural and can only alter bone rotations plus VisualRoot's local Y,
## so animation can never translate the rendered cat backward inside its body.

const CombatIdentityTagScript = preload("res://combat_identity_tag.gd")
const REFERENCE_POSE_SOURCE := "res://models/player_v2/OGCatModelV2_Rigged.glb"

const MOVE_SPEED := 10.0
const MOVE_ACCELERATION := 38.0
const GRAVITY := 19.6
const DEFAULT_FORWARD_DISTANCE := 18.0
const ARRIVE_DISTANCE := 0.65
const LIFETIME := 10.0
const MIN_MOVING_SPEED := 0.2
const BLOCKED_COMMAND_TIMEOUT := 0.12

const NETWORK_SEND_INTERVAL := 0.05
const NETWORK_FOLLOW_RATE := 22.0
const NETWORK_SNAP_DISTANCE := 5.0

const GAIT_STRIDE_LENGTH := 7.5
const GAIT_BLEND_RATE := 8.0
const LEG_SWING_ANGLE := 0.46
const KNEE_BEND_ANGLE := 0.38
const ARM_SWING_ANGLE := 0.24
const SPINE_SWAY_ANGLE := 0.035
const GAIT_BOB_HEIGHT := 0.035

var owner_player = null
var initial_forward := Vector3.FORWARD
var command_target := Vector3.INF
var control_active := false
@export_range(0.05, 60.0, 0.05) var lifetime_seconds := LIFETIME

# Combat-target compatibility. A decoy deliberately exposes the same small
# state surface bots and identity tags read from real actors.
var team_id := -1
var holding_gun := false
var is_eliminated := false
var is_bot := false
var actor_id := -1
var owner_peer_id := -1
var character_skin_id := PlayerSkinRegistry.DEFAULT_SKIN_ID

var _popped := false
var _blocked_command_time := 0.0
var _slow_timer := 0.0
var _slow_multiplier := 1.0
var _network_send_timer := 0.0
var _network_target_transform := Transform3D.IDENTITY
var _network_target_velocity := Vector3.ZERO
var _network_has_snapshot := false

var _visual_root: Node3D = null
var _animation_player: AnimationPlayer = null
var _current_visual_animation := ""
var _skeleton: Skeleton3D = null
var _bone_indices: Dictionary = {}
var _bone_rest_rotations: Dictionary = {}
var _gait_phase := 0.0
var _gait_blend := 0.0
var _visual_motion_speed := 0.0
var _reveal_generation := 0

static var _reference_idle_rotations: Dictionary = {}
static var _reference_idle_loaded := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	set_collision_layer_value(2, true)
	set_collision_mask_value(1, true)
	add_to_group("combat_target")
	add_to_group("combat_decoy")
	_register_with_owner()
	_setup_procedural_visual()
	_apply_owner_skin()
	_face_direction(initial_forward)
	command_forward()
	_network_target_transform = global_transform
	call_deferred("_setup_identity_tags")
	_run_lifetime()


func _register_with_owner() -> void:
	if owner_player == null or not is_instance_valid(owner_player):
		return
	if "active_decoy" in owner_player:
		var previous = owner_player.get("active_decoy")
		if previous != null and previous != self and is_instance_valid(previous):
			# The synchronized deploy event runs this on every peer, so replacing an
			# older decoy does not require a second network message.
			if previous.has_method("_destroy_local"):
				previous._destroy_local(true)
			else:
				previous.queue_free()
		owner_player.set("active_decoy", self)
	team_id = int(owner_player.get("team_id")) if "team_id" in owner_player else -1
	holding_gun = bool(owner_player.get("holding_gun")) \
		if "holding_gun" in owner_player else false
	actor_id = int(owner_player.get("actor_id")) if "actor_id" in owner_player else -1
	owner_peer_id = int(owner_player.get("owner_peer_id")) \
		if "owner_peer_id" in owner_player else -1
	character_skin_id = PlayerSkinRegistry.sanitize_skin_id(
		str(owner_player.get("character_skin_id")) \
		if "character_skin_id" in owner_player else PlayerSkinRegistry.DEFAULT_SKIN_ID)


func _apply_owner_skin() -> void:
	var visual := get_node_or_null("VisualRoot/CatModel")
	if visual != null and visual.has_method("set_skin"):
		visual.set_skin(character_skin_id)


func _setup_identity_tags() -> void:
	if _popped or not is_inside_tree():
		return
	if NetworkManager.is_online():
		var viewer = NetworkManager.find_net_player(NetworkManager.local_id())
		if viewer != null:
			var tag = CombatIdentityTagScript.new()
			tag.name = "OnlineDecoyIdentity"
			add_child(tag)
			tag.setup(self, viewer, 1)
		return
	var scene := get_tree().current_scene
	var manager = scene.get_node_or_null("RoundManager") if scene != null else null
	if manager != null and manager.has_method("register_local_decoy_tags"):
		manager.register_local_decoy_tags(self)


func _setup_procedural_visual() -> void:
	_visual_root = get_node_or_null("VisualRoot")
	if _visual_root == null:
		push_warning("DecoyBody: VisualRoot is missing; gameplay remains active without gait.")
		return
	var visual := get_node_or_null("VisualRoot/CatModel")
	if visual != null and visual.has_method("ensure_animations"):
		_animation_player = visual.ensure_animations(["idle", "standard_run"])
	if _animation_player == null:
		_animation_player = _visual_root.find_child(
			"AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player != null and _animation_player.has_animation("idle"):
		_current_visual_animation = "idle"
		_animation_player.play("idle")
		_animation_player.advance(0.0)
		return
	# Procedural gait remains a safe fallback if an animation import is missing.
	var skeletons: Array[Node] = _visual_root.find_children(
		"*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_warning("DecoyBody: the cat model has no Skeleton3D; gait is disabled.")
		return
	_skeleton = skeletons[0] as Skeleton3D
	_apply_reference_idle_pose()
	_remember_bone("left_up_leg", "mixamorig_LeftUpLeg")
	_remember_bone("right_up_leg", "mixamorig_RightUpLeg")
	_remember_bone("left_leg", "mixamorig_LeftLeg")
	_remember_bone("right_leg", "mixamorig_RightLeg")
	_remember_bone("left_arm", "mixamorig_LeftArm")
	_remember_bone("right_arm", "mixamorig_RightArm")
	_remember_bone("spine", "mixamorig_Spine2")


func _apply_reference_idle_pose() -> void:
	if _skeleton == null:
		return
	if not _reference_idle_loaded:
		_reference_idle_loaded = true
		var packed: PackedScene = load(REFERENCE_POSE_SOURCE)
		if packed != null:
			var instance = packed.instantiate()
			var source_player: AnimationPlayer = instance.find_child(
				"AnimationPlayer", true, false)
			if source_player != null:
				var source_names: PackedStringArray = source_player.get_animation_list()
				if not source_names.is_empty():
					var idle: Animation = source_player.get_animation(source_names[0])
					for track_index in idle.get_track_count():
						if idle.track_get_type(track_index) \
								!= Animation.TYPE_ROTATION_3D \
								or idle.track_get_key_count(track_index) == 0:
							continue
						var track_path: NodePath = idle.track_get_path(track_index)
						if track_path.get_subname_count() == 0:
							continue
						var bone_name := String(track_path.get_subname(0))
						_reference_idle_rotations[bone_name] = \
							idle.track_get_key_value(track_index, 0)
			instance.free()
	for bone_name in _reference_idle_rotations:
		var index := _skeleton.find_bone(str(bone_name))
		if index >= 0:
			var rotation: Quaternion = _reference_idle_rotations[bone_name]
			_skeleton.set_bone_pose_rotation(index, rotation)


func _remember_bone(key: String, bone_name: String) -> void:
	if _skeleton == null:
		return
	var index := _skeleton.find_bone(bone_name)
	if index < 0:
		push_warning("DecoyBody: missing procedural gait bone " + bone_name)
		return
	_bone_indices[key] = index
	_bone_rest_rotations[index] = _skeleton.get_bone_pose_rotation(index)


func _process(delta: float) -> void:
	if _animation_player != null:
		var requested := "standard_run" if _visual_motion_speed > MIN_MOVING_SPEED else "idle"
		if requested != _current_visual_animation and _animation_player.has_animation(requested):
			_current_visual_animation = requested
			_animation_player.play(requested, 0.12)
	else:
		_update_procedural_gait(delta)


func _update_procedural_gait(delta: float) -> void:
	if _visual_root == null or _skeleton == null:
		return
	var moving := _visual_motion_speed > MIN_MOVING_SPEED
	var target_blend := 1.0 if moving else 0.0
	_gait_blend = move_toward(_gait_blend, target_blend, GAIT_BLEND_RATE * delta)
	if moving:
		# Driving phase from resolved travel speed makes slows and collision stops
		# visually honest, while _process keeps the bone motion render-smooth.
		_gait_phase = fposmod(_gait_phase
			+ TAU * (_visual_motion_speed / GAIT_STRIDE_LENGTH) * delta, TAU)
	var stride := sin(_gait_phase)
	var left_knee := maxf(-stride, 0.0)
	var right_knee := maxf(stride, 0.0)
	_set_bone_offset("left_up_leg", Vector3.RIGHT,
		stride * LEG_SWING_ANGLE * _gait_blend)
	_set_bone_offset("right_up_leg", Vector3.RIGHT,
		-stride * LEG_SWING_ANGLE * _gait_blend)
	_set_bone_offset("left_leg", Vector3.RIGHT,
		left_knee * KNEE_BEND_ANGLE * _gait_blend)
	_set_bone_offset("right_leg", Vector3.RIGHT,
		right_knee * KNEE_BEND_ANGLE * _gait_blend)
	var arm_scale := 0.25 if holding_gun else 1.0
	_set_bone_offset("left_arm", Vector3.RIGHT,
		-stride * ARM_SWING_ANGLE * arm_scale * _gait_blend)
	_set_bone_offset("right_arm", Vector3.RIGHT,
		stride * ARM_SWING_ANGLE * arm_scale * _gait_blend)
	_set_bone_offset("spine", Vector3.FORWARD,
		sin(_gait_phase * 2.0) * SPINE_SWAY_ANGLE * _gait_blend)
	# The visual root is never allowed to change local X or Z.
	_visual_root.position = Vector3(0.0,
		absf(sin(_gait_phase * 2.0)) * GAIT_BOB_HEIGHT * _gait_blend, 0.0)


func _set_bone_offset(key: String, axis: Vector3, angle: float) -> void:
	if not _bone_indices.has(key):
		return
	var index: int = int(_bone_indices[key])
	var rest_rotation: Quaternion = _bone_rest_rotations.get(index, Quaternion.IDENTITY)
	_skeleton.set_bone_pose_rotation(index,
		rest_rotation * Quaternion(axis, angle))


func _physics_process(delta: float) -> void:
	if NetworkManager.is_online() and not multiplayer.is_server():
		_follow_network_snapshot(delta)
		return
	if _popped:
		return
	if owner_player != null and is_instance_valid(owner_player):
		holding_gun = bool(owner_player.get("holding_gun")) \
			if "holding_gun" in owner_player else false
		if "is_eliminated" in owner_player \
				and bool(owner_player.get("is_eliminated")):
			_expire_from_authority()
			return
	_update_slow(delta)
	var desired_velocity := _desired_horizontal_velocity()
	velocity.x = move_toward(velocity.x, desired_velocity.x, MOVE_ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, desired_velocity.z, MOVE_ACCELERATION * delta)
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	var resolved := get_real_velocity()
	_visual_motion_speed = Vector2(resolved.x, resolved.z).length()
	_update_blocked_command(desired_velocity, delta)
	_broadcast_transform_if_due(delta)


func _desired_horizontal_velocity() -> Vector3:
	if control_active and owner_player != null and is_instance_valid(owner_player):
		var owner_velocity: Vector3 = owner_player.get("velocity")
		var owner_direction := Vector3(owner_velocity.x, 0.0, owner_velocity.z)
		if owner_direction.length_squared() <= 0.04:
			return Vector3.ZERO
		_face_direction(owner_direction)
		return owner_direction.normalized() * MOVE_SPEED * _slow_multiplier
	if not command_target.is_finite():
		return Vector3.ZERO
	var to_target := command_target - global_position
	to_target.y = 0.0
	if to_target.length() <= ARRIVE_DISTANCE:
		command_target = Vector3.INF
		return Vector3.ZERO
	_face_direction(to_target)
	var approach_speed := minf(MOVE_SPEED, to_target.length() * 4.0)
	return to_target.normalized() * approach_speed * _slow_multiplier


func _update_blocked_command(desired_velocity: Vector3, delta: float) -> void:
	if control_active or not command_target.is_finite():
		_blocked_command_time = 0.0
		return
	if desired_velocity.length_squared() > MIN_MOVING_SPEED * MIN_MOVING_SPEED \
			and _visual_motion_speed <= MIN_MOVING_SPEED \
			and get_slide_collision_count() > 0:
		_blocked_command_time += delta
		if _blocked_command_time >= BLOCKED_COMMAND_TIMEOUT:
			command_target = Vector3.INF
			velocity.x = 0.0
			velocity.z = 0.0
			_visual_motion_speed = 0.0
	else:
		_blocked_command_time = 0.0


func _update_slow(delta: float) -> void:
	if _slow_timer <= 0.0:
		return
	_slow_timer = maxf(_slow_timer - delta, 0.0)
	if _slow_timer <= 0.0:
		_slow_multiplier = 1.0


func command_forward(distance: float = DEFAULT_FORWARD_DISTANCE) -> void:
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	command_target = global_position + forward.normalized() * maxf(distance, 0.0)
	_blocked_command_time = 0.0


func toggle_control() -> void:
	control_active = not control_active
	if control_active:
		command_target = Vector3.INF
	else:
		command_forward()


func request_control_toggle(requester) -> void:
	if requester != owner_player:
		return
	if NetworkManager.is_online():
		if not requester.has_method("is_locally_controlled") or not requester.is_locally_controlled():
			return
		var manager = _round_manager()
		if manager != null and manager.has_method(
				"request_online_decoy_control_toggle"):
			manager.request_online_decoy_control_toggle(
				int(get_meta("online_deployed_id", -1)), int(requester.get("actor_id")))
		return
	toggle_control()


func _face_direction(direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() > 0.0001:
		look_at(global_position + flat.normalized(), Vector3.UP)


func get_visual_facing_direction() -> Vector3:
	if _visual_root == null:
		return -global_basis.z.normalized()
	# VisualRoot has a PI yaw because the imported cat's authored front is +Z.
	var facing := _visual_root.global_basis.z
	facing.y = 0.0
	return facing.normalized()


func _broadcast_transform_if_due(delta: float) -> void:
	if not NetworkManager.is_online() or not multiplayer.is_server():
		return
	_network_send_timer -= delta
	if _network_send_timer > 0.0:
		return
	_network_send_timer = NETWORK_SEND_INTERVAL
	var manager = _round_manager()
	if manager != null and manager.has_method("broadcast_online_decoy_transform"):
		manager.broadcast_online_decoy_transform(
			int(get_meta("online_deployed_id", -1)), global_transform, velocity)


func _receive_network_snapshot(snapshot: Transform3D, snapshot_velocity: Vector3) -> void:
	_network_target_transform = snapshot
	_network_target_velocity = snapshot_velocity
	velocity = snapshot_velocity
	if not _network_has_snapshot:
		_network_has_snapshot = true
		global_transform = snapshot


func _follow_network_snapshot(delta: float) -> void:
	if not _network_has_snapshot or _popped:
		return
	var distance := global_position.distance_to(_network_target_transform.origin)
	if distance > NETWORK_SNAP_DISTANCE:
		global_transform = _network_target_transform
	else:
		# Interpolate only toward received authoritative positions. The former
		# extrapolation advanced beyond each packet and then corrected backward,
		# which is the textbook source of visible network rubber-banding.
		var weight := 1.0 - exp(-NETWORK_FOLLOW_RATE * delta)
		global_transform = global_transform.interpolate_with(
			_network_target_transform, clampf(weight, 0.0, 1.0))
	_visual_motion_speed = Vector2(
		_network_target_velocity.x, _network_target_velocity.z).length()


func apply_slow(duration: float, multiplier: float) -> void:
	if NetworkManager.is_online():
		if multiplayer.is_server():
			_broadcast_action("slow", {
				"duration": duration,
				"multiplier": multiplier,
			})
		return
	_apply_slow_local(duration, multiplier)


func _apply_slow_local(duration: float, multiplier: float) -> void:
	_slow_timer = maxf(_slow_timer, maxf(duration, 0.0))
	_slow_multiplier = minf(_slow_multiplier, clampf(multiplier, 0.0, 1.0))
	_reveal_flicker()


func apply_launch(launch_velocity: float) -> void:
	if NetworkManager.is_online():
		if multiplayer.is_server():
			_broadcast_action("launch", {"velocity": launch_velocity})
		return
	velocity.y = maxf(velocity.y, launch_velocity)


func apply_spring_launch(launch_velocity: float, horizontal_boost: float, _direction_window: float) -> void:
	var launch_direction := Vector3(initial_forward.x, 0.0, initial_forward.z).normalized()
	if launch_direction.is_zero_approx():
		launch_direction = Vector3.FORWARD
	velocity.y = maxf(velocity.y, launch_velocity)
	velocity.x += launch_direction.x * horizontal_boost
	velocity.z += launch_direction.z * horizontal_boost
	if NetworkManager.is_online() and multiplayer.is_server():
		_broadcast_action("spring_launch", {
			"velocity": launch_velocity,
			"horizontal_boost": horizontal_boost,
		})


func _reveal_flicker() -> void:
	_reveal_generation += 1
	var generation := _reveal_generation
	var meshes: Array[Node] = find_children("*", "MeshInstance3D", true, false)
	var overlay := StandardMaterial3D.new()
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.albedo_color = Color(0.2, 0.95, 1.0, 0.4)
	overlay.emission_enabled = true
	overlay.emission = Color(0.2, 0.95, 1.0)
	overlay.emission_energy_multiplier = 1.6
	for node in meshes:
		(node as MeshInstance3D).material_overlay = overlay
	await get_tree().create_timer(0.35).timeout
	if generation != _reveal_generation or _popped:
		return
	for node in meshes:
		if is_instance_valid(node):
			(node as MeshInstance3D).material_overlay = null


func is_combat_decoy() -> bool:
	return true


func can_be_affected_by(attacker) -> bool:
	if attacker == null or owner_player == null or not is_instance_valid(owner_player):
		return true
	if attacker == owner_player:
		return false
	if GameConfig.teams_enabled and not GameConfig.friendly_fire_enabled:
		var attacker_team := int(attacker.get("team_id"))
		if attacker_team >= 0 and attacker_team == team_id:
			return false
	return true


func pop_from_attack(attacker = null, attack_kind: String = "") -> void:
	if _popped or not can_be_affected_by(attacker):
		return
	if NetworkManager.is_online():
		if multiplayer.is_server():
			_broadcast_action("pop", {
				"attacker_id": int(attacker.get("actor_id"))
					if attacker != null else -1,
				"attack_kind": attack_kind,
			})
		return
	if attack_kind == "gun":
		_reveal_shooter(attacker)
	_destroy_local(true)


func eliminate(_killer := "", _icon = null) -> void:
	pop_from_attack(null, "elimination")


func flash_hit() -> void:
	pop_from_attack(null, "hit")


func is_bullet_immune() -> bool:
	return false


func server_online_hit() -> void:
	if NetworkManager.is_online() and multiplayer.is_server():
		pop_from_attack(null, "gun")


func get_display_name() -> String:
	if owner_player != null and is_instance_valid(owner_player) \
			and owner_player.has_method("get_display_name"):
		return owner_player.get_display_name()
	return "Decoy"


func _reveal_shooter(attacker) -> void:
	if attacker != null and attacker.has_method("show_decoy_destroyer_outline"):
		attacker.show_decoy_destroyer_outline(0.5, owner_player)


func _run_lifetime() -> void:
	await get_tree().create_timer(lifetime_seconds).timeout
	if not _popped and is_inside_tree():
		_expire_from_authority()


func manages_deployed_lifetime() -> bool:
	return true


func _expire_from_authority() -> void:
	if _popped:
		return
	if NetworkManager.is_online():
		if multiplayer.is_server():
			_broadcast_action("pop")
		return
	_destroy_local(true)


func _broadcast_action(action: String, data: Dictionary = {}) -> void:
	var manager = _round_manager()
	if manager != null and manager.has_method("broadcast_online_deployed_action"):
		manager.broadcast_online_deployed_action(
			int(get_meta("online_deployed_id", -1)), action, data)


func _round_manager():
	var scene := get_tree().current_scene
	return scene.get_node_or_null("RoundManager") if scene != null else null


func apply_online_action(action: String, data: Dictionary) -> void:
	if _popped:
		return
	match action:
		"transform":
			_receive_network_snapshot(
				data.get("transform", global_transform),
				data.get("velocity", Vector3.ZERO))
		"toggle_control":
			toggle_control()
		"slow":
			_apply_slow_local(
				float(data.get("duration", 2.0)),
				float(data.get("multiplier", 0.5)))
		"launch":
			velocity.y = maxf(velocity.y, float(data.get("velocity", 11.0)))
		"spring_launch":
			var launch_direction := Vector3(initial_forward.x, 0.0, initial_forward.z).normalized()
			velocity.y = maxf(velocity.y, float(data.get("velocity", 13.0)))
			velocity.x += launch_direction.x * float(data.get("horizontal_boost", 4.0))
			velocity.z += launch_direction.z * float(data.get("horizontal_boost", 4.0))
		"pop":
			var attacker = NetworkManager.find_actor(
				int(data.get("attacker_id", -1)))
			if str(data.get("attack_kind", "")) == "gun":
				_reveal_shooter(attacker)
			_destroy_local(true)


func _destroy_local(spawn_pop: bool) -> void:
	if _popped:
		return
	_popped = true
	is_eliminated = true
	_visual_motion_speed = 0.0
	_clear_owner_reference()
	if spawn_pop and is_inside_tree():
		CombatPop.spawn(get_tree().current_scene, global_position)
	queue_free()


func _clear_owner_reference() -> void:
	if owner_player != null and is_instance_valid(owner_player) \
			and "active_decoy" in owner_player \
			and owner_player.get("active_decoy") == self:
		owner_player.set("active_decoy", null)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_clear_owner_reference()
