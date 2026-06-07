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

---
## boss.gd _die() ordering gotcha (void-patrol-variant-f-run4)

`boss.gd` extends `enemy_base.gd` and overrides `_die()` to emit a
`defeated()` signal before the base class emits `died(score_value)`
and `queue_free()`s the node.

CRITICAL: do NOT set `_is_dead = true` in the boss's `_die()` before
calling `super._die()`. The base class guards `_die()` with
`if _is_dead: return`, so pre-setting it short-circuits the base and
the `died` signal never fires. That breaks `_on_enemy_died`
scoring on the main scene (no +500 on kill).

Correct pattern:
```gdscript
func _die() -> void:
    if _is_dead:
        return
    defeated.emit()
    super._die()  # base sets _is_dead, emits died, queue_frees
```

## Boss fire-method _is_dead guard

The boss's three fire methods (`_fire_aimed_shot`, `_fire_spread_burst`,
`_fire_rotating_ring`) MUST each start with `if _is_dead: return`.
The boss's `_physics_process` already early-returns on `_is_dead`,
so that path is safe. But test fixtures (and any future code that
calls fire methods directly) bypass `_physics_process` and need
the guard. Without it, tests that `take_damage(40)` and then call
fire methods either leak bullets into the scene tree (the boss is
queue_freed at the next idle frame, but the bullets it spawned live
on) or crash on a freed-instance call.

## Boss Area2D shape ordering (boss.tscn)

`boss.tscn` wires two `CollisionShape2D` children: `BodyShape`
(index 0) and `WeakShape` (index 1). The shape order in the
`shapes` array of the Area2D MUST match this, because the boss's
`area_shape_entered` callback uses `area_shape_index == 1` to
detect weak-point hits. If the order is swapped, weak-point hits
would never trigger the 2x damage.

## boss + wave_manager integration (main.gd)

- `main.gd.ENEMY_SCENES["boss"] = "res://scenes/boss.tscn"`
- `main.gd._on_boss_fight_started()` (handler for
  `WaveManager.boss_fight_started`) spawns the boss at (576, -48),
  stores the ref in `main.boss`, wires `defeated` -> `_on_boss_defeated`
  and `died` -> `_on_boss_died_score`.
- `main.gd._on_boss_defeated()` sets `victory = true`, calls
  `wave_manager.notify_boss_defeated()`.
- `main.gd._on_boss_died_score(score_value)` calls `add_score(500)`.
- `wave_manager.notify_boss_defeated()` is a no-op unless
  `state == BOSS_FIGHT`; otherwise transitions to `State.COMPLETE`.
- `main.get_game_state()` exposes `victory`, `boss_hp`, `boss_max_hp`
  (sourced from `main.boss` when valid, 0 otherwise).

---
## Task 0007 (Game flow, scoring, high score) — DONE & validated

**Status:** Implementation complete across commits bb6f6ca, c6c1fa1, 7712346, be54b98. 33/33 test_game_flow.gd tests pass, full GUT 224/225 (1 risky placeholder).

**Key files & contracts:**

### scripts/high_score.gd (class_name HighScore, RefCounted, static API)
- `SAVE_PATH = "user://highscore.cfg"`, single ConfigFile section
- `load_high_score() -> int` (returns 0 on missing/corrupt)
- `save_high_score(score) -> int` (preserves difficulty)
- `save_if_higher(score) -> bool` (returns true if written)
- `load_difficulty() -> int` / `save_difficulty(d) -> int`
- `reset_save() -> int` (test-only; removes user://highscore.cfg)

### scripts/game_state.gd (class_name GameState, RefCounted)
- `SessionState` enum: MENU, PLAYING, GAME_OVER, VICTORY
- Signals: state_changed, score_changed, difficulty_changed, no_hit_changed
- `state`, `current_score`, `high_score`, `difficulty`, `wave_no_hit`, `no_hit_wave_number`
- `set_state(s)`, `add_score(d)`, `reset_score()`
- `save_high_score_if_higher()`, `increment_difficulty()` (persists), `reload_persisted()`
- `begin_wave(n)` / `mark_wave_hit()` (no-hit tracking)
- `get_state() -> Dictionary` for StateServer
- Loads high_score + difficulty in `_init` from HighScore

### scripts/main.gd game-flow additions
- `menu_overlay`, `game_over_overlay`, `victory_overlay` (CanvasLayer refs)
- `victory: bool`, `boss: Node` (live boss ref for state), `_game_state: GameState`
- `_boss_difficulty_hp_mult: float = 1.0` (1.0 + 0.04 * difficulty, applied to boss max_hp at spawn)
- Constants: `WAVE_CLEAR_BONUS_PER_WAVE = 100`, `NO_HIT_BONUS = 200`, `BOSS_KILL_BONUS = 500`
- `begin_session()` (public, idempotent): resets score/wave/flags, sets wave_manager difficulty, starts waves
- `_show_*_overlay()` helpers push (final_score, high_score, is_new_high) into overlays
- `_on_wave_cleared(n)`: awards 100*n + optional 200 (no-hit); is_inside_tree()-guarded TestHarness checkpoint
- `_on_boss_defeated()`: sets victory, save_high_score_if_higher, sets state to VICTORY, shows overlay
- `_on_victory_continue_pressed()`: increment_difficulty(), back to MENU, shows menu
- `_on_player_died()`: save_high_score_if_higher, GAME_OVER state, shows overlay
- `_on_player_shield_changed`: flash_damage + mark_wave_hit on drops (only when current < _last_shield)
- `get_game_state()` exposes: scene, score, wave, high_score, bombs, game_over, victory,
  player, hud, enemies, enemy_count, enemy_counts_by_type, wave_manager, boss_hp, boss_max_hp,
  game_flow (state, state_name, current_score, high_score, difficulty, wave_no_hit, no_hit_wave_number)

### scripts/menu_overlay.gd (class_name MenuOverlay, CanvasLayer)
- Signals: start_pressed, exit_pressed
- Tree: Root (Control, PRESET_FULL_RECT) > Content (VBoxContainer with Title, HighScore, Difficulty, Prompt, StartButton)
- show_menu() / hide_menu() / set_high_score(v) / set_difficulty(v)
- ui_accept/ui_select triggers start_pressed; ui_cancel triggers exit_pressed
- _process blinks prompt alpha 0.3..1.0 every 1.2s
- HighScore label hidden when value == 0; same for Difficulty

### scripts/endgame_overlay.gd (class_name EndgameOverlay, CanvasLayer)
- Base for game-over / victory screens. Signals: restart_pressed, continue_pressed.
- Subclasses override _emit_action() to pick the right signal.
- set_summary(final_score, high_score, is_new_high) — gold-tints high score on new high
- Headline / Prompt / Score / HighScore labels, blinks prompt alpha.

### scripts/game_over_overlay.gd (extends EndgameOverlay, class_name GameOverOverlay)
- Headline: "GAME  OVER", prompt: "PRESS  ENTER  TO  RESTART"
- _emit_action() emits restart_pressed

### scripts/victory_overlay.gd (extends EndgameOverlay, class_name VictoryOverlay)
- Headline: "VICTORY", prompt: "PRESS  ENTER  TO  CONTINUE"
- _emit_action() emits continue_pressed

### scenes/main.tscn
- Root Main (Node, scripts/main.gd) > Background (Sprite2D, starfield) +
  MenuOverlay (default visible) + GameOverOverlay (visible=false) + VictoryOverlay (visible=false)
  (Player, HUD, WaveManager, BulletsPool, etc. added at runtime via _ready)

### tests: test/unit/test_game_flow.gd (33 tests, all passing)
- HighScore: load zero when no save, save-then-load round-trip, save_if_higher no-clobber,
  save preserves difficulty, difficulty load returns zero unset
- GameState: starts in menu with zero, set_state emits + idempotent, add_score clamps + updates
  high_score, no-hit flag resets on begin_wave, mark_wave_hit idempotent, increment_difficulty persists
- Main: starts in menu, begin_session transitions to playing, begin_session resets score on second
  call, get_game_state includes game_flow keys, wave-cleared awards 100*wave, no-hit bonus,
  no-hit bonus withheld on damage, player_died saves high score, lower run doesn't overwrite
- Difficulty: starts at 0, victory continue increments, persists across main instances
- Overlays: menu shows high score / hides on zero / emits start_pressed, game-over shows summary,
  celebrates new high, victory shows continue prompt, emits continue_pressed, game-over emits restart_pressed

**Session loop:** menu -> playing (via Start) -> ... -> game_over (player_died) / victory (boss_defeated) ->
menu (via Restart on game-over, or Continue on victory). Continue increments difficulty for the next run;
Restart keeps difficulty the same.

---
## Overlay fade-in/out pattern (void-patrol-variant-f-run4)

For game over / victory / menu overlays, structure as:
```
CanvasLayer (root, with show_X() / hide_X() public methods)
└── Root (Control, PRESET_FULL_RECT)
    ├── Dim (ColorRect, full rect)
    └── Content (VBoxContainer with the actual labels)
```

To fade in/out, tween the Root's `modulate.a` rather than each child:
- `show_X()`: `visible = true; root.modulate.a = 0.0; tween to 1.0 over FADE_IN`
- `hide_X()`: tween to 0.0 over FADE_OUT, then set `visible = false` via tween_callback

Key rules:
- Track the active tween in a member var (`_root_tween: Tween = null`) and `kill()` it before starting a new one so a quick show/hide toggle doesn't double-animate
- `modulate` multiplies through the child tree, so the prompt's sin-pulse on its own modulate still works during the fade-in (it just gets dimmer briefly)
- The fade-in is intentionally short (0.2-0.35s) so it doesn't delay gameplay
- The fade-out is shorter than the fade-in so the next screen pops up snappily
- Don't tween when the overlay is already at the target alpha (avoid restarting finished tweens)
- For an intro fade-in on _ready, set `modulate.a = 0.0` and start a tween in `_ready()`

Recurring gotcha: `Tween.is_valid()` returns true while the tween is active. Use it before `kill()` to avoid no-op kills. But you can also just always call `kill()` — it's safe to kill a finished tween.

In tests:
- Tests that instantiate overlay scenes directly and call `set_summary`/`set_high_score` don't trigger the fade code (they don't call show/hide), so the fade is test-safe
- Tests that call `_unhandled_input` on the overlay work because the CanvasLayer's `visible` is true by default — modulate.a doesn't affect input handling
