extends Node

const MatchLimitsData = preload("res://match_limits.gd")
const MatchServerContext = preload("res://match_server_context.gd")

const CLIENT_MAIN_SCENE := "res://main_menu.tscn"
const DEFAULT_SERVER_MAP := "res://maps/test/ForestMap.tscn"


func _ready() -> void:
	call_deferred("_route_startup")


func _route_startup() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not arguments.has("--server"):
		get_tree().change_scene_to_file(CLIENT_MAIN_SCENE)
		return

	if NetworkManager.is_dedicated_server() and NetworkManager.is_online():
		print("[DEDICATED] Lobby runtime restored; ENet remains active on UDP %d." \
			% NetworkManager.listening_port())
		return

	var port := _int_argument(arguments, "--port=", NetworkManager.DEFAULT_PORT)
	var max_players := _int_argument(arguments, "--max-players=", NetworkManager.MAX_PEERS)
	var lobby_name := _string_argument(arguments, "--lobby-name=", "OneGun-Dev")
	var map_path := _string_argument(arguments, "--map=", DEFAULT_SERVER_MAP)
	var match_context := MatchServerContext.from_environment()
	if port < 1 or port > 65535:
		push_error("Dedicated server port must be between 1 and 65535 (received %d)." % port)
		get_tree().quit(2)
		return
	if max_players < MatchLimitsData.MIN_ONLINE_HUMANS or max_players > NetworkManager.MAX_PEERS:
		push_error("Dedicated server max players must be between %d and %d (received %d)." % [
			MatchLimitsData.MIN_ONLINE_HUMANS, NetworkManager.MAX_PEERS, max_players])
		get_tree().quit(2)
		return
	if not ResourceLoader.exists(map_path):
		push_error("Dedicated server map does not exist: %s" % map_path)
		get_tree().quit(2)
		return
	if bool(match_context.get("active", false)) and not bool(match_context.get("valid", false)):
		for context_error in match_context.get("errors", []):
			push_error("[MATCH SERVER] %s" % str(context_error))
		get_tree().quit(4)
		return
	GameConfig.reset_match_settings_to_defaults()
	GameConfig.split_screen_enabled = false
	if bool(match_context.get("active", false)):
		# The first sandbox profile assigns human tickets only. Match-specific bot
		# and rule attributes will be applied by the coordinator in a later slice.
		GameConfig.bot_configs = []
	if not NetworkManager.host_dedicated_game(
			port, lobby_name, max_players, map_path, match_context):
		push_error("Dedicated server failed to start on UDP %d." % port)
		get_tree().quit(3)
		return
	if bool(match_context.get("active", false)):
		NetworkManager.start_game(map_path)


func _int_argument(arguments: PackedStringArray, prefix: String, fallback: int) -> int:
	for argument in arguments:
		if argument.begins_with(prefix):
			return int(argument.trim_prefix(prefix))
	return fallback


func _string_argument(arguments: PackedStringArray, prefix: String, fallback: String) -> String:
	for argument in arguments:
		if argument.begins_with(prefix):
			var value := argument.trim_prefix(prefix).strip_edges()
			return value if value != "" else fallback
	return fallback
