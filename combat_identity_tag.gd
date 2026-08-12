extends Node3D

const ProtectionIconFactory = preload("res://protection_icon_factory.gd")
const VisibilityRules = preload("res://combat_visibility.gd")
const CombatOutline = preload("res://combat_outline.gd")

var target = null
var viewer = null
var _name: Label3D
var _indicator: Label3D
var _extra_life: Sprite3D
var _sticky_hands: Sprite3D
var _gun_arrow: Label3D
var _all_gun_hearts: Label3D
var _gun_pulse := 0.0
var _was_gun_holder := false

func setup(target_actor, viewing_player, render_layer: int) -> void:
	target = target_actor
	viewer = viewing_player
	var layer_mask := 1 << (render_layer - 1)
	_name = _label(Vector3(0.0, 2.45, 0.0), false, layer_mask)
	_indicator = _label(Vector3(0.0, 2.7, 0.0), true, layer_mask)
	_extra_life = _icon("res://UI/icons/extra_life.svg", Vector3(-0.28, 2.88, 0.0), layer_mask)
	_sticky_hands = _icon("res://UI/icons/sticky_hands.svg", Vector3(0.28, 2.88, 0.0), layer_mask)
	_gun_arrow = _label(Vector3(0.0, 3.18, 0.0), false, layer_mask)
	_all_gun_hearts = _label(Vector3(0.0, 3.18, 0.0), false, layer_mask)
	_all_gun_hearts.name = "AllGunWorldHearts"
	_all_gun_hearts.font_size = 34
	_all_gun_hearts.outline_size = 9
	_all_gun_hearts.modulate = Color(1.0, 0.16, 0.24)
	_all_gun_hearts.visible = false
	_gun_arrow.text = "\u25bc  GUN HOLDER  \u25bc"
	_gun_arrow.font_size = CombatOutline.GUN_HOLDER_MARKER_FONT_SIZE
	_gun_arrow.outline_size = CombatOutline.GUN_HOLDER_MARKER_OUTLINE_SIZE
	_gun_arrow.modulate = Color(1.0, 0.08, 0.08)
	_update_tag()

func _label(at: Vector3, through_walls: bool, layer_mask: int) -> Label3D:
	var label := Label3D.new()
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = through_walls
	label.outline_size = 7
	label.layers = layer_mask
	label.visibility_range_end = 50.0
	label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(label)
	return label

func _icon(texture_path: String, at: Vector3, layer_mask: int) -> Sprite3D:
	var icon := Sprite3D.new()
	icon.texture = ProtectionIconFactory.texture_from_svg(texture_path)
	icon.position = at
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = false
	icon.pixel_size = 0.0025
	icon.layers = layer_mask
	icon.visibility_range_end = 50.0
	icon.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(icon)
	return icon

func _process(delta: float) -> void:
	_gun_pulse += delta * 5.0
	_update_tag()

func _update_tag() -> void:
	if _all_gun_hearts != null:
		_all_gun_hearts.visible = false
	if _gun_arrow != null:
		_gun_arrow.visible = false
	if target == null or viewer == null or not is_instance_valid(target) or not is_instance_valid(viewer):
		visible = false
		return
	var eliminated := bool(target.get("is_eliminated"))
	visible = not eliminated
	if eliminated:
		return
	var source = target.get("owner_player") if target.is_in_group("combat_decoy") else target
	if source == null:
		source = target
	var is_gun_holder := bool(source.get("holding_gun"))
	if is_gun_holder and not _was_gun_holder:
		_gun_pulse = 0.0
	_was_gun_holder = is_gun_holder
	var target_team := int(target.get("team_id"))
	var friendly: bool = source == viewer or (GameConfig.teams_enabled and int(viewer.get("team_id")) >= 0
		and int(viewer.get("team_id")) == target_team)
	var smoke_visible := friendly or VisibilityRules.has_visual_contact(viewer, target, false)
	visible = visible and smoke_visible
	if not visible:
		return
	_name.no_depth_test = friendly
	_name.text = target.get_display_name()
	_name.font_size = 32 if friendly else 38
	_name.modulate = Color(0.25, 0.85, 1.0) if friendly else Color(1.0, 0.2, 0.2)
	_indicator.text = "◆  DECOY" if friendly and target.is_in_group("combat_decoy") else ("◆" if friendly else "")
	_indicator.font_size = 22
	_indicator.modulate = Color(0.2, 0.95, 1.0)
	var icon_size := clampf(float(PlayerPrefs.get_setting("protection_icon_size")), 0.5, 2.0)
	_extra_life.scale = Vector3.ONE * icon_size
	_sticky_hands.scale = Vector3.ONE * icon_size
	_extra_life.modulate = _pref_color("extra_life_icon_color", Color(1.0, 0.72, 0.18))
	_sticky_hands.modulate = _pref_color("sticky_hands_icon_color", Color(0.2, 1.0, 0.35))
	_extra_life.visible = bool(source.get("second_wind_ready"))
	_sticky_hands.visible = int(source.get("melee_disarm_shields")) > 0
	_all_gun_hearts.visible = GameConfig.game_mode == GameConfig.MODE_ALL_GUN
	if _all_gun_hearts.visible:
		var hearts := clampi(int(source.get("all_gun_hearts")), 0, GameConfig.ALL_GUN_MAX_HEARTS)
		var symbols: Array[String] = []
		for index in GameConfig.ALL_GUN_MAX_HEARTS:
			symbols.append("\u2665" if index < hearts else "\u2661")
		_all_gun_hearts.text = " ".join(symbols)
	_gun_arrow.visible = GameConfig.game_mode == GameConfig.MODE_ONE_GUN \
		and source != viewer and bool(source.get("holding_gun")) \
		and VisibilityRules.has_visual_contact(viewer, target, true)
	if _gun_arrow.visible:
		var pulse := 1.0 + sin(_gun_pulse) \
			* CombatOutline.GUN_HOLDER_MARKER_PULSE_AMOUNT
		_gun_arrow.scale = Vector3.ONE * pulse
		_gun_arrow.modulate = Color(1.0, 0.12 + (sin(_gun_pulse) + 1.0) * 0.12, 0.01)

func _pref_color(key: String, fallback: Color) -> Color:
	var value = PlayerPrefs.get_setting(key)
	if value is Array and value.size() >= 4:
		return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return fallback
