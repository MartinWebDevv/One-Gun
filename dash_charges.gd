extends HBoxContainer

const PIP_GAP := 6
const TOTAL_WIDTH := 200.0
const PIP_HEIGHT := 14.0

var player = null
var _prev_charges := -1
var _style_on: StyleBoxFlat = null
var _style_off: StyleBoxFlat = null
var _style_extra: StyleBoxFlat = null
var _hearts_label: Label = null

func _ready():
	_style_on = _pip_style(true)
	_style_off = _pip_style(false)
	_style_extra = ThemeManager.panel(
		ThemeManager.ACCENT_GOLD, ThemeManager.ACCENT_GOLD.lightened(0.35), 6, 1)
	_style_extra.shadow_size = 0
	anchor_left = 0
	anchor_top = 1
	anchor_right = 0
	anchor_bottom = 1
	offset_left = 20
	offset_top = -75
	offset_right = 220
	offset_bottom = -45
	add_theme_constant_override("separation", PIP_GAP)
	# Any scene-baked / template ColorRect pips are replaced by styled panels.
	for child in get_children():
		child.queue_free()
	_build_hearts_label()

func set_player(p):
	player = p
	_prev_charges = -1
	_rebuild_pips()
	_update_hearts()

func _build_hearts_label() -> void:
	if get_parent() == null:
		return
	_hearts_label = Label.new()
	_hearts_label.name = "%sAllGunHearts" % name
	_hearts_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hearts_label.anchor_left = 0.0
	_hearts_label.anchor_top = 1.0
	_hearts_label.anchor_right = 0.0
	_hearts_label.anchor_bottom = 1.0
	_hearts_label.offset_left = 20.0
	_hearts_label.offset_top = -108.0
	_hearts_label.offset_right = 220.0
	_hearts_label.offset_bottom = -78.0
	_hearts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hearts_label.add_theme_font_size_override("font_size", 24)
	_hearts_label.add_theme_constant_override("outline_size", 6)
	_hearts_label.add_theme_color_override("font_color", Color(1.0, 0.18, 0.24))
	get_parent().add_child.call_deferred(_hearts_label)


func _update_hearts() -> void:
	if _hearts_label == null:
		return
	_hearts_label.visible = GameConfig.game_mode == GameConfig.MODE_ALL_GUN \
		and player != null and "all_gun_hearts" in player
	if not _hearts_label.visible:
		return
	var hearts := clampi(int(player.all_gun_hearts), 0, GameConfig.ALL_GUN_MAX_HEARTS)
	var parts: Array[String] = []
	for index in GameConfig.ALL_GUN_MAX_HEARTS:
		parts.append("♥" if index < hearts else "♡")

	_hearts_label.text = " ".join(parts)

func _make_pip() -> Panel:
	var pip := Panel.new()
	pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pip.clip_contents = true
	pip.add_theme_stylebox_override("panel", _style_off)
	var fill := ColorRect.new()
	fill.name = "RechargeFill"
	fill.color = ThemeManager.ACCENT_CYAN
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pip.add_child(fill)
	return pip

func _pip_style(charged: bool) -> StyleBoxFlat:
	var s: StyleBoxFlat
	if charged:
		s = ThemeManager.panel(ThemeManager.ACCENT_CYAN, ThemeManager.ACCENT_CYAN.lightened(0.4), 6, 1)
	else:
		s = ThemeManager.panel(Color(0.05, 0.06, 0.10, 0.6), ThemeManager.BORDER, 6, 1)
	s.shadow_size = 0
	return s

func _rebuild_pips():
	if player == null or not ("max_dash_charges" in player):
		return
	var target_count: int = player.max_dash_charges
	if "extra_dash_charge" in player:
		target_count += int(player.extra_dash_charge)
	while get_child_count() < target_count:
		add_child(_make_pip())
	while get_child_count() > target_count:
		var extra = get_child(get_child_count() - 1)
		remove_child(extra)
		extra.queue_free()
	var count := get_child_count()
	if count <= 0:
		return
	var pip_width: float = (TOTAL_WIDTH - float(PIP_GAP * maxi(count - 1, 0))) / float(count)
	for pip in get_children():
		pip.custom_minimum_size = Vector2(pip_width, PIP_HEIGHT)

func _process(_delta):
	if player == null:
		return
	_update_hearts()
	var target_count: int = player.max_dash_charges + int(player.extra_dash_charge if "extra_dash_charge" in player else 0)
	if get_child_count() != target_count:
		_rebuild_pips()
	var charges: int = player.dash_charges
	for i in get_child_count():
		var pip = get_child(i)
		if not (pip is Panel):
			continue
		var fill := pip.get_node_or_null("RechargeFill") as ColorRect
		var is_extra: bool = i >= player.max_dash_charges
		var is_full := i < charges or is_extra
		var fill_amount := 0.0
		# Only the first empty base pip receives recharge progress. All later
		# pips stay empty until it locks in, producing a left-to-right sequence.
		if not is_full and i == charges and charges < player.max_dash_charges:
			if player.has_method("get_dash_recharge_progress"):
				fill_amount = player.get_dash_recharge_progress()
			else:
				fill_amount = clampf(float(player.dash_recharge_timer) / 3.0, 0.0, 1.0)
		pip.add_theme_stylebox_override(
			"panel", _style_extra if is_extra else (_style_on if is_full else _style_off))
		pip.set_meta("recharge_fill", 1.0 if is_full else fill_amount)
		if fill != null:
			# A fully loaded pip uses its persistent charged panel style. The
			# overlay exists only for the one partially recharging pip.
			fill.visible = not is_full and fill_amount > 0.0
			fill.color = ThemeManager.ACCENT_CYAN
			fill.position = Vector2.ZERO
			fill.size = Vector2(pip.size.x * fill_amount, pip.size.y)
	# Pop the newly-refilled pip; quick flash on the one just spent.
	if _prev_charges >= 0 and charges != _prev_charges:
		if charges > _prev_charges and charges - 1 < get_child_count() and charges >= 1:
			ThemeManager.punch(get_child(charges - 1), 1.45)
		elif charges < _prev_charges and charges < get_child_count():
			ThemeManager.flash(get_child(charges), Color(1, 1, 1, 0.3), 0.2)
	_prev_charges = charges
