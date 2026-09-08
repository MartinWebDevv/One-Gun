extends Node

class GuestLobby extends "res://game_setup.gd":
	func _ready() -> void: pass
	func _is_net() -> bool: return true
	func _selection_unavailable_reason() -> String: return ""
var _delivered: Array = []
var _failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "res://maps/test/title_bg_map.tscn"
	var cancelled := SceneLoadManager.request_scene(path, func(_scene): _delivered.append("cancelled"))
	SceneLoadManager.request_scene(path, func(scene): _delivered.append("loaded" if scene is PackedScene else "failed"))
	SceneLoadManager.cancel(cancelled)
	SceneLoadManager.request_scene("res://missing_quality_validation_map.tscn", func(scene): _delivered.append("missing" if scene == null else "unexpected"))
	var deadline := Time.get_ticks_msec() + 15000
	while _delivered.size() < 2 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(_delivered == ["loaded", "missing"], "cancelled/shared/failed request delivery was incorrect: %s" % [_delivered])
	_check(SceneLoadManager._jobs.is_empty(), "completed loader retained jobs")
	var lobby := preload("res://game_setup.tscn").instantiate()
	add_child(lobby)
	await get_tree().process_frame
	lobby._launch_match()
	_check(lobby._local_load_ticket > 0, "local launch was not asynchronous")
	lobby._cancel_local_load()
	_check(lobby._local_load_ticket == 0, "local cancel retained ticket")
	lobby.queue_free()
	await get_tree().process_frame
	var guest := GuestLobby.new()
	add_child(guest)
	guest._launch_match()
	_check(guest._local_load_ticket == 0, "guest fell through into local launch")
	guest.queue_free()
	if _failures.is_empty(): print("SCENE_LOAD_VALIDATION: PASS shared/cancel/missing/local-cancel")
	else:
		for message in _failures: push_error(message)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok: _failures.append(message)
