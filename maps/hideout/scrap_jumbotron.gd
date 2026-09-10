extends Node3D
## Four lightweight world-space faces; no extra camera, viewport, or lights.
const G = preload("res://maps/hideout/geometry.gd")
const FIGHTER_RED := Color("ff666f")
const FIGHTER_BLUE := Color("65adff")
var faces: Array[Dictionary] = []
var coin_angle := 0.0

func _ready() -> void:
	set_process(false)
	position = Vector3(17,7.4,-110)
	G.box(self,"Suspension",Vector3(0,2,0),Vector3(0.3,3,0.3),G.material("jumbo_rig",G.INK))
	for index in range(4):
		var face := Node3D.new()
		add_child(face)
		face.rotation.y = index*PI/2
		G.box(face,"Case",Vector3(0,0,3.4),Vector3(6.9,3.6,0.16),G.material("jumbo_case",G.INK))
		G.box(face,"Trim",Vector3(0,-1.72,3.51),Vector3(6.9,0.08,0.04),G.material("jumbo_trim",G.ORANGE,0.2))
		G.label(face,"Heading","THE SCRAP YARD",Vector3(0,1.35,3.52),64,G.ORANGE,0.007)
		var label := G.label(face,"Matchup","JOIN THE SCRAP",Vector3(0,-0.15,3.53),60,G.PAPER,0.009)
		label.width=620
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		var red_name := G.label(face,"RedFighter","",Vector3(0,0.6,3.53),60,FIGHTER_RED,0.009)
		var blue_name := G.label(face,"BlueFighter","",Vector3(0,-0.9,3.53),60,FIGHTER_BLUE,0.009)
		red_name.hide()
		blue_name.hide()
		var coin := Node3D.new()
		face.add_child(coin)
		coin.position=Vector3(0,0,3.65)
		var disc := G.cylinder(coin,"Coin",Vector3.ZERO,0.8,0.1,G.material("jumbo_coin",G.GOLD,0.1,0.3))
		disc.rotation.x=PI/2
		var letter := G.label(coin,"Side","H",Vector3(0,0,0.08),90,G.INK,0.009)
		faces.append({"label":label,"coin":coin,"letter":letter,"red_name":red_name,"blue_name":blue_name})

func present(names: Array, status: String, coin_side: String, flipping: bool, showing_coin: bool, remaining: float) -> void:
	set_process(flipping and showing_coin)
	coin_angle=(2.0-remaining)*TAU*3 if flipping else 0.0
	var text: String = status
	var matchup := names.size()==2 and not showing_coin
	if matchup: text="VS"
	var font_size:=60
	if names.size()==2:
		font_size=mini(60,maxi(20,1000/maxi(1,maxi(str(names[0]).length(),str(names[1]).length()))))
	for face in faces:
		face.red_name.visible=matchup
		face.blue_name.visible=matchup
		if matchup:
			face.red_name.font_size=font_size
			face.blue_name.font_size=font_size
			if face.red_name.text!=str(names[0]): face.red_name.text=str(names[0])
			if face.blue_name.text!=str(names[1]): face.blue_name.text=str(names[1])
		face.coin.visible=showing_coin
		face.label.visible=not showing_coin
		if face.label.text!=text: face.label.text=text
		if showing_coin:
			face.coin.rotation.y=coin_angle
			face.letter.text="H" if coin_side=="heads" else "T"

func _process(delta: float) -> void:
	coin_angle+=delta*TAU*3
	for face in faces: face.coin.rotation.y=coin_angle
