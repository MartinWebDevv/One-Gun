extends CanvasLayer

## Runtime-built local HUD used by maps that do not carry the older, very
## large scene-authored CanvasLayer tree. Node names and paths intentionally
## match the established maps so RoundManager and every HUD component can use
## the same contracts in solo, bots, and split-screen play.

func _ready() -> void:
	if get_node_or_null("MatchHUD") != null:
		return
	_build_round_labels()
	_build_match_huds()
	_build_kill_feeds()
	add_child(_build_player_ui("PlayerUI1", "../../player1", false))
	add_child(_build_player_ui("PlayerUI2", "../../player2", true))
	var pause_menu := Control.new()
	pause_menu.name = "PauseMenu"
	pause_menu.set_script(load("res://pause_menu.gd"))
	add_child(pause_menu)

func _build_round_labels() -> void:
	var round_label := Label.new()
	round_label.name = "RoundLabel"
	round_label.set_anchors_preset(Control.PRESET_CENTER)
	round_label.offset_left = -360.0
	round_label.offset_right = 360.0
	round_label.offset_top = -80.0
	round_label.offset_bottom = 20.0
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	round_label.add_theme_font_size_override("font_size", 48)
	round_label.set_script(load("res://round_label.gd"))
	add_child(round_label)

	var round_label_2 := Label.new()
	round_label_2.name = "RoundLabel2"
	round_label_2.set_anchors_preset(Control.PRESET_CENTER)
	round_label_2.offset_left = -360.0
	round_label_2.offset_right = 360.0
	round_label_2.offset_top = -80.0
	round_label_2.offset_bottom = 20.0
	round_label_2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label_2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	round_label_2.add_theme_font_size_override("font_size", 48)
	round_label_2.set_script(load("res://round_label.gd"))
	add_child(round_label_2)

func _build_match_huds() -> void:
	var match_hud := Control.new()
	match_hud.name = "MatchHUD"
	match_hud.set_script(load("res://match_hud.gd"))
	add_child(match_hud)

	var match_hud_2 := Control.new()
	match_hud_2.name = "MatchHUD2"
	match_hud_2.set_script(load("res://match_hud.gd"))
	match_hud_2.set("is_second_screen", true)
	add_child(match_hud_2)

func _build_kill_feeds() -> void:
	var feed := VBoxContainer.new()
	feed.name = "KillFeed"
	_configure_kill_feed(feed, false)
	add_child(feed)

	var feed_2 := VBoxContainer.new()
	feed_2.name = "KillFeed2"
	_configure_kill_feed(feed_2, true)
	add_child(feed_2)

func _configure_kill_feed(feed: VBoxContainer, second_screen: bool) -> void:
	feed.anchor_left = 1.0
	feed.anchor_right = 1.0
	feed.offset_left = -290.0
	feed.offset_right = -18.0
	feed.offset_top = 20.0
	feed.offset_bottom = 220.0
	feed.set_script(load("res://kill_feed.gd"))
	feed.set("is_second_screen", second_screen)

func _build_player_ui(ui_name: String, player_path: String, second_screen: bool) -> Control:
	var ui := Control.new()
	ui.name = ui_name
	ui.anchor_left = 0.5 if second_screen else 0.0
	ui.anchor_right = 1.0 if second_screen else 0.5
	ui.anchor_bottom = 1.0
	ui.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ui.grow_vertical = Control.GROW_DIRECTION_BOTH
	ui.set_script(load("res://player_ui_container.gd"))
	ui.set("player_path", NodePath(player_path))

	var crosshair := Label.new()
	crosshair.name = "Crosshair"
	crosshair.set_script(load("res://crosshair.gd"))
	ui.add_child(crosshair)

	var stamina := ProgressBar.new()
	stamina.name = "StaminaBar"
	stamina.min_value = 0.0
	stamina.max_value = 100.0
	stamina.value = 100.0
	stamina.set_script(load("res://stamina_bar.gd"))
	ui.add_child(stamina)

	var dash := HBoxContainer.new()
	dash.name = "DashCharges"
	dash.set_script(load("res://dash_charges.gd"))
	ui.add_child(dash)

	var gun_ui := HBoxContainer.new()
	gun_ui.name = "GunUI"
	var ammo_label := Label.new()
	ammo_label.name = "AmmoLabel"
	gun_ui.add_child(ammo_label)
	gun_ui.set_script(load("res://gun_ui.gd"))
	ui.add_child(gun_ui)

	var melee_ui := HBoxContainer.new()
	melee_ui.name = "MeleeUI"
	var melee_label := Label.new()
	melee_label.name = "NameLabel"
	melee_ui.add_child(melee_label)
	melee_ui.set_script(load("res://melee_ui.gd"))
	ui.add_child(melee_ui)

	var reload := Control.new()
	reload.name = "ReloadSpinner"
	reload.set_script(load("res://reload_spinner.gd"))
	ui.add_child(reload)

	var inventory := HBoxContainer.new()
	inventory.name = "InventorySlots"
	inventory.add_child(_make_inventory_slot("WeaponSlot"))
	inventory.add_child(_make_inventory_slot("ItemSlot"))
	inventory.add_child(_make_inventory_slot("ItemSlot2"))
	inventory.set_script(load("res://inventory_slots.gd"))
	ui.add_child(inventory)

	var powerups := VBoxContainer.new()
	powerups.name = "PowerupStatus"
	powerups.set_script(load("res://powerup_status.gd"))
	ui.add_child(powerups)
	return ui

func _make_inventory_slot(slot_name: String) -> Control:
	var slot := Control.new()
	slot.name = slot_name
	slot.custom_minimum_size = Vector2(80.0, 80.0)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var background := ColorRect.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(background)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	slot.add_child(icon)

	var label := Label.new()
	label.name = "NameLabel"
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot.add_child(label)

	var hold_bar := ProgressBar.new()
	hold_bar.name = "HoldBar"
	hold_bar.anchor_right = 1.0
	hold_bar.offset_top = 74.0
	hold_bar.offset_bottom = 80.0
	hold_bar.max_value = 1.0
	hold_bar.show_percentage = false
	hold_bar.visible = false
	slot.add_child(hold_bar)
	return slot
