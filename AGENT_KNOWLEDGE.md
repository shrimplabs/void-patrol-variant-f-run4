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

---
## bullet_pool.gd free-list gotcha (Godot 4)

`var candidate: Node = free_list.pop_back()` THROWS "Trying to assign
invalid previously freed instance" if the free list contains a freed-Node
Variant. The intended `is_instance_valid(candidate)` check below never
runs because the typed assignment itself fails first.

Fix: keep the local UNTYPED (`var candidate = free_list.pop_back()`) so the
Variant can hold the freed-Node reference, and let `is_instance_valid`
discard it as designed.

When does the free list get stale refs? Most commonly in tests where a
parent (e.g. a test fixture Main) is freed before its child bullets are
released, and the bullets get released to the pool in a half-freed state.
Production code that uses the pool correctly is unlikely to hit this, but
defensive typing is required regardless.

## --script mode vs autoloads

`/opt/homebrew/bin/godot --headless --path . --script res://foo.gd --quit`
does NOT load autoloads. Scripts that reference autoload names directly
(e.g. `if BulletPool == null:`) will fail to compile with
"Identifier not found: BulletPool" when loaded this way.

Use `check_scripts.gd` (or any SceneTree-based loader) which pre-loads
class_names and is aware of autoload references, instead of a naive
"load every .gd" script. check_scripts.gd is the project-blessed script
parse tool.

---
## closure-repair task pattern (void-patrol-variant-f-run4)

When a regression fix touches files that are also used as autoload globals (e.g. `BulletPool`), bare autoload-name references like `if BulletPool == null:` parse fine inside GUT (autoloads are initialized) but fail to compile in `--script` / `--check-only` invocations where the autoload table is empty.

Fix pattern: replace each bare autoload reference with a defensive `get_node_or_null("/root/<AutoloadName>")` lookup, cached in a member var. Tests can still use the bare name (they run under GUT where autoloads are live).

Do NOT add `class_name <AutoloadName>` to the autoload script — that collides with the autoload identifier and breaks other code.

## bullet_pool.gd free-list pop gotcha (recurring)

`var candidate: Node = free_list.pop_back()` throws "Trying to assign invalid previously freed instance" if the free list contains a freed-Node Variant. Fix: keep the local UNTYPED (`var candidate = free_list.pop_back()`) so `is_instance_valid` can filter stale refs as designed. Stale refs accumulate when tests queue_free the parent before child bullets are released.

## Project: void-patrol-variant-f-run4 — final closure state

- All 3 closure-repair tasks (reg-501e6adcae, reg-95ad0ba384-1, reg-95ad0ba384-2) landed successfully.
- 70 GUT tests, 69 pass, 1 risky placeholder (test_placeholder.gd).
- check_scripts.gd: all scripts parse.
- Game launches and exposes the expected state shape (player, hud, enemies/enemy_count/enemy_counts_by_type, scene, score, wave, high_score, bombs, game_over).
- Bullet pool free-list is defensive; player.gd / enemy_fighter.gd / enemy_bomber.gd look up the autoload via `get_node_or_null("/root/BulletPool")` instead of the bare global.

---
## HUD polish pattern (void-patrol-variant-f-run4)

For damage / status overlay nodes, structure as:
```
HUD (CanvasLayer)
└── Root (Control, PRESET_FULL_RECT)
    ├── DamageFlash (ColorRect, anchors_preset=15, mouse_filter=IGNORE)
    ├── ScoreLabel / WaveLabel / LivesLabel (Label, viewport-relative offsets)
    ├── ShieldBar (ProgressBar with StyleBoxFlat background + fill)
    └── ShieldLabel (Label, right-aligned next to the bar)
```

Key rules:
- Overlay (`DamageFlash`) must be the FIRST child of `Root` so it renders behind text.
- Set `mouse_filter = MOUSE_FILTER_IGNORE` on the overlay so it never intercepts clicks.
- Mutate `StyleBoxFlat.bg_color` on the ProgressBar's `theme_override_styles/fill` at runtime to recolor the bar without rebuilding the theme.
- Use a looping `create_tween().set_loops()` with two `tween_property(_bar, "modulate:a", ...)` steps to pulse the bar (1 / (2 * Hz) seconds per step).
- For "flash then fade", kill the previous tween with `if _tween and _tween.is_running(): _tween.kill()`, then snap to visible alpha and tween to 0.
- For damage-vs-regen differentiation, track `_last_shield` in the signal handler and only call `flash_damage(...)` when `current < _last_shield`.

Recurring gotcha: HUD label `text` strings should use double-space alignment ("SCORE  0") — single colon formats ("SCORE: 0") feel cramped next to a numeric value.
