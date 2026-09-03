extends Node

# GPU-backed regression for the exact Neon Circuit projectile path reported in
# playtesting. Run once normally and once with ONEGUN_PROJECTILE_SPLIT=1.

const MAP_PATH := "res://maps/test/SpaceStationPrototype.tscn"
const GUN_SCENE := preload("res://gun.tscn")
const BULLET_SCRIPT := preload("res://bullet.gd")
const CENTER_TOLERANCE_PIXELS := 0.5

var _failures: Array[String] = []
var _split_enabled := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_split: bool = bool(GameConfig.split_screen_enabled)
	var original_bots: Array = GameConfig.bot_configs.duplicate(true)
	_split_enabled = OS.get_environment("ONEGUN_PROJECTILE_SPLIT") == "1"
	GameConfig.split_screen_enabled = _split_enabled
	GameConfig.bot_configs = []

	var arena := (load(MAP_PATH) as PackedScene).instantiate()
	add_child(arena)
	for _frame in 6:
		await get_tree().process_frame

	var players: Array[Node] = [arena.get_node_or_null("player1")]
	if _split_enabled:
		players.append(arena.get_node_or_null("player2"))
	for index in players.size():
		var player := players[index]
		var label := "P%d" % (index + 1)
		_check(player != null, "%s is missing from Neon Circuit" % label)
		if player != null:
			await _validate_player(arena, player, label)

	arena.queue_free()
	GameConfig.split_screen_enabled = original_split
	GameConfig.bot_configs = original_bots
	await get_tree().process_frame

	var mode := "SPLITSCREEN" if _split_enabled else "SOLO"
	if _failures.is_empty():
		print("PROJECTILE CROSSHAIR RENDER VALIDATION (%s): PASS" % mode)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("PROJECTILE CROSSHAIR RENDER VALIDATION: " + failure)
		get_tree().quit(1)


func _validate_player(arena: Node, player: Node, label: String) -> void:
	# Keep the camera fixed so this test measures projectile alignment, not a
	# deliberate player/camera movement that occurs after the shot.
	player.set_physics_process(false)
	player.set("_intro_active", false)
	var intro_camera = player.get("_intro_camera")
	if is_instance_valid(intro_camera):
		intro_camera.queue_free()
	player.set("_intro_camera", null)

	var gun := GUN_SCENE.instantiate()
	arena.add_child(gun)
	await get_tree().process_frame
	_check(gun._local_pickup(player), "%s could not equip the production gun" % label)
	if not gun.is_held:
		gun.queue_free()
		return
	player.set("active_slot", "weapon")
	if player.has_method("_update_active_slot_and_visuals"):
		player._update_active_slot_and_visuals()
	await get_tree().process_frame

	var render_camera := player.get_gun_fire_camera() as Camera3D
	_check(render_camera != null, "%s has no rendered firing camera" % label)
	if render_camera == null:
		gun.free()
		return
	_check(render_camera.get_viewport() is SubViewport,
		"%s firing camera is not the production SubViewport camera" % label)
	var viewport_center := render_camera.get_viewport().get_visible_rect().size * 0.5
	_validate_hud_center(arena, label)

	var baseline_ray: Dictionary = gun._calculate_fire_ray()
	_assert_ray_centered(render_camera, viewport_center, baseline_ray, label)

	# The animated, shoulder-offset muzzle is presentation only. Moving it by a
	# deliberately huge amount must not change either component of a human shot.
	var muzzle := gun.get_node_or_null("WaterGun/MuzzlePoint") as Node3D
	_check(muzzle != null, "%s production gun has no visual muzzle" % label)
	if muzzle != null:
		var original_muzzle_transform := muzzle.transform
		muzzle.position.x += 2.0
		var shifted_muzzle_ray: Dictionary = gun._calculate_fire_ray()
		_check((shifted_muzzle_ray["origin"] as Vector3).is_equal_approx(
				baseline_ray["origin"] as Vector3),
			"%s projectile origin still inherits lateral muzzle animation" % label)
		_check((shifted_muzzle_ray["direction"] as Vector3).is_equal_approx(
				baseline_ray["direction"] as Vector3),
			"%s projectile direction changed with the visual muzzle" % label)
		muzzle.transform = original_muzzle_transform

	var existing_bullets: Dictionary = {}
	for child in get_children():
		if child.get_script() == BULLET_SCRIPT:
			existing_bullets[child.get_instance_id()] = true
	gun.can_fire = true
	gun.fire()
	var bullet: RigidBody3D = null
	for child in get_children():
		if child.get_script() == BULLET_SCRIPT \
				and not existing_bullets.has(child.get_instance_id()):
			bullet = child as RigidBody3D
			break
	_check(bullet != null, "%s firing did not create a projectile" % label)
	if bullet != null:
		# Keep the projectile alive through the complete visual sample even when
		# the map has nearby scenery along the test camera's authored heading.
		bullet.collision_mask = 0
		bullet.contact_monitor = false
		_assert_projected_center(render_camera, viewport_center,
			bullet.global_position, "%s first visible position" % label)
		for sample in 4:
			await get_tree().physics_frame
			await get_tree().process_frame
			if not is_instance_valid(bullet):
				_failures.append("%s projectile disappeared at trajectory sample %d" \
					% [label, sample + 1])
				break
			render_camera = player.get_gun_fire_camera() as Camera3D
			_assert_projected_center(render_camera, viewport_center,
				bullet.global_position,
				"%s trajectory sample %d" % [label, sample + 1])
		if is_instance_valid(bullet):
			await _capture_frame(label)
			bullet.free()

	player.set("holding_gun", false)
	player.set("active_slot", "none")
	gun.free()


func _assert_ray_centered(camera: Camera3D, center: Vector2,
		fire_ray: Dictionary, label: String) -> void:
	for distance: float in [0.0, 1.0, 10.0, 50.0]:
		var world_point: Vector3 = fire_ray["origin"] + fire_ray["direction"] * distance
		_assert_projected_center(camera, center, world_point,
			"%s ray at %.1fm" % [label, distance])


func _assert_projected_center(camera: Camera3D, center: Vector2,
		world_point: Vector3, context: String) -> void:
	var projected := camera.unproject_position(world_point)
	_check(projected.distance_to(center) <= CENTER_TOLERANCE_PIXELS,
		"%s is %.3fpx off the rendered crosshair center" \
		% [context, projected.distance_to(center)])


func _validate_hud_center(arena: Node, label: String) -> void:
	var ui_name := "PlayerUI2" if label == "P2" else "PlayerUI1"
	var crosshair := arena.get_node_or_null("CanvasLayer/%s/Crosshair" % ui_name) as Control
	_check(crosshair != null, "%s procedural crosshair is missing" % label)
	if crosshair == null:
		return
	var root_size := get_viewport().get_visible_rect().size
	var expected_x := root_size.x * 0.5
	if _split_enabled:
		expected_x = root_size.x * (0.75 if label == "P2" else 0.25)
	var visible_center := crosshair.global_position + crosshair.size * 0.5
	_check(visible_center.distance_to(Vector2(expected_x, root_size.y * 0.5)) \
			<= CENTER_TOLERANCE_PIXELS,
		"%s HUD crosshair is not centered over its rendered viewport" % label)


func _capture_frame(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	var suffix := "split" if _split_enabled else "solo"
	var path := ProjectSettings.globalize_path(
		"res://.godot/projectile_crosshair_%s_%s.png" % [suffix, label.to_lower()])
	var image := get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty() and image.save_png(path) == OK,
		"%s rendered trajectory capture failed" % label)
	print("PROJECTILE CROSSHAIR CAPTURE: %s" % path)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
