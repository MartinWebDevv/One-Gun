extends Node

const PLAYER_PATH := "res://player.tscn"
const DECOY_PATH := "res://decoy_body.tscn"
const CUSTOMIZATION_SCRIPT = preload("res://UI/character_customization_overlay.gd")
const FEMALE_MODEL_PATH := "res://models/player_v2/femaleOGCat/femaleOGCatRigged.glb"


func _ready() -> void:
	if PlayerV2Visual.IDLE_SOURCE_PATH != PlayerV2Visual.MASTER_RIG_PATH:
		_fail("female and male cats do not share the master idle animation source")
	_run.call_deferred()


func _run() -> void:
	var rig_scene := load(FEMALE_MODEL_PATH) as PackedScene
	if rig_scene == null:
		_fail("female rig scene could not be loaded")
		return
	var rig := rig_scene.instantiate()
	add_child(rig)
	var source_skeleton := rig.find_child(
		"Skeleton3D", true, false) as Skeleton3D
	if source_skeleton == null or source_skeleton.get_bone_count() != 33:
		_fail("female rig must expose the compatible 33-bone skeleton")
		return
	var skinned_surfaces := 0
	for child in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.skin != null and mesh_instance.mesh != null:
			skinned_surfaces += mesh_instance.mesh.get_surface_count()
	if skinned_surfaces < 2:
		_fail("female rigged model does not expose both skinned mesh surfaces")
		return
	rig.queue_free()

	var visual_scene := PlayerSkinRegistry.load_visual_scene("female")
	if visual_scene == null:
		_fail("female shared visual scene could not be loaded")
		return
	var visual := visual_scene.instantiate()
	add_child(visual)
	await get_tree().process_frame
	var animation_player := visual.call(
		"ensure_animation_library") as AnimationPlayer
	var skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if animation_player == null or skeleton == null:
		_fail("female visual did not build its runtime animation rig")
		return
	var expected_animations: Array[String] = ["idle", "idle_pistol"]
	for animation_name in PlayerV2Visual.ANIMATION_SOURCES:
		expected_animations.append(str(animation_name))
	for animation_name in expected_animations:
		if not animation_player.has_animation(animation_name):
			visual.call("ensure_animations", [animation_name])
		if not animation_player.has_animation(animation_name):
			_fail("female runtime animation missing: %s" % animation_name)
			return
	for animation_name in ["idle", "standard_run", "melee"]:
		animation_player.play(animation_name, 0.0)
		animation_player.advance(0.08)
		var pose_error := _animated_pose_error(skeleton)
		if not pose_error.is_empty():
			_fail("%s pose is invalid: %s" % [animation_name, pose_error])
			return
	if str(visual.get("model_id")) != "female":
		_fail("female visual did not identify its model family")
		return
	for skin in PlayerSkinRegistry.SKINS:
		var skin_id := str(skin["id"])
		if PlayerSkinRegistry.load_texture(skin_id, "female") == null:
			_fail("female color texture missing: %s" % skin_id)
			return
		if PlayerSkinRegistry.load_portrait(skin_id, "female") == null:
			_fail("female portrait missing: %s" % skin_id)
			return
	visual.queue_free()

	var player_scene := load(PLAYER_PATH) as PackedScene
	var player := player_scene.instantiate()
	add_child(player)
	await get_tree().process_frame
	player.call("set_character_appearance", "female", "salmon")
	player.set_physics_process(false)
	await get_tree().process_frame
	var player_visual := player.get_node_or_null("CharacterModel")
	var salmon_texture := PlayerSkinRegistry.load_texture("salmon", "female")
	var salmon_chest_texture := PlayerSkinRegistry.load_female_chest_texture("salmon")
	if str(player.get("character_model_id")) != "female" \
			or player_visual == null \
			or str(player_visual.get("model_id")) != "female":
		_fail("player did not switch to the female model")
		return
	if not _female_surfaces_use_textures(
			player_visual, salmon_texture, salmon_chest_texture):
		_fail("female salmon face/body and chest textures were not split correctly")
		return
	if not is_equal_approx(player_visual.scale.x, 0.55):
		_fail("live player did not keep the female scene scale")
		return

	var decoy_scene := load(DECOY_PATH) as PackedScene
	var decoy := decoy_scene.instantiate()
	decoy.set("owner_player", player)
	add_child(decoy)
	await get_tree().process_frame
	var decoy_visual := decoy.get_node_or_null("VisualRoot/CatModel")
	if str(decoy.get("character_model_id")) != "female" \
			or decoy_visual == null \
			or str(decoy_visual.get("model_id")) != "female":
		_fail("decoy did not inherit its owner's female model")
		return
	if not _female_surfaces_use_textures(
			decoy_visual, salmon_texture, salmon_chest_texture):
		_fail("decoy did not inherit the split female color surfaces")
		return
	if not is_equal_approx(decoy_visual.scale.x, 0.55):
		_fail("decoy did not keep the female scene scale")
		return
	decoy.queue_free()

	var original_model := str(PlayerPrefs.get_setting("character_model_id"))
	var overlay = CUSTOMIZATION_SCRIPT.new()
	overlay.configure(false, 1)
	add_child(overlay)
	await get_tree().process_frame
	await get_tree().process_frame
	if overlay.find_child("MaleModel", true, false) == null \
			or overlay.find_child("FemaleModel", true, false) == null:
		_fail("customization is missing the M/F model buttons")
		return
	overlay.call("_select_model", "female")
	await get_tree().process_frame
	var preview := overlay.find_child("PreviewCharacter", true, false)
	if str(overlay._pending_model_ids.get(0, "")) != "female" \
			or preview == null or str(preview.get("model_id")) != "female":
		_fail("F did not switch the isolated customization preview")
		return
	if str(PlayerPrefs.get_setting("character_model_id")) != original_model:
		_fail("preview model selection leaked before Confirm")
		return
	overlay.call("_cancel")
	await get_tree().process_frame

	var roster_row := OneGunRosterRow.new()
	add_child(roster_row)
	roster_row.set_human("Remote Player", false, false,
		OneGunRosterRow.ReadyState.READY, "purple", "female")
	await get_tree().process_frame
	var portraits := roster_row.find_children("PlayerPortrait", "", true, false)
	var portrait = portraits[0] if not portraits.is_empty() else null
	if portrait == null or str(portrait.model_id) != "female" \
			or str(portrait.skin_id) != "purple" or portrait.texture == null:
		_fail("online roster row did not resolve the female appearance")
		return

	print("FEMALE_PLAYER_V2_VALIDATION_OK bones=33 animations=19 colors=13 portraits=13 decoy=true customization=true")
	get_tree().quit(0)


func _animated_pose_error(skeleton: Skeleton3D) -> String:
	var hips := _bone_world_position(skeleton, "mixamorig_Hips")
	var head := _bone_world_position(skeleton, "mixamorig_Head")
	var left_toe := _bone_world_position(skeleton, "mixamorig_LeftToeBase")
	var right_toe := _bone_world_position(skeleton, "mixamorig_RightToeBase")
	if head.y < 1.3 or head.y > 2.2:
		return "head height %s is outside gameplay scale" % head
	if hips.y < 0.65 or hips.y > 1.2:
		return "hips height %s is outside gameplay scale" % hips
	if head.y - hips.y < 0.55:
		return "head is not upright above hips (%s vs %s)" % [head, hips]
	if Vector2(head.x - hips.x, head.z - hips.z).length() > 0.8:
		return "upper body is displaced from hips (%s vs %s)" % [head, hips]
	for toe in [left_toe, right_toe]:
		if toe.y < -0.1 or toe.y > 0.65:
			return "foot height is invalid: %s" % toe
	if absf(left_toe.y - right_toe.y) > 0.45:
		return "feet are vertically split (%s vs %s)" % [left_toe, right_toe]
	return ""


func _bone_world_position(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index < 0:
		return Vector3(INF, INF, INF)
	return (skeleton.global_transform \
		* skeleton.get_bone_global_pose(bone_index)).origin


func _female_surfaces_use_textures(root: Node, corrected: Texture2D,
		chest: Texture2D) -> bool:
	if root == null or corrected == null or chest == null:
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
			var expected := chest if surface_index == 0 else corrected
			if material.albedo_texture != expected:
				return false
	return checked >= 2


func _fail(message: String) -> void:
	push_error("FEMALE_PLAYER_V2_VALIDATION_FAILED: %s" % message)
	get_tree().quit(1)
