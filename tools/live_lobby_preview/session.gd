extends RefCounted
## Local session provider. Replace at integration; never starts networking or writes GameConfig.
signal changed
signal notice(message: String)
signal friend_added(alias_name: String, index: int)
signal friend_removed(index: int)
enum Phase { HOME, SEARCHING, FOUND, DEPARTING, AWAY }
const ACTOR_CAP := 10
const MAPS := ["The Town", "Neon Circuit", "Trippy Forest", "Cat Tower"]
const ALIASES := ["ECHO", "STATIC", "MOTH", "JINX", "GHOST", "PATCH", "HEX", "NOVA", "VEX"]
const ACCESS := ["Invite Only", "Friends Only", "Public"]
var phase: Phase = Phase.HOME
var remaining := 0.0
var alias_name := "STRAY"
var guests: Array[String] = [] # Persistent traveling squad, excluding local leader.
var residents: Array[String] = [] # Other occupants; never silently added to the squad.
var destination := "Neon Circuit"
var event_kind := "Play Here"
var local_humans := 1
var bots := 0
var difficulty := "Normal"
var searches := 0
var returns := 0
var mask_color := Color("ffcc65")
var access := "Invite Only"
var is_host := true
var host_alias := ""
var local_ready := false
var confirmed: Array[String] = []
var pending := ""
var selected_lobby: Dictionary = {}
var home_settings: Dictionary = {}
var directory: Array[Dictionary] = [
	{"id":"sunny", "host":"SUNNY", "map":"The Town", "occupants":["SUNNY","BEAN"], "capacity":10},
	{"id":"patch", "host":"PATCH", "map":"Neon Circuit", "occupants":["PATCH","FINCH","MOSS","PIP","DOT","FIZZ","BOP","ACE"], "capacity":10},
	{"id":"nova", "host":"NOVA", "map":"Cat Tower", "occupants":["NOVA"], "capacity":10}
]

func member_count() -> int:
	return 1+guests.size()+residents.size()

func host_name() -> String:
	return alias_name if is_host else host_alias

func set_access(index: int) -> bool:
	if not is_host or phase!=Phase.HOME or index<0 or index>=ACCESS.size(): return false
	access=ACCESS[index]
	changed.emit()
	return true

func set_destination(index: int) -> bool:
	if not is_host or phase!=Phase.HOME or index<0 or index>=MAPS.size(): return false
	destination=MAPS[index]
	changed.emit()
	return true

func browse() -> Array[Dictionary]:
	return directory.filter(func(row): return row.capacity-row.occupants.size()>=guests.size()+1)

func request_join(id: String) -> bool:
	if phase!=Phase.HOME: return false
	for row in browse():
		if row.id==id:
			selected_lobby=row.duplicate(true)
			pending="join"
			phase=Phase.FOUND
			remaining=30.0
			local_ready=false
			confirmed.clear()
			changed.emit()
			return true
	notice.emit("That lobby no longer has room for the whole squad.")
	return false

func request_ready() -> bool:
	if phase!=Phase.HOME: return false
	pending="start"
	event_kind="Play Here" if is_host else "Visiting "+host_alias
	phase=Phase.FOUND
	remaining=0.0 # Readiness is deliberate, without an expiring timer.
	local_ready=false
	confirmed.clear()
	changed.emit()
	return true

func accept() -> bool:
	if phase!=Phase.FOUND: return false
	local_ready=true
	_try_join()
	changed.emit()
	return true

func simulate_confirmations() -> void:
	if phase!=Phase.FOUND: return
	confirmed.assign(guests if pending=="join" else guests+residents)
	_try_join()
	changed.emit()

func all_ready() -> bool:
	var others: Array=guests if pending=="join" else guests+residents
	return local_ready and others.all(func(person): return confirmed.has(person))

func start_match(simulated_host := false) -> bool:
	if phase!=Phase.FOUND or pending!="start" or not all_ready(): return false
	if not is_host and not simulated_host: return false
	phase=Phase.DEPARTING
	remaining=3.0
	changed.emit()
	return true

func _try_join() -> void:
	if pending!="join" or not all_ready(): return
	# Revalidate capacity at commit; never move a subset of a squad.
	var current: Dictionary={}
	for row in directory:
		if row.id==selected_lobby.get("id",""): current=row
	if current.is_empty() or current.capacity-current.occupants.size()<guests.size()+1:
		cancel()
		notice.emit("Lobby changed or filled. Everyone stayed together in this Hideout.")
		return
	if is_host: home_settings={"access":access,"destination":destination}
	is_host=false
	host_alias=current.host
	residents.assign(current.occupants)
	_clamp_bots()
	destination=current.map
	access="Public"
	phase=Phase.HOME
	pending=""
	selected_lobby={}
	confirmed.clear()
	local_ready=false
	notice.emit("Joined "+host_alias+"'s Hideout together / local simulation.")

func leave_together() -> bool:
	if is_host or phase!=Phase.HOME: return false
	residents.clear()
	is_host=true
	host_alias=""
	access=home_settings.get("access","Invite Only")
	destination=home_settings.get("destination","Neon Circuit")
	home_settings.clear()
	changed.emit()
	notice.emit("Your squad is back in your Hideout. Other occupants stayed behind.")
	return true

func add_public_visitor() -> bool:
	if not is_host or access!="Public" or phase!=Phase.HOME or member_count()>=ACTOR_CAP: return false
	residents.append("VISITOR %d" % (residents.size()+1))
	_clamp_bots()
	changed.emit()
	return true

func tick(delta: float) -> void:
	if phase==Phase.SEARCHING:
		remaining=maxf(0,remaining-delta)
		if remaining==0: found()
	elif phase==Phase.FOUND and pending=="join":
		remaining=maxf(0,remaining-delta)
		if remaining==0: cancel(); notice.emit("Travel confirmation expired. Your squad stayed here.")
	elif phase==Phase.DEPARTING:
		remaining=maxf(0,remaining-delta)
		if remaining==0: phase=Phase.AWAY; changed.emit()

func cancel() -> void:
	if phase==Phase.AWAY: return
	phase=Phase.HOME
	remaining=0
	pending=""
	selected_lobby={}
	local_ready=false
	confirmed.clear()
	changed.emit()

func return_home() -> void:
	if phase!=Phase.AWAY: return
	returns+=1
	phase=Phase.HOME
	pending=""
	local_ready=false
	confirmed.clear()
	remaining=0
	changed.emit()
	notice.emit("Back in "+host_name()+"'s Hideout. Squad and lobby kept.")

func add_friend() -> bool:
	if guests.size()>=ALIASES.size() or member_count()>=ACTOR_CAP or phase!=Phase.HOME: return false
	var person: String=ALIASES[guests.size()]
	guests.append(person)
	_clamp_bots()
	friend_added.emit(person,guests.size()-1)
	changed.emit()
	return true

func remove_friend() -> void:
	if guests.is_empty() or phase!=Phase.HOME: return
	var index:=guests.size()-1
	guests.remove_at(index)
	friend_removed.emit(index)
	changed.emit()

func set_local(humans: int, bot_count: int) -> void:
	if not is_host or phase!=Phase.HOME: return
	local_humans=clampi(humans,1,2)
	bots=clampi(bot_count,0,maxi(0,ACTOR_CAP-maxi(member_count(),local_humans)))
	changed.emit()

# Retained for old capture entry points. These now request explicit readiness.
func rehearse(kind: String) -> bool:
	event_kind=kind
	return request_ready()

func start_search() -> bool:
	if phase!=Phase.HOME: return false
	searches+=1
	phase=Phase.SEARCHING
	remaining=1.0
	changed.emit()
	return true

func found() -> void:
	if phase!=Phase.SEARCHING: return
	phase=Phase.HOME
	request_ready()

func _clamp_bots() -> void:
	bots=mini(bots,maxi(0,ACTOR_CAP-maxi(member_count(),local_humans)))
