extends HBoxContainer

var player = null

const COLOR_ACTIVE = Color(0.2, 1.0, 1.0, 1.0)
const COLOR_OWNED_INACTIVE = Color(0.5, 0.5, 0.2, 0.8)
const COLOR_EMPTY = Color(0.15, 0.15, 0.15, 0.6)

func _ready():
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1
	anchor_bottom = 1
	offset_left = -90
	offset_right = 90
	offset_top = -90
	offset_bottom = -20
	add_theme_constant_override("separation", 12)
	$WeaponSlot/Icon.visible = false
	$ItemSlot/Icon.visible = false

func set_player(p):
	player = p

func _process(_delta):
	if player == null:
		return

	var has_weapon = player.holding_gun or player.held_melee_weapon != null
	var weapon_active = "active_slot" in player and player.active_slot == "weapon"
	if has_weapon and weapon_active:
		$WeaponSlot/Background.color = COLOR_ACTIVE
	elif has_weapon:
		$WeaponSlot/Background.color = COLOR_OWNED_INACTIVE
	else:
		$WeaponSlot/Background.color = COLOR_EMPTY

	if player.holding_gun:
		$WeaponSlot/NameLabel.text = "Gun"
	elif player.held_melee_weapon != null:
		if player.held_melee_weapon.has_method("get_display_name"):
			$WeaponSlot/NameLabel.text = player.held_melee_weapon.get_display_name()
		else:
			$WeaponSlot/NameLabel.text = "Melee"
	else:
		$WeaponSlot/NameLabel.text = ""

	var has_item = "held_item" in player and player.held_item != null
	var item_active = "active_slot" in player and player.active_slot == "item"
	if has_item and item_active:
		$ItemSlot/Background.color = COLOR_ACTIVE
	elif has_item:
		$ItemSlot/Background.color = COLOR_OWNED_INACTIVE
	else:
		$ItemSlot/Background.color = COLOR_EMPTY

	if has_item and player.held_item.has_method("get_display_name"):
		$ItemSlot/NameLabel.text = player.held_item.get_display_name()
	else:
		$ItemSlot/NameLabel.text = ""
