extends "res://scripts/enemy_base.gd"
class_name EnemyFighter

## Fighter enemy: mid-tier threat.
##  - 2 HP, takes two player bullets to kill.
##  - Lateral weave: oscillates a small sine-like x offset while drifting down.
##  - Aimed single shot: fires an enemy bullet straight at the player position
##    on each fire_interval tick.
##  - 25 points on kill.

## Amplitude of the lateral weave in pixels (peak-to-peak / 2).
@export var weave_amplitude: float = 32.0
## Period of the weave in seconds (full left-right cycle).
@export var weave_period: float = 1.4
## Base downward speed (added on top of weave component).
@export var down_speed: float = 100.0

## Internal phase counter for the sine weave. 0..1 over a full period.
var _weave_phase: float = 0.0
## Cached reference to the player (resolved on _ready via "player" group).
## When the player is absent (tests, etc.) we fall back to a fixed down direction.
var _player_ref: Node2D = null
## Stable type identifier; matches a key in main.gd.ENEMY_SCENES.
var enemy_type_name: String = "fighter"


func _ready() -> void:
	# Apply type-specific stats before the base wires signals.
	max_hp = 2
	score_value = 25
	move_speed = down_speed  # base speed; per-frame direction handles weave
	fire_interval = 1.2
	contact_damage = 1
	_movement_dir = Vector2.DOWN
	enemy_type_name = "fighter"
	super._ready()
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
	# Advance weave phase and recompute the per-frame movement direction.
	_weave_phase += delta / max(0.001, weave_period)
	if _weave_phase >= 1.0:
		_weave_phase -= 1.0
	var x := sin(_weave_phase * TAU) * weave_amplitude
	_movement_dir = Vector2(x, down_speed).normalized()
	# Delegate to the base for position update + fire cooldown tick.
	super._physics_process(delta)


## Aimed single shot: one bullet straight toward the player (or straight
## down if the player is missing).
func _fire_pattern() -> void:
	var dir := _aim_direction()
	_spawn_enemy_bullet(dir)


func _aim_direction() -> Vector2:
	if _player_ref != null and is_instance_valid(_player_ref):
		var delta_pos := _player_ref.global_position - global_position
		if delta_pos.length() > 0.001:
			return delta_pos.normalized()
	return Vector2.DOWN


func _spawn_enemy_bullet(direction: Vector2) -> Node:
	if BulletPool == null or not BulletPool.has_method("acquire"):
		return null
	var parent := get_parent()
	if parent == null:
		return null
	return BulletPool.acquire("enemy", global_position, parent)
