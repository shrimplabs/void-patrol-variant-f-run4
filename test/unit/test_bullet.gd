extends GutTest
## GUT tests for the bullet system (task 0002):
##  - faction-driven travel direction (player up, enemy down)
##  - faction-driven visual color
##  - screen-edge despawn via VisibleOnScreenNotifier2D
##  - body_entered / area_entered collision damage + friendly-fire filter
##  - pool reuse (no per-shot allocation spikes)

const BULLET_SCRIPT := preload("res://scripts/bullet.gd")
const _DAMAGE_TARGET := preload("res://test/unit/_damage_target.gd")

var _holder: Node = null
var _acquired: Array = []  # tracked so after_each can release them


func before_each() -> void:
	_holder = Node.new()
	_holder.name = "BulletTestHolder"
	add_child_autofree(_holder)
	_acquired = []


func after_each() -> void:
	for b in _acquired:
		if is_instance_valid(b) and BulletPool != null:
			BulletPool.release(b)
	_acquired.clear()
	_holder = null


# --- Helpers ------------------------------------------------------------

func _acquire_player(pos: Vector2) -> Bullet:
	var b: Bullet = BulletPool.acquire("player", pos, _holder)
	_acquired.append(b)
	return b


func _acquire_enemy(pos: Vector2) -> Bullet:
	var b: Bullet = BulletPool.acquire("enemy", pos, _holder)
	_acquired.append(b)
	return b


# --- Movement direction per faction ------------------------------------

func test_player_bullet_moves_up() -> void:
	var b: Bullet = _acquire_player(Vector2(100, 200))
	b._physics_process(0.1)
	assert_lt(b.position.y, 200.0, "Player bullet should move up (y decreases)")
	assert_almost_eq(b.position.x, 100.0, 0.001, "Player bullet should not drift on x")


func test_enemy_bullet_moves_down() -> void:
	var b: Bullet = _acquire_enemy(Vector2(100, 200))
	b._physics_process(0.1)
	assert_gt(b.position.y, 200.0, "Enemy bullet should move down (y increases)")
	assert_almost_eq(b.position.x, 100.0, 0.001, "Enemy bullet should not drift on x")


func test_player_bullet_direction_is_vector2_up() -> void:
	var b: Bullet = _acquire_player(Vector2.ZERO)
	assert_eq(b.direction, Vector2.UP, "Player bullet direction should be Vector2.UP")


func test_enemy_bullet_direction_is_vector2_down() -> void:
	var b: Bullet = _acquire_enemy(Vector2.ZERO)
	assert_eq(b.direction, Vector2.DOWN, "Enemy bullet direction should be Vector2.DOWN")


# --- Visual color per faction ------------------------------------------

func test_player_bullet_uses_cyan_color() -> void:
	var b: Bullet = _acquire_player(Vector2.ZERO)
	var visual: Sprite2D = b.get_node("Visual")
	assert_almost_eq(visual.modulate.r, BULLET_SCRIPT.PLAYER_COLOR.r, 0.01,
		"player red channel")
	assert_almost_eq(visual.modulate.g, BULLET_SCRIPT.PLAYER_COLOR.g, 0.01,
		"player green channel")
	assert_almost_eq(visual.modulate.b, BULLET_SCRIPT.PLAYER_COLOR.b, 0.01,
		"player blue channel")


func test_enemy_bullet_uses_orange_color() -> void:
	var b: Bullet = _acquire_enemy(Vector2.ZERO)
	var visual: Sprite2D = b.get_node("Visual")
	assert_almost_eq(visual.modulate.r, BULLET_SCRIPT.ENEMY_COLOR.r, 0.01,
		"enemy red channel")
	assert_almost_eq(visual.modulate.g, BULLET_SCRIPT.ENEMY_COLOR.g, 0.01,
		"enemy green channel")
	assert_almost_eq(visual.modulate.b, BULLET_SCRIPT.ENEMY_COLOR.b, 0.01,
		"enemy blue channel")


# --- Screen-edge despawn -----------------------------------------------

func test_screen_exit_releases_player_bullet_to_pool() -> void:
	var b: Bullet = _acquire_player(Vector2(1000, 1000))
	assert_eq(b.get_parent(), _holder, "Bullet should be parented to the test holder")
	b._on_screen_exited()
	assert_ne(b.get_parent(), _holder,
		"Bullet should no longer be parented to holder after screen exit")
	var stats: Dictionary = BulletPool.get_stats()
	assert_gte(int(stats["player"]["free"]), 1,
		"Player pool free count should be >= 1 after release")
	# Remove from local tracking so after_each doesn't double-release.
	_acquired.erase(b)


func test_screen_exit_releases_enemy_bullet_to_pool() -> void:
	var b: Bullet = _acquire_enemy(Vector2(1000, 1000))
	b._on_screen_exited()
	var stats: Dictionary = BulletPool.get_stats()
	assert_gte(int(stats["enemy"]["free"]), 1,
		"Enemy pool free count should be >= 1 after release")
	_acquired.erase(b)


# --- Collision: body_entered -------------------------------------------

func test_player_bullet_body_entered_damages_enemy_target() -> void:
	var b: Bullet = _acquire_player(Vector2.ZERO)
	var target: Node2D = _DAMAGE_TARGET.new()
	target.add_to_group("enemies")
	add_child_autofree(target)
	b._on_body_entered(target)
	assert_eq(target.last_damage, b.damage, "Enemy target should take bullet.damage")
	assert_eq(b.get_parent(), null, "Bullet should be released (no parent) after hit")
	_acquired.erase(b)


func test_enemy_bullet_body_entered_damages_player_target() -> void:
	var b: Bullet = _acquire_enemy(Vector2.ZERO)
	var target: Node2D = _DAMAGE_TARGET.new()
	target.add_to_group("player")
	add_child_autofree(target)
	b._on_body_entered(target)
	assert_eq(target.last_damage, b.damage, "Player target should take enemy bullet damage")
	assert_eq(b.get_parent(), null, "Enemy bullet should be released after hitting player")
	_acquired.erase(b)


func test_player_bullet_does_not_hit_another_player() -> void:
	var b: Bullet = _acquire_player(Vector2.ZERO)
	var ally: Node2D = _DAMAGE_TARGET.new()
	ally.add_to_group("player")
	add_child_autofree(ally)
	b._on_body_entered(ally)
	assert_eq(ally.last_damage, 0, "Player bullet should not damage same-faction target")
	assert_eq(b.get_parent(), _holder,
		"Bullet should remain in tree (not released) when friendly-fire is filtered")


func test_bullet_does_not_hit_other_bullets() -> void:
	# `other` is a Bullet (not a _DAMAGE_TARGET), so it has no `last_damage`
	# field. The contract we want to assert is that the source bullet stays
	# in the tree because `_can_hit` correctly filters out other bullets.
	var b: Bullet = _acquire_player(Vector2.ZERO)
	var other: Bullet = _acquire_enemy(Vector2.ZERO)
	b._on_body_entered(other)
	assert_eq(b.get_parent(), _holder, "Bullet should not be released on bullet-on-bullet")


# --- Collision: area_entered -------------------------------------------

func test_player_bullet_area_entered_damages_enemy_area() -> void:
	var b: Bullet = _acquire_player(Vector2.ZERO)
	var target: Node2D = _DAMAGE_TARGET.new()
	target.add_to_group("enemies")
	add_child_autofree(target)
	b._on_area_entered(target)
	assert_eq(target.last_damage, b.damage, "Enemy area target should take bullet damage")
	assert_eq(b.get_parent(), null, "Bullet should be released after hitting an area")
	_acquired.erase(b)


func test_bullet_area_entered_does_not_damage_null_target() -> void:
	var b: Bullet = _acquire_player(Vector2.ZERO)
	# Should not crash; bullet should NOT be released (no target to hit).
	b._on_area_entered(null)
	assert_eq(b.get_parent(), _holder, "Bullet should stay in tree if target is null")


# --- Pool reuse --------------------------------------------------------

func test_pool_reuse_returns_same_instance_after_release() -> void:
	var first: Bullet = _acquire_player(Vector2(10, 20))
	var first_id: int = first.get_instance_id()
	BulletPool.release(first)
	_acquired.erase(first)
	var second: Bullet = BulletPool.acquire("player", Vector2(30, 40), _holder)
	_acquired.append(second)
	assert_eq(second.get_instance_id(), first_id,
		"Pool should hand back the same bullet instance after release")


func test_pool_reuse_does_not_grow_total() -> void:
	var b1: Bullet = _acquire_player(Vector2.ZERO)
	var total_after_first: int = BulletPool.get_total("player")
	BulletPool.release(b1)
	_acquired.erase(b1)
	var b2: Bullet = _acquire_player(Vector2.ZERO)
	_acquired.append(b2)
	var total_after_second: int = BulletPool.get_total("player")
	assert_eq(total_after_second, total_after_first,
		"Pool reuse should not grow total bullet count for the faction")


func test_pool_per_faction_stats_are_separate() -> void:
	var p: Bullet = _acquire_player(Vector2.ZERO)
	var e: Bullet = _acquire_enemy(Vector2.ZERO)
	assert_eq(p.faction, "player", "Acquired player bullet should be faction 'player'")
	assert_eq(e.faction, "enemy", "Acquired enemy bullet should be faction 'enemy'")
	var stats: Dictionary = BulletPool.get_stats()
	assert_has(stats, "player", "Stats should include 'player' key")
	assert_has(stats, "enemy", "Stats should include 'enemy' key")
	assert_gte(int(stats["player"]["alive"]), 1, "Player alive count should be >= 1")
	assert_gte(int(stats["enemy"]["alive"]), 1, "Enemy alive count should be >= 1")


# --- Default state ----------------------------------------------------

func test_bullet_default_state_matches_contract() -> void:
	var b: Bullet = _acquire_player(Vector2.ZERO)
	assert_eq(b.faction, "player", "Default faction after pool setup should be 'player'")
	assert_eq(b.speed, b.PLAYER_SPEED, "Default player speed should match PLAYER_SPEED")
	assert_eq(b.damage, b.DEFAULT_DAMAGE, "Default damage should match DEFAULT_DAMAGE")
	assert_true(b.is_in_group("bullets"), "Bullet should be in 'bullets' group")
