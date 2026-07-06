extends Control

# ============================================================
# ReloadSpinner — wraps around the crosshair at screen center.
# Only visible to the gun holder while reloading.
# ============================================================

var player = null

const RADIUS       = 28.0    # just outside the crosshair
const THICKNESS    = 5.0
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

func _process(_delta):
	if player == null or not player.holding_gun:
		visible = false
		return
	var weapon_active = not ("active_slot" in player) or player.active_slot == "weapon"
	if not weapon_active:
		visible = false
		return
	var hold_point = player.get_hold_point()
	if hold_point.get_child_count() == 0:
		visible = false
		return
	var gun = hold_point.get_child(0)
	visible = not gun.can_fire
	queue_redraw()

func _draw():
	if player == null or not player.holding_gun:
		return
	var weapon_active = not ("active_slot" in player) or player.active_slot == "weapon"
	if not weapon_active:
		return
	var hold_point = player.get_hold_point()
	if hold_point.get_child_count() == 0:
		return
	var gun = hold_point.get_child(0)
	var t = gun.get_reload_progress()
	var center = Vector2(SIZE / 2.0, SIZE / 2.0)

	# Dim background track — full circle so you see the extent
	draw_arc(center, RADIUS, 0.0, TAU, ARC_SEGMENTS, Color(1.0, 1.0, 1.0, 0.15), THICKNESS, true)

	# Foreground arc — fills clockwise from top
	if t > 0.0:
		draw_arc(center, RADIUS, -PI / 2.0, -PI / 2.0 + TAU * t, ARC_SEGMENTS, COLOR_RELOAD, THICKNESS, true)
