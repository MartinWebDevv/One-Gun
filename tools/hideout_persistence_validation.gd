extends SceneTree
const Records = preload("res://maps/hideout/course_records.gd")
const BASE := "res://artifacts/hideout_migration/"
var failed := false

func _initialize() -> void:
	var path := BASE+"persistence_validation.json"
	var legacy := BASE+"persistence_legacy.json"
	for file in [path,legacy]:
		if FileAccess.file_exists(file): DirAccess.remove_absolute(file)
	var store := Records.new()
	store.configure(path)
	store.set_members([{"id":"account:a","name":"A"},{"id":"account:b","name":"B"}])
	store.submit_completed_run("course/standard","account:a",32000)
	store.submit_completed_run("course/standard","account:b",25000)
	store.submit_completed_run("course/powerup","account:a",21000)
	var old := Records.new()
	old.configure(legacy)
	old.set_members([{"id":"account:a","name":"A"}])
	old.submit_completed_run("course/standard","account:a",29000)
	old.submit_completed_run("course/powerup","account:a",23000)
	store.merge_history(legacy)
	check(store.save_error==OK,"history merge saves successfully")
	var restored := Records.new()
	restored.configure(path)
	restored.set_members([{"id":"account:a","name":"RENAMED"}])
	check(restored.personal_best("course/standard","account:a")==29000 and restored.personal_best("course/powerup","account:a")==21000,"migration keeps faster solo or online time per category")
	check(restored.lobby_rows("course/standard")[0].time_ms==29000,"saved personal best appears in fresh home without a run")
	check(restored.saved_bests("account:a")=={"course/standard":29000,"course/powerup":21000},"upload contains only viewing account records")
	var lobby := Records.new()
	lobby.set_members([{"id":"77","name":"RENAMED"}])
	lobby.share_saved_bests("77",restored.saved_bests("account:a"))
	check(lobby.lobby_rows("course/standard")[0].time_ms==29000 and lobby.lobby_details.is_empty(),"new network actor receives personal history without invented finishes")
	check(not lobby.share_saved_bests("outsider",{"course/standard":1000}),"unknown member cannot import history")
	check(not lobby.share_saved_bests("77",{"course/standard":-1,"bad":INF,"fraction":1200.5}),"invalid imported times are rejected")
	lobby.submit_completed_run("course/standard","77",35000)
	check(lobby.lobby_rows("course/standard")[0].time_ms==29000,"slower run keeps imported PB")
	lobby.submit_completed_run("course/standard","77",27000)
	check(lobby.lobby_rows("course/standard")[0].time_ms==27000,"faster run replaces imported PB")
	restored.submit_completed_run("course/standard","account:a",27000)
	var disk := Records.new()
	disk.configure(path)
	check(disk.personal_best("course/standard","account:a")==27000 and disk.personal_best("course/standard","account:b")==25000,"new best survives reopening without modifying another account")
	for file in [path,legacy]: DirAccess.remove_absolute(file)
	if not failed: print("HIDEOUT_PERSISTENCE_COMPLETE")
	quit(1 if failed else 0)

func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ",label)
	else:
		failed=true
		push_error(label)
