extends SceneTree

var _failures := 0

const CEREMONY_THEME_PATHS: Array[String] = [
	"res://audio/ui/winners_circle_ceremony.wav",
	"res://audio/ui/winners_circle_themes/neon_victory.wav",
	"res://audio/ui/winners_circle_themes/western_toybox.wav",
	"res://audio/ui/winners_circle_themes/grand_arena.wav",
	"res://audio/ui/winners_circle_themes/pixel_champion.wav",
	"res://audio/ui/winners_circle_themes/champion_groove.wav",
	"res://audio/ui/winners_circle_themes/deep_orbit.wav",
]


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)


func _run() -> void:
	await process_frame
	var result_builder = load("res://winners_circle_match_result.gd")
	var winners_circle_script = load("res://UI/winners_circle.gd")
	var reward_preview = load("res://match_reward_preview.gd")
	var stage_scene = load("res://UI/winners_circle_stage_blockout.tscn") as PackedScene
	_check(result_builder != null and winners_circle_script != null
			and reward_preview != null and stage_scene != null,
		"Winners Circle presentation resources load")
	for theme_path in CEREMONY_THEME_PATHS:
		_check(load(theme_path) is AudioStream,
			"ceremony theme loads: %s" % theme_path.get_file())
	var stage := stage_scene.instantiate() as Node3D
	root.add_child(stage)
	for required_path in [
		"StageShell",
		"Podiums",
		"Decor",
		"Anchors/FirstPlace",
		"Anchors/SecondPlace",
		"Anchors/ThirdPlace",
		"Anchors/TrophyStart",
		"Anchors/TrophyLanding",
		"Anchors/CeremonialGun",
	]:
		_check(stage.get_node_or_null(required_path) != null,
			"blockout stage preserves replacement anchor %s" % required_path)
	stage.queue_free()
	await process_frame
	_check(load("res://round_manager.gd") != null,
		"RoundManager parses with Winners Circle integration")
	_check(load("res://winners_circle_coordinator.gd") != null,
		"Winners Circle coordinator parses")
	var game_config := root.get_node_or_null("/root/GameConfig")
	_check(game_config != null, "GameConfig autoload is available to the validator")
	game_config.call("reset_match_settings_to_defaults")
	_check(bool(game_config.call("is_official_beta_ruleset", 3, 0)),
		"three-human bot-free default Classic FFA qualifies as an Official Beta candidate")
	_check(not bool(game_config.call("is_official_beta_ruleset", 2, 0))
			and not bool(game_config.call("is_official_beta_ruleset", 3, 1)),
		"Official Beta candidates require at least three humans and no bots")
	game_config.set("round_time_limit", 179.0)
	_check(not bool(game_config.call("is_official_beta_ruleset", 3, 0)),
		"changing an official rule makes the match custom")

	var state := {
		1: _sample_state(1, "Champion", 3, 4, 2, "red", "male"),
		2: _sample_state(2, "Runner Up", 1, 5, 3, "blue", "female"),
		3: _sample_state(3, "Third Place", 1, 2, 5, "green", "male"),
		4: _sample_state(4, "Fourth", 0, 8, 1, "purple", "female"),
	}
	state[2]["runner_up_finishes"] = 2
	state[3]["runner_up_finishes"] = 1
	state[3]["third_place_finishes"] = 2
	var result: Dictionary = result_builder.build_online(
		state, 1, true, "validation-match", "res://maps/test/ForestMap.tscn")
	var entries: Array = result["entries"]
	_check(entries.size() == 4, "all match participants enter the frozen result")
	_check(int(entries[0]["actor_id"]) == 1 and int(entries[0]["placement"]) == 1,
		"the match champion is always first")
	_check(int(entries[1]["actor_id"]) == 2,
		"round finishes outrank kills for runner-up placement")
	_check(bool(result["trophy_awarded"]),
		"an Official Classic result marks the champion Trophy presentation")
	var peer_one_result := result.duplicate(true)
	peer_one_result["local_peer_id"] = 1
	var peer_two_result := result.duplicate(true)
	peer_two_result["local_peer_id"] = 2
	var peer_one_confirmation: Dictionary = result_builder.confirmation_payload(peer_one_result)
	var peer_two_confirmation: Dictionary = result_builder.confirmation_payload(peer_two_result)
	_check(peer_one_confirmation == peer_two_confirmation
			and not peer_one_confirmation.has("local_peer_id"),
		"per-client presentation identity cannot change the shared reward result")

	var champion_reward: Dictionary = reward_preview.for_actor(result, 1)
	_check(int(champion_reward["trophy_delta"]) == 1
			and int(champion_reward["xp_delta"]) == 85
			and int(champion_reward["gun_tokens_delta"]) == 250
			and not bool(champion_reward["persisted"]),
		"the reward boundary mirrors the locked official formula before settlement")
	var custom_result := result.duplicate(true)
	custom_result["official"] = false
	_check(int(reward_preview.for_actor(custom_result, 1)["trophy_delta"]) == 0,
		"custom results never preview a Trophy")

	result["local_peer_id"] = 1
	var circle = winners_circle_script.new()
	var forfeit_result: Dictionary = result_builder.build_online(
		{1: state[1]}, 1, true, "forfeit-validation",
		"res://maps/test/ForestMap.tscn", 3,
		{2: state[2], 3: state[3]}, 1)
	var forfeit_entries: Array = forfeit_result["entries"]
	_check(int(forfeit_result.get("started_humans", 0)) == 3
		and int(forfeit_result.get("finisher_humans", 0)) == 1
		and bool(forfeit_result.get("forfeit_win", false)),
		"a match that started Official preserves its one-finisher forfeit state")
	_check(forfeit_entries.size() == 3
		and bool((forfeit_entries[0] as Dictionary).get("finished_match", false))
		and not bool((forfeit_entries[1] as Dictionary).get("finished_match", true))
		and not bool((forfeit_entries[2] as Dictionary).get("finished_match", true)),
		"the sole finisher stays first while departed players remain visible as DNF")

	root.add_child(circle)
	circle.present(result, [1], true, true)
	await process_frame
	await process_frame
	_check(circle.find_child("WinnersCircleRoot", true, false) != null,
		"the full-screen Winners Circle interface builds")
	_check(circle.find_child("PodiumStage", true, false) != null,
		"the isolated 3D podium stage builds")
	_check(str(circle.call("_ceremony_audio_key")) == "winners_circle_deep_orbit",
		"the champion's equipped ceremony theme selects the shared audio cue")
	var cinematic_stage := circle.find_child("CinematicStage", true, false) as Control
	_check(cinematic_stage != null and cinematic_stage.visible,
		"the ceremony begins on the full-screen cinematic stage")
	var results_interface := circle.find_child(
		"ResultsInterface", true, false) as Control
	_check(results_interface != null and results_interface.modulate.a <= 0.01,
		"standings, personal results and controls stay hidden during the cinematic")
	var results_twinkles := circle.find_child(
		"ResultsTwinkleBackdrop", true, false) as Control
	_check(results_twinkles != null,
		"the result interface builds its soft twinkling backdrop")
	var cinematic_camera := circle.find_child(
		"WinnersCircleCamera", true, false) as Camera3D
	_check(cinematic_camera != null
			and cinematic_camera.position.x >= 5.20
			and cinematic_camera.position.x <= 5.80
			and cinematic_camera.position.z >= 5.05
			and cinematic_camera.position.z <= 8.20,
		"the camera begins on the third-place reveal track")
	var active_performers := 0
	var visible_bind_poses := 0
	for performer_value in circle.find_children(
			"VictoryPerformer", "Node3D", true, false):
		var performer := performer_value as Node3D
		if not performer.visible:
			continue
		var animation_player := performer.find_child(
			"AnimationPlayer", true, false) as AnimationPlayer
		if animation_player == null or animation_player.current_animation == "":
			visible_bind_poses += 1
		else:
			active_performers += 1
	_check(active_performers == 3 and visible_bind_poses == 0,
		"all three visible performers start in an active Victory Move or idle")
	_check(circle.find_child("FinalStandingsCabinet", true, false) != null,
		"the shared standings panel builds")
	_check(circle.find_child("ReadyButton", true, false) != null,
		"an online participant receives a Ready button")
	_check(circle.find_child("HostReturnButton", true, false) != null,
		"the host receives the synchronized return control")
	var return_status := circle.find_child("ReturnStatusLabel", true, false) as Label
	_check(return_status != null and "AUTO" not in return_status.text,
		"results wait for Ready or the host without an automatic return timer")

	circle.set_ready_peers([1, 3], [1, 2, 3])
	var personal_results: Node = circle.find_child("PersonalResults", true, false)
	_check(personal_results != null, "the local player receives a personalized result card")
	_check(circle.find_child("PersonalPlacementBadge", true, false) != null,
		"the personalized card emphasizes the local placement")
	_check(circle.find_child("PersonalPerformance", true, false) != null,
		"the personalized card groups the local performance stats")
	_check(circle.find_child("PersonalRewards", true, false) != null,
		"the personalized card separates match rewards from performance")
	var local_standing: Node = circle.find_child("StandingRow_1", true, false)
	_check(local_standing != null and bool(local_standing.get_meta("viewer_row", false)),
		"the final standings identify the viewing player's row")

	var original_time_scale := Engine.time_scale
	Engine.time_scale = 20.0
	await create_timer(10.40, true).timeout
	Engine.time_scale = original_time_scale
	await process_frame
	_check(circle.find_child("CinematicStage", true, false) == null
			and results_interface.modulate.a >= 0.99,
		"the full cinematic finishes by revealing the results interface")
	_check(cinematic_camera.position.distance_to(
		Vector3(0.0, 4.15, 12.20)) < 0.05
			and cinematic_camera.fov >= 47.9,
		"the champion hero angle preserves outer-medallion headroom")
	var trophy := circle.find_child("VictoryTrophy", true, false) as Node3D
	_check(trophy != null and trophy.visible
			and absf(trophy.position.y - float(
				trophy.get_meta("landing_y", trophy.position.y))) < 0.05,
		"the Official Classic Trophy finishes on its landing plinth")
	var confetti := circle.find_child("WinnerConfetti", true, false) as GPUParticles3D
	_check(confetti != null and bool(
		confetti.get_meta("ceremony_fired", false)),
		"the champion hero beat fires quality-scaled confetti")
	circle.queue_free()
	await process_frame

	if _failures == 0:
		print("WINNERS CIRCLE VALIDATION PASSED")
		quit(0)
	else:
		push_error("WINNERS CIRCLE VALIDATION FAILED: %d issue(s)" % _failures)
		quit(1)


func _sample_state(actor_id: int, player_name: String, round_wins: int,
		kills: int, disarms: int, skin_id: String, model_id: String) -> Dictionary:
	return {
		"actor_id": actor_id,
		"owner_peer_id": actor_id,
		"name": player_name,
		"skin_id": skin_id,
		"model_id": model_id,
		"cosmetics": {
			"character_skin": "", "hat": "", "accessory": "",
			"gun_skin": "", "melee_skin": "", "emote": "hip_hop_dance",
			"ceremony_theme": "wc_theme_deep_orbit" if actor_id == 1 else "",
		},
		"sets": 1 if actor_id == 1 else 0,
		"total_round_wins": round_wins,
		"runner_up_finishes": 0,
		"third_place_finishes": 0,
		"kills": kills,
		"deaths": 2,
		"disarms": disarms,
		"pickups": 2,
		"melee": 3,
		"rounds_participated": 3,
		"active_samples": 12,
		"activity_eligible": true,
	}
