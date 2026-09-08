extends Node3D

class TestActor extends CharacterBody3D:
	var actor_id := 1
	var owner_peer_id := 1
	var is_eliminated := false
	var holding_gun := false
	var team_id := -1
	func get_aim_direction() -> Vector3: return Vector3.FORWARD
	func get_display_name() -> String: return "Cover test"
	func get_hold_point() -> Node: return get_node("Hold")

class TestGun extends Node:
	var disarmed := false
	func force_disarm() -> void: disarmed = true

class TestRelay extends "res://round_manager.gd":
	func _ready() -> void: pass

class TestManager extends Node:
	var broadcasts: Array = []
	var online_round_epoch := 1
	var melee_hits := 0
	func broadcast_online_melee_action(_candidate: int, action: String, _payload: Dictionary) -> void:
		if action == "hit": melee_hits += 1
	func can_accept_online_combat(_epoch: int) -> bool: return true
	func broadcast_online_gun_action(action: String, payload: Dictionary) -> void:
		if action == "fire": broadcasts.append({"action": action, "payload": payload})

var _failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var actors := Node3D.new()
	actors.name = "NetPlayers"
	add_child(actors)
	var attacker := TestActor.new()
	actors.add_child(attacker)
	attacker.position = Vector3(0, 2, 0)
	var target := TestActor.new()
	target.add_to_group("player")
	target.actor_id = 2
	target.owner_peer_id = 2
	target.collision_layer = 2
	actors.add_child(target)
	target.position = Vector3(0, 2, -3)
	var target_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.495
	capsule.height = 2.3267
	target_shape.shape = capsule
	target.add_child(target_shape)
	var manager := TestManager.new()
	manager.name = "RoundManager"
	add_child(manager)
	var gun = preload("res://gun.tscn").instantiate()
	add_child(gun)
	gun.player_ref = attacker
	gun.is_held = true
	var melee = preload("res://melee_weapon.tscn").instantiate()
	add_child(melee)
	melee.player_ref = attacker
	var wall := StaticBody3D.new()
	wall.collision_mask = 0
	wall.position = Vector3(0, 2, -1.5)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 8, 0.04)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	gun._server_try_fire(1, Vector3.FORWARD, 1, Vector3(0, 2, -2), true)
	_check(manager.broadcasts.is_empty(), "origin within distance envelope but through cover was accepted")
	gun._server_try_fire(1, Vector3.FORWARD, 1, Vector3(0, 2, -6.5), true)
	_check(manager.broadcasts.is_empty(), "displaced origin was accepted")
	gun._server_try_fire(1, Vector3.FORWARD, 1, Vector3(0.8, 3.5, 0), true)
	_check(manager.broadcasts.size() == 1, "clear paired shoulder origin was rejected")
	_check(target not in melee._dedicated_swing_candidates(), "dedicated melee selected target behind wall")
	_check(not melee._swing_has_clear_cover(target), "local/listen melee cover rule allowed wall")
	for client_visual in [false, true]:
		NetworkManager._online = client_visual
		var bullet = preload("res://bullet.tscn").instantiate()
		add_child(bullet)
		bullet.launch_from(Vector3(0, 2, 0), Vector3.FORWARD, attacker)
		for _frame in 8: await get_tree().physics_frame
		_check(not is_instance_valid(bullet), "bullet survived wall; visual=%s" % client_visual)
		if is_instance_valid(bullet): bullet.queue_free()
	NetworkManager._online = false
	wall.position.x = 30
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(target in melee._dedicated_swing_candidates(), "clear doorway melee target was rejected")
	_check(melee._swing_has_clear_cover(target), "clear local/listen melee was rejected")
	# A thrown weapon is resolved at its real collision, even beyond swing reach.
	target.position.z = -9
	melee.is_swinging = true
	melee._server_resolve_hit(target, false)
	_check(manager.melee_hits == 0, "held swing hit beyond its range")
	melee.is_swinging = false
	melee._server_resolve_hit(target, true)
	_check(manager.melee_hits == 1, "real thrown collision was rejected beyond swing reach")
	# Impact retirement is independent of the gun staying held after death/drop.
	var relay := TestRelay.new()
	add_child(relay)
	relay.online_round_epoch = 3
	var visual = preload("res://bullet.tscn").instantiate()
	NetworkManager._online = true
	visual.net_shot_id = 12
	visual.net_round_epoch = 3
	add_child(visual)
	relay._net_retire_online_projectile(12, 2, Vector3.ONE)
	_check(not visual.is_queued_for_deletion(), "stale-round impact retired current bullet")
	# Current epoch/shot identity reaches a bullet even without a held gun.
	relay._net_retire_online_projectile(12, 3, Vector3.ONE)
	_check(visual.is_queued_for_deletion(), "authoritative impact did not retire visual")
	NetworkManager._online = false
	var icons: Array = []
	GameEvents.player_disarmed.connect(func(_victim, _killer, icon): icons.append(icon))
	var feed := VBoxContainer.new()
	feed.set_script(preload("res://kill_feed.gd"))
	add_child(feed)
	var hold := Node3D.new()
	hold.name = "Hold"
	target.add_child(hold)
	var held := TestGun.new()
	hold.add_child(held)
	target.holding_gun = true
	var boomerang := preload("res://boomerang.tscn").instantiate()
	add_child(boomerang)
	boomerang._thrower = attacker
	boomerang._strike(target)
	_check(held.disarmed and icons == ["🪃"], "boomerang disarm did not deliver its typed feed icon")
	if _failures.is_empty(): print("COMBAT_COVER_VALIDATION: PASS")
	else:
		for message in _failures: push_error(message)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok: _failures.append(message)
