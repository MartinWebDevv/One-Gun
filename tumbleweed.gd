extends RigidBody3D

# Rolls continuously under a constant "wind" force until its lifetime timer
# runs out, at which point it despawns (see tumbleweed_spawner.gd, which
# maintains 1-3 of these active across the map at any time). Not meant to
# interact with players/bots — collision_mask deliberately excludes them.

@export var wind_direction := Vector3(1.0, 0.0, 0.6).normalized()
@export var wind_strength := 2.0
@export var lifetime_min := 25.0
@export var lifetime_max := 35.0

func _ready():
	var timer = Timer.new()
	timer.wait_time = randf_range(lifetime_min, lifetime_max)
	timer.one_shot = true
	timer.timeout.connect(queue_free)
	add_child(timer)
	timer.start()
	# Random tumble spin so a batch of these doesn't look identical.
	angular_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))

func _integrate_forces(state: PhysicsDirectBodyState3D):
	state.apply_central_force(wind_direction * wind_strength)
