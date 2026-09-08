extends Control
## All views read the same authority timeline and committed result.
var phase := 0.0
var flipping := false
var side := "HEADS"
var font: Font

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	font=load("res://fonts/cinematic/barlow_condensed/BarlowCondensed-ExtraBold.ttf")

func show_coin(active: bool, is_flipping: bool, seconds_left: float, result: String) -> void:
	visible=active
	if not active: return
	flipping=is_flipping
	phase=(2.0-seconds_left)*TAU*3.0 if flipping else 0.0
	side=("HEADS" if cos(phase)>=0 else "TAILS") if flipping else result.to_upper()
	queue_redraw()

func _draw() -> void:
	var center:=size*0.5
	var width:=maxf(0.08,absf(cos(phase))) if flipping else 1.0
	var lift: float=sin(phase*0.5)*9.0 if flipping else 0.0
	draw_circle(center+Vector2(0,74),24,Color(0,0,0,0.18))
	draw_set_transform(center+Vector2(0,lift),0,Vector2(width,1))
	draw_circle(Vector2(4,5),64,Color("916135"))
	draw_circle(Vector2.ZERO,64,Color("ffce69"))
	draw_arc(Vector2.ZERO,56,0,TAU,64,Color("b87b35"),3,true)
	draw_arc(Vector2.ZERO,49,0,TAU,64,Color("fff0b5"),1.5,true)
	var letters: String="H" if side=="HEADS" else "T"
	var bounds:=font.get_string_size(letters,HORIZONTAL_ALIGNMENT_LEFT,-1,54)
	draw_string(font,Vector2(-bounds.x*0.5,10),letters,HORIZONTAL_ALIGNMENT_LEFT,-1,54,Color("674126"))
	var word:=font.get_string_size(side,HORIZONTAL_ALIGNMENT_LEFT,-1,17)
	draw_string(font,Vector2(-word.x*0.5,33),side,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("674126"))
	draw_set_transform(Vector2.ZERO)
