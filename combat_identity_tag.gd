extends Node3D

const ProtectionIconFactory = preload("res://protection_icon_factory.gd")

var target = null
var viewer = null
var _name: Label3D
var _indicator: Label3D
var _extra_life: Sprite3D
var _sticky_hands: Sprite3D

func setup(target_actor, viewing_player, render_layer: int) -> void:
	target = target_actor
	viewer = viewing_player
	var layer_mask := 1 << (render_layer - 1)
	_name = _label(Vector3(0.0, 2.45, 0.0), false, layer_mask)
	_indicator = _label(Vector3(0.0, 2.7, 0.0), true, layer_mask)
	_extra_life = _icon("res://UI/icons/extra_life.svg", Vector3(-0.28, 2.88, 0.0), layer_mask)
	_sticky_hands = _icon("res://UI/icons/sticky_hands.svg", Vector3(0.28, 2.88, 0.0), layer_mask)
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

func _process(_delta: float) -> void:
	_update_tag()

func _update_tag() -> void:
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
	var target_team := int(target.get("team_id"))
	var friendly: bool = source == viewer or (GameConfig.teams_enabled and int(viewer.get("team_id")) >= 0
		and int(viewer.get("team_id")) == target_team)
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

func _pref_color(key: String, fallback: Color) -> Color:
	var value = PlayerPrefs.get_setting(key)
	if value is Array and value.size() >= 4:
		return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return fallback
