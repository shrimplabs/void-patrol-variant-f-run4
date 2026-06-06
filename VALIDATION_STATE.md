Validation state for void-patrol-variant-f-run4 (after integration + enemy code):

**Validation commands (all working):**
- Script parse: `/opt/homebrew/bin/godot --headless --path . --script res://check_scripts.gd --quit` → all scripts OK
- Scene load: use `_swarm_scene_check.gd` aware of autoloads, or just trust check_scripts.gd + manual instantiation (the naive _swarm_scene_check.gd reports false-positive "Identifier not found: BulletPool" because --script mode does not load autoloads)
- Main instantiate: write `_swarm_main_check.gd` (see system prompt), then run --script → Main scene OK
- GUT: `/opt/homebrew/bin/godot --headless --path . --script res://addons/gut/gut_cmdln.gd -- -gdir=res://test/unit -gexit` (timeout 120+). Currently 70 tests / 69 pass / 1 risky placeholder (test_placeholder.gd).
- Game launch: launch_game(project_path) + wait(3) + get_game_state() — verifies the running game exposes the expected state shape including `enemies`/`enemy_count`/`enemy_counts_by_type` keys.

**Excluded paths:** `addons/`, `.godot/`, `*.uid` (third-party / generated). Test directory is `res://test/unit/`.

**Known benign warnings (do not flag as errors):**
- `res://scenes/player.tscn:4 - ext_resource, invalid UID: uid://b1bullet01` — fake UID; Godot falls back to text path fine. Cosmetic warning, not a real error.
- GUT loads with UID warnings for its own scenes (`GutScene.tscn`, `GutBottomPanel.tscn` etc.) — also benign.
- 12 RID allocation / orphan warnings at exit (bullets that didn't despawn in headless because VisibleOnScreenNotifier2D doesn't fire in headless mode). Not a real bug.
- `_swarm_scene_check.gd` reports "Failed to load script" for enemy_fighter.gd and enemy_bomber.gd if run in --script mode (autoloads not loaded). This is a false positive; the scripts ARE valid in normal game mode where autoloads are loaded. Use `check_scripts.gd` instead.

**Recurring gotchas:**
- `for k in arr:` without type annotation fails to parse. Always use `for k: String in arr:`.
- `var x := func_returning_dict()` may fail to infer. Use `var x: Dictionary = func_returning_dict()`.
- `[editable path="."]` at end of bullet/enemy .tscn breaks `add_child` from outside. Don't use it.
- `VisibleOnScreenNotifier2D` has `screen_exited`, NOT Area2D. Connect via child reference in _ready.
- `var x: Node = some_array.pop_back()` THROWS if the popped Variant is a freed-Node reference. Use untyped `var x = some_array.pop_back()` and rely on `is_instance_valid()` to filter stale refs. (See AGENT_KNOWLEDGE.md.)
- `--script` mode does not load autoloads. Scripts that reference autoload names by identifier (e.g. `BulletPool.foo()`) will fail to parse with "Identifier not found". Use `check_scripts.gd` (or any SceneTree-based loader) to parse them, not --script.
