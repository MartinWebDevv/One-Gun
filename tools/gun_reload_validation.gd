extends Node
## Real gun/timer/transfer/projectile logic in an empty room with two holders.
class Holder extends Node3D:
	var holding_gun := false
	var held_melee_weapon = null
	var actor_id := 7201
	func get_hold_point() -> Node3D: return self
	func get_display_name() -> String: return "Reload fixture"
	func get_aim_direction() -> Vector3: return Vector3.FORWARD

var failures := 0
var shots := 0
func _shot(_origin: Vector3, _actor_id: int, kind: String, _radius: float) -> void:
	if kind=="gunshot": shots+=1
func _ready() -> void: _run.call_deferred()
func _check(ok: bool, message: String) -> void:
	if ok: print("PASS: ",message)
	else: failures+=1; print("FAIL: ",message)

func _run() -> void:
	var world:=Node3D.new()
	get_tree().root.add_child(world)
	get_tree().current_scene=world
	var first:=Holder.new();world.add_child(first)
	var second:=Holder.new();world.add_child(second)
	second.position.x=5
	var gun=load("res://gun.tscn").instantiate()
	GameEvents.combat_noise.connect(_shot)
	gun.loose_return_time=0.01
	world.add_child(gun)
	gun._local_pickup(first)
	var timer: Timer=gun.get_node("ReloadTimer")
	_check(is_equal_approx(gun.reload_time,2.0),"configured reload is two seconds")
	# Reproduce transfer near the end of a reload (the former near-zero wait_time).
	gun.can_fire=false
	timer.start(0.05)
	gun.force_disarm()
	gun._local_pickup(second)
	_check(gun.can_fire and timer.is_stopped() and gun.get_reload_progress()==1.0,"disarmed gun is immediately ready on pickup")
	gun.try_fire()
	_check(shots==1 and not gun.can_fire and timer.time_left>1.9,"next local shot starts a full two-second reload")
	await get_tree().create_timer(0.15).timeout
	for i in range(20): gun.try_fire()
	_check(shots==1 and not gun.can_fire,"rapid local clicks cannot bypass reload after disarm")
	# The replicated shot path must reset the duration too, regardless of timer history.
	gun.can_fire=false
	timer.start(0.05)
	gun.drop()
	gun._local_pickup(first)
	_check(gun.can_fire and timer.is_stopped(),"normal drop/pickup also clears the previous reload")
	gun._net_spawn_bullet(Vector3.ZERO,Vector3.FORWARD,first.actor_id,0)
	_check(not gun.can_fire and timer.time_left>1.9,"replicated shot starts a full reload after another transfer")
	# Moving a held gun to a replacement cosmetic socket is not a pickup.
	var progress: float=gun.get_reload_progress()
	var remaining: float=timer.time_left
	first.remove_child(gun);first.add_child(gun)
	gun._resume_reload_after_reparent(remaining)
	_check(not gun.can_fire and is_equal_approx(gun.get_reload_progress(),progress),"cosmetic reattachment preserves the current reload")
	await get_tree().create_timer(0.2).timeout
	_check(not gun.can_fire,"replicated reload stays locked past the old shortened duration")
	gun._apply_forced_reload()
	_check(not gun.can_fire and timer.time_left>1.9,"forced reload still uses the full configured duration")
	gun.reset_to_spawn()
	_check(gun.can_fire and timer.is_stopped(),"round reset clears the current reload")
	# This short fixture exits before gunshot audio naturally finishes.
	for sound in AudioManager.get_children():
		if sound is AudioStreamPlayer: sound.stop()
	await get_tree().create_timer(0.15).timeout
	world.queue_free()
	await get_tree().process_frame
	print("GUN_RELOAD_VALIDATION_COMPLETE failures=",failures)
	get_tree().quit(1 if failures else 0)
