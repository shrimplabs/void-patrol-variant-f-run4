extends GutTest
## GUT tests for the power-up system (task 0006):
##  - All 6 kinds and their TYPE_DATA (color / duration / name / shot_type)
##  - Drop chance: deterministic via Powerup.should_drop(); distribution
##    via main.try_drop_powerup() with a seeded RNG (~25% in [20%, 30%]
##    over 200 rolls for a non-flaky seed)
##  - Drone does not drop; fighter and bomber do (try_drop_powerup routing)
##  - Auto-collect on body_entered (player overlaps powerup, effect fires)
##  - Single-active shot-type rule (DOUBLE then TRIPLE, only 1 active)
##  - SPEED_BOOST coexists with shot types
##  - Durations tick down and reset dependent state on expiry
##  - SHIELD_BOOST is instant and bumps shield by +50% of max
##  - BOMB clears all live bullets + deals 2 damage to every enemy
##  - HUD shows the active power-up name + remaining seconds

const POWERUP_SCRIPT := preload("res://scripts/powerup.gd")
const MAIN_SCRIPT := preload("res://scripts/main.gd")
const ENEMY_DRONE := preload("res://scripts/enemy_drone.gd")

var _main: Node = null
var _holder: Node = null
var _acquired_bullets: Array = []


func before_each() -> void:
	# Each test gets a fresh Main so powerup state and player state are
	# isolated. Main spawns Player + HUD in _ready.
	# First, clean up any stray bullets left in the pool by a previous
	# test -- the player auto-fires every 0.3s, and while the bullets
	# are freed when _main queue_frees, the pool's free-list still
	# holds references. Releasing any in-tree bullets here keeps the
	# pool from growing unbounded across the test suite.
	if BulletPool != null:
		var stray := get_tree().get_nodes_in_group("bullets")
		for b: Node in stray:
			if is_instance_valid(b) and b.get_parent() != null:
				BulletPool.release(b)
	_main = MAIN_SCRIPT.new()
	add_child_autofree(_main)
	_holder = Node.new()
	_holder.name = "PowerupTestHolder"
	add_child_autofree(_holder)
	_acquired_bullets = []


func after_each() -> void:
	# Release any pool bullets we created so the pool doesn't grow per test.
	for b in _acquired_bullets:
		if is_instance_valid(b) and BulletPool != null:
			BulletPool.release(b)
	_acquired_bullets.clear()
	_main = null
	_holder = null


# --- Helpers ------------------------------------------------------------

func _acquire_player_bullet(pos: Vector2) -> Node:
	if BulletPool == null:
		return null
	var b: Node = BulletPool.acquire("player", pos, _holder)
	_acquired_bullets.append(b)
	return b


func _acquire_enemy_bullet(pos: Vector2) -> Node:
	if BulletPool == null:
		return null
	var b: Node = BulletPool.acquire("enemy", pos, _holder)
	_acquired_bullets.append(b)
	return b


func _release_stray_bullets() -> void:
	# In case a player auto-fired during the test, clean up so the pool
	# doesn't leak across tests.
	if BulletPool == null:
		return
	var all := get_tree().get_nodes_in_group("bullets")
	for b: Node in all:
		if is_instance_valid(b) and b.get_parent() != null \
				and b.get_parent() != _main \
				and b.get_parent() != _holder:
			BulletPool.release(b)


# --- TYPE_DATA / static helpers ----------------------------------------

func test_all_kinds_returns_six_in_stable_order() -> void:
	var kinds: Array = Powerup.all_kinds()
	assert_eq(kinds.size(), 6, "all_kinds() should return 6 kinds")
	assert_eq(int(kinds[0]), Powerup.Kind.DOUBLE_SHOT,
		"Index 0 should be DOUBLE_SHOT")
	assert_eq(int(kinds[1]), Powerup.Kind.TRIPLE_SPREAD,
		"Index 1 should be TRIPLE_SPREAD")
	assert_eq(int(kinds[2]), Powerup.Kind.LASER,
		"Index 2 should be LASER")
	assert_eq(int(kinds[3]), Powerup.Kind.SHIELD_BOOST,
		"Index 3 should be SHIELD_BOOST")
	assert_eq(int(kinds[4]), Powerup.Kind.SPEED_BOOST,
		"Index 4 should be SPEED_BOOST")
	assert_eq(int(kinds[5]), Powerup.Kind.BOMB,
		"Index 5 should be BOMB")


func test_type_data_has_six_entries() -> void:
	assert_eq(Powerup.TYPE_DATA.size(), 6,
		"TYPE_DATA should have an entry for each of the 6 kinds")


func test_double_shot_metadata() -> void:
	var d: Dictionary = Powerup.TYPE_DATA[Powerup.Kind.DOUBLE_SHOT]
	assert_eq(str(d["name"]), "DOUBLE SHOT", "DOUBLE_SHOT display name")
	assert_eq(str(d["shot_type"]), "double", "DOUBLE_SHOT shot_type token")
	assert_almost_eq(float(d["duration"]), 15.0, 0.001, "DOUBLE_SHOT duration")
	assert_eq(bool(d["is_shot_type"]), true, "DOUBLE_SHOT is_shot_type")


func test_triple_spread_metadata() -> void:
	var d: Dictionary = Powerup.TYPE_DATA[Powerup.Kind.TRIPLE_SPREAD]
	assert_eq(str(d["name"]), "TRIPLE SPREAD", "TRIPLE_SPREAD display name")
	assert_eq(str(d["shot_type"]), "triple", "TRIPLE_SPREAD shot_type token")
	assert_almost_eq(float(d["duration"]), 12.0, 0.001, "TRIPLE_SPREAD duration")
	assert_eq(bool(d["is_shot_type"]), true, "TRIPLE_SPREAD is_shot_type")


func test_laser_metadata() -> void:
	var d: Dictionary = Powerup.TYPE_DATA[Powerup.Kind.LASER]
	assert_eq(str(d["name"]), "LASER", "LASER display name")
	assert_eq(str(d["shot_type"]), "laser", "LASER shot_type token")
	assert_almost_eq(float(d["duration"]), 8.0, 0.001, "LASER duration")
	assert_eq(bool(d["is_shot_type"]), true, "LASER is_shot_type")


func test_shield_boost_metadata() -> void:
	var d: Dictionary = Powerup.TYPE_DATA[Powerup.Kind.SHIELD_BOOST]
	assert_eq(str(d["name"]), "SHIELD BOOST", "SHIELD_BOOST display name")
	assert_eq(str(d["shot_type"]), "", "SHIELD_BOOST has no shot_type")
	assert_almost_eq(float(d["duration"]), 0.0, 0.001, "SHIELD_BOOST is instant")
	assert_eq(bool(d["is_shot_type"]), false, "SHIELD_BOOST is NOT a shot type")


func test_speed_boost_metadata() -> void:
	var d: Dictionary = Powerup.TYPE_DATA[Powerup.Kind.SPEED_BOOST]
	assert_eq(str(d["name"]), "SPEED BOOST", "SPEED_BOOST display name")
	assert_eq(str(d["shot_type"]), "", "SPEED_BOOST has no shot_type")
	assert_almost_eq(float(d["duration"]), 10.0, 0.001, "SPEED_BOOST duration")
	assert_eq(bool(d["is_shot_type"]), false, "SPEED_BOOST is NOT a shot type")


func test_bomb_metadata() -> void:
	var d: Dictionary = Powerup.TYPE_DATA[Powerup.Kind.BOMB]
	assert_eq(str(d["name"]), "BOMB", "BOMB display name")
	assert_eq(str(d["shot_type"]), "", "BOMB has no shot_type")
	assert_almost_eq(float(d["duration"]), 0.0, 0.001, "BOMB is instant")
	assert_eq(bool(d["is_shot_type"]), false, "BOMB is NOT a shot type")


# --- should_drop / try_drop_powerup (drop chance) ---------------------

func test_should_drop_returns_true_below_threshold() -> void:
	assert_true(Powerup.should_drop(0.0), "roll=0 should always drop")
	assert_true(Powerup.should_drop(0.10), "roll=0.10 should drop (< 0.25)")
	assert_true(Powerup.should_drop(0.2499), "roll just under threshold should drop")


func test_should_drop_returns_false_at_or_above_threshold() -> void:
	assert_false(Powerup.should_drop(0.25), "roll=0.25 should NOT drop")
	assert_false(Powerup.should_drop(0.5), "roll=0.5 should NOT drop")
	assert_false(Powerup.should_drop(0.999), "roll=0.999 should NOT drop")


func test_drop_chance_matches_spec_at_25_percent() -> void:
	# Sanity check: should_drop matches the spec's ~25% rate exactly.
	var hits: int = 0
	var rolls: int = 10000
	for i in range(rolls):
		if Powerup.should_drop(float(i) / float(rolls)):
			hits += 1
	# Over 10000 evenly-spaced rolls, expect hits ~= DROP_CHANCE * rolls.
	# Allow a 0.5% margin for the boundary (roll=0.25).
	var expected: float = Powerup.DROP_CHANCE * float(rolls)
	var margin: float = float(rolls) * 0.005
	assert_almost_eq(float(hits), expected, margin,
		"should_drop rate should be ~25%% over %d rolls" % rolls)


func test_try_drop_powerup_does_not_drop_for_drone() -> void:
	# Drones never drop, regardless of RNG state. Run several iterations
	# to make sure this is a routing decision, not just an unlucky run.
	for i in range(20):
		var p: Node = _main.try_drop_powerup("drone", Vector2(100, 50))
		assert_null(p, "Drone kills should never drop a powerup (iter %d)" % i)


func test_try_drop_powerup_can_drop_for_fighter() -> void:
	# Seed the RNG so we get a deterministic roll. 0.0 always drops; 0.99
	# never does. Test the "happy path" first.
	seed(42)
	var drops: int = 0
	var no_drops: int = 0
	for i in range(50):
		var p: Node = _main.try_drop_powerup("fighter", Vector2(100, 50))
		if p != null:
			drops += 1
			assert_true(p.is_in_group("powerups"),
				"spawned powerup should be in 'powerups' group")
		else:
			no_drops += 1
	# Some drops should occur (we expect ~12-13 of 50 with seed=42).
	assert_gt(drops, 0, "At least one fighter kill should drop a powerup (got %d/50)" % drops)
	assert_gt(no_drops, 0, "At least one fighter kill should NOT drop (got %d/50 misses)" % no_drops)


func test_try_drop_powerup_can_drop_for_bomber() -> void:
	seed(123)
	var drops: int = 0
	for i in range(50):
		var p: Node = _main.try_drop_powerup("bomber", Vector2(200, 80))
		if p != null:
			drops += 1
	assert_gt(drops, 0, "At least one bomber kill should drop a powerup (got %d/50)" % drops)


func test_drop_distribution_is_close_to_25_percent() -> void:
	# Run many fighter kills with a fixed seed; the drop rate should be
	# within +/- 5% of 25% over 200 rolls (per the spec's "~25% chance").
	seed(2024)
	var drops: int = 0
	var rolls: int = 200
	for i in range(rolls):
		if _main.try_drop_powerup("fighter", Vector2(100, 50)) != null:
			drops += 1
	var rate: float = float(drops) / float(rolls)
	assert_almost_eq(rate, Powerup.DROP_CHANCE, 0.05,
		"Drop rate over %d rolls should be ~25%% (got %.3f = %d drops)" %
			[rolls, rate, drops])


# --- Spawning (explicit kind) ------------------------------------------

func test_spawn_powerup_returns_valid_node() -> void:
	var p: Node = _main.spawn_powerup(Powerup.Kind.DOUBLE_SHOT, Vector2(100, 100))
	assert_not_null(p, "spawn_powerup should return a node")
	assert_true(p.is_in_group("powerup"), "Powerup should be in 'powerup' group")
	assert_true(p.is_in_group("powerups"), "Powerup should be in 'powerups' group")


func test_spawn_powerup_applies_kind_to_node() -> void:
	var p: Node = _main.spawn_powerup(Powerup.Kind.LASER, Vector2(100, 100))
	assert_eq(int(p.kind), Powerup.Kind.LASER,
		"spawn_powerup should set kind on the spawned node")
	assert_eq(str(p.get_type_name()), "LASER",
		"spawn_powerup should produce a LASER-named powerup")


func test_spawn_random_powerup_returns_valid_node() -> void:
	seed(7)
	var p: Node = _main.spawn_random_powerup(Vector2(100, 100))
	assert_not_null(p, "spawn_random_powerup should return a node")
	assert_true(p.is_in_group("powerup"),
		"Random powerup should still be in 'powerup' group")


# --- Auto-collect on player contact ------------------------------------

func test_powerup_auto_collects_on_player_contact() -> void:
	# Spawn a powerup at a known position, then move the player to that
	# position. The headless viewport in GUT is 64x64, so the player's
	# clamp would push it back from 200,200 to (48, 48). We use a
	# position within the 64x64 viewport so the overlap actually happens.
	# Multiple physics frames are needed: one for the Area2D to register
	# with the physics server, one for the position update, one for the
	# overlap detection, and one for queue_free to actually free the node.
	var p: Node = _main.spawn_powerup(Powerup.Kind.DOUBLE_SHOT, Vector2(20, 20))
	assert_not_null(p, "powerup should spawn")
	# Move the player to the powerup's position so they overlap.
	_main.player.global_position = Vector2(20, 20)
	for i in range(4):
		await get_tree().physics_frame
	# Powerup should be queued for free; give the engine a frame to actually free it.
	assert_false(is_instance_valid(p),
		"Powerup should be freed after player walks into it")


func test_auto_collect_applies_effect_to_player() -> void:
	# Spawn a DOUBLE_SHOT pickup, walk into it, verify player.shot_type is
	# updated and the pickup is freed. Position is within the 64x64
	# headless viewport so the clamp doesn't push the player back out.
	var p: Node = _main.spawn_powerup(Powerup.Kind.DOUBLE_SHOT, Vector2(20, 20))
	assert_eq(_main.player.shot_type, "single",
		"Player should start with single shot")
	_main.player.global_position = Vector2(20, 20)
	for i in range(4):
		await get_tree().physics_frame
	assert_false(is_instance_valid(p), "Pickup should be freed on contact")
	assert_eq(_main.player.shot_type, "double",
		"Player should have DOUBLE_SHOT active after pickup")
	assert_true(_main.player.active_powerups.has(Powerup.Kind.DOUBLE_SHOT),
		"DOUBLE_SHOT should be in active_powerups")


func test_auto_collect_collected_signal_fires() -> void:
	var p: Node = _main.spawn_powerup(Powerup.Kind.SPEED_BOOST, Vector2(20, 20))
	var received: Array = []
	p.collected.connect(func(node): received.append(node))
	_main.player.global_position = Vector2(20, 20)
	for i in range(4):
		await get_tree().physics_frame
	# The signal was emitted before queue_free; collected signal will have
	# fired even if the node is now freed.
	assert_eq(received.size(), 1, "collected signal should fire once on pickup")


# --- Single-active shot rule ------------------------------------------

func test_double_shot_then_triple_replaces_active() -> void:
	_main.player.apply_powerup(Powerup.Kind.DOUBLE_SHOT)
	assert_eq(_main.player.shot_type, "double",
		"After DOUBLE_SHOT, shot_type should be 'double'")
	assert_true(_main.player.active_powerups.has(Powerup.Kind.DOUBLE_SHOT),
		"DOUBLE_SHOT should be active")
	_main.player.apply_powerup(Powerup.Kind.TRIPLE_SPREAD)
	assert_eq(_main.player.shot_type, "triple",
		"After TRIPLE_SPREAD, shot_type should be 'triple'")
	# DOUBLE_SHOT should be GONE from active_powerups (mutual exclusion).
	assert_false(_main.player.active_powerups.has(Powerup.Kind.DOUBLE_SHOT),
		"DOUBLE_SHOT should be replaced by TRIPLE_SPREAD")
	assert_true(_main.player.active_powerups.has(Powerup.Kind.TRIPLE_SPREAD),
		"TRIPLE_SPREAD should be active")


func test_triple_spread_then_laser_replaces_active() -> void:
	_main.player.apply_powerup(Powerup.Kind.TRIPLE_SPREAD)
	_main.player.apply_powerup(Powerup.Kind.LASER)
	assert_eq(_main.player.shot_type, "laser",
		"Laser should win over TRIPLE_SPREAD")
	assert_false(_main.player.active_powerups.has(Powerup.Kind.TRIPLE_SPREAD),
		"TRIPLE_SPREAD should be replaced by LASER")


func test_only_one_shot_type_active_at_a_time() -> void:
	# Cycle through all 3 shot types, then check exactly one is in the dict.
	for k in [Powerup.Kind.DOUBLE_SHOT, Powerup.Kind.TRIPLE_SPREAD, Powerup.Kind.LASER]:
		_main.player.apply_powerup(k)
	var shot_keys: Array = []
	for k in _main.player.active_powerups.keys():
		if int(k) == Powerup.Kind.DOUBLE_SHOT \
				or int(k) == Powerup.Kind.TRIPLE_SPREAD \
				or int(k) == Powerup.Kind.LASER:
			shot_keys.append(int(k))
	assert_eq(shot_keys.size(), 1,
		"Only one shot-type should be active at a time (got %d)" % shot_keys.size())


# --- Non-shot coexistence ---------------------------------------------

func test_speed_boost_coexists_with_double_shot() -> void:
	_main.player.apply_powerup(Powerup.Kind.DOUBLE_SHOT)
	_main.player.apply_powerup(Powerup.Kind.SPEED_BOOST)
	assert_eq(_main.player.shot_type, "double",
		"SPEED_BOOST should not change shot_type")
	assert_almost_eq(_main.player.speed_multiplier, 1.4, 0.001,
		"SPEED_BOOST should set speed_multiplier to 1.4")
	assert_true(_main.player.active_powerups.has(Powerup.Kind.DOUBLE_SHOT),
		"DOUBLE_SHOT should still be active")
	assert_true(_main.player.active_powerups.has(Powerup.Kind.SPEED_BOOST),
		"SPEED_BOOST should be active alongside DOUBLE_SHOT")


func test_two_speed_boosts_refresh_duration() -> void:
	_main.player.apply_powerup(Powerup.Kind.SPEED_BOOST)
	var first: float = float(_main.player.active_powerups[Powerup.Kind.SPEED_BOOST])
	_main.player.apply_powerup(Powerup.Kind.SPEED_BOOST)
	var second: float = float(_main.player.active_powerups[Powerup.Kind.SPEED_BOOST])
	assert_almost_eq(second, 10.0, 0.001,
		"Re-applying SPEED_BOOST should refresh duration to 10s")
	# Second application resets to full duration, so it should be >= first
	# (assuming some time passed, but in a single test it should be exact).
	assert_gte(second, first, "Refreshed duration should be >= original")


# --- Durations tick and expire -----------------------------------------

func test_double_shot_expires_after_15_seconds() -> void:
	_main.player.apply_powerup(Powerup.Kind.DOUBLE_SHOT)
	_main.player._tick_powerups(15.0)
	assert_false(_main.player.active_powerups.has(Powerup.Kind.DOUBLE_SHOT),
		"DOUBLE_SHOT should expire after 15s tick")
	assert_eq(_main.player.shot_type, "single",
		"shot_type should reset to 'single' on expiry")


func test_triple_spread_expires_after_12_seconds() -> void:
	_main.player.apply_powerup(Powerup.Kind.TRIPLE_SPREAD)
	_main.player._tick_powerups(12.0)
	assert_false(_main.player.active_powerups.has(Powerup.Kind.TRIPLE_SPREAD),
		"TRIPLE_SPREAD should expire after 12s tick")
	assert_eq(_main.player.shot_type, "single",
		"shot_type should reset to 'single' on expiry")


func test_laser_expires_after_8_seconds() -> void:
	_main.player.apply_powerup(Powerup.Kind.LASER)
	_main.player._tick_powerups(8.0)
	assert_false(_main.player.active_powerups.has(Powerup.Kind.LASER),
		"LASER should expire after 8s tick")
	assert_eq(_main.player.shot_type, "single",
		"shot_type should reset to 'single' on expiry")


func test_speed_boost_expires_after_10_seconds() -> void:
	_main.player.apply_powerup(Powerup.Kind.SPEED_BOOST)
	_main.player._tick_powerups(10.0)
	assert_false(_main.player.active_powerups.has(Powerup.Kind.SPEED_BOOST),
		"SPEED_BOOST should expire after 10s tick")
	assert_almost_eq(_main.player.speed_multiplier, 1.0, 0.001,
		"speed_multiplier should reset to 1.0 on expiry")


func test_partial_tick_decreases_remaining() -> void:
	_main.player.apply_powerup(Powerup.Kind.DOUBLE_SHOT)
	_main.player._tick_powerups(3.0)
	var remaining: float = float(_main.player.active_powerups[Powerup.Kind.DOUBLE_SHOT])
	assert_almost_eq(remaining, 12.0, 0.01,
		"After 3s of 15s, DOUBLE_SHOT should have 12.0s remaining")


func test_powerup_changed_signal_fires_on_expiry() -> void:
	_main.player.apply_powerup(Powerup.Kind.DOUBLE_SHOT)
	var signals_received: Array = []
	_main.player.powerup_changed.connect(func(k, n, r): signals_received.append([k, n, r]))
	_main.player._tick_powerups(15.0)
	# At least one signal with remaining=0 should have fired on expiry.
	var found_expiry: bool = false
	for entry in signals_received:
		if int(entry[0]) == Powerup.Kind.DOUBLE_SHOT and float(entry[2]) <= 0.0:
			found_expiry = true
			break
	assert_true(found_expiry,
		"powerup_changed should fire with remaining=0 on expiry")


# --- SHIELD_BOOST (instant) --------------------------------------------

func test_shield_boost_restores_half_max_shield() -> void:
	# Damage the player first, then apply SHIELD_BOOST.
	_main.player.shield = _main.player.max_shield * 0.5  # 50% shield
	_main.player.apply_powerup(Powerup.Kind.SHIELD_BOOST)
	var expected: float = _main.player.max_shield * 0.5 + _main.player.max_shield * 0.5
	assert_almost_eq(_main.player.shield, expected, 0.01,
		"SHIELD_BOOST should restore to full max_shield")


func test_shield_boost_does_not_exceed_max() -> void:
	_main.player.shield = _main.player.max_shield  # already full
	_main.player.apply_powerup(Powerup.Kind.SHIELD_BOOST)
	assert_almost_eq(_main.player.shield, _main.player.max_shield, 0.001,
		"SHIELD_BOOST should cap at max_shield")


func test_shield_boost_does_not_register_in_active_powerups() -> void:
	# SHIELD_BOOST is instant, so it should NOT appear in active_powerups
	# (which only tracks timed effects).
	_main.player.apply_powerup(Powerup.Kind.SHIELD_BOOST)
	assert_false(_main.player.active_powerups.has(Powerup.Kind.SHIELD_BOOST),
		"SHIELD_BOOST is instant and should not be in active_powerups")


# --- BOMB --------------------------------------------------------------

func test_bomb_clears_all_bullets() -> void:
	# Create 3 player bullets + 2 enemy bullets, then drop a bomb.
	# Bullets are acquired in this test specifically (not from player
	# auto-fire) so we can verify the bomb released them.
	# First, suppress the player's auto-fire by setting fire_cooldown to
	# a large value so it doesn't pollute the bullet set during the test.
	if _main.player and "_fire_cooldown" in _main.player:
		_main.player._fire_cooldown = 1000.0
	var p1: Node = _acquire_player_bullet(Vector2(20, 20))
	var p2: Node = _acquire_player_bullet(Vector2(30, 20))
	var p3: Node = _acquire_player_bullet(Vector2(40, 20))
	var e1: Node = _acquire_enemy_bullet(Vector2(20, 30))
	var e2: Node = _acquire_enemy_bullet(Vector2(30, 30))
	# Assert all 5 of our bullets are in the tree to start.
	assert_true(is_instance_valid(p1) and p1.is_inside_tree(),
		"Player bullet 1 should be in tree")
	assert_true(is_instance_valid(p2) and p2.is_inside_tree(),
		"Player bullet 2 should be in tree")
	assert_true(is_instance_valid(p3) and p3.is_inside_tree(),
		"Player bullet 3 should be in tree")
	assert_true(is_instance_valid(e1) and e1.is_inside_tree(),
		"Enemy bullet 1 should be in tree")
	assert_true(is_instance_valid(e2) and e2.is_inside_tree(),
		"Enemy bullet 2 should be in tree")
	# Apply bomb via the main API (which routes BOMB to _bomb_blast).
	_main.apply_powerup(Powerup.Kind.BOMB, _main.player, null)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# All 5 of our bullets should now be released to the pool (no longer
	# in the scene tree). The bomb iterates the 'bullets' group and calls
	# _release_self on each, which removes from parent and hides / queues
	# for free. We don't assert on pool free-list counts because the pool
	# can accumulate entries from earlier tests -- the signal here is
	# that OUR specific bullets are no longer in the scene tree.
	assert_true(is_instance_valid(p1) and not p1.is_inside_tree(),
		"Player bullet 1 should be released (out of tree)")
	assert_true(is_instance_valid(p2) and not p2.is_inside_tree(),
		"Player bullet 2 should be released (out of tree)")
	assert_true(is_instance_valid(p3) and not p3.is_inside_tree(),
		"Player bullet 3 should be released (out of tree)")
	assert_true(is_instance_valid(e1) and not e1.is_inside_tree(),
		"Enemy bullet 1 should be released (out of tree)")
	assert_true(is_instance_valid(e2) and not e2.is_inside_tree(),
		"Enemy bullet 2 should be released (out of tree)")


func test_bomb_damages_all_enemies_by_2() -> void:
	# Drones have 1 HP, so 2 damage from bomb kills them. A 2-HP fighter
	# also dies (2 dmg >= 2 HP). After the bomb, enemies may be queue_freed
	# so we assert via main.get_enemy_count() (defensive) instead of poking
	# at freed enemy references.
	_main.spawn_enemy("drone", Vector2(100, 200))
	_main.spawn_enemy("drone", Vector2(200, 200))
	_main.spawn_enemy("fighter", Vector2(300, 200))
	assert_eq(_main.get_enemy_count(), 3, "3 enemies before bomb")
	_main.apply_powerup(Powerup.Kind.BOMB, _main.player, null)
	# tree_exited fires on the next physics step.
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(_main.get_enemy_count(), 0,
		"All enemies should be cleared (got %d after bomb)" % _main.get_enemy_count())
	# Bomb awarded score for all 3 (10 + 10 + 25 = 45), which is a strong
	# implicit assertion that they were all damaged and killed.
	assert_eq(_main.score, 45,
		"Bomb should award 45 points total (got %d)" % _main.score)


func test_bomb_awards_score_for_killed_enemies() -> void:
	# Drones are worth 10 points each, fighters 25. Killing 2 drones + 1
	# fighter via bomb should award 10 + 10 + 25 = 45 points.
	_main.spawn_enemy("drone", Vector2(100, 200))
	_main.spawn_enemy("drone", Vector2(200, 200))
	_main.spawn_enemy("fighter", Vector2(300, 200))
	assert_eq(_main.score, 0, "Score should start at 0")
	_main.apply_powerup(Powerup.Kind.BOMB, _main.player, null)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# 10 + 10 + 25 = 45
	assert_eq(_main.score, 45,
		"BOMB should award 45 points for killing 2 drones + 1 fighter (got %d)" % _main.score)


func test_bomb_increases_main_enemy_count_to_zero() -> void:
	_main.spawn_enemy("drone", Vector2(100, 200))
	_main.spawn_enemy("drone", Vector2(200, 200))
	_main.spawn_enemy("fighter", Vector2(300, 200))
	assert_eq(_main.get_enemy_count(), 3, "3 enemies before bomb")
	_main.apply_powerup(Powerup.Kind.BOMB, _main.player, null)
	await get_tree().physics_frame
	# tree_exited fires async; give it a frame to settle.
	await get_tree().physics_frame
	assert_eq(_main.get_enemy_count(), 0,
		"All enemies should be cleared after bomb (got %d)" % _main.get_enemy_count())


# --- HUD integration --------------------------------------------------

func test_hud_shows_active_powerup_name() -> void:
	_main.player.apply_powerup(Powerup.Kind.DOUBLE_SHOT)
	await get_tree().physics_frame
	assert_eq(_main.hud.active_powerup_name, "DOUBLE SHOT",
		"HUD should display 'DOUBLE SHOT' after pickup")


func test_hud_shows_active_powerup_remaining() -> void:
	_main.player.apply_powerup(Powerup.Kind.DOUBLE_SHOT)
	await get_tree().physics_frame
	assert_almost_eq(_main.hud.active_powerup_remaining, 15.0, 0.1,
		"HUD should show ~15.0s remaining after DOUBLE_SHOT pickup")


func test_hud_clears_on_expiry() -> void:
	_main.player.apply_powerup(Powerup.Kind.LASER)
	await get_tree().physics_frame
	_main.player._tick_powerups(8.0)
	await get_tree().physics_frame
	# After expiry, powerup_changed fired with remaining=0; HUD set_active_powerup
	# clears the label when remaining <= 0.
	assert_eq(_main.hud.active_powerup_name, "",
		"HUD should clear active powerup name on expiry")


# --- State shape ------------------------------------------------------

func test_player_state_includes_powerup_fields() -> void:
	_main.player.apply_powerup(Powerup.Kind.SPEED_BOOST)
	var state: Dictionary = _main.player.get_state()
	assert_has(state, "shot_type", "get_state() should include shot_type")
	assert_has(state, "speed_multiplier", "get_state() should include speed_multiplier")
	assert_has(state, "active_powerups", "get_state() should include active_powerups")
	assert_eq(str(state["shot_type"]), "single",
		"SPEED_BOOST should not change shot_type")
	assert_almost_eq(float(state["speed_multiplier"]), 1.4, 0.001,
		"SPEED_BOOST should set speed_multiplier to 1.4")


func test_hud_state_includes_powerup_fields() -> void:
	_main.player.apply_powerup(Powerup.Kind.DOUBLE_SHOT)
	await get_tree().physics_frame
	var state: Dictionary = _main.hud.get_state()
	assert_has(state, "active_powerup_name",
		"HUD get_state() should include active_powerup_name")
	assert_has(state, "active_powerup_remaining",
		"HUD get_state() should include active_powerup_remaining")


# --- Cleanup helpers (no assertions) ----------------------------------

func test_cleanup_releases_stray_bullets() -> void:
	# Sanity: the helper should not crash on an empty bullet set.
	_release_stray_bullets()
	_release_stray_bullets()
	assert_true(true, "Cleanup helper should be a no-op when no stray bullets")
