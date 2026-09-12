extends Node
## Durable local-first PB cache; cloud writes are authenticated and minimum-only.
const Records = preload("res://maps/hideout/course_records.gd")
signal account_changed
signal status_changed
var store: RefCounted = Records.new()
var backend: Node
var enabled := false
var status := "Saved on this PC / sign in for cloud backup"
var account_id := ""
var generation := 0
var busy := false
var scheduled := false
var merging := false
var has_synced := false
var synced_bests: Dictionary = {}
var retry: Timer

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	enabled=not OS.has_feature("dedicated_server") and DisplayServer.get_name()!="headless" and not OS.get_cmdline_user_args().has("--hideout-test")
	store.configure_profile(not enabled)
	store.changed.connect(_local_changed)
	retry=Timer.new()
	retry.one_shot=true
	retry.wait_time=45.0
	add_child(retry)
	retry.timeout.connect(request_sync)
	backend=get_node("/root/SupabaseManager")
	backend.login_state_changed.connect(_identity_changed)
	_identity_changed("")

func current_key() -> String:
	var id: String=backend.current_user_id() if is_instance_valid(backend) else ""
	return "account:"+id.sha256_text() if not id.is_empty() else "local:profile"

func _identity_changed(_state: String) -> void:
	var next: String=backend.current_user_id()
	if account_id!=next:
		generation+=1
		account_id=next
		has_synced=false
		synced_bests.clear()
		retry.stop()
		account_changed.emit()
	if backend.is_authenticated(): request_sync()
	else: _status("Saved on this PC / sign in for cloud backup")

func _local_changed() -> void:
	if not merging: request_sync()

func request_sync() -> void:
	if not enabled or not is_instance_valid(backend) or not backend.is_authenticated(): return
	if scheduled or busy: return
	if has_synced and _payload(current_key())==synced_bests: return
	scheduled=true
	_sync.call_deferred()

func _payload(key: String) -> Dictionary:
	var result := {}
	var pattern := RegEx.new()
	pattern.compile("^flow_circuit_v3/dash[0-9]{1,2}/sprint[01]/jump[0-9]{1,3}\\.[0-9]{3}/(standard|powerup|assisted)$")
	var saved: Dictionary=store.saved_bests(key)
	for bucket in saved:
		if pattern.search(bucket)!=null: result[bucket]=saved[bucket]
	return result

func _sync() -> void:
	scheduled=false
	if busy or not enabled or not backend.is_authenticated(): return
	var expected_user: String=backend.current_user_id()
	var expected_generation := generation
	var key := current_key()
	var outgoing := _payload(key)
	busy=true
	_status("Backing up personal bests…")
	var response: Dictionary=await backend._authenticated_request("/rest/v1/rpc/sync_agility_personal_bests",HTTPClient.METHOD_POST,{"p_bests":outgoing},expected_user)
	busy=false
	if expected_generation!=generation or expected_user!=backend.current_user_id():
		request_sync()
		return
	var data: Variant=response.get("data",{})
	if not bool(response.get("ok",false)) or not data is Dictionary or not data.get("bests") is Dictionary:
		_status("Saved on this PC / cloud backup pending")
		retry.start()
		return
	merging=true
	store.merge_bests(key,data.bests)
	merging=false
	synced_bests=data.bests.duplicate(true)
	has_synced=true
	retry.stop()
	_status("Cloud backed up" if store.save_error==OK else "Cloud backed up / local save unavailable")
	# A faster run may have finished while the request was in flight.
	request_sync()

func _status(value: String) -> void:
	if status==value: return
	status=value
	status_changed.emit()
