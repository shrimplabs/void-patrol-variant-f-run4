**Polish + Task 0007 closure (post-game-flow) on void-patrol-variant-f-run4 — DONE**

Final validation commands (all working as of 2026-06-07):
- Script parse: `/opt/homebrew/bin/godot --headless --path . --script res://check_scripts.gd --quit` → all scripts OK
- Main scene instantiate: `godot --headless --path . --script res://_swarm_main_check.gd --quit` → Main scene OK
- Scene load: `godot --headless --path . --script res://_swarm_scene_check.gd --quit` → All scenes OK
- GUT: `timeout 120 /opt/homebrew/bin/godot --headless --path . --script res://addons/gut/gut_cmdln.gd -- -gdir=res://test/unit -gexit` → 225 tests / 224 pass / 1 risky placeholder (test_placeholder.gd, intentional)
- test_game_flow.gd (33 tests) — all 33 pass
- Game launch: `launch_game(project_path)` + `wait(2)` + `get_game_state()` confirms:
  - scene: Main, score: 0, wave: 1, high_score: 0, game_over: false, victory: false
  - game_flow.state == MENU (0), state_name == "menu", wave_no_hit: true, difficulty: 0
  - All three overlays present (MenuOverlay, GameOverOverlay, VictoryOverlay) with full content trees

**Polish-pass scope (HEAD 4580498, pushed)**
- HUD adds a full-screen DamageFlash ColorRect (anchors_preset 15, mouse_filter=IGNORE, alpha 0.55 → 0 over 0.35s) that fires on shield drop (NOT regen). Wired through main.gd `_on_player_shield_changed` using a `_last_shield` member.
- Shield bar fill recolors (green > 55%, yellow > 30%, red ≤ 30%). At ≤ 30% the bar pulses via a looping tween at 4 Hz.
- HUD labels (Score / Wave / Lives / Shield) get outline + distinct tints + larger font; ScoreLabel and WaveLabel use double-space "SCORE  0" / "WAVE  1" / "LIVES  3" for cleaner alignment.
- ShieldBar gets a StyleBoxFlat track + bordered fill (translucent navy track, cyan-tinted border).

**Task 0007 scope (HEAD be54b98, pushed)**
- scripts/high_score.gd: persistent high score + difficulty to user://highscore.cfg via ConfigFile
- scripts/game_state.gd: session state machine (MENU/PLAYING/GAME_OVER/VICTORY), score / no-hit / difficulty bookkeeping
- scripts/menu_overlay.gd: start menu with high-score / difficulty display, blinking prompt, ui_accept -> start_pressed
- scripts/endgame_overlay.gd: shared base for end-of-run screens (game-over / victory)
- scripts/game_over_overlay.gd: extends EndgameOverlay with restart_pressed
- scripts/victory_overlay.gd: extends EndgameOverlay with continue_pressed
- scripts/main.gd: integrated overlays, begin_session(), _on_wave_cleared (100*wave + optional 200 no-hit),
  _on_boss_defeated (saves high score, sets VICTORY), _on_victory_continue_pressed (increment_difficulty),
  _on_player_died (saves high score, sets GAME_OVER), get_game_state() exposes game_flow + boss_hp + victory
- scenes/main.tscn: Main root with MenuOverlay (visible) + GameOverOverlay + VictoryOverlay (both hidden)
- test/unit/test_game_flow.gd: 33 tests covering all of the above

**Excluded paths:** `addons/`, `.godot/`, `*.uid`.

**Known benign warnings (do not flag as errors):**
- `res://scenes/player.tscn:4 - ext_resource, invalid UID: uid://b1bullet01` — fake UID; Godot falls back to text path fine. Cosmetic warning.
- GUT loads with UID warnings for its own scenes.
- 12 RID allocation / orphan warnings at exit (bullets that didn't despawn in headless). Benign.
- `_swarm_scene_check.gd` reports false-positive "Identifier not found: BulletPool" in --script mode. Use `check_scripts.gd` instead.

**Recurring gotchas:**
- `for k in arr:` without type annotation fails to parse. Use `for k: String in arr:`.
- `var x := func_returning_dict()` may fail to infer. Use `var x: Dictionary = func_returning_dict()`.
- `[editable path="."]` at end of bullet/enemy .tscn breaks `add_child` from outside.
- `VisibleOnScreenNotifier2D` has `screen_exited`.
- `var x: Node = some_array.pop_back()` THROWS if the popped Variant is a freed-Node reference. Use untyped `var x = some_array.pop_back()` and rely on `is_instance_valid()`.
- `--script` mode does not load autoloads. Use `check_scripts.gd` (SceneTree-based) to parse them.
- Patch_file arg names are `old` / `new` (not `old_string` / `new_string`).
- HUD overlay nodes must be the FIRST child of the HUD Root so they render behind text. DamageFlash uses mouse_filter=IGNORE so it never blocks clicks.
- StyleBoxFlat on a ProgressBar: set both `theme_override_styles/background` (track) and `theme_override_styles/fill` (progress). Mutating the fill style's `bg_color` at runtime is the cheapest way to recolor the bar.
- main.gd signal handlers that look up `/root/TestHarness` must be guarded with `is_inside_tree()` to avoid "Can't use get_node() with absolute paths from outside the active scene tree" ERROR during GUT teardown (free_all).
- `extends EndgameOverlay` (subclass pattern) + class_name works in this Godot 4.6 setup; both MenuOverlay and the EndgameOverlay subclasses are in `.godot/global_script_class_cache.cfg` once the editor scan runs (regenerate via `godot --headless --editor --quit --quit-after 2`).
