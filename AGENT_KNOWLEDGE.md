Project: void-patrol-variant-f-run4 (Godot 4.6)

## Key facts (from 0001)
- Viewport: 1152x648 (configured in project.godot, applies in normal/editor mode; StateServer headless may use 64x64 — don't rely on viewport size in tests, just verify clamp contract)
- Autoloads: StateServer (port 11009), TestHarness (port 11010, --test-harness flag)
- Editor plugins: GUT (addons/gut/)
- Default main scene: scenes/main.tscn (Node + scripts/main.gd)

## Conventions discovered
- Scripts use `extends X` + `class_name X` so they're globally addressable
- Use @export on tunable values; default scenes set bullet_scene / other PackedScenes via .tscn ext_resource
- Don't preload autoloads as constants — they break as the global instance. Just use the registered name directly (e.g. `StateServer.foo`)
- Headless tests pass but `get_viewport_rect().size` may be 64x64 instead of 1152x648 — write tests that pass regardless
- GUT tests: scripts must `extends GutTest`. Use `for k: String in arr:` (typed loop) and `var x: Dictionary = ...` (explicit type) to avoid "cannot infer type" parse errors
- `VisibleOnScreenNotifier2D` provides `screen_exited` — connect to it in `_ready` to auto-free Area2Ds that leave the viewport
- .tscn files should NOT include `[editable path="."]` for the root bullet/enemy scenes or `add_child` from outside will fail with `set_editable_instance` precondition

## Patch_file gotcha
- Tool's arg names are `old` / `new` (not `old_string` / `new_string` as documented in the system prompt). Empty-string `new` values sometimes fail silently; use shell+python3 for tricky removals.

## player.gd signal/state contract (use this for downstream tasks 0002-0007)
- Signals: shield_changed, lives_changed, life_lost, player_respawned, fired, died
- Public: take_damage(amount), respawn(), get_state()
- State keys: shield, max_shield, lives, max_lives, alive, position, velocity, fire_cooldown, fire_rate
- Group: "player"

## bullet.gd contract (0002 will extend this)
- Area2D, group "bullets", @export speed/damage/faction
- No collision signals wired yet — task 0002 should add body_entered/area_entered

## main.gd contract (use for 0003-0007)
- get_game_state() returns {scene, score, wave, high_score, bombs, game_over, player, hud}
- add_score(amount) and set_wave(n) for game-state changes from enemies/waves
- Already spawns Player + HUD in _ready; new systems should add as children of main, or be wired via signal handlers here
