extends "res://scripts/enemy_base.gd"
class_name Boss
## Multi-phase boss enemy for the Void Patrol finale.
##
## Behavior:
##  - 40 HP, 500 points on kill
##  - Enters from the top of the viewport, then sweeps horizontally
##    in a slow sine wave across the top of the arena
##  - 3 phases triggered by HP thresholds (against max_hp):
##      Phase 1 (100% - 60%): aimed shot at the player every 1.5s
##      Phase 2 (60%  - 30%): adds a 5-shot spread burst every 3s
##      Phase 3 (<30%):      adds a 12-bullet rotating ring every 5s
##  - Glowing core weak point: bullets hitting the central weak-point
##    area deal 2x damage (the body's area_entered signal applies 1x,
##    and the boss's area_shape_entered callback adds a matching extra
##    1x when the bullet lands on the weak point shape).
##  - On death, emits `defeated` and frees itself (the wave manager
##    listens via main.gd and transitions to COMPLETE/victory).
##
## The boss's Area2D has TWO collision shapes (body + weak point) and
## exposes them as `area_shape_entered`. The bullet's regular
## `area_entered` signal handles 1x damage; the boss adds 1x more for
## weak-point hits via the shape-index check.

signal defeated()

## Phase HP thresholds as fractions of max_hp. Phase changes happen
## when HP falls BELOW the threshold.
const PHASE_2_THRESHOLD := 0.60
const PHASE_3_THRESHOLD := 0.30
## Attack intervals (seconds).
const AIMED_SHOT_INTERVAL := 1.5
const SPREAD_BURST_INTERVAL := 3.0
const RING_INTERVAL := 5.0
## Spread burst fan-out (degrees from straight down).
const SPREAD_BURST_FAN_DEG := 18.0
## How many bullets per spread burst (center + 2 fanned = 3, but we use
## 5 for a denser fan; see _fire_spread_burst).
const SPREAD_BURST_COUNT := 5
## How many bullets in the rotating ring.
const RING_BULLET_COUNT := 12
## Speed of the boss's downward entry phase (px/s).
const ENTER_SPEED := 80.0
## Battle-row Y where the boss settles after the entry phase.
const BATTLE_Y := 96.0
## Peak horizontal sweep amplitude (px) from the centerline.
const SWEEP_AMPLITUDE := 220.0
## Period of the horizontal sine sweep (seconds per full cycle).
const SWEEP_PERIOD := 8.0
## Contact damage on a body hit (player walks into the boss).
const BOSS_CONTACT_DAMAGE := 2
## Shape index of the boss body on the Area2D's collision shapes list.
## The scene wires "body" as the first child CollisionShape2D and
## "WeakShape" as the second, so weak point = 1.
const WEAK_SHAPE_INDEX := 1

## Stable type identifier; matches the key in main.gd.ENEMY_SCENES.
var enemy_type_name: String = "boss"
## Current phase: 1, 2, or 3. Updated on HP threshold crossings.
var current_phase: int = 1
## Whether the boss has finished entering the screen.
var _entered: bool = false
## Sweep phase for the horizontal sine motion. 0..1 over a full period.
var _sweep_phase: float = 0.0
## Cooldown timers (per attack type).
var _aimed_cooldown: float = 0.0
var _spread_cooldown: float = 0.0
var _ring_cooldown: float = 0.0
## Cached reference to the player (resolved on _ready).
var _player_ref: Node2D = null


func _ready() -> void:
	# Apply boss-specific stats before the base wires signals.
	max_hp = 40
	score_value = 500
	move_speed = ENTER_SPEED
	fire_interval = 0.0  # we manage our own cooldowns
	contact_damage = BOSS_CONTACT_DAMAGE
	_movement_dir = Vector2.DOWN
	enemy_type_name = "boss"
	super._ready()
	# Stagger the first shot of each pattern so the boss doesn't unload
	# everything on frame 0. Aimed shot is staggered by half its
	# interval; spread and ring start on a small delay so they don't all
	# fire on the first tick.
	_aimed_cooldown = AIMED_SHOT_INTERVAL * 0.5
	_spread_cooldown = SPREAD_BURST_INTERVAL
	_ring_cooldown = RING_INTERVAL
	# Wire the shape-aware signal so we can detect weak-point hits and
	# add the extra 1x damage. The base class wires `body_entered` but
	# not `area_shape_entered`, so we connect it here.
	if not area_shape_entered.is_connected(_on_area_shape_entered):
		area_shape_entered.connect(_on_area_shape_entered)
	_resolve_player()


func _resolve_player() -> void:
	# Look up the player via the "player" group; in tests there may be no
	# player, in which case _aim_direction() falls back to straight down.
	var tree := get_tree()
	if tree == null:
		return
	var players := tree.get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node2D:
		_player_ref = players[0] as Node2D


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	# Movement: enter from the top until we reach the battle row, then
	# sweep horizontally. We bypass the base class's position update
	# (it does `position += _movement_dir * move_speed * delta`) by
	# setting position directly, since the boss's motion is fully
	# scripted and not velocity-driven.
	if not _entered:
		_movement_dir = Vector2.DOWN
		position += _movement_dir * move_speed * delta
		if position.y >= BATTLE_Y:
			position.y = BATTLE_Y
			_entered = true
			_sweep_phase = 0.0
	else:
		_sweep_phase += delta / max(0.001, SWEEP_PERIOD)
		if _sweep_phase >= 1.0:
			_sweep_phase -= 1.0
		var center_x := _arena_center_x()
		var x_offset: float = sin(_sweep_phase * TAU) * SWEEP_AMPLITUDE
		position = Vector2(center_x + x_offset, BATTLE_Y)
	# Tick attack cooldowns. The base class's _physics_process would
	# call _try_fire() but we set fire_interval=0 so it is a no-op;
	# the multi-phase cooldowns are managed here.
	_aimed_cooldown -= delta
	if _aimed_cooldown <= 0.0:
		_aimed_cooldown = AIMED_SHOT_INTERVAL
		_fire_aimed_shot()
	if current_phase >= 2:
		_spread_cooldown -= delta
		if _spread_cooldown <= 0.0:
			_spread_cooldown = SPREAD_BURST_INTERVAL
			_fire_spread_burst()
	if current_phase >= 3:
		_ring_cooldown -= delta
		if _ring_cooldown <= 0.0:
			_ring_cooldown = RING_INTERVAL
		_fire_rotating_ring()


## Compute the arena's horizontal center for the sweep. Falls back to
## the design-doc viewport width (1152) when no viewport is reachable
## (e.g. headless test fixture).
func _arena_center_x() -> float:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return 1152.0 * 0.5
	var vp_size: Vector2 = tree.root.size
	if vp_size.x <= 0.0:
		return 1152.0 * 0.5
	return vp_size.x * 0.5


## Apply damage to this boss. The bullet's `area_entered` signal will
## already have called this with the bullet's damage (1 by default), so
## the area_shape_entered handler adds 1 more for weak-point hits.
## We also re-evaluate the phase on every hit so crossing a threshold
## promotes the boss to the next attack pattern.
func take_damage(amount: int) -> int:
	var hp_before: int = hp
	var result: int = super.take_damage(amount)
	# Phase promotion. We use the post-damage HP so crossing a threshold
	# takes effect immediately (the next attack tick uses the new phase).
	if hp > 0:
		var hp_ratio: float = float(hp) / float(max_hp)
		if hp_ratio < PHASE_3_THRESHOLD and current_phase < 3:
			current_phase = 3
		elif hp_ratio < PHASE_2_THRESHOLD and current_phase < 2:
			current_phase = 2
	return result


## Called when the boss reaches 0 HP. Emits `defeated` BEFORE delegating
## to the base so listeners can read boss state (HP, position) while
## the node is still valid. The base then sets `_is_dead`, emits
## `died` (carrying the score value), and queue_frees the node.
##
## Order matters: we deliberately do NOT set `_is_dead = true` here --
## the base class does that. If we set it first, the base's `if
## _is_dead: return` guard short-circuits and `died` never fires,
## which breaks scoring on kill.
func _die() -> void:
	if _is_dead:
		return
	defeated.emit()
	super._die()


## Shape-aware entry callback. Fires when a bullet's Area2D enters one
## of the boss's collision shapes. The bullet's regular `area_entered`
## signal has ALREADY applied 1x damage to the boss; if the bullet hit
## the weak-point shape we add a matching 1x to make the total 2x.
## Damage is 1 (the player bullet's default) so we just take_damage(1).
func _on_area_shape_entered(_area_rid: RID, _area: Area2D, area_shape_index: int, _local_position: Vector2) -> void:
	if _is_dead:
		return
	if area_shape_index == WEAK_SHAPE_INDEX:
		# Bullet hit the core. Bullet's area_entered has applied 1;
		# add 1 more for the 2x total.
		take_damage(1)


# ---------------------------------------------------------------------
# Attack patterns
# ---------------------------------------------------------------------

## Aimed shot: one enemy bullet straight at the player (or down if no
## player is reachable). The basic attack from phase 1 onward.
##
## Guarded by `_is_dead` so the boss can't fire during its own death
## sequence (e.g. test fixtures that call fire methods directly after
## forcing take_damage(40)).
func _fire_aimed_shot() -> void:
	if _is_dead:
		return
	_spawn_enemy_bullet(_aim_direction())


## Spread burst: a fan of N bullets covering a 90-degree arc, fired
## from phase 2 onward. Centered on the player's direction so the
## player has to dodge laterally.
##
## Guarded by `_is_dead` -- see _fire_aimed_shot for the rationale.
func _fire_spread_burst() -> void:
	if _is_dead:
		return
	var base_dir := _aim_direction()
	# Build SPREAD_BURST_COUNT evenly-spaced directions across a 90deg
	# cone centered on base_dir.
	var arc: float = 90.0
	var step: float = arc / float(max(1, SPREAD_BURST_COUNT - 1))
	for i in range(SPREAD_BURST_COUNT):
		var deg_offset: float = -arc * 0.5 + step * float(i)
		var dir: Vector2 = base_dir.rotated(deg_to_rad(deg_offset))
		_spawn_enemy_bullet(dir)


## Rotating ring: 12 bullets in a full 360-degree circle, fired from
## phase 3 onward. Used to keep the player on their toes in the final
## phase. The "rotating" part is implemented as a constant
## even-spacing; the rotation is from the boss's own motion as it
## sweeps across the top.
##
## Guarded by `_is_dead` -- see _fire_aimed_shot for the rationale.
func _fire_rotating_ring() -> void:
	if _is_dead:
		return
	var step_angle: float = 360.0 / float(RING_BULLET_COUNT)
	for i in range(RING_BULLET_COUNT):
		var deg_offset: float = step_angle * float(i)
		var dir: Vector2 = Vector2.DOWN.rotated(deg_to_rad(deg_offset))
		_spawn_enemy_bullet(dir)


## Aimed direction toward the player. Falls back to straight down if
## the player is missing (e.g. in tests without a player node).
func _aim_direction() -> Vector2:
	if _player_ref != null and is_instance_valid(_player_ref):
		var delta_pos := _player_ref.global_position - global_position
		if delta_pos.length() > 0.001:
			return delta_pos.normalized()
	return Vector2.DOWN


# ---------------------------------------------------------------------
# Bullet pool plumbing (mirrors enemy_fighter.gd / enemy_bomber.gd)
# ---------------------------------------------------------------------

## Cached lookup of the BulletPool autoload. Resolved on demand (the
## autoload is only registered when the main scene is booted, so bare
## `BulletPool` references fail to compile in `--script` / `--check-only`
## headless invocations; we go through the SceneTree instead).
var _bullet_pool: Node = null


func _resolve_bullet_pool() -> Node:
	if _bullet_pool != null and is_instance_valid(_bullet_pool):
		return _bullet_pool
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.root
	if root == null:
		return null
	_bullet_pool = root.get_node_or_null("BulletPool")
	return _bullet_pool


func _spawn_enemy_bullet(direction: Vector2) -> Node:
	var pool := _resolve_bullet_pool()
	if pool == null or not pool.has_method("acquire"):
		return null
	var parent := get_parent()
	if parent == null:
		return null
	# Offset spawn slightly toward the bullet direction so the boss's
	# own collision shape doesn't immediately absorb its projectile.
	var spawn_pos: Vector2 = global_position + direction * 24.0
	return pool.acquire("enemy", spawn_pos, parent)


## Snapshot for the StateServer / tests. Includes boss-specific fields
## (phase, max_hp, weak-point multiplier) so the QA harness can tell
## the boss apart from a regular enemy.
func get_state() -> Dictionary:
	var base_state: Dictionary = super.get_state()
	base_state["type"] = "boss"
	base_state["current_phase"] = current_phase
	base_state["max_hp"] = max_hp
	base_state["score_value"] = score_value
	return base_state
