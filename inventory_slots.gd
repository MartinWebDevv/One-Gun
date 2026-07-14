extends HBoxContainer

var player = null

const COLOR_ACTIVE = Color(0.2, 1.0, 1.0, 1.0)
const COLOR_OWNED_INACTIVE = Color(0.5, 0.5, 0.2, 0.8)
const COLOR_EMPTY = Color(0.15, 0.15, 0.15, 0.6)

# Mirrors character_body_3d.gd's INTERACT_HOLD_DROP_TIME — GDScript consts
# aren't reliably readable via "in"/get() on an instance, so this is kept in
# sync by hand. Update both if the hold duration changes.
const INTERACT_HOLD_DROP_TIME = 0.5

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
	$WeaponSlot/Icon.visible = false
	$ItemSlot/Icon.visible = false
	$ItemSlot2/Icon.visible = false

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
	if has_item and is_active:
		slot.get_node("Background").color = COLOR_ACTIVE
	elif has_item:
		slot.get_node("Background").color = COLOR_OWNED_INACTIVE
	else:
		slot.get_node("Background").color = COLOR_EMPTY

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
