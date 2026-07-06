extends Area3D

@export var slow_duration := 4.0
@export var slow_multiplier := 0.5

var owner_player = null

func _ready():
	add_to_group("hazard")
	body_entered.connect(_on_body_entered)
	collision_layer = 0
	set_collision_mask_value(2, true)

func _on_body_entered(body):
	if not body.is_in_group("player"):
		return
	if not GameConfig.can_affect(owner_player, body):
		return
	if body.has_method("apply_slow"):
		body.apply_slow(slow_duration, slow_multiplier)
