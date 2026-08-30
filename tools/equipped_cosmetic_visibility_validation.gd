extends SceneTree

# Real local gameplay actor coverage for persistent appearance. The fixture
# mutates only in-memory autoload state and restores it before exit.

const TEST_HAT_A := "hat_cowboy_classic"
const TEST_HAT_B := "hat_top"
const GOLDFISH_MODEL := "goldfish_bag_man"
const GOLDFISH_ITEM := "character_goldfish_bag_man"

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var backend = root.get_node("SupabaseManager")
	var prefs = root.get_node("PlayerPrefs")
	var saved_loadout: Dictionary = backend.loadout.duplicate(true)
	var saved_model := str(prefs.settings.get("character_model_id", "male"))
	var saved_skin := str(prefs.settings.get("character_skin_id", "blue"))
	prefs.settings["character_model_id"] = GOLDFISH_MODEL
	prefs.settings["character_skin_id"] = "blue"
	backend.loadout = SupabaseCosmeticRegistry.sanitize_loadout({
		"character_model": GOLDFISH_ITEM,
		"hat": TEST_HAT_A,
		"character_skin": "purple",
	})

	var packed := load("res://player.tscn") as PackedScene
	_check(packed != null, "player.tscn could not load")
	var player := packed.instantiate() as CharacterBody3D if packed != null else null
	if player != null:
		root.add_child(player)
		await _wait_frames(6)
		_check(_actor_has_appearance(player, GOLDFISH_MODEL, "purple", TEST_HAT_A),
			"local gameplay actor did not start with the gifted Gold Fish appearance")
		backend.loadout = SupabaseCosmeticRegistry.sanitize_loadout({
			"character_model": GOLDFISH_ITEM,
			"hat": TEST_HAT_B,
			"character_skin": "purple",
		})
		backend.loadout_updated.emit(backend.loadout.duplicate(true))
		await _wait_frames(4)
		_check(_actor_has_appearance(player, GOLDFISH_MODEL, "purple", TEST_HAT_B),
			"local gameplay actor did not refresh its equipped Hat")
		player.queue_free()
		await _wait_frames(2)
	else:
		_check(false, "player.tscn did not instantiate a CharacterBody3D")

	backend.loadout = saved_loadout
	prefs.settings["character_model_id"] = saved_model
	prefs.settings["character_skin_id"] = saved_skin
	if _failed:
		quit(1)
	else:
		print("EQUIPPED_COSMETIC_VISIBILITY_VALIDATION: PASS gameplay=1 gift-model=1 hat=1 animation=1 live-refresh=1")
		quit(0)


func _actor_has_appearance(player: Node, model_id: String,
		skin_id: String, hat_id: String) -> bool:
	var visual := player.get_node_or_null("CharacterModel") as Node3D
	if visual == null or str(visual.get("model_id")) != model_id \
			or str(visual.get("skin_id")) != skin_id:
		return false
	var socket := visual.call("get_headwear_socket") as Marker3D
	var hat := socket.find_child("HatVisual", false, false) as Node3D \
		if socket != null else null
	var animation_player := visual.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer
	return hat != null and str(hat.get_meta("supabase_hat_id", "")) == hat_id \
		and animation_player != null and animation_player.is_playing()


func _wait_frames(count: int) -> void:
	for _index in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("EQUIPPED COSMETIC VISIBILITY FAILED: %s" % message)
