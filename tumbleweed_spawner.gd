extends Node3D

# Keeps 1-3 tumbleweeds rolling around the map at all times. Each
# tumbleweed despawns on its own lifetime timer (tumbleweed.gd), not on
# wall contact — this node just periodically tops the count back up.

@export var tumbleweed_scene: PackedScene
@export var max_active := 3
@export var map_half := 45.0  # kept a bit inside the boundary walls
@export var check_interval := 2.5
@export var spawn_height := 2.0

var active_tumbleweeds: Array = []

func _ready():
	var timer = Timer.new()
	timer.wait_time = check_interval
	timer.autostart = true
	timer.timeout.connect(_maybe_spawn)
	add_child(timer)
	# Seed the map with a couple so it isn't empty at round start.
	_spawn_one()
	_spawn_one()

func _maybe_spawn():
	active_tumbleweeds = active_tumbleweeds.filter(func(t): return is_instance_valid(t))
	if active_tumbleweeds.size() < max_active:
		_spawn_one()

func _spawn_one():
	if tumbleweed_scene == null:
		return
	var t = tumbleweed_scene.instantiate()
	add_child(t)
	t.global_position = Vector3(randf_range(-map_half, map_half), spawn_height, randf_range(-map_half, map_half))
	active_tumbleweeds.append(t)
