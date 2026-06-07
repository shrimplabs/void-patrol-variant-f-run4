# Power-up (task 0006) -- Failure Diagnosis

## Question

Why has the "Power-ups" feature task (`void-patrol-variant--1780782399254-0006`)
**failed 3 times** without resolving, and what is the correct fix so the next
attempt can succeed?

The integration validator's "latest failure" message is a generic stub:

> `_enemy_count(), clear_enemies()` are the public enemy APIs on main.gd.

That is not an actual log line -- there is no `_enemy_count()` method in
`main.gd`. The real public API is `get_enemy_count()`. The stub is a
placeholder the system prints when the validator script itself never
reaches its assertion phase.

## Method

1. Read all the files the power-up task touched:
   - `scripts/powerup.gd` (251 lines), `scenes/powerup.tscn`
   - `scripts/main.gd` (added try_drop_powerup, spawn_powerup,
     apply_powerup, _bomb_blast, _on_player_powerup_changed)
   - `scripts/player.gd` (added apply_powerup, _tick_powerups,
     _reset_powerups, get_primary_powerup, powerup_changed signal,
     shot_type/speed_multiplier state, DOUBLE/TRIPLE/LASER/SPEED_BOOST
     handling)
   - `scripts/hud.gd` + `scenes/hud.tscn` (added PowerupLabel,
     set_active_powerup, _process countdown)
   - `test/unit/test_powerup.gd` (624 lines, 45 tests)

2. Ran the full validation chain:
   - `godot --headless --script res://check_scripts.gd --quit` → "All scripts OK"
   - `godot --headless --script res://addons/gut/gut_cmdln.gd -- -gdir=res://test/unit -gexit`
     → 115 tests, **114 pass**, 1 risky placeholder. All 45 powerup tests pass.
   - The full GUT run is the gold standard: it exercises every public
     surface the task description requires (drop chance, auto-collect,
     single-active shot rule, durations, BOMB clears bullets + damages
     enemies, HUD label updates).

3. Ran the integration agent's left-behind validator
   (`_swarm_powerup_check.gd`, 53 lines, extends SceneTree) directly:
   - The script writes only the first line ("start") to its output file
     and then **hangs indefinitely** -- exit takes 30+ seconds and
     produces no further output. (Confirmed with a clean rerun and a
     45-second timeout.)

4. Isolated the hang with a series of minimal SceneTree probes (since
   cleaned up):
   - `_test_pwrup5.gd`: `await process_frame` × 5 → only the first
     fires, the second await never resolves.
   - `_test_pwrup6.gd`: `await create_timer(0.1).timeout` × 5 → only
     the first timer fires. The SceneTree stops processing after the
     first signal.
   - `_test_pwrup2.gd` / `_test_pwrup4.gd`: loading main.tscn +
     add_child, then `await process_frame` → first frame completes
     (player is spawned by main._ready), the second `await process_frame`
     hangs.
   - Conclusion: **Godot 4.6 in `--script` mode processes exactly ONE
     frame/timer, then idles**. Any validator that needs two or more
     `await process_frame` calls in `--script` mode will hang.

## Findings

### 1. The feature is already complete and correct

`git log` shows commit `aaba35a` ("Refactor: update swarm_main_check.gd,
_swarm_scene_check.gd, hud.tscn, bullet.gd (+7 more)") landed the
entire power-up stack in one shot:

```
_swarm_main_check.gd      |  27 +-
_swarm_powerup_check.gd   |  53 ++++
_swarm_scene_check.gd     |  22 --
scenes/hud.tscn           |  16 ++
scenes/powerup.tscn       |  21 ++
scripts/bullet.gd         |  10 +-
scripts/hud.gd            |  48 ++++
scripts/main.gd           | 149 +++++++++++
scripts/player.gd         | 230 ++++++++++++++++-
scripts/powerup.gd        | 251 +++++++++++++++++++
test/unit/test_powerup.gd | 624 ++++++++++++++++++++++++++++++++++++++++++++++
```

Every acceptance criterion from the task description is implemented and
tested:

| Criterion (from task) | Where it lives | Tested by |
|---|---|---|
| `powerup.tscn` + `powerup.gd` drop with ~25% chance from fighters and bombers | `Powerup.DROP_CHANCE = 0.25`, `main.try_drop_powerup` routing | `test_try_drop_powerup_*`, `test_drop_distribution_is_close_to_25_percent` |
| Auto-collect on player contact | `powerup.gd._on_body_entered` checks `body.is_in_group("player")` | `test_powerup_auto_collects_on_player_contact`, `test_auto_collect_applies_effect_to_player`, `test_auto_collect_collected_signal_fires` |
| DOUBLE_SHOT yellow 15s, TRIPLE_SPREAD orange 12s, LASER red 8s, SHIELD_BOOST blue instant, SPEED_BOOST green 10s, BOMB purple instant | `Powerup.TYPE_DATA` (every kind has the correct color / duration / name / shot_type / is_shot_type) | `test_*_metadata` × 6, `test_double_shot_expires_after_15_seconds`, `test_triple_spread_expires_after_12_seconds`, `test_laser_expires_after_8_seconds`, `test_speed_boost_expires_after_10_seconds`, `test_shield_boost_*` |
| Only one shot-type active at a time; new one replaces old | `player.gd.apply_powerup` iterates `[DOUBLE_SHOT, TRIPLE_SPREAD, LASER]` and erases the prior kind | `test_double_shot_then_triple_replaces_active`, `test_triple_spread_then_laser_replaces_active`, `test_only_one_shot_type_active_at_a_time` |
| Non-shot powerups can coexist | SPEED_BOOST does not erase shot-types, shot-types do not erase SPEED_BOOST | `test_speed_boost_coexists_with_double_shot`, `test_two_speed_boosts_refresh_duration` |
| HUD shows active power-up name + remaining duration | `hud.gd.set_active_powerup` + PowerupLabel, `_process` countdown | `test_hud_shows_active_powerup_name`, `test_hud_shows_active_powerup_remaining`, `test_hud_clears_on_expiry` |
| BOMB clears all bullets + damages all enemies 2 | `main._bomb_blast` iterates "bullets" group and calls `_release_self`, iterates "enemies" and calls `take_damage(2)` | `test_bomb_clears_all_bullets`, `test_bomb_damages_all_enemies_by_2`, `test_bomb_awards_score_for_killed_enemies`, `test_bomb_increases_main_enemy_count_to_zero` |
| Powerup drop seeding | `Powerup.should_drop(roll: float)` is a pure function so tests can pass deterministic rolls; `_test_drop_distribution_is_close_to_25_percent` uses `seed(2024)` | All `test_should_drop_*`, `test_drop_distribution_is_close_to_25_percent` |
| Public API on main: `try_drop_powerup(type, pos)`, `spawn_powerup(kind, pos)`, `spawn_random_powerup(pos)`, `apply_powerup(kind, player, pickup)`, `get_enemy_count()`, `clear_enemies()` | `scripts/main.gd` lines 226-298 | Used by `test_powerup.gd` end-to-end |

GUT result: **45/45 powerup tests pass, 114/115 total, 1 risky placeholder
(test_placeholder.gd).** No regressions in test_bullet, test_player,
test_enemy, test_main, test_hud, or test_placeholder.

### 2. Root cause of the 3 reported failures

**`_swarm_powerup_check.gd` (left behind in the repo at the repo root) is
broken.** It is a SceneTree script intended to be run as
`godot --headless --script res://_swarm_powerup_check.gd --quit`, and it
relies on a `await process_frame` × 2 + several more `await process_frame`
pattern (lines 11-12, 38, 41, 45, 47, 50). Godot 4.6's `--script` mode
processes exactly one frame, then idles. So the script:

1. Writes "start" to its output file.
2. Loads main.tscn, instantiates, adds to root. (All synchronous.)
3. `await process_frame` -- **first one resolves**, Main's `_ready` runs,
   `inst.player` is now a real Player.
4. `await process_frame` -- **hangs forever**. The SceneTree has no work
   left to do, so the signal never fires.
5. The integration agent's harness eventually times out and reports
   failure. (Three times, in a row, because the validator's behavior is
   deterministic.)

The same hang pattern exists in `_test_bullet_release.gd` (180 awaits in
a loop), which is why that file is also a "run it if you have nothing
better to do, expect a hang" test rather than a CI gate.

The 3 retries failed for the same reason -- every retry ran the same
validator and got the same hang.

### 3. What a correct fix looks like

There are two reasonable fixes, in order of preference:

**Fix A (preferred): Drop the second `await process_frame` in
`_swarm_powerup_check.gd`.** The script can do everything it needs in a
single frame because every public method on Main (`spawn_powerup`,
`apply_powerup`, `_bomb_blast`, `get_game_state`) operates synchronously
on already-instantiated nodes. Concrete edits to
`_swarm_powerup_check.gd`:

- Line 11-12: keep ONE `await process_frame` (to let `main._ready` run
  and `inst.player` become non-null). Remove the second one.
- After each `await process_frame`, do the next state read or action
  immediately, before the next `await`.
- Replace `await get_tree().physics_frame` patterns (lines 38, 41, 45,
  47, 50) with no-await equivalents: the BOMB test only needs to call
  `_bomb_blast` and then read state -- the bomb's effects are applied
  synchronously inside `_bomb_blast` (it iterates the `bullets` group
  and calls `_release_self` on each, then iterates `enemies` and calls
  `take_damage(2)`).
- For the "13-second tick" check, just call `inst.player._tick_powerups(13.0)`
  directly -- that's exactly what `test_powerup.gd` does, and it works
  without any frame awaits.

The end result is a script that writes all expected log lines to
`user://_swarm_powerup_out.txt` and quits cleanly with exit 0.

**Fix B (alternative): Run the validator as a scene, not a script.**
Wrap the validator's logic in a small `.tscn` whose root has the
validator script, and launch it via
`godot --headless --path . res://_swarm_powerup_check.tscn --quit`.
The full GUT harness uses this pattern; `--main-pack`/scene-driven
launches process frames normally. This is a bigger change for less
benefit -- Fix A is preferred.

**Both fixes are documentation-only / scratch-script only.** No
production source files need to change. The power-up implementation
itself is already correct and tested.

### 4. Cross-cutting note (not a regression)

The "12 Orphans" + 3 RID leak messages at GUT exit are pre-existing
benign noise from orphan bullets in headless mode. They are documented
in `VALIDATION_STATE.md` and `AGENT_KNOWLEDGE.md`. They do not affect
test pass/fail status and are not the cause of the failure.

The single "ERROR: 4 resources still in use at exit" from the
`--script` validator runs is also benign -- it comes from the script
tearing down the SceneTree without freeing the Main instance it added.
Not related to the hang.

## Recommendations

1. **Do not rewrite `scripts/powerup.gd`, `scripts/main.gd`,
   `scripts/player.gd`, `scripts/hud.gd`, `scenes/powerup.tscn`, or
   `test/unit/test_powerup.gd`.** They are already correct (45/45 GUT
   tests pass, every acceptance criterion covered).

2. **Apply Fix A to `_swarm_powerup_check.gd` only.** Reduce the two
   sequential `await process_frame` calls after `add_child` to one,
   and remove or inline the subsequent awaits. The validator will
   then complete in well under a second and write all the expected
   log lines.

3. **If a follow-up implementation task is created, the implementer
   should know:** the `--script` mode in Godot 4.6 only processes one
   `process_frame` (and one timer tick) per invocation. Any validator
   scratch file (anything starting with `_swarm_*.gd`) that needs more
   than one frame must run as a regular scene, not as a `--script`.

4. **Do not create new tasks from this diagnosis** (per the read-only
   contract). The next attempt can either:
   - Use the existing `_swarm_powerup_check.gd` after Fix A is applied
     to it, or
   - Skip the validator and use the GUT harness output
     (`godot --headless --path . --script res://addons/gut/gut_cmdln.gd -- -gtest=res://test/unit/test_powerup.gd -gexit`)
     as the sole gate. The GUT run already proves the feature works.

## Confidence

**High.** The implementation is verified end-to-end with the project's
blessed test runner (GUT, 45/45 pass). The hang is reproduced in
isolation with three independent minimal scripts. The fix is localized
to a single scratch file at the repo root.
