extends StaticBody3D
## Reusable wooden practice target. Hits give feedback without match elimination.
const G = preload("res://maps/hideout/geometry.gd")
var training: Node
var lane := 0
var is_eliminated := false
var face: MeshInstance3D
var flash: Tween

func _ready() -> void:
	if NetworkManager.is_online(): add_to_group("player")
	collision_layer=2
	collision_mask=0
	var wood := G.material("range_target_wood",Color("a27346"))
	var paint := G.material("range_target_face",Color("eee4c9"))
	var ink := G.material("range_target_ink",Color("36413d"))
	G.box(self,"WoodenTorso",Vector3(0,1.4,0),Vector3(0.3,1.25,1.0),wood)
	G.cylinder(self,"WoodenHead",Vector3(0,2.25,0),0.36,0.5,wood)
	for side in [-1,1]:
		G.box(self,"WoodenLeg",Vector3(0,0.45,side*0.29),Vector3(0.27,0.9,0.22),wood)
		G.box(self,"WoodenArm",Vector3(0,1.68,side*0.67),Vector3(0.24,0.24,0.45),wood)
	var target := Node3D.new()
	add_child(target)
	target.position=Vector3(-0.18,1.48,0)
	target.rotation.z=PI/2
	face=G.cylinder(target,"PracticeFace",Vector3.ZERO,0.44,0.045,paint)
	face.material_override=paint.duplicate()
	G.cylinder(target,"OuterRing",Vector3(0,0.035,0),0.32,0.025,ink)
	G.cylinder(target,"InnerRing",Vector3(0,0.055,0),0.23,0.015,paint)
	G.cylinder(target,"Bullseye",Vector3(0,0.07,0),0.09,0.015,G.material("range_target_center",G.ORANGE))
	var bounds := BoxShape3D.new()
	bounds.size=Vector3(0.38,2.5,1.8)
	var collision := CollisionShape3D.new()
	collision.shape=bounds
	collision.position.y=1.25
	add_child(collision)

func flash_hit() -> void:
	if flash and flash.is_running(): flash.kill()
	face.material_override.albedo_color=G.GREEN
	flash=create_tween()
	flash.tween_property(face.material_override,"albedo_color",Color("eee4c9"),0.2)

func eliminate(_who := "", _icon := "", _kind := "weapon", _actor_id := -1) -> void:
	if is_instance_valid(training): training.target_hit(lane)

func server_online_hit() -> void:
	if NetworkManager.is_host():
		flash_hit()
		training.target_hit(lane)
