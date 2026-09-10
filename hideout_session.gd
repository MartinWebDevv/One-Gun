extends Node
## Small persistent front-end state; never retains a loaded 3D world.
const SCENE := "res://maps/hideout/hideout.tscn"
var selected_map := ""
var return_message := ""
var home_rules: Dictionary = {}
var home_map := ""
var course_lobby_times: Dictionary = {}
var course_lobby_details: Dictionary = {}
var course_powerup_selected := false
var scrap_lobby_wins: Dictionary = {}

func _ready() -> void:
	if not MapRegistry.MAPS.is_empty(): selected_map = str(MapRegistry.MAPS[0].get("scene_path", ""))

func remember_home() -> void:
	if home_rules.is_empty():
		home_rules = GameConfig.snapshot_for_network().duplicate(true)
		home_map = selected_map

func restore_home() -> void:
	if not home_rules.is_empty():
		GameConfig.apply_network_values(home_rules)
		selected_map = home_map
		home_rules.clear()
		home_map = ""

func return_home(message := "") -> void:
	return_message = message
	PauseManager.reset_pause_state()
	if not NetworkManager.is_online(): restore_home()
	get_tree().change_scene_to_file(SCENE)
