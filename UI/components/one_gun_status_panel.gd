class_name OneGunStatusPanel
extends CenterContainer

# Shared loading / empty / error / unavailable state block (packet Phase 1).
# Lists and async views show this instead of fake rows while they have no
# real data.

signal retry_requested

var _icon: OneGunIcon
var _title_label: Label
var _message_label: Label
var _retry_button: OneGunButton


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 160.0)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", OneGunUI.SPACE_S)
	add_child(column)

	var icon_center := CenterContainer.new()
	_icon = OneGunIcon.new()
	_icon.custom_minimum_size = Vector2(34.0, 34.0)
	icon_center.add_child(_icon)
	column.add_child(icon_center)

	_title_label = OneGunUI.make_label("", OneGunUI.TEXT_L, "text", true)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title_label)

	_message_label = OneGunUI.make_label("", OneGunUI.TEXT_S, "muted")
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.custom_minimum_size = Vector2(320.0, 0.0)
	column.add_child(_message_label)

	var retry_center := CenterContainer.new()
	_retry_button = OneGunButton.new()
	_retry_button.variant = "navy"
	_retry_button.text = "RETRY"
	_retry_button.font_size = OneGunUI.TEXT_S
	_retry_button.pressed.connect(func() -> void: retry_requested.emit())
	retry_center.add_child(_retry_button)
	column.add_child(retry_center)

	show_loading()


func show_loading(message := "Loading…") -> void:
	_apply(OneGunIcon.Kind.SPINNER, OneGunUI.color("cyan"), "", message, false)


func show_empty(title := "NOTHING HERE YET", message := "") -> void:
	_apply(OneGunIcon.Kind.PLAYER, Color(OneGunUI.color("muted"), 0.5), title, message, false)


func show_error(title := "SOMETHING WENT WRONG", message := "", can_retry := true) -> void:
	_apply(OneGunIcon.Kind.WARNING, OneGunUI.color("red"), title, message, can_retry)


func show_unavailable(title := "UNAVAILABLE", message := "") -> void:
	_apply(OneGunIcon.Kind.WARNING, OneGunUI.color("gold"), title, message, false)


func _apply(icon_kind: OneGunIcon.Kind, tone: Color, title: String, message: String,
		can_retry: bool) -> void:
	_icon.kind = icon_kind
	_icon.icon_color = tone
	_title_label.text = title
	_title_label.visible = title != ""
	_message_label.text = message
	_message_label.visible = message != ""
	_retry_button.visible = can_retry
