extends Area2D
class_name Bullet

## Projectile used by both player and enemy ships.
## - Player bullets travel up (cyan); enemy bullets travel down (red/orange).
## - Movement direction is set by `setup(faction, position, speed)` when the
##   bullet is acquired from the pool, or assigned directly to `direction`.
## - Collisions call `take_damage` on the target then release back to the
##   pool (or `queue_free` if no pool is wired in).
## - A `VisibleOnScreenNotifier2D` child releases the bullet when it leaves
##   the viewport, so off-screen bullets never linger.

const PLAYER_COLOR: Color = Color(0.3, 0.9, 1.0, 1.0)
const ENEMY_COLOR: Color = Color(1.0, 0.45, 0.2, 1.0)
const PLAYER_SPEED: float = 600.0
const ENEMY_SPEED: float = 420.0
const DEFAULT_DAMAGE: int = 1
## Hard upper bound on how long a single bullet may live, in seconds.
## Acts as a safety net alongside the `VisibleOnScreenNotifier2D`
## `screen_exited` signal, which can fail to fire (e.g. when the notifier
## was spawned already off-screen, in headless mode without a real
## rendering pipeline, or with a degenerate Rect). At the player bullet's
## 600 px/s top speed this covers ~3000 px of travel, more than enough
## for any reasonable viewport; in practice bullets despawn on the
## notifier long before this cap.
const MAX_LIFETIME: float = 5.0

@export var speed: float = PLAYER_SPEED
@export var damage: int = DEFAULT_DAMAGE
## "player" or "enemy". Drives direction, color, and friendly-fire filter.
@export var faction: String = "player"
## Movement direction in local space. Pool sets this from faction in `setup()`.
@export var direction: Vector2 = Vector2.UP

## Back-reference to the BulletPool autoload (set by the pool on acquire).
## If null, the bullet queue_frees itself on despawn.
var pool: Node = null
## Last damage value this bullet received. Stays at 0 in normal play (friendly
## fire is filtered so bullets never damage each other), but is exposed so
## tests and tooling can assert "no damage applied" without inspecting
## another node's state.
var last_damage: int = 0
## Seconds since the bullet was last configured by `setup()`. Used to
## force a despawn via `MAX_LIFETIME` even when the screen notifier does
## not fire (headless mode, off-screen spawn, etc.).
var _lifetime: float = 0.0

@onready var _visual: CanvasItem = get_node_or_null("Visual")


func _ready() -> void:
	add_to_group("bullets")
	var notifier := get_node_or_null("VisibleOnScreenNotifier2D")
	if notifier:
		# Make the notifier's rect explicit so screen_exited fires reliably
		# even when a bullet is spawned with a zero-size default rect (the
		# default `Rect` of `VisibleOnScreenNotifier2D` is degenerate on
		# some Godot builds and never reports screen_exited until it is
		# overridden). 32x32 covers a generous area around the bullet.
		notifier.rect = Rect2(-16, -16, 32, 32)
		notifier.screen_exited.connect(_on_screen_exited)
	# Connect collision signals for body and area targets.
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	_apply_faction()


## Configure this bullet for a given faction, position, and (optional) speed.
## Called by the pool when handing out a bullet; safe to call directly.
func setup(faction_value: String, spawn_position: Vector2, speed_override: float = -1.0) -> void:
	faction = faction_value
	direction = Vector2.UP if faction_value == "player" else Vector2.DOWN
	speed = (PLAYER_SPEED if faction_value == "player" else ENEMY_SPEED)
	if speed_override >= 0.0:
		speed = speed_override
	if _visual == null:
		_visual = get_node_or_null("Visual")
	global_position = spawn_position
	# Reset the lifetime cap so a re-acquired pooled bullet doesn't carry
	# the previous shot's accumulated time and immediately get released.
	_lifetime = 0.0
	_apply_faction()


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	_lifetime += delta
	# Safety net for the screen notifier. If the notifier never fires
	# (headless rendering, off-screen spawn, degenerate rect on a custom
	# notifier, etc.) the bullet would otherwise accumulate forever in the
	# scene tree. `MAX_LIFETIME` is sized to far exceed any reasonable
	# viewport crossing, so legitimate gameplay is unaffected.
	if _lifetime >= MAX_LIFETIME:
		_release_self()


func _apply_faction() -> void:
	if _visual == null:
		return
	var c: Color = PLAYER_COLOR if faction == "player" else ENEMY_COLOR
	_visual.modulate = c


func _on_screen_exited() -> void:
	_release_self()


func _on_body_entered(body: Node) -> void:
	if not _can_hit(body):
		return
	_apply_damage_to(body)
	_release_self()


func _on_area_entered(area: Node) -> void:
	if not _can_hit(area):
		return
	_apply_damage_to(area)
	_release_self()


func _apply_damage_to(target: Node) -> void:
	if target != null and target.has_method("take_damage"):
		target.take_damage(damage)


## A target is hittable if it's not a bullet and not in our faction's group.
func _can_hit(target: Node) -> bool:
	if target == null:
		return false
	if target.is_in_group("bullets"):
		return false
	# "player" group is for the player; "enemy" group is for enemy ships.
	# Don't shoot same faction.
	if target.is_in_group(faction):
		return false
	return true


func _release_self() -> void:
	if pool != null and is_instance_valid(pool) and pool.has_method("release"):
		pool.release(self)
	else:
		queue_free()
