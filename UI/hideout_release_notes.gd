extends Control
signal closed

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel",OneGunUI.style_box(Color("15272b"),OneGunUI.color("gold"),16,2,8,28))
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",18)
	panel.add_child(column)
	var release := OneGunBuildInfo.load_latest_release()
	column.add_child(OneGunUI.make_heading("%s / v%s" % [release.get("title","Release Notes"),release.get("version",OneGunBuildInfo.GAME_VERSION)],32))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var categories: Dictionary = release.get("categories",{})
	for category in ["Added","Improved","Fixed","Removed","Misc"]:
		var entries: Array = categories.get(category,[])
		if entries.is_empty(): continue
		body.add_child(OneGunUI.make_heading(category.to_upper(),24,"gold"))
		for entry in entries:
			var label := OneGunUI.make_label("• "+str(entry),21)
			label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			body.add_child(label)
	var back := OneGunButton.new()
	back.text="BACK"
	back.pressed.connect(_close)
	column.add_child(back)
	back.grab_focus()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	closed.emit()
