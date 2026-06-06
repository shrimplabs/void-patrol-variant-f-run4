extends "res://scripts/enemy_base.gd"
class_name EnemyDrone

## Drone enemy: the most basic grunt.
##  - 1 HP, dies in one player bullet hit.
##  - Straight-down movement, no lateral drift.
##  - Never fires.
##  - 10 points on kill.
##
## Stats (set as @export so the scene can also override them):
##  max_hp        = 1
##  score_value   = 10
##  move_speed    = 140 px/s (faster than bomber, slower than fighter)
##  fire_interval = 0 (disabled -- drones don't shoot)

## Stable type identifier for spawn_enemy() lookups and the StateServer
## enemy-counts-by-type report. Must match the keys in main.gd.ENEMY_SCENES.
var enemy_type_name: String = "drone"


func _ready() -> void:
	# Apply type-specific stats before the base _ready wires signals.
	# The base _ready will re-apply max_hp to hp, so order matters: do this
	# in our own _ready and then defer to super's behavior via call_deferred.
	max_hp = 1
	score_value = 10
	move_speed = 140.0
	fire_interval = 0.0
	contact_damage = 1
	_movement_dir = Vector2.DOWN
	enemy_type_name = "drone"
	super._ready()
