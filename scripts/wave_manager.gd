extends Node
class_name WaveManager
## Procedural wave manager for Void Patrol.
##
## Drives the 6-wave ramp described in the design doc. Each wave has a
## fixed config (drone/fighter/bomber counts, speed multiplier, fire-rate
## multiplier) that scales difficulty from wave 1 (drone swarm) to wave 6
## (fighter + bomber mix with 1.3x speed and 0.80x fire rate).
##
## Lifecycle:
##   1. `start_game()` -- begins wave 1.
##   2. `_spawn_wave(config)` -- instantiates enemies via main.spawn_enemy
##      and tracks each one. Shows the "INCOMING WAVE n" banner.
##   3. While state == IN_PROGRESS, the manager polls its alive_spawned
##      list. When it empties, the wave is cleared. A 2s grace timer runs,
##      the "WAVE CLEAR" banner shows, and then `start_next_wave()` is
##      called.
##   4. Un-cleared enemies from prior waves are NOT cleared (intentional
##      overlap per the design doc).
##   5. After wave 6, state transitions to BOSS_FIGHT and `current_wave`
##      is set to 7. The actual boss spawn is owned by task 0005.
##
## Public API:
##   start_game() -> void
##   start_next_wave() -> void
##   get_wave_config(wave: int) -> Dictionary
##   is_wave_clear() -> bool
##
## Signals:
##   wave_started(wave: int)
##   wave_cleared(wave: int)
##   boss_fight_started()
##   banner_shown(text: String, duration: float)

signal wave_started(wave_number: int)
signal wave_cleared(wave_number: int)
signal boss_fight_started()
signal banner_shown(text: String, duration: float)

enum State {
	IDLE,
	SPAWNING,
	IN_PROGRESS,
	CLEAR_DELAY,
	BOSS_FIGHT,
	COMPLETE,
}

const TOTAL_WAVES := 6
## Seconds between the last enemy of a wave dying and the next wave's
## INCOMING banner. Design doc: "2s delay before next wave".
const CLEAR_DELAY_SECONDS := 2.0
## How long the INCOMING / WAVE CLEAR banner is on screen.
const BANNER_DURATION := 1.5
## Default viewport width used to spread spawn positions when the actual
## viewport is degenerate (headless tests, freshly-booted scene tree).
const DEFAULT_VIEWPORT_W := 1152.0

## Per-wave configuration. Indexed by wave number (1-based; index 0 is wave 1).
## Each entry: { drone, fighter, bomber, speed_mult, fire_rate_mult }.
## The ramp progresses from "drone swarm" (wave 1) to "fighter + bomber
## pressure" (wave 6), with the fire-rate multiplier decreasing (faster
## cadence) and the speed multiplier increasing as the game ramps up.
const WAVE_CONFIG: Array = [
	## Wave 1 -- pure drone swarm, baseline speed / cadence.
	{"drone": 5, "fighter": 0, "bomber": 0, "speed_mult": 1.0, "fire_rate_mult": 1.0},
	## Wave 2 -- introduce fighters, more drones.
	{"drone": 5, "fighter": 2, "bomber": 0, "speed_mult": 1.0, "fire_rate_mult": 1.0},
	## Wave 3 -- drone + fighter mix, slight speed bump.
	{"drone": 4, "fighter": 3, "bomber": 0, "speed_mult": 1.10, "fire_rate_mult": 0.95},
	## Wave 4 -- first bomber, fighter-heavy, fire rate picks up.
	{"drone": 3, "fighter": 4, "bomber": 1, "speed_mult": 1.15, "fire_rate_mult": 0.90},
	## Wave 5 -- bomber pressure, mid-tier speed.
	{"drone": 2, "fighter": 4, "bomber": 2, "speed_mult": 1.20, "fire_rate_mult": 0.85},
	## Wave 6 -- boss-prelude mix, peak ramp.
	{"drone": 0, "fighter": 5, "bomber": 3, "speed_mult": 1.30, "fire_rate_mult": 0.80},
]

var current_wave: int = 0
## Public state of the manager. See `State` enum.
var state: int = State.IDLE
## Loop-count difficulty from main.gd. Each level adds a small
## speed / fire-rate bump on top of the per-wave config. Defaults to 0
## (first run) so existing tests that assert exact 1.10x / 1.20x
## multipliers continue to pass.
var difficulty: int = 0
## Enemies spawned by the current wave. Entries are removed on
## `tree_exited`. When the list is empty AND state == IN_PROGRESS, the
## wave is considered cleared.
var _alive_spawned: Array = []
## Pending-queue-free enemies that haven't yet emitted `tree_exited`.
## Used so we don't count an enemy as "alive" after it has been freed
## but its exit signal hasn't propagated this frame.
var _pending_exits: Array = []
## Seconds remaining in the post-clear grace timer.
var _clear_timer: float = 0.0
## Seconds the current banner should remain on screen.
var _banner_remaining: float = 0.0
## Cached reference to the parent Main scene. Resolved on _ready.
var _main: Node = null


func _ready() -> void:
	# Walk up the tree to find Main. The wave manager is parented under
	# Main in main.tscn, but resolving defensively (in case a test
	# instantiates it under a different root) keeps the script flexible.
	var p: Node = get_parent()
	while p != null:
		if p.has_method("spawn_enemy"):
			_main = p
			break
		p = p.get_parent()


func _process(delta: float) -> void:
	# Tick the post-clear grace timer and the banner timer. The
	# in-progress -> cleared transition is detected in `_check_clear()`
	# which we poll every frame; that keeps the logic straightforward
	# (no signal ordering hazards between tree_exited and enemy.died).
	if state == State.CLEAR_DELAY:
		_clear_timer -= delta
		if _clear_timer <= 0.0:
			_clear_timer = 0.0
			start_next_wave()
	if _banner_remaining > 0.0:
		_banner_remaining -= delta
		if _banner_remaining <= 0.0:
			_banner_remaining = 0.0


## Public: kick off the wave sequence. Resets current_wave to 0 and
## starts wave 1. Safe to call once per game session.
func start_game() -> void:
	current_wave = 0
	state = State.IDLE
	_alive_spawned.clear()
	_pending_exits.clear()
	_clear_timer = 0.0
	start_next_wave()


## Public: advance to the next wave. After wave 6, transitions the
## state machine into BOSS_FIGHT and stops spawning.
func start_next_wave() -> void:
	if state == State.BOSS_FIGHT or state == State.COMPLETE:
		return
	if state == State.CLEAR_DELAY:
		# We were already in the post-clear grace; the timer fired.
		# Fall through and spawn the next wave.
		pass
	current_wave += 1
	state = State.SPAWNING
	var config: Dictionary = get_wave_config(current_wave)
	if config.is_empty():
		# Past the last wave -- boss territory.
		_transition_to_boss()
		return
	_spawn_wave(config)
	state = State.IN_PROGRESS
	wave_started.emit(current_wave)
	_show_banner("INCOMING  WAVE %d" % current_wave, BANNER_DURATION)


## Public: per-wave config lookup. Returns an empty dictionary for
## wave numbers outside [1, TOTAL_WAVES].
func get_wave_config(wave: int) -> Dictionary:
	if wave < 1 or wave > TOTAL_WAVES:
		return {}
	return WAVE_CONFIG[wave - 1]


## Public: returns true when no enemies spawned by the current wave are
## still alive. NOTE: un-cleared enemies from a prior wave are NOT
## counted here -- the manager only tracks its own spawns. This is
## intentional (the design doc says un-cleared enemies persist).
func is_wave_clear() -> bool:
	_prune_dead()
	return _alive_spawned.is_empty()


## Public: called by main.gd when the boss has been defeated.
## Transitions the state machine from BOSS_FIGHT to COMPLETE (the
## "victory" terminal state). The wave manager does not spawn or
## track the boss itself -- it only owns the post-boss state
## transition so the game-flow layer (task 0007) can branch on
## `state == State.COMPLETE` to show the victory screen.
##
## No-op if the manager is not currently in BOSS_FIGHT (e.g. the
## caller forgot to wait for the boss_fight_started signal). This
## keeps the state machine's transitions strict and prevents
## double-completion.
func notify_boss_defeated() -> void:
	if state != State.BOSS_FIGHT:
		return
	state = State.COMPLETE


## Public: count of enemies the current wave has spawned that are
## still alive. Useful for HUD / StateServer / QA reporting.
func get_alive_count() -> int:
	_prune_dead()
	return _alive_spawned.size()


## Internal: spawn all enemies for a wave's config. Each enemy is
## spawned via main.spawn_enemy() and tracked in `_alive_spawned`.
## Speed / fire-rate multipliers are applied per-enemy so the ramps
## ramp up the whole fleet consistently.
func _spawn_wave(config: Dictionary) -> void:
	if _main == null:
		push_warning("WaveManager: no Main parent; cannot spawn enemies")
		return
	var viewport_w: float = DEFAULT_VIEWPORT_W
	# Resolved via the SceneTree because this manager is a plain Node
	# (not a CanvasItem), so get_viewport_rect() isn't available.
	var tree := get_tree()
	if tree != null and tree.root != null:
		var vp_size: Vector2 = tree.root.size
		if vp_size.x > 0.0:
			viewport_w = vp_size.x
	var speed_mult: float = float(config.get("speed_mult", 1.0))
	var fire_rate_mult: float = float(config.get("fire_rate_mult", 1.0))

	# Spawn each type in sequence. The order doesn't matter gameplay-
	# wise but it makes the per-type counts visually grouped on screen.
	_spawn_type("drone", int(config.get("drone", 0)), viewport_w, speed_mult, fire_rate_mult)
	_spawn_type("fighter", int(config.get("fighter", 0)), viewport_w, speed_mult, fire_rate_mult)
	_spawn_type("bomber", int(config.get("bomber", 0)), viewport_w, speed_mult, fire_rate_mult)


## Spawn `count` enemies of the given `enemy_type`, spread across the
## top of the viewport.
func _spawn_type(enemy_type: String, count: int, viewport_w: float, speed_mult: float, fire_rate_mult: float) -> void:
	if count <= 0 or _main == null:
		return
	for i in range(count):
		var x: float = _spread_x(i, count, viewport_w)
		var spawn_pos := Vector2(x, -30.0)
		var e: Node = _main.spawn_enemy(enemy_type, spawn_pos)
		if e == null:
			continue
		_apply_modifiers(e, speed_mult, fire_rate_mult)
		_track_enemy(e)


## Spread `count` spawn positions evenly across the viewport width.
## Margin of 60px on each side keeps the leftmost / rightmost enemy
## from clipping at the edge.
func _spread_x(index: int, count: int, viewport_w: float) -> float:
	if count <= 1:
		return viewport_w * 0.5
	var usable: float = max(80.0, viewport_w - 120.0)
	var step: float = usable / float(count - 1)
	return 60.0 + step * float(index)


## Apply the wave's speed / fire-rate multipliers to a freshly-spawned
## enemy. Both modifiers are exposed on the enemy base script as
## `move_speed` and `fire_interval`; we mutate those directly. The
## per-manager `difficulty` (loop counter from main.gd) is folded on
## top of the per-wave multipliers: each level adds 5% speed and
## shaves 2% off fire interval (faster cadence).
func _apply_modifiers(enemy: Node, speed_mult: float, fire_rate_mult: float) -> void:
	if enemy == null:
		return
	# Difficulty folding: 1.0 + 0.05 * difficulty for speed, the
	# inverse for fire interval. Difficulty == 0 -> multiplier == 1.0
	# so existing tests that assert exact 1.10x / 1.20x wave configs
	# still pass.
	var diff_speed: float = 1.0 + 0.05 * float(difficulty)
	var diff_fire: float = 1.0
	if difficulty > 0:
		diff_fire = 1.0 - 0.02 * float(difficulty)
	if diff_fire < 0.1:
		diff_fire = 0.1  # floor so the enemy doesn't shoot every frame
	if "move_speed" in enemy:
		enemy.move_speed = float(enemy.move_speed) * speed_mult * diff_speed
	# A lower fire_interval means faster shots; if the wave's
	# fire_rate_mult is < 1.0 we shorten the interval accordingly.
	if fire_rate_mult > 0.0 and "fire_interval" in enemy:
		var base_interval: float = float(enemy.fire_interval)
		if base_interval > 0.0:
			enemy.fire_interval = base_interval * fire_rate_mult * diff_fire


## Public: set the loop-count difficulty. Each level is +5% enemy
## speed and -2% fire interval. Called by main.gd on session start
## (after the menu -> playing transition). Safe to call mid-wave; the
## new value applies to the NEXT wave spawned.
func set_difficulty(value: int) -> void:
	difficulty = max(0, int(value))


## Hook a freshly-spawned enemy into our tracking. We rely on
## `tree_exited` (which fires for both died and off-screen) to
## decrement our alive count. We also stash the enemy in
## `_pending_exits` until the next frame so a queue_freed-in-same-tick
## enemy doesn't accidentally get counted as "still alive" by an
## is_instance_valid race.
func _track_enemy(enemy: Node) -> void:
	if enemy == null:
		return
	_alive_spawned.append(enemy)
	if enemy.has_signal("tree_exited"):
		_pending_exits.append(enemy)
		enemy.tree_exited.connect(_on_enemy_exited.bind(enemy))


func _on_enemy_exited(enemy: Node) -> void:
	_alive_spawned.erase(enemy)
	_pending_exits.erase(enemy)
	# If we were in progress and the wave is now empty, advance to the
	# post-clear grace phase. We do this from a signal callback rather
	# than polling so the transition is immediate.
	if state == State.IN_PROGRESS and is_wave_clear():
		_on_wave_cleared()


## Called when the current wave's spawns are all gone. Triggers the
## post-clear grace timer and the WAVE CLEAR banner.
func _on_wave_cleared() -> void:
	if state != State.IN_PROGRESS:
		return
	var cleared_wave: int = current_wave
	state = State.CLEAR_DELAY
	_clear_timer = CLEAR_DELAY_SECONDS
	wave_cleared.emit(cleared_wave)
	_show_banner("WAVE  %d  CLEAR" % cleared_wave, BANNER_DURATION)


## Transition to the boss-fight phase. Sets current_wave to 7 (per the
## design doc: "After wave 6, state transitions to boss_fight;
## current_wave becomes 7"). The actual boss spawn is task 0005's
## concern -- this method only sets the state and signals.
func _transition_to_boss() -> void:
	state = State.BOSS_FIGHT
	current_wave = TOTAL_WAVES + 1  # 7
	boss_fight_started.emit()
	_show_banner("BOSS  INCOMING", BANNER_DURATION)


## Prune dead / freed enemies from `_alive_spawned` defensively. Also
## drains `_pending_exits` after a single frame so a queue_freed enemy
## isn't double-counted.
func _prune_dead() -> void:
	var live: Array = []
	for e: Node in _alive_spawned:
		if is_instance_valid(e):
			live.append(e)
	_alive_spawned = live
	# Pending exits are kept around so the same-frame queue_free doesn't
	# show up as "alive one tick, dead the next" -- this matters for the
	# test that calls take_damage and expects the count to drop after
	# tree_exited.
	var still_pending: Array = []
	for e: Node in _pending_exits:
		if is_instance_valid(e):
			still_pending.append(e)
	_pending_exits = still_pending


## Show a banner via the `banner_shown` signal. The HUD listens for
## this and renders the text. Decoupling via signal keeps the wave
## manager UI-agnostic (testable without a HUD).
func _show_banner(text: String, duration: float) -> void:
	_banner_remaining = duration
	banner_shown.emit(text, duration)


## Snapshot for the StateServer / tests.
func get_state() -> Dictionary:
	return {
		"current_wave": current_wave,
		"state": state,
		"state_name": _state_name(state),
		"alive_count": get_alive_count(),
		"is_wave_clear": is_wave_clear(),
		"banner_remaining": _banner_remaining,
		"difficulty": difficulty,
	}


## Map the State enum to a human-readable string for the state server.
func _state_name(s: int) -> String:
	match s:
		State.IDLE: return "idle"
		State.SPAWNING: return "spawning"
		State.IN_PROGRESS: return "in_progress"
		State.CLEAR_DELAY: return "clear_delay"
		State.BOSS_FIGHT: return "boss_fight"
		State.COMPLETE: return "complete"
		_: return "unknown"
