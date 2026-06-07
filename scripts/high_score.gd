extends RefCounted
class_name HighScore
## HighScore -- persistent high-score helper for Void Patrol.
##
## Pure data layer. Saves/loads a single int (the highest session score) to
## `user://highscore.cfg` via ConfigFile. Designed to be called by main.gd
## on game-over / victory / boot.
##
## We intentionally keep the storage location stable across runs so the
## file persists between launches. The schema is a single section with a
## single int key -- trivial to inspect / reset by hand if a player wants
## to wipe their record.
##
## This class is a RefCounted (not autoload) so it can be used from GUT
## tests without contaminating the autoload table. All members are
## static so callers don't need to instantiate it.

## File path under user://. ConfigFile accepts this directly.
const SAVE_PATH := "user://highscore.cfg"

## Section name in the ConfigFile.
const SECTION := "highscore"
## Key name within the section.
const KEY_SCORE := "score"
## Key name for the difficulty (loop counter). Stored alongside the
## score so a player's loop count survives between sessions even if the
## score file is reset.
const KEY_DIFFICULTY := "difficulty"


## Load the saved high score from disk. Returns 0 if the file is
## missing, corrupt, or the score value is invalid. Tests rely on this
## being a no-throw, no-side-effect read -- callers can poll it freely.
static func load_high_score() -> int:
	if not FileAccess.file_exists(SAVE_PATH):
		return 0
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		# Corrupt / unreadable file: treat as no high score. Don't wipe
		# the file -- a partial save could be salvageable by hand.
		return 0
	if not cfg.has_section_key(SECTION, KEY_SCORE):
		return 0
	var v = cfg.get_value(SECTION, KEY_SCORE, 0)
	if v == null:
		return 0
	# Cast via int() so we can absorb floats / strings the ConfigFile
	# might surface if the file was edited by hand.
	return int(v)


## Save `score` as the new high score to disk. Returns OK on success or
## an Error code on failure. Does NOT clobber an existing higher score
## (that's the caller's job -- use `save_if_higher` for the usual case).
static func save_high_score(score: int) -> int:
	var cfg := ConfigFile.new()
	# Preserve the difficulty value if it already exists; otherwise
	# default to 0. We never want save_high_score to wipe a loop
	# counter that was set on a previous run.
	if FileAccess.file_exists(SAVE_PATH):
		cfg.load(SAVE_PATH)
	cfg.set_value(SECTION, KEY_SCORE, int(score))
	return cfg.save(SAVE_PATH)


## Convenience: save `score` only if it's strictly greater than the
## currently-persisted value. Returns true if the file was updated.
## `false` is returned both when the score is lower AND when the write
## itself failed (callers don't usually need to distinguish).
static func save_if_higher(score: int) -> bool:
	var current := load_high_score()
	if score <= current:
		return false
	return save_high_score(score) == OK


## Load the persisted loop-count difficulty. Returns 0 when unset.
## Difficulty starts at 0 (the "first run") and increments by 1 each
## time the player returns to the menu from a victory screen.
static func load_difficulty() -> int:
	if not FileAccess.file_exists(SAVE_PATH):
		return 0
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return 0
	if not cfg.has_section_key(SECTION, KEY_DIFFICULTY):
		return 0
	return int(cfg.get_value(SECTION, KEY_DIFFICULTY, 0))


## Save the loop-count difficulty. Preserves the high score.
static func save_difficulty(difficulty: int) -> int:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(SAVE_PATH):
		cfg.load(SAVE_PATH)
	cfg.set_value(SECTION, KEY_DIFFICULTY, int(difficulty))
	return cfg.save(SAVE_PATH)


## Wipe the save file. Test-only convenience. Returns OK / FAILED.
## (No effect in production -- no code path calls this.)
static func reset_save() -> int:
	if not FileAccess.file_exists(SAVE_PATH):
		return OK
	var d := DirAccess.open("user://")
	if d == null:
		return FAILED
	return d.remove(SAVE_PATH.replace("user://", ""))
