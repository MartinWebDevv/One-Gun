extends SceneTree

const Registry = preload("res://supabase/supabase_cosmetic_registry.gd")
const Catalog = preload("res://supabase/one_gun_catalog.gd")
const SkinRegistry = preload("res://player_skin_registry.gd")

const PODIUM_MOVES := {
	"podium_backbeat_bounce": "podium_backbeat_bounce",
	"podium_champion_canter": "podium_champion_canter",
	"podium_fresh_footwork": "podium_fresh_footwork",
	"podium_house_party_heat": "podium_house_party_heat",
	"podium_serpent_flow": "podium_serpent_flow",
	"podium_midnight_monster": "podium_midnight_monster",
	"podium_victory_wave": "podium_victory_wave",
}
const ROUND_MOVES := {
	"round_breakspin_finale": "round_breakspin_finale",
	"round_floorwork_finish": "round_floorwork_finish",
	"round_birdie_boogie": "round_birdie_boogie",
	"round_arena_clapline": "round_arena_clapline",
	"round_soul_cyclone": "round_soul_cyclone",
	"round_quickstep_shuffle": "round_quickstep_shuffle",
	"round_victory_swing": "round_victory_swing",
}

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_validate_registry_and_taxonomy()
	for model_id in SkinRegistry.MODEL_IDS:
		await _validate_model(str(model_id))
	if _failed:
		quit(1)
		return
	print("VICTORY_MOVE_INTEGRATION_OK dances=14 dual_slots=true models=2 lazy_loaded=true")
	quit(0)


func _validate_registry_and_taxonomy() -> void:
	_check(PODIUM_MOVES.size() == 7 and ROUND_MOVES.size() == 7,
		"the fourteen stable imported IDs must remain complete")
	var all_moves := PODIUM_MOVES.duplicate()
	all_moves.merge(ROUND_MOVES)
	_check(all_moves.size() == 14, "the unified dance library must contain 14 moves")
	for item_id in all_moves:
		var animation_name := str(all_moves[item_id])
		_check(Registry.local_victory_animation(item_id) == animation_name,
			"unified registry mismatch for %s" % item_id)
		_check(Registry.local_podium_animation(item_id) == animation_name
			and Registry.local_round_victory_animation(item_id) == animation_name,
			"dance is not available to both gameplay presentation paths: %s" % item_id)
		_check(Registry.has_local_visual(item_id, "emote")
			and Registry.has_local_visual(item_id, "round_victory_move")
			and Registry.has_local_visual(item_id, "victory_dance"),
			"dance is not locally viewable in both equip slots: %s" % item_id)
		_check(Registry.known_slot_for_id(item_id) == "victory_dance",
			"dance did not resolve to the shared catalog type: %s" % item_id)
		var item := Catalog.normalize_item({
			"id": item_id, "item_type": "victory_dance", "active": true,
			"shop_visible": true, "subcategory": "dances",
		})
		_check(Catalog.item_matches(item, "VICTORY", "DANCES"),
			"dance missed Victory > Dances: %s" % item_id)
		_check(not Catalog.item_matches(item, "VICTORY", "POSES"),
			"animated dance leaked into Victory > Poses: %s" % item_id)

func _validate_model(model_id: String) -> void:
	var scene := SkinRegistry.load_visual_scene(model_id)
	_check(scene != null, "missing visual scene for %s" % model_id)
	if scene == null:
		return
	var visual := scene.instantiate() as Node3D
	visual.set("model_id", model_id)
	visual.set("skin_id", "blue")
	visual.set("build_animation_library", false)
	root.add_child(visual)
	await process_frame
	var player := visual.call("ensure_animation_library") as AnimationPlayer
	_check(player != null, "animation player missing for %s" % model_id)
	if player == null:
		visual.queue_free()
		return
	for animation_name in PODIUM_MOVES.values():
		_check(not player.has_animation(str(animation_name)),
			"optional podium move loaded eagerly on %s: %s" % [model_id, animation_name])
	for animation_name in ROUND_MOVES.values():
		_check(not player.has_animation(str(animation_name)),
			"optional round move loaded eagerly on %s: %s" % [model_id, animation_name])
	for animation_name in PODIUM_MOVES.values():
		player = visual.call("ensure_animations", [animation_name]) as AnimationPlayer
		_validate_animation(player, str(animation_name), true, model_id)
	for animation_name in ROUND_MOVES.values():
		player = visual.call("ensure_animations", [animation_name]) as AnimationPlayer
		_validate_animation(player, str(animation_name), true, model_id)
	visual.queue_free()
	await process_frame


func _validate_animation(player: AnimationPlayer, animation_name: String,
		expect_loop: bool, model_id: String) -> void:
	_check(player != null and player.has_animation(animation_name),
		"%s could not load %s" % [model_id, animation_name])
	if player == null or not player.has_animation(animation_name):
		return
	var animation := player.get_animation(animation_name)
	_check(animation.length >= 4.0,
		"%s is unexpectedly short on %s" % [animation_name, model_id])
	_check((animation.loop_mode != Animation.LOOP_NONE) == expect_loop,
		"%s loop policy is wrong on %s" % [animation_name, model_id])
	player.play(animation_name)
	player.seek(animation.length * 0.45, true)
	player.advance(0.0)
	_check(player.current_animation == animation_name,
		"%s did not evaluate on %s" % [animation_name, model_id])


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("VICTORY_MOVE_INTEGRATION: %s" % message)
