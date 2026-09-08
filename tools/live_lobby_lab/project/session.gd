extends RefCounted
## Deliberately in-memory UI rehearsal data; never apply this to GameConfig.
signal changed
signal notice(message: String)
signal friend_added(alias_name: String, index: int)
signal friend_removed(index: int)
enum Phase { HOME, SEARCHING, FOUND, DEPARTING, AWAY }
const ACTOR_CAP := 10 # Audited from match_limits.gd; no runtime import.
const MAPS := ["The Town","Neon Circuit","Trippy Forest","Cat Tower"]
const ALIASES := ["ECHO","STATIC","MOTH","JINX","GHOST","PATCH","HEX","NOVA","VEX"]
var phase: Phase = Phase.HOME
var remaining := 0.0
var alias_name := "STRAY"
var guests: Array[String] = []
var destination := "Neon Circuit"
var event_kind := "Public event"
var local_humans := 1
var bots := 3
var difficulty := "Normal"
var searches := 0
var returns := 0
var hits := 0
var shots := 0
var mask_color := Color("d8d23e")

func start_search() -> bool:
	if phase != Phase.HOME: return false
	event_kind = "Public event"
	phase = Phase.SEARCHING
	remaining = 8.0
	searches += 1
	notice.emit("Demo search started. Keep exploring; R accepts the ready check anywhere.")
	changed.emit()
	return true

func tick(delta: float) -> void:
	if phase not in [Phase.SEARCHING,Phase.FOUND,Phase.DEPARTING]: return
	remaining = maxf(0,remaining-delta)
	if remaining > 0: return
	match phase:
		Phase.SEARCHING: found()
		Phase.FOUND:
			cancel()
			notice.emit("Ready check expired. Your party is still here; no match was entered.")
		Phase.DEPARTING:
			phase = Phase.AWAY
			changed.emit()

func found() -> void:
	if phase != Phase.SEARCHING: return
	phase = Phase.FOUND
	remaining = 15.0
	notice.emit("MATCH FOUND / DEMO. Press R or use the on-screen Accept button.")
	changed.emit()

func accept() -> bool:
	if phase != Phase.FOUND: return false
	phase = Phase.DEPARTING
	remaining = 4.0
	changed.emit()
	return true

func rehearse(kind: String) -> bool:
	if phase != Phase.HOME: return false
	event_kind = kind
	phase = Phase.FOUND
	remaining = 15.0
	changed.emit()
	return true

func cancel() -> void:
	if phase == Phase.AWAY: return
	phase = Phase.HOME
	remaining = 0
	changed.emit()
	notice.emit("Rehearsal cancelled. Party and appearance kept.")

func return_home() -> void:
	if phase != Phase.AWAY: return
	returns += 1
	phase = Phase.HOME
	remaining = 0
	changed.emit()
	notice.emit("Back at Platform 01. Party, mask, and range scores kept in this test session.")

func add_friend() -> bool:
	if guests.size() >= ACTOR_CAP-1 or phase != Phase.HOME:
		return false
	var label: String = ALIASES[guests.size()]
	guests.append(label)
	friend_added.emit(label,guests.size()-1)
	changed.emit()
	return true

func remove_friend() -> void:
	if guests.is_empty() or phase != Phase.HOME: return
	var index := guests.size()-1
	guests.remove_at(index)
	friend_removed.emit(index)
	changed.emit()

func set_local(humans: int, bot_count: int) -> void:
	local_humans = clampi(humans,1,2)
	bots = clampi(bot_count,0,ACTOR_CAP-local_humans)
	changed.emit()
