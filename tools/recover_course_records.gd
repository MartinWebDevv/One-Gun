extends SceneTree
func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--recover-course-records"):
		quit(1);return
	var records=preload("res://maps/hideout/course_records.gd").new()
	records.configure_profile(false)
	print("COURSE RECOVERY ",error_string(records.save_error)," / ",records.personal_times.size()," saved buckets; original versions retained")
	quit(0 if records.save_error==OK else 1)
