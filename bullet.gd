extends RigidBody3D

const SPEED = 60.0
var shooter = null            # local play: the shooter node

# Online (set by gun._net_spawn_bullet): the server owns hit detection; client
# bullets are visual-only and pass through everything.
var net_shooter_id := -1
var is_server_bullet := false
var net_round_epoch := -1

func _ready():
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_body_entered)
	if NetworkManager.is_online():
		add_to_group("online_bullet")
		gravity_scale = 0.0   # straight-line, deterministic across peers
		if not is_server_bullet:
			# client bullet: fly through everything, purely visual
			set_deferred("contact_monitor", false)
			collision_mask = 0
		get_tree().create_timer(2.5).timeout.connect(func():
			if is_instance_valid(self):
				queue_free()
		)

func launch(direction: Vector3, who_fired: Node):
	shooter = who_fired
	linear_velocity = direction * SPEED

func _on_body_entered(body):
	if NetworkManager.is_online():
		_on_hit_online(body)
		return
	# ---- local play ----
	if body == shooter:
		return
	if body.has_method("is_bullet_immune") and body.is_bullet_immune():
		queue_free()
		return
	if not GameConfig.can_affect(shooter, body):
		queue_free()
		return
	if body.has_method("flash_hit"):
		body.flash_hit()
	if body.has_method("eliminate"):
		var killer_name = shooter.get_display_name() if shooter != null else ""
		body.eliminate(killer_name, "🔫")
	queue_free()

func _on_hit_online(body):
	# Only the server resolves hits (authoritative). Clients never reach here
	# (their bullets have contact_monitor off).
	if not is_server_bullet:
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
	if body.has_method("is_bullet_immune") and body.is_bullet_immune():
		queue_free()
		return
	var rm = get_tree().current_scene.get_node_or_null("RoundManager")
	if rm != null and rm.has_method("server_eliminate"):
		rm.server_eliminate(int(vid), net_shooter_id, net_round_epoch)
	queue_free()
