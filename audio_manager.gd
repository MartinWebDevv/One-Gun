extends Node

# ============================================================
# AudioManager — Autoload singleton
#
# Single source of truth for all audio in One Gun.
# Add this to Project Settings → Autoload as "AudioManager".
#
# Usage from any .gd file:
#   AudioManager.play_hover()
#   AudioManager.play_click()
#   AudioManager.play_sfx("gun_pickup")
#   AudioManager.play_music("menu")
#   AudioManager.play_music("game")
#   AudioManager.stop_music()
#
# To add a new sound:
#   1. Drop the file into res://audio/
#   2. Add an entry to SFX_PATHS or MUSIC_PATHS below
#   3. Call AudioManager.play_sfx("your_key") anywhere
# ============================================================

# ============================================================
# Audio file paths — update these when adding new sounds
# ============================================================

const MUSIC_PATHS = {
	"menu": "res://audio/bloodpixelhero_your-last-game.wav",
	# "game": "res://audio/your_game_music.wav",
	# Drop your in-game music file into res://audio/ and uncomment
	# the line above with the correct filename to enable game music.
}

const SFX_PATHS = {
	"hover":      "res://audio/ui/button-hover.mp3",
	"click":      "res://audio/ui/button_click.wav",
	# "gun_pickup": "res://audio/sfx/gun_pickup.wav",
	# "gun_drop":   "res://audio/sfx/gun_drop.wav",
	# "disarm":     "res://audio/sfx/disarm.wav",
	# "round_start":"res://audio/sfx/round_start.wav",
	# "round_end":  "res://audio/sfx/round_end.wav",
	# "death":      "res://audio/sfx/death.wav",
}

# ============================================================
# Volume — adjust these or wire to sliders later
# ============================================================

var MUSIC_VOLUME_DB  = -10.0
var SFX_VOLUME_DB    = 0.0
var HOVER_VOLUME_DB  = -6.0

# ============================================================
# Internal nodes
# ============================================================

var _music_player  : AudioStreamPlayer
var _sfx_players   : Array[AudioStreamPlayer] = []
var _sfx_pool_size : int = 8   # concurrent sfx allowed
var _sfx_index     : int = 0

var _current_music_key : String = ""
var _music_tween       : Tween  = null

func _ready():
	_build_music_player()
	_build_sfx_pool()
	_apply_saved_volumes()

func _apply_saved_volumes():
	# Apply whatever the player last set in Player Settings.
	# PlayerPrefs stores linear 0.0-1.0 values.
	var master = PlayerPrefs.get_setting("master_volume")
	var music  = PlayerPrefs.get_setting("music_volume")
	var sfx    = PlayerPrefs.get_setting("sfx_volume")
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("Master"),
		linear_to_db(max(master, 0.0001))
	)
	set_music_volume(music)
	set_sfx_volume(sfx)

func _build_music_player():
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus  = "Master"
	_music_player.volume_db = MUSIC_VOLUME_DB
	add_child(_music_player)

func _build_sfx_pool():
	# Pool of AudioStreamPlayers for overlapping sound effects.
	for i in _sfx_pool_size:
		var p = AudioStreamPlayer.new()
		p.name = "SFX_%d" % i
		p.bus = "Master"
		p.volume_db = SFX_VOLUME_DB
		add_child(p)
		_sfx_players.append(p)

# ============================================================
# Music
# ============================================================

func play_music(key: String, fade_duration: float = 0.5):
	if key == _current_music_key and _music_player.playing:
		return
	if not MUSIC_PATHS.has(key):
		push_warning("AudioManager: no music key '%s'" % key)
		return

	var path = MUSIC_PATHS[key]
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: music file not found: %s" % path)
		return

	_current_music_key = key

	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()

	if _music_player.playing and fade_duration > 0.0:
		# Fade out current, then swap and fade in
		_music_tween = create_tween()
		_music_tween.tween_property(_music_player, "volume_db", -80.0, fade_duration)
		_music_tween.tween_callback(func():
			_music_player.stream = _load_looping(path)
			_music_player.play()
			var t2 = create_tween()
			t2.tween_property(_music_player, "volume_db", MUSIC_VOLUME_DB, fade_duration)
		)
	else:
		_music_player.stream = _load_looping(path)
		_music_player.volume_db = MUSIC_VOLUME_DB
		_music_player.play()

func stop_music(fade_duration: float = 0.5):
	if not _music_player.playing:
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_current_music_key = ""
	if fade_duration > 0.0:
		_music_tween = create_tween()
		_music_tween.tween_property(_music_player, "volume_db", -80.0, fade_duration)
		_music_tween.tween_callback(_music_player.stop)
	else:
		_music_player.stop()

func _load_looping(path: String) -> AudioStream:
	var stream = load(path)
	if stream == null:
		return null
	# Duplicate before modifying — resources are shared by reference
	# in Godot 4, so we must not mutate the original.
	stream = stream.duplicate()
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
	return stream

# ============================================================
# SFX
# ============================================================

func play_sfx(key: String):
	if not SFX_PATHS.has(key):
		push_warning("AudioManager: no sfx key '%s'" % key)
		return
	var path = SFX_PATHS[key]
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: sfx file not found: %s" % path)
		return
	var stream = load(path)
	if stream == null:
		return
	var player = _get_next_sfx_player()
	player.stream = stream
	player.volume_db = SFX_VOLUME_DB
	player.play()

func play_hover():
	if not SFX_PATHS.has("hover"):
		return
	var path = SFX_PATHS["hover"]
	if not ResourceLoader.exists(path):
		return
	var player = _get_next_sfx_player()
	player.stream = load(path)
	player.volume_db = HOVER_VOLUME_DB
	player.play()

func play_click():
	play_sfx("click")

func _get_next_sfx_player() -> AudioStreamPlayer:
	# Round-robin through pool — oldest sound gets cut if all busy.
	var player = _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_pool_size
	return player

# ============================================================
# Volume control — called by settings sliders later
# ============================================================

func set_music_volume(linear: float):
	# linear: 0.0 to 1.0
	MUSIC_VOLUME_DB = linear_to_db(max(linear, 0.0001))
	_music_player.volume_db = MUSIC_VOLUME_DB

func set_sfx_volume(linear: float):
	SFX_VOLUME_DB = linear_to_db(max(linear, 0.0001))
	for p in _sfx_players:
		p.volume_db = SFX_VOLUME_DB
