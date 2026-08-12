class_name PlayerV2Visual
extends Node3D

const SkinRegistry = preload("res://player_skin_registry.gd")
const MASTER_RIG_PATH := "res://models/player_v2/animations/Idle.fbx"
const RETARGET_STEP := 1.0 / 30.0
const THROW_SOURCE_RANGE := Vector2(2.75, 3.60)
const GUN_IDLE_PITCH := deg_to_rad(55.0)
const GUN_IDLE_POSITION_OFFSET := Vector3(0.0, -0.65, 0.0)
const GUN_IDLE_BLEND_DURATION := 0.16

const LOOPING_ANIMATIONS: Array[String] = [
	"idle", "long_idle", "standard_run", "run", "fall", "pistol_run",
	"pistol_backward", "pistol_strafe_left", "pistol_strafe_right",
	"run_with_sword", "hip_hop_dance", "swing_dance",
]

const ANIMATION_SOURCES := {
	"long_idle": "res://models/player_v2/animations/long Idle.fbx",
	"standard_run": "res://models/player_v2/animations/Standard Run.fbx",
	"run": "res://models/player_v2/animations/Running.fbx",
	"jump": "res://models/player_v2/animations/Jumping.fbx",
	"running_jump": "res://models/player_v2/animations/Running Jump.fbx",
	"fall": "res://models/player_v2/animations/Fall A Loop.fbx",
	"pistol_jump": "res://models/player_v2/animations/Pistol Jump.fbx",
	"pistol_run": "res://models/player_v2/animations/Pistol Run.fbx",
	"pistol_backward": "res://models/player_v2/animations/Pistol Run Backward.fbx",
	"pistol_strafe_left": "res://models/player_v2/animations/Pistol Strafe LEFT.fbx",
	"pistol_strafe_right": "res://models/player_v2/animations/Pistol Strafe RIGHT.fbx",
	"run_with_sword": "res://models/player_v2/animations/Run With Sword.fbx",
	"melee": "res://models/player_v2/animations/melee.fbx",
	"throw_object": "res://models/player_v2/animations/Throw Object.fbx",
	"hit": "res://models/player_v2/animations/Hit.fbx",
	"hip_hop_dance": "res://models/player_v2/animations/Hip Hop Dancing.fbx",
	"swing_dance": "res://models/player_v2/animations/Swing Dancing.fbx",
}

const SOCKET_OFFSETS := {
	"GunHoldPoint": Vector3(-0.16, 0.02, 0.04),
	"MeleeHoldPoint": Vector3(-0.05, 0.08, 0.0),
	"ItemHoldPoint": Vector3(-0.03, 0.04, -0.03),
}
const SOCKET_ROTATIONS := {
	# Gun and melee transforms were authored against the original player's
	# player-aligned, 180-degree hold markers. Follow the V2 hand position, but
	# retain those stable marker axes so assets do not inherit the Mixamo wrist
	# roll and point sideways or behind the character.
	"GunHoldPoint": Vector3.ZERO,
	"MeleeHoldPoint": Vector3.ZERO,
	"ItemHoldPoint": Vector3(0.0, PI, 0.0),
}

static var _animation_cache: Dictionary = {}
static var _master_bone_names: Array[String] = []
static var _master_bone_parents := PackedInt32Array()
static var _master_global_rests: Array[Transform3D] = []
@export var skin_id := SkinRegistry.DEFAULT_SKIN_ID
@export var build_animation_library := true

var _animation_player: AnimationPlayer = null
var _skeleton: Skeleton3D = null
var _right_hand_index := -1
var _foot_bone_indices := {"left": -1, "right": -1}
var _skin_materials: Array[StandardMaterial3D] = []
var _toe_bone_indices := {"left": -1, "right": -1}
var _skin_material_bindings: Array = []
var _hold_points: Dictionary = {}
var _foot_points: Dictionary = {}
var _gun_idle_blend := 0.0


func _ready() -> void:
	# AnimationPlayer updates at the default priority. Run socket sampling after
	# it so held weapons/items follow the current hand pose, not the prior frame.
	process_priority = 100
	_animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	_prepare_unique_skin_materials()
	set_skin(skin_id)
	_setup_hold_points()
	_setup_foot_points()
	if build_animation_library:
		ensure_animation_library()


func _process(delta: float) -> void:
	_update_gun_idle_blend(delta)
	_update_hold_points()
	_update_foot_points()


func _update_gun_idle_blend(delta: float) -> void:
	var should_lower := _animation_player != null \
		and _animation_player.current_animation == "idle_pistol"
	var target := 1.0 if should_lower else 0.0
	_gun_idle_blend = move_toward(
		_gun_idle_blend, target, delta / GUN_IDLE_BLEND_DURATION)


func get_animation_player() -> AnimationPlayer:
	return _animation_player


func get_skeleton() -> Skeleton3D:
	return _skeleton


func get_character_mesh_instances() -> Array[MeshInstance3D]:
	# Return only meshes that belong to the imported character skin. Held props
	# are attached beneath the runtime socket markers after this binding list is
	# prepared and must not inherit character-only reveal/outline materials.
	var result: Array[MeshInstance3D] = []
	for binding in _skin_material_bindings:
		var mesh_instance := binding.get("mesh") as MeshInstance3D
		if is_instance_valid(mesh_instance) and not result.has(mesh_instance):
			result.append(mesh_instance)
	return result


func set_skin(requested_id: String) -> void:
	skin_id = SkinRegistry.sanitize_skin_id(requested_id)
	var texture := SkinRegistry.load_texture(skin_id)
	if texture == null:
		push_warning("PlayerV2Visual: texture is unavailable for skin '%s'." % skin_id)
		return
	if _skin_materials.is_empty():
		_prepare_unique_skin_materials()
	for binding in _skin_material_bindings:
		var material := binding.get("material") as StandardMaterial3D
		var mesh_instance := binding.get("mesh") as MeshInstance3D
		var surface_index := int(binding.get("surface", -1))
		if material == null:
			continue
		material.albedo_texture = texture
		# Rebind the authoritative per-instance material as well as updating its
		# texture. Temporary hit effects replace surface overrides; rebinding here
		# guarantees an interrupted/overlapping effect cannot strand the mesh on a
		# textureless material.
		if is_instance_valid(mesh_instance) and mesh_instance.mesh != null \
				and surface_index >= 0 \
				and surface_index < mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface_index, material)


func ensure_animation_library() -> AnimationPlayer:
	var requested: Array[String] = ["idle", "idle_pistol"]
	for animation_name in ANIMATION_SOURCES:
		requested.append(str(animation_name))
	return ensure_animations(requested)


func ensure_animations(requested: Array) -> AnimationPlayer:
	if _animation_player == null:
		_animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player == null:
		push_warning("PlayerV2Visual: the rig has no AnimationPlayer.")
		return null
	if not _animation_player.has_animation_library(""):
		_animation_player.add_animation_library("", AnimationLibrary.new())
	var library := _animation_player.get_animation_library("")
	for requested_name in requested:
		var animation_name := str(requested_name)
		_cache_animation(animation_name)
		if _animation_cache.has(animation_name) \
				and not library.has_animation(animation_name):
			library.add_animation(animation_name, _animation_cache[animation_name])
	return _animation_player


func _prepare_unique_skin_materials() -> void:
	if not _skin_materials.is_empty():
		return
	for child in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface_index) as StandardMaterial3D
			if source == null:
				continue
			var local_material := source.duplicate(true) as StandardMaterial3D
			mesh_instance.set_surface_override_material(surface_index, local_material)
			_skin_materials.append(local_material)
			_skin_material_bindings.append({
				"mesh": mesh_instance,
				"surface": surface_index,
				"material": local_material,
			})


func _setup_hold_points() -> void:
	if _skeleton == null:
		return
	_right_hand_index = _skeleton.find_bone("mixamorig_RightHand")
	if _right_hand_index < 0:
		push_warning("PlayerV2Visual: mixamorig_RightHand is missing.")
		return
	for point_name in SOCKET_OFFSETS:
		var marker := Marker3D.new()
		marker.name = point_name
		marker.top_level = true
		add_child(marker)
		_hold_points[point_name] = marker
	_update_hold_points()


func _update_hold_points() -> void:
	if _skeleton == null or _right_hand_index < 0 or _hold_points.is_empty():
		return
	var hand_transform := _skeleton.global_transform * _skeleton.get_bone_global_pose(_right_hand_index)
	var hand_basis := hand_transform.basis.orthonormalized()
	var visual_basis := global_basis.orthonormalized()
	for point_name in _hold_points:
		var marker := _hold_points[point_name] as Marker3D
		if marker == null:
			continue
		var offset: Vector3 = SOCKET_OFFSETS[point_name]
		var socket_rotation: Vector3 = SOCKET_ROTATIONS[point_name]
		var socket_position := hand_transform.origin + hand_basis * offset
		if point_name == "GunHoldPoint":
			socket_rotation.x += GUN_IDLE_PITCH * _gun_idle_blend
			socket_position += visual_basis * GUN_IDLE_POSITION_OFFSET * _gun_idle_blend
		marker.global_transform = Transform3D(
			visual_basis * Basis.from_euler(socket_rotation),
			socket_position)



func _setup_foot_points() -> void:
	if _skeleton == null:
		return
	for side in ["left", "right"]:
		var bone_name := "mixamorig_LeftFoot" if side == "left" else "mixamorig_RightFoot"
		var bone_index := _skeleton.find_bone(bone_name)
		_foot_bone_indices[side] = bone_index
		var toe_name := "mixamorig_LeftToeBase" if side == "left" else "mixamorig_RightToeBase"
		var toe_index := _skeleton.find_bone(toe_name)
		_toe_bone_indices[side] = toe_index
		if bone_index < 0:
			push_warning("PlayerV2Visual: %s is missing." % bone_name)
			continue
		var marker := Marker3D.new()
		marker.name = "%sFootSocket" % side.capitalize()
		marker.top_level = true
		add_child(marker)
		_foot_points[side] = marker
	_update_foot_points()


func _update_foot_points() -> void:
	if _skeleton == null or _foot_points.is_empty():
		return
	for side in _foot_points:
		var marker := _foot_points[side] as Marker3D
		var bone_index := int(_foot_bone_indices.get(side, -1))
		if marker == null or bone_index < 0:
			continue
		var foot_transform := _skeleton.global_transform \
			* _skeleton.get_bone_global_pose(bone_index)
		var sole_position := foot_transform.origin
		var toe_index := int(_toe_bone_indices.get(side, -1))
		if toe_index >= 0:
			var toe_transform := _skeleton.global_transform \
				* _skeleton.get_bone_global_pose(toe_index)
			sole_position = foot_transform.origin.lerp(toe_transform.origin, 0.65)
		var visual_basis := global_basis.orthonormalized()
		sole_position -= visual_basis.y * 0.015
		# Follow animation but keep the shoe character-facing and sole-down.
		marker.global_transform = Transform3D(visual_basis, sole_position)


func get_foot_socket(left_foot: bool) -> Marker3D:
	return _foot_points.get("left" if left_foot else "right") as Marker3D

static func _cache_animation(animation_name: String) -> void:
	if _animation_cache.has(animation_name):
		return
	if animation_name == "idle_pistol":
		_cache_animation("idle")
		if _animation_cache.has("idle"):
			_animation_cache["idle_pistol"] = _animation_cache["idle"]
		return
	if animation_name == "idle":
		var model_scene := load(MASTER_RIG_PATH) as PackedScene
		if model_scene == null:
			return
		var model_instance := model_scene.instantiate()
		var model_player := model_instance.find_child(
			"AnimationPlayer", true, false) as AnimationPlayer
		var model_skeleton := model_instance.find_child(
			"Skeleton3D", true, false) as Skeleton3D
		_cache_master_profile(model_skeleton)
		var idle := _first_animation(model_player)
		if idle != null:
			var prepared_idle := _prepare_animation(
				idle, "idle", model_skeleton)
			if prepared_idle != null:
				_animation_cache["idle"] = prepared_idle
		model_instance.free()
		return
	if not ANIMATION_SOURCES.has(animation_name):
		return
	var source_path: String = ANIMATION_SOURCES[animation_name]
	var packed := load(source_path) as PackedScene
	if packed == null:
		push_warning("PlayerV2Visual: could not load animation source %s" % source_path)
		return
	var instance := packed.instantiate()
	var source_player := instance.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer
	var source_skeleton := instance.find_child(
		"Skeleton3D", true, false) as Skeleton3D
	var source_animation := _first_animation(source_player)
	if source_animation != null and source_skeleton != null:
		var prepared := _prepare_animation(
			source_animation, animation_name, source_skeleton)
		if prepared != null:
			_animation_cache[animation_name] = prepared
	instance.free()


static func _first_animation(player: AnimationPlayer) -> Animation:
	if player == null:
		return null
	for animation_name in player.get_animation_list():
		if animation_name != "RESET":
			return player.get_animation(animation_name)
	return null


static func _prepare_animation(source: Animation, animation_name: String,
		source_skeleton: Skeleton3D) -> Animation:
	if source_skeleton == null or _master_bone_names.is_empty():
		push_warning("PlayerV2Visual: master bind profile is unavailable.")
		return null
	var source_indices: PackedInt32Array = []
	for bone_name in _master_bone_names:
		var source_index := source_skeleton.find_bone(bone_name)
		if source_index < 0:
			push_warning("PlayerV2Visual: source clip is missing bone %s." % bone_name)
			return null
		source_indices.append(source_index)
	var source_tracks := _animation_bone_tracks(source)
	var source_start := THROW_SOURCE_RANGE.x \
		if animation_name == "throw_object" else 0.0
	var source_end := minf(THROW_SOURCE_RANGE.y, source.length) \
		if animation_name == "throw_object" else source.length
	var target_length := maxf(source_end - source_start, RETARGET_STEP)
	var sample_times: Array[float] = []
	var sample_count := ceili(target_length / RETARGET_STEP)
	for sample_index in range(sample_count + 1):
		sample_times.append(minf(sample_index * RETARGET_STEP, target_length))
	if sample_times.is_empty() or sample_times[-1] < target_length - 0.00001:
		sample_times.append(target_length)

	var baked_positions: Array = []
	var baked_rotations: Array = []
	var baked_scales: Array = []
	for _bone_index in _master_bone_names.size():
		baked_positions.append([])
		baked_rotations.append([])
		baked_scales.append([])
	var source_globals: Array[Transform3D] = []
	source_globals.resize(source_skeleton.get_bone_count())
	var target_globals: Array[Transform3D] = []
	target_globals.resize(_master_bone_names.size())
	var hips_index := _master_bone_names.find("mixamorig_Hips")
	var hips_horizontal_anchor := Vector2.ZERO

	for sample_index in sample_times.size():
		var sample_time := sample_times[sample_index]
		var source_sample_time := source_start + sample_time
		for source_index in source_skeleton.get_bone_count():
			var source_local := _sample_source_bone(
				source, source_skeleton, source_tracks, source_index, source_sample_time)
			var source_parent := source_skeleton.get_bone_parent(source_index)
			source_globals[source_index] = source_local \
				if source_parent < 0 else source_globals[source_parent] * source_local
		for target_index in _master_bone_names.size():
			var source_index := source_indices[target_index]
			var source_deformation := source_globals[source_index] \
				* source_skeleton.get_bone_global_rest(source_index).affine_inverse()
			target_globals[target_index] = source_deformation \
				* _master_global_rests[target_index]
		for target_index in _master_bone_names.size():
			var target_parent := _master_bone_parents[target_index]
			var target_local := target_globals[target_index] \
				if target_parent < 0 else target_globals[target_parent].affine_inverse() \
				* target_globals[target_index]
			var position := target_local.origin
			if target_index == hips_index:
				if sample_index == 0:
					hips_horizontal_anchor = Vector2(position.x, position.z)
				position.x = hips_horizontal_anchor.x
				position.z = hips_horizontal_anchor.y
			baked_positions[target_index].append(position)
			baked_rotations[target_index].append(
				target_local.basis.orthonormalized().get_rotation_quaternion())
			baked_scales[target_index].append(target_local.basis.get_scale())

	var animation := Animation.new()
	animation.length = target_length
	animation.step = RETARGET_STEP
	animation.loop_mode = Animation.LOOP_LINEAR \
		if animation_name in LOOPING_ANIMATIONS else Animation.LOOP_NONE
	for bone_index in _master_bone_names.size():
		_add_baked_track(animation, Animation.TYPE_POSITION_3D,
			_master_bone_names[bone_index], baked_positions[bone_index], sample_times,
			_values_vary(baked_positions[bone_index]))
		_add_baked_track(animation, Animation.TYPE_ROTATION_3D,
			_master_bone_names[bone_index], baked_rotations[bone_index], sample_times, true)
		_add_baked_track(animation, Animation.TYPE_SCALE_3D,
			_master_bone_names[bone_index], baked_scales[bone_index], sample_times,
			_values_vary(baked_scales[bone_index]))
	return animation


static func _cache_master_profile(skeleton: Skeleton3D) -> void:
	if skeleton == null or not _master_bone_names.is_empty():
		return
	for bone_index in skeleton.get_bone_count():
		_master_bone_names.append(skeleton.get_bone_name(bone_index))
		_master_bone_parents.append(skeleton.get_bone_parent(bone_index))
		_master_global_rests.append(skeleton.get_bone_global_rest(bone_index))


static func _animation_bone_tracks(animation: Animation) -> Dictionary:
	var tracks := {}
	for track_index in animation.get_track_count():
		var type := animation.track_get_type(track_index)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D,
				Animation.TYPE_SCALE_3D]:
			continue
		var path := animation.track_get_path(track_index)
		if path.get_subname_count() == 0:
			continue
		var bone_name := str(path.get_subname(path.get_subname_count() - 1))
		if not tracks.has(bone_name):
			tracks[bone_name] = {}
		tracks[bone_name][type] = track_index
	return tracks


static func _sample_source_bone(animation: Animation, skeleton: Skeleton3D,
		tracks: Dictionary, bone_index: int, sample_time: float) -> Transform3D:
	var rest := skeleton.get_bone_rest(bone_index)
	var position := rest.origin
	var rotation := rest.basis.orthonormalized().get_rotation_quaternion()
	var scale := rest.basis.get_scale()
	var bone_name := skeleton.get_bone_name(bone_index)
	if tracks.has(bone_name):
		var bone_tracks: Dictionary = tracks[bone_name]
		if bone_tracks.has(Animation.TYPE_POSITION_3D):
			position = animation.position_track_interpolate(
				bone_tracks[Animation.TYPE_POSITION_3D], sample_time)
		if bone_tracks.has(Animation.TYPE_ROTATION_3D):
			rotation = animation.rotation_track_interpolate(
				bone_tracks[Animation.TYPE_ROTATION_3D], sample_time)
		if bone_tracks.has(Animation.TYPE_SCALE_3D):
			scale = animation.scale_track_interpolate(
				bone_tracks[Animation.TYPE_SCALE_3D], sample_time)
	return Transform3D(Basis(rotation).scaled(scale), position)


static func _add_baked_track(animation: Animation, type: Animation.TrackType,
		bone_name: String, values: Array, sample_times: Array[float],
		write_all_keys: bool) -> void:
	var track_index := animation.add_track(type)
	animation.track_set_path(track_index, NodePath("Skeleton3D:" + bone_name))
	var key_count := values.size() if write_all_keys else mini(values.size(), 1)
	for key_index in key_count:
		animation.track_insert_key(
			track_index, sample_times[key_index], values[key_index])


static func _values_vary(values: Array) -> bool:
	if values.size() < 2:
		return false
	var first: Vector3 = values[0]
	for value in values:
		if first.distance_to(value) > 0.00001:
			return true
	return false
