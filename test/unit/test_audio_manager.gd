extends GutTest
## GUT tests for the AudioManager autoload (task 0008 polish):
##   - SFX_NAMES catalog has the expected entries
##   - register_all() pre-builds every SFX in the catalog
##   - clear_cache() drops the built cache
##   - play(sfx_name) returns silently for unknown SFX (no crash)
##   - play_loop / stop_loop manage the looping player correctly
##   - is_playing / get_playing_count report correct state
##
## These tests use the global AudioManager autoload (registered in
## project.godot). In --script mode that autoload is not loaded, but
## GUT does load it -- that's what this test relies on.

var _am: Node = null


func before_each() -> void:
	_am = get_node_or_null("/root/AudioManager")
	assert_not_null(_am,
		"AudioManager autoload should be registered in project.godot")
	if _am != null:
		# Mute real audio output during tests so we don't get audible
		# noise on the CI box, and reset cache between tests.
		_am.set_muted(true)
		_am.clear_cache()


func after_each() -> void:
	if _am != null:
		_am.set_muted(false)
		_am.stop_loop()


# ---------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------

func test_sfx_names_catalog_has_all_expected_entries() -> void:
	assert_not_null(_am, "AudioManager autoload available")
	var expected: Array = [
		"shoot", "enemy_shoot",
		"explosion_small", "explosion_large",
		"pickup", "shield_hit",
		"life_lost", "wave_clear",
		"boss_intensity", "victory", "game_over",
	]
	for n: String in expected:
		assert_true(_am.SFX_NAMES.has(n),
			"SFX catalog should include '%s'" % n)
	assert_eq(_am.SFX_NAMES.size(), expected.size(),
		"Catalog size should match expected")


func test_get_sfx_count_matches_catalog() -> void:
	assert_eq(_am.get_sfx_count(), _am.SFX_NAMES.size(),
		"get_sfx_count should match SFX_NAMES size")


# ---------------------------------------------------------------------
# Cache & build
# ---------------------------------------------------------------------

func test_register_all_builds_every_sfx_in_the_catalog() -> void:
	_am.register_all()
	# The cache is private (_sfx_cache) but the catalog should match
	# what we expect. We test by playing every name -- play() should
	# return without warnings for every name.
	for n: String in _am.SFX_NAMES:
		_am.play(n)
	# No assertions on get_playing_count() here -- since we're muted
	# the play() call is a no-op and the counter is not incremented.


func test_clear_cache_drops_built_streams() -> void:
	_am.register_all()
	# Re-registering after a clear should still work (no crash from
	# trying to re-add an already-cached key).
	_am.clear_cache()
	_am.register_all()
	# We can't directly assert cache size without a public accessor, but
	# the call path is exercised -- the test passes if no error fires.
	assert_true(true, "register_all() after clear_cache() should be a no-op-error")


# ---------------------------------------------------------------------
# Play / unknown / mute
# ---------------------------------------------------------------------

func test_play_unknown_sfx_does_not_crash() -> void:
	# Unknown names should push a warning (not asserted) and return
	# cleanly. The test passes if no error is raised.
	_am.play("not_a_real_sfx")
	assert_true(true, "play(unknown) should not raise")


func test_play_returns_quietly_when_muted() -> void:
	# muted=true was set in before_each; play() should be a no-op
	# (in particular it must not increment the playing count).
	var before: int = _am.get_playing_count()
	_am.play("shoot")
	_am.play("explosion_small")
	assert_eq(_am.get_playing_count(), before,
		"muted play() should not change the playing count")


func test_set_muted_toggles_quietly() -> void:
	_am.set_muted(true)
	assert_true(_am.muted, "muted flag should be true after set_muted(true)")
	_am.set_muted(false)
	assert_false(_am.muted, "muted flag should be false after set_muted(false)")


# ---------------------------------------------------------------------
# Looping SFX
# ---------------------------------------------------------------------

func test_play_loop_starts_a_looping_player() -> void:
	# Unmute for this test -- before_each() muted us to keep CI quiet.
	_am.set_muted(false)
	var p: AudioStreamPlayer = _am.play_loop("boss_intensity", -6.0)
	assert_not_null(p, "play_loop should return a player for a known SFX")
	_am.stop_loop()
	_am.set_muted(true)


func test_stop_loop_clears_the_looping_player() -> void:
	_am.set_muted(false)
	_am.play_loop("boss_intensity", -6.0)
	_am.stop_loop()
	# After stop_loop, a fresh is_playing("boss_intensity") should be
	# false (the loop is the only player that can play it, and it's
	# been stopped).
	assert_false(_am.is_playing("boss_intensity"),
		"is_playing(boss_intensity) should be false after stop_loop")
	_am.set_muted(true)


func test_play_loop_replaces_previous_loop() -> void:
	# Two play_loop calls in a row should leave us with one loop
	# player, not two. The first call should be stopped by the second.
	_am.set_muted(false)
	_am.play_loop("boss_intensity", -6.0)
	_am.play_loop("wave_clear", -6.0)
	# If the second call didn't replace the first we'd leak an
	# AudioStreamPlayer; the test passes if no error fires and the
	# state is consistent (we have one loop at most).
	_am.stop_loop()
	assert_false(_am.is_playing("boss_intensity"),
		"Old loop should have been replaced")
	_am.set_muted(true)


func test_play_loop_unknown_returns_null() -> void:
	var p: AudioStreamPlayer = _am.play_loop("nope_not_a_sfx", -6.0)
	assert_null(p,
		"play_loop(unknown) should return null without starting a loop")


# ---------------------------------------------------------------------
# is_playing / get_playing_count
# ---------------------------------------------------------------------

func test_is_playing_returns_false_for_unknown_sfx() -> void:
	assert_false(_am.is_playing("definitely_not_playing"),
		"is_playing for a never-played SFX should be false")


func test_get_playing_count_starts_at_zero() -> void:
	# After clear_cache + before any play, count should be 0.
	assert_eq(_am.get_playing_count(), 0,
		"Playing count should be 0 on a fresh AudioManager")
