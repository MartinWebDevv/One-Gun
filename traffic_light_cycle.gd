extends Node3D

## Cycles a TrafficLight.glb's Lamp_R / Lamp_Y / Lamp_G between lit and dim.
## `state` is readable by cars ("green" / "yellow" / "red").

@export var green_time: float = 7.0
@export var yellow_time: float = 2.0
@export var red_time: float = 7.0

var state := "green"
var _timer := 0.0
var _lamps := {}
var _dim_mats := {}
var _lit_mats := {}

func _ready() -> void:
	for lname in ["Lamp_R", "Lamp_Y", "Lamp_G"]:
		var lamp = find_child(lname, true, false)
		if lamp == null:
			continue
		var mi: MeshInstance3D = lamp if lamp is MeshInstance3D else _first_mesh(lamp)
		if mi == null:
			continue
		_lamps[lname] = mi
		var base := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if base:
			var lit := base.duplicate()
			var dim := base.duplicate()
			dim.emission_enabled = false
			dim.albedo_color = dim.albedo_color.darkened(0.65)
			_lit_mats[lname] = lit
			_dim_mats[lname] = dim
	_apply()

func _first_mesh(node: Node) -> MeshInstance3D:
	for c in node.get_children():
		if c is MeshInstance3D:
			return c
		var r := _first_mesh(c)
		if r:
			return r
	return null

func _process(delta: float) -> void:
	_timer += delta
	match state:
		"green":
			if _timer >= green_time:
				state = "yellow"
				_timer = 0.0
				_apply()
		"yellow":
			if _timer >= yellow_time:
				state = "red"
				_timer = 0.0
				_apply()
		"red":
			if _timer >= red_time:
				state = "green"
				_timer = 0.0
				_apply()

func _apply() -> void:
	var lit_map := {"green": "Lamp_G", "yellow": "Lamp_Y", "red": "Lamp_R"}
	for lname in _lamps:
		var mi: MeshInstance3D = _lamps[lname]
		if lname == lit_map[state]:
			mi.set_surface_override_material(0, _lit_mats.get(lname))
		else:
			mi.set_surface_override_material(0, _dim_mats.get(lname))
