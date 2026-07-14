extends Node3D

## Spins the windmill's "Blades" child at a lazy, slightly varying speed.

@export var base_speed: float = 0.9  # radians/sec

var _blades: Node3D
var _phase := 0.0

func _ready() -> void:
	_blades = find_child("Blades", true, false)

func _process(delta: float) -> void:
	if _blades == null:
		return
	_phase += delta * 0.25
	var speed := base_speed * (0.8 + 0.4 * sin(_phase))
	_blades.rotate_object_local(Vector3(0, 0, 1), speed * delta)
