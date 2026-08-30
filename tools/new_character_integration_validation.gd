extends Node

const SkinRegistry = preload("res://player_skin_registry.gd")
const CosmeticRegistry = preload("res://supabase/supabase_cosmetic_registry.gd")
const VisualScript = preload("res://models/player_v2/player_v2_visual.gd")
const PLAYER_SCENE = preload("res://player.tscn")

const NEW_MODELS: Array[Dictionary] = [
	{"id": "eye_wizard", "item_id": "character_eye_wizard", "scale": 0.450349},
	{"id": "mr_mushroom", "item_id": "character_mr_mushroom", "scale": 0.556026},
	{"id": "mr_poop", "item_id": "character_mr_poop", "scale": 0.760003},
	{"id": "mr_salt", "item_id": "character_mr_salt", "scale": 1.003901},
	{"id": "spooky_witch", "item_id": "character_spooky_witch", "scale": 0.615280},
]
const REQUIRED_BONES: Array[String] = [
	"mixamorig_Hips", "mixamorig_Head", "mixamorig_RightHand",
	"mixamorig_LeftFoot", "mixamorig_RightFoot",
]
const REQUIRED_SOCKETS: Array[String] = [
	"GunHoldPoint", "MeleeHoldPoint", "ItemHoldPoint",
	"LeftFootSocket", "RightFootSocket", "HeadwearSocket",
]
const TEST_HAT_ID := "hat_crown"

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var selected_models: Array[Dictionary] = NEW_MODELS.duplicate()
	var requested_model := OS.get_environment(
		"ONEGUN_NEW_CHARACTER_VALIDATION_MODEL").strip_edges().to_lower()
	if requested_model != "":
		selected_models.clear()
		for model in NEW_MODELS:
			if str(model["id"]) == requested_model:
				selected_models.append(model)
		_check(not selected_models.is_empty(),
			"requested validation model is registered: %s" % requested_model)
	var requested_animations: Array[String] = ["idle", "idle_pistol"]
	for animation_name in VisualScript.ANIMATION_SOURCES:
		requested_animations.append(str(animation_name))
	for model in selected_models:
		await _validate_visual(model, requested_animations)
	for model in selected_models:
		await _validate_gameplay_actor(str(model["id"]))
	if _failures == 0:
		print("NEW CHARACTER INTEGRATION VALIDATION PASSED models=%d animations=%d" % [
			selected_models.size(), requested_animations.size()])
		get_tree().quit(0)
	else:
		push_error("NEW CHARACTER INTEGRATION VALIDATION FAILED: %d issue(s)" % _failures)
		get_tree().quit(1)


func _validate_visual(model: Dictionary,
		requested_animations: Array[String]) -> void:
	var model_id := str(model["id"])
	var item_id := str(model["item_id"])
	_check(model_id not in SkinRegistry.PUBLIC_MODEL_IDS
			and model_id in SkinRegistry.DEVELOPER_GIFT_MODEL_IDS,
		"%s is excluded from the public selector and registered as a developer gift" % model_id)
	_check(CosmeticRegistry.local_character_model_id(item_id) == model_id
			and CosmeticRegistry.known_slot_for_id(item_id) == "character_model"
			and CosmeticRegistry.has_local_visual(item_id, "character_model"),
		"%s entitlement resolves only through its installed character item" % model_id)
	var local_catalog := CosmeticRegistry.local_catalog_item(item_id)
	_check(not local_catalog.is_empty()
			and not bool(local_catalog.get("purchasable", true))
			and not bool(local_catalog.get("shop_visible", true))
			and str(local_catalog.get("rotation_scope", "")) == "none",
		"%s local catalog fallback remains hidden and non-purchasable" % model_id)
	_check(SkinRegistry.uses_fixed_texture(model_id),
		"%s preserves its authored material" % model_id)
	_check(SkinRegistry.has_headwear_profile(model_id),
		"%s declares a headwear socket profile" % model_id)
	_check(SkinRegistry.load_portrait("blue", model_id) != null,
		"%s has a customization and roster portrait" % model_id)

	var packed := SkinRegistry.load_visual_scene(model_id)
	_check(packed != null, "%s visual wrapper loads" % model_id)
	if packed == null:
		return
	var visual := packed.instantiate() as Node3D
	visual.set("build_animation_library", false)
	add_child(visual)
	await get_tree().process_frame
	_check(is_equal_approx(visual.scale.x, float(model["scale"]))
			and is_equal_approx(visual.scale.y, float(model["scale"]))
			and is_equal_approx(visual.scale.z, float(model["scale"])),
		"%s wrapper keeps its normalized gameplay scale" % model_id)
	var authored_model := visual.get_node_or_null("Model") as Node3D
	_check(authored_model != null and is_equal_approx(
		wrapf(authored_model.rotation.y, -PI, PI), -PI * 0.5),
		"%s authored mesh faces gameplay forward" % model_id)

	var skeleton := visual.call("get_skeleton") as Skeleton3D
	_check(skeleton != null, "%s exposes its skinned skeleton" % model_id)
	for bone_name in REQUIRED_BONES:
		_check(skeleton != null and skeleton.find_bone(bone_name) >= 0,
			"%s required bone exists: %s" % [model_id, bone_name])
	for socket_name in REQUIRED_SOCKETS:
		var socket := visual.find_child(socket_name, true, false) as Node3D
		_check(socket != null and _finite_transform(socket.global_transform),
			"%s animated socket is valid: %s" % [model_id, socket_name])

	var character_mesh := _first_character_mesh(visual)
	_check(character_mesh != null, "%s skinned mesh is present" % model_id)
	if character_mesh != null:
		var before_material := character_mesh.get_active_material(0)
		visual.call("set_skin", "red")
		var after_material := character_mesh.get_active_material(0)
		_check(before_material == after_material,
			"%s cat-color changes cannot overwrite its authored look" % model_id)

	var animation_player := visual.call(
		"ensure_animations", requested_animations) as AnimationPlayer
	_check(animation_player != null,
		"%s runtime animation player is available" % model_id)
	if animation_player != null and skeleton != null:
		var hips_index := skeleton.find_bone("mixamorig_Hips")
		for animation_name in requested_animations:
			var installed := animation_player.has_animation(animation_name)
			_check(installed, "%s animation retargeted: %s" % [
				model_id, animation_name])
			if not installed:
				continue
			var animation := animation_player.get_animation(animation_name)
			_check(animation != null and animation.length > 0.0
					and animation.get_track_count() >= 33,
				"%s animation has a complete body track set: %s" % [
					model_id, animation_name])
			animation_player.play(animation_name)
			animation_player.advance(minf(0.25, animation.length * 0.5))
			_check(hips_index >= 0 and _finite_transform(
				skeleton.get_bone_global_pose(hips_index)),
				"%s animation pose remains finite: %s" % [
					model_id, animation_name])

	CosmeticRegistry.apply_to_character_visual(visual, {"hat": TEST_HAT_ID})
	await get_tree().process_frame
	await get_tree().process_frame
	var hat := visual.find_child("HatVisual", true, false)
	var headwear_socket := visual.call("get_headwear_socket") as Marker3D
	_check(hat != null and headwear_socket != null
			and headwear_socket.is_ancestor_of(hat)
			and str(hat.get_meta("supabase_hat_id", "")) == TEST_HAT_ID,
		"%s equipped hat is attached beneath its animated head socket" % model_id)
	visual.queue_free()
	await get_tree().process_frame


func _validate_gameplay_actor(model_id: String) -> void:
	var actor := PLAYER_SCENE.instantiate() as CharacterBody3D
	actor.set("is_online", true)
	actor.set("character_model_id", model_id)
	actor.set("character_skin_id", "blue")
	actor.set("cosmetic_loadout", {"hat": TEST_HAT_ID})
	add_child(actor)
	await get_tree().process_frame
	await get_tree().process_frame
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	var visual := actor.get_node_or_null("CharacterModel") as Node3D
	_check(str(actor.get("character_model_id")) == model_id
			and visual != null and str(visual.get("model_id")) == model_id,
		"gameplay actor spawns with %s" % model_id)
	var hat := visual.find_child("HatVisual", true, false) if visual != null else null
	_check(hat != null and str(hat.get_meta("supabase_hat_id", "")) == TEST_HAT_ID,
		"gameplay actor retains %s cosmetics" % model_id)
	actor.queue_free()
	await get_tree().process_frame


func _first_character_mesh(visual: Node3D) -> MeshInstance3D:
	for candidate in visual.call("get_character_mesh_instances"):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null:
			return mesh_instance
	return null


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


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)
