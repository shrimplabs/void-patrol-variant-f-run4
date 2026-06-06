extends Node2D
## Minimal "target that can be damaged" used by the bullet collision tests.
## Lives in test/unit/ so it is excluded from production script scanning.

var last_damage: int = 0
var damage_history: Array[int] = []


func take_damage(amount: int) -> void:
	last_damage = amount
	damage_history.append(amount)
