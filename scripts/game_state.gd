extends RefCounted
class_name GameState
## GameState -- session-level state machine for Void Patrol.
##
## Owns the menu / playing / game_over / victory transitions and the
## cross-session counters (high score, difficulty loop count, current
## session score). Designed to be a thin data layer so main.gd can call
## `set_state(...)` and react via the state_changed signal without
## caring how the transitions are sequenced.
##
## Pure data; no scene tree dependencies. Tests instantiate the class
## directly to verify transitions / scoring events.

## Session state enum. Mirrors the four screens a player sees:
##   MENU       -- start menu visible, no waves, no enemies
##   PLAYING    -- wave manager active, player can move/shoot
##   GAME_OVER  -- player died, game over screen visible
##   VICTORY    -- boss defeated, victory screen visible
enum SessionState {
	MENU,
	PLAYING,
	GAME_OVER,
	VICTORY,
}

signal state_changed(new_state: int)
signal score_changed(new_score: int, high_score: int)
signal difficulty_changed(new_difficulty: int)
signal no_hit_changed(is_no_hit: bool)

## Current session state. Defaults to MENU (the player must press
## "Start" to begin).
var state: int = SessionState.MENU
## Score accumulated in the current run. Reset to 0 on
## `_begin_session()`.
var current_score: int = 0
## Best score across all saved runs. Loaded from disk on init, written
## back on session end.
var high_score: int = 0
## Loop counter. Starts at 0 (the first run), increments by 1 each
## time the player returns to the menu from a VICTORY screen. Applied
## to wave / boss parameters on the next session (see main.gd).
var difficulty: int = 0
## True while the player has not taken damage in the current wave.
## Tracked by main.gd's `_on_player_shield_changed` (resets to false
## on any drop). Reset to true on wave_started.
var wave_no_hit: bool = true
## The wave number we're currently tracking no-hit for. Set on
## wave_started, used by the no-hit bonus calculation.
var no_hit_wave_number: int = 0


func _init() -> void:
	# Load persisted values at construction so the menu shows the right
	# high score from the very first frame.
	high_score = HighScore.load_high_score()
	difficulty = HighScore.load_difficulty()


## Public: change the session state. Emits `state_changed`.
## Out-of-range values are clamped to MENU so the state machine never
## sits in an undefined state.
func set_state(new_state: int) -> void:
	var clamped: int = clampi(new_state, SessionState.MENU, SessionState.VICTORY)
	if clamped == state:
		return
	state = clamped
	state_changed.emit(state)


## Public: add `delta` to the current score. Updates the high score if
## the new value exceeds it (in-memory only -- the caller is
## responsible for calling `save()` at a stable moment like game over).
func add_score(delta: int) -> void:
	current_score = max(0, current_score + int(delta))
	if current_score > high_score:
		high_score = current_score
	score_changed.emit(current_score, high_score)


## Public: reset the current session's score (called at the start of a
## new run). Does NOT touch the high score.
func reset_score() -> void:
	current_score = 0
	score_changed.emit(current_score, high_score)


## Public: save the current high score to disk if it beats the
## previously-persisted value. Returns true on a successful write.
func save_high_score_if_higher() -> bool:
	return HighScore.save_if_higher(high_score)


## Public: increment the loop counter (difficulty bump) and persist it.
## Called when the player returns to the menu from a VICTORY screen.
func increment_difficulty() -> int:
	difficulty = difficulty + 1
	HighScore.save_difficulty(difficulty)
	difficulty_changed.emit(difficulty)
	return difficulty


## Public: re-read both the high score and the difficulty from disk.
## Useful after the QA harness wipes the save file mid-test.
func reload_persisted() -> void:
	high_score = HighScore.load_high_score()
	difficulty = HighScore.load_difficulty()
	score_changed.emit(current_score, high_score)
	difficulty_changed.emit(difficulty)


## Public: reset wave-level no-hit tracking. Called by main on
## wave_started. The wave number is captured so a late no-hit check
## knows which wave's bonus to award.
func begin_wave(wave_number: int) -> void:
	wave_no_hit = true
	no_hit_wave_number = int(wave_number)
	no_hit_changed.emit(true)


## Public: flag the current wave as no-longer-no-hit (the player took
## damage). Idempotent: a second call doesn't re-emit. No-op if we're
## already not-no-hit (avoids spurious signals when the shield bar
## pulses on regen).
func mark_wave_hit() -> void:
	if not wave_no_hit:
		return
	wave_no_hit = false
	no_hit_changed.emit(false)


## Public: snapshot for the StateServer / tests / HUD overlays. Always
## returns a fresh dictionary so callers can mutate without affecting
## our state.
func get_state() -> Dictionary:
	return {
		"state": state,
		"state_name": _state_name(state),
		"current_score": current_score,
		"high_score": high_score,
		"difficulty": difficulty,
		"wave_no_hit": wave_no_hit,
		"no_hit_wave_number": no_hit_wave_number,
	}


## Human-readable state name. Mirrors WaveManager._state_name()'s
## shape -- lowercase, snake_case.
func _state_name(s: int) -> String:
	match s:
		SessionState.MENU: return "menu"
		SessionState.PLAYING: return "playing"
		SessionState.GAME_OVER: return "game_over"
		SessionState.VICTORY: return "victory"
		_: return "unknown"
