extends Node

@export var countdown_time := 3
@export var round_end_display_time := 3
@export var set_end_display_time := 4
@export var match_end_display_time := 6

const MAX_TOTAL_PLAYERS := 8
const MAX_BOTS_SOLO := 7
const MAX_BOTS_SPLIT := 6

const DummyScene = preload("res://DummyModel.tscn")

var players = []
var spawn_transforms = {}
var round_state = "countdown"
var round_number = 1
var set_number = 1

var round_wins = {}
var match_points = {}
var previous_alive = []

# -- Match stats (accumulate across all rounds, reset when match ends) --
var stat_kills    := {}
var stat_deaths   := {}
var stat_disarms  := {}
var stat_pickups  := {}
var stat_melee    := {}

func _leave_match_to(scene_path: String):
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManager.stop_music(0.5)
	get_tree().change_scene_to_file(scene_path)

func _ready():
	_spawn_bots()
	players = get_tree().get_nodes_in_group("player")
	if not GameConfig.split_screen_enabled:
		players = players.filter(func(p): return not ("is_player2" in p and p.is_player2))
	for p in players:
		round_wins[p] = 0
		match_points[p] = 0
		stat_kills[p]   = 0
		stat_deaths[p]  = 0
		stat_disarms[p] = 0
		stat_pickups[p] = 0
		stat_melee[p]   = 0
	_disable_all_players()
	await get_tree().process_frame
	_disable_all_players()
	_assign_spawn_transforms()
	_apply_gun_spawn_mode()
	GameEvents.player_eliminated.connect(_on_stat_eliminated)
	GameEvents.player_disarmed.connect(_on_stat_disarmed)
	GameEvents.gun_picked_up.connect(_on_stat_gun_picked_up)
	GameEvents.melee_hit_landed.connect(_on_stat_melee_hit)
	await get_tree().process_frame
	AudioManager.play_music("game")
	_start_countdown()

func _find_player_by_name(display_name: String):
	for p in players:
		if p.get_display_name() == display_name:
			return p
	return null

func _on_stat_eliminated(victim_name: String, killer_name: String, _icon: String):
	var victim = _find_player_by_name(victim_name)
	if victim != null and stat_deaths.has(victim):
		stat_deaths[victim] += 1
	if killer_name != "":
		var killer = _find_player_by_name(killer_name)
		if killer != null and stat_kills.has(killer):
			stat_kills[killer] += 1

func _on_stat_disarmed(victim_name: String, disarmer_name: String, _icon: String):
	var disarmer = _find_player_by_name(disarmer_name)
	if disarmer != null and stat_disarms.has(disarmer):
		stat_disarms[disarmer] += 1

func _on_stat_gun_picked_up(player_name: String):
	var p = _find_player_by_name(player_name)
	if p != null and stat_pickups.has(p):
		stat_pickups[p] += 1

func _on_stat_melee_hit(hitter_name: String):
	var p = _find_player_by_name(hitter_name)
	if p != null and stat_melee.has(p):
		stat_melee[p] += 1

func get_scoreboard_data() -> Array:
	var data = []
	for p in players:
		data.append({
			"name":    p.get_display_name(),
			"sets":    match_points.get(p, 0),
			"rounds":  round_wins.get(p, 0),
			"kills":   stat_kills.get(p, 0),
			"deaths":  stat_deaths.get(p, 0),
			"disarms": stat_disarms.get(p, 0),
			"pickups": stat_pickups.get(p, 0),
			"melee":   stat_melee.get(p, 0),
			"alive":   not p.is_eliminated,
		})
	data.sort_custom(func(a, b):
		if a["sets"] != b["sets"]:
			return a["sets"] > b["sets"]
		return a["rounds"] > b["rounds"]
	)
	return data

func _assign_spawn_transforms():
	var all_spawns = get_tree().get_nodes_in_group("spawn_point")
	if all_spawns.size() == 0:
		push_warning("RoundManager: no spawn_point markers found — all players spawn at their scene positions.")
		for p in players:
			spawn_transforms[p] = p.global_transform
		return

	var shuffled = all_spawns.duplicate()
	shuffled.shuffle()
	var used_indices = []

	var human_players = players.filter(func(p): return not ("is_bot" in p and p.is_bot))
	for i in human_players.size():
		var idx = i % shuffled.size()
		spawn_transforms[human_players[i]] = shuffled[idx].global_transform
		used_indices.append(idx)
		human_players[i].global_transform = shuffled[idx].global_transform

	var bot_players = players.filter(func(p): return "is_bot" in p and p.is_bot)
	var next_idx = human_players.size()
	for bot in bot_players:
		var idx = next_idx % shuffled.size()
		spawn_transforms[bot] = shuffled[idx].global_transform
		bot.global_transform = shuffled[idx].global_transform
		next_idx += 1

func _spawn_bots():
	var human_count = 2 if GameConfig.split_screen_enabled else 1
	var max_bots = MAX_BOTS_SPLIT if GameConfig.split_screen_enabled else MAX_BOTS_SOLO
	var bot_count = clamp(GameConfig.bot_configs.size(), 0, min(max_bots, MAX_TOTAL_PLAYERS - human_count))

	if bot_count == 0:
		return

	for i in range(bot_count):
		var bot = DummyScene.instantiate()
		bot.name = "Bot" + str(i + 1)
		var config = GameConfig.bot_configs[i]
		bot.ai_difficulty = config.get("difficulty", "easy")
		bot.team_id = config.get("team_id", -1)
		add_child(bot)

func _disable_all_players():
	for p in players:
		if is_instance_valid(p):
			p.set_physics_process(false)

func _enable_all_players():
	for p in players:
		if is_instance_valid(p) and not p.is_eliminated:
			p.set_physics_process(true)

func _set_round_label_text(text):
	get_node("../CanvasLayer/RoundLabel").text = text
	get_node("../CanvasLayer/RoundLabel2").text = text

func _start_countdown():
	round_state = "countdown"
	for m in get_tree().get_nodes_in_group("melee"):
		if m.has_method("randomize_attributes"):
			m.randomize_attributes()
	_apply_melee_spawn_delay()
	previous_alive = players.duplicate()
	_update_status_label()
	GameEvents.hud_notification.emit("NEW ROUND STARTING")
	for i in range(countdown_time, 0, -1):
		_set_round_label_text(str(i))
		await get_tree().create_timer(1.0).timeout
	_set_round_label_text("GO!")
	round_state = "live"
	_enable_all_players()
	await get_tree().create_timer(0.5).timeout
	_set_round_label_text("")

func _apply_melee_spawn_delay():
	var melee_weapons = get_tree().get_nodes_in_group("melee")
	if GameConfig.melee_spawn_delay <= 0.0:
		for m in melee_weapons:
			m.pickup_locked = false
		return
	for m in melee_weapons:
		m.pickup_locked = true
	await get_tree().create_timer(GameConfig.melee_spawn_delay).timeout
	for m in melee_weapons:
		if is_instance_valid(m):
			m.pickup_locked = false

func _process(_delta):
	if round_state == "live":
		_check_round_end()
		_update_status_label()

func _update_status_label():
	var alive_count = 0
	for p in players:
		if not p.is_eliminated:
			alive_count += 1

	var hud = get_node_or_null("../CanvasLayer/MatchHUD")
	if hud != null and hud.has_method("update_match_state"):
		hud.update_match_state(round_number, set_number, alive_count, players.size())

	var hud2 = get_node_or_null("../CanvasLayer/MatchHUD2")
	if hud2 != null and hud2.has_method("update_match_state"):
		hud2.update_match_state(round_number, set_number, alive_count, players.size())

func _check_round_end():
	var alive = []
	for p in players:
		if not p.is_eliminated:
			alive.append(p)

	var alive_count = alive.size()
	var prev_count = previous_alive.size()
	if alive_count != prev_count:
		# Don't emit these via hud_notification — the remaining label
		# already repositions to center and displays the dramatic text.
		# Emitting here would cause them to appear twice in the same spot.
		pass

	if not GameConfig.teams_enabled:
		if alive.size() == 0 and previous_alive.size() >= 2:
			_end_round(previous_alive, true)
			previous_alive = alive
			return
		if alive.size() <= 1:
			_end_round(alive)
		previous_alive = alive
		return

	var alive_teams = {}
	for p in alive:
		var t = p.team_id if "team_id" in p else -1
		if not alive_teams.has(t):
			alive_teams[t] = []
		alive_teams[t].append(p)

	if alive.size() == 0 and previous_alive.size() >= 2:
		var prev_teams = {}
		for p in previous_alive:
			var t = p.team_id if "team_id" in p else -1
			prev_teams[t] = true
		if prev_teams.size() >= 2:
			_end_round(previous_alive, true)
			previous_alive = alive
			return

	if alive_teams.size() <= 1:
		_end_round(alive)
	previous_alive = alive

func _end_round(alive, multi_winner_draw := false):
	round_state = "ended"
	_disable_all_players()

	if GameConfig.teams_enabled and alive.size() > 0:
		if multi_winner_draw:
			await _resolve_team_multi_winner(alive)
			return
		var winning_team_id = alive[0].team_id if "team_id" in alive[0] else -1
		for p in alive:
			round_wins[p] += 1
		_set_round_label_text("Team " + str(winning_team_id + 1) + " wins the round!")
		await get_tree().create_timer(round_end_display_time).timeout

		var team_round_wins = round_wins[alive[0]]
		if team_round_wins >= GameConfig.rounds_per_set:
			for p in alive:
				match_points[p] += 1
			for p in players:
				round_wins[p] = 0

			if match_points[alive[0]] >= GameConfig.sets_per_match:
				_set_round_label_text("Team " + str(winning_team_id + 1) + " WINS THE MATCH!")
				await get_tree().create_timer(match_end_display_time).timeout
				_leave_match_to("res://game_setup.tscn")
				return
			else:
				_set_round_label_text("Team " + str(winning_team_id + 1) + " wins the set!")
				await get_tree().create_timer(set_end_display_time).timeout
				set_number += 1
				round_number = 0
		_reset_round()
		return

	if multi_winner_draw and alive.size() >= 2:
		await _resolve_multi_winner(alive)
		return

	if alive.size() == 1:
		var winner = alive[0]
		round_wins[winner] += 1
		# Trigger victory dance on the winner immediately.
		if winner.has_method("play_victory_dance"):
			winner.play_victory_dance()
		_set_round_label_text(winner.get_display_name() + " wins the round!")
		await get_tree().create_timer(round_end_display_time).timeout

		if round_wins[winner] >= GameConfig.rounds_per_set:
			match_points[winner] += 1
			for p in players:
				round_wins[p] = 0

			if match_points[winner] >= GameConfig.sets_per_match:
				_set_round_label_text(winner.get_display_name() + " WINS THE MATCH!")
				await get_tree().create_timer(match_end_display_time).timeout
				_leave_match_to("res://game_setup.tscn")
				return
			else:
				_set_round_label_text(winner.get_display_name() + " wins the set!")
				await get_tree().create_timer(set_end_display_time).timeout
				set_number += 1
				round_number = 0
	else:
		_set_round_label_text("Draw!")
		await get_tree().create_timer(round_end_display_time).timeout

	_reset_round()

func _resolve_multi_winner(tied_players):
	var names = []
	for p in tied_players:
		round_wins[p] += 1
		names.append(p.get_display_name())
	_set_round_label_text(" & ".join(names) + " tie the round!")
	await get_tree().create_timer(round_end_display_time).timeout

	var match_winners = []
	for p in tied_players:
		if round_wins[p] >= GameConfig.rounds_per_set:
			match_points[p] += 1
			match_winners.append(p)

	if match_winners.size() > 0:
		for p in players:
			round_wins[p] = 0

		var set_winners = []
		for p in players:
			if match_points[p] >= GameConfig.sets_per_match:
				set_winners.append(p)

		if set_winners.size() > 0:
			var winner_names = []
			for p in set_winners:
				winner_names.append(p.get_display_name())
			_set_round_label_text(" & ".join(winner_names) + " TIE FOR THE MATCH!")
			await get_tree().create_timer(match_end_display_time).timeout
			_leave_match_to("res://game_setup.tscn")
			return
		else:
			var winner_names = []
			for p in match_winners:
				winner_names.append(p.get_display_name())
			_set_round_label_text(" & ".join(winner_names) + " tie for the set!")
			await get_tree().create_timer(set_end_display_time).timeout
			set_number += 1
			round_number = 0

	_reset_round()

func _resolve_team_multi_winner(tied_players):
	var tied_team_ids = []
	for p in tied_players:
		var t = p.team_id if "team_id" in p else -1
		if t not in tied_team_ids:
			tied_team_ids.append(t)

	for p in tied_players:
		round_wins[p] += 1

	var team_labels = []
	for t in tied_team_ids:
		team_labels.append("Team " + str(t + 1))
	_set_round_label_text(" & ".join(team_labels) + " tie the round!")
	await get_tree().create_timer(round_end_display_time).timeout

	var match_winner_teams = []
	for t in tied_team_ids:
		var rep = null
		for p in tied_players:
			if ("team_id" in p and p.team_id == t):
				rep = p
				break
		if rep != null and round_wins[rep] >= GameConfig.rounds_per_set:
			match_winner_teams.append(t)

	if match_winner_teams.size() > 0:
		for p in players:
			if ("team_id" in p and p.team_id in match_winner_teams):
				match_points[p] += 1
		for p in players:
			round_wins[p] = 0

		var set_winner_teams = []
		for t in match_winner_teams:
			var rep = null
			for p in players:
				if ("team_id" in p and p.team_id == t):
					rep = p
					break
			if rep != null and match_points[rep] >= GameConfig.sets_per_match:
				set_winner_teams.append(t)

		if set_winner_teams.size() > 0:
			var labels = []
			for t in set_winner_teams:
				labels.append("Team " + str(t + 1))
			_set_round_label_text(" & ".join(labels) + " TIE FOR THE MATCH!")
			await get_tree().create_timer(match_end_display_time).timeout
			_leave_match_to("res://game_setup.tscn")
			return
		else:
			var labels = []
			for t in match_winner_teams:
				labels.append("Team " + str(t + 1))
			_set_round_label_text(" & ".join(labels) + " tie for the set!")
			await get_tree().create_timer(set_end_display_time).timeout
			set_number += 1
			round_number = 0

	_reset_round()

func _reset_round():
	round_number += 1
	_assign_spawn_transforms()
	for p in players:
		p.respawn(spawn_transforms[p])
	for w in get_tree().get_nodes_in_group("weapon"):
		w.reset_to_spawn()
	_apply_gun_spawn_mode()
	for it in get_tree().get_nodes_in_group("item"):
		it.reset_to_spawn()
	for pu in get_tree().get_nodes_in_group("powerup"):
		if pu.has_method("reset_to_spawn"):
			pu.reset_to_spawn()
	for trap in get_tree().get_nodes_in_group("deployed_trap"):
		trap.queue_free()
	_start_countdown()

func _apply_gun_spawn_mode():
	if GameConfig.gun_spawn_mode != "random":
		return
	var spawn_points = get_tree().get_nodes_in_group("gun_spawn_point")
	if spawn_points.size() == 0:
		return
	var guns = get_tree().get_nodes_in_group("gun")
	if guns.size() == 0:
		return
	var chosen = spawn_points[randi() % spawn_points.size()]
	guns[0].global_position = chosen.global_position
	guns[0].spawn_position = chosen.global_position
