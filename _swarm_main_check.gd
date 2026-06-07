extends SceneTree
## Scratch validator: loads the project's main scene and instantiates
## it, then frees the instance. Used by integration agents to verify
## the main scene still wires up cleanly after edits.
##
## This file is prefixed with `_swarm_` to mark it as a scratch /
## transient validation file. The integration task that uses it is
## expected to delete it after validation completes, but it's safe to
## leave in the repo (it does not run during normal game startup).

func _init() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		print("SCENE ERROR: Cannot load main scene")
		quit(1)
		return
	var instance: Node = packed.instantiate()
	if instance == null:
		print("SCENE ERROR: Cannot instantiate main scene")
		quit(1)
		return
	# Add to the tree briefly so _ready() runs, then free.
	root.add_child(instance)
	instance.queue_free()
	print("Main scene OK")
	quit(0)
