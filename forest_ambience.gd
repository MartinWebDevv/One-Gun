extends Node

## Lives in ForestMap: claims the forest music track for this match and runs
## the bird-chirp ambience loop. Both stop automatically when the map unloads.

func _ready() -> void:
	AudioManager.level_music_key = "forest"
	# round_manager's play_music("game") happens a couple frames into its
	# _ready; if it already fired before us, redirect now.
	AudioManager.play_music("game")
	AudioManager.play_ambient("forest_birds")

func _exit_tree() -> void:
	AudioManager.level_music_key = ""
	AudioManager.stop_ambient()
