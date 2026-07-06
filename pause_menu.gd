extends Control

var settings_overlay: Control = null
var exit_confirm_dialog: ConfirmationDialog = null
var pending_exit_target := ""

func _ready():
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_ui()
	PauseManager.register_pause_menu(self)

func _exit_tree():
	PauseManager.unregister_pause_menu(self)

func _build_ui():
	for child in get_children():
		child.queue_free()

	var background = ColorRect.new()
	background.color = Color(0.102, 0.122, 0.180, 0.82)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)

	var panel = VBoxContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -140
	panel.offset_top = -135
	panel.offset_right = 140
	panel.offset_bottom = 135
	panel.add_theme_constant_override("separation", 16)
	add_child(panel)

	var title = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.718, 0.0))
	panel.add_child(title)

	var resume_button = Button.new()
	resume_button.text = "Resume"
	resume_button.custom_minimum_size = Vector2(0, 44)
	resume_button.pressed.connect(PauseManager.resume)
	panel.add_child(resume_button)

	var settings_button = Button.new()
	settings_button.text = "Settings"
	settings_button.custom_minimum_size = Vector2(0, 44)
	settings_button.pressed.connect(_open_settings_overlay)
	panel.add_child(settings_button)

	var lobby_button = Button.new()
	lobby_button.text = "Return to Lobby"
	lobby_button.custom_minimum_size = Vector2(0, 44)
	lobby_button.pressed.connect(func(): _prompt_exit_confirmation("res://game_setup.tscn", "Return to the lobby? This will abandon the current match."))
	panel.add_child(lobby_button)

	var title_menu_button = Button.new()
	title_menu_button.text = "Title Menu"
	title_menu_button.custom_minimum_size = Vector2(0, 44)
	title_menu_button.pressed.connect(func(): _prompt_exit_confirmation("res://main_menu.tscn", "Exit to the title screen? This will abandon the current match."))
	panel.add_child(title_menu_button)

func _open_settings_overlay():
	if settings_overlay != null:
		return
	var settings_scene = load("res://player_settings.tscn")
	settings_overlay = settings_scene.instantiate()
	settings_overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	settings_overlay.is_overlay = true
	add_child(settings_overlay)
	settings_overlay.settings_closed.connect(_close_settings_overlay)
	PauseManager.set_escape_override(_close_settings_overlay)

func _close_settings_overlay():
	if settings_overlay == null:
		return
	settings_overlay.queue_free()
	settings_overlay = null
	PauseManager.clear_escape_override()

func _prompt_exit_confirmation(target_scene: String, message: String):
	if exit_confirm_dialog != null:
		return
	pending_exit_target = target_scene
	exit_confirm_dialog = ConfirmationDialog.new()
	exit_confirm_dialog.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	exit_confirm_dialog.dialog_text = message
	exit_confirm_dialog.title = "Leave Match"
	exit_confirm_dialog.dialog_close_on_escape = false
	add_child(exit_confirm_dialog)
	exit_confirm_dialog.popup_centered()
	PauseManager.set_escape_override(_cancel_exit_confirmation)

	exit_confirm_dialog.confirmed.connect(func():
		PauseManager.clear_escape_override()
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file(pending_exit_target)
	)
	exit_confirm_dialog.canceled.connect(_cancel_exit_confirmation)

func _cancel_exit_confirmation():
	PauseManager.clear_escape_override()
	if exit_confirm_dialog != null:
		exit_confirm_dialog.queue_free()
		exit_confirm_dialog = null
