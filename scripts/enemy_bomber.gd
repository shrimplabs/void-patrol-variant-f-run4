extends "res://scripts/enemy_base.gd"
class_name EnemyBomber

## Bomber enemy: heavy, slow, deadly broadside.
##  - 4 HP, takes four player bullets to kill.
##  - Slow straight-down movement (no lateral drift) -- reads as "big target".
##  - 3-shot angled burst on each fire tick: center, left-diagonal, right-diagonal.
##  - 50 points on kill.

## Angles in degrees for the left/right burst shots, relative to straight down.
## Center shot is always Vector2.DOWN.
@export var burst_outer_angle_deg: float = 18.0
## Internal fire-on-enter phase: bombers fire a burst the first time the
## cooldown expires, then settle into the interval rhythm.
@export var initial_cooldown: float = 0.6
## Stable type identifier; matches a key in main.gd.ENEMY_SCENES.
var enemy_type_name: String = "bomber"


func _ready() -> void:
	max_hp = 4
	score_value = 50
	move_speed = 60.0
	fire_interval = 1.6
	contact_damage = 2  # bigger ship hurts more on contact
	_movement_dir = Vector2.DOWN
	enemy_type_name = "bomber"
	super._ready()
	# Stagger the first shot so bombers don't fire immediately on spawn.
	if fire_interval > 0.0:
		_fire_cooldown = initial_cooldown


func _fire_pattern() -> void:
	# Three-shot burst: center, then two outer shots fanned out by
	# burst_outer_angle_deg. Each shot is a separate enemy bullet so the
	# player can dodge the fan if positioned well.
	_spawn_enemy_bullet(Vector2.DOWN)
	var left := Vector2.DOWN.rotated(deg_to_rad(-burst_outer_angle_deg))
	var right := Vector2.DOWN.rotated(deg_to_rad(burst_outer_angle_deg))
	_spawn_enemy_bullet(left)
	_spawn_enemy_bullet(right)


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
	return pool.acquire("enemy", global_position, parent)
