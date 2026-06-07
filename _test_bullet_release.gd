extends SceneTree

func _initialize():
	var main_packed = load("res://scenes/main.tscn")
	var main = main_packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var pool = root.get_node_or_null("BulletPool")
	var f = FileAccess.open("user://test_output.txt", FileAccess.WRITE)
	f.store_line("pool=" + str(pool))
	var stats = pool.get_stats()
	f.store_line("BEFORE: " + str(stats))

	var player = main.player
	for i in range(5):
		player._fire_cooldown = 0.0
		player._fire()

	await process_frame
	await process_frame

	stats = pool.get_stats()
	f.store_line("AFTER 5 FIRES: " + str(stats))

	for i in range(180):
		await process_frame

	stats = pool.get_stats()
	f.store_line("AFTER 3 SECONDS: " + str(stats))

	var bullets_in_tree = get_nodes_in_group("bullets")
	f.store_line("Bullets in tree: " + str(bullets_in_tree.size()))
	for b in bullets_in_tree:
		if is_instance_valid(b):
			f.store_line("  - pos=" + str(b.global_position) + " faction=" + str(b.faction) + " parent=" + str(b.get_parent()))

	f.close()
	quit(0)
