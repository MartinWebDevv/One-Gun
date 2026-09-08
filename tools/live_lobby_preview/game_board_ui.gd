extends RefCounted
## Physical Game Board and Squad kiosk share the same isolated session state.
static func build(ui: CanvasLayer, page: String) -> void:
	var s: RefCounted=ui.session
	ui._copy("GAME BOARD" if page!="party" else "YOUR SQUAD",43,ui.G.GOLD)
	ui._copy(s.host_name()+"'s Hideout / "+s.access,23,ui.G.CYAN)
	ui._copy("F6 simulation: sample lobbies and visitors. No network invitations or matches.",18)
	if page=="party":
		ui._copy("TRAVELING TOGETHER / %d" % (s.guests.size()+1),25)
		ui._copy(s.alias_name+" / YOU · SQUAD LEADER",21,ui.G.GREEN)
		for person in s.guests: ui._copy(person+" / SQUAD",21)
		var invite: Button=ui._button(ui.contents,"SIMULATE FRIEND INVITE","add_friend")
		invite.disabled=s.member_count()>=10 or s.phase!=s.Phase.HOME
		var remove: Button=ui._button(ui.contents,"REMOVE LAST SQUAD FRIEND","remove_friend",null,ui.G.PAPER)
		remove.disabled=s.guests.is_empty() or s.phase!=s.Phase.HOME
		if not s.residents.is_empty():
			ui._copy("ALSO IN THIS HIDEOUT",23,ui.G.CYAN)
			for person in s.residents: ui._copy(person+" / LOBBY",20)
		if not s.is_host:
			ui._button(ui.contents,"LEAVE TOGETHER","leave_together",null,ui.G.ORANGE)
		ui._button(ui.contents,"GAME BOARD","page","events")
		return
	if s.phase==s.Phase.FOUND:
		ui._copy("JOIN TOGETHER" if s.pending=="join" else "READY TO PLAY?",32,ui.G.GREEN)
		ui._copy((s.selected_lobby.get("host","")+"'s Hideout") if s.pending=="join" else s.destination,26)
		ui._copy("YOU / "+("READY" if s.local_ready else "NOT READY"),23)
		var others: Array=s.guests if s.pending=="join" else s.guests+s.residents
		for person in others: ui._copy(person+" / "+("READY" if person in s.confirmed else "WAITING"),20)
		ui._button(ui.contents,"I'M READY" if s.pending=="start" else "CONFIRM MY TRAVEL","accept")
		if not others.is_empty(): ui._button(ui.contents,"SIMULATE OTHERS CONFIRMING","confirm_others",null,ui.G.CYAN)
		if s.pending=="start":
			var start: Button=ui._button(ui.contents,"START MATCH" if s.is_host else "SIMULATE HOST START","start_match" if s.is_host else "host_start",null,ui.G.GREEN)
			start.disabled=not s.all_ready()
		ui._button(ui.contents,"CANCEL / STAY HERE","cancel",null,ui.G.ORANGE)
		return
	if s.phase!=s.Phase.HOME:
		ui._copy("A match rehearsal is already in progress.",23)
		ui._button(ui.contents,"CANCEL COUNTDOWN","cancel")
		return
	match page:
		"events":
			ui._copy("Choose where your squad plays.",25)
			ui._button(ui.contents,"PLAY HERE","page","private")
			ui._button(ui.contents,"FIND A LOBBY","page","join",ui.G.CYAN)
			ui._copy("Invite friends at the Squad kiosk. Your Hideout stays private until you change access.",21)
		"private","local":
			ui._copy("PLAY HERE",34)
			if s.is_host:
				ui._map_picker()
				ui._option("WHO CAN JOIN",s.ACCESS,s.ACCESS.find(s.access),"access")
				ui._copy(["Only invited players can enter.","Your friends can drop in without an invite.","Listed publicly for anyone browsing lobbies."][s.ACCESS.find(s.access)],20)
				ui._option("PRACTICE MATCH BOTS",["0","1","2","3","4","5","6","7","8","9"],s.bots,"bots")
				ui._copy("Bots use remaining capacity. Match setup is a rehearsal; Scrap Yard combat is playable.",18)
				if s.access=="Public": ui._button(ui.contents,"SIMULATE PUBLIC VISITOR","public_visitor",null,ui.G.CYAN)
			else:
				ui._copy(s.host_alias+" controls this lobby's settings and start.",24)
				ui._copy("MAP / "+s.destination,24)
			ui._button(ui.contents,"READY UP","ready",null,ui.G.GREEN)
			ui._button(ui.contents,"BACK","page","events",ui.G.PAPER)
		"join":
			ui._copy("FIND A LOBBY",34)
			ui._copy("Showing room for all %d squad members. Everyone confirms before traveling." % (s.guests.size()+1),21)
			for row in s.browse():
				ui._copy("%s / %s / %d OF %d" % [row.host,row.map,row.occupants.size(),row.capacity],23,ui.G.CYAN)
				ui._button(ui.contents,"JOIN TOGETHER — %d PLAYERS" % (s.guests.size()+1),"join_lobby",row.id)
			if s.browse().is_empty(): ui._copy("No sample lobby has room for the whole squad.",23)
			ui._button(ui.contents,"BACK","page","events",ui.G.PAPER)
