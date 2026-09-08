extends RefCounted
## Presentation of the real session. Match rules remain in GameConfig.
signal changed
enum Phase { HOME, SEARCHING, FOUND, DEPARTING, AWAY }
var phase := Phase.HOME
var alias_name := ""
var guests: Array = []
var residents: Array = []
var access := "Only Me"
var destination := "Choose a map"
var local_ready := false
var remaining := 0.0
var pending := ""
var local_humans := 1
var bots := 0

func refresh() -> void:
	alias_name = NetworkManager.local_name()
	guests.clear()
	residents.clear()
	if NetworkManager.is_online():
		for id in NetworkManager.peer_ids_sorted():
			if id != NetworkManager.local_id(): residents.append(NetworkManager.peer_name(id))
		access = "Public" if NetworkManager.lobby_privacy == "public" else "Unlisted"
		local_ready = NetworkManager.is_peer_lobby_ready(NetworkManager.local_id())
	else:
		access = "Only Me"
		local_ready = false
	phase = Phase.DEPARTING if NetworkManager._prelaunch_active else Phase.HOME
	remaining = NetworkManager._prelaunch_seconds
	local_humans = 2 if GameConfig.split_screen_enabled else 1
	bots = GameConfig.bot_configs.size()
	var index := MapRegistry.find_index_by_path(HideoutSession.selected_map)
	destination = str(MapRegistry.get_map(index).get("name", "Random Map")) if index >= 0 else "Random Map"
	changed.emit()

func member_count() -> int:
	return NetworkManager.peers.size() if NetworkManager.is_online() else local_humans

func tick(_delta: float) -> void:
	pass
