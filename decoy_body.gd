extends StaticBody3D

## Deployed decoy: a fake standing player. Sits on the player collision layer
## and in the "player" group so bots target it and bullets connect. One hit
## pops it. Gives no kill credit and never emits elimination signals.
## Plays the shared idle animation so it reads as a real standing player.

const ANIM_SOURCE_GLB = "res://models/playerAnimations/Dance.glb"

var owner_player = null
var _popped := false
var _sway_time := 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	add_to_group("player")
	_setup_idle()

func _setup_idle() -> void:
	var ap: AnimationPlayer = find_child("AnimationPlayer", true, false)
	if ap == null:
		return
	if not ap.has_animation_library(""):
		ap.add_animation_library("", AnimationLibrary.new())
	var lib = ap.get_animation_library("")
	if not lib.has_animation("idle"):
		var packed = load(ANIM_SOURCE_GLB)
		if packed != null:
			var inst = packed.instantiate()
			var src = inst.find_child("AnimationPlayer", true, false)
			if src != null:
				var src_list = src.get_animation_list()
				if src_list.size() > 0:
					# idle is index 0 in the shared source (see ANIM_INDICES)
					var anim = src.get_animation(src_list[0]).duplicate()
					anim.loop_mode = Animation.LOOP_LINEAR
					lib.add_animation("idle", anim)
			inst.queue_free()
	if ap.has_animation("idle"):
		ap.play("idle")

func _process(delta: float) -> void:
	_sway_time += delta
	rotation.y += sin(_sway_time * 0.8) * 0.0006

# Bullets call eliminate() on what they hit; decoys just pop.
func eliminate(_killer := "", _icon = null) -> void:
	_pop()

func flash_hit() -> void:
	if not NetworkManager.is_online():
		_pop()

func is_bullet_immune() -> bool:
	return false

func get_display_name() -> String:
	return "Decoy"

func _pop() -> void:
	if _popped:
		return
	_popped = true
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = 24
	p.lifetime = 0.6
	p.explosiveness = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.85, 0.75)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = m
	p.draw_pass_1 = mesh
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -6.0, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	p.process_material = pm
	p.position = Vector3(0, 1.2, 0)
	get_parent().add_child(p)
	p.global_position = global_position + Vector3(0, 1.2, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)
	queue_free()

func server_online_hit() -> void:
	if NetworkManager.is_online() and multiplayer.is_server():
		var rm = get_tree().current_scene.get_node_or_null("RoundManager")
		if rm != null:
			rm.broadcast_online_deployed_action(int(get_meta("online_deployed_id", -1)), "pop")

func apply_online_action(action: String, _data: Dictionary) -> void:
	if action == "pop":
		_pop()
