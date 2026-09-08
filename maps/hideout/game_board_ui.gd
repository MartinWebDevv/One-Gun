extends RefCounted
## Kiosks route to the same production menus and authority.
static func build(ui: CanvasLayer, page: String) -> void:
	ui._copy("SQUAD" if page=="party" else "GAME BOARD",43,ui.G.GOLD)
	var online := NetworkManager.is_online()
	var owner := NetworkManager.peer_name(NetworkManager.lobby_controller_peer_id if NetworkManager.is_dedicated_session() else 1) if online else NetworkManager.local_name()
	ui._copy(owner+"'s Hideout / "+ui.session.access,23,ui.G.CYAN)
	if page == "party":
		ui._button(ui.contents,"FRIENDS & INVITATIONS","page","friends",ui.G.CYAN)
		ui._copy("IN THIS HIDEOUT",25)
		if online:
			for id in NetworkManager.peer_ids_sorted():
				var suffix := " / HOST" if NetworkManager.is_lobby_controller(id) else (" / READY" if NetworkManager.is_peer_lobby_ready(id) else " / NOT READY")
				ui._copy(NetworkManager.peer_name(id)+suffix,21)
			ui._button(ui.contents,"ROSTER, TEAMS & MATCH SETUP","page","match_setup")
			ui._button(ui.contents,"LEAVE HIDEOUT","leave",null,ui.G.ORANGE)
		else:
			ui._copy(NetworkManager.local_name()+" / YOU",22)
			ui._button(ui.contents,"HOST FOR FRIENDS","host")
		return
	if page == "private":
		ui._copy("WHO CAN FIND YOUR HIDEOUT",26)
		ui._copy("Unlisted: join by code or address. Public: shown in the lobby browser.",21)
		if NetworkManager.can_manage_lobby():
			ui._button(ui.contents,"UNLISTED","access","private")
			ui._button(ui.contents,"PUBLIC","access","public",ui.G.CYAN)
		else: ui._copy("The host controls visibility.",22)
		return
	ui._button(ui.contents,"PLAY HERE / MATCH SETUP","page","match_setup")
	if not online:
		ui._button(ui.contents,"SOLO + BOTS","solo",null,ui.G.PAPER)
		ui._button(ui.contents,"2 PLAYER SPLITSCREEN","local",null,ui.G.PAPER)
		ui._button(ui.contents,"HOST A HIDEOUT","host",null,ui.G.GREEN)
		ui._button(ui.contents,"FIND A LOBBY","browse",null,ui.G.CYAN)
		ui._button(ui.contents,"FIND A MATCH","queue",null,ui.G.GREEN)
	if online:
		ui._button(ui.contents,"HIDEOUT VISIBILITY","page","private",ui.G.PAPER)
		if NetworkManager._prelaunch_active and NetworkManager.can_manage_lobby():
			ui._button(ui.contents,"CANCEL COUNTDOWN","cancel",null,ui.G.ORANGE)
		elif not NetworkManager.lobby_in_progress and not NetworkManager.can_manage_lobby():
			ui._button(ui.contents,"NOT READY" if NetworkManager.is_peer_lobby_ready(NetworkManager.local_id()) else "READY UP","ready")
	ui._button(ui.contents,"SQUAD","page","party",ui.G.PAPER)
