extends Area2D
class_name Bullet

## Basic upward-moving bullet. The full Bullets system (next task) will
## expand this with power-up variants, multi-shot patterns, and pool reuse.

const DEFAULT_SPEED: float = 600.0

var speed: float = DEFAULT_SPEED
var damage: int = 1
## "player" or "enemy" -- used to filter collisions in the future.
var faction: String = "player"


func _ready() -> void:
	add_to_group("bullets")
	# Free self if it leaves the screen so we don't leak nodes.
	var notifier := get_node_or_null("VisibleOnScreenNotifier2D")
	if notifier:
		notifier.screen_exited.connect(_on_screen_exited)


func _physics_process(delta: float) -> void:
	position.y -= speed * delta


func _on_screen_exited() -> void:
	queue_free()
