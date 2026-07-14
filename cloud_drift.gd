extends Node3D

## Drifts child cloud meshes slowly across the sky, wrapping around the map.

@export var wind: Vector3 = Vector3(1.2, 0, 0.25)
@export var wrap_extent: float = 90.0

var _speeds := {}

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	for c in get_children():
		_speeds[c] = rng.randf_range(0.5, 1.4)

func _process(delta: float) -> void:
	for c in get_children():
		if not (c in _speeds):
			_speeds[c] = 1.0
		c.position += wind * _speeds[c] * delta
		if c.position.x > wrap_extent:
			c.position.x = -wrap_extent
		if absf(c.position.z) > wrap_extent:
			c.position.z = -signf(c.position.z) * wrap_extent * 0.6
