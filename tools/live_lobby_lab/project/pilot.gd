extends CharacterBody3D
## Offline movement adapter, snapshotted from the human controller 2026-09-05.
## No gameplay singleton, pickup, damage, persistence, or networking dependency.
const Avatar = preload("res://avatar.gd")
const SPEED := 10.0
const SPRINT_SPEED := 18.0
const JUMP_VELOCITY := 7.0
const DASH_SPEED := 30.0
const DASH_DURATION := 0.2
const STEP_HEIGHT := 0.55
const STEP_FORWARD_PROBE := 0.25
const CAMERA_BOOM := 4.0
const CAPSULE_HEIGHT := 2.3266993
const CAPSULE_RADIUS := 0.495
@export var input_prefix := "p1"
var look: Node3D
var boom: SpringArm3D
var camera: Camera3D
var avatar: Node3D
var controls_enabled := false
var sprint_allowed := false
var stamina := 100.0
var regen_delay := 0.0
var charges: Array[float] = [0.0,0.0,0.0]
var dash_left := 0.0
var dash_direction := Vector3.ZERO
var desired_heading := 0.0

func _ready() -> void:
	name = "OfflinePilot"
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = CAPSULE_HEIGHT
	capsule.radius = CAPSULE_RADIUS
	collision.shape = capsule
	# Origin at soles; the equivalent live actor origin is 1.09m higher.
	collision.position.y = 1.16335
	add_child(collision)
	avatar = Avatar.new()
	add_child(avatar)
	look = Node3D.new()
	look.name = "AimPivot"
	add_child(look)
	boom = SpringArm3D.new()
	look.add_child(boom)
	boom.position = Vector3(0.6596317,1.6743513+1.09,-0.5467267) + Vector3(1.02,0.23,0.06)
	boom.spring_length = CAMERA_BOOM
	boom.margin = 0.15
	boom.collision_mask = 1
	boom.add_excluded_object(get_rid())
	camera = Camera3D.new()
	boom.add_child(camera)
	camera.position = Vector3(-0.43908894,-0.11221671+0.03,-0.13058637)
	camera.fov = 75.0
	camera.current = true
	look.rotation.x = -0.09
	_bind_inputs()

func _bind_inputs() -> void:
	var keys := {"left":KEY_A,"right":KEY_D,"forward":KEY_W,"back":KEY_S,
		"jump":KEY_SPACE,"dash":KEY_SHIFT,"sprint":KEY_CTRL,"interact":KEY_E,
		"events":KEY_TAB,"party":KEY_P,"locker":KEY_L,"accept":KEY_R,"cancel_queue":KEY_X}
	for action in keys:
		var full: String = input_prefix+"_"+action
		if not InputMap.has_action(full):
			InputMap.add_action(full)
			var event := InputEventKey.new()
			event.physical_keycode = keys[action]
			InputMap.action_add_event(full,event)

func _unhandled_input(event: InputEvent) -> void:
	if controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseMotion:
		look.rotation.y -= event.relative.x*0.0025
		look.rotation.x = clampf(look.rotation.x-event.relative.y*0.0025,-1.15,0.7)

func _physics_process(delta: float) -> void:
	for i in range(charges.size()):
		charges[i] = maxf(0,charges[i]-delta)
	regen_delay = maxf(0,regen_delay-delta)
	if regen_delay == 0:
		stamina = minf(100,stamina+20*delta)
	var v := Vector2.ZERO
	if controls_enabled:
		v = Input.get_vector(input_prefix+"_left",input_prefix+"_right",input_prefix+"_forward",input_prefix+"_back")
	var dir := Basis(Vector3.UP,look.rotation.y)*Vector3(v.x,0,v.y)
	var speed := SPEED
	if controls_enabled and sprint_allowed and Input.is_action_pressed(input_prefix+"_sprint") and stamina > 0 and v.length() > 0:
		speed = SPRINT_SPEED
		stamina = maxf(0,stamina-25*delta)
		regen_delay = 1.0
	if not is_on_floor():
		velocity.y -= 9.8*delta
	if controls_enabled and Input.is_action_just_pressed(input_prefix+"_jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	if controls_enabled and Input.is_action_just_pressed(input_prefix+"_dash") and dash_left <= 0:
		for i in range(charges.size()):
			if charges[i] <= 0:
				charges[i] = 3.0 # Game rules/config override the old 2s controller fallback.
				dash_left = DASH_DURATION
				dash_direction = dir.normalized() if dir.length_squared()>0.01 else -Basis(Vector3.UP,look.rotation.y).z
				break
	if not controls_enabled:
		dash_left = 0
	if dash_left > 0:
		dash_left -= delta
		dir = dash_direction
		speed = DASH_SPEED
	velocity.x = dir.x*speed
	velocity.z = dir.z*speed
	var desired := Vector3(velocity.x,0,velocity.z)
	move_and_slide()
	_try_step_up(desired,delta)
	if desired.length_squared() > 0.1:
		desired_heading = atan2(-dir.x,-dir.z)
	avatar.rotation.y = lerp_angle(avatar.rotation.y,desired_heading,minf(delta*14,1))
	avatar.animate(delta,desired.length())
	if global_position.y < -8 or absf(global_position.x)>23 or absf(global_position.z)>19:
		respawn()

func respawn() -> void:
	global_position = Vector3(0,1.3,14.2)
	velocity = Vector3.ZERO
	dash_left = 0
	look.rotation = Vector3(-0.09,0,0)
	desired_heading = 0
	avatar.rotation.y = 0

func _try_step_up(desired_h_vel: Vector3, delta: float) -> void:
	# Same up/forward/down body sweep used by character_body_3d.gd.
	if not is_on_floor(): return
	var h := Vector3(desired_h_vel.x,0,desired_h_vel.z)
	if h.length_squared()<0.04: return
	var dir := h.normalized()
	var blocked := false
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y<0.7 and n.dot(dir)<-0.4:
			blocked = true
			break
	if not blocked: return
	var params := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()
	params.from = global_transform
	params.motion = Vector3.UP*STEP_HEIGHT
	var up_dist := STEP_HEIGHT
	if PhysicsServer3D.body_test_motion(get_rid(),params,result):
		up_dist = result.get_travel().y
	if up_dist<0.03: return
	var raised := global_transform
	raised.origin.y += up_dist
	var fwd := dir*maxf(h.length()*delta,STEP_FORWARD_PROBE)
	params.from = raised
	params.motion = fwd
	if PhysicsServer3D.body_test_motion(get_rid(),params,result):
		if result.get_travel().length()<fwd.length()*0.5: return
	var fwd_pos := raised
	fwd_pos.origin += fwd
	params.from = fwd_pos
	params.motion = Vector3.DOWN*(up_dist+0.1)
	if not PhysicsServer3D.body_test_motion(get_rid(),params,result): return
	if result.get_collision_normal().angle_to(Vector3.UP)>floor_max_angle: return
	var step_h := up_dist+result.get_travel().y
	if step_h<=0.01 or step_h>STEP_HEIGHT: return
	global_position.y += step_h+0.02
