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
	var entry = HBoxContainer.new()
	entry.add_theme_constant_override("separation", 6)

	if killer_name != "":
		_add_label(entry, killer_name, 14, Color.WHITE)
		_add_label(entry, weapon_icon, 16, Color(1.0, 0.718, 0.0), 28)
		_add_label(entry, victim_name, 14, Color(0.608, 0.639, 0.761))
		_add_label(entry, "💀", 16, Color(1.0, 0.294, 0.294), 24)
	else:
		_add_label(entry, "☠", 16, Color(0.608, 0.639, 0.761), 24)
		_add_label(entry, victim_name, 14, Color(0.608, 0.639, 0.761))

	add_child(entry)
	_fade_and_remove(entry)

func _on_player_disarmed(victim_name: String, disarmer_name: String, weapon_icon: String):
	var entry = HBoxContainer.new()
	entry.add_theme_constant_override("separation", 6)

	_add_label(entry, disarmer_name, 14, Color.WHITE)
	_add_label(entry, weapon_icon, 16, Color(1.0, 0.718, 0.0), 28)
	_add_label(entry, victim_name, 14, Color(0.608, 0.639, 0.761))
	_add_label(entry, "🔄", 16, Color(0.0, 0.898, 1.0), 24)

	add_child(entry)
	_fade_and_remove(entry)

func _add_label(parent: HBoxContainer, text: String, font_size: int, color: Color, min_width: int = 0) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.modulate = color
	if min_width > 0:
		label.custom_minimum_size = Vector2(min_width, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label

func _fade_and_remove(entry: HBoxContainer):
	await get_tree().create_timer(ENTRY_LIFETIME - 0.5).timeout
	if not is_instance_valid(entry):
		return
	var tween = create_tween()
	tween.tween_property(entry, "modulate:a", 0.0, 0.5)
	await tween.finished
	if is_instance_valid(entry):
		entry.queue_free()
