extends Control

const ONLINE_PLAY_OVERLAY_SCRIPT = preload("res://UI/online_play_overlay.gd")

# Main-menu presentation only. Gameplay, lobby, and networking behavior remains
# delegated to the existing GameConfig and NetworkManager entry points below.

enum MenuIconKind { PLAY, NETWORK, SETTINGS, EXIT }


# Code-drawn icons stay crisp at every target resolution and avoid platform-
# dependent emoji rendering. They intentionally use simple toy-signage shapes.
class MenuButtonIcon:
	extends Control

	var kind := MenuIconKind.PLAY
	var icon_color := Color(1.0, 0.97, 0.90)
	var cutout_color := Color(0.12, 0.14, 0.24)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center := size * 0.5
		match kind:
			MenuIconKind.PLAY:
				_draw_play(center)
			MenuIconKind.NETWORK:
				_draw_network(center)
			MenuIconKind.SETTINGS:
				_draw_settings(center)
			MenuIconKind.EXIT:
				_draw_exit(center)

	func _draw_play(center: Vector2) -> void:
		var points := PackedVector2Array([
			center + Vector2(-8.0, -13.0),
			center + Vector2(13.0, 0.0),
			center + Vector2(-8.0, 13.0),
		])
		draw_colored_polygon(points, icon_color)

	func _draw_network(center: Vector2) -> void:
		draw_arc(center, 14.0, 0.0, TAU, 48, icon_color, 2.5, true)
		draw_polyline(_ellipse_points(center, Vector2(6.0, 14.0)), icon_color, 2.0, true)
		draw_line(center + Vector2(-13.0, -5.0), center + Vector2(13.0, -5.0), icon_color, 2.0, true)
		draw_line(center + Vector2(-13.0, 5.0), center + Vector2(13.0, 5.0), icon_color, 2.0, true)

	func _draw_settings(center: Vector2) -> void:
		for index in 8:
			var direction := Vector2.RIGHT.rotated(TAU * float(index) / 8.0)
			draw_line(center + direction * 9.0, center + direction * 14.0, icon_color, 4.0, true)
		draw_circle(center, 10.5, icon_color)
		draw_circle(center, 4.0, cutout_color)

	func _draw_exit(center: Vector2) -> void:
		var door := Rect2(center + Vector2(-13.0, -14.0), Vector2(16.0, 28.0))
		draw_rect(door, icon_color, false, 2.5, true)
		draw_circle(center + Vector2(-1.5, 3.0), 1.6, icon_color)
		draw_line(center + Vector2(-3.0, 0.0), center + Vector2(14.0, 0.0), icon_color, 3.0, true)
		var arrow := PackedVector2Array([
			center + Vector2(14.0, 0.0),
			center + Vector2(7.0, -6.0),
			center + Vector2(7.0, 6.0),
		])
		draw_colored_polygon(arrow, icon_color)

	func _ellipse_points(center: Vector2, radii: Vector2) -> PackedVector2Array:
		var points := PackedVector2Array()
		for index in 33:
			var angle := TAU * float(index) / 32.0
			points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
		return points


# Section 10 portrait placeholder. The project has no authored 2D profile
# portrait yet, so this small code-drawn cat keeps the footer composition
# asset-independent. Replace this node's contents when profile portraits land.
class LocalProfilePortrait:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var scale_factor := minf(size.x, size.y) / 48.0
		var center := size * 0.5
		var navy := Color(0.07, 0.09, 0.17)
		var cream := Color(0.94, 0.83, 0.62)
		var gold := Color(0.95, 0.65, 0.20)
		var cheek := Color(0.84, 0.42, 0.38)
		var left_ear := PackedVector2Array([
			center + Vector2(-14.0, -7.0) * scale_factor,
			center + Vector2(-11.0, -19.0) * scale_factor,
			center + Vector2(-3.0, -11.0) * scale_factor,
		])
		var right_ear := PackedVector2Array([
			center + Vector2(14.0, -7.0) * scale_factor,
			center + Vector2(11.0, -19.0) * scale_factor,
			center + Vector2(3.0, -11.0) * scale_factor,
		])
		draw_colored_polygon(left_ear, gold)
		draw_colored_polygon(right_ear, gold)
		draw_circle(center + Vector2(0.0, 2.0) * scale_factor, 15.0 * scale_factor, cream)
		draw_circle(center + Vector2(-6.0, 1.0) * scale_factor, 2.1 * scale_factor, navy)
		draw_circle(center + Vector2(6.0, 1.0) * scale_factor, 2.1 * scale_factor, navy)
		draw_circle(center + Vector2(0.0, 6.0) * scale_factor, 2.0 * scale_factor, cheek)
		draw_line(
			center + Vector2(0.0, 8.0) * scale_factor,
			center + Vector2(-4.0, 11.0) * scale_factor,
			navy, 1.5 * scale_factor, true)
		draw_line(
			center + Vector2(0.0, 8.0) * scale_factor,
			center + Vector2(4.0, 11.0) * scale_factor,
			navy, 1.5 * scale_factor, true)


const FONT_PATH := "res://fonts/Fredoka-VariableFont_wdth,wght.ttf"
# The actual player cat model (same glb player.tscn instances). Its own file
# only contains the firing animation — idle/dance get merged in at runtime
# from the shared animation library, exactly like character_body_3d.gd does.
const MASCOT_DISPLAY_PATH := "res://models/playerAnimations/cat model firing ani.glb"
const MASCOT_ANIM_SOURCE := "res://models/playerAnimations/Dance.glb"
const MASCOT_ANIM_IDLE_INDEX := 2    # idle_pistol — hands posed for the held gun
const MASCOT_ANIM_DANCE_INDEX := 10
const SHOWCASE_PLAYER_SCENE := "res://player.tscn"   # the real cat, display-only
const SHOWCASE_GUN_SCENE := "res://gun.tscn"
# Section 4 trophy pedestal (menu-only; source .blend alongside, regenerate
# with tools/gen_trophy_pedestal.py). Deck top sits at this height.
const PEDESTAL_SCENE := "res://models/menu/TrophyPedestal.glb"
const PEDESTAL_TOP := 0.66
const PEDESTAL_RING_HEIGHT := 0.51

# Rendered logo (replaces the text logo when present). The region crops the
# artwork out of the source image's outer margins.
const LOGO_IMAGE_PATH := "res://UI/MainMenu/OneGunLogoV2.png"
# V2 is 1672x941 and uses a different artwork footprint than V1. Keep a small
# even border around its measured 1277x817 logo bounds instead of cropping it
# with V1's region (which cut off the new outer letters and star).
const LOGO_IMAGE_REGION := Rect2(204, 36, 1309, 849)
# Blender-rendered tagline ribbon (source .blend in models/menu; regenerate
# with tools/gen_tagline_ribbon.py). Text stays live on top.
const RIBBON_IMAGE_PATH := "res://UI/MainMenu/TaglineRibbon.png"

# Section 7 ribbon carousel. Keep the original line first so the existing
# presentation remains the initial state, then rotate through the added copy.
const TAGLINES: PackedStringArray = [
	"ONE SHOT. ONE CHANCE. ONE SWING.",
	"THE GUN IS YOURS. UNTIL IT ISN’T.",
	"GET THE GUN. BECOME THE TARGET.",
	"EVERYBODY WANTS IT. NOBODY KEEPS IT.",
	"HOLD THE GUN. FEAR EVERYONE.",
	"GRAB THE GUN. START THE CHAOS.",
	"THE MOST POWERFUL PLAYER IS ALSO THE BIGGEST TARGET.",
	"HAVING THE GUN IS THE EASY PART.",
	"THERE’S ONLY ONE. FIGHT FOR IT.",
	"GET THE GUN. LOSE YOUR PEACE.",
	"ONE GUN. ALL EYES ON YOU.",
	"THE SECOND YOU GRAB IT, THE HUNT BEGINS.",
	"POWER UP. STAND OUT. GET CHASED.",
	"GRAB THE GUN. EARN THE HEAT.",
	"YOU WANT THE GUN. THEY WANT YOU.",
	"HOLD THE POWER. HANDLE THE PRESSURE.",
]
const TAGLINE_HOLD_DURATION := 5.0
const TAGLINE_FADE_DURATION := 0.24

const HOVER_DURATION := 0.19
const PRESS_DURATION := 0.08
const PANEL_DURATION := 0.24
const BUTTON_STAGGER := 0.055
const HOVER_SCALE := 1.018
const PRESSED_SCALE := 0.975
const HOVER_RISE := 3.0
const ICON_HOVER_SCALE := 1.08
const STAR_HOVER_SCALE := 1.13
const BUILD_CHANNEL := "PLAYTEST"
const PEDESTAL_PULSE_HALF_DURATION := 6.0

@onready var _background_layer: Control = $BackgroundLayer
@onready var _interface_layer: Control = $InterfaceLayer
@onready var _modal_layer: Control = $ModalLayer

var _font_medium: FontVariation
var _font_bold: FontVariation
var _font_heavy: FontVariation
var _button_noise_texture: NoiseTexture2D

# FABLE5 packet §1: toggleable composition guides (target cabinet rect, the
# 65% showcase vertical, the 89% pedestal baseline). Off in the finished menu.
@export var show_layout_guides := false:
	set(value):
		show_layout_guides = value
		if _guides != null and is_instance_valid(_guides):
			_guides.visible = value

# Packet §1 composition targets (fractions of a 16:9 reference viewport).
const CABINET_X := 0.031
const CABINET_Y := 0.023
const CABINET_W := 0.325
const CABINET_H := 0.954
const SHOWCASE_SCREEN_X := 0.65   # showcase visual center
const PEDESTAL_SCREEN_Y := 0.89   # pedestal base line

var _left_panel: PanelContainer
var _guides: Control
var _title_label: Label
var _title_label2: Label
var _logo_image: TextureRect
var _logo_stack: Control
var _tagline_label: Label
var _tagline_timer: Timer
var _tagline_tween: Tween
var _tagline_index := 0
var _player_name_label: Label
var _connection_label: Label
var _secondary_status_label: Label
var _status_dot: Panel
var _version_label: Label
var _build_channel_label: Label
var _primary_buttons: Array[Button] = []
var _local_menu_button: Button
var _online_menu_button: Button

var _map_cycler: Node
var _background_viewport: SubViewport
var _showcase_viewport: SubViewport
var _showcase_animation_player: AnimationPlayer
var _pedestal_ring_light: OmniLight3D
var _pedestal_glow_materials: Array[StandardMaterial3D] = []
var _pedestal_glow_base_energy: Array[float] = []
var _pedestal_pulse_tween: Tween
var _ambient_particles: Array[GPUParticles3D] = []
var _ambient_app_focused := true

var _modal_scrim: ColorRect
var _modal_center: CenterContainer
var _local_panel: PanelContainer
var _online_panel: PanelContainer
var _player_settings_overlay: Control
var _online_status: Label
var _online_ip_field: LineEdit
var _online_host_lobby_field: LineEdit
var _online_host_button: Button
var _online_join_button: Button
var _online_host_hint: Label

var _reduced_motion := false
var _last_modal_opener: Control
var _using_pointer := true


func _ready() -> void:
	_reduced_motion = _reduced_motion_enabled()
	_load_fonts()
	_build_background()
	_build_main_interface()
	_build_modal_layer()
	_refresh_ambient_motion()
	_refresh_connection_status()
	if not PlayerPrefs.setting_changed.is_connected(_on_player_preference_changed):
		PlayerPrefs.setting_changed.connect(_on_player_preference_changed)
	if not NetworkManager.lobby_changed.is_connected(_refresh_connection_status):
		NetworkManager.lobby_changed.connect(_refresh_connection_status)
	if not NetworkManager.connection_succeeded.is_connected(_refresh_connection_status):
		NetworkManager.connection_succeeded.connect(_refresh_connection_status)
	if not NetworkManager.connection_failed.is_connected(_refresh_connection_status):
		NetworkManager.connection_failed.connect(_refresh_connection_status)
	if not NetworkManager.server_disconnected.is_connected(_refresh_connection_status):
		NetworkManager.server_disconnected.connect(_refresh_connection_status)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_finish_layout")
	AudioManager.play_music("menu")
	UICapture.maybe_capture(self, _capture_name(), 4.2)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_ambient_app_focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_ambient_app_focused = true
	else:
		return
	if is_node_ready():
		_refresh_ambient_motion()


func _unhandled_input(event: InputEvent) -> void:
	if not _modal_layer.visible or not event.is_action_pressed("ui_cancel"):
		return
	if _online_panel.visible:
		_on_online_back()
	else:
		_close_modal()
	get_viewport().set_input_as_handled()


func _finish_layout() -> void:
	_apply_responsive_layout()
	_animate_entrance()
	if OS.get_environment("ONEGUN_UI_CAPTURE") != "" and OS.get_environment("ONEGUN_UI_CAPTURE_STATE").begins_with("online_"):
		_on_online_pressed.call_deferred()
	elif OS.get_environment("ONEGUN_UI_CAPTURE") != "" and (OS.get_environment("ONEGUN_UI_CAPTURE_STATE").begins_with("settings_") or OS.get_environment("ONEGUN_UI_CAPTURE_STATE").begins_with("crosshair_")):
		_on_player_settings_pressed.call_deferred()
	elif OS.get_environment("ONEGUN_UI_CAPTURE") != "" and OS.get_environment("ONEGUN_UI_CAPTURE_STATE").begins_with("lobby_"):
		_bootstrap_lobby_capture.call_deferred()
	if not Input.get_connected_joypads().is_empty() and not _primary_buttons.is_empty():
		_using_pointer = false
		# Let the Local Play entrance finish before applying its selected-scale
		# tween so the two motions never fight each other.
		var focus_delay := get_tree().create_timer(PANEL_DURATION + 0.12)
		focus_delay.timeout.connect(_focus_local_play_if_needed, CONNECT_ONE_SHOT)
func _input(event: InputEvent) -> void:
	if _modal_layer == null:
		return
	if event is InputEventMouseMotion:
		if event.relative.length_squared() > 4.0:
			_using_pointer = true
			_clear_primary_focus_for_pointer()
		return
	if event is InputEventMouseButton:
		_using_pointer = true
		return

	var navigation_input := false
	if event is InputEventKey:
		navigation_input = event.pressed and not event.echo
	elif event is InputEventJoypadButton:
		navigation_input = event.pressed
	elif event is InputEventJoypadMotion:
		navigation_input = absf(event.axis_value) >= 0.45
	if not navigation_input:
		return
	_using_pointer = false
	if not _modal_layer.visible and get_viewport().gui_get_focus_owner() == null:
		_focus_local_play_if_needed()


func _focus_local_play_if_needed() -> void:
	if _using_pointer or _modal_layer.visible or _local_menu_button == null:
		return
	if get_viewport().gui_get_focus_owner() == null:
		_local_menu_button.grab_focus()


func _clear_primary_focus_for_pointer() -> void:
	if _modal_layer.visible:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and focus_owner in _primary_buttons:
		focus_owner.release_focus()


# -----------------------------------------------------------------------------
# Shared typography, palette, and style roles
# -----------------------------------------------------------------------------

func _load_fonts() -> void:
	if not ResourceLoader.exists(FONT_PATH):
		return
	var base_font: Font = load(FONT_PATH)
	_font_medium = FontVariation.new()
	_font_medium.base_font = base_font
	_font_medium.variation_opentype = {"wght": 550}
	_font_bold = FontVariation.new()
	_font_bold.base_font = base_font
	_font_bold.variation_opentype = {"wght": 760}
	_font_heavy = FontVariation.new()
	_font_heavy.base_font = base_font
	_font_heavy.variation_opentype = {"wght": 850, "wdth": 92}
	_font_heavy.variation_embolden = 0.22


func _color(role: String) -> Color:
	match role:
		"canvas":
			return ThemeManager.BG_DARK
		"panel":
			return ThemeManager.BG_PANEL
		"panel_raised":
			return ThemeManager.BG_PANEL.lightened(0.055)
		"input":
			return ThemeManager.BG_INPUT
		"gold":
			return ThemeManager.ACCENT_GOLD
		"cyan":
			return ThemeManager.ACCENT_CYAN
		"danger":
			return ThemeManager.DANGER
		"positive":
			return ThemeManager.POSITIVE
		"text":
			return ThemeManager.TEXT_WHITE
		"muted":
			return ThemeManager.TEXT_DIM
		"border":
			return ThemeManager.BORDER
	return Color.WHITE


func _style_box(
		background: Color,
		border: Color,
		radius: int = 18,
		border_width: int = 2,
		shadow_size: int = 0,
		content_margin: float = 0.0
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
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
		style.shadow_size = shadow_size
		style.shadow_offset = Vector2(0.0, float(shadow_size) * 0.45)
	return style


func _panel_style(emphasized := false) -> StyleBoxFlat:
	var background := _color("panel_raised") if emphasized else _color("panel")
	background.a = 0.96
	var border := _color("gold") if emphasized else _color("border")
	return _style_box(background, border, 22, 2, 12)


func _button_style(state: String) -> StyleBoxFlat:
	match state:
		"hover":
			return _style_box(_color("gold"), _color("gold").lightened(0.16), 13, 2, 5, 18.0)
		"pressed":
			return _style_box(_color("cyan").darkened(0.22), _color("cyan"), 13, 3, 2, 18.0)
		"focus":
			return _style_box(_color("panel_raised"), _color("cyan"), 13, 4, 7, 18.0)
		"danger":
			return _style_box(_color("panel_raised"), _color("danger").darkened(0.15), 13, 2, 4, 18.0)
		"disabled":
			var disabled := _color("input")
			disabled.a = 0.62
			return _style_box(disabled, _color("border").darkened(0.25), 13, 2, 0, 18.0)
		_:
			return _style_box(_color("panel_raised"), _color("border"), 13, 2, 4, 18.0)


func _line_edit_style(focused := false) -> StyleBoxFlat:
	return _style_box(
		_color("input"),
		_color("cyan") if focused else _color("border"),
		12,
		3 if focused else 2,
		4 if focused else 0,
		15.0
	)


func _make_label(text: String, size: int, color_role := "text", bold := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", _color(color_role))
	if bold and _font_bold:
		label.add_theme_font_override("font", _font_bold)
	elif _font_medium:
		label.add_theme_font_override("font", _font_medium)
	return label


func _apply_margin(container: MarginContainer, amount: int) -> void:
	container.add_theme_constant_override("margin_left", amount)
	container.add_theme_constant_override("margin_top", amount)
	container.add_theme_constant_override("margin_right", amount)
	container.add_theme_constant_override("margin_bottom", amount)


func _set_accessible_text(control: Control, label: String, description := "") -> void:
	control.accessibility_name = label
	control.accessibility_description = description
	control.tooltip_text = label if description.is_empty() else "%s — %s" % [label, description]


# -----------------------------------------------------------------------------
# Existing live background, kept as a presentation-only viewport
# -----------------------------------------------------------------------------

func _preview_render_size(viewport_size: Vector2) -> Vector2i:
	# Render 1:1 up to the 1920x1080 master pixel budget. Larger displays get
	# one clean upscale rather than rendering oversized 3D previews and then
	# scaling them down through the project canvas.
	var safe_size := Vector2(maxf(viewport_size.x, 1.0), maxf(viewport_size.y, 1.0))
	var master_pixels := 1920.0 * 1080.0
	var scale_factor := minf(1.0, sqrt(master_pixels / (safe_size.x * safe_size.y)))
	return Vector2i(
		maxi(1, roundi(safe_size.x * scale_factor)),
		maxi(1, roundi(safe_size.y * scale_factor)))

func _build_background() -> void:
	# MapPreviewHost — full-screen live 3D world. Section 2 replaces the single
	# title map inside it with the 10-second map-preview cycler.
	var background_container := SubViewportContainer.new()
	background_container.name = "MapPreviewHost"
	background_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_container.stretch = true
	background_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_layer.add_child(background_container)

	var background_viewport := SubViewport.new()
	background_viewport.size = _preview_render_size(get_viewport_rect().size)
	background_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	background_viewport.gui_disable_input = true
	background_container.add_child(background_viewport)
	_background_viewport = background_viewport

	var camera := Camera3D.new()
	camera.name = "TitleCamera"
	# NOTE (packet §5 deviation): FOV stays 60 — the showcase composition was
	# eye-matched and approved across several iterations at this FOV, and the
	# wider view also keeps the ground-level map previews immersive.
	camera.fov = 60.0
	# Depth of field on the MAP only: the showcase lives in its own overlay
	# world (below) and is never blurred or tinted by map conditions.
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = 13.0
	attributes.dof_blur_far_transition = 8.0
	attributes.dof_blur_amount = 0.07
	camera.attributes = attributes
	background_viewport.add_child(camera)

	# Full-screen transition fade for map swaps (covers the 3D world only;
	# the cabinet UI in InterfaceLayer stays visible and stable above it).
	var map_fade := ColorRect.new()
	map_fade.name = "MapTransitionFade"
	map_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_fade.color = Color(0.02, 0.03, 0.06, 0.0)
	map_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_layer.add_child(map_fade)

	# Live map-preview cycler (packet §2): real maps, gameplay stripped,
	# rotating every 10 seconds behind the fade.
	var cycler: Node = load("res://menu_map_cycler.gd").new()
	cycler.name = "MapCycler"
	background_viewport.add_child(cycler)
	_map_cycler = cycler
	cycler.setup(background_viewport, camera, map_fade, self, _reduced_motion)

	_build_showcase_overlay()


# The showcase lives in its OWN transparent overlay viewport with its own
# world, environment, and lights — composited over the map view. Map lighting,
# fog, tint, exposure, and DOF can never touch it: identical clean read on
# every cycling map (and it persists visibly through map-swap fades).
func _build_showcase_overlay() -> void:
	var overlay_container := SubViewportContainer.new()
	overlay_container.name = "ShowcaseOverlay"
	overlay_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_container.stretch = true
	overlay_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_layer.add_child(overlay_container)

	var overlay_viewport := SubViewport.new()
	overlay_viewport.size = _preview_render_size(get_viewport_rect().size)
	overlay_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	overlay_viewport.transparent_bg = true
	overlay_viewport.own_world_3d = true
	overlay_viewport.gui_disable_input = true
	overlay_container.add_child(overlay_viewport)
	_showcase_viewport = overlay_viewport

	# Showcase-private environment: neutral cool ambient base + the same
	# filmic/glow treatment tuned for the maps — one look, everywhere.
	var overlay_env := Environment.new()
	overlay_env.background_mode = Environment.BG_CLEAR_COLOR
	overlay_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	overlay_env.ambient_light_color = Color(0.60, 0.66, 0.84)
	overlay_env.ambient_light_energy = 0.48
	overlay_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	overlay_env.glow_enabled = true
	overlay_env.glow_intensity = 0.45
	overlay_env.glow_strength = 1.0
	overlay_env.glow_bloom = 0.03
	overlay_env.glow_hdr_threshold = 1.16
	var overlay_world_env := WorldEnvironment.new()
	overlay_world_env.name = "ShowcaseEnvironment"
	overlay_world_env.environment = overlay_env
	overlay_viewport.add_child(overlay_world_env)

	var overlay_camera := Camera3D.new()
	overlay_camera.name = "ShowcaseCamera"
	overlay_camera.fov = 60.0   # matches the map camera so composition math holds
	overlay_viewport.add_child(overlay_camera)

	_build_showcase_anchors(overlay_camera)
	# The readability gradient and vignette are authored while the showcase is
	# being built, so they are temporarily later siblings in BackgroundLayer.
	# Keep that grading on the MAP only: drawing it over the transparent
	# showcase was dimming the cat, pedestal, ring glow, and motes together.
	_background_layer.move_child(overlay_container, _background_layer.get_child_count() - 1)


# CharacterShowcase + Pedestal anchors, parented to the overlay camera. Local
# offsets are derived from the packet targets at fov 60: showcase center near
# 65% screen width, pedestal base near 89% screen height, shifted per the
# approved framing iterations.
func _build_showcase_anchors(camera: Camera3D) -> void:
	var showcase := Node3D.new()
	showcase.name = "CharacterShowcase"
	# Raised + pushed back vs the original framing: the wide trophy pedestal
	# was cropping its front plaque at the bottom of the frame. This puts the
	# pedestal base near the packet's 89% screen-height line with the plaque
	# fully visible.
	showcase.position = Vector3(3.05, -2.40, -6.1)
	camera.add_child(showcase)

	var pedestal := Node3D.new()
	pedestal.name = "Pedestal"
	# The showcase sits right of the camera axis, so a straight-ahead plaque
	# reads angled from the viewer's seat — turn it to face the camera.
	pedestal.rotation.y = -0.46
	showcase.add_child(pedestal)

	if ResourceLoader.exists(PEDESTAL_SCENE):
		var packed: PackedScene = load(PEDESTAL_SCENE)
		if packed != null:
			var trophy := packed.instantiate() as Node3D
			trophy.name = "TrophyPedestal"
			pedestal.add_child(trophy)
			# The glow ring is emissive; back it with real warm light so it
			# genuinely illuminates the cat's lower body (packet §4).
			var ring_light := OmniLight3D.new()
			ring_light.name = "RingLight"
			ring_light.position = Vector3(0.0, PEDESTAL_RING_HEIGHT, 0.0)
			ring_light.light_color = Color(1.0, 0.72, 0.25)
			ring_light.light_energy = 1.9
			ring_light.omni_range = 2.6
			pedestal.add_child(ring_light)
			_configure_pedestal_pulse(trophy, ring_light)
	else:
		# Fallback placeholder if the generated asset is missing.
		var pedestal_block := MeshInstance3D.new()
		pedestal_block.name = "PedestalPlaceholder"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.05
		cyl.bottom_radius = 1.2
		cyl.height = 0.4
		pedestal_block.mesh = cyl
		pedestal_block.position.y = 0.2
		var block_mat := StandardMaterial3D.new()
		block_mat.albedo_color = Color(0.45, 0.38, 0.20)
		pedestal_block.material_override = block_mat
		pedestal.add_child(pedestal_block)

	_build_showcase_character(showcase)
	_build_showcase_lighting(showcase)
	_build_ambient_particles(showcase)


# Section 11: the imported glow ring keeps its normal emission while a long
# 12-second sine-like loop moves it only +/-12%. Its backing light follows a
# similarly narrow range, so the pedestal never turns off or flashes.
func _configure_pedestal_pulse(trophy: Node, ring_light: OmniLight3D) -> void:
	_pedestal_ring_light = ring_light
	_pedestal_glow_materials.clear()
	_pedestal_glow_base_energy.clear()
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(trophy, meshes)
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var source_material := mesh_instance.get_active_material(surface_index) as StandardMaterial3D
			if source_material == null:
				continue
			var material_name := source_material.resource_name.to_lower()
			var is_glow_ring := material_name.contains("goldglow")
			is_glow_ring = is_glow_ring or (
				source_material.emission_enabled
				and source_material.emission_energy_multiplier >= 2.0)
			if not is_glow_ring:
				continue
			var local_material := source_material.duplicate(true) as StandardMaterial3D
			mesh_instance.set_surface_override_material(surface_index, local_material)
			_pedestal_glow_materials.append(local_material)
			_pedestal_glow_base_energy.append(local_material.emission_energy_multiplier)

	_set_pedestal_pulse(0.5)
	if _reduced_motion:
		return
	if _pedestal_pulse_tween != null and _pedestal_pulse_tween.is_valid():
		_pedestal_pulse_tween.kill()
	_pedestal_pulse_tween = create_tween().set_loops()
	_pedestal_pulse_tween.tween_method(
		_set_pedestal_pulse, 0.0, 1.0, PEDESTAL_PULSE_HALF_DURATION
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_pedestal_pulse_tween.tween_method(
		_set_pedestal_pulse, 1.0, 0.0, PEDESTAL_PULSE_HALF_DURATION
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_instances(child, out)


func _set_pedestal_pulse(weight: float) -> void:
	for index in _pedestal_glow_materials.size():
		var base_energy := _pedestal_glow_base_energy[index]
		_pedestal_glow_materials[index].emission_energy_multiplier = lerpf(
			base_energy * 0.54, base_energy * 0.70, weight)
	if _pedestal_ring_light != null:
		_pedestal_ring_light.light_energy = lerpf(1.0, 1.3, weight)


# Sparse GPU particles: 24 slow warm-light motes with a 10-second lifetime,
# plus 12 shorter pedestal sparks on a 6-second lifetime. Both are rendered
# in the private 3D overlay, so they always remain behind the 2D cabinet.
func _build_ambient_particles(showcase: Node3D) -> void:
	if _reduced_motion:
		return
	var warm_motes := _make_ambient_particle_field(
		"WarmDustMotes", Vector3(0.9, 3.45, -0.65), 24, 10.0,
		Vector3(1.65, 1.65, 0.55), Color(1.0, 0.76, 0.35, 0.38),
		Vector2(0.026, 0.055), Vector2(0.015, 0.055))
	showcase.add_child(warm_motes)
	_ambient_particles.append(warm_motes)

	var pedestal_sparks := _make_ambient_particle_field(
		"PedestalSparks", Vector3(0.0, 0.68, 0.25), 12, 6.0,
		Vector3(1.25, 0.12, 0.48), Color(1.0, 0.64, 0.18, 0.42),
		Vector2(0.022, 0.045), Vector2(0.035, 0.105))
	showcase.add_child(pedestal_sparks)
	_ambient_particles.append(pedestal_sparks)


func _make_ambient_particle_field(
		field_name: String, field_position: Vector3, particle_count: int,
		particle_lifetime: float, emission_extents: Vector3, tint: Color,
		mote_size: Vector2, rise_speed: Vector2) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = field_name
	particles.position = field_position
	particles.amount = particle_count
	particles.lifetime = particle_lifetime
	particles.randomness = 0.55
	particles.preprocess = particle_lifetime
	particles.fixed_fps = 15
	particles.interpolate = true
	particles.fract_delta = true
	particles.local_coords = true
	particles.visibility_aabb = AABB(
		-emission_extents - Vector3(0.5, 0.5, 0.5),
		emission_extents * 2.0 + Vector3(1.0, 2.0, 1.0))

	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = emission_extents
	process_material.direction = Vector3.UP
	process_material.spread = 32.0
	process_material.gravity = Vector3(0.0, 0.006, 0.0)
	process_material.initial_velocity_min = rise_speed.x
	process_material.initial_velocity_max = rise_speed.y
	process_material.scale_min = 0.72
	process_material.scale_max = 1.18
	var color_gradient := Gradient.new()
	color_gradient.set_color(0, Color(tint, 0.0))
	color_gradient.set_color(1, Color(tint, 0.0))
	color_gradient.add_point(0.18, tint)
	color_gradient.add_point(0.72, Color(tint, tint.a * 0.72))
	var color_ramp := GradientTexture1D.new()
	color_ramp.gradient = color_gradient
	process_material.color_ramp = color_ramp
	particles.process_material = process_material

	var mote_material := StandardMaterial3D.new()
	mote_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote_material.vertex_color_use_as_albedo = true
	mote_material.albedo_color = Color.WHITE
	mote_material.emission_enabled = true
	mote_material.emission = tint
	mote_material.emission_energy_multiplier = 1.25
	var mote_quad := QuadMesh.new()
	mote_quad.size = mote_size
	mote_quad.material = mote_material
	particles.draw_pass_1 = mote_quad
	return particles


# Section 3 showcase: the ACTUAL player character + gun, display-only.
# player.tscn is instanced with its gameplay script removed (no input, camera,
# network, or combat code runs) — it brings the correct model scale and the
# game's own hand-bone gun mount, so the held pose matches gameplay exactly.
func _build_showcase_character(showcase: Node3D) -> void:
	if not ResourceLoader.exists(SHOWCASE_PLAYER_SCENE):
		return
	var packed: PackedScene = load(SHOWCASE_PLAYER_SCENE)
	if packed == null:
		return
	var actor := packed.instantiate()
	actor.set_script(null)   # BEFORE entering the tree: no gameplay _ready runs
	actor.name = "ShowcaseCat"
	# Neutralize gameplay leftovers baked in the scene.
	var cam := actor.find_child("Camera3D", true, false) as Camera3D
	if cam != null:
		cam.current = false
	for shape in [actor.get_node_or_null("CollisionShape3D")]:
		if shape != null:
			shape.disabled = true
	# Feet on the trophy deck (actor origin sits 1.04 above the feet), facing
	# the player with a slight three-quarter turn per the concept.
	actor.position = Vector3(0.0, PEDESTAL_TOP + 1.04, 0.0)
	actor.rotation.y = -0.30
	showcase.add_child(actor)
	_mount_showcase_gun(actor)
	if not _reduced_motion:
		_setup_mascot_animations(actor)

func _mount_showcase_gun(actor: Node) -> void:
	var hold_point := actor.find_child("GunHoldPoint", true, false)
	if hold_point == null or not ResourceLoader.exists(SHOWCASE_GUN_SCENE):
		return
	var packed: PackedScene = load(SHOWCASE_GUN_SCENE)
	if packed == null:
		return
	var gun := packed.instantiate()
	gun.set_script(null)   # display only — no firing, pickup, or physics logic
	gun.name = "ShowcaseGun"
	if gun is RigidBody3D:
		gun.freeze = true
		gun.collision_layer = 0
		gun.collision_mask = 0
	var pickup_label := gun.get_node_or_null("PickupLabel")
	if pickup_label != null:
		pickup_label.visible = false
	var area := gun.get_node_or_null("Area3D")
	if area != null:
		area.monitoring = false
	# Base mount matches the game (gun.gd _local_pickup: origin at the palm,
	# yaw PI), but the gameplay idle points the muzzle UP — from the menu's
	# front-facing camera that reads like the cat licking the gun. Pitch it
	# forward into a readable "ready" diagonal across the torso instead.
	hold_point.add_child(gun)
	gun.position = Vector3.ZERO
	# NOTE: this axis is amplified by the bone space — -70 swung the muzzle
	# ~150 degrees (fully downward). -30 gives the approved ~40-degree diagonal.
	gun.rotation_degrees = Vector3(-30.0, 180.0, 0.0)
	gun.scale = Vector3.ONE

# Dedicated showcase lighting, parented to the camera-space anchor so the cat
# reads identically on every cycling map (including the dark forest): warm key
# from upper camera-right with contact shadows, cool rim from behind-left.
func _build_showcase_lighting(showcase: Node3D) -> void:
	# Bright, shadowless, with a deliberate kiss of glow (user call): the key
	# pushes highlights just past the bloom threshold so the cat pops with a
	# soft sheen — well short of the old full-halo glare.
	var key := SpotLight3D.new()
	key.name = "ShowcaseKeyLight"
	key.position = Vector3(2.6, 4.6, 3.0)
	key.light_color = Color(1.0, 0.88, 0.68)
	key.light_energy = 6.0
	key.spot_range = 9.5
	key.spot_angle = 32.0
	key.shadow_enabled = false
	showcase.add_child(key)
	key.look_at_from_position(showcase.to_global(key.position), showcase.to_global(Vector3(0.0, 1.4, 0.0)), Vector3.UP)

	var rim := OmniLight3D.new()
	rim.name = "ShowcaseRimLight"
	rim.position = Vector3(-1.6, 2.6, -2.0)
	rim.light_color = Color(0.45, 0.75, 1.0)
	rim.light_energy = 1.9
	rim.omni_range = 4.5
	showcase.add_child(rim)

	# Cool low-intensity fill from camera-left/front (packet §5) — lifts the
	# shadow side of the cat without flattening the warm key.
	var fill := OmniLight3D.new()
	fill.name = "ShowcaseFillLight"
	fill.position = Vector3(-3.4, 1.3, 3.0)
	fill.light_color = Color(0.60, 0.72, 1.0)
	fill.light_energy = 1.25
	fill.omni_range = 6.5
	showcase.add_child(fill)

	# Horizontal readability gradient: strongest behind navigation, lighter over
	# the display case, then slightly darker at the far edge.
	var readability := TextureRect.new()
	readability.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	readability.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readability.stretch_mode = TextureRect.STRETCH_SCALE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.025, 0.035, 0.075, 0.90))
	gradient.set_color(1, Color(0.025, 0.035, 0.075, 0.58))
	gradient.add_point(0.57, Color(0.025, 0.035, 0.075, 0.33))
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0.0, 0.5)
	gradient_texture.fill_to = Vector2(1.0, 0.5)
	readability.texture = gradient_texture
	_background_layer.add_child(readability)

	var vignette := TextureRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	var vignette_gradient := Gradient.new()
	vignette_gradient.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	vignette_gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.58))
	var vignette_texture := GradientTexture2D.new()
	vignette_texture.gradient = vignette_gradient
	vignette_texture.fill = GradientTexture2D.FILL_RADIAL
	vignette_texture.fill_from = Vector2(0.5, 0.5)
	vignette_texture.fill_to = Vector2(0.5, -0.12)
	vignette.texture = vignette_texture
	_background_layer.add_child(vignette)





# -----------------------------------------------------------------------------
# Main shell: brand/navigation + mascot display + supporting information
# -----------------------------------------------------------------------------

func _build_main_interface() -> void:
	# MainMenuUI — the 2D cabinet floats over the full-screen 3D world at the
	# packet's exact reference rect (3.1% / 2.3% / 32.5% / 95.4%). Positioning
	# happens in _apply_responsive_layout so ultrawide screens keep a centered
	# 16:9-proportioned safe region instead of stretching.
	_build_brand_navigation()
	_build_layout_guides()


func _build_layout_guides() -> void:
	_guides = Control.new()
	_guides.name = "LayoutGuides"
	_guides.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_guides.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guides.visible = show_layout_guides
	_guides.draw.connect(func():
		var size := _guides.size
		var safe := _safe_region(size)
		# Target cabinet rect (gold)
		var rect := Rect2(
			safe.position.x + safe.size.x * CABINET_X,
			safe.position.y + safe.size.y * CABINET_Y,
			safe.size.x * CABINET_W,
			safe.size.y * CABINET_H)
		_guides.draw_rect(rect, Color(1.0, 0.72, 0.0, 0.35), false, 3.0)
		# Showcase center vertical (cyan) + pedestal base line (green)
		var showcase_x := safe.position.x + safe.size.x * SHOWCASE_SCREEN_X
		_guides.draw_line(Vector2(showcase_x, 0), Vector2(showcase_x, size.y), Color(0.0, 0.9, 1.0, 0.4), 2.0)
		var pedestal_y := safe.position.y + safe.size.y * PEDESTAL_SCREEN_Y
		_guides.draw_line(Vector2(0, pedestal_y), Vector2(size.x, pedestal_y), Color(0.3, 1.0, 0.3, 0.4), 2.0)
	)
	_interface_layer.add_child(_guides)


# The centered 16:9-proportioned region the composition anchors to. On 16:9
# screens this is the whole viewport; on ultrawide the extra width shows more
# live map while the cabinet/showcase stay composed (packet §1/§12).
func _safe_region(viewport_size: Vector2) -> Rect2:
	var target_aspect := 16.0 / 9.0
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	if aspect <= target_aspect + 0.01:
		return Rect2(Vector2.ZERO, viewport_size)
	var safe_width := viewport_size.y * target_aspect
	return Rect2(Vector2((viewport_size.x - safe_width) * 0.5, 0.0), Vector2(safe_width, viewport_size.y))


func _build_brand_navigation() -> void:
	# Packet §6 — premium toy cabinet, built from nested styleboxes so it stays
	# crisp at every resolution. Layers, outermost in:
	#   1. dark amber gold edge + soft exterior shadow (lifts off the 3D scene)
	#   2. bright gold frame body with a pale warm inner-highlight ring
	#   3. near-black separator line
	#   4. deep navy inset face (faint center lift + whisper of speck texture)
	_left_panel = PanelContainer.new()
	_left_panel.name = "LeftCabinet"
	var edge_style := _style_box(Color(0.48, 0.31, 0.09), Color(0.24, 0.15, 0.05), 30, 2, 18)
	edge_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	_left_panel.add_theme_stylebox_override("panel", edge_style)
	_interface_layer.add_child(_left_panel)

	var frame_margin := MarginContainer.new()
	_apply_margin(frame_margin, 3)
	_left_panel.add_child(frame_margin)
	var frame_body := PanelContainer.new()
	frame_body.name = "GoldFrame"
	# Bright gold body; the pale border reads as the warm inner highlight
	# catching light along the frame's inner lip.
	frame_body.add_theme_stylebox_override("panel", _style_box(Color(0.83, 0.60, 0.19), Color(0.99, 0.86, 0.52), 27, 2))
	frame_margin.add_child(frame_body)

	var separator_margin := MarginContainer.new()
	_apply_margin(separator_margin, 9)
	frame_body.add_child(separator_margin)
	var separator := PanelContainer.new()
	separator.name = "FrameSeparator"
	separator.add_theme_stylebox_override("panel", _style_box(Color(0.025, 0.03, 0.055), Color.TRANSPARENT, 20, 0))
	separator_margin.add_child(separator)

	var face_margin := MarginContainer.new()
	_apply_margin(face_margin, 3)
	separator.add_child(face_margin)
	var face := PanelContainer.new()
	face.name = "CabinetFace"
	var face_style := _style_box(Color(0.055, 0.065, 0.115, 0.985), Color(0.85, 0.62, 0.25, 0.20), 17, 1)
	face.add_theme_stylebox_override("panel", face_style)
	face_margin.add_child(face)

	# Faint center lift on the navy face (nearly-black at edges, subtle glow
	# toward the middle) + a very quiet speck/wear texture.
	var face_stack := Control.new()
	face_stack.name = "FaceLayers"
	face.add_child(face_stack)
	var center_lift := TextureRect.new()
	center_lift.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_lift.stretch_mode = TextureRect.STRETCH_SCALE
	var lift_gradient := Gradient.new()
	lift_gradient.set_color(0, Color(0.35, 0.42, 0.72, 0.10))
	lift_gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var lift_texture := GradientTexture2D.new()
	lift_texture.gradient = lift_gradient
	lift_texture.fill = GradientTexture2D.FILL_RADIAL
	lift_texture.fill_from = Vector2(0.5, 0.32)
	lift_texture.fill_to = Vector2(0.5, 1.1)
	center_lift.texture = lift_texture
	face_stack.add_child(center_lift)
	var wear := TextureRect.new()
	wear.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wear.stretch_mode = TextureRect.STRETCH_SCALE
	var wear_noise := FastNoiseLite.new()
	wear_noise.frequency = 0.35
	var wear_texture := NoiseTexture2D.new()
	wear_texture.noise = wear_noise
	wear_texture.width = 512
	wear_texture.height = 512
	wear.texture = wear_texture
	wear.modulate = Color(1.0, 0.95, 0.85, 0.03)
	face_stack.add_child(wear)

	var inner := MarginContainer.new()
	inner.name = "CabinetContentMargin"
	_apply_margin(inner, 26)
	face.add_child(inner)

	var column := VBoxContainer.new()
	column.name = "CabinetColumn"
	column.add_theme_constant_override("separation", 12)
	inner.add_child(column)

	# LogoArea: the rendered ONE GUN logo image when present, otherwise the
	# chunky faux-3D stacked text logo. NO Toy Box wording (FABLE5 packet rule 5).
	if ResourceLoader.exists(LOGO_IMAGE_PATH):
		var logo_tex := TextureRect.new()
		logo_tex.name = "LogoImage"
		# The rendered logo ships with large transparent margins — crop to the
		# artwork region so it displays at full size.
		var atlas := AtlasTexture.new()
		atlas.atlas = load(LOGO_IMAGE_PATH)
		atlas.region = LOGO_IMAGE_REGION
		logo_tex.texture = atlas
		logo_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# Packet §7: the logo dominates the upper cabinet — stretched across the
		# panel width, aspect preserved, centered with even spacing both sides.
		logo_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_logo_image = logo_tex
		_title_label = _make_label("", 1, "text")   # placeholders keep responsive code happy
		_title_label2 = _make_label("", 1, "text")
	else:
		var logo_block := VBoxContainer.new()
		logo_block.name = "LogoBlock"
		logo_block.add_theme_constant_override("separation", -34)   # tight stack like the art
		logo_block.rotation_degrees = -2.5                          # playful tilt
		logo_block.pivot_offset = Vector2(0, 90)
		column.add_child(logo_block)

		_title_label = _make_logo_line("ONE ★", Color(0.99, 0.98, 0.95))
		_title_label.name = "GameTitle"
		logo_block.add_child(_title_label)

		_title_label2 = _make_logo_line("GUN", _color("gold"))
		_title_label2.name = "GameTitle2"
		logo_block.add_child(_title_label2)

	# Logo block: the ribbon banner is the "line" the logo sits on (concept
	# art) — stacked in one Control, ribbon anchored low, logo overlapping it.
	var logo_stack := Control.new()
	logo_stack.name = "LogoStack"
	logo_stack.custom_minimum_size = Vector2(0, 396)
	_logo_stack = logo_stack
	column.add_child(logo_stack)

	var ribbon_holder := Control.new()
	ribbon_holder.name = "TaglineRibbon"
	ribbon_holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	ribbon_holder.offset_top = -120.0
	logo_stack.add_child(ribbon_holder)

	if ResourceLoader.exists(RIBBON_IMAGE_PATH):
		var ribbon_img := TextureRect.new()
		ribbon_img.name = "RibbonArt"
		ribbon_img.texture = load(RIBBON_IMAGE_PATH)
		ribbon_img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ribbon_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ribbon_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ribbon_img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		ribbon_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ribbon_holder.add_child(ribbon_img)

	# The stars are separate, persistent fixtures; only the centered copy fades
	# between lines. This keeps the concept-art framing steady during rotation.
	var tagline_row := HBoxContainer.new()
	tagline_row.name = "TaglineCarousel"
	tagline_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tagline_row.offset_left = 48.0
	tagline_row.offset_right = -48.0
	tagline_row.offset_bottom = -18.0
	tagline_row.add_theme_constant_override("separation", 8)
	tagline_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon_holder.add_child(tagline_row)

	var left_star := _make_label("★", 15, "text", true)
	left_star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	left_star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tagline_row.add_child(left_star)

	_tagline_label = _make_label(TAGLINES[0], 14, "text", true)
	_tagline_label.add_theme_constant_override("letter_spacing", 1)
	_tagline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tagline_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tagline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tagline_label.max_lines_visible = 2
	_tagline_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tagline_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tagline_row.add_child(_tagline_label)

	var right_star := _make_label("★", 15, "text", true)
	right_star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right_star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tagline_row.add_child(right_star)

	_tagline_timer = Timer.new()
	_tagline_timer.name = "TaglineTimer"
	_tagline_timer.wait_time = TAGLINE_HOLD_DURATION
	_tagline_timer.one_shot = false
	_tagline_timer.timeout.connect(_advance_tagline)
	ribbon_holder.add_child(_tagline_timer)
	_tagline_timer.start()

	# Logo on top, overlapping the ribbon's band.
	if _logo_image != null:
		_logo_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_logo_image.offset_bottom = -112.0
		logo_stack.add_child(_logo_image)

	var divider := HSeparator.new()
	divider.add_theme_stylebox_override("separator", _style_box(_color("gold"), _color("gold"), 1, 0))
	divider.custom_minimum_size.y = 4
	column.add_child(divider)

	var navigation := VBoxContainer.new()
	navigation.name = "ButtonList"
	navigation.add_theme_constant_override("separation", 10)
	column.add_child(navigation)

	# Concept-art toy buttons: molded color fill, icon tile, title + subtitle, star.
	_local_menu_button = _make_menu_button("LOCAL PLAY", _on_local_menu_pressed, false,
		"SOLO • BOTS • SPLITSCREEN", MenuIconKind.PLAY, _color("gold"))
	_online_menu_button = _make_menu_button("ONLINE PLAY", _on_online_pressed, false,
		"HOST OR JOIN A LOBBY", MenuIconKind.NETWORK, Color(0.16, 0.39, 0.82))
	_primary_buttons = [
		_local_menu_button,
		_online_menu_button,
		_make_menu_button("PLAYER SETTINGS", _on_player_settings_pressed, false,
			"AUDIO • VIDEO • CONTROLS", MenuIconKind.SETTINGS, Color(0.46, 0.20, 0.76)),
	]
	if OS.is_debug_build() or Engine.is_editor_hint():
		_primary_buttons.append(_make_menu_button("DEV TOOLS  →  COMBAT LAB",
			_on_combat_lab_pressed, false, "RANGES • TARGETS • LIVE TUNING",
			MenuIconKind.SETTINGS, Color(0.08, 0.55, 0.58)))
	_primary_buttons.append(_make_menu_button("QUIT GAME", _on_quit_pressed, true,
		"SEE YA LATER", MenuIconKind.EXIT, Color(0.78, 0.16, 0.22)))
	for button in _primary_buttons:
		navigation.add_child(button)
	_connect_primary_focus_loop()

	var flexible_space := Control.new()
	flexible_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(flexible_space)

	var footer := PanelContainer.new()
	footer.name = "StatusFooter"
	footer.custom_minimum_size.y = 76
	var footer_outer_style := _style_box(
		_color("input").darkened(0.22), _color("border").lightened(0.05), 14, 2, 4)
	footer_outer_style.shadow_color = Color(0.015, 0.02, 0.06, 0.52)
	footer.add_theme_stylebox_override("panel", footer_outer_style)
	column.add_child(footer)

	# The nested one-pixel panel creates the concept's recessed inner highlight.
	var footer_outer_margin := MarginContainer.new()
	_apply_margin(footer_outer_margin, 4)
	footer.add_child(footer_outer_margin)
	var footer_inset := PanelContainer.new()
	footer_inset.name = "RecessedInset"
	var inset_background := _color("input").lightened(0.015)
	var inset_highlight := _color("border").lightened(0.2)
	footer_inset.add_theme_stylebox_override(
		"panel", _style_box(inset_background, inset_highlight, 10, 1))
	footer_outer_margin.add_child(footer_inset)
	var footer_content_margin := MarginContainer.new()
	footer_content_margin.add_theme_constant_override("margin_left", 9)
	footer_content_margin.add_theme_constant_override("margin_top", 7)
	footer_content_margin.add_theme_constant_override("margin_right", 10)
	footer_content_margin.add_theme_constant_override("margin_bottom", 7)
	footer_inset.add_child(footer_content_margin)

	var footer_row := HBoxContainer.new()
	footer_row.name = "IdentityAndBuild"
	footer_row.add_theme_constant_override("separation", 9)
	footer_content_margin.add_child(footer_row)

	var portrait_frame := PanelContainer.new()
	portrait_frame.name = "LocalPortraitFrame"
	portrait_frame.custom_minimum_size = Vector2(46, 46)
	portrait_frame.add_theme_stylebox_override(
		"panel", _style_box(_color("panel"), _color("gold").darkened(0.12), 10, 2))
	footer_row.add_child(portrait_frame)
	var portrait := LocalProfilePortrait.new()
	portrait.name = "LocalPortraitPlaceholder"
	portrait.custom_minimum_size = Vector2(42, 42)
	portrait_frame.add_child(portrait)

	var identity_column := VBoxContainer.new()
	identity_column.name = "LocalIdentity"
	identity_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_column.add_theme_constant_override("separation", 2)
	footer_row.add_child(identity_column)
	var identity_top_row := HBoxContainer.new()
	identity_top_row.add_theme_constant_override("separation", 5)
	identity_column.add_child(identity_top_row)
	_player_name_label = _make_label("PLAYER 1", 13, "text", true)
	_player_name_label.name = "DisplayName"
	_player_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	identity_top_row.add_child(_player_name_label)
	_status_dot = Panel.new()
	_status_dot.name = "ReadyIndicator"
	_status_dot.custom_minimum_size = Vector2(8, 8)
	_status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity_top_row.add_child(_status_dot)
	_connection_label = _make_label("LOCAL", 10, "positive", true)
	_connection_label.name = "ConnectionState"
	identity_top_row.add_child(_connection_label)
	_secondary_status_label = _make_label("LOCAL PROFILE / OFFLINE", 10, "muted", false)
	_secondary_status_label.name = "ProfileState"
	_secondary_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	identity_column.add_child(_secondary_status_label)

	var divider_margin := MarginContainer.new()
	divider_margin.add_theme_constant_override("margin_top", 3)
	divider_margin.add_theme_constant_override("margin_bottom", 3)
	footer_row.add_child(divider_margin)
	var footer_divider := ColorRect.new()
	footer_divider.name = "BuildDivider"
	footer_divider.custom_minimum_size.x = 1
	footer_divider.color = Color(_color("border"), 0.72)
	footer_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider_margin.add_child(footer_divider)

	var build_column := VBoxContainer.new()
	build_column.name = "BuildIdentity"
	build_column.custom_minimum_size.x = 108
	build_column.add_theme_constant_override("separation", 2)
	footer_row.add_child(build_column)
	_version_label = _make_label(_build_text(), 12, "gold", true)
	_version_label.name = "BuildVersion"
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	build_column.add_child(_version_label)
	_build_channel_label = _make_label(BUILD_CHANNEL, 10, "muted", true)
	_build_channel_label.name = "BuildChannel"
	_build_channel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	build_column.add_child(_build_channel_label)


# One line of the faux-3D logotype: huge bold face with a thick navy outline
# AND a hard drop shadow — outline + offset shadow together read as molded
# plastic depth, the closest a dynamic font gets to the concept's 3D letters.
func _make_logo_line(text: String, face_color: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font_bold:
		l.add_theme_font_override("font", _font_bold)
	l.add_theme_font_size_override("font_size", 96)
	l.add_theme_color_override("font_color", face_color)
	l.add_theme_color_override("font_outline_color", Color(0.07, 0.06, 0.14))
	l.add_theme_constant_override("outline_size", 22)
	l.add_theme_color_override("font_shadow_color", Color(0.03, 0.03, 0.08, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 8)
	l.add_theme_constant_override("shadow_outline_size", 22)
	return l


func _make_badge(text: String, color_role: String) -> PanelContainer:
	var badge := PanelContainer.new()
	var accent := _color(color_role)
	var background := accent.darkened(0.72)
	background.a = 0.94
	badge.add_theme_stylebox_override("panel", _style_box(background, accent, 10, 2, 0, 9.0))
	var label := _make_label(text, 12, color_role, true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(label)
	return badge


func _make_menu_button(text: String, callback: Callable, danger := false,
		subtitle := "", icon_kind := -1, accent := Color.TRANSPARENT) -> Button:
	var button := Button.new()
	button.name = text.to_pascal_case().replace(" ", "")
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 62)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _font_bold:
		button.add_theme_font_override("font", _font_bold)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", _color("text"))
	button.add_theme_color_override("font_hover_color", _color("input"))
	button.add_theme_color_override("font_pressed_color", _color("text"))
	button.add_theme_color_override("font_focus_color", _color("text"))
	button.add_theme_color_override("font_disabled_color", _color("muted"))
	if accent != Color.TRANSPARENT:
		_apply_toy_button_look(button, text, subtitle, icon_kind, accent)
	else:
		button.text = text
		button.add_theme_stylebox_override("normal", _button_style("danger" if danger else "normal"))
		button.add_theme_stylebox_override("hover", _button_style("hover"))
		button.add_theme_stylebox_override("pressed", _button_style("pressed"))
		button.add_theme_stylebox_override("focus", _button_style("focus"))
		button.add_theme_stylebox_override("disabled", _button_style("disabled"))
	_set_accessible_text(button, text, subtitle)
	button.set_meta("menu_selected", false)
	button.pressed.connect(callback)
	button.mouse_entered.connect(_on_button_selection_changed.bind(button))
	button.mouse_exited.connect(_on_button_selection_changed.bind(button))
	button.focus_entered.connect(_on_button_selection_changed.bind(button))
	button.focus_exited.connect(_on_button_selection_changed.bind(button))
	button.button_down.connect(_on_button_down.bind(button))
	button.button_up.connect(_on_button_up.bind(button))
	return button


func _toy_button_style(accent: Color, state: String) -> StyleBoxFlat:
	var face := accent
	var border := Color(0.055, 0.045, 0.085, 0.98)
	var shadow_size := 7
	match state:
		"selected":
			face = accent.lightened(0.08)
			border = Color(1.0, 0.91, 0.62)
		"pressed":
			face = accent.darkened(0.15)
			border = accent.darkened(0.48)
			shadow_size = 3
		"disabled":
			face = accent.darkened(0.48)
			border = accent.darkened(0.62)
			shadow_size = 2
	var style := _style_box(face, border, 16, 3, shadow_size)
	style.shadow_color = Color(0.015, 0.012, 0.035, 0.62)
	style.shadow_offset = Vector2(0.0, 5.0 if shadow_size > 3 else 2.0)
	style.corner_detail = 10
	return style


func _get_button_noise_texture() -> NoiseTexture2D:
	if _button_noise_texture != null:
		return _button_noise_texture
	var noise := FastNoiseLite.new()
	noise.seed = 8217
	noise.frequency = 0.12
	noise.fractal_octaves = 2
	_button_noise_texture = NoiseTexture2D.new()
	_button_noise_texture.noise = noise
	_button_noise_texture.width = 256
	_button_noise_texture.height = 64
	return _button_noise_texture


func _make_button_sheen_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.46, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.24),
		Color(1.0, 0.98, 0.90, 0.075),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	return texture


func _make_selection_sheen_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.48, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 0.96, 0.78, 0.34),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


# Concept-art "molded toy plastic" button: dark outer shell, saturated face,
# upper sheen, lower bevel, inset icon compartment, copy stack, and end star.
# The Button's own text stays empty; child controls ignore the mouse so the
# entire molded shape remains one reliable target.
func _apply_toy_button_look(button: Button, title: String, subtitle: String,
		icon_kind: int, accent: Color) -> void:
	button.text = ""
	button.custom_minimum_size = Vector2(0, 88)
	# Dark text on bright fills (gold), warm white on the deeper toy colors.
	var text_color: Color = Color(0.10, 0.09, 0.16) if accent.get_luminance() > 0.45 else Color(0.99, 0.97, 0.94)
	var subtitle_color := text_color
	subtitle_color.a = 0.84
	button.add_theme_stylebox_override("normal", _toy_button_style(accent, "normal"))
	button.add_theme_stylebox_override("hover", _toy_button_style(accent, "selected"))
	button.add_theme_stylebox_override("pressed", _toy_button_style(accent, "pressed"))
	button.add_theme_stylebox_override("focus", _toy_button_style(accent, "selected"))
	button.add_theme_stylebox_override("disabled", _toy_button_style(accent, "disabled"))

	var surface_layers := Control.new()
	surface_layers.name = "SurfaceLayers"
	surface_layers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface_layers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface_layers.clip_contents = true
	button.add_child(surface_layers)

	# A softly graded upper lift supplies the molded-plastic gradient without a
	# fixed-resolution button texture.
	var top_sheen := TextureRect.new()
	top_sheen.name = "UpperSheen"
	top_sheen.anchor_right = 1.0
	top_sheen.anchor_bottom = 0.58
	top_sheen.offset_left = 8.0
	top_sheen.offset_top = 5.0
	top_sheen.offset_right = -8.0
	top_sheen.texture = _make_button_sheen_texture()
	top_sheen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top_sheen.stretch_mode = TextureRect.STRETCH_SCALE
	top_sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface_layers.add_child(top_sheen)

	var texture_wear := TextureRect.new()
	texture_wear.name = "PlasticTexture"
	texture_wear.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_wear.offset_left = 7.0
	texture_wear.offset_top = 6.0
	texture_wear.offset_right = -7.0
	texture_wear.offset_bottom = -7.0
	texture_wear.texture = _get_button_noise_texture()
	texture_wear.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_wear.stretch_mode = TextureRect.STRETCH_SCALE
	texture_wear.modulate = Color(1.0, 1.0, 1.0, 0.035)
	texture_wear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface_layers.add_child(texture_wear)

	var selection_sheen := TextureRect.new()
	selection_sheen.name = "SelectionSheen"
	selection_sheen.texture = _make_selection_sheen_texture()
	selection_sheen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	selection_sheen.stretch_mode = TextureRect.STRETCH_SCALE
	selection_sheen.position = Vector2(-84.0, 6.0)
	selection_sheen.size = Vector2(76.0, 68.0)
	selection_sheen.modulate.a = 0.0
	selection_sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface_layers.add_child(selection_sheen)

	var inner_highlight := Panel.new()
	inner_highlight.name = "InnerHighlight"
	inner_highlight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner_highlight.offset_left = 4.0
	inner_highlight.offset_top = 4.0
	inner_highlight.offset_right = -4.0
	inner_highlight.offset_bottom = -4.0
	var highlight_color := accent.lightened(0.44)
	highlight_color.a = 0.78
	inner_highlight.add_theme_stylebox_override("panel", _style_box(Color.TRANSPARENT, highlight_color, 12, 1))
	inner_highlight.modulate.a = 0.78
	inner_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface_layers.add_child(inner_highlight)

	var lower_bevel := Panel.new()
	lower_bevel.name = "LowerBevel"
	lower_bevel.anchor_left = 0.0
	lower_bevel.anchor_right = 1.0
	lower_bevel.anchor_top = 1.0
	lower_bevel.anchor_bottom = 1.0
	lower_bevel.offset_left = 10.0
	lower_bevel.offset_top = -13.0
	lower_bevel.offset_right = -10.0
	lower_bevel.offset_bottom = -5.0
	lower_bevel.add_theme_stylebox_override("panel", _style_box(Color(0.01, 0.01, 0.03, 0.34), Color.TRANSPARENT, 4, 0))
	lower_bevel.modulate.a = 0.62
	lower_bevel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface_layers.add_child(lower_bevel)

	var content := MarginContainer.new()
	content.name = "ButtonContent"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("margin_left", 9)
	content.add_theme_constant_override("margin_right", 12)
	content.add_theme_constant_override("margin_top", 8)
	content.add_theme_constant_override("margin_bottom", 10)
	button.add_child(content)

	var row := HBoxContainer.new()
	row.name = "ButtonRow"
	row.add_theme_constant_override("separation", 11)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(row)

	var icon_tile := PanelContainer.new()
	icon_tile.name = "IconCompartment"
	icon_tile.custom_minimum_size = Vector2(62, 62)
	icon_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tile_color := accent.darkened(0.34)
	icon_tile.add_theme_stylebox_override("panel", _style_box(tile_color, accent.lightened(0.20), 11, 2, 2))
	var icon_center := CenterContainer.new()
	icon_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_tile.add_child(icon_center)
	var icon_art := MenuButtonIcon.new()
	icon_art.name = "ButtonIcon"
	icon_art.kind = icon_kind
	icon_art.icon_color = Color(1.0, 0.97, 0.90)
	icon_art.cutout_color = tile_color
	icon_art.custom_minimum_size = Vector2(36, 36)
	icon_center.add_child(icon_art)
	row.add_child(icon_tile)

	var divider_margin := MarginContainer.new()
	divider_margin.name = "IconDivider"
	divider_margin.custom_minimum_size.x = 2.0
	divider_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	divider_margin.add_theme_constant_override("margin_top", 7)
	divider_margin.add_theme_constant_override("margin_bottom", 7)
	var divider := ColorRect.new()
	divider.custom_minimum_size.x = 2.0
	divider.color = Color(0.03, 0.025, 0.07, 0.28)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider_margin.add_child(divider)
	row.add_child(divider_margin)

	var text_column := VBoxContainer.new()
	text_column.name = "CopyStack"
	text_column.alignment = BoxContainer.ALIGNMENT_CENTER
	text_column.add_theme_constant_override("separation", -1)
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_label := Label.new()
	title_label.name = "ButtonTitle"
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 23)
	title_label.add_theme_color_override("font_color", text_color)
	title_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.24))
	title_label.add_theme_constant_override("shadow_offset_y", 1)
	if _font_heavy:
		title_label.add_theme_font_override("font", _font_heavy)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(title_label)
	var subtitle_label := Label.new()
	subtitle_label.name = "ButtonSubtitle"
	subtitle_label.text = subtitle
	subtitle_label.add_theme_font_size_override("font_size", 13)
	subtitle_label.add_theme_color_override("font_color", subtitle_color)
	subtitle_label.add_theme_constant_override("letter_spacing", 1)
	if _font_medium:
		subtitle_label.add_theme_font_override("font", _font_medium)
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(subtitle_label)
	row.add_child(text_column)

	var star := Label.new()
	star.name = "ButtonStar"
	star.text = "★"
	star.custom_minimum_size.x = 25.0
	star.add_theme_font_size_override("font_size", 22)
	var star_color := text_color
	star_color.a = 0.68
	star.add_theme_color_override("font_color", star_color)
	star.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.28))
	star.add_theme_constant_override("shadow_offset_y", 2)
	star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font_bold:
		star.add_theme_font_override("font", _font_bold)
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(star)


func _make_dialog_button(text: String, callback: Callable, accent := false) -> Button:
	var button := _make_menu_button(text, callback)
	button.custom_minimum_size = Vector2(160, 54)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if accent:
		button.add_theme_stylebox_override("normal", _style_box(_color("gold"), _color("gold").lightened(0.14), 13, 2, 4, 16.0))
		button.add_theme_color_override("font_color", _color("input"))
	return button


func _connect_primary_focus_loop() -> void:
	if _primary_buttons.is_empty():
		return
	for index in _primary_buttons.size():
		var button := _primary_buttons[index]
		var previous := _primary_buttons[(index - 1 + _primary_buttons.size()) % _primary_buttons.size()]
		var next := _primary_buttons[(index + 1) % _primary_buttons.size()]
		button.focus_neighbor_top = button.get_path_to(previous)
		button.focus_neighbor_bottom = button.get_path_to(next)
		button.focus_previous = button.get_path_to(previous)
		button.focus_next = button.get_path_to(next)
		# Horizontal input stays on the vertical main-action rail.
		button.focus_neighbor_left = NodePath(".")
		button.focus_neighbor_right = NodePath(".")


func _configure_tab_cycle(controls: Array) -> void:
	if controls.is_empty():
		return
	for index in controls.size():
		var control := controls[index] as Control
		var previous := controls[(index - 1 + controls.size()) % controls.size()] as Control
		var next := controls[(index + 1) % controls.size()] as Control
		control.focus_previous = control.get_path_to(previous)
		control.focus_next = control.get_path_to(next)


func _configure_vertical_focus_cycle(controls: Array) -> void:
	_configure_tab_cycle(controls)
	if controls.is_empty():
		return
	for index in controls.size():
		var control := controls[index] as Control
		var previous := controls[(index - 1 + controls.size()) % controls.size()] as Control
		var next := controls[(index + 1) % controls.size()] as Control
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_neighbor_bottom = control.get_path_to(next)


# -----------------------------------------------------------------------------
# Safe, visual-only mascot display
# -----------------------------------------------------------------------------

# Merge idle + dance from the shared animation library into the cat's own
# AnimationPlayer (its glb only ships the firing animation), then loop idle
# with an occasional one-shot dance as the charm beat.
func _setup_mascot_animations(actor: Node) -> void:
	var animation_player := actor.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null:
		return
	_showcase_animation_player = animation_player
	if not animation_player.has_animation_library(""):
		animation_player.add_animation_library("", AnimationLibrary.new())
	var lib := animation_player.get_animation_library("")

	var packed = load(MASCOT_ANIM_SOURCE)
	if packed == null:
		_play_safe_mascot_idle(animation_player)
		return
	var source_instance = packed.instantiate()
	var source_player := source_instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source_player == null:
		source_instance.queue_free()
		_play_safe_mascot_idle(animation_player)
		return
	var source_list := source_player.get_animation_list()
	for entry in [["mascot_idle", MASCOT_ANIM_IDLE_INDEX, true], ["mascot_dance", MASCOT_ANIM_DANCE_INDEX, false]]:
		var idx: int = entry[1]
		if idx >= source_list.size():
			continue
		var anim := source_player.get_animation(source_list[idx]).duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR if entry[2] else Animation.LOOP_NONE
		lib.add_animation(entry[0], anim)
	source_instance.queue_free()

	if animation_player.has_animation("mascot_idle"):
		# Pure pistol-hold idle, looped. No dance interruptions — the dance clip
		# raises the gun to face height mid-move, which reads as a wrong pose in
		# still glances at the menu.
		animation_player.speed_scale = 1.0
		animation_player.set_meta("ambient_speed_scale", 1.0)
		animation_player.play("mascot_idle")
	else:
		_play_safe_mascot_idle(animation_player)

# Fallback if the shared animation library can't be loaded: play whatever the
# model itself ships (better than a frozen T-pose).
func _play_safe_mascot_idle(animation_player: AnimationPlayer) -> void:
	for animation_name in animation_player.get_animation_list():
		if animation_name == "RESET":
			continue
		animation_player.speed_scale = 0.72
		animation_player.set_meta("ambient_speed_scale", 0.72)
		animation_player.play(animation_name)
		return


# -----------------------------------------------------------------------------
# Local and online presentation panels
# -----------------------------------------------------------------------------

func _build_modal_layer() -> void:
	_modal_scrim = ColorRect.new()
	_modal_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_scrim.color = Color(0.015, 0.022, 0.055, 0.78)
	_modal_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_layer.add_child(_modal_scrim)

	_modal_center = CenterContainer.new()
	_modal_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.add_child(_modal_center)

	_local_panel = _build_local_panel()
	_modal_center.add_child(_local_panel)
	_online_panel = _build_online_panel()
	_modal_center.add_child(_online_panel)
	_local_panel.visible = false
	_online_panel.visible = false


func _build_local_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "LocalPlayPanel"
	panel.custom_minimum_size = Vector2(640, 440)
	panel.add_theme_stylebox_override("panel", _panel_style(true))
	var margin := MarginContainer.new()
	_apply_margin(margin, 30)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	column.add_child(_make_modal_header("LOCAL PLAY", "PICK A COUCH MODE"))
	var explanation := _make_label("Both routes use the existing local lobby and match setup.", 16, "muted")
	column.add_child(explanation)

	var solo := _make_menu_button("SOLO + BOTS", _on_single_pressed)
	solo.name = "SoloAndBots"
	solo.custom_minimum_size.y = 68
	_set_accessible_text(solo, "Solo plus bots", "Start a local match for one player with configurable bots")
	column.add_child(solo)
	var solo_hint := _make_label("One local player. Add and tune bots from the lobby.", 14, "muted")
	column.add_child(solo_hint)

	var split := _make_menu_button("2 PLAYER SPLITSCREEN", _on_local_pressed)
	split.name = "TwoPlayerSplitscreen"
	split.custom_minimum_size.y = 68
	_set_accessible_text(split, "Two player splitscreen", "Start a local match for two players sharing this screen")
	column.add_child(split)
	var split_hint := _make_label("Two local players share the screen. Match rules stay unchanged.", 14, "muted")
	column.add_child(split_hint)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var cancel := _make_dialog_button("CANCEL", _close_modal)
	cancel.name = "CancelLocal"
	column.add_child(cancel)
	_configure_vertical_focus_cycle([solo, split, cancel])
	return panel


func _build_online_panel() -> PanelContainer:
	var panel: PanelContainer = ONLINE_PLAY_OVERLAY_SCRIPT.new()
	panel.name = "OnlinePlayPanel"
	panel.custom_minimum_size = Vector2(1100, 760)
	panel.close_requested.connect(_close_online_overlay)
	panel.session_started.connect(_on_online_session_started)
	return panel


func _build_legacy_online_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "OnlinePlayPanel"
	panel.custom_minimum_size = Vector2(760, 630)
	panel.add_theme_stylebox_override("panel", _panel_style(true))
	var margin := MarginContainer.new()
	_apply_margin(margin, 28)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(_make_modal_header("ONLINE PLAY", "TAILSCALE SESSION"))
	_online_host_hint = _make_label("Checking Tailscale...", 14, "cyan", true)
	_online_host_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_online_host_hint)

	var host_caption := _make_label("HOST A LOBBY", 15, "gold", true)
	column.add_child(host_caption)
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 10)
	column.add_child(host_row)
	_online_host_lobby_field = _make_line_edit("Choose a lobby name", 32)
	_online_host_lobby_field.name = "HostLobbyName"
	_online_host_lobby_field.text = "%s's Lobby" % NetworkManager.local_name()
	_online_host_lobby_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_row.add_child(_online_host_lobby_field)
	_online_host_button = _make_dialog_button("HOST", _on_host_pressed, true)
	_online_host_button.name = "HostLobby"
	host_row.add_child(_online_host_button)

	var or_row := HBoxContainer.new()
	or_row.add_theme_constant_override("separation", 12)
	column.add_child(or_row)
	var line_left := HSeparator.new()
	line_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	or_row.add_child(line_left)
	or_row.add_child(_make_label("OR", 13, "muted", true))
	var line_right := HSeparator.new()
	line_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	or_row.add_child(line_right)

	var join_caption := _make_label("JOIN A LOBBY", 15, "cyan", true)
	column.add_child(join_caption)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	column.add_child(join_row)
	_online_ip_field = _make_line_edit("Lobby name (or 100.x address)", 64)
	_online_ip_field.name = "JoinLobbyNameOrIp"
	_online_ip_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_online_ip_field)
	_online_join_button = _make_dialog_button("JOIN", _on_join_pressed, true)
	_online_join_button.name = "JoinLobby"
	join_row.add_child(_online_join_button)

	var direct_hint := _make_label("Use the host's lobby name. A direct Tailscale 100.x address remains available as fallback.", 13, "muted")
	direct_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(direct_hint)

	_online_status = _make_label("", 15, "text", true)
	_online_status.name = "OnlineStatus"
	_online_status.custom_minimum_size.y = 42
	_online_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_online_status)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var cancel := _make_dialog_button("CANCEL", _on_online_back)
	cancel.name = "CancelOnline"
	column.add_child(cancel)

	_set_accessible_text(_online_host_lobby_field, "Host lobby name", "Enter the name other players will use to find this lobby")
	_set_accessible_text(_online_host_button, "Host lobby", "Create an online lobby with the entered name")
	_set_accessible_text(_online_ip_field, "Join lobby", "Enter a lobby name or direct Tailscale address")
	_set_accessible_text(_online_join_button, "Join lobby", "Connect to the entered lobby name or address")
	_configure_tab_cycle([
		_online_host_lobby_field, _online_host_button,
		_online_ip_field, _online_join_button, cancel])
	_online_host_lobby_field.focus_neighbor_top = _online_host_lobby_field.get_path_to(cancel)
	_online_host_lobby_field.focus_neighbor_bottom = _online_host_lobby_field.get_path_to(_online_ip_field)
	_online_host_lobby_field.focus_neighbor_right = _online_host_lobby_field.get_path_to(_online_host_button)
	_online_host_button.focus_neighbor_left = _online_host_button.get_path_to(_online_host_lobby_field)
	_online_host_button.focus_neighbor_top = _online_host_button.get_path_to(cancel)
	_online_host_button.focus_neighbor_bottom = _online_host_button.get_path_to(_online_join_button)
	_online_ip_field.focus_neighbor_right = _online_ip_field.get_path_to(_online_join_button)
	_online_ip_field.focus_neighbor_top = _online_ip_field.get_path_to(_online_host_lobby_field)
	_online_ip_field.focus_neighbor_bottom = _online_ip_field.get_path_to(cancel)
	_online_join_button.focus_neighbor_left = _online_join_button.get_path_to(_online_ip_field)
	_online_join_button.focus_neighbor_top = _online_join_button.get_path_to(_online_host_button)
	_online_join_button.focus_neighbor_bottom = _online_join_button.get_path_to(cancel)
	cancel.focus_neighbor_top = cancel.get_path_to(_online_ip_field)
	cancel.focus_neighbor_bottom = cancel.get_path_to(_online_host_lobby_field)
	return panel


func _make_modal_header(title: String, badge_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var title_label := _make_label(title, 34, "gold", true)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	row.add_child(_make_badge(badge_text, "cyan"))
	return row


func _make_line_edit(placeholder: String, maximum_length: int) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = maximum_length
	field.custom_minimum_size = Vector2(390, 54)
	field.focus_mode = Control.FOCUS_ALL
	_set_accessible_text(field, placeholder, "Editable text field")
	field.add_theme_font_size_override("font_size", 18)
	field.add_theme_color_override("font_color", _color("text"))
	field.add_theme_color_override("font_placeholder_color", _color("muted"))
	field.add_theme_color_override("caret_color", _color("cyan"))
	field.add_theme_color_override("selection_color", _color("cyan").darkened(0.55))
	field.add_theme_stylebox_override("normal", _line_edit_style(false))
	field.add_theme_stylebox_override("focus", _line_edit_style(true))
	if _font_medium:
		field.add_theme_font_override("font", _font_medium)
	return field


func _on_local_menu_pressed() -> void:
	AudioManager.play_click()
	_last_modal_opener = _local_menu_button
	_show_modal(_local_panel)
	var solo := _local_panel.find_child("SoloAndBots", true, false) as Control
	if solo:
		solo.grab_focus.call_deferred()


func _on_online_pressed() -> void:
	AudioManager.play_click()
	_last_modal_opener = _online_menu_button
	var overlay = _online_panel
	var capture_state := OS.get_environment("ONEGUN_UI_CAPTURE_STATE") if OS.get_environment("ONEGUN_UI_CAPTURE") != "" else ""
	overlay.open(capture_state.trim_prefix("online_"))
	_show_modal(_online_panel, overlay.initial_focus())


func _close_online_overlay() -> void:
	AudioManager.play_click()
	_close_modal()
	_refresh_connection_status()


func _on_online_session_started() -> void:
	get_tree().change_scene_to_file("res://game_setup.tscn")


func _show_modal(panel: PanelContainer, initial_focus: Control = null) -> void:
	_local_panel.visible = panel == _local_panel
	_online_panel.visible = panel == _online_panel
	_modal_layer.visible = true
	_refresh_ambient_motion()
	_modal_layer.modulate.a = 1.0
	panel.modulate.a = 1.0
	panel.scale = Vector2.ONE
	if not _reduced_motion:
		_modal_layer.modulate.a = 0.0
		panel.modulate.a = 0.0
		panel.scale = Vector2(0.975, 0.975)
		panel.pivot_offset = panel.size * 0.5
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_modal_layer, "modulate:a", 1.0, PANEL_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		tween.tween_property(panel, "modulate:a", 1.0, PANEL_DURATION * 0.75)
		tween.tween_property(panel, "scale", Vector2.ONE, PANEL_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if initial_focus:
		initial_focus.grab_focus.call_deferred()


func _close_modal() -> void:
	_modal_layer.visible = false
	_local_panel.visible = false
	_online_panel.visible = false
	_refresh_ambient_motion()
	if _last_modal_opener and is_instance_valid(_last_modal_opener):
		_last_modal_opener.grab_focus.call_deferred()


# -----------------------------------------------------------------------------
# Motion and responsive layout
# -----------------------------------------------------------------------------

func _refresh_ambient_motion() -> void:
	var modal_open := _modal_layer != null and _modal_layer.visible
	var scene_active := _ambient_app_focused and not modal_open
	var active := scene_active and not _reduced_motion
	if _pedestal_pulse_tween != null and _pedestal_pulse_tween.is_valid():
		if active:
			_pedestal_pulse_tween.play()
		else:
			_pedestal_pulse_tween.pause()
	for particles in _ambient_particles:
		if particles != null and is_instance_valid(particles):
			particles.speed_scale = 1.0 if active else 0.0
	if _showcase_animation_player != null and is_instance_valid(_showcase_animation_player):
		var idle_speed := float(_showcase_animation_player.get_meta("ambient_speed_scale", 1.0))
		_showcase_animation_player.speed_scale = idle_speed if active else 0.0
	if _showcase_viewport != null:
		_showcase_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_ONCE)
	if _background_viewport != null:
		_background_viewport.process_mode = (
			Node.PROCESS_MODE_INHERIT if scene_active else Node.PROCESS_MODE_DISABLED)
		_background_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if scene_active else SubViewport.UPDATE_ONCE)
	if _map_cycler != null and _map_cycler.has_method("set_ambient_suspended"):
		_map_cycler.set_ambient_suspended(not scene_active)

func _animate_entrance() -> void:
	if _reduced_motion:
		return
	_left_panel.modulate.a = 0.0
	_left_panel.scale = Vector2(0.985, 0.985)
	for button in _primary_buttons:
		button.modulate.a = 0.0
		button.scale = Vector2(0.97, 0.97)

	var panel_tween := create_tween().set_parallel(true)
	panel_tween.tween_property(_left_panel, "modulate:a", 1.0, PANEL_DURATION)
	panel_tween.tween_property(_left_panel, "scale", Vector2.ONE, PANEL_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	for index in _primary_buttons.size():
		var button := _primary_buttons[index]
		button.pivot_offset = button.size * 0.5
		var delay := 0.10 + BUTTON_STAGGER * float(index)
		var button_tween := create_tween().set_parallel(true)
		button_tween.tween_property(button, "modulate:a", 1.0, PANEL_DURATION * 0.8).set_delay(delay)
		button_tween.tween_property(button, "scale", Vector2.ONE, PANEL_DURATION).set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _on_button_selection_changed(button: Button) -> void:
	if button.disabled:
		return
	var selected := button.is_hovered() or button.has_focus()
	var was_selected := bool(button.get_meta("menu_selected", false))
	if selected == was_selected:
		return
	button.set_meta("menu_selected", selected)
	if selected:
		# Mouse hover and keyboard/controller focus converge here, so simultaneous
		# state changes still produce exactly one quiet selection tick.
		AudioManager.play_hover()
	else:
		_stop_button_sheen(button)
	_animate_button_selection(button, selected)


func _animate_button_selection(button: Button, selected: bool) -> void:
	var rest_position := _button_rest_position(button)
	_kill_button_tween(button, "motion_tween")
	var icon := button.find_child("ButtonIcon", true, false) as Control
	var star := button.find_child("ButtonStar", true, false) as Control
	var highlight := button.find_child("InnerHighlight", true, false) as Control
	var lower_bevel := button.find_child("LowerBevel", true, false) as Control
	button.pivot_offset = button.size * 0.5
	if icon:
		icon.pivot_offset = icon.size * 0.5
	if star:
		star.pivot_offset = star.size * 0.5

	if _reduced_motion:
		button.scale = Vector2.ONE
		button.position = rest_position
		if icon:
			icon.scale = Vector2.ONE
			icon.rotation_degrees = 0.0
		if star:
			star.scale = Vector2.ONE
			star.rotation_degrees = 0.0
		if highlight:
			highlight.modulate.a = 1.0 if selected else 0.78
		if lower_bevel:
			lower_bevel.modulate.a = 0.62
		return

	var target_scale := Vector2(HOVER_SCALE, HOVER_SCALE) if selected else Vector2.ONE
	var target_position := rest_position + Vector2(0.0, -HOVER_RISE if selected else 0.0)
	var tween := create_tween().set_parallel(true)
	button.set_meta("motion_tween", tween)
	tween.tween_property(button, "scale", target_scale, HOVER_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK if selected else Tween.TRANS_SINE)
	tween.tween_property(button, "position", target_position, HOVER_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	if icon:
		tween.tween_property(icon, "scale", Vector2(ICON_HOVER_SCALE, ICON_HOVER_SCALE) if selected else Vector2.ONE, HOVER_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(icon, "rotation_degrees", -3.0 if selected else 0.0, HOVER_DURATION).set_ease(Tween.EASE_OUT)
	if star:
		tween.tween_property(star, "scale", Vector2(STAR_HOVER_SCALE, STAR_HOVER_SCALE) if selected else Vector2.ONE, HOVER_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(star, "rotation_degrees", 7.0 if selected else 0.0, HOVER_DURATION).set_ease(Tween.EASE_OUT)
	if highlight:
		tween.tween_property(highlight, "modulate:a", 1.0 if selected else 0.78, HOVER_DURATION)
	if lower_bevel:
		tween.tween_property(lower_bevel, "modulate:a", 0.62, HOVER_DURATION)
	if selected:
		_play_button_sheen(button)


func _play_button_sheen(button: Button) -> void:
	var sheen := button.find_child("SelectionSheen", true, false) as TextureRect
	if sheen == null:
		return
	_kill_button_tween(button, "sheen_tween")
	var sheen_width := clampf(button.size.x * 0.18, 68.0, 92.0)
	sheen.size = Vector2(sheen_width, maxf(button.size.y - 12.0, 1.0))
	sheen.position = Vector2(-sheen_width - 8.0, 6.0)
	sheen.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	button.set_meta("sheen_tween", tween)
	tween.tween_property(sheen, "position:x", button.size.x + 8.0, 0.46).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(sheen, "modulate:a", 0.34, 0.10).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(sheen, "modulate:a", 0.0, 0.12).set_ease(Tween.EASE_IN)


func _stop_button_sheen(button: Button, immediate := false) -> void:
	var sheen := button.find_child("SelectionSheen", true, false) as TextureRect
	if sheen == null:
		return
	_kill_button_tween(button, "sheen_tween")
	if immediate or _reduced_motion:
		sheen.modulate.a = 0.0
		return
	var tween := create_tween()
	button.set_meta("sheen_tween", tween)
	tween.tween_property(sheen, "modulate:a", 0.0, 0.08).set_ease(Tween.EASE_IN)


func _on_button_down(button: Button) -> void:
	if button.disabled or _reduced_motion:
		return
	_stop_button_sheen(button, true)
	var rest_position := _button_rest_position(button)
	_kill_button_tween(button, "motion_tween")
	var icon := button.find_child("ButtonIcon", true, false) as Control
	var star := button.find_child("ButtonStar", true, false) as Control
	var highlight := button.find_child("InnerHighlight", true, false) as Control
	var lower_bevel := button.find_child("LowerBevel", true, false) as Control
	var tween := create_tween().set_parallel(true)
	button.set_meta("motion_tween", tween)
	tween.tween_property(button, "scale", Vector2(PRESSED_SCALE, PRESSED_SCALE), PRESS_DURATION).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "position", rest_position + Vector2(0.0, 2.0), PRESS_DURATION).set_ease(Tween.EASE_OUT)
	if icon:
		tween.tween_property(icon, "scale", Vector2(0.94, 0.94), PRESS_DURATION).set_ease(Tween.EASE_OUT)
		tween.tween_property(icon, "rotation_degrees", 0.0, PRESS_DURATION)
	if star:
		tween.tween_property(star, "scale", Vector2(0.94, 0.94), PRESS_DURATION).set_ease(Tween.EASE_OUT)
		tween.tween_property(star, "rotation_degrees", 0.0, PRESS_DURATION)
	if highlight:
		tween.tween_property(highlight, "modulate:a", 0.64, PRESS_DURATION)
	if lower_bevel:
		tween.tween_property(lower_bevel, "modulate:a", 1.0, PRESS_DURATION)


func _on_button_up(button: Button) -> void:
	if button.disabled or _reduced_motion:
		return
	var selected := button.is_hovered() or button.has_focus()
	var rest_position := _button_rest_position(button)
	_kill_button_tween(button, "motion_tween")
	var icon := button.find_child("ButtonIcon", true, false) as Control
	var star := button.find_child("ButtonStar", true, false) as Control
	var highlight := button.find_child("InnerHighlight", true, false) as Control
	var lower_bevel := button.find_child("LowerBevel", true, false) as Control
	var release_duration := 0.14
	var tween := create_tween().set_parallel(true)
	button.set_meta("motion_tween", tween)
	tween.tween_property(button, "scale", Vector2(HOVER_SCALE, HOVER_SCALE) if selected else Vector2.ONE, release_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(button, "position", rest_position + Vector2(0.0, -HOVER_RISE if selected else 0.0), release_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if icon:
		tween.tween_property(icon, "scale", Vector2(ICON_HOVER_SCALE, ICON_HOVER_SCALE) if selected else Vector2.ONE, release_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(icon, "rotation_degrees", -3.0 if selected else 0.0, release_duration)
	if star:
		tween.tween_property(star, "scale", Vector2(STAR_HOVER_SCALE, STAR_HOVER_SCALE) if selected else Vector2.ONE, release_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(star, "rotation_degrees", 7.0 if selected else 0.0, release_duration)
	if highlight:
		tween.tween_property(highlight, "modulate:a", 1.0 if selected else 0.78, release_duration)
	if lower_bevel:
		tween.tween_property(lower_bevel, "modulate:a", 0.62, release_duration)


func _button_rest_position(button: Button) -> Vector2:
	if not button.has_meta("rest_position"):
		button.set_meta("rest_position", button.position)
	return button.get_meta("rest_position")


func _kill_button_tween(button: Button, meta_name: StringName) -> void:
	var existing = button.get_meta(meta_name, null)
	if existing is Tween and existing.is_valid():
		existing.kill()


func _advance_tagline() -> void:
	if TAGLINES.size() <= 1 or _tagline_label == null:
		return
	_tagline_index = wrapi(_tagline_index + 1, 0, TAGLINES.size())
	if _reduced_motion:
		_set_tagline(TAGLINES[_tagline_index])
		return
	if _tagline_tween != null and _tagline_tween.is_valid():
		_tagline_tween.kill()
	_tagline_tween = create_tween()
	_tagline_tween.tween_property(
		_tagline_label, "modulate:a", 0.0, TAGLINE_FADE_DURATION * 0.45
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	_tagline_tween.tween_callback(_set_tagline.bind(TAGLINES[_tagline_index]))
	_tagline_tween.tween_property(
		_tagline_label, "modulate:a", 1.0, TAGLINE_FADE_DURATION * 0.55
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


func _set_tagline(text: String) -> void:
	_tagline_label.text = text
	_refresh_tagline_typography.call_deferred()


func _refresh_tagline_typography() -> void:
	if _tagline_label == null or _tagline_label.size.x <= 0.0:
		return
	var viewport_size := get_viewport_rect().size
	var compact := viewport_size.y <= 760.0 or viewport_size.x < 1120.0
	var font_size := 13 if compact else 15
	# Prefer a readable two-line lockup over shrinking long copy into fine print.
	var minimum_size := 11 if compact else 14
	var font := _tagline_label.get_theme_font("font")
	var available_width := maxf(_tagline_label.size.x - 8.0, 1.0)
	while font_size > minimum_size:
		var text_width := font.get_string_size(
			_tagline_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		).x + maxf(float(_tagline_label.text.length() - 1), 0.0)
		if text_width <= available_width:
			break
		font_size -= 1
	_tagline_label.add_theme_font_size_override("font_size", font_size)


func _apply_responsive_layout() -> void:
	if _left_panel == null:
		return
	var viewport_size := get_viewport_rect().size
	var compact_height := viewport_size.y <= 760.0
	var layout_scale := clampf(viewport_size.y / 1080.0, 0.667, 1.333)
	var preview_size := _preview_render_size(viewport_size)
	if _background_viewport != null and _background_viewport.size != preview_size:
		_background_viewport.size = preview_size
	if _showcase_viewport != null and _showcase_viewport.size != preview_size:
		_showcase_viewport.size = preview_size

	# The cabinet rect is applied after its responsive child minimums below.
	# Applying it before those values settle makes PanelContainer preserve the
	# larger desktop minimum when the window first opens at 720p.
	if _guides != null:
		_guides.queue_redraw()

	var cabinet_inner := _left_panel.find_child("CabinetContentMargin", true, false) as MarginContainer
	var cabinet_column := _left_panel.find_child("CabinetColumn", true, false) as VBoxContainer
	var navigation := _left_panel.find_child("ButtonList", true, false) as VBoxContainer
	var footer := _left_panel.find_child("StatusFooter", true, false) as Control
	var portrait := _left_panel.find_child("LocalPortraitFrame", true, false) as Control
	var build_identity := _left_panel.find_child("BuildIdentity", true, false) as Control
	var ribbon_holder := _logo_stack.find_child("TaglineRibbon", true, false) as Control if _logo_stack else null
	var tagline_row := _logo_stack.find_child("TaglineCarousel", true, false) as Control if _logo_stack else null

	var inner_margin := 14 if compact_height else clampi(roundi(26.0 * layout_scale), 22, 30)
	if cabinet_inner != null:
		_apply_margin(cabinet_inner, inner_margin)
	if cabinet_column != null:
		cabinet_column.add_theme_constant_override(
			"separation", 6 if compact_height else clampi(roundi(12.0 * layout_scale), 10, 12))
	if navigation != null:
		navigation.add_theme_constant_override(
			"separation", 6 if compact_height else clampi(roundi(10.0 * layout_scale), 8, 12))

	var logo_size := clampi(roundi(96.0 * layout_scale), 68, 108)
	if _logo_stack != null:
		_logo_stack.custom_minimum_size.y = (
			230.0 if compact_height else clampf(viewport_size.y * 0.36, 300.0, 520.0))
	var ribbon_height := clampf(120.0 * layout_scale, 82.0, 140.0)
	if ribbon_holder != null:
		ribbon_holder.offset_top = -ribbon_height
	if tagline_row != null:
		tagline_row.offset_left = 48.0 * layout_scale
		tagline_row.offset_right = -48.0 * layout_scale
		tagline_row.offset_bottom = -18.0 * layout_scale
	if _logo_image != null:
		_logo_image.offset_bottom = -(ribbon_height - 8.0 * layout_scale)
	_title_label.add_theme_font_size_override("font_size", logo_size)
	if _title_label2 != null:
		_title_label2.add_theme_font_size_override("font_size", logo_size)
	_refresh_tagline_typography.call_deferred()

	var button_height := clampf(88.0 * layout_scale, 58.0, 96.0)
	var button_title_size := clampi(roundi(23.0 * layout_scale), 18, 24)
	var button_subtitle_size := clampi(roundi(13.0 * layout_scale), 10, 14)
	var icon_size := clampf(62.0 * layout_scale, 46.0, 66.0)
	var star_size := clampi(roundi(22.0 * layout_scale), 18, 24)
	for button in _primary_buttons:
		button.custom_minimum_size.y = button_height
		var button_title := button.find_child("ButtonTitle", true, false) as Label
		var button_subtitle := button.find_child("ButtonSubtitle", true, false) as Label
		var icon_compartment := button.find_child("IconCompartment", true, false) as Control
		var button_star := button.find_child("ButtonStar", true, false) as Label
		if button_title:
			button_title.add_theme_font_size_override("font_size", button_title_size)
		if button_subtitle:
			button_subtitle.add_theme_font_size_override("font_size", button_subtitle_size)
		if icon_compartment:
			icon_compartment.custom_minimum_size = Vector2(icon_size, icon_size)
		if button_star:
			button_star.add_theme_font_size_override("font_size", star_size)

	if footer != null:
		footer.custom_minimum_size.y = clampf(70.0 * layout_scale, 64.0, 82.0)
	if portrait != null:
		var portrait_size := clampf(46.0 * layout_scale, 42.0, 54.0)
		portrait.custom_minimum_size = Vector2(portrait_size, portrait_size)
	if build_identity != null:
		build_identity.custom_minimum_size.x = clampf(108.0 * layout_scale, 100.0, 125.0)
	if _player_name_label != null:
		_player_name_label.add_theme_font_size_override(
			"font_size", clampi(roundi(13.0 * layout_scale), 12, 15))
	if _connection_label != null:
		_connection_label.add_theme_font_size_override(
			"font_size", clampi(roundi(10.0 * layout_scale), 10, 12))
	if _secondary_status_label != null:
		_secondary_status_label.add_theme_font_size_override(
			"font_size", clampi(roundi(10.0 * layout_scale), 10, 12))
		if compact_height and _secondary_status_label.text == "LOCAL PROFILE / NETWORK READY":
			_secondary_status_label.text = "LOCAL PROFILE / READY"
		elif not compact_height and _secondary_status_label.text == "LOCAL PROFILE / READY":
			_secondary_status_label.text = "LOCAL PROFILE / NETWORK READY"
	if _version_label != null:
		_version_label.add_theme_font_size_override(
			"font_size", clampi(roundi(12.0 * layout_scale), 11, 14))
	if _build_channel_label != null:
		_build_channel_label.add_theme_font_size_override(
			"font_size", clampi(roundi(10.0 * layout_scale), 10, 12))
	_apply_cabinet_rect()
	call_deferred("_apply_cabinet_rect")
	if _local_panel:
		_local_panel.custom_minimum_size = Vector2(
			minf(640.0, viewport_size.x - 44.0),
			minf(440.0, viewport_size.y - 44.0)
		)
	if _online_panel:
		_online_panel.custom_minimum_size = Vector2(
			minf(1100.0, viewport_size.x - 44.0),
			minf(760.0, viewport_size.y - 36.0)
		)
	call_deferred("_rebase_button_positions_after_layout")


func _apply_cabinet_rect() -> void:
	if _left_panel == null:
		return
	var viewport_size := get_viewport_rect().size
	var safe := _safe_region(viewport_size)
	_left_panel.anchor_left = 0.0
	_left_panel.anchor_top = 0.0
	_left_panel.anchor_right = 0.0
	_left_panel.anchor_bottom = 0.0
	_left_panel.position = Vector2(
		safe.position.x + safe.size.x * CABINET_X,
		safe.position.y + safe.size.y * CABINET_Y)
	_left_panel.size = Vector2(safe.size.x * CABINET_W, safe.size.y * CABINET_H)


func _rebase_button_positions_after_layout() -> void:
	for button in _primary_buttons:
		var rest_position := button.position
		button.set_meta("rest_position", rest_position)
		if bool(button.get_meta("menu_selected", false)) and not _reduced_motion:
			button.position = rest_position + Vector2(0.0, -HOVER_RISE)


func _reduced_motion_enabled() -> bool:
	# Future-facing hook: no player-facing setting exists yet, so an absent key
	# intentionally resolves to false without adding a new settings feature here.
	if PlayerPrefs and PlayerPrefs.has_method("get_setting"):
		var preference = PlayerPrefs.get_setting("reduced_motion")
		if preference != null:
			return bool(preference)
	return false


func _capture_name() -> String:
	var state := OS.get_environment("ONEGUN_UI_CAPTURE_STATE")
	return state if state.begins_with("online_") or state.begins_with("settings_") or state.begins_with("crosshair_") else "main_menu"


func _bootstrap_lobby_capture() -> void:
	var state := OS.get_environment("ONEGUN_UI_CAPTURE_STATE")
	if state == "lobby_host":
		GameConfig.set_bot_count(2)
		if NetworkManager.host_game(NetworkManager.DEFAULT_PORT, "Sundown Showdown",
				{"privacy": "public", "share_code": "SUN555", "max_players": 10}):
			get_tree().change_scene_to_file("res://game_setup.tscn")
	elif state == "lobby_guest":
		if NetworkManager.join_game("127.0.0.1", NetworkManager.DEFAULT_PORT):
			get_tree().change_scene_to_file("res://game_setup.tscn")


func _build_text() -> String:
	var version := String(ProjectSettings.get_setting("application/config/version", "0.0.1"))
	return "BUILD v%s" % version


func _on_player_preference_changed(key: String, _value: Variant) -> void:
	if key == "player_name":
		_refresh_connection_status()
	elif key == "reduced_motion":
		_reduced_motion = _reduced_motion_enabled()
		_refresh_ambient_motion()


func _set_footer_status_dot(color: Color) -> void:
	if _status_dot == null:
		return
	var dot_style := _style_box(color, color.lightened(0.12), 8, 1, 2)
	dot_style.shadow_color = Color(color, 0.36)
	_status_dot.add_theme_stylebox_override("panel", dot_style)


func _refresh_connection_status() -> void:
	if _connection_label == null or _player_name_label == null:
		return
	_player_name_label.text = NetworkManager.local_name().to_upper()
	if _version_label != null:
		_version_label.text = _build_text()
	if NetworkManager.is_online():
		_connection_label.text = "ONLINE"
		_connection_label.add_theme_color_override("font_color", _color("positive"))
		_secondary_status_label.text = "CONNECTED PROFILE"
		_set_footer_status_dot(_color("positive"))
		return
	# Packet §10: never display an IP address in the menu. Reachability only —
	# the host's shareable address lives in the Online Play panel where it's
	# functionally required.
	var tailscale_ip := NetworkManager.get_tailscale_ip()
	if tailscale_ip != "":
		_connection_label.text = "READY"
		_connection_label.add_theme_color_override("font_color", _color("positive"))
		_secondary_status_label.text = "LOCAL PROFILE / NETWORK READY"
	else:
		_connection_label.text = "LOCAL"
		_connection_label.add_theme_color_override("font_color", _color("positive"))
		_secondary_status_label.text = "LOCAL PROFILE / OFFLINE"
	_set_footer_status_dot(_color("positive"))


# -----------------------------------------------------------------------------
# Existing scene and networking callbacks (behavior preserved)
# -----------------------------------------------------------------------------

func _on_quit_pressed() -> void:
	AudioManager.play_click()
	get_tree().quit()


func _on_single_pressed() -> void:
	AudioManager.play_click()
	if not GameConfig.lobby_settings_dirty:
		GameConfig.reset_match_settings_to_defaults()
	GameConfig.split_screen_enabled = false
	get_tree().change_scene_to_file("res://game_setup.tscn")


func _on_local_pressed() -> void:
	AudioManager.play_click()
	if not GameConfig.lobby_settings_dirty:
		GameConfig.reset_match_settings_to_defaults()
	GameConfig.split_screen_enabled = true
	get_tree().change_scene_to_file("res://game_setup.tscn")


func _on_player_settings_pressed() -> void:
	AudioManager.play_click()
	if _player_settings_overlay != null:
		return
	_player_settings_overlay = preload("res://player_settings.tscn").instantiate()
	_player_settings_overlay.is_overlay = true
	_player_settings_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player_settings_overlay)
	_player_settings_overlay.settings_closed.connect(_close_player_settings_overlay)


func _on_combat_lab_pressed() -> void:
	AudioManager.play_click()
	get_tree().change_scene_to_file("res://tools/combat_lab.tscn")


func _close_player_settings_overlay() -> void:
	if _player_settings_overlay == null:
		return
	_player_settings_overlay.queue_free()
	_player_settings_overlay = null


func _on_online_back() -> void:
	var overlay = _online_panel
	if overlay != null:
		overlay.handle_cancel()
	else:
		_close_online_overlay()


func _on_host_pressed() -> void:
	AudioManager.play_click()
	var requested_name := _online_host_lobby_field.text.strip_edges()
	if requested_name == "":
		_set_online_status("Choose a lobby name first.", true)
		_online_host_lobby_field.grab_focus()
		return
	if not NetworkManager.host_game(NetworkManager.DEFAULT_PORT, requested_name):
		_set_online_status("Failed to host. Check port 24545 and firewall access.", true)
		return
	if not GameConfig.lobby_settings_dirty:
		GameConfig.reset_match_settings_to_defaults()
	GameConfig.split_screen_enabled = false
	get_tree().change_scene_to_file("res://game_setup.tscn")


func _on_join_pressed() -> void:
	AudioManager.play_click()
	var lobby_or_address := _online_ip_field.text.strip_edges()
	if lobby_or_address == "":
		_set_online_status("Enter a lobby name first.", true)
		_online_ip_field.grab_focus()
		return
	if not NetworkManager.connection_succeeded.is_connected(_on_join_ok):
		NetworkManager.connection_succeeded.connect(_on_join_ok, CONNECT_ONE_SHOT)
	if not NetworkManager.connection_failed.is_connected(_on_join_fail):
		NetworkManager.connection_failed.connect(_on_join_fail, CONNECT_ONE_SHOT)
	if not NetworkManager.lobby_discovery_failed.is_connected(_on_lobby_discovery_fail):
		NetworkManager.lobby_discovery_failed.connect(_on_lobby_discovery_fail, CONNECT_ONE_SHOT)
	if lobby_or_address.begins_with("100.") or lobby_or_address.begins_with("127."):
		_set_online_status("CONNECTING TO %s..." % lobby_or_address)
		if not NetworkManager.join_game(lobby_or_address):
			_set_online_status("Couldn't start the direct connection.", true)
	else:
		_set_online_status("SEARCHING TAILSCALE FOR '%s'..." % lobby_or_address)
		if not NetworkManager.join_lobby_by_name(lobby_or_address):
			_set_online_status("Enter a valid lobby name.", true)


func _on_join_ok() -> void:
	if NetworkManager.connection_failed.is_connected(_on_join_fail):
		NetworkManager.connection_failed.disconnect(_on_join_fail)
	if NetworkManager.lobby_discovery_failed.is_connected(_on_lobby_discovery_fail):
		NetworkManager.lobby_discovery_failed.disconnect(_on_lobby_discovery_fail)
	GameConfig.split_screen_enabled = false
	get_tree().change_scene_to_file("res://game_setup.tscn")


func _on_join_fail() -> void:
	if NetworkManager.connection_succeeded.is_connected(_on_join_ok):
		NetworkManager.connection_succeeded.disconnect(_on_join_ok)
	if NetworkManager.lobby_discovery_failed.is_connected(_on_lobby_discovery_fail):
		NetworkManager.lobby_discovery_failed.disconnect(_on_lobby_discovery_fail)
	_set_online_status("Connection failed. Check Tailscale and confirm the host clicked Host.", true)


func _on_lobby_discovery_fail(message: String) -> void:
	if NetworkManager.connection_succeeded.is_connected(_on_join_ok):
		NetworkManager.connection_succeeded.disconnect(_on_join_ok)
	if NetworkManager.connection_failed.is_connected(_on_join_fail):
		NetworkManager.connection_failed.disconnect(_on_join_fail)
	_set_online_status(message, true)


func _set_online_status(message: String, is_error := false) -> void:
	if _online_status == null:
		return
	_online_status.text = message
	_online_status.add_theme_color_override("font_color", _color("danger" if is_error else "cyan"))
