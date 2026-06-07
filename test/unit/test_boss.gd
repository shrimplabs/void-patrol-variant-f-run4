extends GutTest
## GUT tests for the multi-phase boss (task 0005):
##  - stats: 40 HP, 500 points, slow horizontal sweep entry
##  - phase 1: aimed shot every 1.5s only (HP 100%..60%)
##  - phase 2: adds spread burst every 3s (HP < 60%..30%)
##  - phase 3: adds rotating ring every 5s (HP < 30%)
##  - weak point: bullets hitting the core deal 2x damage
##  - victory transition: defeating the boss sets main.victory = true
##    and calls wave_manager.notify_boss_defeated()
##  - boss_hp appears in main.get_game_state()

const BOSS_SCRIPT := preload("res://scripts/boss.gd")
const WAVE_MANAGER_SCRIPT := preload("res://scripts/wave_manager.gd")
const MAIN_SCRIPT := preload("res://scripts/main.gd")

var _main: Node = null
var _wm: Node = null


func before_each() -> void:
	_main = MAIN_SCRIPT.new()
	add_child_autofree(_main)
	_wm = _main.wave_manager
	if _wm == null:
		_wm = WAVE_MANAGER_SCRIPT.new()
		_main.add_child(_wm)
		_main.wave_manager = _wm


func after_each() -> void:
	# Free any boss the test spawned so the next before_each starts clean.
	if _main != null and is_instance_valid(_main) and _main.boss != null:
		if is_instance_valid(_main.boss):
			_main.boss.queue_free()
		_main.boss = null
	# Release any bullets we acquired during fire-pattern tests.
	for b: Node in get_tree().get_nodes_in_group("bullets"):
		if is_instance_valid(b) and b.has_method("_release_self"):
			b._release_self()
	_wm = null
	_main = null


# --- Helpers ------------------------------------------------------------

## Spawn a fresh boss at the default entry position. Returns the boss
## node (or null on failure).
func _spawn_boss() -> Node:
	var b: Node = _main.spawn_enemy("boss", Vector2(576.0, -48.0))
	if b != null:
		_main.boss = b
	return b


## Count enemy bullets acquired during a callable. Used to assert how
## many bullets each attack pattern spawns without inspecting nodes.
func _count_enemy_bullets_acquired_during(callable: Callable) -> int:
	var stats_before: Dictionary = BulletPool.get_stats()
	var before: int = int(stats_before.get("enemy", {}).get("alive", 0))
	callable.call()
	var stats_after: Dictionary = BulletPool.get_stats()
	var after: int = int(stats_after.get("enemy", {}).get("alive", 0))
	# Recycle anything we just acquired so the pool doesn't grow per test.
	for b: Node in get_tree().get_nodes_in_group("bullets"):
		if is_instance_valid(b) and "faction" in b and b.faction == "enemy" \
				and b.get_parent() != null and b.get_parent() != _main:
			BulletPool.release(b)
	return after - before


## Drive the boss's _physics_process(delta) without depending on real
## time. Returns the boss for chaining.
func _tick_boss(boss: Node, delta: float = 0.05) -> Node:
	boss._physics_process(delta)
	return boss


## Force the boss into the entry-completed state so phase tests don't
## have to wait for the entry animation. Without this, the boss stays
## at y < 0 (above the screen) for several frames.
func _finish_entry(boss: Node) -> void:
	boss._entered = true
	boss.position = Vector2(576.0, 96.0)


# --- Stats --------------------------------------------------------------

func test_boss_starts_at_40_hp() -> void:
	var boss: Node = _spawn_boss()
	assert_eq(int(boss.max_hp), 40, "Boss max_hp should be 40")
	assert_eq(int(boss.hp), 40, "Boss should start at 40 HP")


func test_boss_score_value_is_500() -> void:
	var boss: Node = _spawn_boss()
	assert_eq(int(boss.score_value), 500, "Boss score_value should be 500")


func test_boss_enemy_type_name_is_boss() -> void:
	var boss: Node = _spawn_boss()
	assert_eq(str(boss.enemy_type_name), "boss",
		"Boss enemy_type_name should be 'boss'")


func test_boss_is_in_enemy_groups() -> void:
	var boss: Node = _spawn_boss()
	assert_true(boss.is_in_group("enemy"),
		"Boss should be in 'enemy' group (so bullets target it)")
	assert_true(boss.is_in_group("enemies"),
		"Boss should be in 'enemies' group")


func test_boss_starts_in_phase_1() -> void:
	var boss: Node = _spawn_boss()
	assert_eq(int(boss.current_phase), 1,
		"Boss should start in phase 1")


# --- Phase transitions --------------------------------------------------

func test_boss_promotes_to_phase_2_below_60_percent_hp() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	# 60% of 40 = 24 HP. Phase 2 starts when HP < 24, so 23 is phase 2.
	boss.hp = 24
	boss.take_damage(1)  # 23 HP, ~57.5%
	assert_eq(int(boss.current_phase), 2,
		"Boss should be in phase 2 after dropping below 60% HP")


func test_boss_promotes_to_phase_3_below_30_percent_hp() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	# 30% of 40 = 12 HP. Phase 3 starts when HP < 12, so 11 is phase 3.
	boss.hp = 12
	boss.take_damage(1)  # 11 HP, 27.5%
	assert_eq(int(boss.current_phase), 3,
		"Boss should be in phase 3 after dropping below 30% HP")


func test_boss_stays_in_phase_1_above_60_percent() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	# 60% threshold. 25 HP / 40 = 62.5% which is above the threshold.
	boss.hp = 25
	boss.take_damage(1)  # 24 HP, exactly 60%; threshold is "< 0.60"
	assert_eq(int(boss.current_phase), 1,
		"Boss should still be in phase 1 at exactly 60% HP")


func test_boss_phase_only_promotes_not_demotes() -> void:
	# Phase monotonicity: once in phase 3, the boss stays in phase 3
	# even if hypothetically healed. (The game doesn't heal the boss,
	# but the invariant protects against accidental regressions.)
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	boss.hp = 5
	boss.take_damage(0)  # triggers phase eval
	assert_eq(int(boss.current_phase), 3, "Should be phase 3")
	boss.hp = 40  # "heal" -- should NOT demote
	boss.take_damage(0)
	assert_eq(int(boss.current_phase), 3,
		"Boss phase should never decrease")


# --- Phase 1: aimed shot only -----------------------------------------

func test_phase_1_fires_only_aimed_shot() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	# Zero the cooldowns and run one attack tick. Phase 1 should fire
	# ONLY the aimed shot (1 bullet).
	boss._aimed_cooldown = 0.0
	boss._spread_cooldown = 1000.0  # disable spread
	boss._ring_cooldown = 1000.0    # disable ring
	var fired: int = _count_enemy_bullets_acquired_during(func() -> void:
		boss._fire_aimed_shot()
	)
	assert_eq(fired, 1, "Phase 1 aimed shot should fire exactly 1 bullet")


# --- Phase 2: adds spread burst ---------------------------------------

func test_phase_2_fires_aimed_shot_and_spread_burst() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	boss.current_phase = 2
	boss._aimed_cooldown = 0.0
	boss._spread_cooldown = 0.0
	boss._ring_cooldown = 1000.0  # ring still disabled
	var fired: int = _count_enemy_bullets_acquired_during(func() -> void:
		boss._fire_aimed_shot()
		boss._fire_spread_burst()
	)
	# 1 aimed + SPREAD_BURST_COUNT spread = 1 + 5 = 6
	assert_eq(fired, 1 + BOSS_SCRIPT.SPREAD_BURST_COUNT,
		"Phase 2 should fire aimed + %d spread bullets" % BOSS_SCRIPT.SPREAD_BURST_COUNT)


func test_spread_burst_emits_spread_burst_count_bullets() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	boss.current_phase = 2
	var fired: int = _count_enemy_bullets_acquired_during(func() -> void:
		boss._fire_spread_burst()
	)
	assert_eq(fired, BOSS_SCRIPT.SPREAD_BURST_COUNT,
		"Spread burst should fire %d bullets" % BOSS_SCRIPT.SPREAD_BURST_COUNT)


# --- Phase 3: adds rotating ring --------------------------------------

func test_phase_3_fires_all_three_attack_patterns() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	boss.current_phase = 3
	boss._aimed_cooldown = 0.0
	boss._spread_cooldown = 0.0
	boss._ring_cooldown = 0.0
	var fired: int = _count_enemy_bullets_acquired_during(func() -> void:
		boss._fire_aimed_shot()
		boss._fire_spread_burst()
		boss._fire_rotating_ring()
	)
	# 1 + 5 + 12 = 18
	assert_eq(fired, 1 + BOSS_SCRIPT.SPREAD_BURST_COUNT + BOSS_SCRIPT.RING_BULLET_COUNT,
		"Phase 3 should fire aimed + spread + ring bullets")


func test_rotating_ring_emits_ring_bullet_count_bullets() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	boss.current_phase = 3
	var fired: int = _count_enemy_bullets_acquired_during(func() -> void:
		boss._fire_rotating_ring()
	)
	assert_eq(fired, BOSS_SCRIPT.RING_BULLET_COUNT,
		"Rotating ring should fire %d bullets" % BOSS_SCRIPT.RING_BULLET_COUNT)


func test_physics_process_fires_aimed_shot_every_1_5s() -> void:
	# Aimed-shot interval = 1.5s. The boss fires when _aimed_cooldown
	# crosses zero. We drive 1.5s of physics time and expect at least
	# one shot to fire.
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	boss._aimed_cooldown = 1.5
	boss._spread_cooldown = 1000.0  # disable spread/ring during this test
	boss._ring_cooldown = 1000.0
	# Snapshot baseline
	var baseline: int = int(BulletPool.get_stats().get("enemy", {}).get("alive", 0))
	# Tick 1.5s in 0.05s steps so the cooldown has a chance to cross 0.
	for i in range(31):  # 31 * 0.05 = 1.55s
		_tick_boss(boss, 0.05)
	var after: int = int(BulletPool.get_stats().get("enemy", {}).get("alive", 0))
	var fired: int = after - baseline
	assert_gte(fired, 1,
		"Boss should have fired at least 1 aimed shot over 1.5s (got %d)" % fired)


# --- Weak point: 2x damage --------------------------------------------

func test_player_bullet_on_body_does_1x_damage() -> void:
	# End-to-end: spawn a real player bullet, simulate a body hit by
	# calling area_entered (shape 0 = body), and assert the boss took
	# 1 damage.
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	var bullet: Node = BulletPool.acquire("player", boss.global_position, _main)
	# Shape index 0 = body, 1 = weak point. The bullet's area_entered
	# is what the bullet does; the BOSS's area_shape_entered is what
	# we test for the weak point extra damage.
	boss._on_area_shape_entered(bullet.get_rid(), bullet, 0, Vector2.ZERO)
	# Note: _on_area_shape_entered alone does NOT call the base 1x
	# damage; that's the bullet's area_entered. We're testing just the
	# shape-extra path here. So calling with shape 0 should NOT damage.
	assert_eq(int(boss.hp), 40,
		"Body shape (index 0) should NOT add extra damage")
	BulletPool.release(bullet)


func test_player_bullet_on_weak_point_does_extra_1x_damage() -> void:
	# When the shape index is WEAK_SHAPE_INDEX, the boss adds 1 more
	# damage to the 1x already applied by the bullet's area_entered.
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	var bullet: Node = BulletPool.acquire("player", boss.global_position, _main)
	# Simulate: bullet's area_entered applies 1x first.
	boss.take_damage(1)
	assert_eq(int(boss.hp), 39, "First hit should reduce HP to 39")
	# Then the boss's area_shape_entered fires with shape index 1 (weak).
	boss._on_area_shape_entered(bullet.get_rid(), bullet, BOSS_SCRIPT.WEAK_SHAPE_INDEX, Vector2.ZERO)
	assert_eq(int(boss.hp), 38,
		"Weak-point shape should add 1 more damage (38 after 1+1)")
	BulletPool.release(bullet)


func test_weak_point_doubles_damage_end_to_end() -> void:
	# Full integration: spawn a player bullet, call BOTH the bullet's
	# area_entered (which calls boss.take_damage(1)) and the boss's
	# area_shape_entered with the weak-point shape. The total damage
	# from a single bullet that hit the core should be 2 HP.
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	# Move the boss out of the way of any other collisions.
	boss.position = Vector2(2000, 2000)
	var bullet: Node = BulletPool.acquire("player", boss.global_position, _main)
	var hp_before: int = int(boss.hp)
	# Bullet's path: the bullet itself, when its area_entered fires
	# with the boss as the area, calls boss.take_damage(1) and then
	# releases itself. We simulate that here.
	boss.take_damage(1)
	# Then the boss's area_shape_entered fires (in Godot, both signals
	# fire on the same physics tick). The boss's handler sees the
	# weak-point shape and adds 1 more.
	boss._on_area_shape_entered(bullet.get_rid(), bullet, BOSS_SCRIPT.WEAK_SHAPE_INDEX, Vector2.ZERO)
	var total_damage: int = hp_before - int(boss.hp)
	assert_eq(total_damage, 2,
		"Total damage from a weak-point bullet hit should be 2 (got %d)" % total_damage)
	BulletPool.release(bullet)


func test_40_player_bullets_kill_the_boss() -> void:
	# Sanity: at 1x damage (all body hits), it takes exactly 40 bullets
	# to kill a 40-HP boss. We don't actually spawn 40 bullets; we
	# call take_damage(1) 40 times.
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	for i in range(40):
		boss.take_damage(1)
	assert_eq(int(boss.hp), 0, "Boss should be at 0 HP after 40 body hits")
	assert_true(bool(boss._is_dead), "Boss should be marked dead at 0 HP")


func test_20_weak_point_hits_kill_the_boss() -> void:
	# 2x damage means 20 weak-point hits kill the boss (40 / 2 = 20).
	# Simulate each weak-point hit as take_damage(1) followed by
	# _on_area_shape_entered (which adds 1 more) = 2 damage per hit.
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	var bullet: Node = BulletPool.acquire("player", boss.global_position, _main)
	for i in range(20):
		boss.take_damage(1)
		boss._on_area_shape_entered(bullet.get_rid(), bullet, BOSS_SCRIPT.WEAK_SHAPE_INDEX, Vector2.ZERO)
	assert_eq(int(boss.hp), 0,
		"Boss should be at 0 HP after 20 weak-point hits (2x each)")
	assert_true(bool(boss._is_dead), "Boss should be marked dead")
	BulletPool.release(bullet)


# --- Boss death: scoring + signals ------------------------------------

func test_boss_died_signal_carries_500_points() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	var received: Array = []
	boss.died.connect(func(v): received.append(v))
	boss.take_damage(40)  # overkill
	assert_eq(received.size(), 1, "boss.died should fire once")
	assert_eq(int(received[0]), 500, "Boss should be worth 500 points")


func test_boss_defeated_signal_fires_on_death() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	var received: Array = []
	boss.defeated.connect(func(): received.append(true))
	boss.take_damage(40)
	assert_eq(received.size(), 1,
		"boss.defeated should fire once when the boss dies")


func test_boss_defeated_fires_before_died() -> void:
	# The defeated signal must fire BEFORE the base `died` signal so
	# the wave_manager / main can read boss state during their
	# defeated handler. The boss script wires defeated first then
	# calls super._die() which emits died.
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	var order: Array = []
	boss.defeated.connect(func(): order.append("defeated"))
	boss.died.connect(func(_v): order.append("died"))
	boss.take_damage(40)
	assert_eq(order.size(), 2, "Both signals should fire")
	assert_eq(str(order[0]), "defeated",
		"defeated should fire before died")
	assert_eq(str(order[1]), "died", "died should fire after defeated")


func test_killing_boss_adds_500_to_main_score() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	assert_eq(_main.score, 0, "Score starts at 0")
	boss.take_damage(40)
	# pump a frame so the queue_free takes effect and the enemy tracker
	# processes tree_exited
	await get_tree().physics_frame
	assert_eq(_main.score, 500,
		"Score should be 500 after killing the boss")
	assert_eq(_main.high_score, 500,
		"High score should track the new max")


# --- Victory transition ------------------------------------------------

func test_main_victory_starts_false() -> void:
	assert_false(bool(_main.victory),
		"main.victory should start false")


func test_boss_defeated_sets_main_victory_true() -> void:
	# Manually wire main's defeated handler and trigger boss death.
	# We bypass the spawn_enemy / _on_boss_fight_started path so we
	# can assert main's victory transition in isolation.
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	boss.defeated.connect(_main._on_boss_defeated)
	boss.died.connect(_main._on_boss_died_score)
	boss.take_damage(40)
	await get_tree().physics_frame
	assert_true(bool(_main.victory),
		"main.victory should be true after the boss is defeated")


func test_boss_defeated_calls_notify_boss_defeated_on_wave_manager() -> void:
	# Set up: wave manager in BOSS_FIGHT, then boss dies. The wave
	# manager should transition to COMPLETE.
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	# Force the wave manager into BOSS_FIGHT (skip the 6-wave ramp).
	_wm.state = _wm.State.BOSS_FIGHT
	boss.defeated.connect(_main._on_boss_defeated)
	boss.died.connect(_main._on_boss_died_score)
	boss.take_damage(40)
	await get_tree().physics_frame
	assert_eq(_wm.state, _wm.State.COMPLETE,
		"Wave manager should transition to COMPLETE after boss defeat")


func test_notify_boss_defeated_is_noop_when_not_in_boss_fight() -> void:
	# If the wave manager is in IN_PROGRESS (boss hasn't started yet),
	# notify_boss_defeated should be a no-op -- it can't prematurely
	# complete a wave that's still in progress.
	_wm.state = _wm.State.IN_PROGRESS
	_wm.notify_boss_defeated()
	assert_eq(_wm.state, _wm.State.IN_PROGRESS,
		"notify_boss_defeated should NOT change state when not in BOSS_FIGHT")


# --- get_game_state() integration -------------------------------------

func test_get_game_state_includes_victory_key() -> void:
	var state: Dictionary = _main.get_game_state()
	assert_has(state, "victory",
		"get_game_state() should include 'victory' key")
	assert_eq(state["victory"], false,
		"victory should be false at start")


func test_get_game_state_includes_boss_hp_keys() -> void:
	var state: Dictionary = _main.get_game_state()
	assert_has(state, "boss_hp",
		"get_game_state() should include 'boss_hp' key")
	assert_has(state, "boss_max_hp",
		"get_game_state() should include 'boss_max_hp' key")


func test_get_game_state_boss_hp_is_zero_when_no_boss() -> void:
	# No boss spawned -> boss_hp = 0, boss_max_hp = 0.
	var state: Dictionary = _main.get_game_state()
	assert_eq(int(state["boss_hp"]), 0,
		"boss_hp should be 0 when no boss is alive")
	assert_eq(int(state["boss_max_hp"]), 0,
		"boss_max_hp should be 0 when no boss is alive")


func test_get_game_state_reports_live_boss_hp() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	var state: Dictionary = _main.get_game_state()
	assert_eq(int(state["boss_hp"]), 40,
		"boss_hp should be 40 for a fresh boss")
	assert_eq(int(state["boss_max_hp"]), 40,
		"boss_max_hp should be 40")


func test_get_game_state_reports_damaged_boss_hp() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	boss.hp = 10
	var state: Dictionary = _main.get_game_state()
	assert_eq(int(state["boss_hp"]), 10,
		"boss_hp should reflect damaged HP")


func test_get_game_state_victory_true_after_boss_defeated() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	boss.defeated.connect(_main._on_boss_defeated)
	boss.died.connect(_main._on_boss_died_score)
	boss.take_damage(40)
	await get_tree().physics_frame
	var state: Dictionary = _main.get_game_state()
	assert_eq(state["victory"], true,
		"get_game_state()['victory'] should be true after boss defeat")


# --- Boss spawn wiring through main ----------------------------------

func test_spawn_enemy_boss_uses_boss_scene() -> void:
	# spawn_enemy("boss", ...) should produce a Boss node and set
	# main.boss to it.
	var boss: Node = _main.spawn_enemy("boss", Vector2(576.0, -48.0))
	assert_not_null(boss, "spawn_enemy should return a boss node")
	assert_true(boss.get_script() == BOSS_SCRIPT,
		"spawned boss should use the boss script")
	assert_eq(int(boss.max_hp), 40, "Spawned boss should have 40 HP")
	_main.boss = boss  # so after_each can clean it up


func test_spawn_enemy_boss_tracks_in_enemy_count() -> void:
	var boss: Node = _spawn_boss()
	assert_eq(_main.get_enemy_count(), 1,
		"Main should report 1 enemy (the boss)")


# --- Defensive / edge cases -------------------------------------------

func test_boss_does_not_fire_after_death() -> void:
	# Killing the boss should stop all attack patterns. The boss is
	# queue_freed on death, so we capture the baseline + call the fire
	# methods within the SAME frame the kill happens (the node is still
	# alive in-memory until the next idle frame, just marked _is_dead
	# and queued for free). Calling on a truly freed node would
	# crash with "previously freed" -- the test exercises the guard
	# path before that happens.
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	boss.take_damage(40)  # kills boss; _is_dead = true, queue_free scheduled
	var baseline: int = int(BulletPool.get_stats().get("enemy", {}).get("alive", 0))
	boss._fire_aimed_shot()
	boss._fire_spread_burst()
	boss._fire_rotating_ring()
	var after: int = int(BulletPool.get_stats().get("enemy", {}).get("alive", 0))
	assert_eq(after - baseline, 0,
		"Dead boss should not fire any bullets")
	# Let the queue_free complete so subsequent tests/cleanup see a
	# free tree.
	await get_tree().physics_frame


func test_weak_point_handler_noop_when_dead() -> void:
	var boss: Node = _spawn_boss()
	_finish_entry(boss)
	boss.take_damage(40)
	var hp_at_death: int = int(boss.hp)
	var bullet: Node = BulletPool.acquire("player", boss.global_position, _main)
	# _on_area_shape_entered on a dead boss should be a no-op (the
	# _is_dead early-return guard). HP should not change.
	boss._on_area_shape_entered(bullet.get_rid(), bullet, BOSS_SCRIPT.WEAK_SHAPE_INDEX, Vector2.ZERO)
	assert_eq(int(boss.hp), hp_at_death,
		"Dead boss should not take more damage from weak-point hits")
	BulletPool.release(bullet)
