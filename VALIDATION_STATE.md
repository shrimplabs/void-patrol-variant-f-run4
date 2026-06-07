**Polish pass (post-art, pre-QA) on void-patrol-variant-f-run4 — DONE**

Final validation commands (all working as of 2026-06-06):
- Script parse: `/opt/homebrew/bin/godot --headless --path . --script res://check_scripts.gd --quit` → all scripts OK
- Main scene instantiate: write `_swarm_main_check.gd` (load res://scenes/main.tscn + instantiate + free), then `godot --headless --path . --script res://_swarm_main_check.gd --quit` → Main scene OK
- GUT: `timeout 120 /opt/homebrew/bin/godot --headless --path . --script res://addons/gut/gut_cmdln.gd -- -gdir=res://test/unit -gexit` → 70 tests / 69 pass / 1 risky placeholder (test_placeholder.gd)
- Game launch: `launch_game(project_path)` + `wait(2)` + `get_game_state()` confirms HUD has DamageFlash, ShieldBar, ShieldLabel, ScoreLabel, WaveLabel, LivesLabel all anchored in /root/Main/HUD/Root/.

**Polish-pass scope (HEAD 4580498, pushed)**
- HUD adds a full-screen DamageFlash ColorRect (anchors_preset 15, mouse_filter=IGNORE, alpha 0.55 → 0 over 0.35s) that fires on shield drop (NOT regen). Wired through main.gd `_on_player_shield_changed` using a `_last_shield` member.
- Shield bar fill recolors (green > 55%, yellow > 30%, red ≤ 30%). At ≤ 30% the bar pulses via a looping tween at 4 Hz.
- HUD labels (Score / Wave / Lives / Shield) get outline + distinct tints + larger font; ScoreLabel and WaveLabel use double-space "SCORE  0" / "WAVE  1" / "LIVES  3" for cleaner alignment.
- ShieldBar gets a StyleBoxFlat track + bordered fill (translucent navy track, cyan-tinted border).

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
