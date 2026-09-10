extends RefCounted
## Session-only wins. The server owns online updates; never written to disk.
static func award(id: String, player_name: String) -> void:
	var row: Dictionary=HideoutSession.scrap_lobby_wins.get(id,{"wins":0})
	row["wins"]=int(row.wins)+1
	row["name"]=player_name.strip_edges().left(24)
	HideoutSession.scrap_lobby_wins[id]=row

static func render(board: Label3D, online: bool) -> void:
	if not is_instance_valid(board): return
	var standings: Dictionary=HideoutSession.scrap_lobby_wins.duplicate(true)
	if online:
		for peer in NetworkManager.peer_ids_sorted():
			var id:=str(NetworkManager.actor_id_for_peer(peer))
			var row: Dictionary=standings.get(id,{"wins":0})
			row["name"]=NetworkManager.peer_name(peer)
			standings[id]=row
	var rows: Array=[]
	for id in standings:
		var row: Dictionary=standings[id].duplicate()
		row["id"]=id
		rows.append(row)
	rows.sort_custom(func(a,b):
		if int(a.wins)!=int(b.wins): return int(a.wins)>int(b.wins)
		return str(a.id)<str(b.id))
	var lines: PackedStringArray=[]
	for index in mini(10,rows.size()):
		var row: Dictionary=rows[index]
		lines.append("%02d  %s  /  %d %s" % [index+1,str(row.name).left(18),int(row.wins),"WIN" if int(row.wins)==1 else "WINS"])
	if rows.is_empty(): lines.append("FIRST WIN TAKES THE LEAD")
	var next: String="\n".join(lines)
	if board.text!=next: board.text=next
