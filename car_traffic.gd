extends Node3D

## A car that drives a rectangular waypoint loop around the block. Wheels
## spin, the car eases around corners, waits at the traffic light when its
## crossing is red, and shoves players (melee-style knockback, never lethal)
## if they get clipped.

@export var waypoints: Array[Vector3] = []
@export var speed: float = 7.0
@export var knockback_distance: float = 5.0
@export var traffic_light_path: NodePath  ## optional traffic_light_cycle.gd node
@export var stop_zone_center := Vector3.ZERO  ## where to check the light
@export var stop_zone_radius: float = 6.0

var _wp := 0
var _wheels: Array = []
var _hit_cooldown := {}
var _light: Node = null

func _ready() -> void:
	# Support both the original short wheel names and the descriptive names used
	# by the replacement City GLBs. Restrict the match to Node3D descendants so
	# material/mesh resource names cannot be mistaken for transformable wheels.
	for child in find_children("*", "Node3D", true, false):
		var normalized_name := str(child.name).to_lower()
		if "wheel" in normalized_name and not _wheels.has(child):
			_wheels.append(child)
	if traffic_light_path != NodePath(""):
		_light = get_node_or_null(traffic_light_path)
	# waypoints/stop zone are authored in parent-local space so the route
	# stays on the roads even when the whole map root is scaled
	var parent3d := get_parent() as Node3D
	if parent3d:
		var wps: Array[Vector3] = []
		for w in waypoints:
			wps.append(parent3d.to_global(w))
		waypoints = wps
		stop_zone_center = parent3d.to_global(stop_zone_center)
		stop_zone_radius *= parent3d.global_transform.basis.get_scale().x
	# knockback trigger volume around the body
	var area := Area3D.new()
	area.name = "HitZone"
	area.collision_layer = 0
	area.collision_mask = 2
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.1, 1.6, 4.8)
	col.shape = shape
	col.position = Vector3(0, 0.9, 0)
	area.add_child(col)
	add_child(area)
	area.body_entered.connect(_on_body_hit)
	if waypoints.size() > 0:
		global_position = waypoints[0]

func _physics_process(delta: float) -> void:
	if waypoints.size() < 2:
		return
	var target: Vector3 = waypoints[_wp]
	var to_target := target - global_position
	to_target.y = 0
	if to_target.length() < 1.2:
		_wp = (_wp + 1) % waypoints.size()
		return
	# red light: stop while approaching the intersection zone
	if _light != null and global_position.distance_to(stop_zone_center) < stop_zone_radius:
		var heading_in: bool = (stop_zone_center - global_position).normalized().dot(to_target.normalized()) > 0.3
		if heading_in and _light.get("state") == "red":
			_spin_wheels(0.0, delta)
			return
	var dir := to_target.normalized()
	global_position += dir * speed * delta
	# smooth yaw toward travel direction
	var target_yaw := atan2(dir.x, dir.z) + PI
	rotation.y = lerp_angle(rotation.y, target_yaw, 6.0 * delta)
	_spin_wheels(speed, delta)

func _spin_wheels(v: float, delta: float) -> void:
	for w in _wheels:
		w.rotate_object_local(Vector3(1, 0, 0), v / 0.34 * delta)

func _on_body_hit(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var now := Time.get_ticks_msec()
	if _hit_cooldown.has(body) and now - _hit_cooldown[body] < 1500:
		return
	_hit_cooldown[body] = now
	if body.has_method("apply_knockback"):
		var shove := (body.global_position - global_position)
		shove.y = 0
		# push away from the car's path, biased along travel direction
		var travel := -global_transform.basis.z
		var dir := (shove.normalized() * 0.6 + travel * 0.4).normalized()
		body.apply_knockback(dir, knockback_distance)
