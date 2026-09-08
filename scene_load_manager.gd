extends Node

# One owner drains threaded requests even if the requesting UI/connection leaves.
# Requests are serialized to avoid loading several full maps at once.
var _jobs: Array[Dictionary] = []
var _next_ticket := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func request_scene(path: String, completed: Callable) -> int:
	_next_ticket += 1
	var ticket := _next_ticket
	for job in _jobs:
		if str(job["path"]) == path:
			job["callbacks"][ticket] = completed
			return ticket
	_jobs.append({"path": path, "started": false, "callbacks": {ticket: completed}})
	set_process(true)
	return ticket

func cancel(ticket: int) -> void:
	for index in range(_jobs.size() - 1, -1, -1):
		var job := _jobs[index]
		job["callbacks"].erase(ticket)
		if job["callbacks"].is_empty() and not bool(job["started"]):
			_jobs.remove_at(index)
	set_process(not _jobs.is_empty())

func progress(ticket: int) -> float:
	for job in _jobs:
		if job["callbacks"].has(ticket) and bool(job["started"]):
			var values: Array = []
			ResourceLoader.load_threaded_get_status(str(job["path"]), values)
			return float(values[0]) if not values.is_empty() else 0.0
	return 0.0

func _process(_delta: float) -> void:
	if _jobs.is_empty():
		set_process(false)
		return
	var job := _jobs[0]
	var path := str(job["path"])
	if not bool(job["started"]):
		if not ResourceLoader.exists(path) or ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
			_complete(null)
			return
		job["started"] = true
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_complete(ResourceLoader.load_threaded_get(path) as PackedScene)
	elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_complete(null)

func _complete(scene: PackedScene) -> void:
	var callbacks: Dictionary = _jobs.pop_front()["callbacks"]
	for callback: Callable in callbacks.values():
		if callback.is_valid():
			callback.call(scene)
	set_process(not _jobs.is_empty())

func _exit_tree() -> void:
	# Godot has no threaded-load cancellation API. Join the one active worker
	# before resource teardown; never deliver callbacks during shutdown.
	for job in _jobs:
		if bool(job["started"]):
			ResourceLoader.load_threaded_get(str(job["path"]))
	_jobs.clear()
