class_name OneGunUI
extends Object

# ============================================================
# OneGunUI — static token + style library for the redesigned
# "toy cabinet" menus (docs/design/ONE_GUN_MENU_SYSTEMS_ULTRA_PACKET).
#
# ThemeManager remains the single source of base colors; this
# class centralizes the redesign's spacing, radii, border,
# typography, and animation tokens plus StyleBox builders so
# every component and screen speaks the same visual language.
# ============================================================

const TM := preload("res://theme_manager.gd")

# ---- Animation timings (packet §4 "Shared motion") ----
const TIME_PANEL := 0.22       # panel open/close
const TIME_SLIDEOUT := 0.30    # connected slide-out
const TIME_MAP_FADE := 0.70    # map-preview crossfade
const TIME_CONFIRM_RESET := 5.0
const HOVER_SCALE := 1.015

# ---- Corner radii ----
const RADIUS_CABINET := 22
const RADIUS_SECTION := 14
const RADIUS_BUTTON := 12
const RADIUS_INPUT := 10
const RADIUS_CHIP := 999

# ---- Spacing scale ----
const SPACE_XS := 4
const SPACE_S := 8
const SPACE_M := 12
const SPACE_L := 20
const SPACE_XL := 32

# ---- Border widths ----
const BORDER_THIN := 2
const BORDER_THICK := 3
const CABINET_RIM := 5

# ---- Font sizes ----
const TEXT_XS := 12
const TEXT_S := 14
const TEXT_M := 16
const TEXT_L := 20
const TEXT_XL := 26
const TEXT_TITLE := 34

# Semantic color roles. Every component asks for a role, never a raw color,
# so a palette change stays a one-file edit.
static func color(role: String) -> Color:
	match role:
		"canvas":        return TM.BG_DARK
		"face":          return TM.BG_PANEL
		"face_raised":   return TM.BG_PANEL.lightened(0.055)
		"well":          return TM.BG_INPUT
		"gold":          return TM.ACCENT_GOLD
		"gold_edge":     return TM.GOLD_EDGE
		"cyan":          return TM.ACCENT_CYAN
		"blue":          return TM.INFO_BLUE
		"purple":        return TM.ACCENT_PURPLE
		"green":         return TM.POSITIVE
		"red":           return TM.DANGER
		"text":          return TM.TEXT_CREAM
		"text_bright":   return TM.TEXT_WHITE
		"muted":         return TM.TEXT_DIM
		"border":        return TM.BORDER
		"ink":           return TM.BG_INPUT.darkened(0.35)  # dark text on gold/green
	return Color.WHITE


static func _theme_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("ThemeManager")


static func font_med() -> FontVariation:
	var tm := _theme_manager()
	return tm.font_med if tm != null else null


static func font_bold() -> FontVariation:
	var tm := _theme_manager()
	return tm.font_bold if tm != null else null


static func style_box(
		background: Color,
		border: Color,
		radius: int = RADIUS_BUTTON,
		border_width: int = BORDER_THIN,
		shadow_size: int = 0,
		content_margin: float = 0.0,
		shadow_color: Color = Color(0.0, 0.0, 0.0, 0.34)
	) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = content_margin
	style.content_margin_right = content_margin
	style.content_margin_top = content_margin
	style.content_margin_bottom = content_margin
	if shadow_size > 0:
		style.shadow_color = shadow_color
		style.shadow_size = shadow_size
		style.shadow_offset = Vector2(0.0, float(shadow_size) * 0.45)
	return style


# Recessed content well (inset section of a cabinet face).
static func well_style(radius: int = RADIUS_INPUT) -> StyleBoxFlat:
	var style := style_box(color("well"), color("well").darkened(0.35), radius, BORDER_THIN)
	# Slightly lighter bottom border fakes light catching the recess lip.
	style.border_color = color("well").darkened(0.4)
	return style


# Keyboard/controller focus ring: cyan outline plus soft glow so focus is
# never communicated by color alone (packet §4 interaction states).
static func focus_ring(base: StyleBoxFlat) -> StyleBoxFlat:
	var style := base.duplicate() as StyleBoxFlat
	style.border_color = color("cyan")
	style.set_border_width_all(BORDER_THICK + 1)
	style.shadow_color = Color(color("cyan"), 0.35)
	style.shadow_size = 7
	style.shadow_offset = Vector2.ZERO
	return style


static func make_label(text: String, size: int = TEXT_M, color_role := "text", bold := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color(color_role))
	var font := font_bold() if bold else font_med()
	if font != null:
		label.add_theme_font_override("font", font)
	return label


static func make_heading(text: String, size: int = TEXT_L, color_role := "gold") -> Label:
	var label := make_label(text, size, color_role, true)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


# Small rounded value readout (slider values, stepper counts).
static func make_value_box(text: String, min_width: float = 64.0) -> Label:
	var label := make_label(text, TEXT_M, "text_bright", true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(min_width, 0)
	var style := well_style()
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	label.add_theme_stylebox_override("normal", style)
	return label


static func make_dropdown(items: PackedStringArray = PackedStringArray()) -> OptionButton:
	var dropdown := OptionButton.new()
	for item in items:
		dropdown.add_item(item)
	var normal := style_box(color("well"), color("border"), RADIUS_INPUT, BORDER_THIN, 0, 8.0)
	dropdown.add_theme_stylebox_override("normal", normal)
	dropdown.add_theme_stylebox_override("hover",
		style_box(color("well").lightened(0.06), color("gold"), RADIUS_INPUT, BORDER_THIN, 0, 8.0))
	dropdown.add_theme_stylebox_override("pressed",
		style_box(color("well"), color("gold"), RADIUS_INPUT, BORDER_THICK, 0, 8.0))
	dropdown.add_theme_stylebox_override("focus", focus_ring(normal))
	dropdown.add_theme_stylebox_override("disabled",
		style_box(Color(color("well"), 0.55), color("border").darkened(0.3), RADIUS_INPUT, BORDER_THIN, 0, 8.0))
	dropdown.add_theme_color_override("font_color", color("text"))
	dropdown.add_theme_color_override("font_hover_color", color("gold"))
	dropdown.add_theme_color_override("font_focus_color", color("text_bright"))
	dropdown.add_theme_color_override("font_disabled_color", color("muted"))
	var font := font_bold()
	if font != null:
		dropdown.add_theme_font_override("font", font)
	return dropdown


static func style_checkbox(checkbox: CheckBox) -> CheckBox:
	checkbox.add_theme_color_override("font_color", color("text"))
	checkbox.add_theme_color_override("font_hover_color", color("gold"))
	checkbox.add_theme_color_override("font_focus_color", color("text_bright"))
	checkbox.add_theme_color_override("font_disabled_color", color("muted"))
	checkbox.add_theme_stylebox_override("focus",
		focus_ring(style_box(Color.TRANSPARENT, Color.TRANSPARENT, RADIUS_INPUT, 0)))
	var font := font_med()
	if font != null:
		checkbox.add_theme_font_override("font", font)
	return checkbox


static func make_slider(min_value: float, max_value: float, step: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(160.0, 26.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := style_box(color("well"), color("well").darkened(0.4), 6, 1)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	var fill := style_box(color("gold"), Color.TRANSPARENT, 6, 0)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	return slider


# Chain focus neighbors vertically so keyboard/controller users can walk a
# column of controls without relying on Godot's spatial guessing.
static func chain_focus_vertical(controls: Array) -> void:
	for index in controls.size():
		var control := controls[index] as Control
		if control == null:
			continue
		var prev := controls[wrapi(index - 1, 0, controls.size())] as Control
		var next := controls[wrapi(index + 1, 0, controls.size())] as Control
		control.focus_neighbor_top = control.get_path_to(prev)
		control.focus_neighbor_bottom = control.get_path_to(next)
		control.focus_previous = control.get_path_to(prev)
		control.focus_next = control.get_path_to(next)
