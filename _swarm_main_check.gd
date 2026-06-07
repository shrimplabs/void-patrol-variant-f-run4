extends SceneTree
func _initialize():
	var packed = load("res://scenes/main.tscn")
	if packed == null: print("SCENE ERROR: Cannot load main scene"); quit(1); return
	var instance = packed.instantiate()
	if instance == null: print("SCENE ERROR: Cannot instantiate main scene"); quit(1); return
	instance.free()
	print("Main scene OK")
	quit(0)
