extends RigidBody3D

@export var projectile_speed := 200.0
@export var emergency_lifetime := 10.0
var shooter = null            # local play: the shooter node

# Online (set by gun._net_spawn_bullet): the server owns hit detection; client
# bullets predict world impacts for presentation and never resolve damage.
var net_shooter_id := -1
var is_server_bullet := false
var net_round_epoch := -1
var net_shot_id := -1
var _retired := false
var _age := 0.0
var _visual_client := false

func _ready():
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_body_entered)
	if NetworkManager.is_online():
		add_to_group("online_bullet")
		gravity_scale = 0.0   # straight-line, deterministic across peers
		if not is_server_bullet:
			_visual_client = true
			set_deferred("contact_monitor", false)
			collision_mask = 0
			collision_layer = 0

func launch(direction: Vector3, who_fired: Node):
	shooter = who_fired
	if who_fired is PhysicsBody3D:
		add_collision_exception_with(who_fired)
	linear_velocity = direction.normalized() * projectile_speed


func launch_from(origin: Vector3, direction: Vector3, who_fired: Node) -> void:
	# Rigid bodies can otherwise interpolate their first rendered transform from
	# the scene's authored origin. Position and reset interpolation before making
	# this projectile visible so frame zero is already on the reticle ray.
	global_position = origin
	reset_physics_interpolation()
	launch(direction, who_fired)

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= emergency_lifetime:
		_retire()
		return
	if not _visual_client or _retired or linear_velocity.is_zero_approx():
		return
	# Cosmetic prediction only. Peer actor motion can differ, so actor impacts
	# wait for the reliable host event; static cover stops the tracer immediately.
	var excluded: Array[RID] = [get_rid()]
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		excluded.append(shooter.get_rid())
	var query := PhysicsRayQueryParameters3D.create(global_position,
		global_position + linear_velocity * delta, 1, excluded)
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		retire_at(hit["position"])


func retire_at(impact_position: Vector3) -> void:
	if not impact_position.is_finite():
		return
	global_position = impact_position
	_retire()


func _retire() -> void:
	if _retired:
		return
	_retired = true
	visible = false
	if is_server_bullet and net_shot_id >= 0:
		GameEvents.online_projectile_retired.emit(net_shot_id, net_round_epoch, global_position)
	queue_free()


func _expire() -> void:
	_retire()

func _is_decoy(body: Node) -> bool:
	return body != null and body.has_method("is_combat_decoy") and body.is_combat_decoy()

func _incoming_source_direction() -> Vector3:
	var direction := -linear_velocity
	if direction.is_zero_approx() and shooter is Node3D:
		direction = (shooter as Node3D).global_position - global_position
	return direction.normalized() if not direction.is_zero_approx() else Vector3.ZERO

func _emit_local_damage_direction(body: Node) -> void:
	var victim_actor_id = body.get("actor_id") if body != null else null
	if victim_actor_id == null:
		return
	GameEvents.actor_damage_direction.emit(
		int(victim_actor_id), _incoming_source_direction(), "gun")

func _hit_decoy(body: PhysicsBody3D) -> void:
	var attacker = shooter
	if attacker == null and NetworkManager.is_online():
		attacker = NetworkManager.find_actor(net_shooter_id)
	var can_pop := true
	if body.has_method("can_be_affected_by"):
		can_pop = body.can_be_affected_by(attacker)
	if can_pop and body.has_method("pop_from_attack"):
		body.pop_from_attack(attacker, "gun")
	# Decoys are real collision targets. Whether friendly or hostile, a bullet
	# stops at this first impact instead of receiving a pass-through exception.
	_retire()

func _on_body_entered(body):
	if _retired:
		return
	if NetworkManager.is_online():
		_on_hit_online(body)
		return
	# ---- local play ----
	if body == shooter:
		return
	if _is_decoy(body):
		_hit_decoy(body)
		return
	var shooter_name: String = shooter.get_display_name() if shooter != null else ""
	if body.has_method("is_bullet_immune") and body.is_bullet_immune():
		if body.is_in_group("player") and GameConfig.can_affect(shooter, body):
			_emit_local_damage_direction(body)
			GameEvents.combat_feedback.emit(shooter_name, "gun_hit")
			GameEvents.actor_combat_feedback.emit(int(shooter.get("actor_id")) if shooter != null and shooter.get("actor_id") != null else -1, "gun_hit")
		_retire()
		return
	if not GameConfig.can_affect(shooter, body):
		_retire()
		return
	if body.is_in_group("player"):
		_emit_local_damage_direction(body)
	if body.has_method("flash_hit"):
		body.flash_hit()
	if body.has_method("eliminate"):
		var shooter_actor_id := int(shooter.get("actor_id")) if shooter != null and shooter.get("actor_id") != null else -1
		body.eliminate(shooter_name, "🔫", "weapon", shooter_actor_id)
		# eliminate() sets is_eliminated synchronously unless Extra Life ate the
		# hit — so this reads the true outcome for the red-vs-white marker.
		var eliminated := bool(body.get("is_eliminated"))
		var event_kind := "gun_elimination" if eliminated else "gun_hit"
		GameEvents.combat_feedback.emit(shooter_name, event_kind)
		GameEvents.actor_combat_feedback.emit(shooter_actor_id, event_kind)
	_retire()

func _on_hit_online(body):
	# Only the server resolves hits (authoritative). Clients never reach here
	# (their bullets have contact_monitor off).
	if not is_server_bullet:
		return
	if _is_decoy(body):
		_hit_decoy(body)
		return
	if not body.is_in_group("player"):
		_retire()   # hit world geometry
		return
	if body.has_method("server_online_hit"):
		body.server_online_hit()
		_retire()
		return
	var vid = body.get("actor_id")
	if vid == null or vid == net_shooter_id:
		return   # not a networked player, or the shooter — ignore
	var rm = get_tree().current_scene.get_node_or_null("RoundManager")
	if rm != null and rm.has_method("server_report_damage_direction"):
		rm.server_report_damage_direction(
			int(vid), net_shooter_id, _incoming_source_direction(), net_round_epoch)
	if body.has_method("is_bullet_immune") and body.is_bullet_immune():
		# Blocked by immunity — still confirm the connect to the shooter.
		if rm != null and rm.has_method("server_confirm_hit"):
			rm.server_confirm_hit(net_shooter_id, false, "gun")
		_retire()
		return
	if rm != null and rm.has_method("server_eliminate"):
		rm.server_eliminate(int(vid), net_shooter_id, net_round_epoch)
	_retire()
