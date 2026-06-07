extends Node
## Main scene controller. Owns game-wide state (score, wave) and wires the
## Player + HUD together. `get_game_state()` returns the full state dictionary
## used by the StateServer / QA harness / tests.
##
## Enemy spawning: `spawn_enemy(type, position)` instantiates one of the
## drone/fighter/bomber .tscn files under Main, wires its `died` signal to
## `_on_enemy_died` for scoring, and tracks it in `_enemies` so the StateServer
## can report live enemy state. The wave manager (task 0004) builds on this
## API to clear waves and free enemies when an area is cleared.
##
## Game flow (task 0007): the start menu, game over screen, and victory
## screen live as overlay children (see main.tscn). The session state
## machine is in `_game_state`; transitions are driven by menu input
## (start_pressed), player death, and boss defeat.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const HUD_SCENE := preload("res://scenes/hud.tscn")
const POWERUP_SCENE := preload("res://scenes/powerup.tscn")
const ENEMY_SCENES := {
	"drone": "res://scenes/enemy_drone.tscn",
	"fighter": "res://scenes/enemy_fighter.tscn",
	"bomber": "res://scenes/enemy_bomber.tscn",
	"boss": "res://scenes/boss.tscn",
}
## Score bonus awarded when the player completes a wave. Spec:
## +100 * wave_number on every wave clear.
const WAVE_CLEAR_BONUS_PER_WAVE := 100
## Score bonus awarded when the player completes a wave with full
## shield remaining (no-hit). Spec: +200 flat on a no-hit clear.
const NO_HIT_BONUS := 200
## Score bonus awarded on boss kill. Spec: +500 on boss kill. The
## boss's `score_value` (500) is already added via the normal
## `_on_enemy_died` path, so this constant is informational only
## (kept here for documentation / future use).
const BOSS_KILL_BONUS := 500

var score: int = 0
var wave: int = 1
var high_score: int = 0
var bombs: int = 0
var game_over: bool = false
## True after the player defeats the boss (task 0005). Distinct from
## `game_over` (player death); both can technically be true if the
## boss's final attack kills the player, but victory is the headline
## flag for the StateServer / HUD victory banner.
var victory: bool = false
## Live reference to the currently-spawned boss, or null if no boss is
## active. Used by `get_game_state()` to report `boss_hp`.
var boss: Node = null

var player: Node = null
var hud: CanvasLayer = null
## Procedural wave manager (task 0004). Spawned as a child in _ready
## but does NOT auto-start (task 0007 owns the boot sequence: the
## menu -> playing transition calls `wave_manager.start_game()`).
var wave_manager: Node = null
## Game-flow overlay children (task 0007). All three are siblings
## under Main, all are CanvasLayers with their own scripts. They
## start visible/hidden per their .tscn defaults (menu visible,
## game-over and victory hidden) and main.gd flips them as the
## session state machine transitions.
var menu_overlay: CanvasLayer = null
var game_over_overlay: CanvasLayer = null
var victory_overlay: CanvasLayer = null
## Session-level state machine. Owns the score / high-score / loop
## difficulty bookkeeping. Decoupled from main.gd so tests can poke
## it directly.
var _game_state: GameState = null
## Live enemies currently parented under Main. We track by node reference and
## prune on `tree_exited` so the StateServer list never includes freed nodes.
var _enemies: Array = []
## Cache of the most recently killed enemy's type and position, used by
## `_on_enemy_died` to know which drop chance to roll. Set by
## `_track_enemy`'s death-time snapshot, consumed by the next `died`
## signal. Empty string = no recent kill (signal already consumed).
var _last_died_enemy_type: String = ""
var _last_died_enemy_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_spawn_player()
	_spawn_hud()
	_spawn_wave_manager()
	_resolve_overlays()
	_wire_signals()
	_wire_wave_signals()
	_wire_overlay_signals()
	# Boot the session in the MENU state. We no longer auto-start the
	# wave sequence here -- task 0007 introduces a start menu that
	# drives the menu -> playing transition. GUT tests that want to
	# drive the wave sequence call `wave_manager.start_game()` (or
	# `_begin_session()`) directly on their Main instance; that path
	# is unaffected by this change.
	_initialize_session_state()


## Resolve the menu / game-over / victory overlay children by name.
## All three are siblings under Main in main.tscn. We tolerate any of
## them being absent (a stripped-down test fixture might omit the
## overlays) so a missing node doesn't break the rest of the wiring.
func _resolve_overlays() -> void:
	menu_overlay = get_node_or_null("MenuOverlay")
	game_over_overlay = get_node_or_null("GameOverOverlay")
	victory_overlay = get_node_or_null("VictoryOverlay")


## Build the GameState (loads high score / difficulty from disk) and
## seed the HUD with the loaded values. The session starts in the
## MENU state; the player must press Start to transition to PLAYING.
func _initialize_session_state() -> void:
	_game_state = GameState.new()
	# Seed the HUD with the persisted values so a returning player
	# sees their high score before the menu even shows (this also
	# catches a case where the overlays' labels would otherwise show
	# "HIGH  SCORE  0" briefly).
	if _game_state.high_score > 0 and hud != null and hud.has_method("set_score"):
		hud.set_score(_game_state.high_score)
	# Set the session state to MENU and show the menu. We always start
	# at MENU -- even on the first run -- so the player explicitly
	# begins each session (no surprises for a player who just wanted
	# to see the title screen).
	_game_state.set_state(GameState.SessionState.MENU)
	_show_menu_overlay()


## Wire the three overlay signals back to the corresponding
## transitions. Mirrors `_wire_wave_signals` in shape.
func _wire_overlay_signals() -> void:
	if menu_overlay != null and menu_overlay.has_signal("start_pressed"):
		menu_overlay.start_pressed.connect(_on_menu_start_pressed)
	if game_over_overlay != null and game_over_overlay.has_signal("restart_pressed"):
		game_over_overlay.restart_pressed.connect(_on_game_over_restart_pressed)
	if victory_overlay != null and victory_overlay.has_signal("continue_pressed"):
		victory_overlay.continue_pressed.connect(_on_victory_continue_pressed)


# ---------------------------------------------------------------------
# Game-flow overlay helpers (task 0007)
# ---------------------------------------------------------------------

## Show the start menu and hide the two end-of-run overlays. Called
## on boot and when the player returns to the menu from the victory
## screen.
func _show_menu_overlay() -> void:
	if menu_overlay != null and menu_overlay.has_method("show_menu"):
		# Push the persisted high score / difficulty into the labels so
		# the menu's first frame already shows the right values (vs.
		# flashing "0" before _game_state catches up).
		if menu_overlay.has_method("set_high_score") and _game_state != null:
			menu_overlay.set_high_score(_game_state.high_score)
		if menu_overlay.has_method("set_difficulty") and _game_state != null:
			menu_overlay.set_difficulty(_game_state.difficulty)
		menu_overlay.show_menu()
	if game_over_overlay != null and game_over_overlay.has_method("hide_overlay"):
		game_over_overlay.hide_overlay()
	if victory_overlay != null and victory_overlay.has_method("hide_overlay"):
		victory_overlay.hide_overlay()


## Hide the menu and begin a fresh session (reset score, clear
## enemies, start wave 1). Idempotent in the sense that calling it
## twice in a row leaves the game in the same state, but the second
## call is wasteful (an extra wave_manager reset). Callers should
## gate on `state == MENU` or `state == GAME_OVER` to avoid that.
func _hide_menu_overlay() -> void:
	if menu_overlay != null and menu_overlay.has_method("hide_menu"):
		menu_overlay.hide_menu()


## Show the game-over screen with the just-finished run's score and
## the high score (highlighting "NEW  HIGH  SCORE!" if the run set a
## new record).
func _show_game_over_overlay() -> void:
	if game_over_overlay == null:
		return
	if game_over_overlay.has_method("set_summary") and _game_state != null:
		# "New high score" is true if the just-finished run's final
		# score beat the previous high score (i.e. the in-memory high
		# is exactly the session score, and the session score > 0).
		var is_new_high: bool = (
			_game_state.current_score > 0
			and _game_state.current_score == _game_state.high_score
		)
		game_over_overlay.set_summary(
			_game_state.current_score,
			_game_state.high_score,
			is_new_high,
		)
	if game_over_overlay.has_method("show_overlay"):
		game_over_overlay.show_overlay()


## Show the victory screen with the just-finished run's score and
## the new high score (with the celebratory line if the run set a
## new record).
func _show_victory_overlay() -> void:
	if victory_overlay == null:
		return
	if victory_overlay.has_method("set_summary") and _game_state != null:
		var is_new_high: bool = (
			_game_state.current_score > 0
			and _game_state.current_score == _game_state.high_score
		)
		victory_overlay.set_summary(
			_game_state.current_score,
			_game_state.high_score,
			is_new_high,
		)
	if victory_overlay.has_method("show_overlay"):
		victory_overlay.show_overlay()


## Menu -> Playing transition. Resets the session, hides the menu,
## starts the wave manager. Public so tests can drive a fresh
## session without faking a keypress.
func begin_session() -> void:
	if _game_state == null:
		_initialize_session_state()
	# Reset the session counters (score, wave, game-over / victory
	# flags). The high score and difficulty persist across sessions.
	_game_state.reset_score()
	score = 0
	wave = 1
	game_over = false
	victory = false
	boss = null
	# Push the current difficulty into the wave manager so the next
	# wave's enemies are scaled accordingly. We do this BEFORE
	# start_game() so the wave 1 spawn already uses the difficulty
	# multiplier.
	if wave_manager != null:
		if wave_manager.has_method("set_difficulty"):
			wave_manager.set_difficulty(_game_state.difficulty)
		if wave_manager.has_method("start_game"):
			wave_manager.start_game()
	# Apply the boss-difficulty bump on top of the wave_manager's
	# per-enemy scaling. We don't touch the boss scene here because
	# the boss is spawned lazily on `boss_fight_started`; we record
	# the desired HP multiplier on `_boss_difficulty_hp_mult` and
	# apply it at spawn time. Each difficulty level adds +1 boss HP
	# (4%) to keep the boss loop challenging without being unfair.
	_boss_difficulty_hp_mult = 1.0 + 0.04 * float(_game_state.difficulty)
	_game_state.set_state(GameState.SessionState.PLAYING)
	_hide_menu_overlay()
	# Hide the end-of-run overlays so a player who just lost and
	# restarted sees a clean screen (defensive -- _show_*_overlay
	# also hides the others, but this is explicit).
	if game_over_overlay != null and game_over_overlay.has_method("hide_overlay"):
		game_over_overlay.hide_overlay()
	if victory_overlay != null and victory_overlay.has_method("hide_overlay"):
		victory_overlay.hide_overlay()
	# Reset the player so lives/shield are full and they're at the
	# bottom-center of the viewport. (The player scene's _ready does
	# this on a fresh instance, but the same player node lives
	# across sessions, so we need to call respawn() explicitly.)
	if player != null and player.has_method("respawn"):
		player.respawn()


## HP multiplier applied to a freshly-spawned boss. Computed in
## `begin_session()` from the current loop difficulty. Defaults to
## 1.0 (no change) so existing tests that assert `boss.max_hp == 40`
## continue to pass.
var _boss_difficulty_hp_mult: float = 1.0


## Menu -> Playing handler. Called when the player presses Enter on
## the start menu.
func _on_menu_start_pressed() -> void:
	begin_session()


## Game Over -> Playing handler. Called when the player presses
## Enter on the game-over screen. Same effect as begin_session()
## but the explicit name makes the signal-routing readable.
func _on_game_over_restart_pressed() -> void:
	begin_session()


## Victory -> Menu handler. Called when the player presses Enter on
## the victory screen. Increments the loop difficulty (since they
## completed a full run), then transitions back to MENU so the next
## Start begins a more difficult run.
func _on_victory_continue_pressed() -> void:
	# Increment difficulty on the loop transition. The increment
	# happens BEFORE we show the menu so the menu's "DIFFICULTY  N+1"
	# line is accurate on the very next frame.
	if _game_state != null:
		_game_state.increment_difficulty()
	_game_state.set_state(GameState.SessionState.MENU)
	_show_menu_overlay()


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	add_child(player)


func _spawn_hud() -> void:
	hud = HUD_SCENE.instantiate()
	add_child(hud)


func _spawn_wave_manager() -> void:
	# Instantiate the wave manager script and add it as a child. We don't
	# load a .tscn for it because the manager is a pure-logic node (no
	# visual / collision), and keeping it script-only avoids a one-line
	# scene file we don't need.
	var WaveManagerScript := load("res://scripts/wave_manager.gd")
	if WaveManagerScript == null:
		push_warning("Main._spawn_wave_manager: wave_manager.gd failed to load")
		return
	wave_manager = WaveManagerScript.new()
	wave_manager.name = "WaveManager"
	add_child(wave_manager)


func _wire_signals() -> void:
	if player and player.has_signal("shield_changed"):
		player.shield_changed.connect(_on_player_shield_changed)
	if player and player.has_signal("lives_changed"):
		player.lives_changed.connect(_on_player_lives_changed)
	if player and player.has_signal("died"):
		player.died.connect(_on_player_died)
	if player and player.has_signal("powerup_changed"):
		player.powerup_changed.connect(_on_player_powerup_changed)
		# Initial state broadcast so HUD shows the right baseline (no
		# powerup, no countdown).
		_on_player_powerup_changed(-1, "", 0.0)


## Connect the wave manager's signals to the HUD (banner) and to the
## game's wave counter. Called from _ready after the wave manager is
## spawned so both ends are guaranteed to be in the tree.
func _wire_wave_signals() -> void:
	if wave_manager == null:
		return
	if wave_manager.has_signal("banner_shown"):
		wave_manager.banner_shown.connect(_on_wave_banner)
	if wave_manager.has_signal("wave_started"):
		wave_manager.wave_started.connect(_on_wave_started)
	if wave_manager.has_signal("wave_cleared"):
		wave_manager.wave_cleared.connect(_on_wave_cleared)
	if wave_manager.has_signal("boss_fight_started"):
		wave_manager.boss_fight_started.connect(_on_boss_fight_started)


func _on_wave_banner(text: String, duration: float) -> void:
	if hud and hud.has_method("show_banner"):
		hud.show_banner(text, duration)


func _on_wave_started(wave_number: int) -> void:
	# Update the global wave counter (so the HUD WaveLabel reflects the
	# current wave even if the wave manager state lags by a frame).
	set_wave(wave_number)
	# Reset the no-hit flag for the new wave. We use GameState's
	# `begin_wave` to also capture the wave number, so the no-hit
	# bonus can reference which wave just completed (useful for QA
	# / replay logs).
	if _game_state != null:
		_game_state.begin_wave(wave_number)


func _on_wave_cleared(_wave_number: int) -> void:
	# Game-flow integration point: a cleared wave could refill lives or
	# grant a small score bonus. The full game-flow design lives in
	# task 0007; for now we just leave a checkpoint hook for the harness.
	#
	# Guard the absolute-path lookup with is_inside_tree(): signal
	# callbacks can fire during GUT's free_all teardown, at which point
	# `self` is no longer in the active scene tree and get_node() with
	# absolute paths raises "Can't use get_node() with absolute paths
	# from outside the active scene tree". The harness is a no-op for
	# us when we're tearing down anyway, so silently skip the checkpoint.
	if not is_inside_tree():
		return
	var harness := get_node_or_null("/root/TestHarness")
	if harness != null and harness.has_method("checkpoint"):
		harness.checkpoint({"event": "wave_cleared", "wave": _wave_number_for_harness()})


func _wave_number_for_harness() -> int:
	# Helper so the wave_cleared handler above can capture the wave
	# number without shadowing the function parameter.
	if wave_manager == null:
		return 0
	return int(wave_manager.current_wave)


func _on_boss_fight_started() -> void:
	# Update the global wave counter to 7 (per design doc). The boss
	# itself is task 0005's responsibility; this only updates state.
	set_wave(wave_manager.current_wave if wave_manager else 7)
	# Spawn the boss at the top-center of the arena. The boss script
	# (scripts/boss.gd) handles the entry animation: it starts above
	# the viewport, drifts down to BATTLE_Y, then sweeps horizontally.
	var spawn_x: float = 576.0  # viewport center for the 1152-wide arena
	var spawn_y: float = -48.0  # just above the top of the screen
	var boss_node: Node = spawn_enemy("boss", Vector2(spawn_x, spawn_y))
	if boss_node != null:
		boss = boss_node
		# The wave manager's signal doesn't carry the boss, so we wire
		# `defeated` here for the victory transition and `died` (which
		# carries the score value) for scoring.
		if boss_node.has_signal("defeated"):
			boss_node.defeated.connect(_on_boss_defeated)
		if boss_node.has_signal("died"):
			boss_node.died.connect(_on_boss_died_score)
	if not is_inside_tree():
		return
	var harness := get_node_or_null("/root/TestHarness")
	if harness != null and harness.has_method("checkpoint"):
		harness.checkpoint({"event": "boss_fight_started"})


## Handle the boss's `defeated` signal. Emitted in boss.gd._die()
## BEFORE the base class emits `died` and queue_free's, so we can
## safely read boss state here. Transitions the game to victory and
## notifies the wave manager to advance to COMPLETE.
func _on_boss_defeated() -> void:
	victory = true
	if wave_manager != null and wave_manager.has_method("notify_boss_defeated"):
		wave_manager.notify_boss_defeated()
	# QA checkpoint for the test harness. Guard the absolute-path
	# lookup so a late signal during GUT teardown doesn't ERROR.
	if not is_inside_tree():
		return
	var harness := get_node_or_null("/root/TestHarness")
	if harness != null and harness.has_method("checkpoint"):
		harness.checkpoint({"event": "boss_defeated", "score": score})


## Score the boss's death (separate from `defeated` so the score
## addition happens after the base class's `died` signal which carries
## the score value -- we use add_score() which also updates the HUD
## and high_score). The boss's `died` signal is connected by
## `_track_enemy` too, so it will also go through `_on_enemy_died`
## for the generic add_score path. We don't double-credit because
## `_on_enemy_died` reads from `_last_died_enemy_type` which we set
## in the snapshot; the boss's `enemy_type_name` is "boss" and the
## drop table excludes bosses, so no powerup spawns.
func _on_boss_died_score(score_value: int) -> void:
	# Add the boss's score explicitly; this also flows through the
	# normal add_score() path (updates HUD + high_score).
	add_score(int(score_value))


var _last_shield: float = 0.0

func _on_player_shield_changed(current: float, max_value: float) -> void:
	if hud and hud.has_method("set_shield"):
		hud.set_shield(current, max_value)
	# Only flash when shield drops -- regen shouldn't trigger the damage overlay.
	if current < _last_shield and hud.has_method("flash_damage"):
		hud.flash_damage(_last_shield - current)
		# A drop in shield also disqualifies the current wave from the
		# no-hit bonus. We mark here rather than in the player because
		# that's the single source of truth for "the player took
		# damage" (the player itself doesn't know about wave context).
		# Note: a life-loss / respawn also calls shield_changed with
		# current=0 then current=max, so this also catches that path.
		if _game_state != null:
			_game_state.mark_wave_hit()
	_last_shield = current


func _on_player_lives_changed(current: int, _max_value: int) -> void:
	if hud and hud.has_method("set_lives"):
		hud.set_lives(current)


func _on_player_died() -> void:
	game_over = true
	if score > high_score:
		high_score = score
	# Persist the high score immediately so a player who force-quits
	# right after dying still gets credit for the run. We save AFTER
	# the in-memory update so the write reflects the final score.
	if _game_state != null:
		_game_state.save_high_score_if_higher()
	# Transition the session state and show the game-over overlay.
	# We don't stop the wave manager here -- it will keep ticking
	# the cleared-delay timer, but the wave sequence effectively
	# freezes (no input reaches the player; no new enemies spawn
	# from the player's perspective). The wave_manager is reset on
	# the next begin_session().
	if _game_state != null:
		_game_state.set_state(GameState.SessionState.GAME_OVER)
	_show_game_over_overlay()
	# QA checkpoint for the test harness. Guard the absolute-path
	# lookup so a late signal during GUT teardown doesn't ERROR.
	if not is_inside_tree():
		return
	var harness := get_node_or_null("/root/TestHarness")
	if harness != null and harness.has_method("checkpoint"):
		harness.checkpoint({"event": "player_died", "score": score, "high_score": high_score})


## Add score (e.g. when an enemy is killed). Clamps the new high score.
func add_score(amount: int) -> void:
	score += amount
	if hud and hud.has_method("set_score"):
		hud.set_score(score)
	if score > high_score:
		high_score = score


func set_wave(value: int) -> void:
	wave = value
	if hud and hud.has_method("set_wave"):
		hud.set_wave(wave)


## Spawn an enemy of the given type at the given world position. Returns the
## spawned node (or null if the type is unknown / scene failed to load).
## The enemy is parented to Main so it shares the same physics layer as the
## player. The `died` signal is wired to `_on_enemy_died` for scoring.
func spawn_enemy(enemy_type: String, world_position: Vector2) -> Node:
	var path: String = ENEMY_SCENES.get(enemy_type, "")
	if path == "":
		push_warning("Main.spawn_enemy: unknown enemy type '%s'" % enemy_type)
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		push_warning("Main.spawn_enemy: failed to load scene '%s'" % path)
		return null
	var enemy: Node = packed.instantiate()
	if enemy == null:
		return null
	if enemy is Node2D:
		(enemy as Node2D).global_position = world_position
	add_child(enemy)
	_track_enemy(enemy)
	return enemy


func _track_enemy(enemy: Node) -> void:
	if enemy == null:
		return
	_enemies.append(enemy)
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)
	# Capture the type and position at death-time so _on_enemy_died can
	# roll the drop chance for the right enemy. The `died` signal itself
	# only carries the score value, so we lean on a small helper that
	# snapshots the enemy just before it frees itself.
	if enemy.has_signal("tree_exited"):
		var snapshot := [enemy]
		enemy.tree_exited.connect(func() -> void:
			_snapshot_dead_enemy(snapshot)
		)
	# Auto-prune when the enemy frees itself (death, off-screen, etc.).
	enemy.tree_exited.connect(_on_enemy_exited.bind(enemy))


## Read the most-recently-tracked enemy's type/position into our drop
## cache, but only if it died from `died` (not from off-screen). We use
## the `_is_dead` flag the base enemy sets on death to distinguish.
func _snapshot_dead_enemy(snapshot: Array) -> void:
	if snapshot.is_empty():
		return
	var e: Node = snapshot[0]
	if e == null or not is_instance_valid(e):
		return
	if not bool(e.get("_is_dead")):
		# Off-screen / wave-clear -- no drop.
		return
	var etype: String = ""
	if "enemy_type_name" in e:
		etype = str(e.enemy_type_name)
	if etype == "":
		etype = str(e.name).to_lower()
	_last_died_enemy_type = etype
	if e is Node2D:
		_last_died_enemy_position = (e as Node2D).global_position


func _on_enemy_died(score_value: int) -> void:
	# The score value is the enemy's `score_value` export (drone=10,
	# fighter=25, bomber=50). We add it to the main score; the enemy itself
	# is freed in EnemyBase._die() and pruned from _enemies by
	# _on_enemy_exited when the tree_exited signal fires.
	add_score(int(score_value))
	# The enemy that just died passed its `enemy_type_name` before freeing.
	# We can't read it from the dead signal (it carries only the score), so
	# we have to look at the most-recently-killed enemy. We do that by
	# routing drop attempts through `try_drop_powerup` on each enemy
	# individually (see EnemyBase._die() in extension) -- but for now, we
	# just attempt drops from the enemy that sent the signal. Since the
	# signal payload doesn't carry the type, we use the last known type
	# from the most recent tracking. Tests that need exact drop behavior
	# can call `try_drop_powerup` directly with an explicit type.
	if _last_died_enemy_type != "":
		try_drop_powerup(_last_died_enemy_type, _last_died_enemy_position)
	_last_died_enemy_type = ""


func _on_enemy_exited(enemy: Node) -> void:
	_enemies.erase(enemy)


## Clear all currently-spawned enemies. Used by the wave manager (0004) to
## fast-forward a wave when the player advances. Each enemy is freed via its
## own queue_free so its `died` signal does not fire (no false score).
func clear_enemies() -> void:
	for e: Node in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()


# ---------------------------------------------------------------------
# Power-up plumbing
# ---------------------------------------------------------------------

## Try to spawn a power-up at `world_position` based on a kill by an
## enemy of `enemy_type`. Returns the spawned powerup node, or null if
## the drop roll fails / the enemy type doesn't drop.
##
## Drop chance: ~25% for fighter and bomber kills. Drones never drop.
## `randf()` is used for the roll; tests should call this many times
## (with a seeded RNG) to assert the rate, or call `Powerup.should_drop`
## directly with a deterministic roll value.
func try_drop_powerup(enemy_type: String, world_position: Vector2) -> Node:
	if enemy_type != "fighter" and enemy_type != "bomber":
		return null
	if not Powerup.should_drop(randf()):
		return null
	return spawn_random_powerup(world_position)


## Spawn a power-up of a random kind at the given position. Returns the
## spawned powerup node (or null on failure). Public so tests and the
## future wave manager can pre-place powerups if they want to.
func spawn_random_powerup(world_position: Vector2) -> Node:
	var kinds: Array = Powerup.all_kinds()
	if kinds.is_empty():
		return null
	var kind_value: int = int(kinds[randi() % kinds.size()])
	return spawn_powerup(kind_value, world_position)


## Spawn a power-up of an explicit kind at the given position. Public
## so tests can construct specific scenarios without dealing with the
## RNG. Returns the spawned powerup node (or null on failure).
func spawn_powerup(kind: int, world_position: Vector2) -> Node:
	if POWERUP_SCENE == null:
		push_warning("Main.spawn_powerup: powerup scene failed to load")
		return null
	var p: Node = POWERUP_SCENE.instantiate()
	if p == null:
		return null
	if p is Node2D:
		(p as Node2D).global_position = world_position
	if p.has_method("setup"):
		p.setup(kind)
	add_child(p)
	return p


## Apply a power-up of the given kind. Called by Powerup._on_body_entered
## once the player has walked into a pickup. Routes instant effects
## (BOMB) here at the scene level, and forwards player-state effects
## to the player via its `apply_powerup` method.
##
## `powerup` is the pickup node (kept for future hooks like a
## pickup-celebration effect); currently unused.
func apply_powerup(kind: int, player_node: Node, _powerup: Node = null) -> void:
	if kind == Powerup.Kind.BOMB:
		_bomb_blast(player_node)
		# BOMB has no per-player state to set; the player just sees the
		# blast. Don't call player.apply_powerup (it's a no-op for BOMB).
		return
	if player_node != null and player_node.has_method("apply_powerup"):
		player_node.apply_powerup(kind, _powerup)


## BOMB: clear all live bullets in the scene and damage every enemy by
## 2 HP. Used by both the BOMB pickup and the future HUD bomb button.
## `origin_player` is kept for future damage-source attribution.
func _bomb_blast(_origin_player: Node = null) -> void:
	# 1) Clear all bullets. Use _release_self so the pool's free list
	# grows correctly (no per-blast allocations).
	for b: Node in get_tree().get_nodes_in_group("bullets"):
		if is_instance_valid(b) and b.has_method("_release_self"):
			b._release_self()
	# 2) Damage all enemies by 2. This may trigger `died` on already-
	# weakened enemies, which scores them through the normal path.
	for e: Node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.has_method("take_damage"):
			e.take_damage(2)


## Signal: player reports a power-up state change. Forward to the HUD
## so the active-powerup label can update.
func _on_player_powerup_changed(kind: int, type_name: String, remaining: float) -> void:
	if hud and hud.has_method("set_active_powerup"):
		hud.set_active_powerup(type_name, remaining)
	# QA checkpoint (fire-and-forget). Failure to find the harness is
	# benign: it just means we're not running under the test harness.
	# Guard the absolute-path lookup against late signal callbacks
	# fired during GUT teardown (when `self` is no longer in the
	# active scene tree, get_node() with absolute paths raises).
	if not is_inside_tree():
		return
	var harness := get_node_or_null("/root/TestHarness")
	if harness != null and harness.has_method("checkpoint"):
		harness.checkpoint({"event": "powerup_changed", "kind": kind, "name": type_name, "remaining": remaining})


## Count of currently-live enemies (for the StateServer / wave manager).
func get_enemy_count() -> int:
	# Prune stale entries defensively so the count never includes freed nodes.
	var live: Array = []
	for e: Node in _enemies:
		if is_instance_valid(e):
			live.append(e)
	_enemies = live
	return _enemies.size()


func get_game_state() -> Dictionary:
	var player_state: Dictionary = {}
	if player and player.has_method("get_state"):
		player_state = player.get_state()
	var hud_state: Dictionary = {}
	if hud and hud.has_method("get_state"):
		hud_state = hud.get_state()
	# Build the per-enemy state list. Filter out freed nodes defensively.
	var enemy_states: Array = []
	var counts: Dictionary = {"drone": 0, "fighter": 0, "bomber": 0}
	var live_enemies: Array = []
	for e: Node in _enemies:
		if not is_instance_valid(e):
			continue
		live_enemies.append(e)
		if e.has_method("get_state"):
			enemy_states.append(e.get_state())
		var etype: String = ""
		if "enemy_type_name" in e:
			etype = str(e.enemy_type_name).to_lower()
		if etype == "" or not counts.has(etype):
			etype = str(e.name).to_lower()
		if counts.has(etype):
			counts[etype] = int(counts[etype]) + 1
	_enemies = live_enemies
	# Wave manager snapshot. Optional: the manager may be null in tests
	# that strip the scene tree. We always include the key so the
	# StateServer has a stable shape.
	var wave_state: Dictionary = {}
	if wave_manager and wave_manager.has_method("get_state"):
		wave_state = wave_manager.get_state()
	# Boss HP snapshot. 0 means "no boss alive" (either pre-spawn or
	# post-defeat). The StateServer / HUD use this to render a boss bar
	# during the boss fight; we report it even when 0 so consumers can
	# rely on a stable key shape.
	var boss_hp_value: int = 0
	var boss_max_hp_value: int = 0
	if boss != null and is_instance_valid(boss):
		boss_hp_value = int(boss.hp)
		boss_max_hp_value = int(boss.max_hp)
	return {
		"scene": "Main",
		"score": score,
		"wave": wave,
		"high_score": high_score,
		"bombs": bombs,
		"game_over": game_over,
		"victory": victory,
		"player": player_state,
		"hud": hud_state,
		"enemies": enemy_states,
		"enemy_count": enemy_states.size(),
		"enemy_counts_by_type": counts,
		"wave_manager": wave_state,
		"boss_hp": boss_hp_value,
		"boss_max_hp": boss_max_hp_value,
	}
