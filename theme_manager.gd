extends Node

# ============================================================
# ThemeManager — autoload.
# Builds and applies the One Gun cartoon theme globally.
# Every scene that uses standard Control nodes picks this up
# automatically once set as the project default theme.
#
# Shared Hideout / frontend palette: plum, violet, apricot, ivory and mint.
# Legacy semantic names remain API-compatible for existing UI callers.
# ============================================================

const BG_DARK = Color("292236")
const BG_PANEL = Color("352c49")
const BG_INPUT = Color("2c243c")
const ACCENT_GOLD = Color("f3aa7c")
const ACCENT_CYAN = Color("9bcbb3")
const DANGER = Color("ed827e")
const POSITIVE = Color("9bcbb3")
const TEXT_WHITE = Color("f4e5d2")
const TEXT_DIM = Color("c3b6cc")
const BORDER = Color("705b87")

# Menu-redesign semantic colors (docs/design/menu_redesign concepts).
const ACCENT_PURPLE = Color("705b87")
const INFO_BLUE = Color("b3a1d2")
const TEXT_CREAM = Color("f4e5d2")
const GOLD_EDGE = Color("705b87")

var game_theme: Theme = null

# Font weights built from the Fredoka VARIABLE font (the old code looked for
# Fredoka-Bold.ttf, which doesn't exist — so no custom weighting ever loaded).
var font_med: FontVariation = null    # wght 500 — body/UI default
var font_bold: FontVariation = null   # wght 700 — headings, values, names

const FONT_PATH := "res://fonts/Fredoka-VariableFont_wdth,wght.ttf"

func _ready():
	_build_fonts()
	game_theme = _build_theme()
	# Packaged builds only need the in-memory theme; res:// is commonly read-only.
	if Engine.is_editor_hint():
		var err = ResourceSaver.save(game_theme, "res://one_gun_theme.tres")
		if err != OK:
			push_warning("ThemeManager: could not save generated theme: " + str(err))

func _build_fonts():
	if not ResourceLoader.exists(FONT_PATH):
		push_warning("ThemeManager: font not found: " + FONT_PATH)
		return
	var base: Font = load(FONT_PATH)
	font_med = FontVariation.new()
	font_med.base_font = base
	font_med.variation_opentype = {"wght": 500}
	font_med.variation_embolden = 0.3
	font_bold = FontVariation.new()
	font_bold.base_font = preload("res://fonts/cinematic/barlow_condensed/BarlowCondensed-ExtraBold.ttf")
	font_bold.variation_opentype = {"wght": 700}

func _build_theme() -> Theme:
	var t = Theme.new()

	if font_med != null:
		t.default_font = font_med
	t.default_font_size = 15

	# ---- Label ----
	t.set_color("font_color",        "Label", TEXT_WHITE)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.4))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 0)

	# ---- Button ---- (chunky playful-arcade: bigger radius, brighter hover)
	var btn_normal   = _make_stylebox_flat(BG_PANEL,                  BORDER,      10, 2)
	var btn_hover    = _make_stylebox_flat(BG_PANEL.lightened(0.18),  ACCENT_GOLD, 10, 2)
	var btn_pressed  = _make_stylebox_flat(ACCENT_GOLD.darkened(0.2), ACCENT_GOLD, 10, 2)
	var btn_focus    = _make_stylebox_flat(BG_PANEL,                  ACCENT_CYAN, 10, 2)
	var btn_disabled = _make_stylebox_flat(BG_DARK.darkened(0.1),     BORDER,      10, 1)

	t.set_stylebox("normal",   "Button", btn_normal)
	t.set_stylebox("hover",    "Button", btn_hover)
	t.set_stylebox("pressed",  "Button", btn_pressed)
	t.set_stylebox("focus",    "Button", btn_focus)
	t.set_stylebox("disabled", "Button", btn_disabled)

	t.set_color("font_color",          "Button", TEXT_WHITE)
	t.set_color("font_hover_color",    "Button", ACCENT_GOLD)
	t.set_color("font_pressed_color",  "Button", BG_DARK)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_color("font_focus_color",    "Button", ACCENT_CYAN)

	# ---- PanelContainer ----
	t.set_stylebox("panel", "PanelContainer", _make_stylebox_flat(BG_PANEL, BORDER, 8, 1))

	# ---- CheckBox ----
	t.set_color("font_color",       "CheckBox", TEXT_WHITE)
	t.set_color("font_hover_color", "CheckBox", ACCENT_GOLD)

	# ---- OptionButton ----
	t.set_stylebox("normal",  "OptionButton", btn_normal)
	t.set_stylebox("hover",   "OptionButton", btn_hover)
	t.set_stylebox("pressed", "OptionButton", btn_pressed)
	t.set_stylebox("focus",   "OptionButton", btn_focus)
	t.set_color("font_color",       "OptionButton", TEXT_WHITE)
	t.set_color("font_hover_color", "OptionButton", ACCENT_GOLD)

	# ---- PopupMenu (dropdown) ----
	t.set_stylebox("panel", "PopupMenu", _make_stylebox_flat(BG_PANEL, BORDER, 6, 1))
	t.set_stylebox("hover", "PopupMenu", _make_stylebox_flat(ACCENT_GOLD.darkened(0.3), ACCENT_GOLD, 4, 1))
	t.set_color("font_color",       "PopupMenu", TEXT_WHITE)
	t.set_color("font_hover_color", "PopupMenu", ACCENT_GOLD)

	# ---- LineEdit ----
	var lineedit_normal = _make_stylebox_flat(BG_INPUT, BORDER,      6, 1)
	var lineedit_focus  = _make_stylebox_flat(BG_INPUT, ACCENT_CYAN, 6, 2)
	t.set_stylebox("normal", "LineEdit", lineedit_normal)
	t.set_stylebox("focus",  "LineEdit", lineedit_focus)
	t.set_color("font_color",             "LineEdit", TEXT_WHITE)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color",            "LineEdit", ACCENT_GOLD)
	t.set_color("selection_color",        "LineEdit", ACCENT_GOLD.darkened(0.3))

	# ---- SpinBox ----
	t.set_stylebox("normal", "SpinBox", lineedit_normal)
	t.set_stylebox("focus",  "SpinBox", lineedit_focus)
	t.set_color("font_color", "SpinBox", TEXT_WHITE)

	# ---- HSlider ----
	t.set_stylebox("slider",        "HSlider", _make_stylebox_flat(BG_INPUT,    BORDER,             4, 1))
	t.set_stylebox("grabber_area",  "HSlider", _make_stylebox_flat(ACCENT_GOLD, Color.TRANSPARENT,  4, 0))

	# ---- ScrollContainer ----
	t.set_stylebox("panel", "ScrollContainer", _make_stylebox_flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))

	# ---- HSeparator ----
	var sep_style = StyleBoxLine.new()
	sep_style.color = BORDER
	sep_style.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep_style)

	# ---- ProgressBar ----
	t.set_stylebox("background", "ProgressBar", _make_stylebox_flat(BG_INPUT,    BORDER,             4, 1))
	t.set_stylebox("fill",       "ProgressBar", _make_stylebox_flat(ACCENT_GOLD, Color.TRANSPARENT,  4, 0))
	t.set_color("font_color", "ProgressBar", TEXT_WHITE)

	# ---- AcceptDialog / ConfirmationDialog ----
	t.set_stylebox("panel", "AcceptDialog", _make_stylebox_flat(BG_PANEL, BORDER, 8, 2))

	return t

func _make_stylebox_flat(bg: Color, border: Color, corner_radius: int, border_width: int) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left   = border_width
	s.border_width_right  = border_width
	s.border_width_top    = border_width
	s.border_width_bottom = border_width
	s.corner_radius_top_left     = corner_radius
	s.corner_radius_top_right    = corner_radius
	s.corner_radius_bottom_left  = corner_radius
	s.corner_radius_bottom_right = corner_radius
	s.content_margin_left   = 10
	s.content_margin_right  = 10
	s.content_margin_top    = 6
	s.content_margin_bottom = 6
	return s

static func gold() -> Color: return ACCENT_GOLD
static func cyan() -> Color: return ACCENT_CYAN
static func danger() -> Color: return DANGER
static func positive() -> Color: return POSITIVE
static func dim() -> Color: return TEXT_DIM

# ============================================================
# UI kit — the shared building blocks every HUD widget and menu
# uses so the whole game speaks one visual language.
# ============================================================

# Chunky rounded panel with a soft drop shadow.
func panel(bg: Color, border_col: Color, radius: int = 10, border_w: int = 2) -> StyleBoxFlat:
	var s = _make_stylebox_flat(bg, border_col, radius, border_w)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 2)
	return s

# Fully-rounded pill (feed entries, status chips, weapon readouts).
func pill(bg: Color, border_col: Color = Color.TRANSPARENT, border_w: int = 0) -> StyleBoxFlat:
	var s = _make_stylebox_flat(bg, border_col, 999, border_w)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

# Bold heading label with shadow, in the accent color.
func heading(text: String, size: int, color: Color = ACCENT_GOLD) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font_bold != null:
		l.add_theme_font_override("font", font_bold)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

# Make an existing label bold (values, names).
func embolden(l: Label) -> Label:
	if font_bold != null:
		l.add_theme_font_override("font", font_bold)
	return l

# The standard "pop" — scale-punch from the node's center. All HUD juice goes
# through this so motion feels consistent everywhere.
func punch(node: CanvasItem, amount: float = 1.25, dur: float = 0.18) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node is Control:
		node.pivot_offset = node.size * 0.5
	node.scale = Vector2.ONE * amount
	var tw = node.create_tween()
	tw.tween_property(node, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# The standard blink — modulate flash to a color and back.
func flash(node: CanvasItem, color: Color, dur: float = 0.25) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var accessibility = get_node_or_null("/root/AccessibilityManager")
	if accessibility != null and not accessibility.allow_flash(): return
	node.modulate = color
	var tw = node.create_tween()
	tw.tween_property(node, "modulate", Color.WHITE, dur)
