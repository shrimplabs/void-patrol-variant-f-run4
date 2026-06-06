extends GutTest
## GUT tests for the HUD: setters update labels / bar values, and get_state()
## returns the expected shape used by the main scene's get_game_state().

const HUD_SCRIPT := preload("res://scripts/hud.gd")

var _hud: CanvasLayer = null


func before_each() -> void:
	_hud = HUD_SCENE_NEW()
	add_child_autofree(_hud)


func after_each() -> void:
	if is_instance_valid(_hud):
		_hud.queue_free()
	_hud = null


func HUD_SCENE_NEW() -> CanvasLayer:
	# Build a minimal HUD instance by adding a CanvasLayer with the script
	# and the four expected child nodes. Avoids loading hud.tscn which has
	# specific pixel positions that don't matter for state-shape tests.
	var h: CanvasLayer = HUD_SCRIPT.new()
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_child(root)
	root.add_child(Label.new())
	root.get_child(0).name = "ScoreLabel"
	root.add_child(Label.new())
	root.get_child(1).name = "WaveLabel"
	root.add_child(Label.new())
	root.get_child(2).name = "LivesLabel"
	var pb := ProgressBar.new()
	pb.name = "ShieldBar"
	root.add_child(pb)
	return h


func test_hud_setters_update_state() -> void:
	_hud.set_score(1234)
	_hud.set_wave(3)
	_hud.set_lives(2)
	_hud.set_shield(75.0, 100.0)
	assert_eq(_hud.score, 1234, "score should be 1234")
	assert_eq(_hud.wave, 3, "wave should be 3")
	assert_eq(_hud.lives, 2, "lives should be 2")
	assert_eq(_hud.shield, 75.0, "shield should be 75")
	assert_eq(_hud.max_shield, 100.0, "max_shield should be 100")


func test_hud_get_state_shape() -> void:
	var state: Dictionary = _hud.get_state()
	var expected_keys: Array = ["score", "wave", "lives", "shield", "max_shield"]
	for k: String in expected_keys:
		assert_has(state, k, "HUD get_state() should include key: %s" % k)
