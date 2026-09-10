extends "res://character_body_3d.gd"
## Preview-only adapter: real movement/combat, with a spatial practice boundary.
var pen: Node
var is_sparring := false
var is_bot := false

func _ready():
	super._ready()
	if is_sparring:
		is_bot = true
		set_process_input(false)
		if SupabaseManager.loadout_updated.is_connected(_on_persistent_cosmetic_loadout_updated):
			SupabaseManager.loadout_updated.disconnect(_on_persistent_cosmetic_loadout_updated)

func _physics_process(delta):
	if pen == null:
		super._physics_process(delta)
		return
	pen.sync_actor(self)
	if is_sparring:
		pen.tick_sparring(self,delta)
	else:
		super._physics_process(delta)
	pen.sync_actor(self)

func in_playpen() -> bool:
	return pen != null and pen.contains_actor(self) and not is_eliminated

func register_interactable(obj):
	if in_playpen() and is_instance_valid(obj) and pen.contains_object(obj):
		super.register_interactable(obj)

func _try_interact() -> bool:
	if not in_playpen(): return false
	nearby_interactables = nearby_interactables.filter(func(obj):
		return is_instance_valid(obj) and pen.contains_object(obj))
	return super._try_interact()

func is_manual_pickup_request_active() -> bool:
	return in_playpen() and (is_sparring or super.is_manual_pickup_request_active())

func _try_primary_action():
	if in_playpen(): super._try_primary_action()

func apply_powerup(power_type: String, duration: float) -> bool:
	return super.apply_powerup(power_type,duration) if in_playpen() or bool(get_meta("course_grant",false)) else false

func can_collect_powerup(power_type: String) -> bool:
	return (in_playpen() or (bool(get_meta("course_grant",false)) and power_type in ["speed_surge","extra_dash"])) and super.can_collect_powerup(power_type)

func activate_double_jump_shoes() -> void:
	if in_playpen(): super.activate_double_jump_shoes()

func apply_knockback(direction: Vector3, distance: float):
	if in_playpen(): super.apply_knockback(direction,distance)

func apply_stagger(duration: float):
	if in_playpen(): super.apply_stagger(duration)

func apply_slow(duration: float, multiplier: float):
	if in_playpen(): super.apply_slow(duration,multiplier)

func apply_flash_blind(duration: float) -> void:
	if in_playpen(): super.apply_flash_blind(duration)

func apply_spring_launch(launch_velocity: float, horizontal_boost: float, direction_window: float) -> void:
	if in_playpen(): super.apply_spring_launch(launch_velocity,horizontal_boost,direction_window)

func flash_hit():
	if in_playpen(): super.flash_hit()

func is_bullet_immune():
	return not in_playpen() or super.is_bullet_immune()

func eliminate(killer_name = "", weapon_icon = "💀", lethal_kind := "weapon", killer_actor_id: int = -1):
	if not in_playpen() and not is_online: return
	# Reuse Extra Life, the death pop and event bus; keep this scene's own camera.
	var previous_bot := is_bot
	is_bot = true
	super.eliminate(killer_name,weapon_icon,lethal_kind,killer_actor_id)
	is_bot = previous_bot

func respawn(spawn_transform):
	super.respawn(spawn_transform)
	all_gun_hearts = 0 # Practice has no match-round heart accounting.
	if is_sparring: set_process_input(false)

func get_display_name() -> String:
	return "SPARRING PARTNER" if is_sparring else super.get_display_name()

func get_gun_fire_camera() -> Camera3D:
	return null if is_sparring else super.get_gun_fire_camera()

func get_camera():
	return null if is_sparring else super.get_camera()

func get_aim_direction():
	if is_sparring and pen != null:
		return (pen.lab.pilot.global_position+Vector3.UP*0.3-get_hold_point().global_position).normalized()
	return super.get_aim_direction()
