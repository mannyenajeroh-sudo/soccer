extends Node

# ============================================================
#  SoundManager.gd — STREET 3 ELITE  (Polish Pass)
#
#  Fully procedural audio — generates tones using AudioStreamGenerator
#  when no real audio files are present.  Drop real .ogg/.wav files
#  into res://audio/ with matching names and they auto-load.
#
#  Real file names expected (optional, falls back to synth):
#    audio/kick.ogg, audio/kick_hard.ogg
#    audio/bounce.ogg
#    audio/whistle.ogg
#    audio/goal_cheer.ogg
#    audio/crowd_ambient.ogg, audio/crowd_near_miss.ogg
#    audio/tackle.ogg
#    audio/flick.ogg
#    audio/roulette.ogg
#    audio/menu_hover.ogg, audio/menu_confirm.ogg
# ============================================================

const AUDIO_DIR  := "res://audio/"
const SYNTH_RATE := 44100

# Persistent players
var _players: Dictionary = {}   # name → AudioStreamPlayer
var _crowd_player:  AudioStreamPlayer = null
var _crowd_vol_db:  float = -18.0

func _ready() -> void:
	_load_or_create("kick",        AUDIO_DIR + "kick.ogg")
	_load_or_create("kick_hard",   AUDIO_DIR + "kick_hard.ogg")
	_load_or_create("bounce",      AUDIO_DIR + "bounce.ogg")
	_load_or_create("whistle",     AUDIO_DIR + "whistle.ogg")
	_load_or_create("goal",        AUDIO_DIR + "goal_cheer.ogg")
	_load_or_create("tackle",      AUDIO_DIR + "tackle.ogg")
	_load_or_create("flick",       AUDIO_DIR + "flick.ogg")
	_load_or_create("roulette",    AUDIO_DIR + "roulette.ogg")
	_load_or_create("menu_hover",  AUDIO_DIR + "menu_hover.ogg")
	_load_or_create("menu_confirm",AUDIO_DIR + "menu_confirm.ogg")

	# Crowd ambient — loops
	var crowd_node := AudioStreamPlayer.new()
	crowd_node.name = "CrowdAmbient"
	crowd_node.volume_db = _crowd_vol_db
	crowd_node.bus = "SFX"
	if ResourceLoader.exists(AUDIO_DIR + "crowd_ambient.ogg"):
		crowd_node.stream = load(AUDIO_DIR + "crowd_ambient.ogg")
		crowd_node.stream.set("loop", true)
	else:
		crowd_node.stream = _make_crowd_noise()
	add_child(crowd_node)
	_crowd_player = crowd_node
	crowd_node.play()

func _load_or_create(key: String, path: String) -> void:
	var ap := AudioStreamPlayer.new()
	ap.name = key
	ap.bus = "SFX"
	if ResourceLoader.exists(path):
		ap.stream = load(path)
	else:
		ap.stream = _make_synth_sound(key)
	add_child(ap)
	_players[key] = ap

# ── Synth fallbacks ────────────────────────────────────────

func _make_synth_sound(key: String) -> AudioStream:
	# Returns an AudioStreamWAV generated from PCM
	match key:
		"kick":        return _gen_pcm(0.18, 80.0,  0.0,   true,  0.0)
		"kick_hard":   return _gen_pcm(0.22, 60.0,  0.0,   true,  0.0)
		"bounce":      return _gen_pcm(0.10, 200.0, 0.0,   true,  0.0)
		"whistle":     return _gen_pcm(0.55, 1800.0,1400.0,false, 0.02)
		"goal":        return _gen_pcm(0.40, 200.0, 0.0,   true,  0.0)
		"tackle":      return _gen_pcm(0.12, 120.0, 0.0,   true,  0.0)
		"flick":       return _gen_pcm(0.10, 600.0, 800.0, false, 0.01)
		"roulette":    return _gen_pcm(0.20, 400.0, 600.0, false, 0.01)
		"menu_hover":  return _gen_pcm(0.08, 1200.0,1400.0,false, 0.0)
		"menu_confirm":return _gen_pcm(0.18, 880.0, 1200.0,false, 0.0)
		_:             return _gen_pcm(0.10, 400.0, 0.0,   false, 0.0)

## Generate a short PCM sound wave:
## dur=seconds, freq=base Hz, freq2=end Hz (sweep), noise=add white noise, vibrato_hz
func _gen_pcm(dur: float, freq: float, freq2: float, _noise: bool, vibrato_hz: float) -> AudioStreamWAV:
	var samples := int(SYNTH_RATE * dur)
	var data    := PackedByteArray()
	data.resize(samples * 2)  # 16-bit mono
	var f2: float = freq2 if freq2 > 0.0 else freq
	for i in samples:
		var t: float = float(i) / SYNTH_RATE
		var env: float = exp(-t * (8.0 / dur))  # exponential decay
		var inst_freq: float = lerp(freq, f2, float(i) / samples)
		var vibrato: float = sin(t * vibrato_hz * TAU) * 0.005 if vibrato_hz > 0.0 else 0.0
		var wave: float = sin(t * inst_freq * TAU + vibrato) * env
		# Add a tiny bit of white noise for texture
		wave += randf_range(-0.05, 0.05) * env
		var s := int(clampf(wave * 28000.0, -32768.0, 32767.0))
		data[i * 2]     = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format       = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo       = false
	wav.mix_rate     = SYNTH_RATE
	wav.data         = data
	return wav

func _make_crowd_noise() -> AudioStreamWAV:
	# Pink-ish noise that loops — simulates crowd murmur
	var samples := SYNTH_RATE * 2
	var data    := PackedByteArray()
	data.resize(samples * 2)
	var prev := 0.0
	for i in samples:
		var white: float = randf_range(-1.0, 1.0)
		prev = prev * 0.9 + white * 0.1   # low-pass pink approx
		var s := int(clampf(prev * 4000.0, -32768.0, 32767.0))
		data[i * 2]     = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo   = false
	wav.mix_rate = SYNTH_RATE
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end   = samples
	wav.data = data
	return wav

# ── Public API ─────────────────────────────────────────────

func kick(speed: float, _pos: Vector3) -> void:
	var vol := clampf(speed / 26.0, 0.3, 1.0)
	if speed > 18.0:
		_play("kick_hard", linear_to_db(vol))
		VisualEffects.kick_flash(_pos, vol)
	else:
		_play("kick", linear_to_db(vol * 0.85))
		if speed > 8.0:
			VisualEffects.kick_flash(_pos, vol * 0.6)

func bounce(impact_speed: float, _pos: Vector3) -> void:
	if impact_speed > 1.5:
		_play("bounce", linear_to_db(clampf(impact_speed / 14.0, 0.2, 1.0)))

func whistle() -> void:
	_play("whistle", linear_to_db(0.9))

func goal_cheer() -> void:
	_play("goal", linear_to_db(1.0))
	_crowd_boost(8.0, -4.0)

func play_celebration(celeb_type: int) -> void:
	match celeb_type:
		0: _play("menu_confirm", linear_to_db(0.7))
		1: _play("tackle", linear_to_db(0.6))
		2: _play("roulette", linear_to_db(0.85))
		3: _play("flick", linear_to_db(0.75))
		4: _play("goal", linear_to_db(0.9)); _crowd_boost(4.0, -2.0)
		5: _play("whistle", linear_to_db(0.5)); _play("goal", linear_to_db(0.95))
		6: _play("kick_hard", linear_to_db(1.0)); _crowd_boost(6.0, -3.0)
		7: _play("menu_hover", linear_to_db(0.65))
		_: goal_cheer()

func tackle_won() -> void:
	_play("tackle", linear_to_db(0.85))
	VisualEffects.tackle_spark(Vector3.ZERO)  # caller can pass pos

func tackle_at(pos: Vector3) -> void:
	_play("tackle", linear_to_db(0.85))
	VisualEffects.tackle_spark(pos)

func near_miss() -> void:
	_crowd_boost(3.0, -8.0)

func flick_up() -> void:
	_play("flick", linear_to_db(0.75))

func heel_flick() -> void:
	_play("flick", linear_to_db(0.70))

func roulette() -> void:
	_play("roulette", linear_to_db(0.80))

func menu_hover() -> void:
	_play("menu_hover", linear_to_db(0.5))

func menu_confirm() -> void:
	_play("menu_confirm", linear_to_db(0.85))

func set_crowd_volume(vol_db: float) -> void:
	_crowd_vol_db = vol_db
	if _crowd_player:
		_crowd_player.volume_db = vol_db

# ── Internals ──────────────────────────────────────────────

func _play(key: String, vol_db: float) -> void:
	var ap: AudioStreamPlayer = _players.get(key)
	if ap == null: return
	ap.volume_db = vol_db
	ap.play()

func _crowd_boost(duration: float, boost_db: float) -> void:
	if _crowd_player == null: return
	var base := _crowd_vol_db
	_crowd_player.volume_db = base + boost_db
	get_tree().create_timer(duration).timeout.connect(func():
		if is_instance_valid(_crowd_player):
			_crowd_player.volume_db = base
	)
