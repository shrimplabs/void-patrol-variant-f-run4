extends GutTest
## GUT tests for game flow, scoring, high-score persistence (task 0007):
##  - HighScore helper: save/load round-trip on the ConfigFile,
##    lower-score no-clobber behavior, difficulty persistence
##  - GameState helper: state machine transitions, score / no-hit /
##    difficulty bookkeeping
##  - Main scene: menu -> playing transition via begin_session(),
##    wave-clear bonus calculation (100 * wave), no-hit bonus (+200),
##    high-score save on game over, difficulty increment on victory
##    -> menu
##  - Overlay wiring: end-of-run overlays show the right summary when
##    the player dies / the boss is defeated
##
## These tests intentionally avoid instantiating main.tscn directly.
## Instead they instantiate the high_score / game_state helpers and
## the Main script directly, and assert against the public API.
## Overlay integration is tested with the overlay scenes instantiated
## standalone so we can assert label text without driving the full
## game.

const MAIN_SCRIPT := preload("res://scripts/main.gd")
const MENU_SCENE := preload("res://scenes/menu_overlay.tscn")
const GAME_OVER_SCENE := preload("res://scenes/game_over_overlay.tscn")
const VICTORY_SCENE := preload("res://scenes/victory_overlay.tscn")

var _main: Node = null


func before_each() -> void:
	# Wipe the save file so each test starts from a clean state. The
	# high score / difficulty helpers read user://highscore.cfg on
	# init, so a stale save from a prior test could contaminate
	# assertions.
	HighScore.reset_save()
	_main = MAIN_SCRIPT.new()
	add_child_autofree(_main)


func after_each() -> void:
	_main = null
	HighScore.reset_save()


# ---------------------------------------------------------------------
# HighScore helper
# ---------------------------------------------------------------------

func test_high_score_load_returns_zero_when_no_save() -> void:
	assert_eq(HighScore.load_high_score(), 0,
		"Loading with no save should return 0")


func test_high_score_save_then_load_round_trips() -> void:
	var err: int = HighScore.save_high_score(12345)
	assert_eq(err, OK, "save should return OK")
	assert_eq(HighScore.load_high_score(), 12345,
		"loaded value should equal saved value")


func test_high_score_save_if_higher_only_writes_when_strictly_greater() -> void:
	HighScore.save_high_score(1000)
	# Lower score should not overwrite.
	var wrote_lower: bool = HighScore.save_if_higher(500)
	assert_false(wrote_lower,
		"save_if_higher should return false on a lower score")
	assert_eq(HighScore.load_high_score(), 1000,
		"high score should remain 1000 after a lower attempt")
	# Higher score should overwrite.
	var wrote_higher: bool = HighScore.save_if_higher(2000)
	assert_true(wrote_higher,
		"save_if_higher should return true on a higher score")
	assert_eq(HighScore.load_high_score(), 2000,
		"high score should be updated to 2000")


func test_high_score_save_preserves_difficulty() -> void:
	HighScore.save_difficulty(3)
	HighScore.save_high_score(9999)
	assert_eq(HighScore.load_difficulty(), 3,
		"save_high_score should not clobber the difficulty value")
	assert_eq(HighScore.load_high_score(), 9999,
		"save_high_score should still write the new score")


func test_high_score_difficulty_load_returns_zero_when_unset() -> void:
	assert_eq(HighScore.load_difficulty(), 0,
		"Difficulty should default to 0 on a fresh save")


# ---------------------------------------------------------------------
# GameState helper
# ---------------------------------------------------------------------

func test_game_state_starts_in_menu_with_zero_score() -> void:
	var gs: RefCounted = GameState.new()
	var state: Dictionary = gs.get_state()
	assert_eq(int(state["state"]), GameState.SessionState.MENU,
		"fresh GameState should default to MENU")
	assert_eq(int(state["current_score"]), 0, "score should start at 0")
	assert_eq(int(state["high_score"]), 0, "high score should start at 0")
	assert_eq(int(state["difficulty"]), 0, "difficulty should start at 0")
	assert_eq(str(state["state_name"]), "menu",
		"state_name should be 'menu'")


func test_game_state_set_state_emits_signal_and_updates_field() -> void:
	var gs: RefCounted = GameState.new()
	var received: Array = []
	gs.state_changed.connect(func(s): received.append(s))
	gs.set_state(GameState.SessionState.PLAYING)
	assert_eq(gs.state, GameState.SessionState.PLAYING,
		"state should be PLAYING after set_state")
	assert_eq(received.size(), 1, "state_changed should fire once")
	assert_eq(int(received[0]), GameState.SessionState.PLAYING,
		"state_changed payload should be the new state")


func test_game_state_set_state_to_same_value_does_not_emit() -> void:
	var gs: RefCounted = GameState.new()
	var received: Array = []
	gs.state_changed.connect(func(s): received.append(s))
	gs.set_state(GameState.SessionState.MENU)  # already MENU
	assert_eq(received.size(), 0,
		"set_state to the current value should not emit state_changed")


func test_game_state_add_score_clamps_to_zero_on_negative() -> void:
	var gs: RefCounted = GameState.new()
	gs.add_score(-50)
	assert_eq(gs.current_score, 0,
		"Negative add_score should clamp to 0, not go negative")


func test_game_state_add_score_updates_high_score() -> void:
	var gs: RefCounted = GameState.new()
	gs.add_score(500)
	assert_eq(gs.current_score, 500, "score should be 500")
	assert_eq(gs.high_score, 500, "high_score should track max")
	gs.add_score(200)
	assert_eq(gs.current_score, 700, "score should be 700")
	assert_eq(gs.high_score, 700, "high_score should still track max")


func test_game_state_no_hit_flag_resets_on_begin_wave() -> void:
	var gs: RefCounted = GameState.new()
	gs.begin_wave(1)
	assert_true(gs.wave_no_hit, "wave_no_hit should start true")
	gs.mark_wave_hit()
	assert_false(gs.wave_no_hit, "mark_wave_hit should flip the flag")
	gs.begin_wave(2)
	assert_true(gs.wave_no_hit, "begin_wave should reset the flag")


func test_game_state_mark_wave_hit_is_idempotent() -> void:
	var gs: RefCounted = GameState.new()
	gs.begin_wave(1)
	var received: Array = []
	gs.no_hit_changed.connect(func(b): received.append(b))
	gs.mark_wave_hit()
	gs.mark_wave_hit()  # second call should not re-emit
	assert_eq(received.size(), 1,
		"no_hit_changed should fire exactly once")


func test_game_state_increment_difficulty_persists() -> void:
	var gs: RefCounted = GameState.new()
	gs.increment_difficulty()
	assert_eq(gs.difficulty, 1, "difficulty should increment to 1")
	assert_eq(HighScore.load_difficulty(), 1,
		"difficulty should be persisted to disk")
	# A new GameState should see the persisted value.
	var gs2: RefCounted = GameState.new()
	assert_eq(gs2.difficulty, 1,
		"a fresh GameState should pick up the persisted difficulty")


# ---------------------------------------------------------------------
# Main scene: menu -> playing and overlay wiring
# ---------------------------------------------------------------------

func test_main_starts_in_menu_state_with_score_zero() -> void:
	var state: Dictionary = _main.get_game_state()
	assert_eq(int(state["game_flow"]["state"]),
			GameState.SessionState.MENU,
		"Main should boot in MENU state")
	assert_eq(int(state["score"]), 0, "score should start at 0")


func test_main_begin_session_transitions_to_playing() -> void:
	_main.begin_session()
	var state: Dictionary = _main.get_game_state()
	assert_eq(int(state["game_flow"]["state"]),
			GameState.SessionState.PLAYING,
		"begin_session should transition to PLAYING")
	assert_eq(int(state["score"]), 0,
		"score should still be 0 after begin_session")


func test_main_begin_session_resets_score_on_second_call() -> void:
	_main.begin_session()
	# Simulate scoring during the run by adding directly via add_score
	# (which mirrors to GameState).
	_main.add_score(1500)
	assert_eq(_main.score, 1500, "score should be 1500 after add")
	# Begin a new session -- the score should reset.
	_main.begin_session()
	assert_eq(_main.score, 0,
		"score should reset to 0 when starting a new session")
	assert_eq(_main.get_game_state()["game_flow"]["current_score"], 0,
		"GameState.current_score should also reset")


func test_main_get_game_state_includes_game_flow_keys() -> void:
	var state: Dictionary = _main.get_game_state()
	assert_has(state, "game_flow",
		"get_game_state should include game_flow")
	var flow: Dictionary = state["game_flow"]
	var expected_keys: Array = [
		"state", "state_name", "current_score", "high_score",
		"difficulty", "wave_no_hit", "no_hit_wave_number",
	]
	for k: String in expected_keys:
		assert_has(flow, k,
			"game_flow should include key: %s" % k)


# ---------------------------------------------------------------------
# Wave-clear bonus (the +100 * wave + optional +200 no-hit)
# ---------------------------------------------------------------------

func test_wave_cleared_awards_100_times_wave_number() -> void:
	# Drive a wave-clear via main's handler. The wave manager is not
	# involved -- we call the handler directly to isolate the
	# scoring logic from the wave-manager state machine.
	_main.begin_session()
	# Simulate clearing wave 3. No damage was taken, so the no-hit
	# bonus would normally apply, but we add a damage event first to
	# isolate the per-wave bonus.
	_main._on_wave_started(3)
	# Mark the wave as hit (player took damage) so the +200 no-hit
	# bonus is NOT awarded -- we want to assert the per-wave
	# component is exactly 300.
	_main._game_state.mark_wave_hit()
	var before: int = _main.score
	_main._on_wave_cleared(3)
	var after: int = _main.score
	assert_eq(after - before, 100 * 3,
		"wave-clear bonus should be 100 * 3 = 300 when wave is NOT no-hit")


func test_wave_cleared_adds_no_hit_bonus_when_shield_never_dropped() -> void:
	_main.begin_session()
	_main._on_wave_started(2)
	# No damage -- the no-hit flag should still be true.
	assert_true(_main._game_state.wave_no_hit,
		"no-hit flag should be true after a clean wave start")
	_main._on_wave_cleared(2)
	# Bonus = 100 * 2 + 200 = 400.
	assert_eq(_main.score, 100 * 2 + 200,
		"clean wave clear should award 200 no-hit bonus")


func test_wave_cleared_no_hit_bonus_is_withheld_on_damage() -> void:
	_main.begin_session()
	_main._on_wave_started(1)
	# Take some damage. The shield_changed signal handler in main
	# calls _game_state.mark_wave_hit() when current < _last_shield
	# (the seeded value is the player's initial shield, so any drop
	# counts as damage).
	_main.player.take_damage(20)
	assert_false(_main._game_state.wave_no_hit,
		"no-hit flag should be false after taking damage")
	_main._on_wave_cleared(1)
	# Bonus = 100 * 1 + 0 = 100 (no-hit bonus is NOT awarded).
	assert_eq(_main.score, 100 * 1,
		"damaged wave clear should award no no-hit bonus")


# ---------------------------------------------------------------------
# High score persistence on game over
# ---------------------------------------------------------------------

func test_player_died_saves_high_score() -> void:
	_main.begin_session()
	_main.add_score(5000)
	# Simulate the player dying.
	_main._on_player_died()
	# The in-memory high score should equal the session score.
	assert_eq(_main.high_score, 5000, "high_score should be 5000 in memory")
	# The high score should also be persisted to disk.
	assert_eq(HighScore.load_high_score(), 5000,
		"high score should be saved to disk on game over")
	# Session state should be GAME_OVER.
	assert_eq(int(_main.get_game_state()["game_flow"]["state"]),
			GameState.SessionState.GAME_OVER,
		"session state should transition to GAME_OVER")


func test_player_died_does_not_overwrite_higher_existing_high_score() -> void:
	HighScore.save_high_score(9999)
	_main.begin_session()
	_main.add_score(1000)  # lower than the persisted 9999
	_main._on_player_died()
	assert_eq(HighScore.load_high_score(), 9999,
		"lower run should not clobber a higher existing high score")


# ---------------------------------------------------------------------
# Difficulty increment on victory
# ---------------------------------------------------------------------

func test_difficulty_starts_at_zero() -> void:
	assert_eq(int(_main.get_game_state()["game_flow"]["difficulty"]), 0,
		"fresh save should yield difficulty == 0")


func test_victory_continue_increments_difficulty() -> void:
	_main.begin_session()
	# Simulate the boss being defeated -- the wave manager signal
	# would normally drive this, but we call the handler directly.
	_main._on_boss_defeated()
	assert_eq(int(_main.get_game_state()["game_flow"]["state"]),
			GameState.SessionState.VICTORY,
		"session should be VICTORY after boss defeat")
	# Player presses Enter on the victory screen.
	_main._on_victory_continue_pressed()
	assert_eq(int(_main.get_game_state()["game_flow"]["difficulty"]), 1,
		"difficulty should increment to 1 after returning to menu from victory")
	assert_eq(HighScore.load_difficulty(), 1,
		"difficulty should be persisted to disk")
	assert_eq(int(_main.get_game_state()["game_flow"]["state"]),
			GameState.SessionState.MENU,
		"session should transition back to MENU")


func test_difficulty_persists_across_main_instances() -> void:
	# First instance: victory -> back to menu (difficulty becomes 1).
	_main.begin_session()
	_main._on_boss_defeated()
	_main._on_victory_continue_pressed()
	# Second instance: should pick up difficulty == 1 from disk.
	var main2: Node = MAIN_SCRIPT.new()
	add_child_autofree(main2)
	assert_eq(int(main2.get_game_state()["game_flow"]["difficulty"]), 1,
		"fresh Main should see the persisted difficulty")


# ---------------------------------------------------------------------
# Overlay integration
# ---------------------------------------------------------------------

func test_menu_overlay_shows_high_score_on_set() -> void:
	var menu: CanvasLayer = MENU_SCENE.instantiate()
	add_child_autofree(menu)
	menu.set_high_score(12345)
	# The HighScore label should be visible and show the value.
	var label: Label = menu.get_node("Root/Content/HighScore")
	assert_true(label.visible,
		"HighScore label should be visible for non-zero value")
	assert_true("12345" in str(label.text),
		"HighScore label should show the value: %s" % str(label.text))


func test_menu_overlay_hides_high_score_when_zero() -> void:
	var menu: CanvasLayer = MENU_SCENE.instantiate()
	add_child_autofree(menu)
	menu.set_high_score(0)
	var label: Label = menu.get_node("Root/Content/HighScore")
	assert_false(label.visible,
		"HighScore label should be hidden when high score is 0")


func test_menu_overlay_emits_start_pressed_on_enter() -> void:
	var menu: CanvasLayer = MENU_SCENE.instantiate()
	add_child_autofree(menu)
	var received: Array = []
	menu.start_pressed.connect(func(): received.append(true))
	# Synthesize an "ui_accept" input event. The default Godot 4
	# input map has ui_accept pre-registered (Enter / Space / gamepad
	# Start) so the action is recognised.
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	menu._unhandled_input(ev)
	assert_eq(received.size(), 1,
		"start_pressed should fire once on Enter")


func test_game_over_overlay_shows_summary() -> void:
	var go: CanvasLayer = GAME_OVER_SCENE.instantiate()
	add_child_autofree(go)
	go.set_summary(42000, 50000, false)
	var score_label: Label = go.get_node("Root/Content/Score")
	var high_label: Label = go.get_node("Root/Content/HighScore")
	assert_true("42000" in str(score_label.text),
		"GameOver score label should show 42000")
	assert_true("50000" in str(high_label.text),
		"GameOver high-score label should show 50000")
	# Not new-high -- the high-score line should say "HIGH  SCORE"
	# (not "NEW  HIGH  SCORE!").
	assert_true("HIGH  SCORE" in str(high_label.text),
		"non-celebratory high-score line should use 'HIGH  SCORE' prefix")


func test_game_over_overlay_celebrates_new_high() -> void:
	var go: CanvasLayer = GAME_OVER_SCENE.instantiate()
	add_child_autofree(go)
	go.set_summary(50000, 50000, true)
	var high_label: Label = go.get_node("Root/Content/HighScore")
	assert_true("NEW  HIGH  SCORE!" in str(high_label.text),
		"celebratory line should say 'NEW  HIGH  SCORE!'")


func test_victory_overlay_shows_continue_prompt() -> void:
	var v: CanvasLayer = VICTORY_SCENE.instantiate()
	add_child_autofree(v)
	var prompt: Label = v.get_node("Root/Content/Prompt")
	assert_true("CONTINUE" in str(prompt.text),
		"Victory prompt should say 'PRESS  ENTER  TO  CONTINUE'")


func test_victory_overlay_emits_continue_pressed_on_enter() -> void:
	var v: CanvasLayer = VICTORY_SCENE.instantiate()
	add_child_autofree(v)
	var received: Array = []
	v.continue_pressed.connect(func(): received.append(true))
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	v._unhandled_input(ev)
	assert_eq(received.size(), 1,
		"continue_pressed should fire once on Enter")


func test_game_over_overlay_emits_restart_pressed_on_enter() -> void:
	var go: CanvasLayer = GAME_OVER_SCENE.instantiate()
	add_child_autofree(go)
	var received: Array = []
	go.restart_pressed.connect(func(): received.append(true))
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	go._unhandled_input(ev)
	assert_eq(received.size(), 1,
		"restart_pressed should fire once on Enter")
