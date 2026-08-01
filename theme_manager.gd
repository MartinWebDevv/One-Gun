extends Node

# ============================================================
# ThemeManager — autoload.
# Builds and applies the One Gun cartoon theme globally.
# Every scene that uses standard Control nodes picks this up
# automatically once set as the project default theme.
#
# Palette:
#   BG_DARK      Deep navy       #1A1F2E — panel backgrounds
#   BG_PANEL     Semi-dark navy  #232845 — card/section backgrounds
#   ACCENT_GOLD  Yellow-orange   #FFB700 — primary highlight, scores
#   ACCENT_CYAN  Electric cyan   #00E5FF — secondary, notifications
#   DANGER       Coral red       #FF4B4B — death, danger
#   POSITIVE     Lime green      #7AFF6E — alive, ready
#   TEXT_WHITE   White           #FFFFFF — general text
#   TEXT_DIM     Muted lavender  #9BA3C2 — secondary text
# ============================================================

const BG_DARK    = Color(0.102, 0.122, 0.180)
const BG_PANEL   = Color(0.137, 0.157, 0.271)
const BG_INPUT   = Color(0.082, 0.098, 0.157)
const ACCENT_GOLD  = Color(1.000, 0.718, 0.000)
const ACCENT_CYAN  = Color(0.000, 0.898, 1.000)
const DANGER       = Color(1.000, 0.294, 0.294)
const POSITIVE     = Color(0.478, 1.000, 0.431)
const TEXT_WHITE   = Color(1.000, 1.000, 1.000)
const TEXT_DIM     = Color(0.608, 0.639, 0.761)
const BORDER       = Color(0.200, 0.220, 0.380)

# Menu-redesign semantic colors (docs/design/menu_redesign concepts).
const ACCENT_PURPLE = Color(0.541, 0.310, 0.847)  # secondary selection / Player Settings
const INFO_BLUE     = Color(0.180, 0.435, 0.816)  # informational / network states
const TEXT_CREAM    = Color(0.953, 0.914, 0.812)  # primary text on cabinet faces
const GOLD_EDGE     = Color(0.478, 0.322, 0.000)  # dark edge of layered gold rims

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
	font_bold = FontVariation.new()
	font_bold.base_font = base
	font_bold.variation_opentype = {"wght": 700}

func _build_theme() -> Theme:
	var t = Theme.new()

	if font_med != null:
		t.default_font = font_med
	t.default_font_size = 15

	# ---- Label ----
	t.set_color("font_color",        "Label", TEXT_WHITE)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.4))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)

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

static func gold()     -> Color: return Color(1.000, 0.718, 0.000)
static func cyan()     -> Color: return Color(0.000, 0.898, 1.000)
static func danger()   -> Color: return Color(1.000, 0.294, 0.294)
static func positive() -> Color: return Color(0.478, 1.000, 0.431)
static func dim()      -> Color: return Color(0.608, 0.639, 0.761)

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
