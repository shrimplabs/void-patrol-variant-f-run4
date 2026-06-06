extends CharacterBody2D
class_name Player

## Void Patrol player ship. Handles 4-directional movement (WASD/arrows OR mouse),
## auto-fire, shield, and lives. Loss of all shield costs a life and respawns the
## ship at bottom-center with full shield. Loss of all lives emits `died`.

signal shield_changed(current: float, max_value: float)
signal lives_changed(current: int, max_value: int)
signal life_lost(remaining_lives: int)
signal player_respawned()
signal fired(bullet: Node)
signal died()

@export var speed: float = 320.0
@export var max_shield: float = 100.0
@export var max_lives: int = 3
@export var fire_rate: float = 0.3
## If null, auto-fire does nothing. Set in player.tscn.
@export var bullet_scene: PackedScene
## Offset from the ship center where bullets spawn.
@export var bullet_spawn_offset: Vector2 = Vector2(0, -16)

var shield: float = max_shield
var lives: int = max_lives
var _fire_cooldown: float = 0.0
var _alive: bool = true


func _ready() -> void:
	add_to_group("player")
	shield = max_shield
	lives = max_lives
	_alive = true
	# Position at bottom-center on spawn.
	var vp_size := get_viewport_rect().size
	position = Vector2(vp_size.x * 0.5, vp_size.y - 60.0)
	# Initial signal broadcast so HUD can sync.
	shield_changed.emit(shield, max_shield)
	lives_changed.emit(lives, max_lives)


func _physics_process(delta: float) -> void:
	if not _alive:
		velocity = Vector2.ZERO
		return

	_update_movement(delta)
	_update_fire(delta)


func _update_movement(delta: float) -> void:
	var dir := _read_movement_input()
	velocity = dir * speed
	move_and_slide()
	_clamp_to_viewport()


func _read_movement_input() -> Vector2:
	# Mouse-aim mode: when left mouse is held, the ship steers toward the cursor.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var to_mouse := get_global_mouse_position() - global_position
		if to_mouse.length() > 4.0:
			return to_mouse.normalized()
		return Vector2.ZERO

	# Keyboard mode: WASD or arrow keys, 4-directional (no diagonal blend for
	# crisp arcade feel; up/down/left/right each map cleanly).
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	if Input.is_action_pressed("move_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("move_down"):
		dir.y += 1.0
	if dir.length() > 0.0:
		dir = dir.normalized()
	return dir


func _clamp_to_viewport() -> void:
	var vp := get_viewport_rect()
	var half := Vector2(16, 16)  # approximate ship half-extent
	position.x = clamp(position.x, vp.position.x + half.x, vp.position.x + vp.size.x - half.x)
	position.y = clamp(position.y, vp.position.y + half.y, vp.position.y + vp.size.y - half.y)


func _update_fire(delta: float) -> void:
	# Fire if EITHER the pool is wired up OR a fallback bullet_scene was set.
	var can_fire: bool = (BulletPool != null and BulletPool.has_method("acquire")) \
		or bullet_scene != null
	if not can_fire:
		return
	_fire_cooldown -= delta
	if _fire_cooldown <= 0.0:
		_fire()
		_fire_cooldown = fire_rate


func _fire() -> void:
	var spawn_pos: Vector2 = global_position + bullet_spawn_offset
	var parent: Node = get_parent()
	# Prefer the BulletPool autoload (no per-shot allocation); fall back to a
	# direct instantiate if the pool is unavailable (e.g. test runs without
	# the autoload, or future scenes that need to bypass the pool).
	var b: Node = null
	if BulletPool != null and BulletPool.has_method("acquire"):
		b = BulletPool.acquire("player", spawn_pos, parent)
	if b == null and bullet_scene != null:
		b = bullet_scene.instantiate()
		if b is Node2D:
			(b as Node2D).global_position = spawn_pos
		parent.add_child(b)
	if b != null:
		fired.emit(b)


## Apply damage. Returns the remaining shield.
func take_damage(amount: float) -> float:
	if not _alive:
		return shield
	shield = max(0.0, shield - amount)
	shield_changed.emit(shield, max_shield)
	if shield <= 0.0:
		_lose_life()
	return shield


func _lose_life() -> void:
	lives -= 1
	lives_changed.emit(lives, max_lives)
	if lives <= 0:
		_alive = false
		velocity = Vector2.ZERO
		died.emit()
		return
	life_lost.emit(lives)
	respawn()


## Respawn the ship at bottom-center with full shield. Used by both
## _lose_life() and any future "reset" path.
func respawn() -> void:
	var vp_size := get_viewport_rect().size
	position = Vector2(vp_size.x * 0.5, vp_size.y - 60.0)
	velocity = Vector2.ZERO
	shield = max_shield
	shield_changed.emit(shield, max_shield)
	_alive = true
	_fire_cooldown = 0.0
	player_respawned.emit()


## Snapshot of player state for the QA state server / HUD / tests.
func get_state() -> Dictionary:
	return {
		"shield": shield,
		"max_shield": max_shield,
		"lives": lives,
		"max_lives": max_lives,
		"alive": _alive,
		"position": [global_position.x, global_position.y],
		"velocity": [velocity.x, velocity.y],
		"fire_cooldown": _fire_cooldown,
		"fire_rate": fire_rate,
	}
