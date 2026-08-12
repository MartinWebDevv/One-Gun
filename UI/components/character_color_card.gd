class_name CharacterColorCard
extends Button

signal color_chosen(skin_id: String)

const SkinRegistry = preload("res://player_skin_registry.gd")
const CHARACTER_PORTRAIT_SCRIPT = preload("res://UI/components/character_portrait.gd")

var skin_id := SkinRegistry.DEFAULT_SKIN_ID
var _portrait = null
var _name_label: Label
var _check_badge: PanelContainer
var _selected := false


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(138.0, 108.0)
	clip_contents = false
	_build_contents()
	_apply_styles()
	pressed.connect(func() -> void: color_chosen.emit(skin_id))


func setup(requested_id: String) -> void:
	skin_id = SkinRegistry.sanitize_skin_id(requested_id)
	if is_inside_tree():
		_refresh_contents()


func set_selected(value: bool) -> void:
	_selected = value
	if is_inside_tree():
		_apply_styles()
		if _check_badge != null:
			_check_badge.visible = value


func _build_contents() -> void:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)

	_portrait = CHARACTER_PORTRAIT_SCRIPT.new()
	_portrait.name = "Portrait"
	_portrait.custom_minimum_size = Vector2(0.0, 74.0)
	_portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_portrait)

	_name_label = OneGunUI.make_label("", OneGunUI.TEXT_XS, "text_bright", true)
	_name_label.name = "ColorName"
	_name_label.custom_minimum_size.y = 24.0
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_name_label)

	_check_badge = PanelContainer.new()
	_check_badge.name = "SelectedBadge"
	_check_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_check_badge.position = Vector2(105.0, 7.0)
	_check_badge.size = Vector2(26.0, 26.0)
	var badge_style := OneGunUI.style_box(
		OneGunUI.color("gold"), OneGunUI.color("gold_edge"), 13, 2, 5)
	_check_badge.add_theme_stylebox_override("panel", badge_style)
	add_child(_check_badge)
	var check := OneGunIcon.new()
	check.kind = OneGunIcon.Kind.CHECK
	check.icon_color = OneGunUI.color("ink")
	check.custom_minimum_size = Vector2(22.0, 22.0)
	_check_badge.add_child(check)

	_refresh_contents()
	_check_badge.visible = _selected


func _refresh_contents() -> void:
	if _portrait != null:
		_portrait.set_skin(skin_id)
	if _name_label != null:
		_name_label.text = SkinRegistry.display_name(skin_id).to_upper()
	tooltip_text = "Preview the %s color" % SkinRegistry.display_name(skin_id)


func _apply_styles() -> void:
	var face := OneGunUI.color("face_raised")
	var border := OneGunUI.color("gold") if _selected else OneGunUI.color("border")
	var border_width := 3 if _selected else 1
	var shadow := 9 if _selected else 3
	var normal := OneGunUI.style_box(face, border, 12, border_width, shadow)
	if _selected:
		normal.shadow_color = Color(OneGunUI.color("gold"), 0.45)
	var hover := OneGunUI.style_box(
		face.lightened(0.08), OneGunUI.color("gold"), 12, 2, 7)
	var pressed_style := OneGunUI.style_box(
		face.darkened(0.12), OneGunUI.color("gold"), 12, 2)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed_style)
	add_theme_stylebox_override("focus", OneGunUI.focus_ring(normal))
