extends Node3D
## One inexpensive bounded toy. Analytic flight + swept world hits; no combat objects.
const G=preload("res://maps/hideout/geometry.gd")
const ORIGIN:=Vector3(4.5,-0.6,3)
const GOALS:=[Vector3(6,-0.05,-3),Vector3(3.5,0.8,-4.5)]
var lab: Node3D
var ball: MeshInstance3D
var velocity:=Vector3.ZERO
var flying:=false
var flight_left:=0.0
var score:=0
var attempts:=0
var banked:=false
var label: Label3D

func setup(preview: Node3D) -> void:
	lab=preview
	if not lab.station.has_meta("toss_zone_added"):
		lab.station._zone("toss",ORIGIN+Vector3(0,1,0),Vector3(5,3,4))
		lab.station.set_meta("toss_zone_added",true)
	var wood:=G.material("toss_wood",Color("ba8657"))
	var coral:=G.material("toss_coral",G.ORANGE)
	G.box(self,"BallBasket",ORIGIN+Vector3(1.8,0.35,0),Vector3(0.85,0.7,0.85),wood,true)
	G.panel(self,"TossSign","TRICKSHOT TOSS",ORIGIN+Vector3(1.8,1.65,0),Vector2(3.3,0.5),G.ORANGE)
	label=G.label(self,"TossScore","AIM + INTERACT / SOFT BALLS",ORIGIN+Vector3(1.8,1.15,0.05),32,G.CYAN,0.005)
	for i in range(GOALS.size()):
		var at: Vector3=GOALS[i]
		G.cylinder(self,"BasketStand",Vector3(at.x,(-0.6+at.y)*0.5,at.z),0.08,at.y+0.6,wood)
		G.ring(self,"BasketRim",0.48,0.62,at.y,coral).position=Vector3(at.x,0,at.z)
		for j in range(10):
			var a: float=j*TAU/10
			G.rod(self,at+Vector3(sin(a)*0.5,0,cos(a)*0.5),at+Vector3(sin(a)*0.3,-0.55,cos(a)*0.3),0.018,wood)
		G.box(self,"TossBackboard",at+Vector3(0,0.75,-0.9),Vector3(1.8,1.4,0.13),coral,true)
	ball=MeshInstance3D.new()
	var mesh:=SphereMesh.new()
	mesh.radius=0.18
	mesh.height=0.36
	mesh.radial_segments=16
	mesh.rings=8
	ball.mesh=mesh
	ball.material_override=G.material("toss_ball",Color("b29ae2"))
	add_child(ball)
	reset_ball()
	set_physics_process(false)

func throw_ball() -> bool:
	if flying or not lab.controls_enabled or not lab.nearby.has("toss"): return false
	ball.position=lab.pilot.get_gameplay_camera().global_position+lab.pilot.get_aim_direction()*1.2
	# Release from the character, avoiding a shot originating behind the bench/camera.
	ball.position=lab.pilot.position+Vector3(0,0.65,0)+lab.pilot.get_aim_direction()*0.6
	velocity=lab.pilot.get_aim_direction()*10.5+Vector3.UP*3.0
	flying=true
	flight_left=6.0
	banked=false
	attempts+=1
	set_physics_process(true)
	return true

func _physics_process(delta: float) -> void:
	if not lab.controls_enabled and not NetworkManager.is_online(): return
	var before:=ball.position
	velocity.y-=9.8*delta
	var after:=before+velocity*delta
	for goal in GOALS:
		if before.y>=goal.y and after.y<goal.y:
			var t: float=(before.y-goal.y)/maxf(before.y-after.y,0.00001)
			var crossing:=before.lerp(after,t)
			if Vector2(crossing.x-goal.x,crossing.z-goal.z).length()<0.43:
				score+=2 if banked else 1
				lab.ui.show_toast("BANK SHOT! +2" if banked else "NICE SHOT! +1")
				reset_ball()
				return
	var query:=PhysicsRayQueryParameters3D.create(before,after,1)
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		velocity=velocity.bounce(hit.normal)*0.62
		after=hit.position+hit.normal*0.2
		banked=true
	ball.position=after
	flight_left-=delta
	if flight_left<=0 or after.y< -1.0 or Vector2(after.x,after.z).length()>9.2: reset_ball()

func reset_ball() -> void:
	flying=false
	velocity=Vector3.ZERO
	ball.position=ORIGIN+Vector3(1.8,0.8,0)
	label.text="%d POINTS / %d THROWS / AIM + INTERACT" % [score,attempts]
	set_physics_process(false)
