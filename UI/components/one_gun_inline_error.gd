class_name OneGunInlineError
extends HBoxContainer

# Inline validation/error message (packet Phase 1/4): warning icon + red
# text under the offending field, announced with a brief restrained shake.
# Never a popup.

var _icon: OneGunIcon
var _label: Label
var _shake_tween: Tween
var _rest_position := Vector2.ZERO


func _ready() -> void:
	visible = false
	add_theme_constant_override("separation", OneGunUI.SPACE_S)
	_icon = OneGunIcon.new()
	_icon.kind = OneGunIcon.Kind.WARNING
	_icon.icon_color = OneGunUI.color("red")
	_icon.custom_minimum_size = Vector2(18.0, 18.0)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_icon)
	_label = OneGunUI.make_label("", OneGunUI.TEXT_S, "red")
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_label)


func show_error(message: String) -> void:
	_label.text = message
	visible = true
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
		position = _rest_position
	_rest_position = position
	_shake_tween = create_tween()
	for offset in [4.0, -3.0, 2.0, 0.0]:
		_shake_tween.tween_property(self, "position:x", _rest_position.x + offset, 0.05)


func clear() -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
		position = _rest_position
	visible = false
	_label.text = ""
