Validation state for void-patrol-variant-f-run4 (after task 0001):

**Validation commands (all working):**
- Script parse: `/opt/homebrew/bin/godot --headless --path . --script res://check_scripts.gd --quit` → all scripts OK
- Scene load: write `_swarm_scene_check.gd` (see system prompt), then run --script → all scenes OK
- Main instantiate: write `_swarm_main_check.gd` (see system prompt), then run --script → Main scene OK
- GUT: `/opt/homebrew/bin/godot --headless --path . --script res://addons/gut/gut_cmdln.gd -- -gdir=res://test/unit -gexit` (timeout 120+). Currently 22 tests / 21 pass / 1 risky placeholder.
- Game launch: launch_game(project_path) + wait(3) + get_game_state() — verifies the running game exposes the expected state shape.

**Excluded paths:** `addons/`, `.godot/`, `*.uid` (third-party / generated). Test directory is `res://test/unit/`.

**Known benign warnings (do not flag as errors):**
- `res://scenes/player.tscn:4 - ext_resource, invalid UID: uid://b1bullet01` — fake UID; Godot falls back to text path fine. Cosmetic warning, not a real error.
- GUT loads with UID warnings for its own scenes (`GutScene.tscn`, `GutBottomPanel.tscn` etc.) — also benign.

**Recurring gotchas:**
- `for k in arr:` without type annotation fails to parse. Always use `for k: String in arr:`.
- `var x := func_returning_dict()` may fail to infer. Use `var x: Dictionary = func_returning_dict()`.
- `[editable path="."]` at end of bullet/enemy .tscn breaks `add_child` from outside. Don't use it.
- `VisibleOnScreenNotifier2D` has `screen_exited`, NOT Area2D. Connect via child reference in _ready.
