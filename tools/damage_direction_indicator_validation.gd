extends Node

const IndicatorScript = preload("res://damage_direction_indicator.gd")

var _failures: Array[String] = []


class FakePlayer extends Node3D:
	var actor_id := 1
	var is_eliminated := false
	var view_camera: Camera3D

	func _init(requested_actor_id: int) -> void:
		actor_id = requested_actor_id
		view_camera = Camera3D.new()
		add_child(view_camera)

	func get_camera() -> Camera3D:
		return view_camera


func _ready() -> void:
	var world := Node3D.new()
	get_tree().root.add_child.call_deferred(world)
	await get_tree().process_frame
	var player := FakePlayer.new(7)
	world.add_child(player)
	var indicator = IndicatorScript.new()
	indicator.size = Vector2(1600.0, 900.0)
	get_tree().root.add_child(indicator)
	indicator.set_player(player)

	_check_angle(float(indicator._bearing_for_direction(
		player.view_camera, Vector3.FORWARD)), 0.0, "front bearing")
	_check_angle(float(indicator._bearing_for_direction(
		player.view_camera, Vector3.RIGHT)), PI * 0.5, "right bearing")
	_check_angle(absf(float(indicator._bearing_for_direction(
		player.view_camera, Vector3.BACK))), PI, "rear bearing")
	_check_angle(float(indicator._bearing_for_direction(
		player.view_camera, Vector3.LEFT)), -PI * 0.5, "left bearing")

	indicator._on_actor_damage_direction(99, Vector3.FORWARD, "gun")
	_check(_entry_count(indicator) == 0, "indicator accepted another victim's hit")
	indicator._on_actor_damage_direction(7, Vector3.FORWARD, "melee")
	_check(_entry_count(indicator) == 0, "indicator accepted a non-gun hit")
	indicator._on_actor_damage_direction(7, Vector3.FORWARD, "gun")
	_check(indicator.visible and _entry_count(indicator) == 1,
		"valid gun hit did not activate one indicator")
	indicator._on_actor_damage_direction(
		7, Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(10.0)), "gun")
	_check(_entry_count(indicator) == 1, "nearby repeated hits did not merge")

	for direction in [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3(1, 0, -1)]:
		indicator._on_actor_damage_direction(7, direction, "gun")
	_check(_entry_count(indicator) <= IndicatorScript.MAX_INDICATORS,
		"simultaneous source cap was exceeded")

	player.is_eliminated = true
	var followed_player := FakePlayer.new(8)
	world.add_child(followed_player)
	indicator.set_player(followed_player)
	_check(_entry_count(indicator) > 0,
		"lethal hit vanished during spectator rebinding")
	indicator._process(IndicatorScript.DISPLAY_TIME)
	_check(not indicator.visible and _entry_count(indicator) == 0,
		"expired indicators remained active")

	if _failures.is_empty():
		print("DAMAGE DIRECTION INDICATOR VALIDATION: PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)


func _entry_count(indicator) -> int:
	return (indicator.get("_indicators") as Array).size()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _check_angle(actual: float, expected: float, label: String) -> void:
	_check(is_equal_approx(actual, expected), "%s was %.3f, expected %.3f" % [
		label, actual, expected])
