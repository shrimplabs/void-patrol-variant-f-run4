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
## Emitted whenever the active power-up set changes (kind added, expired,
## or replaced). Listeners (main.gd → HUD) get the kind, the type name
## for display, and the remaining duration (0 = instant).
signal powerup_changed(kind: int, type_name: String, remaining: float)

@export var speed: float = 320.0
@export var max_shield: float = 100.0
@export var max_lives: int = 3
@export var fire_rate: float = 0.3
## Multiplier applied to `speed` while a SPEED_BOOST is active.
@export var speed_boost_multiplier: float = 1.4
## If null, auto-fire does nothing. Set in player.tscn.
@export var bullet_scene: PackedScene
## Offset from the ship center where bullets spawn.
@export var bullet_spawn_offset: Vector2 = Vector2(0, -16)
## Lateral offset (px) for DOUBLE_SHOT secondary bullets. Tuned so the
## two bullets don't overlap a single-target enemy.
@export var double_shot_lateral_offset: float = 10.0
## Spread angle (degrees) for TRIPLE_SPREAD outer bullets.
@export var triple_spread_angle_deg: float = 12.0
## Fire rate while LASER is active (faster than default 0.3s).
@export var laser_fire_rate: float = 0.08

var shield: float = max_shield
var lives: int = max_lives
var _fire_cooldown: float = 0.0
var _alive: bool = true

## Current shot pattern. One of "single" / "double" / "triple" / "laser".
## A shot-type power-up (DOUBLE_SHOT / TRIPLE_SPREAD / LASER) sets this;
## "single" is the default. Mutually exclusive: a new shot-type pickup
## replaces the previous shot-type.
var shot_type: String = "single"
## Active speed multiplier (1.0 = no boost). SET by SPEED_BOOST, RESET
## to 1.0 when the boost expires.
var speed_multiplier: float = 1.0
## Active powerups by kind. The value is the *remaining* duration in
## seconds. Kinds not in this dict are inactive. SHIELD_BOOST and BOMB
## are instant and never appear here. SPEED_BOOST and the three
## shot-type powerups are timed.
var active_powerups: Dictionary = {}


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
	_tick_powerups(delta)


func _update_movement(delta: float) -> void:
	var dir := _read_movement_input()
	velocity = dir * speed * speed_multiplier
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


## Cached lookup of the BulletPool autoload. Resolved on first use and
## reused thereafter so we don't pay the node-path lookup cost per shot.
## Bare `BulletPool` is also a global identifier in the autoloaded scene
## tree, but using it directly in script expressions fails to compile in
## contexts where the autoload table is empty (e.g. `--script` /
## `--check-only` headless invocations), so we go through the SceneTree
## instead. Tests can still access the autoload by its registered name
## `BulletPool` -- this lookup is for self-containment.
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


func _update_fire(delta: float) -> void:
	# Fire if EITHER the pool is wired up OR a fallback bullet_scene was set.
	var pool := _resolve_bullet_pool()
	var can_fire: bool = (pool != null and pool.has_method("acquire")) \
		or bullet_scene != null
	if not can_fire:
		return
	_fire_cooldown -= delta
	if _fire_cooldown <= 0.0:
		_fire()
		_fire_cooldown = _current_fire_rate()


func _current_fire_rate() -> float:
	# LASER is a continuous-fire mode with a much faster cadence.
	if shot_type == "laser":
		return laser_fire_rate
	return fire_rate


func _fire() -> void:
	# Dispatch on shot_type. Each branch produces 1 / 2 / 3 bullets in the
	# right pattern. All bullets fire upward (player bullets travel up).
	match shot_type:
		"double":
			_fire_bullet_at(global_position + bullet_spawn_offset + Vector2(-double_shot_lateral_offset, 0))
			_fire_bullet_at(global_position + bullet_spawn_offset + Vector2(double_shot_lateral_offset, 0))
		"triple":
			var rad := deg_to_rad(triple_spread_angle_deg)
			_fire_bullet_at(global_position + bullet_spawn_offset)
			_fire_bullet_angled(Vector2.UP.rotated(-rad))
			_fire_bullet_angled(Vector2.UP.rotated(rad))
		"laser":
			# Lasers behave like single shots but at high cadence. The
			# "infinite pierce" is currently visual / design-doc; the
			# bullet system uses is_instance_valid for friendly-fire
			# filtering, so we just fire straight up at laser speed.
			_fire_bullet_at(global_position + bullet_spawn_offset)
		_:
			_fire_bullet_at(global_position + bullet_spawn_offset)


## Spawn one bullet at an absolute world position, traveling straight up.
func _fire_bullet_at(world_pos: Vector2) -> void:
	var b := _spawn_bullet(world_pos)
	if b != null:
		fired.emit(b)


## Spawn one bullet traveling in an arbitrary direction (used for
## TRIPLE_SPREAD). The bullet's `direction` is set after acquire so the
## pool's faction-based default doesn't override us.
func _fire_bullet_angled(direction: Vector2) -> void:
	var b := _spawn_bullet(global_position + bullet_spawn_offset)
	if b != null and "direction" in b:
		b.direction = direction.normalized()
	if b != null:
		fired.emit(b)


## Lower-level: acquire a bullet from the pool (or instantiate via the
## scene fallback) and add it to the parent. Returns the bullet, or null
## on failure.
func _spawn_bullet(world_pos: Vector2) -> Node:
	var parent: Node = get_parent()
	if parent == null:
		return null
	# Prefer the BulletPool autoload (no per-shot allocation); fall back to a
	# direct instantiate if the pool is unavailable (e.g. test runs without
	# the autoload, or future scenes that need to bypass the pool).
	var pool := _resolve_bullet_pool()
	var b: Node = null
	if pool != null and pool.has_method("acquire"):
		b = pool.acquire("player", world_pos, parent)
	if b == null and bullet_scene != null:
		b = bullet_scene.instantiate()
		if b is Node2D:
			(b as Node2D).global_position = world_pos
		parent.add_child(b)
	return b


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
	# Respawn clears all timed powerups; non-shot and shot alike. Instant
	# pickups (SHIELD_BOOST) already fired on collect so they don't need
	# cleanup here.
	_reset_powerups()
	player_respawned.emit()


# ---------------------------------------------------------------------
# Power-up application
# ---------------------------------------------------------------------

## Apply a power-up of the given kind. The powerup node itself is the
## third argument (for context); effects are routed through the player's
## own state, not the pickup node, so this method is callable directly
## from tests.
##
## Shot-type contract: a new shot-type pickup REPLACES any prior shot-type.
## Non-shot pickups (SPEED_BOOST) coexist with shot-types and with each
## other.
func apply_powerup(kind: int, _powerup: Node = null) -> void:
	# Look up type metadata. We import Powerup's constants via the global
	# class_name (registered by check_scripts.gd in pass 1). Bare
	# `Powerup` reference is fine here because this method is only ever
	# called from gameplay code where the class is loaded.
	if not Powerup.TYPE_DATA.has(kind):
		push_warning("Player.apply_powerup: unknown kind %d" % kind)
		return
	var data: Dictionary = Powerup.TYPE_DATA[kind]
	var shot_type_value: String = str(data.get("shot_type", ""))
	var duration: float = float(data.get("duration", 0.0))
	var is_shot: bool = bool(data.get("is_shot_type", false))
	var name_str: String = str(data.get("name", "POWERUP"))

	if kind == Powerup.Kind.SHIELD_BOOST:
		# Instant: restore half the max shield, capped at max.
		var gain: float = max_shield * 0.5
		shield = min(max_shield, shield + gain)
		shield_changed.emit(shield, max_shield)
		# Emit a powerup_changed event with duration=0 so the HUD can
		# flash a tooltip-style "SHIELD BOOST" banner if it wants to.
		powerup_changed.emit(kind, name_str, 0.0)
		return

	if kind == Powerup.Kind.BOMB:
		# Bomb is handled by main.apply_powerup() before it gets here.
		# If it's routed here anyway, treat as a no-op (the player has no
		# per-state effect for BOMB).
		return

	if kind == Powerup.Kind.SPEED_BOOST:
		# Coexist with other speed boosts (refresh duration if re-collected).
		speed_multiplier = speed_boost_multiplier
		active_powerups[kind] = duration
		powerup_changed.emit(kind, name_str, duration)
		return

	# Shot-type pickup. Drop any existing shot-type and install the new one.
	if is_shot and shot_type_value != "":
		# Remove every prior shot-type from the active set, so the dict
		# invariant holds "at most one shot-type active".
		for prior_kind in [Powerup.Kind.DOUBLE_SHOT, Powerup.Kind.TRIPLE_SPREAD, Powerup.Kind.LASER]:
			if prior_kind != kind and active_powerups.has(prior_kind):
				active_powerups.erase(prior_kind)
		shot_type = shot_type_value
		active_powerups[kind] = duration
		# If the new fire rate is faster than the current cooldown,
		# snap the cooldown so the next fire happens immediately. This
		# makes the upgrade feel snappy.
		if _fire_cooldown > _current_fire_rate():
			_fire_cooldown = _current_fire_rate()
		powerup_changed.emit(kind, name_str, duration)


## Tick down all active powerups; remove expired entries and reset the
## related state (shot_type → "single", speed_multiplier → 1.0).
## Emits a `powerup_changed` signal with remaining=0 for each kind that
## expires so listeners (HUD) can clear their display.
func _tick_powerups(delta: float) -> void:
	if active_powerups.is_empty():
		return
	var expired: Array = []
	for k in active_powerups.keys():
		var remaining: float = float(active_powerups[k]) - delta
		if remaining <= 0.0:
			expired.append(k)
		else:
			active_powerups[k] = remaining
	for k in expired:
		active_powerups.erase(k)
		# Restore defaults.
		if k == Powerup.Kind.DOUBLE_SHOT or k == Powerup.Kind.TRIPLE_SPREAD or k == Powerup.Kind.LASER:
			shot_type = "single"
		elif k == Powerup.Kind.SPEED_BOOST:
			speed_multiplier = 1.0
		# Look up the type name (or fall back to a placeholder) for the
		# expire notification.
		var nm: String = "POWERUP"
		if Powerup.TYPE_DATA.has(k):
			nm = str(Powerup.TYPE_DATA[k].get("name", "POWERUP"))
		powerup_changed.emit(k, nm, 0.0)


## Drop every timed powerup and reset dependent state. Used by respawn()
## so the player doesn't keep an expired DOUBLE_SHOT across a life loss.
func _reset_powerups() -> void:
	var kinds := active_powerups.keys().duplicate()
	active_powerups.clear()
	shot_type = "single"
	speed_multiplier = 1.0
	# Fire the expire notification for each cleared powerup so the HUD
	# drops the label.
	for k in kinds:
		var nm: String = "POWERUP"
		if Powerup.TYPE_DATA.has(k):
			nm = str(Powerup.TYPE_DATA[k].get("name", "POWERUP"))
		powerup_changed.emit(k, nm, 0.0)


## Public: the "primary" active powerup for HUD display. Returns the
## first entry from `active_powerups` (insertion order), or a sentinel
## dict if none are active. Used by main.gd → HUD to drive the
## "POWERUP  12.3s" label.
func get_primary_powerup() -> Dictionary:
	if active_powerups.is_empty():
		return {"kind": -1, "name": "", "remaining": 0.0}
	# Use keys()[0] to preserve insertion order (DOUBLE_SHOT picked up
	# before TRIPLE_SPREAD shows as DOUBLE_SHOT, etc.).
	var first_key: int = int(active_powerups.keys()[0])
	var nm: String = "POWERUP"
	if Powerup.TYPE_DATA.has(first_key):
		nm = str(Powerup.TYPE_DATA[first_key].get("name", "POWERUP"))
	return {
		"kind": first_key,
		"name": nm,
		"remaining": float(active_powerups[first_key]),
	}


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
		"shot_type": shot_type,
		"speed_multiplier": speed_multiplier,
		"active_powerups": active_powerups.duplicate(),
	}
