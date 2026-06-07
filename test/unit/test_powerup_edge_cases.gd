extends GutTest
## Edge-case tests for the power-up system. Complements the 45 main
## tests in test_powerup.gd. These cover behaviors the main suite
## doesn't explicitly assert:
##   - BOMB on an empty scene (no bullets, no enemies) is a no-op
##   - Re-applying a shot-type to a held one refreshes duration
##   - Respawning the player clears all timed powerups and resets
##     shot_type / speed_multiplier
##   - Powerup drift via _physics_process
##   - apply_powerup rejects unknown kinds
##
## Tests here are isolated: each test sets up a fresh Main + Player.

const POWERUP_SCRIPT := preload("res://scripts/powerup.gd")
const MAIN_SCRIPT := preload("res://scripts/main.gd")

var _main: Node = null
var _holder: Node = null
var _acquired_bullets: Array = []


func before_each() -> void:
	# Clean up stray bullets so the pool doesn't grow across tests.
	if BulletPool != null:
		for b: Node in get_tree().get_nodes_in_group("bullets"):
			if is_instance_valid(b) and b.get_parent() != null:
				BulletPool.release(b)
	_main = MAIN_SCRIPT.new()
	add_child_autofree(_main)
	_holder = Node.new()
	_holder.name = "EdgeTestHolder"
	add_child_autofree(_holder)
	_acquired_bullets = []


func after_each() -> void:
	for b in _acquired_bullets:
		if is_instance_valid(b) and BulletPool != null:
			BulletPool.release(b)
	_acquired_bullets.clear()
	_main = null
	_holder = null


# --- BOMB on empty scene ----------------------------------------------

func test_bomb_on_empty_scene_is_noop() -> void:
	assert_eq(_main.get_enemy_count(), 0, "No enemies initially")
	assert_eq(_main.score, 0, "Score starts at 0")
	_main.apply_powerup(Powerup.Kind.BOMB, _main.player, null)
	assert_eq(_main.get_enemy_count(), 0,
		"Bomb on empty scene should leave enemy count at 0")
	assert_eq(_main.score, 0, "Bomb on empty scene should not award score")


# --- Re-applying a held shot-type refreshes duration -------------------

func test_reapplying_double_shot_refreshes_duration_to_15() -> void:
	_main.player.apply_powerup(Powerup.Kind.DOUBLE_SHOT)
	_main.player._tick_powerups(7.0)
	var partial: float = float(_main.player.active_powerups[Powerup.Kind.DOUBLE_SHOT])
	assert_almost_eq(partial, 8.0, 0.01,
		"After 7s tick, DOUBLE_SHOT should have ~8s remaining")
	_main.player.apply_powerup(Powerup.Kind.DOUBLE_SHOT)
	var refreshed: float = float(_main.player.active_powerups[Powerup.Kind.DOUBLE_SHOT])
	assert_almost_eq(refreshed, 15.0, 0.01,
		"Re-applying DOUBLE_SHOT should refresh duration to 15s")
	assert_eq(_main.player.shot_type, "double",
		"shot_type should remain 'double' after refresh")


# --- Respawn clears powerups ------------------------------------------

func test_respawn_clears_shot_type_powerup() -> void:
	_main.player.apply_powerup(Powerup.Kind.DOUBLE_SHOT)
	assert_eq(_main.player.shot_type, "double", "Pre-respawn shot_type")
	assert_true(_main.player.active_powerups.has(Powerup.Kind.DOUBLE_SHOT),
		"Pre-respawn active_powerups should hold DOUBLE_SHOT")
	_main.player.respawn()
	assert_eq(_main.player.shot_type, "single",
		"Respawn should reset shot_type to 'single'")
	assert_false(_main.player.active_powerups.has(Powerup.Kind.DOUBLE_SHOT),
		"Respawn should clear DOUBLE_SHOT from active_powerups")


func test_respawn_clears_speed_boost() -> void:
	_main.player.apply_powerup(Powerup.Kind.SPEED_BOOST)
	assert_almost_eq(_main.player.speed_multiplier, 1.4, 0.001,
		"Pre-respawn speed_multiplier")
	_main.player.respawn()
	assert_almost_eq(_main.player.speed_multiplier, 1.0, 0.001,
		"Respawn should reset speed_multiplier to 1.0")
	assert_false(_main.player.active_powerups.has(Powerup.Kind.SPEED_BOOST),
		"Respawn should clear SPEED_BOOST from active_powerups")


# --- Powerup drift ----------------------------------------------------

func test_powerup_drifts_down_after_spawn() -> void:
	var p: Node = _main.spawn_powerup(Powerup.Kind.DOUBLE_SHOT, Vector2(100, 50))
	assert_not_null(p, "powerup should spawn")
	var initial_y: float = p.global_position.y
	p._physics_process(1.0)
	assert_almost_eq(p.global_position.y, initial_y + 80.0, 0.5,
		"Powerup should drift down at FALL_SPEED px/s")


# --- apply_powerup rejects unknown kinds ------------------------------

func test_apply_powerup_unknown_kind_is_noop() -> void:
	var initial_shot: String = _main.player.shot_type
	var initial_active_size: int = _main.player.active_powerups.size()
	_main.player.apply_powerup(99, null)
	assert_eq(_main.player.shot_type, initial_shot,
		"Unknown kind should not change shot_type")
	assert_eq(_main.player.active_powerups.size(), initial_active_size,
		"Unknown kind should not add to active_powerups")
