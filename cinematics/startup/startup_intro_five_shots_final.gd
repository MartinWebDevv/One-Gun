extends "res://cinematics/startup/startup_intro_five_shots.gd"

## Final framing refinement: the opening wide establishes all six competitors,
## then a restrained dark wipe clears the five targets before Blue's grab. This
## gives the pickup one unambiguous subject and prevents edge crowding.


func _blue_claims_the_gun(generation: int) -> bool:
	for actor_id in TARGET_ORDER:
		var target := _actors.get(actor_id) as Node3D
		if target != null:
			target.visible = false
	_flash.color = Color(BACKGROUND_COLOR, 0.16)
	_tween_property(_flash, "color:a", 0.0, 0.14,
		Tween.TRANS_QUAD, Tween.EASE_OUT)
	return await super._blue_claims_the_gun(generation)

