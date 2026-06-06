extends GutTest
## GUT tests for the main scene controller: get_game_state() returns the full
## shape from the design doc, and signal handlers update HUD values correctly.

const MAIN_SCRIPT := preload("res://scripts/main.gd")

var _main: Node = null


func before_each() -> void:
	_main = MAIN_SCRIPT.new()
	add_child_autofree(_main)


func after_each() -> void:
	_main = null


func test_main_get_game_state_has_full_shape() -> void:
	var state: Dictionary = _main.get_game_state()
	var expected_keys := [
		"scene", "score", "wave", "high_score", "bombs",
		"game_over", "player", "hud",
	]
	for k: String in expected_keys:
		assert_has(state, k, "get_game_state() should include key: %s" % k)
	assert_eq(state["scene"], "Main", "scene should be 'Main'")
	assert_eq(state["score"], 0, "score should start at 0")
	assert_eq(state["wave"], 1, "wave should start at 1")
	assert_eq(state["game_over"], false, "game_over should start false")


func test_main_player_and_hud_are_spawned() -> void:
	assert_not_null(_main.player, "main should spawn a player")
	assert_not_null(_main.hud, "main should spawn a hud")


func test_main_player_state_is_embedded_in_get_game_state() -> void:
	var state: Dictionary = _main.get_game_state()
	assert_has(state["player"], "shield", "player state should have shield")
	assert_has(state["player"], "lives", "player state should have lives")
	assert_has(state["player"], "position", "player state should have position")


func test_main_hud_state_is_embedded_in_get_game_state() -> void:
	var state: Dictionary = _main.get_game_state()
	assert_has(state["hud"], "score", "hud state should have score")
	assert_has(state["hud"], "wave", "hud state should have wave")
	assert_has(state["hud"], "lives", "hud state should have lives")
	assert_has(state["hud"], "shield", "hud state should have shield")


func test_add_score_updates_state_and_high_score() -> void:
	_main.add_score(500)
	assert_eq(_main.score, 500, "score should be 500")
	assert_eq(_main.high_score, 500, "high_score should track max score")
	assert_eq(_main.get_game_state()["score"], 500,
		"get_game_state() should reflect new score")


func test_player_take_damage_propagates_to_hud_via_signal() -> void:
	# Drain half the shield; HUD should reflect it.
	_main.player.take_damage(40)
	var hud_state: Dictionary = _main.hud.get_state()
	assert_eq(hud_state["shield"], 60.0,
		"HUD shield should reflect player damage (100 - 40 = 60)")


func test_player_life_loss_propagates_to_hud_via_signal() -> void:
	# Drain full shield to trigger life loss + respawn.
	_main.player.take_damage(_main.player.max_shield)
	var hud_state: Dictionary = _main.hud.get_state()
	assert_eq(hud_state["lives"], _main.player.max_lives - 1,
		"HUD lives should reflect life loss")
	assert_eq(hud_state["shield"], _main.player.max_shield,
		"HUD shield should be full after respawn")
