extends SceneTree
func _init():
	var s = load("res://scripts/player.gd")
	if s == null: print("FAILED to load player.gd"); quit(1)
	print("player.gd loaded OK")
	quit(0)
