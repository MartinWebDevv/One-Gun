extends Node

const SkinRegistry = preload("res://player_skin_registry.gd")
const CosmeticRegistry = preload("res://supabase/supabase_cosmetic_registry.gd")
const VisualScript = preload("res://models/player_v2/player_v2_visual.gd")
const VISUAL_PATH := \
	"res://models/player_v2/characterSkins/goldfish_bag_man_visual.tscn"
const ITEM_ID := "character_goldfish_bag_man"
const TEST_HAT_ID := "hat_crown"

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)


func _run() -> void:
	_check(SkinRegistry.GOLDFISH_BAG_MAN_MODEL_ID in SkinRegistry.MODEL_IDS,
		"Gold Fish is a supported model")
	_check(SkinRegistry.GOLDFISH_BAG_MAN_MODEL_ID \
			not in SkinRegistry.PUBLIC_MODEL_IDS,
		"Gold Fish is absent from the public M/F model selector")
	_check(CosmeticRegistry.known_slot_for_id(ITEM_ID) == "character_model"
			and CosmeticRegistry.has_local_visual(ITEM_ID, "character_model"),
		"gift item resolves only to the installed character-model slot")

	var packed := load(VISUAL_PATH) as PackedScene
	_check(packed != null, "Gold Fish visual wrapper loads")
	if packed == null:
		_finish()
		return
	var visual := packed.instantiate() as Node3D
	add_child(visual)
	await get_tree().process_frame
	var authored_model := visual.get_node_or_null("Model") as Node3D
	_check(authored_model != null and is_equal_approx(
			wrapf(authored_model.rotation.y, -PI, PI), -PI * 0.5),
		"authored Gold Fish mesh is rotated 180 degrees to face gameplay forward")
	var skeleton := visual.call("get_skeleton") as Skeleton3D
	_check(skeleton != null and skeleton.get_bone_count() == 65,
		"authored 65-bone Mixamo skeleton is preserved")
	for required_bone in [
		"mixamorig_Hips", "mixamorig_Head", "mixamorig_RightHand",
		"mixamorig_LeftFoot", "mixamorig_RightFoot",
	]:
		_check(skeleton != null and skeleton.find_bone(required_bone) >= 0,
			"required gameplay bone exists: %s" % required_bone)

	var requested: Array[String] = ["idle", "idle_pistol"]
	for animation_name in VisualScript.ANIMATION_SOURCES:
		requested.append(str(animation_name))
	var animation_player := visual.call(
		"ensure_animations", requested) as AnimationPlayer
	_check(animation_player != null, "runtime animation player is available")
	if animation_player != null:
		for animation_name in requested:
			var installed := animation_player.has_animation(animation_name)
			_check(installed, "animation retargeted: %s" % animation_name)
			if not installed:
				continue
			var animation := animation_player.get_animation(animation_name)
			_check(animation != null and animation.length > 0.0 \
					and animation.get_track_count() >= 33,
				"animation has a complete body track set: %s" % animation_name)
			animation_player.play(animation_name)
			animation_player.advance(minf(0.25, animation.length * 0.5))
			var hips := skeleton.get_bone_global_pose(
				skeleton.find_bone("mixamorig_Hips"))
			_check(_finite_transform(hips),
				"animation pose remains finite: %s" % animation_name)

	var character_mesh: MeshInstance3D = null
	for candidate in visual.find_children("*", "MeshInstance3D", true, false):
		character_mesh = candidate as MeshInstance3D
		if character_mesh != null and character_mesh.mesh != null:
			break
	_check(character_mesh != null, "Gold Fish skinned mesh is present")
	if character_mesh != null:
		var before := character_mesh.get_active_material(0) as StandardMaterial3D
		var before_texture := before.albedo_texture if before != null else null
		visual.call("set_skin", "red")
		var after := character_mesh.get_active_material(0) as StandardMaterial3D
		var after_texture := after.albedo_texture if after != null else null
		_check(before_texture != null and after_texture == before_texture,
			"cat color changes cannot overwrite the authored Gold Fish texture")

	for socket_name in [
		"GunHoldPoint", "MeleeHoldPoint", "ItemHoldPoint",
		"LeftFootSocket", "RightFootSocket", "HeadwearSocket",
	]:
		_check(visual.find_child(socket_name, true, false) != null,
			"runtime socket exists: %s" % socket_name)
	CosmeticRegistry.apply_to_character_visual(visual, {
		"character_model": ITEM_ID,
		"hat": TEST_HAT_ID,
	})
	await get_tree().process_frame
	var hat := visual.find_child("HatVisual", true, false)
	_check(hat != null and str(hat.get_meta("supabase_hat_id", "")) == TEST_HAT_ID,
		"equipped hat attaches to the animated Gold Fish head socket")
	var stored_loadout = visual.get_meta("supabase_cosmetic_loadout", {})
	_check(stored_loadout is Dictionary \
			and str(stored_loadout.get("character_model", "")) == ITEM_ID,
		"presentation character retains the complete sanitized cosmetic loadout")

	visual.queue_free()
	await get_tree().process_frame
	_finish()


func _finite_transform(value: Transform3D) -> bool:
	for component in [
		value.origin.x, value.origin.y, value.origin.z,
		value.basis.x.x, value.basis.x.y, value.basis.x.z,
		value.basis.y.x, value.basis.y.y, value.basis.y.z,
		value.basis.z.x, value.basis.z.y, value.basis.z.z,
	]:
		if not is_finite(float(component)):
			return false
	return true


func _finish() -> void:
	if _failures == 0:
		print("GOLD FISH BAG MAN VALIDATION PASSED")
		get_tree().quit(0)
	else:
		push_error("GOLD FISH BAG MAN VALIDATION FAILED: %d issue(s)" % _failures)
		get_tree().quit(1)
