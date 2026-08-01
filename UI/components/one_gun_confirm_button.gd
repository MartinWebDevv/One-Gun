class_name OneGunConfirmButton
extends OneGunButton

# Two-click inline confirmation button (packet locked behavior: destructive
# actions and Force Start never use popups). First press arms the button —
# it turns red and shows confirm_text; a second press within the window
# emits `confirmed`. Arming cancels on Escape, focus/hover leaving, a
# five-second timeout, or an external state change via reset_confirm().
#
# Consumers connect to `confirmed`, not `pressed`.

signal confirmed
signal armed_changed(armed: bool)

@export var confirm_text: String = "CONFIRM"

var _armed := false
var _idle_text := ""
var _idle_variant := "navy"
var _reset_timer: Timer


func _ready() -> void:
	super()
	_idle_text = text
	_idle_variant = variant
	_reset_timer = Timer.new()
	_reset_timer.one_shot = true
	_reset_timer.wait_time = OneGunUI.TIME_CONFIRM_RESET
	_reset_timer.timeout.connect(reset_confirm)
	add_child(_reset_timer)
	pressed.connect(_on_confirm_pressed)
	focus_exited.connect(_on_attention_lost)
	mouse_exited.connect(_on_attention_lost)
	hidden.connect(reset_confirm)


func is_armed() -> bool:
	return _armed


func reset_confirm() -> void:
	if not _armed:
		return
	_armed = false
	_reset_timer.stop()
	text = _idle_text
	variant = _idle_variant
	armed_changed.emit(false)


# Call when external state changes (lobby update, roster change, etc.) —
# the locked behavior requires arming to cancel on any state change.
func notify_state_changed() -> void:
	reset_confirm()


func set_idle(new_text: String, new_variant: String = "") -> void:
	_idle_text = new_text
	if new_variant != "":
		_idle_variant = new_variant
	if not _armed:
		text = _idle_text
		variant = _idle_variant


func _on_confirm_pressed() -> void:
	if _armed:
		reset_confirm()
		confirmed.emit()
		return
	_armed = true
	text = confirm_text
	variant = "red"
	_reset_timer.start()
	armed_changed.emit(true)


func _on_attention_lost() -> void:
	# "Clicking elsewhere" cancels arming; losing both hover and focus is the
	# closest safe equivalent that also covers controller navigation.
	if _armed and not is_hovered() and not has_focus():
		reset_confirm()


func _input(event: InputEvent) -> void:
	if not _armed:
		return
	if event.is_action_pressed("ui_cancel"):
		reset_confirm()
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		if not get_global_rect().has_point(mouse_event.global_position):
			reset_confirm()
