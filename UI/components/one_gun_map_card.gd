class_name OneGunMapCard
extends Button

# Map thumbnail card for the bottom carousel (packet Phase 1/2). Shows a
# thumbnail (or a tinted placeholder until map thumbnails exist) with a name
# plate. Selected state is a warm gold glow frame per the concept.

signal card_selected(map_index: int)

var map_index := -1
var map_name := ""

var _thumb: TextureRect
var _placeholder: ColorRect
var _placeholder_label: Label
var _name_label: Label


func _ready() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(168.0, 112.0)
	clip_contents = true
	_refresh_style()
	toggled.connect(func(_on: bool) -> void: _refresh_style())
	mouse_entered.connect(func() -> void:
		if not disabled:
			AudioManager.play_hover())
	pressed.connect(func() -> void:
		AudioManager.play_click()
		card_selected.emit(map_index))
	focus_entered.connect(_refresh_style)
	focus_exited.connect(_refresh_style)

	var layout := VBoxContainer.new()
	# Inset the content so the selection border/glow stays visible around it.
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 3
	layout.offset_top = 3
	layout.offset_right = -3
	layout.offset_bottom = -3
	layout.add_theme_constant_override("separation", 0)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)

	_placeholder = ColorRect.new()
	_placeholder.color = OneGunUI.color("face")
	_placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_placeholder)
	var placeholder_center := CenterContainer.new()
	placeholder_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	placeholder_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.add_child(placeholder_center)
	_placeholder_label = OneGunUI.make_heading("", OneGunUI.TEXT_XL, "text_bright")
	_placeholder_label.modulate = Color(1.0, 1.0, 1.0, 0.58)
	placeholder_center.add_child(_placeholder_label)

	_thumb = TextureRect.new()
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_thumb.visible = false
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_thumb)

	var plate := PanelContainer.new()
	var plate_style := OneGunUI.style_box(Color(0.03, 0.04, 0.08, 0.88), Color.TRANSPARENT, 0, 0)
	plate_style.content_margin_left = 8
	plate_style.content_margin_right = 8
	plate_style.content_margin_top = 4
	plate_style.content_margin_bottom = 5
	plate.add_theme_stylebox_override("panel", plate_style)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = OneGunUI.make_label("", OneGunUI.TEXT_XS - 1, "text", true)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	plate.add_child(_name_label)
	layout.add_child(plate)


# Programmatic selection (map carousel state). button_pressed assignment does
# not emit `toggled`, so the visual refresh must be explicit.
func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)
	_refresh_style()


func set_map(index: int, name_text: String, thumbnail: Texture2D = null,
		placeholder_tint: Color = Color(0.2, 0.3, 0.25)) -> void:
	map_index = index
	map_name = name_text
	_name_label.text = name_text.to_upper()
	var initials := ""
	for word in name_text.split(" ", false):
		if not word.is_empty() and word != "&":
			initials += word.left(1).to_upper()
	_placeholder_label.text = initials.left(3)
	if thumbnail != null:
		_thumb.texture = thumbnail
		_thumb.visible = true
		_placeholder.visible = false
		tooltip_text = "Live preview: %s" % name_text
	else:
		_placeholder.color = placeholder_tint
		_thumb.visible = false
		_placeholder.visible = true
		tooltip_text = "Select %s to load its live preview." % name_text


func _refresh_style() -> void:
	var border := OneGunUI.color("border")
	var width := 1
	var shadow := 0
	var shadow_color := Color(0.0, 0.0, 0.0, 0.34)
	if button_pressed:
		border = OneGunUI.color("gold")
		width = OneGunUI.BORDER_THICK
		shadow = 8
		shadow_color = Color(OneGunUI.color("gold"), 0.4)
	var style := OneGunUI.style_box(Color.TRANSPARENT, border, OneGunUI.RADIUS_INPUT, width, shadow, 0.0, shadow_color)
	for state in ["normal", "hover", "pressed"]:
		add_theme_stylebox_override(state, style)
	add_theme_stylebox_override("focus", OneGunUI.focus_ring(style))
	add_theme_stylebox_override("disabled",
		OneGunUI.style_box(Color(0, 0, 0, 0.4), border.darkened(0.3), OneGunUI.RADIUS_INPUT, 1))
