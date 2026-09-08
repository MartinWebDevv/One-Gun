extends RefCounted
## Local provider for the course board. Replace the provider, not the board UI,
## when host-authoritative lobby records and world-service records are connected.
signal changed
var members: Dictionary = {}
var lobby_times: Dictionary = {}
var personal_times: Dictionary = {}
var lobby_details: Dictionary = {}
var storage_path := ""
var save_error := OK

func configure(path := "") -> void:
	storage_path=path
	if path.is_empty() or not FileAccess.file_exists(path): return
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("version")!=1: return
	var buckets: Variant=parsed.get("personal",{})
	if not buckets is Dictionary: return
	for bucket in buckets:
		if not buckets[bucket] is Dictionary: continue
		var records := {}
		for id in buckets[bucket]:
			var time: Variant=buckets[bucket][id]
			if _valid_time(time): records[str(id)]=int(time)
		personal_times[str(bucket)]=records

func set_members(roster: Array) -> void:
	var next := {}
	for member in roster:
		var id := str(member.get("id",""))
		if not id.is_empty(): next[id]=str(member.get("name","PLAYER")).strip_edges().left(24)
	if members==next: return
	members=next
	changed.emit()

func submit_completed_run(bucket: String, actor_id: String, time_ms: int, falls := 0) -> bool:
	# Called only after the course controller has accepted every checkpoint.
	# A future online provider must accept host-validated finishes, not client times.
	if bucket.is_empty() or not members.has(actor_id) or not _valid_time(time_ms): return false
	if not lobby_details.has(bucket): lobby_details[bucket]={}
	var previous: Dictionary=lobby_details[bucket].get(actor_id,{})
	lobby_details[bucket][actor_id]={"last_ms":time_ms,"falls":falls,"finishes":int(previous.get("finishes",0))+1}
	if not lobby_times.has(bucket): lobby_times[bucket]={}
	if not personal_times.has(bucket): personal_times[bucket]={}
	var lobby: Dictionary=lobby_times[bucket]
	var personal: Dictionary=personal_times[bucket]
	if not lobby.has(actor_id) or time_ms<int(lobby[actor_id]): lobby[actor_id]=time_ms
	if not personal.has(actor_id) or time_ms<int(personal[actor_id]):
		personal[actor_id]=time_ms
		_save()
	changed.emit()
	return true

func lobby_rows(bucket: String) -> Array:
	var rows: Array=[]
	var times: Dictionary=lobby_times.get(bucket,{})
	for id in members:
		var detail: Dictionary=lobby_details.get(bucket,{}).get(id,{})
		rows.append({"id":id,"name":members[id],"time_ms":int(times.get(id,-1)),"last_ms":int(detail.get("last_ms",-1)),"falls":int(detail.get("falls",0)),"finishes":int(detail.get("finishes",0))})
	rows.sort_custom(func(a,b):
		if a.time_ms!=b.time_ms:
			if a.time_ms<0: return false
			if b.time_ms<0: return true
			return a.time_ms<b.time_ms
		return str(a.id)<str(b.id))
	return rows

func personal_best(bucket: String, viewer_id: String) -> int:
	return int(personal_times.get(bucket,{}).get(viewer_id,-1))

func world_available() -> bool:
	return false

func world_rows(_bucket: String) -> Array:
	return []

func _save() -> void:
	if storage_path.is_empty(): return
	save_error=DirAccess.make_dir_recursive_absolute(storage_path.get_base_dir())
	if save_error!=OK: return
	var file := FileAccess.open(storage_path+".tmp",FileAccess.WRITE)
	if file==null:
		save_error=FileAccess.get_open_error()
		return
	file.store_string(JSON.stringify({"version":1,"personal":personal_times}))
	file.flush()
	file.close()
	save_error=DirAccess.rename_absolute(storage_path+".tmp",storage_path)

func _valid_time(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=1000 and float(value)<=3600000 and float(value)==floorf(float(value))
