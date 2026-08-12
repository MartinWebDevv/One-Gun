extends Node

const MODEL_PATH := "res://models/player_v2/OGCatModelV2_Rigged.glb"
const VISUAL_PATH := "res://models/player_v2/player_v2_visual.tscn"
const PLAYER_PATH := "res://player.tscn"
const DECOY_PATH := "res://decoy_body.tscn"
const GUN_PATH := "res://gun.tscn"
const CUSTOMIZATION_SCRIPT = preload("res://UI/character_customization_overlay.gd")
const SkinRegistry = preload("res://player_skin_registry.gd")
const VisualScript = preload("res://models/player_v2/player_v2_visual.gd")

const EXPECTED_ANIMATIONS: Array[String] = [
	"idle", "idle_pistol", "long_idle", "standard_run", "run", "jump",
	"running_jump", "fall", "pistol_jump", "pistol_run", "pistol_backward",
	"pistol_strafe_left", "pistol_strafe_right", "run_with_sword", "melee",
	"throw_object", "hit", "hip_hop_dance", "swing_dance",
]

const EXPECTED_LOOPING: Array[String] = [
	"idle", "idle_pistol", "long_idle", "standard_run", "run", "fall",
	"pistol_run", "pistol_backward", "pistol_strafe_left",
	"pistol_strafe_right", "run_with_sword", "hip_hop_dance", "swing_dance",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		_fail("could not load %s" % MODEL_PATH)
		return
	var instance := packed.instantiate()
	add_child(instance)
	var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		_fail("Skeleton3D missing")
		return
	if skeleton.get_bone_count() != 33:
		_fail("expected 33 bones, found %d" % skeleton.get_bone_count())
		return
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null:
		_fail("master AnimationPlayer missing")
		return
	instance.queue_free()

	var visual_scene := load(VISUAL_PATH) as PackedScene
	if visual_scene == null:
		_fail("could not load %s" % VISUAL_PATH)
		return
	var visual := visual_scene.instantiate()
	add_child(visual)
	await get_tree().process_frame
	animation_player = visual.call("ensure_animation_library") as AnimationPlayer
	if animation_player == null:
		_fail("runtime AnimationPlayer missing")
		return
	var runtime_skeleton := visual.find_child(
		"Skeleton3D", true, false) as Skeleton3D
	var model_root := visual.get_node_or_null("Model") as Node3D
	if runtime_skeleton == null or model_root == null:
		_fail("shared visual rig hierarchy is incomplete")
		return
	if not model_root.position.is_zero_approx():
		_fail("shared visual model root is offset from its authored origin: %s" % model_root.position)
		return
	for expected_name in EXPECTED_ANIMATIONS:
		if not animation_player.has_animation(expected_name):
			_fail("runtime animation missing: %s" % expected_name)
			return
		var animation := animation_player.get_animation(expected_name)
		var should_loop := expected_name in EXPECTED_LOOPING
		if (animation.loop_mode != Animation.LOOP_NONE) != should_loop:
			_fail("animation loop mode is wrong: %s" % expected_name)
			return
		animation_player.play(expected_name)
		animation_player.advance(minf(animation.length * 0.5, 0.1))
		var hips_position_track := _bone_track(
			animation, Animation.TYPE_POSITION_3D, "mixamorig_Hips")
		if hips_position_track < 0 or animation.track_get_key_count(hips_position_track) == 0:
			_fail("runtime animation has no Hips position: %s" % expected_name)
			return
		var hips_anchor: Vector3 = animation.track_get_key_value(
			hips_position_track, 0)
		for key_index in animation.track_get_key_count(hips_position_track):
			var hips_position: Vector3 = animation.track_get_key_value(
				hips_position_track, key_index)
			if not is_equal_approx(hips_position.x, hips_anchor.x) \
					or not is_equal_approx(hips_position.z, hips_anchor.z):
				_fail("horizontal root motion was not stripped: %s" % expected_name)
				return
	# Compare every retargeted clip to its source FBX at multiple frames. Bone
	# rotations and bone-to-Hips positions must match exactly; only horizontal
	# Hips translation may differ because CharacterBody3D owns world movement.
	for animation_name in VisualScript.ANIMATION_SOURCES:
		var source_path: String = VisualScript.ANIMATION_SOURCES[animation_name]
		var pose_error := _compare_clip_to_source(
			str(animation_name), source_path, animation_player, runtime_skeleton)
		if not pose_error.is_empty():
			_fail(pose_error)
			return
	for point_name in ["GunHoldPoint", "MeleeHoldPoint", "ItemHoldPoint"]:
		if visual.find_child(point_name, true, false) == null:
			_fail("runtime hold point missing: %s" % point_name)
			return
	for skin in SkinRegistry.SKINS:
		var skin_id := str(skin["id"])
		if SkinRegistry.load_texture(skin_id) == null:
			_fail("skin texture missing: %s" % skin_id)
			return
		visual.call("set_skin", skin_id)
	var expected_texture := SkinRegistry.load_texture(
		SkinRegistry.skin_id_at(SkinRegistry.skin_count() - 1))
	var material_applied := false
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var skinned_mesh := child as MeshInstance3D
		for surface_index in skinned_mesh.get_surface_override_material_count():
			var material := skinned_mesh.get_surface_override_material(
				surface_index) as StandardMaterial3D
			if material != null and material.albedo_texture == expected_texture:
				material_applied = true
				break
	if not material_applied:
		_fail("selected skin texture was not applied to a mesh material")
		return
	animation_player.play("idle")
	animation_player.advance(0.0)

	var combined := AABB()
	var has_bounds := false
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var world_aabb := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		combined = world_aabb if not has_bounds else combined.merge(world_aabb)
		has_bounds = true
	if not has_bounds or combined.size.y < 1.5 or combined.size.y > 3.0:
		_fail("runtime visual bounds are invalid: %s" % combined)
		return

	var player_scene := load(PLAYER_PATH) as PackedScene
	if player_scene == null:
		_fail("could not load %s" % PLAYER_PATH)
		return
	var player := player_scene.instantiate()
	add_child(player)
	var initial_player_animation := player.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer
	if initial_player_animation == null \
			or initial_player_animation.current_animation != "idle":
		_fail("player does not evaluate Idle immediately on spawn")
		return
	await get_tree().process_frame
	if player.call("get_hold_point") == null \
			or player.call("get_melee_hold_point") == null \
			or player.call("get_item_hold_point") == null:
		_fail("player scene did not expose all V2 hold points")
		return
	var character_model := player.get_node_or_null("CharacterModel") as Node3D
	if character_model == null or absf(character_model.position.y + 1.09) > 0.001:
		_fail("player visual is not aligned with the capsule bottom")
		return

	player.call("set_character_skin", "salmon")
	player.set_physics_process(false)
	var expected_player_texture := SkinRegistry.load_texture("salmon")
	if not _all_standard_surfaces_use_texture(
			player.get_node_or_null("CharacterModel"), expected_player_texture):
		_fail("selected character texture was missing before hit-flash regression")
		return
	var accessibility_values: Dictionary = PlayerPrefs.settings.duplicate(true)
	var flash_test_values := accessibility_values.duplicate(true)
	flash_test_values["reduce_flashing"] = false
	AccessibilityManager.preview_policy(flash_test_values)
	player.call("flash_hit")
	await get_tree().create_timer(0.02).timeout
	player.call("flash_hit")
	await get_tree().create_timer(0.30).timeout
	AccessibilityManager.preview_policy(accessibility_values)
	if not _all_standard_surfaces_use_texture(
			player.get_node_or_null("CharacterModel"), expected_player_texture):
		_fail("overlapping hit flashes removed the selected character texture")
		return

	var gun_scene := load(GUN_PATH) as PackedScene
	if gun_scene == null:
		_fail("could not load %s" % GUN_PATH)
		return
	var held_gun = gun_scene.instantiate()
	add_child(held_gun)
	held_gun.call("_local_pickup", player)
	player.set("active_slot", "weapon")
	player.call("play_victory_dance")
	await get_tree().process_frame
	if held_gun.visible:
		_fail("held gun remained visible during the victory dance")
		return
	player.set("holding_gun", false)
	held_gun.queue_free()

	var decoy_scene := load(DECOY_PATH) as PackedScene
	if decoy_scene == null:
		_fail("could not load %s" % DECOY_PATH)
		return
	var decoy := decoy_scene.instantiate()
	decoy.set("owner_player", player)
	add_child(decoy)
	await get_tree().process_frame
	var decoy_visual := decoy.get_node_or_null("VisualRoot/CatModel")
	var decoy_player := decoy.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer
	if str(decoy.get("character_skin_id")) != "salmon" \
			or decoy_visual == null or str(decoy_visual.get("skin_id")) != "salmon":
		_fail("decoy did not copy its owner's selected color")
		return
	if decoy_player == null or not decoy_player.has_animation("idle") \
			or not decoy_player.has_animation("standard_run"):
		_fail("decoy lightweight animation set is incomplete")
		return
	decoy.queue_free()

	var original_p2_skin := str(GameConfig.player2_skin_id)
	GameConfig.player2_skin_id = SkinRegistry.skin_id_at(SkinRegistry.skin_count() - 1)
	var customization := CUSTOMIZATION_SCRIPT.new()
	customization.configure(false, 2)
	add_child(customization)
	await get_tree().process_frame
	await get_tree().process_frame
	if customization.find_children("*", "SubViewport", true, false).size() != 1:
		_fail("split-screen customization did not build its shared preview")
		return
	var preview_characters := customization.find_children(
		"PreviewCharacter", "Node3D", true, false)
	if preview_characters.size() != 1:
		_fail("customization shared preview character is missing")
		return
	for preview_character in preview_characters:
		var preview_model := preview_character.get_node_or_null("Model") as Node3D
		var preview_player := preview_character.find_child(
			"AnimationPlayer", true, false) as AnimationPlayer
		if preview_model == null or not preview_model.position.is_zero_approx() \
				or preview_player == null or preview_player.current_animation != "idle":
			_fail("customization preview is not centered in an evaluated Idle pose")
			return
	var canvas := customization.find_child(
		"CustomizationCanvas", true, false) as Control
	var back_button := customization.find_child("Back", true, false) as Control
	if canvas == null or back_button == null \
			or not canvas.get_global_rect().encloses(back_button.get_global_rect()) \
			or customization.find_child("Player1Tab", true, false) == null \
			or customization.find_child("Player2Tab", true, false) == null:
		_fail("customization controls or local player tabs are out of frame")
		return
	customization.call("_set_active_slot", 1)
	customization.call("_cycle_skin", 1)
	if str(customization._pending_skin_ids.get(1, "")) != SkinRegistry.skin_id_at(0) \
			or str(GameConfig.player2_skin_id) != SkinRegistry.skin_id_at(
				SkinRegistry.skin_count() - 1):
		_fail("P2 pending color did not wrap independently before Confirm")
		return
	GameConfig.player2_skin_id = original_p2_skin
	customization.queue_free()
	await get_tree().process_frame

	print("PLAYER_V2_VALIDATION_OK bones=33 animations=%d skins=%d decoy=true customization=true bounds=%s" % [
		EXPECTED_ANIMATIONS.size(), SkinRegistry.skin_count(), combined])
	get_tree().quit(0)


func _compare_clip_to_source(animation_name: String, source_path: String,
		target_player: AnimationPlayer, target_skeleton: Skeleton3D) -> String:
	var source_scene := load(source_path) as PackedScene
	if source_scene == null:
		return "could not load animation source: %s" % source_path
	var source_instance := source_scene.instantiate() as Node3D
	add_child(source_instance)
	var source_player := source_instance.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer
	var source_skeleton := source_instance.find_child(
		"Skeleton3D", true, false) as Skeleton3D
	var source_animation := _first_animation(source_player)
	if source_player == null or source_skeleton == null or source_animation == null:
		source_instance.free()
		return "animation source rig is incomplete: %s" % animation_name
	var target_animation := target_player.get_animation(animation_name)
	var sample_times: Array[float] = [
		0.0,
		minf(target_animation.length * 0.25, 0.2),
		minf(target_animation.length * 0.60, 0.4),
	]
	var source_animation_name := ""
	for candidate in source_player.get_animation_list():
		if candidate != "RESET":
			source_animation_name = candidate
			break
	var target_hips_index := target_skeleton.find_bone("mixamorig_Hips")
	var source_hips_index := source_skeleton.find_bone("mixamorig_Hips")
	var source_offset := VisualScript.THROW_SOURCE_RANGE.x \
		if animation_name == "throw_object" else 0.0
	for sample_time in sample_times:
		target_player.play(animation_name, 0.0)
		target_player.seek(sample_time, true)
		target_player.advance(0.0)
		source_player.play(source_animation_name, 0.0)
		source_player.seek(minf(source_offset + sample_time, source_animation.length), true)
		source_player.advance(0.0)
		var target_hips := target_skeleton.get_bone_global_pose(target_hips_index)
		var source_hips := source_skeleton.get_bone_global_pose(source_hips_index)
		if absf(target_hips.origin.y - source_hips.origin.y) > 0.00015:
			source_instance.free()
			return "vertical Hips motion differs from source: %s" % animation_name
		for target_index in target_skeleton.get_bone_count():
			var bone_name := target_skeleton.get_bone_name(target_index)
			var source_index := source_skeleton.find_bone(bone_name)
			if source_index < 0:
				source_instance.free()
				return "source bone missing during pose comparison: %s" % bone_name
			var target_pose := target_skeleton.get_bone_global_pose(target_index)
			var source_pose := source_skeleton.get_bone_global_pose(source_index)
			var target_relative := target_pose.origin - target_hips.origin
			var source_relative := source_pose.origin - source_hips.origin
			if target_relative.distance_to(source_relative) > 0.0002:
				source_instance.free()
				return "retargeted bone position differs: %s/%s" % [
					animation_name, bone_name]
			var target_rotation := target_pose.basis.orthonormalized() \
				.get_rotation_quaternion()
			var source_rotation := source_pose.basis.orthonormalized() \
				.get_rotation_quaternion()
			if absf(target_rotation.dot(source_rotation)) < 0.9995:
				source_instance.free()
				return "retargeted bone rotation differs: %s/%s" % [
					animation_name, bone_name]
	source_instance.free()
	return ""


func _fail(message: String) -> void:
	push_error("PLAYER_V2_VALIDATION_FAILED: %s" % message)
	get_tree().quit(1)


func _first_animation(player: AnimationPlayer) -> Animation:
	if player == null:
		return null
	for animation_name in player.get_animation_list():
		if animation_name != "RESET":
			return player.get_animation(animation_name)
	return null


func _bone_track(animation: Animation, track_type: Animation.TrackType,
		bone_name: String) -> int:
	if animation == null:
		return -1
	for track_index in animation.get_track_count():
		if animation.track_get_type(track_index) != track_type:
			continue
		var path := animation.track_get_path(track_index)
		if path.get_subname_count() > 0 \
				and str(path.get_subname(path.get_subname_count() - 1)) == bone_name:
			return track_index
	return -1


func _all_standard_surfaces_use_texture(root: Node, expected: Texture2D) -> bool:
	if root == null or expected == null:
		return false
	var checked := 0
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_surface_override_material(
				surface_index) as StandardMaterial3D
			if material == null:
				continue
			checked += 1
			if material.albedo_texture != expected:
				print("PLAYER_V2_SKIN_MISMATCH mesh=", mesh_instance.name,
					" surface=", surface_index,
					" expected=", expected.resource_path,
					" actual=", material.albedo_texture.resource_path
						if material.albedo_texture != null else "<null>")
				return false
	return checked > 0
