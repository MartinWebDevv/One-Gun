extends VBoxContainer

const ENTRY_LIFETIME = 4.0

@export var is_second_screen := false

func _ready():
	if is_second_screen and not GameConfig.split_screen_enabled:
		visible = false
		return

	var right_anchor = 1.0
	if GameConfig.split_screen_enabled:
		right_anchor = 0.5 if not is_second_screen else 1.0

	anchor_top = 0
	offset_top = 20
	anchor_left = right_anchor
	anchor_right = right_anchor
	offset_left = -320
	offset_right = -20

	GameEvents.player_eliminated.connect(_on_player_eliminated)
	GameEvents.player_disarmed.connect(_on_player_disarmed)

func _on_player_eliminated(victim_name: String, killer_name: String, weapon_icon: String):
	var entry = _make_pill_entry()
	var row: HBoxContainer = entry.get_child(0)

	if killer_name != "":
		_add_label(row, killer_name, 14, ThemeManager.ACCENT_GOLD, 0, true)
		_add_label(row, weapon_icon, 16, Color.WHITE, 28)
		_add_label(row, victim_name, 14, ThemeManager.TEXT_DIM)
		_add_label(row, "💀", 16, ThemeManager.DANGER, 24)
	else:
		_add_label(row, "☠", 16, ThemeManager.TEXT_DIM, 24)
		_add_label(row, victim_name, 14, ThemeManager.TEXT_DIM)

	_show_entry(entry)

func _on_player_disarmed(victim_name: String, disarmer_name: String, weapon_icon: String):
	var entry = _make_pill_entry()
	var row: HBoxContainer = entry.get_child(0)

	_add_label(row, disarmer_name, 14, ThemeManager.ACCENT_GOLD, 0, true)
	_add_label(row, weapon_icon, 16, Color.WHITE, 28)
	_add_label(row, victim_name, 14, ThemeManager.TEXT_DIM)
	_add_label(row, "🔄", 16, ThemeManager.ACCENT_CYAN, 24)

	_show_entry(entry)

# Rounded translucent pill that wraps a feed row.
func _make_pill_entry() -> PanelContainer:
	var pill = PanelContainer.new()
	pill.add_theme_stylebox_override("panel", ThemeManager.pill(Color(0.05, 0.06, 0.10, 0.78), Color.TRANSPARENT, 0))
	pill.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	pill.add_child(row)
	return pill

# Pop-in from the right edge (scale, not position — the VBox owns positions),
# then live out the normal lifetime.
func _show_entry(entry: PanelContainer):
	add_child(entry)
	entry.modulate.a = 0.0
	var tw = entry.create_tween()
	tw.tween_property(entry, "modulate:a", 1.0, 0.15)
	# Pivot on the right edge so the pop reads as sliding in from the right.
	entry.resized.connect(func(): entry.pivot_offset = Vector2(entry.size.x, entry.size.y * 0.5), CONNECT_ONE_SHOT)
	entry.scale = Vector2(0.7, 0.7)
	var tw2 = entry.create_tween()
	tw2.tween_property(entry, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fade_and_remove(entry)

func _add_label(parent: HBoxContainer, text: String, font_size: int, color: Color, min_width: int = 0, bold: bool = false) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.modulate = color
	if bold:
		ThemeManager.embolden(label)
	if min_width > 0:
		label.custom_minimum_size = Vector2(min_width, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label

func _fade_and_remove(entry: Control):
	await get_tree().create_timer(ENTRY_LIFETIME - 0.5).timeout
	if not is_instance_valid(entry):
		return
	var tween = create_tween()
	tween.tween_property(entry, "modulate:a", 0.0, 0.5)
	await tween.finished
	if is_instance_valid(entry):
		entry.queue_free()
