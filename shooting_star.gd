extends GPUParticles3D

## Fires the one-shot star streak at random intervals.

@export var min_interval: float = 6.0
@export var max_interval: float = 14.0

func _ready() -> void:
	one_shot = true
	emitting = false
	_schedule()

func _schedule() -> void:
	var t := get_tree().create_timer(randf_range(min_interval, max_interval))
	t.timeout.connect(_fire)

func _fire() -> void:
	if not is_inside_tree():
		return
	restart()
	emitting = true
	_schedule()
