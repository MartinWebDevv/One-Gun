class_name OneGunTabBar
extends HBoxContainer

# Segmented tab control (Match Settings GENERAL/COMBAT/SPAWNS/PRESETS,
# crosshair Shape/Behavior/Feedback, controls sub-tabs). Selected tab is a
# raised gold segment; unselected tabs are navy.

signal tab_selected(index: int)

@export var tabs: PackedStringArray = PackedStringArray():
	set(value):
		tabs = value
		if is_inside_tree():
			_rebuild()
@export var selected: int = 0:
	set(value):
		selected = clampi(value, 0, maxi(tabs.size() - 1, 0))
		_refresh_selection()

var _buttons: Array[Button] = []
var _group := ButtonGroup.new()


func _ready() -> void:
	add_theme_constant_override("separation", OneGunUI.SPACE_XS)
	_rebuild()


func _rebuild() -> void:
	for button in _buttons:
		button.queue_free()
	_buttons.clear()
	for index in tabs.size():
		var button := Button.new()
		button.text = tabs[index]
		button.toggle_mode = true
		button.button_group = _group
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_entered.connect(func() -> void:
			if not button.disabled:
				AudioManager.play_hover())
		button.pressed.connect(_on_tab_pressed.bind(index))
		_style_tab(button)
		add_child(button)
		_buttons.append(button)
	_refresh_selection()


func _style_tab(button: Button) -> void:
	var radius := OneGunUI.RADIUS_INPUT
	var margin := 12.0
	var idle := OneGunUI.style_box(
		OneGunUI.color("well"), OneGunUI.color("border"), radius, OneGunUI.BORDER_THIN, 0, margin)
	var hover := OneGunUI.style_box(
		OneGunUI.color("face_raised"), OneGunUI.color("gold").darkened(0.2), radius, OneGunUI.BORDER_THIN, 0, margin)
	var active := OneGunUI.style_box(
		OneGunUI.color("gold"), OneGunUI.color("gold").lightened(0.18), radius, OneGunUI.BORDER_THIN, 3, margin)
	button.add_theme_stylebox_override("normal", idle)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_stylebox_override("hover_pressed", active)
	button.add_theme_stylebox_override("focus", OneGunUI.focus_ring(idle))
	button.add_theme_color_override("font_color", OneGunUI.color("muted"))
	button.add_theme_color_override("font_hover_color", OneGunUI.color("text"))
	button.add_theme_color_override("font_pressed_color", OneGunUI.color("ink"))
	button.add_theme_color_override("font_hover_pressed_color", OneGunUI.color("ink"))
	button.add_theme_color_override("font_focus_color", OneGunUI.color("text"))
	button.add_theme_font_size_override("font_size", OneGunUI.TEXT_S)
	var font := OneGunUI.font_bold()
	if font != null:
		button.add_theme_font_override("font", font)


func _on_tab_pressed(index: int) -> void:
	AudioManager.play_click()
	if index == selected:
		_refresh_selection()  # keep the pressed visual in sync
		return
	selected = index
	tab_selected.emit(index)


func _refresh_selection() -> void:
	for index in _buttons.size():
		_buttons[index].set_pressed_no_signal(index == selected)
