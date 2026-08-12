class_name FlashBlindOverlay
extends ColorRect

# Viewport-scoped flash presentation. Keeping this inside each local HUD (and
# the one online HUD) prevents a flashed splitscreen player from whitening the
# other player's half of the screen.

var player = null
const SOLID_WHITE_TIME := 2.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func set_player(p) -> void:
	player = p
	_update_from_player()

func _process(_delta: float) -> void:
	_update_from_player()

func _update_from_player() -> void:
	if player == null or not ("flash_blind_timer" in player):
		visible = false
		return
	var remaining := float(player.get("flash_blind_timer"))
	visible = remaining > 0.0
	if not visible:
		return
	var total := remaining
	if "_flash_blind_total" in player:
		total = maxf(float(player.get("_flash_blind_total")), remaining)
	var elapsed := maxf(total - remaining, 0.0)
	var alpha := 1.0
	if elapsed > SOLID_WHITE_TIME:
		var fade_duration := maxf(total - SOLID_WHITE_TIME, 0.01)
		alpha = clampf(remaining / fade_duration, 0.0, 1.0)
	color = Color(1.0, 1.0, 1.0, alpha)
