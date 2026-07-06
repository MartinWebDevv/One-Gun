extends Label

var player = null
var is_owned_by_player1 := false

func _ready():
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -10
	offset_right = 10
	offset_top = -10
	offset_bottom = 10
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func set_player(p):
	player = p
	# Only Player 1's crosshair reflects personal color preferences;
	# Player 2 is a different person sharing the same local install.
	is_owned_by_player1 = not ("is_player2" in p and p.is_player2)
	if is_owned_by_player1:
		add_theme_color_override("font_color", PlayerPrefs.get_crosshair_color())
		if not PlayerPrefs.setting_changed.is_connected(_on_player_pref_changed):
			PlayerPrefs.setting_changed.connect(_on_player_pref_changed)

func _on_player_pref_changed(key: String, _value):
	if is_owned_by_player1 and key == "crosshair_color":
		add_theme_color_override("font_color", PlayerPrefs.get_crosshair_color())

func _process(_delta):
	if player == null:
		return
	var has_weapon = player.holding_gun or player.held_melee_weapon != null
	var weapon_active = not ("active_slot" in player) or player.active_slot == "weapon"
	visible = has_weapon and weapon_active
