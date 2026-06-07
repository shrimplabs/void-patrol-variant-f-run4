extends SceneTree
func _initialize():
	var f = FileAccess.open("user://_swarm_powerup_out.txt", FileAccess.WRITE)
	var log := func(msg): f.store_line(msg); f.flush()
	log.call("start")
	var packed = load("res://scenes/main.tscn")
	if packed == null: log.call("FAILED: cannot load main scene"); f.close(); quit(1); return
	var inst = packed.instantiate()
	if inst == null: log.call("FAILED: cannot instantiate main scene"); f.close(); quit(1); return
	root.add_child(inst)
	# In --script mode add_child does not auto-fire _ready; call it
	# manually so player / hud / wave_manager are populated before
	# we read state from them.
	if inst.has_method("_ready"):
		inst._ready()
	# Spawn a powerup explicitly to test the scene+script chain.
	var p = inst.spawn_powerup(0, Vector2(100, 100))
	if p == null: log.call("FAILED: cannot spawn powerup"); f.close(); quit(1); return
	log.call("Powerup spawned OK at " + str(p.global_position))
	log.call("Type name: " + p.get_type_name())
	# Try apply it to the player (just the apply_powerup chain).
	inst.apply_powerup(0, inst.player, p)
	var state = inst.get_game_state()
	log.call("Player shot_type: " + str(state["player"]["shot_type"]))
	log.call("Player active_powerups: " + str(state["player"]["active_powerups"]))
	log.call("HUD active_powerup_name: " + str(state["hud"]["active_powerup_name"]))
	# Test bomb
	var drone = inst.spawn_enemy("drone", Vector2(200, 50))
	var drone2 = inst.spawn_enemy("drone", Vector2(200, 100))
	log.call("Enemies before bomb: " + str(inst.get_enemy_count()))
	inst._bomb_blast(inst.player)
	log.call("Enemies after bomb: " + str(inst.get_enemy_count()))
	log.call("Drone 1 HP: " + str(int(drone.hp)) + " is_dead: " + str(bool(drone._is_dead)))
	log.call("Drone 2 HP: " + str(int(drone2.hp)) + " is_dead: " + str(bool(drone2._is_dead)))
	# Apply a speed boost and check active_powerups
	inst.apply_powerup(Powerup.Kind.SPEED_BOOST, inst.player)
	var s = inst.get_game_state()
	log.call("After speed boost shot_type=" + str(s["player"]["shot_type"]) + " speed_mult=" + str(s["player"]["speed_multiplier"]))
	# Apply double shot, then triple - should replace
	inst.apply_powerup(Powerup.Kind.DOUBLE_SHOT, inst.player)
	log.call("After DOUBLE shot_type=" + str(inst.player.shot_type))
	inst.apply_powerup(Powerup.Kind.TRIPLE_SPREAD, inst.player)
	log.call("After TRIPLE shot_type=" + str(inst.player.shot_type))
	log.call("Active powerups keys: " + str(inst.player.active_powerups.keys()))
	# Tick by 13 seconds - triple should expire (12s)
	inst.player._tick_powerups(13.0)
	log.call("After 13s tick shot_type=" + str(inst.player.shot_type))
	log.call("Active powerups after tick: " + str(inst.player.active_powerups.keys()))
	log.call("speed_multiplier after tick: " + str(inst.player.speed_multiplier))
	f.close()
	quit(0)
