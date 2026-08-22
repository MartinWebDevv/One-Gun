extends SceneTree

# Loads the real main-menu scene and exercises both neighboring overlay
# callbacks. This guards the incremental Account & Store insertion from
# regressing the existing Character Customization flow.

var _failed := false


func _initialize() -> void:
	var supabase = root.get_node_or_null("SupabaseManager")
	if supabase != null:
		# The catalog HTTP contract is tested separately; this layout/callback test
		# must remain deterministic and must not contact the live backend.
		supabase.project_url = ""
		supabase.publishable_key = ""
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var scene_resource = load("res://main_menu.tscn")
	_check(scene_resource is PackedScene, "main menu scene did not load")
	if not scene_resource is PackedScene:
		quit(1)
		return
	var menu = scene_resource.instantiate()
	root.add_child(menu)
	# This test covers callbacks, not ambient map rotation. Prevent the real
	# cycler from starting a threaded second-map request during slow CI startup.
	var map_cycler = menu.get("_map_cycler") as Node
	map_cycler.set_process(false)
	await process_frame
	await process_frame

	menu.call("_on_account_store_pressed")
	await process_frame
	var account_overlay = menu.get("_supabase_overlay")
	var modal_layer = menu.get("_modal_layer") as Control
	_check(account_overlay != null and is_instance_valid(account_overlay),
		"Account & Store callback did not create its overlay")
	_check(modal_layer != null and modal_layer.visible,
		"Account & Store did not activate the modal layer")
	if account_overlay != null and is_instance_valid(account_overlay):
		account_overlay.call("_close")
	await process_frame
	_check(menu.get("_supabase_overlay") == null,
		"Account & Store close left a stale overlay reference")

	menu.call("_on_character_customization_pressed")
	await process_frame
	var customization = menu.get("_character_customization_overlay")
	_check(customization != null and is_instance_valid(customization),
		"existing Character Customization callback was regressed")
	if customization != null and is_instance_valid(customization):
		menu.call("_close_character_customization")

	menu.queue_free()
	await process_frame
	if _failed:
		quit(1)
		return
	print("SUPABASE MAIN MENU VALIDATION OK: account/store and customization callbacks remain isolated")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("SUPABASE MAIN MENU VALIDATION FAILED: %s" % message)
