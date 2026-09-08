extends "res://tools/live_lobby_preview/preview_actor.gd"
var duel: Node
var demo_bot := true
var rival: CharacterBody3D
var label_name := "SCRAP PARTNER"

func _physics_process(delta):
	if duel==null: return
	if not duel.can_fight(self) or not duel.lab.ui.page.is_empty() or is_instance_valid(duel.lab.native_overlay):
		velocity=Vector3.ZERO
		return
	if demo_bot:
		pen.sync_actor(self)
		duel.tick_bot(self,delta)
		pen.sync_actor(self)
	else: super._physics_process(delta)

func get_display_name() -> String:
	return label_name

func get_aim_direction():
	if demo_bot and is_instance_valid(rival):
		var origin: Vector3=get_hold_point().global_position
		for obj in get_hold_point().get_children():
			if obj.is_in_group("gun"):
				var muzzle: Node3D=obj.get_node_or_null("WaterGun/MuzzlePoint")
				if muzzle: origin=muzzle.global_position
				break
		return (rival.global_position+Vector3.UP*0.3-origin).normalized()
	return super.get_aim_direction()

func get_camera():
	return null if demo_bot else get_gameplay_camera()

func get_gun_fire_camera() -> Camera3D:
	return null if demo_bot else get_gameplay_camera()
