extends Area2D
class_name EnemyBase

## Base class for all enemy ships. Shared responsibilities:
##  - HP / damage tracking and on-death `died` signal
##  - Contact damage to the player (when player walks into us)
##  - Off-screen cleanup via VisibleOnScreenNotifier2D
##  - Optional fire pattern; subclasses override _fire_pattern()
##
## Subclasses specialize movement in `_physics_process` and fire in
## `_fire_pattern`. Movement direction is exposed as `_movement_dir` and
## `move_speed` so subclasses can swap it per-frame (e.g. fighter weave).
##
## Wiring:
##  - group "enemy" (singular) -- matches the friendly-fire filter in
##    bullet.gd, so player bullets can hit us and enemy bullets pass through.
##  - group "enemies" (plural) -- kept for legacy queries / wave manager list.

signal died(score_value: int)
signal hp_changed(current: int, max_value: int)

@export var max_hp: int = 1
@export var score_value: int = 10
@export var contact_damage: int = 1
## Seconds between shots. 0 (default) means "don't fire" -- used by the drone.
@export var fire_interval: float = 0.0
## Per-frame movement speed, in pixels/sec. Subclasses can override per type.
@export var move_speed: float = 120.0
## Movement direction in local space. Subclasses set this per frame.
var _movement_dir: Vector2 = Vector2.DOWN
## Current HP. Set in _ready from max_hp.
var hp: int = 1
## Tick-down timer for the next shot. 0 = ready to fire (if fire_interval > 0).
var _fire_cooldown: float = 0.0
## True after `died` has been emitted; prevents double-die on multi-hit frames.
var _is_dead: bool = false


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("enemies")
	hp = max_hp
	hp_changed.emit(hp, max_hp)
	if fire_interval > 0.0:
		_fire_cooldown = fire_interval
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	var notifier := get_node_or_null("VisibleOnScreenNotifier2D")
	if notifier:
		notifier.screen_exited.connect(_on_screen_exited)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	position += _movement_dir * move_speed * delta
	_try_fire(delta)


## Decrement the fire cooldown and call `_fire_pattern` when it hits zero.
## Exposed (not `_try_fire` private-name) so tests can call it directly to
## mock the timer and assert fire-pattern emission without sleeping.
func _try_fire(delta: float) -> void:
	if fire_interval <= 0.0:
		return
	_fire_cooldown -= delta
	if _fire_cooldown <= 0.0:
		_fire_cooldown = fire_interval
		_fire_pattern()


## Override in subclasses to spawn bullets. Default: do nothing (drone).
func _fire_pattern() -> void:
	pass


## Apply damage to this enemy. Returns the remaining HP. Emits `died` on 0 HP.
func take_damage(amount: int) -> int:
	if _is_dead:
		return hp
	hp = max(0, hp - amount)
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		_die()
	return hp


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	died.emit(score_value)
	# Remove from any active wave's tracking set; wave manager (task 0004)
	# listens for this signal and decrements its alive counter. We free here
	# so the enemy doesn't linger after the wave-clear callback.
	queue_free()


func _on_body_entered(body: Node) -> void:
	if _is_dead:
		return
	if body == null:
		return
	# Only the player takes contact damage from enemies.
	if not body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.take_damage(contact_damage)


func _on_screen_exited() -> void:
	# Off-screen enemies free themselves. Wave manager (0004) will hook the
	# `tree_exited` signal to decrement its alive count; this method only
	# handles the actual despawn.
	if _is_dead:
		return
	_is_dead = true
	queue_free()


## Snapshot for the StateServer / tests.
func get_state() -> Dictionary:
	return {
		"type": "enemy_base",
		"hp": hp,
		"max_hp": max_hp,
		"score_value": score_value,
		"position": [global_position.x, global_position.y],
		"is_dead": _is_dead,
	}
