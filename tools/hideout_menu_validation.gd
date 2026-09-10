extends RefCounted

# Exercise real locomotion and camera input in both standalone and ENet scenes.
static func run(world: Node3D) -> Array[String]:
	var errors: Array[String]=[]
	var actor=world.pilot
	var old_position: Vector3=actor.position
	var old_velocity: Vector3=actor.velocity
	var pivot: Node3D=actor.get_node("AimPivot")
	var arm: Node3D=pivot.get_node("SpringArm3D")
	var old_yaw: Vector3=pivot.rotation
	var old_pitch: Vector3=arm.rotation
	var old_gamepad: bool=actor.use_gamepad_look
	actor.use_gamepad_look=false
	actor.position=Vector3(0,0.5,8)
	actor.velocity=Vector3.ZERO
	pivot.rotation=Vector3.ZERO
	world._open("pause")
	await world.get_tree().create_timer(0.3).timeout
	if not world.controls_enabled or not actor.is_physics_processing(): errors.append("Escape blocks locomotion")
	if Input.mouse_mode!=Input.MOUSE_MODE_VISIBLE: errors.append("Escape does not free the cursor")
	for child in world.ui.contents.get_children():
		if child is Button and child.focus_mode!=Control.FOCUS_NONE: errors.append("movement keys can focus a menu action")
	var mouse:=InputEventMouseMotion.new()
	mouse.relative=Vector2(90,35)
	var menu_yaw: Vector3=pivot.rotation
	var menu_pitch: Vector3=arm.rotation
	actor._input(mouse)
	if pivot.rotation!=menu_yaw or arm.rotation!=menu_pitch: errors.append("menu pointer rotates camera")
	var start: Vector3=actor.position
	Input.action_press(actor.input_prefix+"_move_forward")
	Input.action_press(actor.input_prefix+"_ads")
	await world.get_tree().create_timer(0.3).timeout
	Input.action_release(actor.input_prefix+"_move_forward")
	Input.action_release(actor.input_prefix+"_ads")
	if Vector2(actor.position.x-start.x,actor.position.z-start.z).length()<0.5: errors.append("movement input does not move actor through Escape")
	if actor.ads_blend_target!=0.0: errors.append("menu right-click activates aiming")
	Input.action_press(actor.input_prefix+"_jump")
	await world.get_tree().create_timer(0.08).timeout
	Input.action_release(actor.input_prefix+"_jump")
	if actor.velocity.y<=0.0: errors.append("Escape blocks jumping")
	if world.ui.page!="pause": errors.append("locomotion closes or activates menu")
	world._open("")
	actor._input(mouse)
	if actor.menu_movement_only or pivot.rotation==menu_yaw: errors.append("closing Escape does not restore mouse look")
	errors.append_array(await _check_shortcut_menus(world))
	actor.use_gamepad_look=old_gamepad
	actor.position=old_position
	actor.velocity=old_velocity
	pivot.rotation=old_yaw
	arm.rotation=old_pitch
	return errors

static func _check_shortcut_menus(world: Node3D) -> Array[String]:
	var errors: Array[String] = []
	var actor = world.pilot
	var pivot: Node3D = actor.get_node("AimPivot")
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(80, 20)
	var shortcuts = {"lobby_events":"events", "lobby_party":"party", "lobby_hub":"hub", "lobby_locker":"locker", "lobby_friends":"friends", "lobby_scrap":"scrap", "lobby_playpen":"sparring", "lobby_range":"range_settings", "lobby_agility":"agility", "lobby_records":"course_board"}
	for shortcut in shortcuts:
		actor.position = Vector3(0, 0.5, 8)
		actor.velocity = Vector3.ZERO
		var event := InputEventAction.new()
		event.action = "p1_" + shortcut
		event.pressed = true
		world._input(event)
		await world.get_tree().create_timer(0.25).timeout
		var page: String = shortcuts[shortcut]
		if world.native_page != page and world.ui.page != page: errors.append("shortcut failed: " + page)
		if not world.controls_enabled or not actor.menu_movement_only: errors.append("menu blocks locomotion: " + page)
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE: errors.append("menu captures cursor: " + page)
		var yaw: Vector3 = pivot.rotation
		actor._input(mouse)
		if pivot.rotation != yaw: errors.append("menu rotates world camera: " + page)
		var start: Vector3 = actor.position
		Input.action_press(actor.input_prefix + "_move_forward")
		await world.get_tree().create_timer(0.15).timeout
		Input.action_release(actor.input_prefix + "_move_forward")
		if Vector2(actor.position.x-start.x,actor.position.z-start.z).length() < 0.2: errors.append("no actual movement: " + page)
		# Real dispatched jump key: it must not click a focused menu action.
		var button := Button.new()
		button.text = "Input probe"
		var presses := [0]
		button.pressed.connect(func(): presses[0] += 1)
		var parent: Node = world.native_overlay if is_instance_valid(world.native_overlay) else world.ui.contents
		parent.add_child(button)
		button.grab_focus()
		for binding in InputMap.action_get_events(actor.input_prefix + "_jump"):
			if binding is InputEventKey:
				var key := binding.duplicate() as InputEventKey
				key.pressed = true
				Input.parse_input_event(key)
				await world.get_tree().physics_frame
				key.pressed = false
				Input.parse_input_event(key)
				break
		if presses[0] != 0: errors.append("jump also clicks a menu button: " + page)
		button.queue_free()
		world._escape()
		await world.get_tree().create_timer(0.4).timeout
		if actor.menu_movement_only: errors.append("closing menu leaves camera blocked: " + page)
	# Text entry must not move the actor; leaving the field restores locomotion.
	world._open("friends")
	var field := LineEdit.new()
	world.native_overlay.add_child(field)
	field.grab_focus()
	await world.get_tree().physics_frame
	actor.velocity = Vector3.ZERO
	var start: Vector3 = actor.position
	Input.action_press(actor.input_prefix + "_move_forward")
	await world.get_tree().create_timer(0.15).timeout
	Input.action_release(actor.input_prefix + "_move_forward")
	if not actor.menu_text_input_active or Vector2(actor.position.x-start.x,actor.position.z-start.z).length() > 0.15: errors.append("typing also moves actor")
	field.release_focus()
	await world.get_tree().create_timer(0.05).timeout
	if actor.menu_text_input_active: errors.append("text field leaves movement blocked")
	world._escape()
	await world.get_tree().process_frame
	world._open("settings")
	var settings = world.native_overlay
	settings._capture_action = actor.input_prefix + "_jump"
	await world.get_tree().create_timer(0.05).timeout
	if not actor.menu_text_input_active: errors.append("rebinding does not reserve movement input")
	settings._cancel_capture()
	await world.get_tree().create_timer(0.05).timeout
	if actor.menu_text_input_active: errors.append("cancelled rebind keeps movement blocked")
	world._escape()
	await world.get_tree().create_timer(0.4).timeout
	return errors
