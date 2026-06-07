extends SceneTree

func _initialize():
	var f = FileAccess.open("user://_swarm_diag_scene.txt", FileAccess.WRITE)
	f.store_line("start diag")
	var main_packed = load("res://scenes/main.tscn")
	if main_packed == null:
		f.store_line("FAILED: main.tscn not loadable")
		f.close()
		quit(1)
		return
	f.store_line("main.tscn loaded")
	var main = main_packed.instantiate()
	f.store_line("main instantiated")
	f.store_line("current_scene before add: " + str(current_scene))
	root.add_child(main)
	f.store_line("main added to root")
	f.store_line("current_scene after add: " + str(current_scene))
	f.store_line("current_scene == main? " + str(current_scene == main))
	await process_frame
	f.store_line("after 1 frame:")
	f.store_line("  current_scene: " + str(current_scene))
	f.store_line("  wave_manager state: " + str(main.wave_manager.state if main.wave_manager else "null"))
	f.store_line("  wave_manager current_wave: " + str(main.wave_manager.current_wave if main.wave_manager else "null"))
	f.store_line("  enemies count: " + str(main.get_enemy_count()))
	f.close()
	quit(0)
