extends RigidBody3D

@export var projectile_speed := 200.0
@export var emergency_lifetime := 10.0
var shooter = null            # local play: the shooter node

# Online (set by gun._net_spawn_bullet): the server owns hit detection; client
# bullets are visual-only and pass through everything.
var net_shooter_id := -1
var is_server_bullet := false
var net_round_epoch := -1

func _ready():
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(emergency_lifetime).timeout.connect(_expire)
	if NetworkManager.is_online():
		add_to_group("online_bullet")
		gravity_scale = 0.0   # straight-line, deterministic across peers
		if not is_server_bullet:
			# client bullet: fly through everything, purely visual
			set_deferred("contact_monitor", false)
			collision_mask = 0

func launch(direction: Vector3, who_fired: Node):
	shooter = who_fired
	if who_fired is PhysicsBody3D:
		add_collision_exception_with(who_fired)
	linear_velocity = direction.normalized() * projectile_speed

func _expire() -> void:
	if is_instance_valid(self):
		queue_free()

func _is_decoy(body: Node) -> bool:
	return body != null and body.has_method("is_combat_decoy") and body.is_combat_decoy()

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
	queue_free()

func _on_body_entered(body):
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
			GameEvents.combat_feedback.emit(shooter_name, "gun_hit")
			GameEvents.actor_combat_feedback.emit(int(shooter.get("actor_id")) if shooter != null and shooter.get("actor_id") != null else -1, "gun_hit")
		queue_free()
		return
	if not GameConfig.can_affect(shooter, body):
		queue_free()
		return
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
	queue_free()

func _on_hit_online(body):
	# Only the server resolves hits (authoritative). Clients never reach here
	# (their bullets have contact_monitor off).
	if not is_server_bullet:
		return
	if _is_decoy(body):
		_hit_decoy(body)
		return
	if not body.is_in_group("player"):
		queue_free()   # hit world geometry
		return
	if body.has_method("server_online_hit"):
		body.server_online_hit()
		queue_free()
		return
	var vid = body.get("actor_id")
	if vid == null or vid == net_shooter_id:
		return   # not a networked player, or the shooter — ignore
	var rm = get_tree().current_scene.get_node_or_null("RoundManager")
	if body.has_method("is_bullet_immune") and body.is_bullet_immune():
		# Blocked by immunity — still confirm the connect to the shooter.
		if rm != null and rm.has_method("server_confirm_hit"):
			rm.server_confirm_hit(net_shooter_id, false, "gun")
		queue_free()
		return
	if rm != null and rm.has_method("server_eliminate"):
		rm.server_eliminate(int(vid), net_shooter_id, net_round_epoch)
	queue_free()
