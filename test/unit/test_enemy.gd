extends GutTest
## GUT tests for enemy types (task 0003):
##  - HP per type (drone=1, fighter=2, bomber=4)
##  - Fire-pattern emission with the timer mocked (drones don't fire,
##    fighters fire 1 aimed shot, bombers fire a 3-shot burst)
##  - Scoring on kill: Main.add_score() is called with the right value
##    (10 / 25 / 50) and the died signal carries that value too
##  - Enemies are added to the "enemy" and "enemies" groups so the bullet
##    friendly-fire filter routes damage correctly
##  - Defeated enemies free themselves from the main scene tree (so the
##    wave manager can rely on get_enemy_count() / tree_exited to track
##    active wave members)

const ENEMY_BASE := preload("res://scripts/enemy_base.gd")
const ENEMY_DRONE := preload("res://scripts/enemy_drone.gd")
const ENEMY_FIGHTER := preload("res://scripts/enemy_fighter.gd")
const ENEMY_BOMBER := preload("res://scripts/enemy_bomber.gd")
const MAIN_SCRIPT := preload("res://scripts/main.gd")

var _main: Node = null


func before_each() -> void:
	# Each test gets a fresh Main so enemy state and score are isolated.
	_main = MAIN_SCRIPT.new()
	add_child_autofree(_main)


func after_each() -> void:
	# Release any test bullets we acquired so the pool's free list doesn't
	# grow per test. Each release removes the bullet from the parent
	# and pushes it onto the per-faction free list.
	for b: Node in _acquired_test_bullets:
		if is_instance_valid(b):
			BulletPool.release(b)
	_acquired_test_bullets.clear()
	# Free the per-test ally if the test created one (we don't use
	# add_child_autofree for it because _main is already in the GUT tree).
	if _ally_in_test != null and is_instance_valid(_ally_in_test):
		_ally_in_test.queue_free()
	_ally_in_test = null
	_main = null


# --- Helpers ------------------------------------------------------------

func _spawn(enemy_type: String) -> Node:
	var e: Node = _main.spawn_enemy(enemy_type, Vector2(100, 50))
	assert_not_null(e, "spawn_enemy(%s) should return a node" % enemy_type)
	return e


func _enemy_bullets_acquired_during(callable: Callable) -> int:
	# Snapshot pool stats, run a fire-emit callable, then return the delta
	# in 'enemy' alive count. Used to assert how many bullets a fire
	# pattern spawned without inspecting the bullet nodes themselves.
	var stats_before: Dictionary = BulletPool.get_stats()
	var before: int = int(stats_before.get("enemy", {}).get("alive", 0))
	callable.call()
	var stats_after: Dictionary = BulletPool.get_stats()
	var after: int = int(stats_after.get("enemy", {}).get("alive", 0))
	# Recycle anything we just acquired so the pool doesn't grow per test.
	var enemies_in_tree := get_tree().get_nodes_in_group("bullets")
	for b: Node in enemies_in_tree:
		if is_instance_valid(b) and "faction" in b and b.faction == "enemy" \
				and b.get_parent() != null and b.get_parent() != _main:
			BulletPool.release(b)
	return after - before


func _release_stray_enemy_bullets() -> void:
	var all_bullets := get_tree().get_nodes_in_group("bullets")
	for b: Node in all_bullets:
		if is_instance_valid(b) and "faction" in b and b.faction == "enemy":
			BulletPool.release(b)


# --- HP per type --------------------------------------------------------

func test_drone_has_one_hp() -> void:
	var drone: Node = _spawn("drone")
	assert_eq(int(drone.hp), 1, "Drone should start at 1 HP")
	assert_eq(int(drone.max_hp), 1, "Drone max_hp should be 1")


func test_fighter_has_two_hp() -> void:
	var fighter: Node = _spawn("fighter")
	assert_eq(int(fighter.hp), 2, "Fighter should start at 2 HP")
	assert_eq(int(fighter.max_hp), 2, "Fighter max_hp should be 2")


func test_bomber_has_four_hp() -> void:
	var bomber: Node = _spawn("bomber")
	assert_eq(int(bomber.hp), 4, "Bomber should start at 4 HP")
	assert_eq(int(bomber.max_hp), 4, "Bomber max_hp should be 4")


func test_drone_dies_in_one_hit() -> void:
	var drone: Node = _spawn("drone")
	drone.take_damage(1)
	assert_eq(int(drone.hp), 0, "Drone HP should be 0 after one hit")
	assert_true(bool(drone._is_dead), "Drone should be marked dead")


func test_fighter_dies_in_two_hits() -> void:
	var fighter: Node = _spawn("fighter")
	fighter.take_damage(1)
	assert_eq(int(fighter.hp), 1, "Fighter HP should be 1 after first hit")
	assert_false(bool(fighter._is_dead), "Fighter should not be dead at 1 HP")
	fighter.take_damage(1)
	assert_eq(int(fighter.hp), 0, "Fighter HP should be 0 after second hit")
	assert_true(bool(fighter._is_dead), "Fighter should be dead at 0 HP")


func test_bomber_dies_in_four_hits() -> void:
	var bomber: Node = _spawn("bomber")
	for i in range(3):
		bomber.take_damage(1)
	assert_eq(int(bomber.hp), 1, "Bomber HP should be 1 after 3 hits")
	assert_false(bool(bomber._is_dead), "Bomber should not be dead at 1 HP")
	bomber.take_damage(1)
	assert_eq(int(bomber.hp), 0, "Bomber HP should be 0 after 4th hit")
	assert_true(bool(bomber._is_dead), "Bomber should be dead at 0 HP")


func test_overkill_damage_still_dies_once() -> void:
	var drone: Node = _spawn("drone")
	drone.take_damage(50)
	assert_eq(int(drone.hp), 0, "Overkill should clamp HP to 0")
	assert_true(bool(drone._is_dead), "Overkill should still mark enemy dead")


# --- Group membership (so player bullets target us) -------------------

func test_drone_is_in_enemy_groups() -> void:
	var drone: Node = _spawn("drone")
	assert_true(drone.is_in_group("enemy"), "Drone should be in 'enemy' group")
	assert_true(drone.is_in_group("enemies"), "Drone should be in 'enemies' group")


func test_fighter_is_in_enemy_groups() -> void:
	var fighter: Node = _spawn("fighter")
	assert_true(fighter.is_in_group("enemy"), "Fighter should be in 'enemy' group")


func test_bomber_is_in_enemy_groups() -> void:
	var bomber: Node = _spawn("bomber")
	assert_true(bomber.is_in_group("enemy"), "Bomber should be in 'enemy' group")


# --- Fire-pattern emission (mocked timer) -----------------------------

func test_drone_does_not_fire() -> void:
	var drone: Node = _spawn("drone")
	# Drones have fire_interval = 0, so _try_fire should be a no-op regardless
	# of how much time we tick. Mock the timer by zeroing the cooldown and
	# calling _try_fire repeatedly.
	drone._fire_cooldown = 0.0
	var spawned: int = _enemy_bullets_acquired_during(func() -> void:
		for i in range(5):
			drone._try_fire(0.5)
	)
	assert_eq(spawned, 0, "Drone should never spawn bullets")
	_release_stray_enemy_bullets()


func test_fighter_fires_aimed_single_shot() -> void:
	var fighter: Node = _spawn("fighter")
	# Force fire by zeroing the cooldown, then tick _try_fire once.
	fighter._fire_cooldown = 0.0
	var spawned: int = _enemy_bullets_acquired_during(func() -> void:
		fighter._try_fire(0.001)
	)
	assert_eq(spawned, 1, "Fighter should fire exactly 1 bullet per tick")
	_release_stray_enemy_bullets()


func test_bomber_fires_three_shot_burst() -> void:
	var bomber: Node = _spawn("bomber")
	bomber._fire_cooldown = 0.0
	var spawned: int = _enemy_bullets_acquired_during(func() -> void:
		bomber._try_fire(0.001)
	)
	assert_eq(spawned, 3, "Bomber should fire exactly 3 bullets per burst")
	_release_stray_enemy_bullets()


func test_drone_fire_interval_is_zero() -> void:
	var drone: Node = _spawn("drone")
	assert_almost_eq(drone.fire_interval, 0.0, 0.001,
		"Drone fire_interval should be 0 (no fire)")


func test_fighter_fire_interval_is_positive() -> void:
	var fighter: Node = _spawn("fighter")
	assert_gt(fighter.fire_interval, 0.0,
		"Fighter fire_interval should be > 0 so it actually shoots")


func test_bomber_fire_interval_is_positive() -> void:
	var bomber: Node = _spawn("bomber")
	assert_gt(bomber.fire_interval, 0.0,
		"Bomber fire_interval should be > 0 so it actually shoots")


func test_drone_does_not_respawn_cooldown_when_fire_disabled() -> void:
	# Edge case: even if some external code resets _fire_cooldown, a drone
	# (fire_interval = 0) must not start firing. This guarantees the
	# "drones never shoot" contract from the design doc.
	var drone: Node = _spawn("drone")
	drone._fire_cooldown = 0.0
	drone._try_fire(10.0)
	assert_eq(drone._fire_cooldown, 0.0,
		"Drone fire cooldown should stay 0 (fire_interval=0 means disabled)")


# --- Scoring on kill (died signal + main.add_score) -------------------

func test_drone_died_signal_carries_10_points() -> void:
	var drone: Node = _spawn("drone")
	var received: Array = []
	drone.died.connect(func(v): received.append(v))
	drone.take_damage(drone.max_hp)
	assert_eq(received.size(), 1, "drone.died should fire once on kill")
	assert_eq(int(received[0]), 10, "Drone should be worth 10 points")


func test_fighter_died_signal_carries_25_points() -> void:
	var fighter: Node = _spawn("fighter")
	var received: Array = []
	fighter.died.connect(func(v): received.append(v))
	fighter.take_damage(fighter.max_hp)
	assert_eq(received.size(), 1, "fighter.died should fire once on kill")
	assert_eq(int(received[0]), 25, "Fighter should be worth 25 points")


func test_bomber_died_signal_carries_50_points() -> void:
	var bomber: Node = _spawn("bomber")
	var received: Array = []
	bomber.died.connect(func(v): received.append(v))
	bomber.take_damage(bomber.max_hp)
	assert_eq(received.size(), 1, "bomber.died should fire once on kill")
	assert_eq(int(received[0]), 50, "Bomber should be worth 50 points")


func test_killing_drone_adds_10_to_main_score() -> void:
	var drone: Node = _spawn("drone")
	assert_eq(_main.score, 0, "Main score should start at 0")
	drone.take_damage(drone.max_hp)
	assert_eq(_main.score, 10, "Main score should be 10 after killing a drone")
	assert_eq(_main.high_score, 10, "Main high_score should track the new max")


func test_killing_fighter_adds_25_to_main_score() -> void:
	var fighter: Node = _spawn("fighter")
	fighter.take_damage(fighter.max_hp)
	assert_eq(_main.score, 25, "Main score should be 25 after killing a fighter")


func test_killing_bomber_adds_50_to_main_score() -> void:
	var bomber: Node = _spawn("bomber")
	bomber.take_damage(bomber.max_hp)
	assert_eq(_main.score, 50, "Main score should be 50 after killing a bomber")


func test_killing_multiple_enemies_accumulates_score() -> void:
	_spawn("drone").take_damage(1)
	_spawn("drone").take_damage(1)
	_spawn("fighter").take_damage(2)
	_spawn("bomber").take_damage(4)
	assert_eq(_main.score, 10 + 10 + 25 + 50,
		"Main score should accumulate: 2 drones + fighter + bomber")


# --- Defeated enemies free themselves from the wave / main -----------

func test_killing_enemy_removes_it_from_enemy_count() -> void:
	var drone: Node = _spawn("drone")
	var fighter: Node = _spawn("fighter")
	assert_eq(_main.get_enemy_count(), 2,
		"Main should track 2 live enemies before kills")
	drone.take_damage(drone.max_hp)
	# tree_exited fires on the next frame; pump one physics step so the
	# queue_free takes effect.
	await get_tree().physics_frame
	assert_eq(_main.get_enemy_count(), 1,
		"Main should report 1 live enemy after killing the drone")
	# Cleanup: kill the fighter so it doesn't bleed into the next test.
	fighter.take_damage(fighter.max_hp)


func test_killed_enemy_is_freed_from_scene_tree() -> void:
	var drone: Node = _spawn("drone")
	assert_true(is_instance_valid(drone), "Drone should be valid after spawn")
	drone.take_damage(drone.max_hp)
	await get_tree().physics_frame
	assert_false(is_instance_valid(drone),
		"Drone should be freed from the scene tree after death")


# --- Type-name identity -----------------------------------------------

func test_drone_reports_type_name_drone() -> void:
	var drone: Node = _spawn("drone")
	assert_eq(str(drone.enemy_type_name), "drone",
		"Drone enemy_type_name should be 'drone'")


func test_fighter_reports_type_name_fighter() -> void:
	var fighter: Node = _spawn("fighter")
	assert_eq(str(fighter.enemy_type_name), "fighter",
		"Fighter enemy_type_name should be 'fighter'")


func test_bomber_reports_type_name_bomber() -> void:
	var bomber: Node = _spawn("bomber")
	assert_eq(str(bomber.enemy_type_name), "bomber",
		"Bomber enemy_type_name should be 'bomber'")


# --- get_state() shape --------------------------------------------------

func test_enemy_get_state_shape() -> void:
	var drone: Node = _spawn("drone")
	var state: Dictionary = drone.get_state()
	var expected_keys := ["type", "hp", "max_hp", "score_value", "position", "is_dead"]
	for k: String in expected_keys:
		assert_has(state, k, "get_state() should include key: %s" % k)
	assert_eq(int(state["hp"]), 1, "state.hp should match starting HP")
	assert_eq(int(state["score_value"]), 10, "state.score_value should be 10 for drone")
	assert_eq(state["is_dead"], false, "state.is_dead should be false at start")


# --- Player-bullet -> enemy integration (0003 + 0002) -----------------
# The acceptance criteria for task 0003 say "Player bullets destroy
# enemies on contact (HP per type)". The bullet-vs-generic-target flow
# is covered in test_bullet.gd, but here we exercise the *actual*
# enemy classes end-to-end: acquire a real player bullet, call its
# body_entered handler with a spawned enemy, and assert that the enemy's
# HP drops by the bullet's damage value.

var _acquired_test_bullets: Array = []


func _acquire_player_bullet_against(enemy: Node) -> Node:
	# Position the bullet at the same global position as the enemy so the
	# caller can call _on_body_entered without worrying about coordinates.
	var b: Node = BulletPool.acquire("player", enemy.global_position, _main)
	# Recycle the bullet in after_each so the pool doesn't grow per test.
	_acquired_test_bullets.append(b)
	return b


func test_player_bullet_one_hit_kills_drone() -> void:
	var drone: Node = _spawn("drone")
	var bullet: Node = _acquire_player_bullet_against(drone)
	# Bullet._on_body_entered takes a body (Node) and routes through
	# _can_hit -> take_damage -> _release_self.
	bullet._on_body_entered(drone)
	assert_eq(int(drone.hp), 0, "Drone should be at 0 HP after one player bullet")
	assert_true(bool(drone._is_dead),
		"Drone should be marked dead after one player bullet")


func test_player_bullet_two_hits_kills_fighter() -> void:
	var fighter: Node = _spawn("fighter")
	var b1: Node = _acquire_player_bullet_against(fighter)
	b1._on_body_entered(fighter)
	assert_eq(int(fighter.hp), 1,
		"Fighter should have 1 HP after one player bullet")
	assert_false(bool(fighter._is_dead),
		"Fighter should NOT be dead after 1 hit (HP=2)")
	# Acquire a second bullet (the first is in the pool's free list now).
	var b2: Node = _acquire_player_bullet_against(fighter)
	b2._on_body_entered(fighter)
	assert_eq(int(fighter.hp), 0,
		"Fighter should be at 0 HP after two player bullets")
	assert_true(bool(fighter._is_dead),
		"Fighter should be marked dead after 2 hits")


func test_player_bullet_four_hits_kills_bomber() -> void:
	var bomber: Node = _spawn("bomber")
	for i in range(3):
		var b: Node = _acquire_player_bullet_against(bomber)
		b._on_body_entered(bomber)
		assert_false(bool(bomber._is_dead),
			"Bomber should NOT be dead at HP %d" % int(bomber.hp))
	assert_eq(int(bomber.hp), 1,
		"Bomber should be at 1 HP after three player bullets")
	var final_bullet: Node = _acquire_player_bullet_against(bomber)
	final_bullet._on_body_entered(bomber)
	assert_eq(int(bomber.hp), 0, "Bomber should be at 0 HP after 4 hits")
	assert_true(bool(bomber._is_dead),
		"Bomber should be marked dead after 4 hits")


func test_player_bullet_killing_drone_credits_score() -> void:
	# End-to-end: a real bullet hitting a real enemy should trigger the
	# died signal, which main.gd's _on_enemy_died converts to add_score.
	var drone: Node = _spawn("drone")
	assert_eq(_main.score, 0, "Score starts at 0")
	var bullet: Node = _acquire_player_bullet_against(drone)
	bullet._on_body_entered(drone)
	# Died signal already fired; main's _on_enemy_died should have added 10.
	assert_eq(_main.score, 10,
		"Score should be 10 after a player bullet kills a drone")


func test_player_bullet_killing_bomber_credits_50() -> void:
	var bomber: Node = _spawn("bomber")
	for i in range(4):
		var b: Node = _acquire_player_bullet_against(bomber)
		b._on_body_entered(bomber)
	assert_eq(_main.score, 50,
		"Score should be 50 after a player bullet kills a bomber")


func test_player_bullet_on_player_ally_does_not_damage() -> void:
	# A player bullet should never damage a friendly (the player itself,
	# another player, or another bullet). _can_hit filters by the `enemy`
	# group; spawn a fake "ally" target and verify it stays alive and the
	# bullet is NOT consumed.
	var ally: Node = Node2D.new()
	ally.add_to_group("player")
	_main.add_child(ally)
	# Note: do NOT add_child_autofree(ally) -- _main is already a child of
	# the GUT tree, so re-parenting the ally would raise "already has a
	# parent". We free it explicitly in after_each to keep the test tidy.
	_ally_in_test = ally
	var bullet: Node = _acquire_player_bullet_against(ally)
	# _on_body_entered will see group=player, faction=player -> skip.
	bullet._on_body_entered(ally)
	# Bullet should still have a parent (not released).
	assert_eq(bullet.get_parent(), _main,
		"Bullet should stay in tree when target is in friendly group")
	# Sanity: the ally itself was not damaged (no take_damage method on
	# a bare Node2D, so this is implicit; the contract is "the bullet
	# didn't try to call take_damage on a non-enemy group").
	assert_true(is_instance_valid(ally), "Ally target should still be valid")


# Tracked so after_each can free the per-test ally that we parented to
# _main. We avoid add_child_autofree(ally) here because _main is already
# in the GUT tree and re-parenting the ally would fail the precondition.
var _ally_in_test: Node = null
