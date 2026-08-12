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
	"menu": "res://audio/MainMenu.wav",
	"forest": "res://audio/ForestSounds/ForestLevelMusic-Loop.wav",
	# "game": "res://audio/your_game_music.wav",
	# Drop your in-game music file into res://audio/ and uncomment
	# the line above with the correct filename to enable game music.
}

# Looping background ambience (follows the SFX volume slider, offset quieter)
const AMBIENT_PATHS = {
	"forest_birds": "res://audio/ForestSounds/ForestBackground-birdChirps.wav",
}

# Maps set this on enter (and clear it on exit) to give themselves their own
# in-match music: round_manager's generic play_music("game") gets redirected.
var level_music_key: String = ""

const SFX_PATHS = {
	"hover":      "res://audio/ui/button-hover.mp3",
	"click":      "res://audio/ui/button_click.wav",
	"gun_shot":   "res://audio/weapon_sounds/Gun_Shot.wav",
	"melee_swing": "res://audio/weapon_sounds/Swing_Sound.wav",
	"hit_sword":  "res://audio/weapon_sounds/Sword_Clash.wav",
	"hit_stick":  "res://audio/weapon_sounds/Stick_Hitting.wav",
	"hit_crowbar": "res://audio/weapon_sounds/Crow_Bar_Hit.wav",
	"hit_bat":    "res://audio/weapon_sounds/BaseballBat_hit.mp3",
	"hit_pan":    "res://audio/weapon_sounds/Frying_Pan.mp3",
	"footstep":   "res://audio/GlobalSounds/footsteps.wav",
	"double_jump_boing": "res://audio/itemSounds/Cartoon_Boing.mp3",
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

# Authored base levels (what the sliders' 100% means). User slider values are
# added on top as dB offsets so the authored mix is preserved at full volume.
const MUSIC_BASE_DB   := -5.0
const HOVER_OFFSET_DB := -6.0   # hover sits this much under the SFX level

var MUSIC_VOLUME_DB  = MUSIC_BASE_DB  # current effective music level (base + user)
var SFX_VOLUME_DB    = 0.0            # current effective sfx level (user)
var AMBIENT_OFFSET_DB = -10.0  # ambience sits this much under the SFX level

# Squared perceptual curve: raw linear_to_db leaves most of the slider's travel
# nearly inaudible (0.5 → only -6 dB); squaring makes mid-slider clearly quieter.
func _user_db(linear: float) -> float:
	linear = clampf(linear, 0.0, 1.0)
	return linear_to_db(maxf(linear * linear, 0.0001))

# ============================================================
# Internal nodes
# ============================================================

var _music_player  : AudioStreamPlayer
var _ambient_player: AudioStreamPlayer
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
	set_master_volume(master)
	set_music_volume(music)
	set_sfx_volume(sfx)

func _build_music_player():
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus  = "Master"
	_music_player.volume_db = MUSIC_VOLUME_DB
	add_child(_music_player)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.name = "AmbientPlayer"
	_ambient_player.bus = "Master"
	_ambient_player.volume_db = SFX_VOLUME_DB + AMBIENT_OFFSET_DB
	add_child(_ambient_player)

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
	# A map can claim its own in-match track: the generic "game" request that
	# round_manager makes for every match gets redirected to it.
	if key == "game" and level_music_key != "":
		key = level_music_key
	elif key == "game":
		# Most maps intentionally have no authored match track. Silence is a valid
		# fallback, not a missing-resource warning on every local match start.
		stop_music(fade_duration)
		return
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
		if stream.loop_end <= 0:
			# WAVs imported without loop metadata have loop_end 0 — an empty
			# loop region kills playback instantly. Loop the full sample.
			var bytes_per_frame := 1
			if stream.format == AudioStreamWAV.FORMAT_16_BITS:
				bytes_per_frame = 2
			if stream.stereo:
				bytes_per_frame *= 2
			stream.loop_end = stream.data.size() / bytes_per_frame
	elif stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
	return stream

# ============================================================
# Ambience (looping, follows the SFX volume slider)
# ============================================================

func play_ambient(key: String):
	if not AMBIENT_PATHS.has(key):
		push_warning("AudioManager: no ambient key '%s'" % key)
		return
	var path = AMBIENT_PATHS[key]
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: ambient file not found: %s" % path)
		return
	_ambient_player.stream = _load_looping(path)
	_ambient_player.volume_db = SFX_VOLUME_DB + AMBIENT_OFFSET_DB
	_ambient_player.play()

func stop_ambient():
	_ambient_player.stop()

# ============================================================
# SFX
# ============================================================

func play_sfx(key: String, pitch_scale: float = 1.0, volume_scale: float = 1.0):
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
	player.volume_db = SFX_VOLUME_DB + (-80.0 if volume_scale <= 0.0 else linear_to_db(clampf(volume_scale, 0.0, 1.0)))
	player.pitch_scale = pitch_scale
	player.play()

func play_hover():
	if not SFX_PATHS.has("hover"):
		return
	var path = SFX_PATHS["hover"]
	if not ResourceLoader.exists(path):
		return
	var player = _get_next_sfx_player()
	player.stream = load(path)
	# Follows the SFX slider (offset quieter) — was a fixed level that made
	# menu sounds ignore the volume setting entirely.
	player.volume_db = SFX_VOLUME_DB + HOVER_OFFSET_DB
	player.pitch_scale = 1.0   # pool players are shared; clear any sfx pitch
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

func set_master_volume(linear: float):
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), _user_db(linear))

func set_music_volume(linear: float):
	# linear: 0.0 to 1.0. Preserve the authored music base level — the old code
	# replaced it outright, which played music 30 dB louder than designed.
	MUSIC_VOLUME_DB = MUSIC_BASE_DB + _user_db(linear)
	_music_player.volume_db = MUSIC_VOLUME_DB

func set_sfx_volume(linear: float):
	SFX_VOLUME_DB = _user_db(linear)
	for p in _sfx_players:
		p.volume_db = SFX_VOLUME_DB
	if _ambient_player:
		_ambient_player.volume_db = SFX_VOLUME_DB + AMBIENT_OFFSET_DB
