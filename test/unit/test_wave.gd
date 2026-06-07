extends GutTest
## GUT tests for the procedural wave manager (task 0004):
##  - per-wave spawn parameters (drone/fighter/bomber counts, multipliers)
##  - clear detection: killing all spawned enemies advances state to CLEAR_DELAY
##  - 2s clear delay -> start_next_wave() advances the wave number
##  - un-cleared enemies from a prior wave are NOT cleared on the next spawn
##  - after wave 6, state transitions to BOSS_FIGHT and current_wave becomes 7
##  - INCOMING / WAVE CLEAR banners emit via the banner_shown signal

const WAVE_MANAGER_SCRIPT := preload("res://scripts/wave_manager.gd")
const MAIN_SCRIPT := preload("res://scripts/main.gd")

var _main: Node = null
var _wm: Node = null


func before_each() -> void:
	# Each test gets a fresh Main + WaveManager. We don't call
	# start_game() automatically; tests that want a wave to begin call
	# `_wm.start_game()` explicitly so they control when enemies spawn.
	_main = MAIN_SCRIPT.new()
	add_child_autofree(_main)
	# The Main scene auto-spawns a wave manager as a child. Use that
	# instance (preserves the wiring through Main) rather than building
	# a standalone one. If Main didn't spawn one (older code), fall back
	# to instantiating the script directly.
	_wm = _main.wave_manager
	if _wm == null:
		_wm = WAVE_MANAGER_SCRIPT.new()
		_main.add_child(_wm)
		_main.wave_manager = _wm


func after_each() -> void:
	# Kill any test-spawned enemies that the wave manager may still be
	# tracking. The free triggers tree_exited -> _alive_spawned cleanup
	# on the next frame, so the test isolation is per-test (one wave
	# manager instance per before_each).
	if _wm != null and is_instance_valid(_wm):
		var alive: Array = _wm._alive_spawned.duplicate()
		for e: Node in alive:
			if is_instance_valid(e):
				e.queue_free()
	_wm = null
	_main = null


# --- Helpers ------------------------------------------------------------

func _drain_pool() -> void:
	# Release any bullets that might have spawned during a fire-pattern
	# tick (fighters/bombers fire in _physics_process). The pool's free
	# list is then drained into the per-faction totals so subsequent
	# tests don't carry them over.
	if BulletPool == null:
		return
	for b: Node in get_tree().get_nodes_in_group("bullets"):
		if is_instance_valid(b) and b.has_method("_release_self"):
			b._release_self()


func _kill_all_alive() -> void:
	# Forcibly free every enemy the wave manager has tracked.
	if _wm == null:
		return
	var alive: Array = _wm._alive_spawned.duplicate()
	for e: Node in alive:
		if is_instance_valid(e):
			e.queue_free()


# --- Per-wave spawn parameters -----------------------------------------

func test_wave_1_is_pure_drone_swarm() -> void:
	var config: Dictionary = _wm.get_wave_config(1)
	assert_eq(int(config.get("drone", 0)), 5, "Wave 1 should spawn 5 drones")
	assert_eq(int(config.get("fighter", 0)), 0, "Wave 1 should spawn 0 fighters")
	assert_eq(int(config.get("bomber", 0)), 0, "Wave 1 should spawn 0 bombers")
	assert_almost_eq(float(config.get("speed_mult", 1.0)), 1.0, 0.001,
		"Wave 1 speed_mult should be 1.0")


func test_wave_2_introduces_fighters() -> void:
	var config: Dictionary = _wm.get_wave_config(2)
	assert_gt(int(config.get("fighter", 0)), 0, "Wave 2 should include fighters")
	assert_eq(int(config.get("bomber", 0)), 0, "Wave 2 should still have no bombers")


func test_wave_4_introduces_bombers() -> void:
	var config: Dictionary = _wm.get_wave_config(4)
	assert_gt(int(config.get("bomber", 0)), 0, "Wave 4 should include bombers")


func test_wave_6_has_no_drones_and_many_fighters_and_bombers() -> void:
	var config: Dictionary = _wm.get_wave_config(6)
	assert_eq(int(config.get("drone", 0)), 0, "Wave 6 should have no drones")
	assert_gt(int(config.get("fighter", 0)), 0, "Wave 6 should have fighters")
	assert_gt(int(config.get("bomber", 0)), 0, "Wave 6 should have bombers")


func test_wave_speed_multiplier_strictly_increases_from_wave_3_to_6() -> void:
	# The speed ramp should go up; wave 1 and 2 are baseline at 1.0.
	var s3: float = float(_wm.get_wave_config(3).get("speed_mult", 1.0))
	var s6: float = float(_wm.get_wave_config(6).get("speed_mult", 1.0))
	assert_gt(s6, s3, "Wave 6 speed_mult should be > wave 3's")
	assert_gt(s3, 1.0, "Wave 3 speed_mult should be > 1.0")


func test_wave_fire_rate_multiplier_strictly_decreases_from_wave_3_to_6() -> void:
	# Lower fire_rate_mult = faster cadence. So the trend is decreasing.
	var r3: float = float(_wm.get_wave_config(3).get("fire_rate_mult", 1.0))
	var r6: float = float(_wm.get_wave_config(6).get("fire_rate_mult", 1.0))
	assert_lt(r6, r3, "Wave 6 fire_rate_mult should be < wave 3's")
	assert_lt(r3, 1.0, "Wave 3 fire_rate_mult should be < 1.0")


func test_get_wave_config_returns_empty_for_out_of_range() -> void:
	assert_true(_wm.get_wave_config(0).is_empty(),
		"Wave 0 should return empty config")
	assert_true(_wm.get_wave_config(7).is_empty(),
		"Wave 7 should return empty config")
	assert_true(_wm.get_wave_config(-1).is_empty(),
		"Negative wave should return empty config")


func test_total_waves_constant_is_six() -> void:
	assert_eq(_wm.TOTAL_WAVES, 6, "TOTAL_WAVES should be 6")


# --- Spawning actually creates enemies ---------------------------------

func test_start_game_spawns_wave_1_enemies() -> void:
	_wm.start_game()
	# Wave 1 = 5 drones per config.
	assert_eq(_wm.get_alive_count(), 5,
		"Wave 1 should spawn 5 enemies (5 drones)")
	assert_eq(_wm.current_wave, 1, "current_wave should be 1")
	assert_eq(_wm.state, _wm.State.IN_PROGRESS,
		"State should be IN_PROGRESS after spawning")


func test_start_next_wave_increments_wave_number() -> void:
	_wm.start_game()
	assert_eq(_wm.current_wave, 1, "Start should set wave to 1")
	# Manually advance to wave 2 (without waiting for the clear delay).
	_wm.start_next_wave()
	assert_eq(_wm.current_wave, 2,
		"start_next_wave should increment current_wave to 2")


func test_wave_started_signal_fires_with_wave_number() -> void:
	var received: Array = []
	_wm.wave_started.connect(func(w): received.append(w))
	_wm.start_game()
	assert_eq(received.size(), 1, "wave_started should fire once on start_game")
	assert_eq(int(received[0]), 1, "wave_started should report wave 1")


# --- Apply modifiers to spawned enemies --------------------------------

func test_wave_3_applies_speed_multiplier_to_spawned_enemies() -> void:
	# Skip ahead to wave 3 by calling start_game + 2 manual advances.
	_wm.start_game()
	_kill_all_alive()
	await get_tree().physics_frame
	_wm.start_next_wave()
	_kill_all_alive()
	await get_tree().physics_frame
	_wm.start_next_wave()
	# Wave 3: drone base 140 * 1.10 = 154; fighter base 100 * 1.10 = 110.
	var drones := []
	var fighters := []
	for e: Node in _wm._alive_spawned:
		if not is_instance_valid(e):
			continue
		if "enemy_type_name" in e and str(e.enemy_type_name) == "drone":
			drones.append(e)
		elif "enemy_type_name" in e and str(e.enemy_type_name) == "fighter":
			fighters.append(e)
	if drones.size() > 0:
		assert_almost_eq(float(drones[0].move_speed), 140.0 * 1.10, 0.1,
			"Wave 3 drone should have 1.10x speed multiplier applied")
	if fighters.size() > 0:
		assert_almost_eq(float(fighters[0].move_speed), 100.0 * 1.10, 0.1,
			"Wave 3 fighter should have 1.10x speed multiplier applied")


# --- Clear detection ---------------------------------------------------

func test_is_wave_clear_is_false_when_enemies_alive() -> void:
	_wm.start_game()
	assert_false(_wm.is_wave_clear(),
		"Wave should not be clear while enemies are alive")


func test_killing_all_enemies_marks_wave_clear() -> void:
	_wm.start_game()
	_kill_all_alive()
	# tree_exited fires after the next frame; pump one physics tick so
	# the wave manager's _on_enemy_exited callback runs.
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(_wm.is_wave_clear(),
		"Wave should be clear after all enemies are freed")


func test_wave_cleared_signal_fires_on_clear() -> void:
	var received: Array = []
	_wm.wave_cleared.connect(func(w): received.append(w))
	_wm.start_game()
	_kill_all_alive()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(received.size(), 1, "wave_cleared should fire once")
	assert_eq(int(received[0]), 1, "wave_cleared should report wave 1")


func test_state_transitions_to_clear_delay_after_kill() -> void:
	_wm.start_game()
	_kill_all_alive()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(_wm.state, _wm.State.CLEAR_DELAY,
		"State should be CLEAR_DELAY after all enemies die")


func test_clear_delay_timer_runs_for_2_seconds() -> void:
	_wm.start_game()
	_kill_all_alive()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(_wm.state, _wm.State.CLEAR_DELAY,
		"State should be CLEAR_DELAY immediately after clear")
	# The timer was set to 2.0 in _on_wave_cleared and is then ticked
	# down by _process on every idle frame. By the time the assertion
	# runs, the timer may have decremented slightly. We assert that the
	# timer is between 1.5 and 2.0 (i.e. we haven't run out yet) and
	# that the constant matches the design doc.
	assert_gte(_wm._clear_timer, 1.5,
		"Clear timer should still have most of its 2.0s grace left")
	assert_lte(_wm._clear_timer, 2.0,
		"Clear timer should be at most 2.0 (initial value)")
	assert_almost_eq(_wm.CLEAR_DELAY_SECONDS, 2.0, 0.001,
		"CLEAR_DELAY_SECONDS constant should be 2.0 (design doc: 2s delay)")


# --- Banner emission --------------------------------------------------

func test_incoming_banner_emitted_on_wave_start() -> void:
	var banners: Array = []
	_wm.banner_shown.connect(func(text, _dur): banners.append(text))
	_wm.start_game()
	assert_eq(banners.size(), 1, "One banner should show on wave start")
	assert_true("WAVE 1" in str(banners[0]) or "WAVE  1" in str(banners[0]),
		"INCOMING banner should mention the wave number: %s" % str(banners[0]))


func test_wave_clear_banner_emitted_on_clear() -> void:
	var banners: Array = []
	_wm.banner_shown.connect(func(text, _dur): banners.append(text))
	_wm.start_game()
	_kill_all_alive()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(banners.size() >= 2,
		"Should see both INCOMING and WAVE CLEAR banners")
	var saw_clear: bool = false
	for b: String in banners:
		if "CLEAR" in b:
			saw_clear = true
			break
	assert_true(saw_clear, "WAVE CLEAR banner should fire on clear")


# --- Un-cleared enemies persist into the next wave ---------------------

func test_un_cleared_enemies_persist_into_next_wave() -> void:
	# Don't kill the wave-1 enemies; advance to wave 2 and confirm the
	# wave-1 enemies are still alive (we are not auto-clearing on advance).
	_wm.start_game()
	var wave1_count: int = _wm.get_alive_count()
	assert_gt(wave1_count, 0, "Wave 1 should have spawned some enemies")
	# Advance to wave 2 without freeing anyone.
	_wm.start_next_wave()
	var wave2_count: int = _wm.get_alive_count()
	# wave2_count = surviving wave-1 enemies + freshly-spawned wave-2
	# enemies. The contract is that wave-1 enemies persist (so the new
	# count is strictly greater than wave-2's fresh-spawn count of 7).
	var wave2_config: Dictionary = _wm.get_wave_config(2)
	var wave2_fresh: int = int(wave2_config.get("drone", 0)) \
		+ int(wave2_config.get("fighter", 0)) \
		+ int(wave2_config.get("bomber", 0))
	assert_gt(wave2_count, wave2_fresh,
		"Wave-1 enemies should still be alive after wave-2 spawns")


# --- BOSS transition ---------------------------------------------------

func test_state_transitions_to_boss_after_wave_6() -> void:
	# Skip ahead by starting game then calling start_next_wave 5 more
	# times -- the wave manager will spawn waves 2..6 then transition.
	_wm.start_game()  # spawns wave 1
	# Free the wave-1 enemies so wave 2 can spawn cleanly.
	_kill_all_alive()
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Waves 2..6: each start_next_wave advances. The clear-delay timer
	# is ticked in _process, so we tick it manually with delta=0.5 to
	# simulate elapsed time.
	for wave_idx in range(2, 7):
		# Wait for the clear delay to elapse by stepping _process.
		# _clear_timer starts at 2.0; we tick it down to 0.
		for _step in range(5):
			_wm._process(0.5)  # 5 * 0.5 = 2.5s, exceeds 2.0s clear delay
		# Should now have advanced to the next wave.
		assert_eq(_wm.current_wave, wave_idx,
			"After tick + advance, should be on wave %d (got %d)" % [wave_idx, _wm.current_wave])
		# Free the just-spawned enemies so the next wave can spawn.
		_kill_all_alive()
		await get_tree().physics_frame
		await get_tree().physics_frame
	# After wave 6 is fully cleared, _process should have transitioned
	# to BOSS_FIGHT. Tick enough to flush the clear delay.
	for _step in range(5):
		_wm._process(0.5)
	# Wave 6 cleared -> next start_next_wave -> boss_fight.
	_kill_all_alive()
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Trigger one more clear-delay tick that will call start_next_wave
	# internally, which then transitions to boss_fight.
	for _step in range(5):
		_wm._process(0.5)
	assert_eq(_wm.state, _wm.State.BOSS_FIGHT,
		"State should be BOSS_FIGHT after wave 6 clears")
	assert_eq(_wm.current_wave, 7,
		"current_wave should be 7 once BOSS_FIGHT starts")


func test_boss_fight_started_signal_fires_on_wave_6_complete() -> void:
	var fired: Array = []
	_wm.boss_fight_started.connect(func(): fired.append(true))
	# Fast-forward: start + clear wave 1, then loop through 2..6 with
	# fake _process ticks. The boss signal should fire once at the end.
	_wm.start_game()
	_kill_all_alive()
	await get_tree().physics_frame
	await get_tree().physics_frame
	for wave_idx in range(2, 7):
		for _step in range(5):
			_wm._process(0.5)
		assert_eq(_wm.current_wave, wave_idx,
			"Should be on wave %d (got %d)" % [wave_idx, _wm.current_wave])
		_kill_all_alive()
		await get_tree().physics_frame
		await get_tree().physics_frame
	# Now the clear-delay for wave 6 is set; tick it to fire boss_fight.
	for _step in range(5):
		_wm._process(0.5)
	assert_eq(fired.size(), 1,
		"boss_fight_started should fire exactly once after wave 6 clears")


# --- State machine integrity ------------------------------------------

func test_state_name_helper_covers_all_enum_values() -> void:
	# The state server reads state_name as a string; guard against
	# accidentally removing a case from _state_name().
	for s in [_wm.State.IDLE, _wm.State.SPAWNING, _wm.State.IN_PROGRESS,
			_wm.State.CLEAR_DELAY, _wm.State.BOSS_FIGHT, _wm.State.COMPLETE]:
		var nm: String = _wm._state_name(int(s))
		assert_ne(nm, "unknown",
			"_state_name should map every State value to a real name")


func test_get_state_includes_wave_fields() -> void:
	_wm.start_game()
	var state: Dictionary = _wm.get_state()
	var expected_keys: Array = [
		"current_wave", "state", "state_name", "alive_count",
		"is_wave_clear", "banner_remaining",
	]
	for k: String in expected_keys:
		assert_has(state, k, "get_state() should include key: %s" % k)
	assert_eq(int(state["current_wave"]), 1, "current_wave should be 1 after start_game")
	assert_eq(int(state["state"]), _wm.State.IN_PROGRESS,
		"state should be IN_PROGRESS after spawning")
	assert_eq(str(state["state_name"]), "in_progress",
		"state_name should be 'in_progress' after spawning")


# --- Spawned enemies are alive under Main ------------------------------

func test_spawned_enemies_belong_to_main_enemy_count() -> void:
	_wm.start_game()
	# Wave 1 spawns 5 drones; main's enemy counter should reflect that.
	assert_eq(_main.get_enemy_count(), _wm.get_alive_count(),
		"Main and wave manager should track the same live count")


func test_spawned_enemies_have_applied_speed_modifier() -> void:
	# Wave 1 baseline speed_mult = 1.0, so enemies should be at their
	# base move_speed. (Wave 3+ would mutate them; not testing that here.)
	_wm.start_game()
	for e: Node in _wm._alive_spawned:
		if not is_instance_valid(e):
			continue
		if "enemy_type_name" in e and str(e.enemy_type_name) == "drone":
			assert_almost_eq(float(e.move_speed), 140.0, 0.001,
				"Wave 1 drone should keep its base move_speed (mult 1.0)")
			break


# --- Idempotency: re-calling start_game resets the manager --------------

func test_start_game_resets_state() -> void:
	_wm.start_game()
	_kill_all_alive()
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Now we're in CLEAR_DELAY for wave 1.
	_wm.start_game()  # reset
	assert_eq(_wm.current_wave, 1, "start_game should reset current_wave to 1")
	assert_eq(_wm.state, _wm.State.IN_PROGRESS,
		"start_game should land in IN_PROGRESS for the freshly-spawned wave 1")
