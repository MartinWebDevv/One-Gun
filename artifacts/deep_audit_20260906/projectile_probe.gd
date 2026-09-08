extends Node3D
class AuditActor extends CharacterBody3D:
	var actor_id := 1
	var owner_peer_id := 1
	var is_eliminated := false
	func get_aim_direction() -> Vector3: return Vector3.FORWARD
class AuditManager extends Node:
	var broadcasts: Array = []
	func can_accept_online_combat(_epoch:int)->bool:return true
	func broadcast_online_gun_action(action:String,payload:Dictionary)->void: broadcasts.append({"action":action,"payload":payload})
func _ready()->void:_run.call_deferred()
func _run()->void:
	var wall:=StaticBody3D.new()
	wall.name="ThinWall"
	wall.collision_mask=0
	wall.position=Vector3(0,2,-5)
	var collision:=CollisionShape3D.new()
	var box:=BoxShape3D.new();box.size=Vector3(20,8,0.04);collision.shape=box
	wall.add_child(collision);add_child(wall)
	await get_tree().physics_frame
	for server_mode in [false,true]:
		NetworkManager._online=server_mode
		var bullet=load("res://bullet.tscn").instantiate()
		bullet.position=Vector3(0,2,0)
		add_child(bullet);bullet.launch_from(Vector3(0,2,0),Vector3.FORWARD,null)
		for i in range(12): await get_tree().physics_frame
		print("AUDIT_BULLET mode=",("client-visual" if server_mode else "local-authoritative")," still_exists=",is_instance_valid(bullet)," position=",bullet.global_position if is_instance_valid(bullet) else null)
		if is_instance_valid(bullet):bullet.queue_free()
		await get_tree().process_frame
	NetworkManager._online=false
	var actor:=AuditActor.new();var players:=Node3D.new();players.name="NetPlayers";add_child(players);players.add_child(actor)
	actor.global_position=Vector3(0,2,0)
	var manager:=AuditManager.new();manager.name="RoundManager";add_child(manager)
	var gun=load("res://gun.tscn").instantiate();add_child(gun)
	gun.player_ref=actor;gun.is_held=true
	var normal:=Vector3.FORWARD
	gun._server_try_fire(1,normal,1,Vector3(0,2,-6.5),true)
	print("AUDIT_REMOTE_ORIGIN accepted_count=",manager.broadcasts.size()," submitted_origin=",Vector3(0,2,-6.5)," wall_z=-5 actor=",actor.global_position)
	if manager.broadcasts.size()>0:print("AUDIT_REMOTE_ORIGIN_EVENT ",JSON.stringify(manager.broadcasts[0]))

	wall.position=Vector3(0,2,-1.5)
	var target:=AuditActor.new();target.actor_id=2;target.owner_peer_id=2
	players.add_child(target);target.position=Vector3(0,2,-3);target.collision_layer=2
	var target_shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=0.495;capsule.height=2.3267;target_shape.shape=capsule;target.add_child(target_shape)
	var melee=load("res://melee_weapon.tscn").instantiate();add_child(melee);melee.player_ref=actor
	await get_tree().physics_frame
	await get_tree().physics_frame
	var candidates:Array=melee._dedicated_swing_candidates()
	var ray:=PhysicsRayQueryParameters3D.create(actor.position+Vector3.UP*0.55,target.position+Vector3.UP*0.55,1)
	ray.exclude=[gun.get_rid(),melee.get_rid()]
	var obstruction:=get_world_3d().direct_space_state.intersect_ray(ray)
	print("AUDIT_MELEE behind_wall_candidate=",target in candidates," obstructed_by=",obstruction.get("collider",null))
	get_tree().quit()
