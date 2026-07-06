extends Area3D

@export var cycle_enabled := true
@export var cycle_interval := 1.5
@export var effect_duration := 5.0
@export var respawn_time := 15.0

const BOB_HEIGHT = 0.15
const BOB_SPEED = 2.0

var available_types = ["extra_dash", "extra_melee_shield"]
var color_map = {
	"extra_dash": Color(0.2, 1.0, 1.0),
	"extra_melee_shield": Color(1.0, 0.85, 0.2)
}

var power_type := "extra_dash"
var spawn_position = Vector3.ZERO
var base_y = 0.0
var bob_time = 0.0
var collected = false
var cycle_timer = 0.0
var active_material: StandardMaterial3D = null

func _ready():
	add_to_group("powerup")
	body_entered.connect(_on_body_entered)
	collision_layer = 0
	set_collision_mask_value(2, true)
	spawn_position = global_position
	base_y = position.y
	_setup_material()
	power_type = available_types[randi() % available_types.size()]
	_update_color()
	cycle_timer = cycle_interval

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

func _process(delta):
	if collected:
		return
	rotate_y(delta * 2.0)
	bob_time += delta * BOB_SPEED
	position.y = base_y + sin(bob_time) * BOB_HEIGHT

	if cycle_enabled:
		cycle_timer -= delta
		if cycle_timer <= 0.0:
			power_type = available_types[randi() % available_types.size()]
			_update_color()
			cycle_timer = cycle_interval

func _on_body_entered(body):
	if collected:
		return
	if not body.is_in_group("player"):
		return
	if body.has_method("apply_powerup"):
		body.apply_powerup(power_type, effect_duration)
	_collect()

func _collect():
	collected = true
	visible = false
	set_deferred("monitoring", false)
	await get_tree().create_timer(respawn_time).timeout
	global_position = spawn_position
	position.y = base_y
	collected = false
	visible = true
	set_deferred("monitoring", true)
	power_type = available_types[randi() % available_types.size()]
	_update_color()
	cycle_timer = cycle_interval

func reset_to_spawn():
	collected = false
	global_position = spawn_position
	position.y = base_y
	visible = true
	monitoring = true
