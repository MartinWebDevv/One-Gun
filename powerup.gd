extends Area3D

# Type is fixed once at spawn and re-rolled only when the powerup respawns.
@export var effect_duration := 5.0
@export var respawn_time := 8.0
@export var fixed_power_type := ""

const BOB_HEIGHT = 0.15
const BOB_SPEED = 2.0

const ICON_TEXTURES := {
	"extra_dash": preload("res://models/2DPowerUpLogos/extra dash.png"),
	"sticky_hands": preload("res://models/2DPowerUpLogos/sticky hands pixel.png"),
	"speed_surge": preload("res://models/2DPowerUpLogos/speed surge.png"),
	"silent_steps": preload("res://models/2DPowerUpLogos/silent steps pixel.png"),
	"extra_life": preload("res://models/2DPowerUpLogos/extra life.png"),
	"reach": preload("res://models/2DPowerUpLogos/reach pixel.png"),
	"fast_hands": preload("res://models/2DPowerUpLogos/fastHands2D.png"),
}

const DISPLAY_NAMES := {
	"extra_dash": "Extra Dash",
	"sticky_hands": "Sticky Hands",
	"speed_surge": "Speed Surge",
	"silent_steps": "Silent Steps",
	"extra_life": "Extra Life",
	"reach": "Reach",
	"fast_hands": "Fast Hands",
}

var color_map = {
	"extra_dash": Color(0.2, 1.0, 1.0),
	"sticky_hands": Color(0.2, 1.0, 0.35),
	"speed_surge": Color(0.3, 1.0, 0.3),
	"silent_steps": Color(0.55, 0.55, 0.85),
	"extra_life": Color(1.0, 0.72, 0.18),
	"reach": Color(0.2, 1.0, 0.42),
	"fast_hands": Color(1.0, 0.2, 0.68),
}

var power_type := "extra_dash"
var spawn_position = Vector3.ZERO
var base_y = 0.0
var bob_time = 0.0
var collected = false
var overtime_disabled := false
var online_powerup_id := -1
var _respawn_generation := 0

@onready var powerup_icon: Sprite3D = $PowerupIcon
@onready var powerup_name_label: Label3D = $PowerupName

func _ready():
	var enabled_types := GameConfig.enabled_powerup_types()
	if enabled_types.is_empty() or (fixed_power_type != "" and fixed_power_type not in enabled_types):
		queue_free()
		return
	add_to_group("powerup")
	body_entered.connect(_on_body_entered)
	collision_layer = 0
	set_collision_mask_value(2, true)
	spawn_position = global_position
	base_y = position.y
	if fixed_power_type in enabled_types:
		power_type = fixed_power_type
	elif not NetworkManager.is_online():
		power_type = enabled_types[randi() % enabled_types.size()]
	_update_visual()

func _update_visual():
	if powerup_icon != null:
		powerup_icon.texture = ICON_TEXTURES.get(
			power_type, ICON_TEXTURES["extra_dash"])
	if powerup_name_label != null:
		powerup_name_label.text = str(DISPLAY_NAMES.get(
			power_type, power_type.replace("_", " ").capitalize()))
		powerup_name_label.modulate = color_map.get(power_type, Color.WHITE)


func _process(delta):
	if collected:
		return
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


func try_collect_for(body) -> bool:
	if overtime_disabled or collected or body == null or not body.is_in_group("player"):
		return false
	if NetworkManager.is_online():
		var rm = get_tree().current_scene.get_node_or_null("RoundManager")
		if rm != null:
			rm.request_online_powerup_collect(online_powerup_id, int(body.get("actor_id")))
			return true
		return false
	if not body.has_method("apply_powerup") or not body.apply_powerup(power_type, effect_duration):
		return false
	_collect()
	return true

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
	var enabled_types := GameConfig.enabled_powerup_types()
	if enabled_types.is_empty():
		queue_free()
		return
	power_type = fixed_power_type if fixed_power_type in enabled_types \
		else enabled_types[randi() % enabled_types.size()]
	_update_visual()

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
	_update_visual()

func reset_to_spawn():
	_respawn_generation += 1
	overtime_disabled = false
	if not GameConfig.is_powerup_enabled(power_type):
		queue_free()
		return
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
