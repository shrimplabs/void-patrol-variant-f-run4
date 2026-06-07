extends Node
## AudioManager -- procedurally-generated SFX for Void Patrol.
##
## The project ships with no audio asset files (no .wav, no .ogg), so
## all SFX are synthesized at runtime via `AudioStreamWAV`. We pre-build
## a small bank of named sounds (shoot, explosion, pickup, ...) on
## first request, cache them, and play them through a pool of
## `AudioStreamPlayer` nodes. The pool avoids per-shot allocation and
## is sized to handle the densest case (a boss fight where multiple
## SFX overlap).
##
## API:
##   play(sfx_name: String, volume_db: float = 0.0) -> void
##   play_loop(sfx_name: String, volume_db: float = -6.0) -> AudioStreamPlayer
##   stop_loop() -> void
##   is_playing(sfx_name: String) -> bool
##   get_playing_count() -> int  # how many one-shots are still playing
##
## The SFX bank is built lazily on first play. Tests can also force a
## pre-build by calling `register_all()` from a fixture's before_each.
##
## IMPORTANT: This script is registered as an autoload (see
## project.godot). The autoload name is `AudioManager`. We do NOT
## declare `class_name AudioManager` on the autoload script -- doing
## so would collide with the autoload identifier and break any code
## that uses the bare name (mirrors the BulletPool pattern).

const SFX_POOL_SIZE := 8
## Default sample rate for the generated WAVs. 22050 is plenty for
## short SFX (a few hundred ms each) and halves the memory vs 44100.
const DEFAULT_MIX_RATE := 22050

## Names of all SFX in the bank. Kept as a constant so tests can
## iterate them.
const SFX_NAMES := [
	"shoot",
	"enemy_shoot",
	"explosion_small",
	"explosion_large",
	"pickup",
	"shield_hit",
	"life_lost",
	"wave_clear",
	"boss_intensity",
	"victory",
	"game_over",
]

## Cache of built streams: sfx_name -> AudioStreamWAV
var _sfx_cache: Dictionary = {}
## Pool of AudioStreamPlayer nodes for one-shots.
var _pool: Array = []
## The current looping player (if any). boss_intensity uses this so we
## can start/stop a long-running drone without freeing it.
var _loop_player: AudioStreamPlayer = null
## Tracks how many one-shots are currently playing (for tests).
var _active_oneshots: int = 0


func _ready() -> void:
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "SfxPlayer_%d" % i
		p.bus = "Master"
		p.finished.connect(_on_player_finished.bind(p))
		add_child(p)
		_pool.append(p)


## Public: play a one-shot SFX. Picks the first idle player in the
## pool. If all players are busy the oldest active one is preempted.
func play(sfx_name: String, volume_db: float = 0.0) -> void:
	var stream := _get_or_build_sfx(sfx_name)
	if stream == null:
		return
	var p := _get_available_player()
	if p == null:
		return
	# Reuse the looping player for one-shots only when nothing else is
	# free AND the loop is idle (loop not playing). We don't preempt
	# an active loop with a one-shot -- that would break boss music.
	if _loop_player != null and _loop_player.playing:
		# Find a non-loop player.
		for candidate in _pool:
			if candidate != _loop_player and not candidate.playing:
				p = candidate
				break
	p.stream = stream
	p.volume_db = volume_db
	p.play()
	_active_oneshots += 1


## Public: start a looping SFX (used for `boss_intensity`). Returns the
## looping AudioStreamPlayer, or null if the SFX is unknown. The loop
## is exclusive -- a second call to play_loop without a stop_loop
## replaces the previous loop.
func play_loop(sfx_name: String, volume_db: float = -6.0) -> AudioStreamPlayer:
	if _loop_player != null:
		stop_loop()
	var stream := _get_or_build_sfx(sfx_name)
	if stream == null:
		return null
	_loop_player = AudioStreamPlayer.new()
	_loop_player.name = "LoopPlayer"
	_loop_player.bus = "Master"
	_loop_player.volume_db = volume_db
	add_child(_loop_player)
	_loop_player.stream = stream
	_loop_player.play()
	return _loop_player


## Public: stop the current loop (if any) and free the player.
func stop_loop() -> void:
	if _loop_player == null:
		return
	_loop_player.stop()
	_loop_player.queue_free()
	_loop_player = null


## Public: is a one-shot with the given name currently playing? We
## don't track names per-player (the pool reuses players), so this
## iterates the pool and checks each playing player's stream's
## resource path (which we set to the SFX name for traceability).
func is_playing(sfx_name: String) -> bool:
	for p in _pool:
		if p == null:
			continue
		if p.playing and p.stream != null:
			var sfx_id := _stream_to_sfx_name(p.stream)
			if sfx_id == sfx_name:
				return true
	return false


## Public: how many one-shots are currently in flight. The loop
## doesn't count toward this number.
func get_playing_count() -> int:
	return _active_oneshots


## Public: pre-build every SFX in the bank. Tests call this from
## before_each so a one-shot play() doesn't pay the (small) build
## cost during the first frame.
func register_all() -> void:
	for n: String in SFX_NAMES:
		_get_or_build_sfx(n)


## Public: clear the SFX cache. Tests use this to assert on a
## "first-time build" path without polluting other tests.
func clear_cache() -> void:
	_sfx_cache.clear()


# ---------------------------------------------------------------------
# SFX bank (procedural synthesis)
# ---------------------------------------------------------------------

## Return the cached AudioStreamWAV for the given name, building it
## on first request. Returns null if the name is unknown.
func _get_or_build_sfx(sfx_name: String) -> AudioStreamWAV:
	if _sfx_cache.has(sfx_name):
		return _sfx_cache[sfx_name]
	var stream: AudioStreamWAV = null
	match sfx_name:
		"shoot":
			stream = _build_sine(880.0, 0.06, 0.005, 0.05, 0.7)
		"enemy_shoot":
			stream = _build_sine(220.0, 0.07, 0.005, 0.06, 0.5)
		"explosion_small":
			stream = _build_noise(0.20, 0.005, 0.15, 0.8)
		"explosion_large":
			stream = _build_explosion_large()
		"pickup":
			stream = _build_arpeggio([523.25, 659.25, 783.99], 0.06, 0.005, 0.04, 0.6)
		"shield_hit":
			stream = _build_shield_hit()
		"life_lost":
			stream = _build_sine(440.0, 0.40, 0.005, 0.20, 0.7, -1.0)
		"wave_clear":
			stream = _build_arpeggio([523.25, 659.25, 783.99, 1046.50], 0.10, 0.005, 0.06, 0.6)
		"boss_intensity":
			stream = _build_boss_drone()
		"victory":
			stream = _build_arpeggio([523.25, 659.25, 783.99, 1046.50], 0.13, 0.005, 0.10, 0.7)
		"game_over":
			stream = _build_arpeggio([523.25, 440.0, 349.23, 261.63], 0.18, 0.005, 0.10, 0.7)
		_:
			push_warning("AudioManager: unknown SFX '%s'" % sfx_name)
			return null
	if stream != null:
		_sfx_cache[sfx_name] = stream
	return stream


## Build a simple sine-wave SFX. `freq` is the pitch (Hz), `duration`
## is the total length in seconds. `attack` / `release` shape the
## amplitude envelope. `pitch_slide` is a per-second pitch shift
## (e.g. -1.0 = drop one octave over `duration`).
func _build_sine(
	freq: float,
	duration: float,
	attack: float,
	release: float,
	volume: float,
	pitch_slide: float = 0.0,
) -> AudioStreamWAV:
	var mix_rate := DEFAULT_MIX_RATE
	var sample_count: int = int(duration * float(mix_rate))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var env: float = _envelope(t, duration, attack, release)
		var current_freq: float = freq * pow(2.0, pitch_slide * t / 12.0)
		var phase: float = TAU * current_freq * t
		var sample: float = sin(phase) * env * volume
		_write_sample(data, i, sample)
	return _wav_from_data(data, mix_rate)


## Build a noise-burst SFX. Used for explosions and shield hits.
## The noise is a low-pass-filtered pseudo-random signal (each sample
## is averaged with the previous one) so it has a "thump" rather than
## a sharp hiss.
func _build_noise(
	duration: float,
	attack: float,
	release: float,
	volume: float,
) -> AudioStreamWAV:
	var mix_rate := DEFAULT_MIX_RATE
	var sample_count: int = int(duration * float(mix_rate))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var prev: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var env: float = _envelope(t, duration, attack, release)
		var raw: float = rng.randf_range(-1.0, 1.0)
		# 1-pole low-pass: smooth random -> "thump".
		var smoothed: float = prev * 0.7 + raw * 0.3
		prev = smoothed
		var sample: float = smoothed * env * volume
		_write_sample(data, i, sample)
	return _wav_from_data(data, mix_rate)


## Build the large-explosion SFX: a sub-bass thump (60Hz) layered with
## a noise tail.
func _build_explosion_large() -> AudioStreamWAV:
	var mix_rate := DEFAULT_MIX_RATE
	var duration: float = 0.4
	var sample_count: int = int(duration * float(mix_rate))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var prev: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var env: float = _envelope(t, duration, 0.005, 0.20)
		# Sub-bass thump.
		var thump: float = sin(TAU * 60.0 * t) * 0.6
		# Filtered noise tail.
		var raw: float = rng.randf_range(-1.0, 1.0)
		var smoothed: float = prev * 0.6 + raw * 0.4
		prev = smoothed
		var sample: float = (thump + smoothed * 0.4) * env * 0.9
		_write_sample(data, i, sample)
	return _wav_from_data(data, mix_rate)


## Build a shield-hit SFX: short descending blip with a noise transient.
func _build_shield_hit() -> AudioStreamWAV:
	var mix_rate := DEFAULT_MIX_RATE
	var duration: float = 0.18
	var sample_count: int = int(duration * float(mix_rate))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var env: float = _envelope(t, duration, 0.003, 0.08)
		# Descending tone 660Hz -> 330Hz.
		var f: float = lerp(660.0, 330.0, t / duration)
		var tone: float = sin(TAU * f * t)
		# Brief noise transient at the start (max(0, 0.04 - t)).
		var trans_t: float = 0.04 - t
		var trans_atten: float = trans_t if trans_t > 0.0 else 0.0
		var noise: float = rng.randf_range(-1.0, 1.0) * trans_atten
		var sample: float = (tone * 0.6 + noise * 0.4) * env
		_write_sample(data, i, sample)
	return _wav_from_data(data, mix_rate)


## Build an arpeggio from a list of pitches. Each note plays for
## `note_duration` seconds back-to-back; the total stream length is
## `len(pitches) * note_duration`.
func _build_arpeggio(
	pitches: Array,
	note_duration: float,
	attack: float,
	release: float,
	volume: float,
) -> AudioStreamWAV:
	var mix_rate := DEFAULT_MIX_RATE
	var total_duration: float = note_duration * float(pitches.size())
	var sample_count: int = int(total_duration * float(mix_rate))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		var note_idx: int = int(t / note_duration)
		if note_idx >= pitches.size():
			note_idx = pitches.size() - 1
		var note_t: float = t - float(note_idx) * note_duration
		var env: float = _envelope(note_t, note_duration, attack, release)
		var freq: float = float(pitches[note_idx])
		var sample: float = sin(TAU * freq * t) * env * volume
		_write_sample(data, i, sample)
	return _wav_from_data(data, mix_rate)


## Build the boss-intensity drone: a low sustained chord with a slow
## pulse, suitable for looping. ~1.5s total so the loop point is
## inaudible.
func _build_boss_drone() -> AudioStreamWAV:
	var mix_rate := DEFAULT_MIX_RATE
	var duration: float = 1.5
	var sample_count: int = int(duration * float(mix_rate))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	# Drone chord: low octave C2 + Eb2 + G2.
	var chord: Array = [65.41, 77.78, 98.00]
	for i in range(sample_count):
		var t: float = float(i) / float(mix_rate)
		# Slow tremolo pulse, ~1.5 Hz.
		var env: float = 0.6 + 0.4 * (0.5 + 0.5 * sin(TAU * 1.5 * t))
		var sample: float = 0.0
		for f: float in chord:
			sample += sin(TAU * f * t)
		sample = sample / float(chord.size()) * env * 0.5
		_write_sample(data, i, sample)
	return _wav_from_data(data, mix_rate)


## ADSR-lite envelope. attack/release are seconds; sustain = 1.0
## (we don't model release-sustain for short SFX).
func _envelope(t: float, duration: float, attack: float, release: float) -> float:
	if t < attack:
		return t / max(0.001, attack)
	if t > duration - release:
		return max(0.0, (duration - t) / max(0.001, release))
	return 1.0


## Write a single 16-bit signed sample into the byte buffer.
func _write_sample(data: PackedByteArray, idx: int, sample: float) -> void:
	var clipped: float = clampf(sample, -1.0, 1.0)
	var int_sample: int = int(clipped * 32767.0)
	if int_sample < 0:
		int_sample += 65536  # two's complement for 16-bit
	data[idx * 2] = int_sample & 0xff
	data[idx * 2 + 1] = (int_sample >> 8) & 0xff


## Build an AudioStreamWAV from raw 16-bit PCM.
func _wav_from_data(data: PackedByteArray, mix_rate: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	return stream


## Reverse-lookup a stream back to its SFX name. We use
## `resource_path` to identify the WAV, but since `AudioStreamWAV` is
## built in code (no resource path), we walk the cache instead.
func _stream_to_sfx_name(stream: AudioStream) -> String:
	for k: String in _sfx_cache.keys():
		if _sfx_cache[k] == stream:
			return k
	return ""


# ---------------------------------------------------------------------
# Player pool
# ---------------------------------------------------------------------

## Return the first idle (non-playing) AudioStreamPlayer in the pool,
## or null if every player is busy. The loop player is excluded from
## the one-shot pool.
func _get_available_player() -> AudioStreamPlayer:
	for p: AudioStreamPlayer in _pool:
		if p == _loop_player:
			continue
		if not p.playing:
			return p
	# All busy -- preempt the oldest one (first in the pool) so we
	# never drop a one-shot. The loop is NEVER preempted.
	for p: AudioStreamPlayer in _pool:
		if p != _loop_player:
			p.stop()
			return p
	return null


## Decrement the playing-count when a one-shot player finishes.
func _on_player_finished(player: AudioStreamPlayer) -> void:
	if player == _loop_player:
		return
	_active_oneshots = max(0, _active_oneshots - 1)
