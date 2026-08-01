class_name OneGunStepper
extends HBoxContainer

# Plus/minus stepper with a value readout. The packet locks bot count (and
# similar values) to a stepper, never a slider.

signal value_changed(value: int)

@export var min_value: int = 0
@export var max_value: int = 10
@export var step: int = 1
@export var value: int = 0:
	set(new_value):
		var clamped := clampi(new_value, min_value, max_value)
		if clamped == value:
			return
		value = clamped
		_refresh()
		value_changed.emit(value)

var _minus_button: OneGunButton
var _plus_button: OneGunButton
var _value_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", OneGunUI.SPACE_S)
	alignment = BoxContainer.ALIGNMENT_CENTER

	_minus_button = _make_step_button(OneGunIcon.Kind.MINUS)
	_minus_button.pressed.connect(func() -> void: value -= step)
	add_child(_minus_button)

	_value_label = OneGunUI.make_value_box(str(value), 56.0)
	_value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_value_label)

	_plus_button = _make_step_button(OneGunIcon.Kind.PLUS)
	_plus_button.pressed.connect(func() -> void: value += step)
	add_child(_plus_button)

	_refresh()


func set_range(new_min: int, new_max: int) -> void:
	min_value = new_min
	max_value = new_max
	value = clampi(value, min_value, max_value)
	_refresh()


func _make_step_button(icon_kind: OneGunIcon.Kind) -> OneGunButton:
	var button := OneGunButton.new()
	button.variant = "navy"
	button.custom_minimum_size = Vector2(40.0, 40.0)
	var icon := OneGunIcon.new()
	icon.kind = icon_kind
	icon.icon_color = OneGunUI.color("gold")
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(icon)
	return button


func _refresh() -> void:
	if _value_label == null:
		return
	_value_label.text = str(value)
	_minus_button.disabled = value <= min_value
	_plus_button.disabled = value >= max_value
