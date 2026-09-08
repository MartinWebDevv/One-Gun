extends RefCounted
const Records = preload("res://tools/live_lobby_preview/course_records.gd")

func run(lab: Node3D, test: Node) -> void:
	var store := Records.new()
	var path := ProjectSettings.globalize_path("res://tools/live_lobby_preview/artifacts/course_records_test.json")
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	store.configure(path)
	store.set_members([{"id":"a","name":"ALPHA"},{"id":"b","name":"BRAVO"}])
	test.check(store.lobby_rows("course/standard").size()==2 and store.personal_best("course/standard","a")==-1,"board roster starts without invented times")
	test.check(not store.submit_completed_run("course/standard","outsider",12345) and not store.submit_completed_run("course/standard","a",-1),"records reject unknown runners and invalid times")
	store.submit_completed_run("course/standard","a",32765)
	store.submit_completed_run("course/standard","b",29995)
	store.submit_completed_run("course/standard","a",35000)
	test.check(store.lobby_rows("course/standard")[0].id=="b" and store.lobby_rows("course/standard")[1].time_ms==32765,"shared lobby standings sort fastest first and preserve each runner's best")
	test.check(store.personal_best("course/standard","a")==32765 and store.personal_best("course/standard","b")==29995,"Your Best resolves separately for each viewing player")
	store.submit_completed_run("course/assisted","a",24000)
	test.check(store.personal_best("course/standard","a")==32765 and store.personal_best("course/assisted","a")==24000,"assisted and standard times stay in separate record categories")
	test.check(store.personal_best("different_course/standard","a")==-1,"new course versions cannot inherit incompatible records")
	store.set_members([{"id":"a","name":"RENAMED"}])
	test.check(store.lobby_rows("course/standard").size()==1 and store.lobby_rows("course/standard")[0].name=="RENAMED" and store.personal_best("course/standard","a")==32765,"departed friends disappear and an alias change preserves stable-identity records")
	var restored := Records.new()
	restored.configure(path)
	restored.set_members([{"id":"a","name":"ALPHA"},{"id":"b","name":"BRAVO"}])
	test.check(store.save_error==OK and restored.personal_best("course/standard","a")==32765 and restored.personal_best("course/standard","b")==29995,"personal records persist and reload independently across preview sessions")
	test.check(restored.lobby_rows("course/standard")[0].time_ms==-1,"a fresh lobby does not import the previous lobby's standings")
	test.check(not restored.world_available() and restored.world_rows("course/standard").is_empty(),"World page stays explicitly unavailable without live services")
	DirAccess.remove_absolute(path)
	var marker: Marker3D=lab.station.get_node("CourseBoardApproach")
	lab.pilot.position=marker.position
	lab.pilot.velocity=Vector3.ZERO
	await test.settle(4)
	test.check(lab.nearby.has("course_board"),"wall board between the course doors has a real interaction area")
	var event := InputEventAction.new()
	event.action="p1_interact"
	event.pressed=true
	lab._input(event)
	test.check(lab.ui.page=="course_board" and not lab.controls_enabled,"saved Interact opens the physical record board")
	for tab in ["personal","world","lobby"]:
		lab._action("course_tab",tab)
		test.check(lab.training.board_tab==tab and lab.ui.contents.get_child_count()>3,"record board renders the "+tab+" page")
	lab._open("")
