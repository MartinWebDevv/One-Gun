extends CanvasLayer
## Real player widgets, with no match scoreboard, pause routing or network polling.
const OnlineHUD = preload("res://online_hud.gd")
var player: CharacterBody3D
var shell: Control
var stamina_bar: ProgressBar
var dash_display: HBoxContainer
var inventory_slots: HBoxContainer
var widgets: Array[Control] = []

func _ready() -> void:
	layer=15
	shell=Control.new()
	shell.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(shell)
	stamina_bar=preload("res://stamina_bar.gd").new()
	stamina_bar.name="StaminaBar"
	_add_widget(stamina_bar,true)
	dash_display=preload("res://dash_charges.gd").new()
	dash_display.name="DashCharges"
	dash_display.show_hearts=false
	_add_widget(dash_display,true)
	dash_display.offset_top-=18
	dash_display.offset_bottom-=18
	inventory_slots=preload("res://inventory_slots.gd").new()
	inventory_slots.name="InventorySlots"
	for slot in ["WeaponSlot","ItemSlot","ItemSlot2"]:
		inventory_slots.add_child(OnlineHUD._make_inventory_slot(slot))
	_add_widget(inventory_slots,true)
	var powers := preload("res://powerup_status.gd").new()
	_add_widget(powers,true)
	powers.offset_top-=18
	powers.offset_bottom-=18
	_add_widget(preload("res://reload_spinner.gd").new())
	_add_widget(preload("res://throw_arc_overlay.gd").new())
	_add_widget(preload("res://flash_camera_overlay.gd").new())
	_add_widget(preload("res://flash_blind_overlay.gd").new())
	_add_widget(preload("res://damage_direction_indicator.gd").new())
	get_viewport().size_changed.connect(_resize)
	_resize()

func _add_widget(widget: Control, bottom := false) -> void:
	shell.add_child(widget)
	widget.mouse_filter=Control.MOUSE_FILTER_IGNORE
	if bottom:
		widget.offset_top-=64
		widget.offset_bottom-=64
	widgets.append(widget)

func bind_player(actor: CharacterBody3D) -> void:
	player=actor
	for widget in widgets: widget.set_player(actor)

func set_room_visible(active: bool) -> void:
	visible=active and is_instance_valid(player)
	process_mode=Node.PROCESS_MODE_INHERIT if visible else Node.PROCESS_MODE_DISABLED

func _resize() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var factor := minf(viewport_size.x/1600.0,viewport_size.y/900.0)
	shell.scale=Vector2.ONE*factor
	shell.size=viewport_size/factor
