extends RefCounted
## Course selection never changes match rules or extends a normal pickup.
static func clear(actor: CharacterBody3D) -> void:
	actor.clear_all_powerups()
	actor.clear_double_jump_shoes()
	actor._clear_spring_launch_state()
	actor._clear_steam_boost()
	actor.slow_timer=0.0
	actor.slow_multiplier_value=1.0
	actor.knockback_timer=0.0
	actor.knockback_velocity=Vector3.ZERO
	actor.stagger_timer=0.0
	actor.is_dashing=false
	actor.dash_charges=actor.max_dash_charges
	actor.dash_recharge_timer=0.0
	actor.stamina=100.0

static func start(actor: CharacterBody3D, powered: bool) -> void:
	clear(actor)
	if powered:
		# Read the normal pickup default; no course-specific duration multiplier.
		var pickup := preload("res://powerup.gd").new()
		actor.apply_powerup("speed_surge",pickup.effect_duration)
		actor.apply_powerup("extra_dash",pickup.effect_duration)
		pickup.free()
