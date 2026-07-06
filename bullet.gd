extends RigidBody3D

const SPEED = 60.0
var shooter = null

func _ready():
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_body_entered)

func launch(direction: Vector3, who_fired: Node):
	shooter = who_fired
	linear_velocity = direction * SPEED

func _on_body_entered(body):
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
