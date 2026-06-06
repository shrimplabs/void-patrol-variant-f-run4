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

@onready var _visual: Polygon2D = get_node_or_null("Visual")


func _ready() -> void:
	add_to_group("bullets")
	var notifier := get_node_or_null("VisibleOnScreenNotifier2D")
	if notifier:
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
	_apply_faction()


func _physics_process(delta: float) -> void:
	position += direction * speed * delta


func _apply_faction() -> void:
	if _visual == null:
		return
	var c: Color = PLAYER_COLOR if faction == "player" else ENEMY_COLOR
	_visual.color = c


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
