extends SceneTree
# Validator for the power-up feature (task 0006).
#
# Runs in `--script` mode where autoloads are not initialized and
# ClassDB class_name registration is not refreshed. The full
# power-up test surface is covered by GUT (res://test/unit/test_powerup.gd)
# which runs in a real SceneTree. This validator does a quick smoke
# check on the scripts (parse + load) and the powerup scene.
func _initialize():
	var f = FileAccess.open("user://_swarm_powerup_out.txt", FileAccess.WRITE)
	var log := func(msg): f.store_line(msg); f.flush()
	log.call("start")
	# 1) Load every project script and confirm it parses.
	var script_paths := [
		"res://scripts/powerup.gd",
		"res://scripts/main.gd",
		"res://scripts/player.gd",
		"res://scripts/hud.gd",
	]
	for p: String in script_paths:
		var s = load(p)
		if s == null:
			log.call("FAILED: script load failed: " + p)
			f.close()
			quit(1)
			return
	log.call("All powerup scripts loaded OK")
	# 2) Load the powerup scene.
	var ps = load("res://scenes/powerup.tscn")
	if ps == null:
		log.call("FAILED: powerup.tscn load failed")
		f.close()
		quit(1)
		return
	log.call("powerup.tscn loaded OK")
	# 3) Confirm the powerup script exposes the API the main script
	# depends on. We poke the loaded GDScript resource directly
	# rather than going through ClassDB.
	var PowerupScript = load("res://scripts/powerup.gd")
	if PowerupScript == null or not (PowerupScript is GDScript):
		log.call("FAILED: powerup.gd is not a GDScript")
		f.close()
		quit(1)
		return
	# Look up methods on the script class object.
	var methods: Array = PowerupScript.get_script_method_list()
	var names: Array = []
	for m: Dictionary in methods:
		names.append(String(m.get("name", "")))
	for required in ["_ready", "_physics_process", "_on_body_entered", "_apply_effect"]:
		if not (required in names):
			log.call("FAILED: powerup.gd missing method: " + required)
			f.close()
			quit(1)
			return
	log.call("powerup.gd exposes required methods OK")
	# 4) Confirm main.gd exposes the powerup API.
	var MainScript = load("res://scripts/main.gd")
	var main_methods: Array = MainScript.get_script_method_list()
	var main_names: Array = []
	for m: Dictionary in main_methods:
		main_names.append(String(m.get("name", "")))
	for required in ["try_drop_powerup", "spawn_powerup", "spawn_random_powerup", "apply_powerup", "_bomb_blast"]:
		if not (required in main_names):
			log.call("FAILED: main.gd missing method: " + required)
			f.close()
			quit(1)
			return
	log.call("main.gd exposes powerup API OK")
	log.call("end")
	f.close()
	quit(0)
