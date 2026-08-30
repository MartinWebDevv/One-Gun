class_name FriendsQuickAccessOrb
extends Button

const PORTRAIT_SCRIPT = preload("res://UI/components/character_portrait.gd")

var _portrait: TextureRect
var _hover_label: Label
var _activity_badge: PanelContainer
var _activity_label: Label
var _online_badge: PanelContainer
var _online_label: Label
var _active := false


func _ready() -> void:
	name = "FriendsQuickAccessOrb"
	custom_minimum_size = Vector2(104.0, 104.0)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Open Friends, requests, online players, and lobby invitations"
	clip_contents = false
	_build_visuals()
	_apply_styles()
	mouse_entered.connect(func() -> void: _set_active(true))
	mouse_exited.connect(func() -> void: _set_active(false))
	focus_entered.connect(func() -> void: _set_active(true))
	focus_exited.connect(func() -> void: _set_active(false))
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	pivot_offset = size * 0.5
	refresh_counts()


func refresh_counts(_snapshot: Dictionary = {}) -> void:
	if _activity_label == null:
		return
	var attention_count := SocialManager.incoming_requests().size() \
		+ SocialManager.invites().size()
	_activity_badge.visible = attention_count > 0
	_activity_label.text = str(mini(attention_count, 9)) if attention_count < 10 else "9+"
	var online_count := SocialManager.online_friend_count()
	_online_badge.visible = online_count > 0
	_online_label.text = str(mini(online_count, 99))


func _build_visuals() -> void:
	_portrait = PORTRAIT_SCRIPT.new()
	_portrait.name = "BlueMaleMascotPortrait"
	_portrait.set_appearance("blue", "male")
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.offset_left = 13.0
	_portrait.offset_top = 13.0
	_portrait.offset_right = -13.0
	_portrait.offset_bottom = -13.0
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)

	_hover_label = OneGunUI.make_heading("FRIENDS", 19, "text_bright")
	_hover_label.name = "FriendsHoverLabel"
	_hover_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hover_label.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.12, 0.96))
	_hover_label.add_theme_constant_override("outline_size", 7)
	_hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_label.modulate.a = 0.0
	add_child(_hover_label)

	_activity_badge = _make_badge("red")
	_activity_badge.name = "FriendsAttentionBadge"
	_activity_badge.anchor_left = 1.0
	_activity_badge.anchor_top = 0.0
	_activity_badge.anchor_right = 1.0
	_activity_badge.anchor_bottom = 0.0
	_activity_badge.offset_left = -35.0
	_activity_badge.offset_top = -3.0
	_activity_badge.offset_right = 3.0
	_activity_badge.offset_bottom = 35.0
	_activity_label = _activity_badge.get_child(0) as Label
	add_child(_activity_badge)

	_online_badge = _make_badge("green")
	_online_badge.name = "FriendsOnlineBadge"
	_online_badge.anchor_left = 1.0
	_online_badge.anchor_top = 1.0
	_online_badge.anchor_right = 1.0
	_online_badge.anchor_bottom = 1.0
	_online_badge.offset_left = -35.0
	_online_badge.offset_top = -35.0
	_online_badge.offset_right = 3.0
	_online_badge.offset_bottom = 3.0
	_online_label = _online_badge.get_child(0) as Label
	add_child(_online_badge)


func _make_badge(role: String) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", OneGunUI.style_box(
		OneGunUI.color(role).darkened(0.22), OneGunUI.color("text_bright"),
		19, 2, 2, 5.0))
	var label := OneGunUI.make_heading("0", 14,
		"ink" if role == "green" else "text_bright")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	return badge


func _apply_styles() -> void:
	var normal := OneGunUI.style_box(
		Color(0.018, 0.055, 0.13, 0.98), Color(OneGunUI.color("cyan"), 0.90),
		64, 3, 7, 0.0)
	var hover := OneGunUI.style_box(
		Color(0.08, 0.025, 0.14, 0.98), OneGunUI.color("gold"),
		64, 4, 10, 0.0)
	var pressed_style := OneGunUI.style_box(
		Color(0.008, 0.018, 0.055, 0.98), OneGunUI.color("gold"),
		64, 4, 3, 0.0)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed_style)
	add_theme_stylebox_override("focus", OneGunUI.focus_ring(hover))
	add_theme_stylebox_override("disabled", normal)


func _set_active(value: bool) -> void:
	if _active == value:
		return
	_active = value
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_portrait, "modulate:a", 0.32 if value else 1.0, 0.14)
	tween.tween_property(_hover_label, "modulate:a", 1.0 if value else 0.0, 0.14)
	tween.tween_property(self, "scale", Vector2.ONE * (1.045 if value else 1.0), 0.14) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
