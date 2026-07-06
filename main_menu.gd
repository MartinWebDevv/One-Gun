extends Control

# ============================================================
# MainMenu
#
# Two pages:
#   MAIN  — Single Player, Multi-Player, Player Settings
#   MULTI — Online (dead), Local, Player Settings, Back
#
# Player Settings button always visible on both pages.
#
# Animations:
#   - Title "ONE GUN" drops in with bounce, then pulses gold glow
#   - Buttons stagger fade+slide in from below on page load
#   - Page transitions fade out → fade in
#   - Button hover: scale pop + color shift
# ============================================================

enum Page { MAIN, MULTI }

const FONT_PATH  = "res://fonts/Fredoka-VariableFont_wdth,wght.ttf"

# Palette
const COL_BG          = Color(0.102, 0.122, 0.180)
const COL_PANEL       = Color(0.137, 0.157, 0.271, 0.85)
const COL_GOLD        = Color(1.000, 0.718, 0.000)
const COL_GOLD_DIM    = Color(1.000, 0.718, 0.000, 0.0)
const COL_CYAN        = Color(0.000, 0.898, 1.000)
const COL_WHITE       = Color(1.000, 1.000, 1.000)
const COL_DISABLED    = Color(0.5, 0.5, 0.5, 0.5)
const COL_TRANSPARENT = Color(1, 1, 1, 0)

# Animation timings
const TITLE_DROP_DURATION   = 0.55
const TITLE_BOUNCE_OVERSHOOT = 1.08
const GLOW_PULSE_DURATION   = 1.8
const BTN_STAGGER_DELAY     = 0.08
const BTN_SLIDE_DURATION    = 0.3
const PAGE_FADE_DURATION    = 0.25
const HOVER_SCALE           = 1.06
const HOVER_DURATION        = 0.1

var _current_page : Page = Page.MAIN
var _font         : Font  = null

# Node references — built entirely in code, no .tscn dependencies for UI
var _root_canvas    : CanvasLayer
var _bg_viewport_c  : SubViewportContainer
var _bg_viewport    : SubViewport
var _overlay        : ColorRect
var _title_label    : Label
var _title_glow     : Label   # duplicate label for glow effect
var _page_main      : Control
var _page_multi     : Control
var _glow_tween     : Tween
var _btn_font       : FontVariation

func _ready():
	_load_font()
	_build_ui()
	AudioManager.play_music("menu")
	call_deferred("_reposition_buttons")
	call_deferred("_animate_entrance")

# ============================================================
# Font
# ============================================================

func _load_font():
	if ResourceLoader.exists(FONT_PATH):
		var base = load(FONT_PATH)
		_btn_font = FontVariation.new()
		_btn_font.base_font = base
		_btn_font.variation_opentype = {"wght": 700}

# ============================================================
# UI Construction
# ============================================================

func _build_ui():
	# Root fills screen
	anchor_right  = 1.0
	anchor_bottom = 1.0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# -- Background SubViewport --
	_bg_viewport_c = SubViewportContainer.new()
	_bg_viewport_c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_viewport_c.stretch = true
	add_child(_bg_viewport_c)

	_bg_viewport = SubViewport.new()
	_bg_viewport.size = Vector2(1920, 1080)
	_bg_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_bg_viewport_c.add_child(_bg_viewport)

	# Load the map + background script into the SubViewport
	var map_scene_path = "res://maps/test/title_bg_map.tscn"
	if ResourceLoader.exists(map_scene_path):
		var map = load(map_scene_path).instantiate()
		_bg_viewport.add_child(map)

	# Camera + background controller
	var bg_cam = Camera3D.new()
	bg_cam.name = "TitleCamera"
	bg_cam.fov  = 60.0
	_bg_viewport.add_child(bg_cam)

	# Attach pan script inline via a simple node
	var pan_node = Node.new()
	pan_node.set_script(_make_pan_script())
	pan_node.set_meta("camera", bg_cam)
	_bg_viewport.add_child(pan_node)

	# -- Dark overlay for readability --
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0.05, 0.07, 0.12, 0.55)
	add_child(_overlay)

	# -- Title --
	_build_title()

	# -- Pages --
	_page_main  = _build_page_main()
	_page_multi = _build_page_multi()
	add_child(_page_main)
	add_child(_page_multi)
	_page_multi.modulate.a = 0.0
	_page_multi.visible = false
	_page_main.visible = true

func _make_pan_script() -> GDScript:
	# Inline camera pan script attached at runtime
	var s = GDScript.new()
	s.source_code = """
extends Node
const SPEED = 0.035
const DIST  = 16.0
const H     = 4.0
const MIN_A = -0.35
const MAX_A = 0.35
var angle = 0.0
var dir   = 1.0
var cam : Camera3D = null
func _ready():
	cam = get_meta("camera") if has_meta("camera") else null
	if cam == null:
		for c in get_parent().get_children():
			if c is Camera3D:
				cam = c
				break
func _process(delta):
	if cam == null:
		return
	angle += SPEED * dir * delta
	if angle > MAX_A:
		angle = MAX_A
		dir = -1.0
	elif angle < MIN_A:
		angle = MIN_A
		dir = 1.0
	cam.global_position = Vector3(sin(angle)*DIST, H, cos(angle)*DIST)
	cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)
"""
	s.reload()
	return s

func _build_title():
	# Glow layer (slightly larger, gold, blurred by modulate)
	_title_glow = Label.new()
	_title_glow.text = "ONE GUN"
	_title_glow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_glow.anchor_left   = 0.0
	_title_glow.anchor_right  = 0.0
	_title_glow.anchor_top    = 0.0
	_title_glow.anchor_bottom = 0.0
	_title_glow.offset_left   = 60
	_title_glow.offset_right  = 700
	_title_glow.offset_top    = 60
	_title_glow.offset_bottom = 220
	if _btn_font:
		_title_glow.add_theme_font_override("font", _btn_font)
	_title_glow.add_theme_font_size_override("font_size", 115)
	_title_glow.add_theme_color_override("font_color", COL_GOLD)
	_title_glow.modulate = COL_GOLD_DIM
	add_child(_title_glow)

	_title_label = Label.new()
	_title_label.text = "ONE GUN"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.anchor_left   = 0.0
	_title_label.anchor_right  = 0.0
	_title_label.anchor_top    = 0.0
	_title_label.anchor_bottom = 0.0
	_title_label.offset_left   = 60
	_title_label.offset_right  = 700
	_title_label.offset_top    = 60
	_title_label.offset_bottom = 220
	if _btn_font:
		_title_label.add_theme_font_override("font", _btn_font)
	_title_label.add_theme_font_size_override("font_size", 110)
	_title_label.add_theme_color_override("font_color", COL_GOLD)
	_title_label.modulate = COL_TRANSPARENT
	_title_label.pivot_offset = Vector2(320, 80)
	add_child(_title_label)

func _build_page_main() -> Control:
	var page = _make_page_container()
	var vbox = page.get_meta("vbox") as VBoxContainer

	var btns = [
		_make_button("Single Player", _on_single_pressed),
		_make_button("Multi-Player",  _on_multiplayer_pressed),
		_make_button("Player Settings", _on_player_settings_pressed),
	]
	for b in btns:
		vbox.add_child(b)

	return page

func _build_page_multi() -> Control:
	var page = _make_page_container()
	var vbox = page.get_meta("vbox") as VBoxContainer

	var online_btn = _make_button("Online", _on_online_pressed)
	online_btn.disabled = true
	online_btn.modulate = COL_DISABLED
	online_btn.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN

	var btns = [
		online_btn,
		_make_button("Local",           _on_local_pressed),
		_make_button("Player Settings", _on_player_settings_pressed),
		_make_button("← Back",         _on_back_pressed),
	]
	for b in btns:
		vbox.add_child(b)

	return page

func _make_page_container() -> Control:
	var page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox = VBoxContainer.new()
	vbox.position = Vector2(60.0, 240.0)
	vbox.size = Vector2(340.0, 400.0)
	vbox.add_theme_constant_override("separation", 14)
	page.add_child(vbox)

	page.set_meta("vbox", vbox)
	return page

func _make_button(label_text: String, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(320, 52)
	btn.flat = false

	if _btn_font:
		btn.add_theme_font_override("font", _btn_font)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color",          COL_WHITE)
	btn.add_theme_color_override("font_hover_color",    COL_GOLD)
	btn.add_theme_color_override("font_pressed_color",  COL_CYAN)
	btn.add_theme_color_override("font_focus_color",    COL_WHITE)
	btn.add_theme_stylebox_override("normal",   _make_btn_style(COL_PANEL, Color(0,0,0,0)))
	btn.add_theme_stylebox_override("hover",    _make_btn_style(Color(0.18, 0.21, 0.38, 0.95), COL_GOLD))
	btn.add_theme_stylebox_override("pressed",  _make_btn_style(Color(0.10, 0.13, 0.25, 0.95), COL_CYAN))
	btn.add_theme_stylebox_override("focus",    _make_btn_style(COL_PANEL, Color(0,0,0,0)))
	btn.add_theme_stylebox_override("disabled", _make_btn_style(Color(0.1,0.1,0.15,0.4), Color(0,0,0,0)))

	btn.pressed.connect(callback)
	btn.mouse_entered.connect(_on_btn_hover.bind(btn))
	btn.mouse_exited.connect(_on_btn_unhover.bind(btn))

	# Start invisible for stagger animation
	btn.modulate = COL_WHITE
	# btn.position.y += 30  # re-enable after confirming visibility

	return btn

func _make_btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color            = bg
	s.border_color        = border
	s.border_width_left   = 2
	s.border_width_right  = 2
	s.border_width_top    = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left     = 8
	s.corner_radius_top_right    = 8
	s.corner_radius_bottom_left  = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left   = 16
	s.content_margin_right  = 16
	s.content_margin_top    = 10
	s.content_margin_bottom = 10
	return s

# ============================================================
# Entrance Animation
# ============================================================

func _reposition_buttons():
	# Place buttons below the title on the left side.
	# Title bottom is around y=220, so start buttons at y=240.
	for page in [_page_main, _page_multi]:
		var vbox = page.get_meta("vbox") as VBoxContainer
		if vbox == null:
			continue
		vbox.position = Vector2(60.0, 240.0)
		vbox.size = Vector2(340.0, 400.0)

func _animate_entrance():
	# Title drops from above with bounce
	_title_label.modulate = COL_TRANSPARENT
	_title_label.scale    = Vector2(0.7, 0.7)

	var t = create_tween().set_parallel(false)
	t.tween_property(_title_label, "modulate", COL_WHITE, 0.2)
	t.parallel().tween_property(_title_label, "scale", Vector2(TITLE_BOUNCE_OVERSHOOT, TITLE_BOUNCE_OVERSHOOT), TITLE_DROP_DURATION * 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(_title_label, "scale", Vector2(1.0, 1.0), TITLE_DROP_DURATION * 0.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_callback(_start_glow_pulse)
	t.tween_callback(_stagger_page_buttons.bind(_page_main))

func _start_glow_pulse():
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_property(_title_glow, "modulate", Color(1.0, 0.718, 0.0, 0.45), GLOW_PULSE_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_glow_tween.tween_property(_title_glow, "modulate", Color(1.0, 0.718, 0.0, 0.0),  GLOW_PULSE_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _stagger_page_buttons(page: Control):
	# Animation stripped for debugging — just ensure all buttons are visible
	var vbox = page.get_meta("vbox") as VBoxContainer
	if vbox == null:
		return
	for child in vbox.get_children():
		child.modulate = COL_WHITE

# ============================================================
# Page Transitions
# ============================================================

func _transition_to(from_page: Control, next_page: Control):
	# Immediately hide all pages then show only the target
	_page_main.visible = false
	_page_multi.visible = false

	# Fade in next page
	next_page.modulate.a = 0.0
	next_page.visible = true
	_reset_page_buttons(next_page)
	_stagger_page_buttons(next_page)

	var t_in = create_tween()
	t_in.tween_property(next_page, "modulate:a", 1.0, PAGE_FADE_DURATION)

func _reset_page_buttons(page: Control):
	var vbox = page.get_meta("vbox") as VBoxContainer
	if vbox == null:
		return
	for child in vbox.get_children():
		if child is Button and not child.disabled:
			child.modulate = COL_TRANSPARENT
			child.position.y += 30

# ============================================================
# Button Hover
# ============================================================

func _on_btn_hover(btn: Button):
	if btn.disabled:
		return
	AudioManager.play_hover()
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(btn, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_DURATION).set_ease(Tween.EASE_OUT)
	btn.pivot_offset = btn.size / 2.0

func _on_btn_unhover(btn: Button):
	if btn.disabled:
		return
	var t = create_tween()
	t.tween_property(btn, "scale", Vector2(1.0, 1.0), HOVER_DURATION).set_ease(Tween.EASE_OUT)

# ============================================================
# Button Callbacks
# ============================================================

func _on_single_pressed():
	AudioManager.play_click()
	if not GameConfig.lobby_settings_dirty:
		GameConfig.reset_match_settings_to_defaults()
	GameConfig.split_screen_enabled = false
	get_tree().change_scene_to_file("res://game_setup.tscn")

func _on_multiplayer_pressed():
	AudioManager.play_click()
	_current_page = Page.MULTI
	_transition_to(_page_main, _page_multi)

func _on_online_pressed():
	# Dead button — disabled, does nothing
	pass

func _on_local_pressed():
	AudioManager.play_click()
	if not GameConfig.lobby_settings_dirty:
		GameConfig.reset_match_settings_to_defaults()
	GameConfig.split_screen_enabled = true
	get_tree().change_scene_to_file("res://game_setup.tscn")

func _on_player_settings_pressed():
	AudioManager.play_click()
	get_tree().change_scene_to_file("res://player_settings.tscn")

func _on_back_pressed():
	AudioManager.play_click()
	_current_page = Page.MAIN
	_transition_to(_page_multi, _page_main)
