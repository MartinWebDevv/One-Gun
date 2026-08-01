extends VBoxContainer

# Displays the player's currently active powerups as a vertical stack,
# positioned directly above the dash pips. Most recently acquired powerup
# is shown at the top of the stack.
#
# Timed powerups (e.g. extra_dash) show a countdown in seconds.
# Persistent/consumed powerups (e.g. Sticky Hands) show an infinity
# symbol instead of a timer, since they last until used, not until time runs out.

const ENTRY_HEIGHT := 24
const ENTRY_GAP := 4
const STACK_WIDTH := 160

const DISPLAY_NAMES = {
	"extra_dash": "Extra Dash",
	"sticky_hands": "Sticky Hands",
	"speed_surge": "Speed Surge",
	"silent_steps": "Silent Steps",
	"vampire_touch": "Vampire Touch",
	"extra_life": "Extra Life",
	"magnet_hands": "Magnet Hands",
}

# One-line effect blurbs, shown under the name while the powerup is active.
const DESCRIPTIONS = {
	"extra_dash": "+1 dash charge",
	"sticky_hands": "blocks one disarm",
	"speed_surge": "+40% move speed",
	"silent_steps": "your footsteps are silent",
	"vampire_touch": "melee hits refund stamina",
	"extra_life": "survive one lethal weapon hit",
	"magnet_hands": "pulls nearby items to you",
}

var player = null
var entry_nodes = {}  # power_type -> {root, name_label, value_label}

func _ready():
	anchor_left = 0
	anchor_top = 1
	anchor_right = 0
	anchor_bottom = 1
	offset_left = 20
	offset_right = 20 + STACK_WIDTH
	offset_top = -90
	offset_bottom = -90
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_theme_constant_override("separation", ENTRY_GAP)

func set_player(p):
	player = p

func _process(_delta):
	if player == null or not player.has_method("get_active_powerups_for_display"):
		visible = false
		return

	var active = player.get_active_powerups_for_display()
	visible = active.size() > 0

	var seen_types = []
	for entry in active:
		var power_type = entry["type"]
		seen_types.append(power_type)
		if not entry_nodes.has(power_type):
			_create_entry(power_type)
		_update_entry(power_type, entry)

	for power_type in entry_nodes.keys().duplicate():
		if power_type not in seen_types:
			_remove_entry(power_type)

	_reorder_entries(active)

# Mirrors powerup.gd's color_map so each pill carries its powerup's world
# color. Update both by hand if a powerup color changes.
const TYPE_COLORS = {
	"extra_dash": Color(0.2, 1.0, 1.0),
	"sticky_hands": Color(0.2, 1.0, 0.35),
	"speed_surge": Color(0.3, 1.0, 0.3),
	"silent_steps": Color(0.55, 0.55, 0.85),
	"vampire_touch": Color(0.85, 0.15, 0.25),
	"extra_life": Color(1.0, 0.72, 0.18),
	"magnet_hands": Color(0.85, 0.35, 0.95),
}
const DESC_SHOW_TIME := 2.0   # description collapses after this to reduce clutter

func _create_entry(power_type: String):
	var type_color: Color = TYPE_COLORS.get(power_type, ThemeManager.ACCENT_GOLD)

	# Pill card with a left color bar in the powerup's world color.
	var block = PanelContainer.new()
	var style = ThemeManager.panel(Color(0.06, 0.07, 0.12, 0.82), Color.TRANSPARENT, 8, 0)
	style.border_width_left = 4
	style.border_color = type_color
	style.shadow_size = 2
	block.add_theme_stylebox_override("panel", style)

	var inner = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	block.add_child(inner)

	var row = HBoxContainer.new()
	row.custom_minimum_size = Vector2(STACK_WIDTH, ENTRY_HEIGHT)

	var name_label = Label.new()
	name_label.text = DISPLAY_NAMES.get(power_type, power_type.capitalize())
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 14)
	ThemeManager.embolden(name_label)

	var value_label = Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size = Vector2(40, 0)
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", type_color)
	ThemeManager.embolden(value_label)

	row.add_child(name_label)
	row.add_child(value_label)
	inner.add_child(row)

	var desc_label = Label.new()
	desc_label.text = DESCRIPTIONS.get(power_type, "")
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.modulate = Color(1, 1, 1, 0.65)
	inner.add_child(desc_label)
	add_child(block)

	# Juice: slide in from the left + pop.
	block.modulate.a = 0.0
	var tw = block.create_tween()
	tw.tween_property(block, "modulate:a", 1.0, 0.18)
	ThemeManager.punch(block, 1.12)

	# Collapse the description after a moment so the stack stays compact.
	get_tree().create_timer(DESC_SHOW_TIME).timeout.connect(func():
		if is_instance_valid(desc_label):
			var t2 = desc_label.create_tween()
			t2.tween_property(desc_label, "modulate:a", 0.0, 0.3)
			t2.tween_callback(func():
				if is_instance_valid(desc_label):
					desc_label.visible = false
			)
	)

	entry_nodes[power_type] = {"root": block, "name_label": name_label, "value_label": value_label}

func _update_entry(power_type: String, entry: Dictionary):
	var nodes = entry_nodes[power_type]
	if entry["timed"]:
		nodes["value_label"].text = "%.1fs" % entry["time_left"]
	else:
		nodes["value_label"].text = "∞"

func _remove_entry(power_type: String):
	var nodes = entry_nodes[power_type]
	var root = nodes["root"]
	entry_nodes.erase(power_type)
	if is_instance_valid(root):
		var tw = root.create_tween()
		tw.tween_property(root, "modulate:a", 0.0, 0.25)
		tw.tween_callback(root.queue_free)

func _reorder_entries(active: Array):
	# active[] is already ordered most-recent-first; move_child enforces that
	# visual order without rebuilding nodes every frame.
	for i in active.size():
		var power_type = active[i]["type"]
		if entry_nodes.has(power_type):
			move_child(entry_nodes[power_type]["root"], i)
