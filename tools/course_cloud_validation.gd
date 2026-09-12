extends SceneTree
const Records=preload("res://maps/hideout/course_records.gd")
const Cloud=preload("res://supabase/course_cloud.gd")
const BUCKET="flow_circuit_v3/dash3/sprint0/jump7.000/standard"
const OLD="flow_circuit_v2/dash3/sprint0/jump7.000/standard"
const POWER="flow_circuit_v3/dash3/sprint0/jump7.000/powerup"
const USER_A="11111111-1111-4111-8111-111111111111"
const USER_B="22222222-2222-4222-8222-222222222222"
const DIR="res://artifacts/course_cloud_validation"
var failures := 0
class FakeBackend extends Node:
	var user_id := USER_A
	var fail_requests := false
	var calls: Array=[]
	var remote: Dictionary={USER_A:{BUCKET:12000},USER_B:{BUCKET:22000}}
	func current_user_id() -> String: return user_id
	func is_authenticated() -> bool: return not user_id.is_empty()
	func _authenticated_request(_path: String,_method: int,payload: Dictionary,expected_user: String) -> Dictionary:
		calls.append({"user":expected_user,"bests":payload.p_bests.duplicate(true)})
		if expected_user!=user_id: return {"ok":false}
		var failure := fail_requests
		var response: Dictionary=remote.get(expected_user,{}).duplicate(true)
		if not failure:
			for bucket in payload.p_bests:
				response[bucket]=mini(int(response.get(bucket,3600001)),int(payload.p_bests[bucket]))
			remote[expected_user]=response.duplicate(true)
		await get_tree().create_timer(0.04).timeout
		return {"ok":not failure,"data":{"version":1,"bests":response}}

func _initialize() -> void: _run.call_deferred()
func _check(ok: bool, message: String) -> void:
	if ok: print("PASS: ",message)
	else: failures+=1;push_error(message)
func _write(path: String, personal: Dictionary) -> void:
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify({"version":1,"personal":personal}))
func _settled(cloud: Node) -> void:
	var until:=Time.get_ticks_msec()+2500
	await process_frame
	while (cloud.busy or cloud.scheduled) and Time.get_ticks_msec()<until: await process_frame
	_check(not cloud.busy and not cloud.scheduled,"cloud request settles")
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var a: String="account:"+USER_A.sha256_text()
	var b: String="account:"+USER_B.sha256_text()
	var base: String=DIR+"/recovery_"+str(Time.get_ticks_usec())+".json"
	_write(base,{OLD:{a:11002},BUCKET:{a:10841,b:15000},POWER.replace("v3","v2"):{a:9283}})
	var records:=Records.new()
	records.configure(base)
	_check(records.personal_best(BUCKET,a)==10841,"recovery preserves a faster new Standard time")
	_check(records.personal_best(POWER,a)==9283,"old Power-Up best becomes visible again")
	_check(records.personal_best(OLD,a)==11002,"original version history remains intact")
	_check(records.personal_best(BUCKET,b)==15000,"recovery keeps account identities separate")
	records.merge_bests(a,{BUCKET:10900})
	_check(records.personal_best(BUCKET,a)==10841,"slower import cannot overwrite a best")
	records.merge_bests(a,{BUCKET:10500})
	_check(FileAccess.file_exists(base+".bak"),"saving retains the previous file as a backup")
	_write(base+".tmp",{BUCKET:{a:10400}})
	var restored:=Records.new();restored.configure(base)
	_check(restored.personal_best(BUCKET,a)==10400,"interrupted atomic write is recovered")
	var corrupt:=FileAccess.open(base,FileAccess.WRITE);corrupt.store_string("interrupted");corrupt.close()
	restored=Records.new();restored.configure(base)
	_check(restored.personal_best(BUCKET,a)==10400,"corrupt primary recovers valid backup/pending times")

	var fake:=FakeBackend.new();root.add_child(fake)
	var cloud:=Cloud.new();root.add_child(cloud)
	cloud.backend=fake
	cloud.enabled=true
	cloud.account_id=USER_A
	cloud.store.configure(DIR+"/sync_"+str(Time.get_ticks_usec())+".json")
	cloud.request_sync();await _settled(cloud)
	_check(cloud.store.personal_best(BUCKET,a)==12000,"empty local save restores the account best from cloud")
	cloud.store.merge_bests(a,{BUCKET:9000})
	await process_frame
	cloud.store.merge_bests(a,{BUCKET:8000})
	await _settled(cloud)
	_check(fake.remote[USER_A][BUCKET]==8000,"a faster finish during sync is sent after the in-flight reply")
	fake.fail_requests=true
	cloud.store.merge_bests(a,{BUCKET:7500});await _settled(cloud)
	var disk:=Records.new();disk.configure(cloud.store.storage_path)
	_check(disk.personal_best(BUCKET,a)==7500 and cloud.retry.time_left>0,"connection failure keeps a durable local best and schedules retry")
	fake.fail_requests=false
	cloud.request_sync();await _settled(cloud)
	_check(fake.remote[USER_A][BUCKET]==7500,"reconnecting uploads the offline best")
	cloud.has_synced=false;cloud.request_sync();await process_frame
	fake.user_id=USER_B;cloud._identity_changed("authenticated")
	await _settled(cloud)
	_check(cloud.store.personal_best(BUCKET,b)==22000,"account switch discards an old-account response")
	_check(fake.remote[USER_B][BUCKET]==22000,"old account time is never uploaded to the next account")
	_check(cloud.store.personal_best(BUCKET,a)==7500,"switching accounts retains the first account cache")
	cloud.queue_free();fake.queue_free()
	print("COURSE_CLOUD_VALIDATION_COMPLETE failures=",failures)
	quit(1 if failures else 0)
