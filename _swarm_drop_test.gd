extends SceneTree

# Quick repro test: kill a fighter via natural death (take_damage) and
# verify whether a powerup is dropped. With the current snapshot-via-
# tree_exited mechanism, the drop should FAIL because _on_enemy_died
# runs BEFORE the snapshot is captured.

const MAIN_SCRIPT := preload("res://scripts/main.gd")

func _init() -> void:
	var main: Node = MAIN_SCRIPT.new()
	root.add_child(main)
	# Force RNG to drop (roll = 0.0 always drops).
	# We can't set seed for randf directly, so just try a few times.
	var total_drops: int = 0
	var trials: int = 50
	for i in range(trials):
		var fighter: Node = main.spawn_enemy("fighter", Vector2(100, 100))
		# Count powerups in tree before kill.
		var before: int = get_nodes_in_group("powerup").size()
		fighter.take_damage(fighter.max_hp)
		# Pump one frame so queue_free takes effect and tree_exited fires.
		await physics_frame
		# After death, check if a powerup spawned (it would have been added
		# during _on_enemy_died if the snapshot was already set).
		var after: int = get_nodes_in_group("powerup").size()
		if after > before:
			total_drops += 1
	print("BUG REPRO: %d/%d fighter kills spawned a powerup" % [total_drops, trials])
	quit(0)
