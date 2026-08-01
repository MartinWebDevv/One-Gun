extends HBoxContainer

var player = null

# Mirrors character_body_3d.gd's INTERACT_HOLD_DROP_TIME — GDScript consts
# aren't reliably readable via "in"/get() on an instance, so this is kept in
# sync by hand. Update both if the hold duration changes.
const INTERACT_HOLD_DROP_TIME = 0.5

var _style_active: StyleBoxFlat = null
var _style_owned: StyleBoxFlat = null
var _style_empty: StyleBoxFlat = null
var _slot_active_state := {}   # slot node -> bool (for pop-on-activate)

func _ready():
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1
	anchor_bottom = 1
	offset_left = -135
	offset_right = 135
	offset_top = -90
	offset_bottom = -20
	add_theme_constant_override("separation", 12)

	# Kit card styles: gold-bordered when active, subtle when owned, faint when empty.
	_style_active = ThemeManager.panel(Color(0.14, 0.16, 0.27, 0.92), ThemeManager.ACCENT_GOLD, 10, 2)
	_style_owned = ThemeManager.panel(Color(0.10, 0.11, 0.19, 0.85), ThemeManager.BORDER, 10, 1)
	_style_empty = ThemeManager.panel(Color(0.05, 0.06, 0.10, 0.45), Color(ThemeManager.BORDER.r, ThemeManager.BORDER.g, ThemeManager.BORDER.b, 0.35), 10, 1)

	for slot in [$WeaponSlot, $ItemSlot, $ItemSlot2]:
		slot.get_node("Icon").visible = false
		# Swap the flat ColorRect background for a styled rounded card.
		var bg = slot.get_node_or_null("Background")
		if bg != null:
			bg.visible = false
		var card = Panel.new()
		card.name = "StyledBg"
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_theme_stylebox_override("panel", _style_empty)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(card)
		slot.move_child(card, 0)
		var name_label = slot.get_node_or_null("NameLabel")
		if name_label != null:
			name_label.add_theme_font_size_override("font_size", 13)
			ThemeManager.embolden(name_label)
		var hold_bar = slot.get_node_or_null("HoldBar")
		if hold_bar != null:
			var hb_bg = ThemeManager.panel(Color(0, 0, 0, 0.5), Color.TRANSPARENT, 3, 0)
			hb_bg.shadow_size = 0
			var hb_fill = ThemeManager.panel(ThemeManager.ACCENT_GOLD, Color.TRANSPARENT, 3, 0)
			hb_fill.shadow_size = 0
			hold_bar.add_theme_stylebox_override("background", hb_bg)
			hold_bar.add_theme_stylebox_override("fill", hb_fill)
		_slot_active_state[slot] = false

func set_player(p):
	player = p

func _process(_delta):
	if player == null:
		return

	var has_weapon = player.holding_gun or player.held_melee_weapon != null
	var weapon_active = "active_slot" in player and player.active_slot == "weapon"
	_update_slot($WeaponSlot, has_weapon, weapon_active)

	if player.holding_gun:
		$WeaponSlot/NameLabel.text = "Gun"
	elif player.held_melee_weapon != null:
		if player.held_melee_weapon.has_method("get_display_name"):
			$WeaponSlot/NameLabel.text = player.held_melee_weapon.get_display_name()
		else:
			$WeaponSlot/NameLabel.text = "Melee"
	else:
		$WeaponSlot/NameLabel.text = ""

	var item1 = player.held_item_1 if "held_item_1" in player else null
	var item1_active = "active_slot" in player and player.active_slot == "item1"
	_update_slot($ItemSlot, item1 != null, item1_active)
	if item1 != null and item1.has_method("get_display_name"):
		$ItemSlot/NameLabel.text = item1.get_display_name()
	else:
		$ItemSlot/NameLabel.text = ""

	var item2 = player.held_item_2 if "held_item_2" in player else null
	var item2_active = "active_slot" in player and player.active_slot == "item2"
	_update_slot($ItemSlot2, item2 != null, item2_active)
	if item2 != null and item2.has_method("get_display_name"):
		$ItemSlot2/NameLabel.text = item2.get_display_name()
	else:
		$ItemSlot2/NameLabel.text = ""

func _update_slot(slot: Control, has_item: bool, is_active: bool):
	var card = slot.get_node_or_null("StyledBg")
	if card != null:
		if has_item and is_active:
			card.add_theme_stylebox_override("panel", _style_active)
		elif has_item:
			card.add_theme_stylebox_override("panel", _style_owned)
		else:
			card.add_theme_stylebox_override("panel", _style_empty)
	# Pop the slot when it becomes the active one.
	var was_active: bool = _slot_active_state.get(slot, false)
	var now_active := has_item and is_active
	if now_active and not was_active:
		ThemeManager.punch(slot, 1.15)
	_slot_active_state[slot] = now_active

	var hold_bar = slot.get_node_or_null("HoldBar")
	if hold_bar == null:
		return
	var holding_to_drop = (
		is_active
		and "interact_hold_active" in player
		and player.interact_hold_active
	)
	hold_bar.visible = holding_to_drop
	if holding_to_drop:
		hold_bar.value = clamp(player.interact_hold_timer / INTERACT_HOLD_DROP_TIME, 0.0, 1.0)
