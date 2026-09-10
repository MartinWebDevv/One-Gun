extends CanvasLayer
## A peer-local overlay. Callers must identify their local duel participant.
var veil: ColorRect
var tween: Tween
var generation := 0
func _ready() -> void:
	layer=85
	veil=ColorRect.new()
	veil.color=Color(0.08,0.06,0.11,0)
	veil.mouse_filter=Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	hide()
func reset() -> void:
	generation+=1
	if tween and tween.is_valid(): tween.kill()
	veil.color.a=0.0
	hide()
func fade(alpha: float, for_local_fighter: bool) -> void:
	if not for_local_fighter:
		reset()
		return
	generation+=1
	var expected := generation
	if tween and tween.is_valid(): tween.kill()
	show()
	tween=create_tween()
	tween.tween_property(veil,"color:a",alpha,0.28)
	# Reset can cancel a tween. A bounded wait also releases its awaiting caller.
	await get_tree().create_timer(0.28).timeout
	if expected==generation and alpha<=0.0:
		reset()
