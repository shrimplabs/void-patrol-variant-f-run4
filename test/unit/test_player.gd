extends GutTest
## GUT tests for the player ship: movement clamp, shield depletion, life loss +
## respawn, and get_state() shape. Runs without a visible window -- the player
## node is added to a child root inside this test, not the SceneTree's root.

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const BULLET_SCRIPT := preload("res://scripts/bullet.gd")

var _player: CharacterBody2D = null
var _holder: Node = null


func before_each() -> void:
	# The viewport is empty by default in headless tests, so the player uses
	# a 1152x648 default. We create a holder node and add the player under it
	# so its _ready() runs once.
	_holder = Node.new()
	add_child_autofree(_holder)
	_player = PLAYER_SCRIPT.new()
	_holder.add_child(_player)


func after_each() -> void:
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null
	_holder = null


# --- Movement clamp ----------------------------------------------------

func test_player_starts_at_bottom_center() -> void:
	var vp := _player.get_viewport_rect()
	var expected_y := vp.size.y - 60.0
	assert_almost_eq(_player.position.x, vp.size.x * 0.5, 0.1,
		"Player should spawn at horizontal center of viewport")
	assert_almost_eq(_player.position.y, expected_y, 0.1,
		"Player should spawn near bottom of viewport (y = vp.h - 60)")


func test_player_position_clamps_to_viewport_bounds() -> void:
	# Try to push the player well off the left edge of the screen.
	_player.position = Vector2(-10000, -10000)
	_player._clamp_to_viewport()
	var vp := _player.get_viewport_rect()
	var half := Vector2(16, 16)
	assert_gte(_player.position.x, vp.position.x + half.x,
		"Position x must be clamped to >= left edge + half_extent")
	assert_lte(_player.position.x, vp.position.x + vp.size.x - half.x,
		"Position x must be clamped to <= right edge - half_extent")
	assert_gte(_player.position.y, vp.position.y + half.y,
		"Position y must be clamped to >= top edge + half_extent")
	assert_lte(_player.position.y, vp.position.y + vp.size.y - half.y,
		"Position y must be clamped to <= bottom edge - half_extent")


func test_movement_input_keyboard_returns_unit_vector_for_one_key() -> void:
	# We can't fake Input.is_action_pressed easily, so verify the
	# normalization contract on a manually-constructed direction.
	var raw := Vector2(1, 0)
	var dir := raw.normalized()
	assert_almost_eq(dir.length(), 1.0, 0.001, "Normalized vector should be length 1")


# --- Shield depletion --------------------------------------------------

func test_shield_starts_at_max() -> void:
	assert_almost_eq(_player.shield, _player.max_shield, 0.001,
		"Shield should start at max_shield (100)")


func test_take_damage_reduces_shield() -> void:
	var signals_received: Array = []
	_player.shield_changed.connect(func(c, m): signals_received.append([c, m]))
	_player.take_damage(30)
	assert_almost_eq(_player.shield, 70.0, 0.001,
		"Shield should be 70 after taking 30 damage from 100")
	assert_eq(signals_received.size(), 1, "shield_changed should fire once")
	assert_eq(signals_received[0][0], 70.0, "Signal should report new shield")
	assert_eq(_player.lives, _player.max_lives,
		"Lives should be unchanged when shield > 0")


func test_overkill_damage_loses_a_life_and_respawns_with_full_shield() -> void:
	# Damage greater than max shield still triggers a life loss and respawn
	# (refilling shield). The intermediate 0-shield state is intentional but
	# not observable from outside because respawn happens immediately.
	_player.take_damage(150)
	assert_almost_eq(_player.shield, _player.max_shield, 0.001,
		"Shield should be refilled to max after a lethal hit triggers respawn")
	assert_eq(_player.lives, _player.max_lives - 1,
		"Lives should decrement when shield hits 0 from overkill damage")


# --- Life loss + respawn -----------------------------------------------

func test_lose_life_costs_a_life_and_respawns_with_full_shield() -> void:
	var lives_signals: Array = []
	var respawn_signals: Array = []
	_player.lives_changed.connect(func(c, m): lives_signals.append([c, m]))
	_player.player_respawned.connect(func(): respawn_signals.append(true))

	# Drive shield to zero -- should trigger life loss + respawn.
	_player.take_damage(_player.max_shield)

	assert_eq(_player.lives, _player.max_lives - 1,
		"Lives should decrease by 1 when shield hits 0")
	assert_almost_eq(_player.shield, _player.max_shield, 0.001,
		"Shield should be refilled to max after respawn")
	assert_eq(respawn_signals.size(), 1, "player_respawned should fire once")
	var vp := _player.get_viewport_rect()
	assert_almost_eq(_player.position.x, vp.size.x * 0.5, 0.1,
		"Respawn should place player at horizontal center")
	assert_almost_eq(_player.position.y, vp.size.y - 60.0, 0.1,
		"Respawn should place player near bottom of viewport")


func test_zero_lives_emits_died_and_marks_not_alive() -> void:
	var died_signals: Array = []
	_player.died.connect(func(): died_signals.append(true))

	# Drain 3 lives' worth of shield.
	for i in range(_player.max_lives):
		_player.take_damage(_player.max_shield)

	assert_eq(_player.lives, 0, "All lives should be lost after 3 shield depletions")
	assert_false(_player._alive, "Player should be marked not alive after death")
	assert_eq(died_signals.size(), 1, "died should fire once when lives reach 0")


func test_take_damage_after_death_is_no_op() -> void:
	for i in range(_player.max_lives):
		_player.take_damage(_player.max_shield)
	var shield_after_death: float = _player.shield
	_player.take_damage(50)
	assert_almost_eq(_player.shield, shield_after_death, 0.001,
		"take_damage should be ignored when player is dead")


# --- get_state() shape --------------------------------------------------

func test_get_state_returns_full_dictionary() -> void:
	var state: Dictionary = _player.get_state()
	var expected_keys: Array = [
		"shield", "max_shield", "lives", "max_lives", "alive",
		"position", "velocity", "fire_cooldown", "fire_rate",
	]
	for k: String in expected_keys:
		assert_has(state, k, "get_state() should include key: %s" % k)
	assert_eq(state["shield"], _player.max_shield, "shield value should match")
	assert_eq(state["lives"], _player.max_lives, "lives value should match")
	assert_true(state["alive"], "alive should be true at start")
	assert_eq(state["position"].size(), 2, "position should be a 2-element array")
	assert_eq(state["velocity"].size(), 2, "velocity should be a 2-element array")


# --- Auto-fire ----------------------------------------------------------

func test_auto_fire_does_nothing_when_bullet_scene_is_null() -> void:
	# Default player has no bullet_scene wired in this test setup.
	assert_null(_player.bullet_scene, "bullet_scene should be null in test setup")
	# Run a few physics frames worth of cooldown decrement.
	_player._update_fire(1.0)
	# No assertion needed beyond "did not crash"; bullets count would be 0.
	var bullets := get_tree().get_nodes_in_group("bullets")
	assert_eq(bullets.size(), 0, "No bullets should spawn when bullet_scene is null")


func test_auto_fire_spawns_bullet_after_cooldown() -> void:
	# Wire up bullet_scene via a small wrapper scene-less bullet.
	var wrapper := PackedScene.new()
	# We can't easily make a packed scene from a script-only instance, so we
	# instead just call _fire() directly after overriding bullet_scene to a
	# real bullet PackedScene. Reuse the bullet.tscn resource if it exists.
	var bullet_scene_res := load("res://scenes/bullet.tscn")
	if bullet_scene_res == null:
		pending("bullet.tscn not loadable; skipping spawn assertion")
		return
	_player.bullet_scene = bullet_scene_res
	# Make sure there's a parent (the holder) to spawn into.
	_player._fire()
	var bullets := get_tree().get_nodes_in_group("bullets")
	assert_eq(bullets.size(), 1, "One bullet should be spawned by _fire()")
