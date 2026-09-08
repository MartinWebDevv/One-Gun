extends "res://maps/hideout/preview_actor.gd"
## Uses the production controller and host-owned practice boundary.
func _ready() -> void:
	pen = get_tree().current_scene.get_node("RoundManager")
	super._ready()

func shares_combat_space_with(other: Node) -> bool:
	return pen != null and pen.can_affect(self,other)
