extends VBoxContainer

# Displays the player's currently active powerups as a vertical stack,
# positioned directly above the dash pips. Most recently acquired powerup
# is shown at the top of the stack.
#
# Timed powerups (e.g. extra_dash) show a countdown in seconds.
# Persistent/consumed powerups (e.g. extra_melee_shield) show an infinity
# symbol instead of a timer, since they last until used, not until time runs out.

const ENTRY_HEIGHT := 24
const ENTRY_GAP := 4
const STACK_WIDTH := 160

const DISPLAY_NAMES = {
	"extra_dash": "Extra Dash",
	"extra_melee_shield": "Disarm Shield"
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

func _create_entry(power_type: String):
	var row = HBoxContainer.new()
	row.custom_minimum_size = Vector2(STACK_WIDTH, ENTRY_HEIGHT)

	var name_label = Label.new()
	name_label.text = DISPLAY_NAMES.get(power_type, power_type.capitalize())
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)

	var value_label = Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size = Vector2(40, 0)
	value_label.add_theme_font_size_override("font_size", 16)

	row.add_child(name_label)
	row.add_child(value_label)
	add_child(row)

	entry_nodes[power_type] = {"root": row, "name_label": name_label, "value_label": value_label}

func _update_entry(power_type: String, entry: Dictionary):
	var nodes = entry_nodes[power_type]
	if entry["timed"]:
		nodes["value_label"].text = "%.1fs" % entry["time_left"]
	else:
		nodes["value_label"].text = "∞"

func _remove_entry(power_type: String):
	var nodes = entry_nodes[power_type]
	nodes["root"].queue_free()
	entry_nodes.erase(power_type)

func _reorder_entries(active: Array):
	# active[] is already ordered most-recent-first; move_child enforces that
	# visual order without rebuilding nodes every frame.
	for i in active.size():
		var power_type = active[i]["type"]
		if entry_nodes.has(power_type):
			move_child(entry_nodes[power_type]["root"], i)
