extends Area3D

# Type is fixed once at spawn and re-rolled only when the powerup respawns.
@export var effect_duration := 5.0
@export var respawn_time := 15.0
@export var fixed_power_type := ""

const BOB_HEIGHT = 0.15
const BOB_SPEED = 2.0

const DISPLAY_NAMES := {
	"extra_dash": "Extra Dash",
	"sticky_hands": "Sticky Hands",
	"speed_surge": "Speed Surge",
	"silent_steps": "Silent Steps",
	"vampire_touch": "Vampire Touch",
	"extra_life": "Extra Life",
	"magnet_hands": "Magnet Hands",
}

var available_types = ["extra_dash", "sticky_hands", "speed_surge", "silent_steps", "vampire_touch", "extra_life", "magnet_hands"]
var color_map = {
	"extra_dash": Color(0.2, 1.0, 1.0),
	"sticky_hands": Color(0.2, 1.0, 0.35),
	"speed_surge": Color(0.3, 1.0, 0.3),
	"silent_steps": Color(0.55, 0.55, 0.85),
	"vampire_touch": Color(0.85, 0.15, 0.25),
	"extra_life": Color(1.0, 0.72, 0.18),
	"magnet_hands": Color(0.85, 0.35, 0.95),
}

var power_type := "extra_dash"
var spawn_position = Vector3.ZERO
var base_y = 0.0
var bob_time = 0.0
var collected = false
var overtime_disabled := false
var active_material: StandardMaterial3D = null
var online_powerup_id := -1
var _respawn_generation := 0

@onready var powerup_name_label: Label3D = $PowerupName

func _ready():
	add_to_group("powerup")
	body_entered.connect(_on_body_entered)
	collision_layer = 0
	set_collision_mask_value(2, true)
	spawn_position = global_position
	base_y = position.y
	_setup_material()
	if fixed_power_type in available_types:
		power_type = fixed_power_type
	elif not NetworkManager.is_online():
		power_type = available_types[randi() % available_types.size()]
	_update_color()

func _setup_material():
	var mesh_instance = $MeshInstance3D
	var existing = mesh_instance.get_surface_override_material(0)
	if existing == null:
		existing = mesh_instance.mesh.surface_get_material(0)
	if existing != null:
		active_material = existing.duplicate()
	else:
		active_material = StandardMaterial3D.new()
	active_material.emission_enabled = true
	active_material.emission_energy_multiplier = 2.5
	mesh_instance.set_surface_override_material(0, active_material)

func _update_color():
	if active_material != null and color_map.has(power_type):
		active_material.albedo_color = color_map[power_type]
		active_material.emission = color_map[power_type]
	if powerup_name_label != null:
		powerup_name_label.text = str(DISPLAY_NAMES.get(
			power_type, power_type.replace("_", " ").capitalize()))
		powerup_name_label.modulate = color_map.get(power_type, Color.WHITE)

func _process(delta):
	if collected:
		return
	rotate_y(delta * 2.0)
	bob_time += delta * BOB_SPEED
	position.y = base_y + sin(bob_time) * BOB_HEIGHT

func _on_body_entered(body):
	if overtime_disabled:
		return
	if collected:
		return
	if not body.is_in_group("player"):
		return
	if NetworkManager.is_online():
		if multiplayer.is_server():
			var rm = get_tree().current_scene.get_node_or_null("RoundManager")
			if rm != null:
				rm.server_collect_online_powerup(online_powerup_id, int(body.get("actor_id")), rm.online_round_epoch)
		return
	if body.has_method("apply_powerup"):
		if not body.apply_powerup(power_type, effect_duration):
			return
	_collect()

func _collect():
	collected = true
	visible = false
	set_deferred("monitoring", false)
	_respawn_generation += 1
	var generation := _respawn_generation
	await get_tree().create_timer(respawn_time).timeout
	if generation != _respawn_generation or overtime_disabled or not is_inside_tree():
		return
	global_position = spawn_position
	position.y = base_y
	collected = false
	visible = true
	set_deferred("monitoring", true)
	power_type = fixed_power_type if fixed_power_type in available_types \
		else available_types[randi() % available_types.size()]
	_update_color()

func _net_collect(actor_id: int, collected_type: String) -> void:
	if collected:
		return
	collected = true
	visible = false
	set_deferred("monitoring", false)
	var actor = NetworkManager.find_actor(actor_id)
	if actor != null and actor.has_method("apply_powerup"):
		actor.apply_powerup(collected_type, effect_duration)

func _net_respawn(new_type: String) -> void:
	if overtime_disabled:
		return
	power_type = new_type
	global_position = spawn_position
	position.y = base_y
	collected = false
	visible = true
	monitoring = true
	_update_color()

func reset_to_spawn():
	_respawn_generation += 1
	overtime_disabled = false
	collected = false
	global_position = spawn_position
	position.y = base_y
	visible = true
	monitoring = true

func disable_for_overtime() -> void:
	_respawn_generation += 1
	overtime_disabled = true
	collected = true
	visible = false
	monitoring = false
