extends Label

func _ready() -> void:
	name = "ConnectionStatus"
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -230
	offset_right = -16
	offset_top = 12
	offset_bottom = 34
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 14)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_refresh)
	add_child(timer)
	timer.start()
	_refresh()

func _refresh() -> void:
	visible = NetworkManager.is_online() and bool(PlayerPrefs.get_setting("network_status_enabled"))
	if not visible:
		return
	if NetworkManager.is_host():
		text = "HOST"
		modulate = Color(0.75, 0.83, 0.9)
		return
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		text = "CONNECTION LOST"
		modulate = Color(1.0, 0.45, 0.3)
		return
	var remote := peer.get_peer(1)
	if remote == null:
		text = "CONNECTING"
		return
	var milliseconds := int(remote.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	text = "%d ms" % milliseconds
	modulate = Color(1.0, 0.72, 0.25) if milliseconds >= 120 else Color(0.75, 0.83, 0.9)
