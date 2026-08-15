extends Node

## GPU-backed visual regression capture for the shared V2 player presentation.
## Run this outside --headless so root and SubViewport textures are rendered.

const MAIN_MENU_SCENE := preload("res://main_menu.tscn")
const GAME_SETUP_SCENE := preload("res://game_setup.tscn")
const PLAYER_SCENE := preload("res://player.tscn")
const GUN_SCENE := preload("res://gun.tscn")
const MELEE_SCENE := preload("res://melee_weapon.tscn")

var _content: Node = null
var _output_dir := ""


func _ready() -> void:
	_output_dir = OS.get_environment("ONE_GUN_V2_RENDER_OUTPUT")
	if _output_dir.is_empty():
		_output_dir = ProjectSettings.globalize_path("res://.player_v2_render_validation")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	_run.call_deferred()


func _run() -> void:
	if OS.get_environment("ONE_GUN_V2_GUN_HOLDER_ONLY") == "1":
		await _capture_gun_holder_visibility()
		await _replace_content(Node.new())
		await _wait_frames(3)
		print("PLAYER_V2_RENDER_VALIDATION_OK output=", _output_dir)
		get_tree().quit(0)
		return
	if OS.get_environment("ONE_GUN_V2_OT_REVEAL_ONLY") == "1":
		await _capture_overtime_reveal()
		await _replace_content(Node.new())
		await _wait_frames(3)
		print("PLAYER_V2_RENDER_VALIDATION_OK output=", _output_dir)
		get_tree().quit(0)
		return
	if OS.get_environment("ONE_GUN_V2_DECOY_REVEAL_ONLY") == "1":
		await _capture_decoy_destroyer_reveal()
		await _replace_content(Node.new())
		await _wait_frames(3)
		print("PLAYER_V2_RENDER_VALIDATION_OK output=", _output_dir)
		get_tree().quit(0)
		return
	if OS.get_environment("ONE_GUN_V2_SHOES_ONLY") == "1":
		await _capture_double_jump_shoes()
		await _replace_content(Node.new())
		await _wait_frames(3)
		print("PLAYER_V2_RENDER_VALIDATION_OK output=", _output_dir)
		get_tree().quit(0)
		return
	if OS.get_environment("ONE_GUN_V2_EQUIPMENT_ONLY") == "1":
		await _capture_held_weapon_poses()
		await _capture_throw_sequence()
		await _replace_content(Node.new())
		await _wait_frames(3)
		print("PLAYER_V2_RENDER_VALIDATION_OK output=", _output_dir)
		get_tree().quit(0)
		return
	await _capture_main_menu()
	await _capture_lobby_customization()
	await _capture_gameplay_poses()
	await _capture_held_weapon_poses()
	await _capture_throw_sequence()
	await _capture_source_poses()
	await _replace_content(Node.new())
	await _wait_frames(3)
	print("PLAYER_V2_RENDER_VALIDATION_OK output=", _output_dir)
	get_tree().quit(0)


func _capture_main_menu() -> void:
	var menu := MAIN_MENU_SCENE.instantiate()
	await _replace_content(menu)
	await _wait_frames(18)
	await _capture("main_menu.png")
	menu.call("_on_character_customization_pressed")
	await _wait_frames(10)
	await _capture("main_menu_customization.png")


func _capture_lobby_customization() -> void:
	# Exercise the denser P1/P2 customization state in the real lobby so the
	# player tabs and the shared preview are covered by the visual regression.
	GameConfig.split_screen_enabled = true
	var lobby := GAME_SETUP_SCENE.instantiate()
	await _replace_content(lobby)
	await _wait_frames(10)
	lobby.call("_on_character_customization_pressed")
	await _wait_frames(10)
	await _capture("lobby_customization.png")


func _capture_gameplay_poses() -> void:
	var world := Node3D.new()
	world.name = "GameplayPoseWorld"
	await _replace_content(world)
	_build_pose_environment(world)

	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.name = "GameplayPlayer"
	player.position = Vector3(0.0, 1.09, 0.0)
	world.add_child(player)
	# Disable after _ready: Godot registers an overridden _physics_process when
	# the scripted node enters the tree, which can undo a pre-tree disable. The
	# pose lab has a visual floor only, so allowing controller physics here would
	# replace every requested pose with Fall before the screenshot.
	player.set_physics_process(false)
	var camera := world.get_node("ValidationCamera") as Camera3D
	camera.current = true
	await _wait_frames(4)

	var animation_player := player.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer
	for pose in [
		["idle", 0.2, "gameplay_idle.png"],
		["standard_run", 0.2, "gameplay_run.png"],
		["jump", 0.2, "gameplay_jump.png"],
		["melee", 0.2, "gameplay_melee.png"],
	]:
		animation_player.play(str(pose[0]), 0.0)
		animation_player.advance(float(pose[1]))
		await _wait_frames(2)
		await _capture(str(pose[2]))


func _capture_overtime_reveal() -> void:
	var pose_setup := await _create_gameplay_pose_world()
	var world: Node3D = pose_setup[0]
	var player: CharacterBody3D = pose_setup[1]
	var animation_player: AnimationPlayer = pose_setup[2]
	animation_player.play("idle", 0.0)
	animation_player.advance(0.2)

	# Attach a real prop to prove the reveal is scoped to the cat mesh rather than
	# recursively painting equipment added below the V2 socket markers.
	var gun = GUN_SCENE.instantiate()
	world.add_child(gun)
	gun.call("_local_pickup", player)
	await _wait_frames(6)
	player.call("show_overtime_pulse", 8.0)
	await _wait_frames(4)
	var visual = player.get_node_or_null("CharacterModel")
	var character_meshes: Array = visual.get_character_mesh_instances() \
		if visual != null and visual.has_method("get_character_mesh_instances") \
		else []
	if character_meshes.is_empty():
		push_error("PLAYER_V2_OT_REVEAL_CHARACTER_MESHES_MISSING")
		get_tree().quit(1)
		return
	for mesh in character_meshes:
		if mesh.material_overlay == null:
			push_error("PLAYER_V2_OT_REVEAL_NOT_APPLIED_TO_CHARACTER")
			get_tree().quit(1)
			return
	for mesh in _find_mesh_instances(gun):
		if mesh.material_overlay != null:
			push_error("PLAYER_V2_OT_REVEAL_LEAKED_TO_HELD_GUN")
			get_tree().quit(1)
			return
	await _capture("overtime_reveal_visible.png")

	var occluder := MeshInstance3D.new()
	var occluder_mesh := BoxMesh.new()
	occluder_mesh.size = Vector3(3.0, 3.0, 0.18)
	occluder.mesh = occluder_mesh
	occluder.position = Vector3(0.0, 1.4, -2.0)
	var occluder_material := StandardMaterial3D.new()
	occluder_material.albedo_color = Color(0.04, 0.07, 0.12)
	occluder.material_override = occluder_material
	world.add_child(occluder)
	await _wait_frames(3)
	await _capture("overtime_reveal_through_cover.png")


func _capture_decoy_destroyer_reveal() -> void:
	var pose_setup := await _create_gameplay_pose_world()
	var world: Node3D = pose_setup[0]
	var player: CharacterBody3D = pose_setup[1]
	var animation_player: AnimationPlayer = pose_setup[2]
	animation_player.play("idle_pistol", 0.0)
	animation_player.advance(0.2)

	# Reproduce the local-play failure exactly: the shooter is holding the gun,
	# destroys a decoy, receives the temporary reveal, then must return to their
	# normal textured model without a persistent expanded shell.
	var gun = GUN_SCENE.instantiate()
	world.add_child(gun)
	gun.call("_local_pickup", player)
	await _wait_frames(6)
	player.call("show_decoy_destroyer_outline", 0.35, null)
	await _wait_frames(3)
	var visual = player.get_node_or_null("CharacterModel")
	var character_meshes: Array = visual.get_character_mesh_instances() \
		if visual != null and visual.has_method("get_character_mesh_instances") \
		else []
	if character_meshes.is_empty():
		push_error("PLAYER_V2_DECOY_REVEAL_CHARACTER_MESHES_MISSING")
		get_tree().quit(1)
		return
	for mesh in character_meshes:
		var overlay := mesh.material_overlay as ShaderMaterial
		if overlay == null or overlay.shader == null:
			push_error("PLAYER_V2_DECOY_REVEAL_RIM_MISSING")
			get_tree().quit(1)
			return
		if "grow" in overlay.shader.code:
			push_error("PLAYER_V2_DECOY_REVEAL_USES_EXPANDED_SHELL")
			get_tree().quit(1)
			return
	for mesh in _find_mesh_instances(gun):
		if mesh.material_overlay != null:
			push_error("PLAYER_V2_DECOY_REVEAL_LEAKED_TO_GUN")
			get_tree().quit(1)
			return
	await _capture("decoy_destroyer_reveal.png")
	await get_tree().create_timer(0.45).timeout
	await _wait_frames(3)
	for mesh in character_meshes:
		if mesh.material_overlay != null:
			push_error("PLAYER_V2_DECOY_REVEAL_PERSISTED_AFTER_TIMEOUT")
			get_tree().quit(1)
			return
	await _capture("decoy_destroyer_reveal_cleared.png")


func _capture_gun_holder_visibility() -> void:
	var pose_setup := await _create_gameplay_pose_world()
	var world: Node3D = pose_setup[0]
	var player: CharacterBody3D = pose_setup[1]
	var animation_player: AnimationPlayer = pose_setup[2]
	animation_player.play("idle_pistol", 0.0)
	animation_player.advance(0.2)

	var gun = GUN_SCENE.instantiate()
	world.add_child(gun)
	gun.call("_local_pickup", player)
	await _wait_frames(6)
	# Exercise the remote-online presentation without starting a network peer.
	# Setting these flags after _ready avoids building unrelated synchronizers;
	# the focused regression calls the same material/tag methods directly.
	player.is_online = true
	player.set("_is_local_online", false)
	player.call("_update_gun_holder_outline")
	player.call("_build_online_name_tag")
	var marker := player.get("_gun_holder_arrow") as Label3D
	marker.visible = true
	marker.scale = Vector3.ONE
	var name_tag := player.get("_online_name_tag") as Label3D
	name_tag.visible = false

	var visual = player.get_node_or_null("CharacterModel")
	var character_meshes: Array = visual.get_character_mesh_instances() \
		if visual != null and visual.has_method("get_character_mesh_instances") \
		else []
	if character_meshes.is_empty():
		push_error("PLAYER_V2_GUN_HOLDER_CHARACTER_MESHES_MISSING")
		get_tree().quit(1)
		return
	for mesh in character_meshes:
		var overlay := mesh.material_overlay as ShaderMaterial
		if overlay == null or overlay.shader == null:
			push_error("PLAYER_V2_GUN_HOLDER_RIM_MISSING")
			get_tree().quit(1)
			return
		if "depth_test_disabled" in overlay.shader.code:
			push_error("PLAYER_V2_GUN_HOLDER_RIM_WALLHACK")
			get_tree().quit(1)
			return
	for mesh in _find_mesh_instances(gun):
		if mesh.material_overlay != null:
			push_error("PLAYER_V2_GUN_HOLDER_RIM_LEAKED_TO_GUN")
			get_tree().quit(1)
			return
	if marker.font_size != 52 or marker.outline_size != 18:
		push_error("PLAYER_V2_GUN_HOLDER_MARKER_SIZE_WRONG")
		get_tree().quit(1)
		return
	var camera := world.get_node("ValidationCamera") as Camera3D
	camera.fov = 48.0
	camera.look_at_from_position(
		Vector3(4.5, 2.8, -6.6), Vector3(0.0, 1.7, 0.0), Vector3.UP)
	await _wait_frames(4)
	await _capture("gun_holder_indicator.png")


func _capture_held_weapon_poses() -> void:
	var pose_setup := await _create_gameplay_pose_world()
	var world: Node3D = pose_setup[0]
	var player: CharacterBody3D = pose_setup[1]
	var animation_player: AnimationPlayer = pose_setup[2]
	animation_player.play("idle_pistol", 0.0)
	animation_player.advance(0.2)

	var gun = GUN_SCENE.instantiate()
	world.add_child(gun)
	gun.call("_local_pickup", player)
	await _wait_frames(12)
	var muzzle := gun.get_node_or_null("WaterGun/MuzzlePoint") as Node3D
	var gun_forward: Vector3 = (muzzle.global_position - gun.global_position).normalized() \
		if muzzle != null else Vector3.ZERO
	print("PLAYER_V2_GUN_IDLE_ALIGNMENT player_forward=", -player.global_basis.z,
		" muzzle_from_grip=", gun_forward)
	await _capture("held_gun.png")
	_set_pose_camera(world, true)
	await _capture("held_gun_rear.png")
	_set_pose_camera(world, false)
	animation_player.play("pistol_run", 0.0)
	animation_player.seek(0.2, true)
	animation_player.advance(0.0)
	await _wait_frames(12)
	gun_forward = (muzzle.global_position - gun.global_position).normalized() \
		if muzzle != null else Vector3.ZERO
	print("PLAYER_V2_GUN_MOVING_ALIGNMENT player_forward=", -player.global_basis.z,
		" muzzle_from_grip=", gun_forward)
	await _capture("held_gun_moving.png")
	_set_pose_camera(world, true)
	await _capture("held_gun_moving_rear.png")
	_set_pose_camera(world, false)
	player.call("set_character_skin", "salmon")
	var accessibility_values: Dictionary = PlayerPrefs.settings.duplicate(true)
	var flash_test_values := accessibility_values.duplicate(true)
	flash_test_values["reduce_flashing"] = false
	AccessibilityManager.preview_policy(flash_test_values)
	player.call("flash_hit")
	await _wait_frames(2)
	player.call("flash_hit")
	await _wait_frames(20)
	AccessibilityManager.preview_policy(accessibility_values)
	player.call("play_victory_dance")
	await _wait_frames(8)
	await _capture("victory_dance_no_gun_skin_preserved.png")
	player.holding_gun = false
	gun.queue_free()
	await _wait_frames(2)
	animation_player.play("idle", 0.0)
	animation_player.advance(0.2)

	for weapon_name in ["Sword", "Baseball Bat", "Stick", "Crowbar", "Frying Pan"]:
		var weapon = MELEE_SCENE.instantiate()
		world.add_child(weapon)
		weapon.apply_weapon_data(
			MeleeWeaponRegistry.get_weapon_data_by_name(weapon_name), "normal")
		weapon.call("_local_pickup", player)
		await _wait_frames(3)
		await _capture("held_%s.png" % weapon_name.to_lower().replace(" ", "_"))
		_set_pose_camera(world, true)
		await _capture("held_%s_rear.png" % weapon_name.to_lower().replace(" ", "_"))
		_set_pose_camera(world, false)
		var rest_rotation: Vector3 = weapon.rotation
		weapon.swing()
		var swing_frames := 0
		while not weapon.get_node("HitBox").monitoring \
				and weapon.is_swinging and swing_frames < 120:
			await get_tree().physics_frame
			swing_frames += 1
		if not weapon.get_node("HitBox").monitoring:
			push_error("PLAYER_V2_MELEE_ACTIVE_WINDOW_MISSING weapon=" + weapon_name)
			get_tree().quit(1)
			return
		if (weapon.rotation - rest_rotation).length() > 0.001:
			push_error("PLAYER_V2_MELEE_ROOT_SWING_PRESENT weapon=" + weapon_name)
			get_tree().quit(1)
			return
		await _capture("swing_%s.png" % weapon_name.to_lower().replace(" ", "_"))
		while weapon.is_swinging:
			await get_tree().physics_frame
		player.held_melee_weapon = null
		weapon.queue_free()
		await _wait_frames(2)


func _capture_double_jump_shoes() -> void:
	var pose_setup := await _create_gameplay_pose_world()
	var world: Node3D = pose_setup[0]
	var player: CharacterBody3D = pose_setup[1]
	var animation_player: AnimationPlayer = pose_setup[2]
	player.activate_double_jump_shoes()

	animation_player.play("idle", 0.0)
	animation_player.advance(0.0)
	await _wait_frames(12)
	var camera := world.get_node("ValidationCamera") as Camera3D
	camera.fov = 34.0
	camera.look_at_from_position(Vector3(2.45, 0.9, -3.1),
		Vector3(0.0, 0.28, 0.0), Vector3.UP)
	await _wait_frames(3)
	await _capture("double_jump_shoes_front.png")
	camera.look_at_from_position(Vector3(-2.45, 0.75, 2.85),
		Vector3(0.0, 0.24, 0.0), Vector3.UP)
	await _wait_frames(3)
	await _capture("double_jump_shoes_rear.png")
	camera.look_at_from_position(Vector3(3.0, 0.58, 0.0),
		Vector3(0.0, 0.18, 0.0), Vector3.UP)
	await _wait_frames(3)
	await _capture("double_jump_shoes_side.png")

func _capture_throw_sequence() -> void:
	var pose_setup := await _create_gameplay_pose_world()
	var player: CharacterBody3D = pose_setup[1]
	var animation_player: AnimationPlayer = pose_setup[2]
	print("PLAYER_V2_THROW_LENGTH runtime=",
		animation_player.get_animation("throw_object").length)
	for sample in [[0.12, "throw_012.png"], [0.30, "throw_030.png"],
			[0.48, "throw_048.png"], [0.66, "throw_066.png"], [0.82, "throw_082.png"]]:
		animation_player.play("throw_object", 0.0)
		animation_player.seek(float(sample[0]), true)
		animation_player.advance(0.0)
		await _wait_frames(2)
		await _capture(str(sample[1]))
func _create_gameplay_pose_world() -> Array:
	var world := Node3D.new()
	world.name = "GameplayEquipmentWorld"
	await _replace_content(world)
	_build_pose_environment(world)
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.name = "EquipmentPlayer"
	player.position = Vector3(0.0, 1.09, 0.0)
	world.add_child(player)
	player.set_physics_process(false)
	# Match the real controller's first gameplay frame. The imported cat faces
	# +Z, so the controller applies MODEL_FACING_OFFSET before presenting it.
	player.call("_update_facing")
	(world.get_node("ValidationCamera") as Camera3D).current = true
	await _wait_frames(4)
	var animation_player := player.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer
	return [world, player, animation_player]


func _capture_source_poses() -> void:
	for pose in [
		["res://models/player_v2/animations/Standard Run.fbx", 0.2,
			"source_standard_run.png"],
		["res://models/player_v2/animations/Jumping.fbx", 0.2,
			"source_jump.png"],
		["res://models/player_v2/animations/melee.fbx", 0.2,
			"source_melee.png"],
	]:
		var world := Node3D.new()
		world.name = "SourcePoseWorld"
		await _replace_content(world)
		_build_pose_environment(world)
		var source_scene := load(str(pose[0])) as PackedScene
		var source := source_scene.instantiate() as Node3D
		# FBX animation scenes import at centimeter scale. Match the combined
		# 100x retarget, master Armature, and shared-visual scale used in gameplay.
		source.scale = Vector3.ONE * 55.4667
		world.add_child(source)
		var animation_player := source.find_child(
			"AnimationPlayer", true, false) as AnimationPlayer
		animation_player.play(_first_animation_name(animation_player), 0.0)
		animation_player.advance(float(pose[1]))
		(world.get_node("ValidationCamera") as Camera3D).current = true
		await _wait_frames(2)
		await _capture(str(pose[2]))


func _build_pose_environment(world: Node3D) -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.025, 0.035, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.68, 0.74, 0.92)
	env.ambient_light_energy = 1.0
	environment.environment = env
	world.add_child(environment)

	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(8.0, 0.08, 8.0)
	floor.mesh = floor_mesh
	floor.position.y = -0.04
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.10, 0.15, 0.25)
	floor.material_override = floor_material
	world.add_child(floor)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, 28.0, 0.0)
	key.light_color = Color(1.0, 0.86, 0.70)
	key.light_energy = 2.2
	key.shadow_enabled = true
	world.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.0, 2.0, -2.0)
	fill.light_color = Color(0.35, 0.65, 1.0)
	fill.light_energy = 3.0
	fill.omni_range = 7.0
	world.add_child(fill)

	var camera := Camera3D.new()
	camera.name = "ValidationCamera"
	camera.fov = 40.0
	camera.look_at_from_position(
		Vector3(3.2, 2.15, -4.5), Vector3(0.0, 0.95, 0.0), Vector3.UP)
	world.add_child(camera)


func _set_pose_camera(world: Node3D, rear_view: bool) -> void:
	var camera := world.get_node("ValidationCamera") as Camera3D
	var camera_position := Vector3(-3.2, 2.15, 4.5) \
		if rear_view else Vector3(3.2, 2.15, -4.5)
	camera.look_at_from_position(camera_position, Vector3(0.0, 0.95, 0.0), Vector3.UP)


func _replace_content(next: Node) -> void:
	if _content != null and is_instance_valid(_content):
		_content.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	_content = next
	add_child(_content)


func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _output_dir.path_join(file_name)
	var error := image.save_png(path)
	if error != OK:
		push_error("PlayerV2RenderValidation: could not save %s (%d)" % [path, error])
		get_tree().quit(1)
		return
	print("PLAYER_V2_RENDER_CAPTURE ", path)


func _first_animation_name(player: AnimationPlayer) -> String:
	for animation_name in player.get_animation_list():
		if animation_name != "RESET":
			return animation_name
	return ""


func _find_mesh_instances(node: Node) -> Array:
	var result: Array = []
	if node == null:
		return result
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result
