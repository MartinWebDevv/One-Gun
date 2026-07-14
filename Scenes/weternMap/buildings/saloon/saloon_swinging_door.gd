extends Node3D

## Reusable western saloon door: swings open around its hinge edge when a
## player/bot walks into it, holds, then flaps back and forth with decaying
## momentum before settling closed - like a real saloon door.

@export var hinge_on_positive_side: bool = false  ## Flip if this instance swings from the wrong edge
@export var open_angle_degrees: float = 105.0
@export var open_time: float = 0.18
@export var hold_open_time: float = 1.2
@export var flap_count: int = 3  ## Back-and-forth passes while settling closed
@export var flap_decay: float = 0.42  ## Each flap swings this fraction of the previous one

@onready var _pivot: Node3D = $Pivot
@onready var _door_mesh: Node3D = $Pivot/DoorMesh
@onready var _area: Area3D = $Area3D
@onready var _collision_shape: CollisionShape3D = $Area3D/CollisionShape3D

var _closed_basis: Basis
var _angle := 0.0:
	set(value):
		_angle = value
		if _pivot:
			_pivot.basis = _closed_basis.rotated(Vector3.UP, value)
var _is_open := false
var _close_timer := 0.0
var _swing_tween: Tween

func _ready() -> void:
	var mesh_aabb := _get_local_aabb(_door_mesh)
	_align_pivot_to_hinge(mesh_aabb)
	_size_trigger_area(mesh_aabb)
	_closed_basis = _pivot.basis
	_area.body_entered.connect(_on_body_entered)

func _get_local_aabb(node: Node) -> AABB:
	var combined: AABB
	var first := true
	for mesh in _find_mesh_instances(node):
		var world_aabb: AABB = mesh.transform * mesh.get_aabb()
		if first:
			combined = world_aabb
			first = false
		else:
			combined = combined.merge(world_aabb)
	return combined

func _find_mesh_instances(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_mesh_instances(child))
	return result

func _align_pivot_to_hinge(mesh_aabb: AABB) -> void:
	var hinge_z: float = mesh_aabb.end.z if hinge_on_positive_side else mesh_aabb.position.z
	_door_mesh.position.z = -hinge_z

func _size_trigger_area(mesh_aabb: AABB) -> void:
	if _collision_shape.shape == null or not (_collision_shape.shape is BoxShape3D):
		_collision_shape.shape = BoxShape3D.new()
	var box: BoxShape3D = _collision_shape.shape
	box.size = Vector3(
		max(mesh_aabb.size.x * 4.0, 0.05),
		mesh_aabb.size.y,
		mesh_aabb.size.z + mesh_aabb.size.x * 2.0
	)
	_collision_shape.position = Vector3(0, mesh_aabb.position.y + mesh_aabb.size.y * 0.5, 0)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var local_pos := to_local(body.global_position)
	var swing_sign := 1.0 if local_pos.x >= 0.0 else -1.0
	_open_door(swing_sign)

func _open_door(swing_sign: float) -> void:
	_is_open = true
	_close_timer = hold_open_time
	if _swing_tween:
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.tween_property(self, "_angle", deg_to_rad(open_angle_degrees) * swing_sign, open_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if not _is_open:
		return
	_close_timer -= delta
	if _close_timer > 0.0:
		return
	# Don't slam the door on someone still standing in the doorway
	for body in _area.get_overlapping_bodies():
		if body.is_in_group("player"):
			_close_timer = hold_open_time * 0.5
			return
	_is_open = false
	_start_flapping_close()

func _start_flapping_close() -> void:
	if _swing_tween:
		_swing_tween.kill()
	_swing_tween = create_tween()
	var amplitude: float = -_angle * flap_decay
	var duration: float = open_time * 1.6
	for i in flap_count:
		_swing_tween.tween_property(self, "_angle", amplitude, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		amplitude = -amplitude * flap_decay
		duration *= 0.85
	_swing_tween.tween_property(self, "_angle", 0.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
