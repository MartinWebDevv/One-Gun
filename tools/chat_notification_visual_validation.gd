extends SceneTree

# Focused render validation for the real OnlineChat closed-history receive UI.
# The backdrop is only a lightweight framing surface; notification cards come
# directly from the production OnlineChat autoload and its delivery callback.

const CAPTURE_ENV := "ONEGUN_CHAT_CAPTURE"
const VIEWPORT_SIZE := Vector2i(1280, 720)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = VIEWPORT_SIZE
	_build_backdrop()

	var network = root.get_node("NetworkManager")
	var port := 27500 + int(OS.get_process_id() % 1000)
	if not network.host_game(port, "Chat Capture", {
		"privacy": "private",
		"max_players": 4,
	}):
		push_error("CHAT VISUAL VALIDATION: could not start local host")
		quit(1)
		return
	await process_frame

	var chat = root.get_node("OnlineChat")
	chat._on_chat_message_received(
		2, "Rattlesnake", "Gun spotted by the west armory.", "lobby")
	chat._on_chat_message_received(
		3, "Dusty", "Moving through the center lane.", "lobby")
	await create_timer(0.2).timeout

	var notifications: Array = chat.get("_notifications")
	var history_panel := chat.get("_panel") as Control
	if notifications.size() != 2 or history_panel == null or history_panel.visible:
		push_error("CHAT VISUAL VALIDATION: receive UI state was incorrect")
		network.disconnect_net()
		quit(1)
		return

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var capture_path := OS.get_environment(CAPTURE_ENV)
	if capture_path.is_empty():
		capture_path = ProjectSettings.globalize_path(
			"res://.godot/chat_notifications_headless.png")
	DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
	var error := image.save_png(capture_path)
	if error != OK:
		push_error("CHAT VISUAL VALIDATION: could not save capture")
		network.disconnect_net()
		quit(1)
		return

	print("CHAT_VISUAL_VALIDATION_OK ", capture_path)
	network.disconnect_net()
	quit(0)


func _build_backdrop() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	root.add_child(layer)

	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = OneGunUI.color("canvas")
	layer.add_child(background)

	var lower_field := ColorRect.new()
	lower_field.anchor_left = 0.0
	lower_field.anchor_right = 1.0
	lower_field.anchor_top = 0.48
	lower_field.anchor_bottom = 1.0
	lower_field.color = Color(0.025, 0.075, 0.19, 1.0)
	background.add_child(lower_field)

	var horizon := ColorRect.new()
	horizon.anchor_left = 0.0
	horizon.anchor_right = 1.0
	horizon.anchor_top = 0.475
	horizon.anchor_bottom = 0.482
	horizon.color = OneGunUI.color("cyan")
	background.add_child(horizon)

	var title := OneGunUI.make_label(
		"THE PLAYPEN", OneGunUI.TEXT_XL, "cyan")
	title.position = Vector2(28.0, 22.0)
	background.add_child(title)

	var subtitle := OneGunUI.make_label(
		"REMOTE PLAYER VIEW  /  CHAT HISTORY CLOSED",
		OneGunUI.TEXT_XS, "muted")
	subtitle.position = Vector2(30.0, 55.0)
	background.add_child(subtitle)

	for index in range(5):
		var lane := ColorRect.new()
		lane.position = Vector2(0.0, 430.0 + float(index) * 56.0)
		lane.size = Vector2(float(VIEWPORT_SIZE.x), 2.0)
		lane.color = Color(OneGunUI.color("cyan"), 0.16)
		background.add_child(lane)
