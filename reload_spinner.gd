extends Control

# ============================================================
# ReloadSpinner — wraps around the crosshair at screen center.
# Only visible to the gun holder while reloading.
# ============================================================

var player = null

const RADIUS       = 28.0    # just outside the crosshair
const THICKNESS    = 6.0
const SIZE         = (RADIUS + THICKNESS + 2.0) * 2.0
const ARC_SEGMENTS = 64
const COLOR_RELOAD = Color(0.95, 0.75, 0.2, 0.92)   # amber while reloading

func _ready():
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)

	# Centred exactly on the crosshair
	anchor_left   = 0.5
	anchor_right  = 0.5
	anchor_top    = 0.5
	anchor_bottom = 0.5
	offset_left   = -SIZE / 2.0
	offset_right  =  SIZE / 2.0
	offset_top    = -SIZE / 2.0
	offset_bottom =  SIZE / 2.0

func set_player(p):
	player = p

var _was_reloading := false
var _flash := 0.0   # 1 → reload just completed, decays to 0

func _process(delta):
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
	if player == null or not player.holding_gun:
		visible = false
		_was_reloading = false
		return
	var weapon_active = not ("active_slot" in player) or player.active_slot == "weapon"
	if not weapon_active:
		visible = false
		_was_reloading = false
		return
	var hold_point = player.get_hold_point()
	if hold_point.get_child_count() == 0:
		visible = false
		return
	var gun = hold_point.get_child(0)
	var reloading: bool = not gun.can_fire
	# One-shot "ready!" ring flash the instant the reload completes.
	if _was_reloading and not reloading:
		_flash = 1.0
	_was_reloading = reloading
	visible = reloading or _flash > 0.0
	queue_redraw()

func _draw():
	var center = Vector2(SIZE / 2.0, SIZE / 2.0)
	# One-shot completion flash: gold ring that expands and fades.
	if _flash > 0.0:
		var flash_radius = RADIUS + (1.0 - _flash) * 8.0
		draw_arc(center, flash_radius, 0.0, TAU, ARC_SEGMENTS,
			Color(1.0, 0.718, 0.0, _flash * 0.9), THICKNESS, true)
	if player == null or not player.holding_gun:
		return
	var weapon_active = not ("active_slot" in player) or player.active_slot == "weapon"
	if not weapon_active:
		return
	var hold_point = player.get_hold_point()
	if hold_point.get_child_count() == 0:
		return
	var gun = hold_point.get_child(0)
	if gun.can_fire:
		return
	var t = gun.get_reload_progress()

	# Dim background track — full circle so you see the extent
	draw_arc(center, RADIUS, 0.0, TAU, ARC_SEGMENTS, Color(1.0, 1.0, 1.0, 0.15), THICKNESS, true)

	# Foreground arc — fills clockwise from top
	if t > 0.0:
		draw_arc(center, RADIUS, -PI / 2.0, -PI / 2.0 + TAU * t, ARC_SEGMENTS, COLOR_RELOAD, THICKNESS, true)
