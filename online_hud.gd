extends CanvasLayer

# One full-screen HUD per online machine. Gameplay state remains in the
# authoritative RoundManager; this node only binds local presentation.

var player = null
var _local_player = null
var match_hud: Control = null
var reload_spinner: Control = null
var stamina_bar: ProgressBar = null
var dash_display: HBoxContainer = null
var banner: Label = null
var ammo_label: Label = null
var local_state_label: Label = null
var inventory_slots: HBoxContainer = null
var powerup_status: VBoxContainer = null
var throw_arc_overlay: ThrowArcOverlay = null
var flash_camera_overlay: FlashCameraOverlay = null
var flash_blind_overlay: FlashBlindOverlay = null
var _hit_marker: Control = null
var _last_banner_text := ""
var pure_spectator := false
var practice_mode := false

func _ready() -> void:
	layer = 10

	match_hud = Control.new()
	match_hud.name = "MatchHUD"
	match_hud.set_script(load("res://match_hud.gd"))
	add_child(match_hud)

	var kill_feed := VBoxContainer.new()
	kill_feed.name = "KillFeed"
	kill_feed.set_script(load("res://kill_feed.gd"))
	add_child(kill_feed)

	reload_spinner = Control.new()
	reload_spinner.name = "ReloadSpinner"
	reload_spinner.set_script(load("res://reload_spinner.gd"))
	add_child(reload_spinner)

	stamina_bar = ProgressBar.new()
	stamina_bar.name = "StaminaBar"
	stamina_bar.min_value = 0.0
	stamina_bar.max_value = 100.0
	stamina_bar.show_percentage = false
	stamina_bar.set_script(load("res://stamina_bar.gd"))
	add_child(stamina_bar)

	dash_display = HBoxContainer.new()
	dash_display.name = "DashCharges"
	dash_display.set_script(load("res://dash_charges.gd"))   # builds its own styled pips
	add_child(dash_display)

	banner = Label.new()
	banner.name = "PhaseBanner"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.anchor_left = 0.15
	banner.anchor_right = 0.85
	banner.anchor_top = 0.34
	banner.anchor_bottom = 0.54
	banner.add_theme_font_size_override("font_size", 46)
	banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.28))
	banner.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	banner.add_theme_constant_override("shadow_offset_x", 4)
	banner.add_theme_constant_override("shadow_offset_y", 4)
	ThemeManager.embolden(banner)
	add_child(banner)

	ammo_label = Label.new()
	ammo_label.name = "AmmoLabel"
	ammo_label.anchor_left = 1.0
	ammo_label.anchor_right = 1.0
	ammo_label.anchor_top = 1.0
	ammo_label.anchor_bottom = 1.0
	ammo_label.offset_left = -190
	ammo_label.offset_right = -25
	ammo_label.offset_top = -82
	ammo_label.offset_bottom = -25
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.add_theme_font_size_override("font_size", 18)
	ammo_label.add_theme_stylebox_override("normal", ThemeManager.pill(Color(0.06, 0.07, 0.12, 0.85), ThemeManager.BORDER, 1))
	ThemeManager.embolden(ammo_label)
	add_child(ammo_label)

	local_state_label = Label.new()
	local_state_label.name = "LocalState"
	local_state_label.anchor_left = 0.0
	local_state_label.anchor_right = 0.0
	local_state_label.anchor_top = 1.0
	local_state_label.anchor_bottom = 1.0
	local_state_label.offset_left = 20
	local_state_label.offset_right = 360
	local_state_label.offset_top = -112
	local_state_label.offset_bottom = -84
	local_state_label.add_theme_font_size_override("font_size", 13)
	local_state_label.modulate = Color(0.85, 0.9, 1.0)
	local_state_label.add_theme_stylebox_override("normal", ThemeManager.pill(Color(0.06, 0.07, 0.12, 0.7), Color.TRANSPARENT, 0))
	ThemeManager.embolden(local_state_label)
	add_child(local_state_label)

	inventory_slots = HBoxContainer.new()
	inventory_slots.name = "InventorySlots"
	inventory_slots.add_child(_make_inventory_slot("WeaponSlot"))
	inventory_slots.add_child(_make_inventory_slot("ItemSlot"))
	inventory_slots.add_child(_make_inventory_slot("ItemSlot2"))
	inventory_slots.set_script(load("res://inventory_slots.gd"))
	add_child(inventory_slots)

	powerup_status = VBoxContainer.new()
	powerup_status.name = "PowerupStatus"
	powerup_status.set_script(load("res://powerup_status.gd"))
	add_child(powerup_status)
	throw_arc_overlay = ThrowArcOverlay.new()
	throw_arc_overlay.name = "ThrowArcOverlay"
	add_child(throw_arc_overlay)
	flash_camera_overlay = FlashCameraOverlay.new()
	flash_camera_overlay.name = "FlashCameraOverlay"
	add_child(flash_camera_overlay)
	flash_blind_overlay = FlashBlindOverlay.new()
	flash_blind_overlay.name = "FlashBlindOverlay"
	add_child(flash_blind_overlay)

	var pause_overlay := Control.new()
	pause_overlay.name = "PauseMenu"
	pause_overlay.set_script(load("res://pause_menu.gd"))
	add_child(pause_overlay)

	# Combat-feedback emissions are already filtered to this machine's own
	# attacker, so the marker can consume every validated event it hears.
	var marker_holder := Control.new()
	marker_holder.name = "HitMarkerHolder"
	marker_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marker_holder)
	_hit_marker = Control.new()
	_hit_marker.name = "HitMarker"
	_hit_marker.set_script(load("res://hit_marker.gd"))
	marker_holder.add_child(_hit_marker)   # self-subscribes; filter empty = all

func _make_inventory_slot(slot_name: String) -> Control:
	var slot := Control.new()
	slot.name = slot_name
	slot.custom_minimum_size = Vector2(80, 80)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var background := ColorRect.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(background)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(icon)
	var label := Label.new()
	label.name = "NameLabel"
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	slot.add_child(label)
	var hold_bar := ProgressBar.new()
	hold_bar.name = "HoldBar"
	hold_bar.anchor_right = 1.0
	hold_bar.offset_bottom = 6.0
	hold_bar.max_value = 1.0
	hold_bar.show_percentage = false
	hold_bar.visible = false
	slot.add_child(hold_bar)
	return slot

func bind_local_player(p) -> void:
	if p == null:
		return
	_local_player = p
	_bind_display_player(p)

func _bind_display_player(p) -> void:
	if p == player:
		return
	player = p
	if _hit_marker != null:
		_hit_marker.set("filter_actor_id", int(player.get("actor_id")) if player != null else -1)
	reload_spinner.set_player(player)
	stamina_bar.set_player(player)
	dash_display.set_player(player)
	inventory_slots.set_player(player)
	powerup_status.set_player(player)
	throw_arc_overlay.set_player(player)
	flash_camera_overlay.set_player(player)
	flash_blind_overlay.set_player(player)

func _spectator_controller():
	if _local_player != null:
		var local_spectator = _local_player.get("_spectator")
		if local_spectator != null:
			return local_spectator
	var scene := get_tree().current_scene
	return scene.get_node_or_null("LateSpectatorController") if scene != null else null

func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var rm = scene.get_node_or_null("RoundManager")
	if rm == null:
		return
	if player == null:
		bind_local_player(NetworkManager.find_net_player(NetworkManager.local_id()))
	var spectator = _spectator_controller()
	if spectator != null and spectator.has_method("get_follow_target"):
		var followed = spectator.get_follow_target()
		if followed != null:
			_bind_display_player(followed)
		else:
			_bind_display_player(_local_player)
	elif _local_player != null:
		_bind_display_player(_local_player)

	var alive := 0
	match_hud.visible = not practice_mode
	for actor_id in rm.online_actor_state:
		if bool(rm.online_actor_state[actor_id].get("alive", false)):
			alive += 1
	match_hud.update_match_state(rm.round_number, rm.set_number, alive, rm.online_actor_state.size())
	if match_hud.has_method("update_round_timer"):
		match_hud.update_round_timer(rm.get_round_timer_text(), rm.overtime_active)
	if match_hud.has_method("update_fire_warning") and player != null:
		match_hud.update_fire_warning(rm.get_fire_warning(player))
	# Slam the banner in whenever the announcement changes (countdown ticks,
	# GO!, round winners) — color-coded: GO green, countdown white, rest gold.
	if rm.online_announcement != _last_banner_text:
		_last_banner_text = rm.online_announcement
		if _last_banner_text != "":
			if _last_banner_text == "GO!":
				banner.add_theme_color_override("font_color", ThemeManager.POSITIVE)
			elif _last_banner_text.is_valid_int():
				banner.add_theme_color_override("font_color", ThemeManager.TEXT_WHITE)
			else:
				banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.28))
			ThemeManager.punch(banner, 1.5, 0.28)
	banner.text = rm.online_announcement
	banner.visible = rm.online_announcement != ""

	if player == null:
		ammo_label.visible = false
		local_state_label.text = "SPECTATOR" if pure_spectator else ""
		return
	local_state_label.text = ("SPECTATING: " if spectator != null else "YOU: ") + player.get_display_name()
	var gun = null
	var melee = player.held_melee_weapon
	var active_item = null
	if player.has_method("get_active_item"):
		if not ("active_slot" in player) or player.active_slot in ["item1", "item2"]:
			active_item = player.get_active_item()
	if player.holding_gun:
		var hold_point = player.get_hold_point()
		if hold_point != null and hold_point.get_child_count() > 0:
			gun = hold_point.get_child(0)
	ammo_label.visible = gun != null or melee != null or active_item != null
	if gun != null:
		if gun.can_fire:
			ammo_label.text = "GUN  •  READY"
			ammo_label.add_theme_color_override("font_color", ThemeManager.ACCENT_GOLD)
		else:
			ammo_label.text = "GUN  •  RELOADING…"
			ammo_label.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	elif melee != null:
		ammo_label.text = melee.get_display_name()
		ammo_label.add_theme_color_override("font_color", ThemeManager.TEXT_WHITE)
	elif active_item != null:
		ammo_label.text = active_item.get_display_name() + "  •  THROW"
		ammo_label.add_theme_color_override("font_color", ThemeManager.ACCENT_CYAN)
