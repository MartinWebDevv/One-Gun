class_name OneGunSliderRow
extends HBoxContainer

# Labeled slider row with optional help tooltip and live value box, matching
# the Player Settings concept rows (label — ? — slider — value).

signal value_changed(value: float)

@export var label_text: String = "Setting"
@export var help_text: String = ""
@export var min_value: float = 0.0
@export var max_value: float = 1.0
@export var step: float = 0.01
@export var value: float = 0.5:
	set(new_value):
		value = clampf(new_value, min_value, max_value)
		if _slider != null and not is_equal_approx(_slider.value, value):
			_slider.set_value_no_signal(value)
		_refresh_value_label()
@export var display_format: String = "%.2f"  # e.g. "%.2f", "%d", "%d%%"
@export var display_scale: float = 1.0      # value multiplier for display (e.g. 100 for percent)
@export var label_min_width: float = 210.0

var _slider: HSlider
var _value_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", OneGunUI.SPACE_M)

	var label := OneGunUI.make_label(label_text, OneGunUI.TEXT_M, "text")
	label.custom_minimum_size = Vector2(label_min_width, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)

	if help_text != "":
		var help := OneGunHelpIcon.new()
		help.tooltip_text = help_text
		help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(help)

	_slider = OneGunUI.make_slider(min_value, max_value, step, value)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.value_changed.connect(_on_slider_changed)
	add_child(_slider)

	_value_label = OneGunUI.make_value_box("", 72.0)
	_value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_value_label)
	_refresh_value_label()


func get_slider() -> HSlider:
	return _slider


func _on_slider_changed(new_value: float) -> void:
	value = new_value
	value_changed.emit(value)


func _refresh_value_label() -> void:
	if _value_label == null:
		return
	var shown := value * display_scale
	if display_format.contains("%d"):
		_value_label.text = display_format % int(roundf(shown))
	else:
		_value_label.text = display_format % shown
