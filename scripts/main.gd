extends Node
## Main scene controller. Owns game-wide state (score, wave) and wires the
## Player + HUD together. `get_game_state()` returns the full state dictionary
## used by the StateServer / QA harness / tests.
##
## Enemy spawning: `spawn_enemy(type, position)` instantiates one of the
## drone/fighter/bomber .tscn files under Main, wires its `died` signal to
## `_on_enemy_died` for scoring, and tracks it in `_enemies` so the StateServer
## can report live enemy state. The wave manager (task 0004) builds on this
## API to clear waves and free enemies when an area is cleared.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const HUD_SCENE := preload("res://scenes/hud.tscn")
const POWERUP_SCENE := preload("res://scenes/powerup.tscn")
const ENEMY_SCENES := {
	"drone": "res://scenes/enemy_drone.tscn",
	"fighter": "res://scenes/enemy_fighter.tscn",
	"bomber": "res://scenes/enemy_bomber.tscn",
}

var score: int = 0
var wave: int = 1
var high_score: int = 0
var bombs: int = 0
var game_over: bool = false

var player: Node = null
var hud: CanvasLayer = null
## Live enemies currently parented under Main. We track by node reference and
## prune on `tree_exited` so the StateServer list never includes freed nodes.
var _enemies: Array = []
## Cache of the most recently killed enemy's type and position, used by
## `_on_enemy_died` to know which drop chance to roll. Set by
## `_track_enemy`'s death-time snapshot, consumed by the next `died`
## signal. Empty string = no recent kill (signal already consumed).
var _last_died_enemy_type: String = ""
var _last_died_enemy_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_spawn_player()
	_spawn_hud()
	_wire_signals()


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	add_child(player)


func _spawn_hud() -> void:
	hud = HUD_SCENE.instantiate()
	add_child(hud)


func _wire_signals() -> void:
	if player and player.has_signal("shield_changed"):
		player.shield_changed.connect(_on_player_shield_changed)
	if player and player.has_signal("lives_changed"):
		player.lives_changed.connect(_on_player_lives_changed)
	if player and player.has_signal("died"):
		player.died.connect(_on_player_died)
	if player and player.has_signal("powerup_changed"):
		player.powerup_changed.connect(_on_player_powerup_changed)
		# Initial state broadcast so HUD shows the right baseline (no
		# powerup, no countdown).
		_on_player_powerup_changed(-1, "", 0.0)


var _last_shield: float = 0.0

func _on_player_shield_changed(current: float, max_value: float) -> void:
	if hud and hud.has_method("set_shield"):
		hud.set_shield(current, max_value)
	# Only flash when shield drops -- regen shouldn't trigger the damage overlay.
	if current < _last_shield and hud.has_method("flash_damage"):
		hud.flash_damage(_last_shield - current)
	_last_shield = current


func _on_player_lives_changed(current: int, _max_value: int) -> void:
	if hud and hud.has_method("set_lives"):
		hud.set_lives(current)


func _on_player_died() -> void:
	game_over = true
	if score > high_score:
		high_score = score


## Add score (e.g. when an enemy is killed). Clamps the new high score.
func add_score(amount: int) -> void:
	score += amount
	if hud and hud.has_method("set_score"):
		hud.set_score(score)
	if score > high_score:
		high_score = score


func set_wave(value: int) -> void:
	wave = value
	if hud and hud.has_method("set_wave"):
		hud.set_wave(wave)


## Spawn an enemy of the given type at the given world position. Returns the
## spawned node (or null if the type is unknown / scene failed to load).
## The enemy is parented to Main so it shares the same physics layer as the
## player. The `died` signal is wired to `_on_enemy_died` for scoring.
func spawn_enemy(enemy_type: String, world_position: Vector2) -> Node:
	var path: String = ENEMY_SCENES.get(enemy_type, "")
	if path == "":
		push_warning("Main.spawn_enemy: unknown enemy type '%s'" % enemy_type)
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		push_warning("Main.spawn_enemy: failed to load scene '%s'" % path)
		return null
	var enemy: Node = packed.instantiate()
	if enemy == null:
		return null
	if enemy is Node2D:
		(enemy as Node2D).global_position = world_position
	add_child(enemy)
	_track_enemy(enemy)
	return enemy


func _track_enemy(enemy: Node) -> void:
	if enemy == null:
		return
	_enemies.append(enemy)
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)
	# Capture the type and position at death-time so _on_enemy_died can
	# roll the drop chance for the right enemy. The `died` signal itself
	# only carries the score value, so we lean on a small helper that
	# snapshots the enemy just before it frees itself.
	if enemy.has_signal("tree_exited"):
		var snapshot := [enemy]
		enemy.tree_exited.connect(func() -> void:
			_snapshot_dead_enemy(snapshot)
		)
	# Auto-prune when the enemy frees itself (death, off-screen, etc.).
	enemy.tree_exited.connect(_on_enemy_exited.bind(enemy))


## Read the most-recently-tracked enemy's type/position into our drop
## cache, but only if it died from `died` (not from off-screen). We use
## the `_is_dead` flag the base enemy sets on death to distinguish.
func _snapshot_dead_enemy(snapshot: Array) -> void:
	if snapshot.is_empty():
		return
	var e: Node = snapshot[0]
	if e == null or not is_instance_valid(e):
		return
	if not bool(e.get("_is_dead")):
		# Off-screen / wave-clear -- no drop.
		return
	var etype: String = ""
	if "enemy_type_name" in e:
		etype = str(e.enemy_type_name)
	if etype == "":
		etype = str(e.name).to_lower()
	_last_died_enemy_type = etype
	if e is Node2D:
		_last_died_enemy_position = (e as Node2D).global_position


func _on_enemy_died(score_value: int) -> void:
	# The score value is the enemy's `score_value` export (drone=10,
	# fighter=25, bomber=50). We add it to the main score; the enemy itself
	# is freed in EnemyBase._die() and pruned from _enemies by
	# _on_enemy_exited when the tree_exited signal fires.
	add_score(int(score_value))
	# The enemy that just died passed its `enemy_type_name` before freeing.
	# We can't read it from the dead signal (it carries only the score), so
	# we have to look at the most-recently-killed enemy. We do that by
	# routing drop attempts through `try_drop_powerup` on each enemy
	# individually (see EnemyBase._die() in extension) -- but for now, we
	# just attempt drops from the enemy that sent the signal. Since the
	# signal payload doesn't carry the type, we use the last known type
	# from the most recent tracking. Tests that need exact drop behavior
	# can call `try_drop_powerup` directly with an explicit type.
	if _last_died_enemy_type != "":
		try_drop_powerup(_last_died_enemy_type, _last_died_enemy_position)
	_last_died_enemy_type = ""


func _on_enemy_exited(enemy: Node) -> void:
	_enemies.erase(enemy)


## Clear all currently-spawned enemies. Used by the wave manager (0004) to
## fast-forward a wave when the player advances. Each enemy is freed via its
## own queue_free so its `died` signal does not fire (no false score).
func clear_enemies() -> void:
	for e: Node in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()


# ---------------------------------------------------------------------
# Power-up plumbing
# ---------------------------------------------------------------------

## Try to spawn a power-up at `world_position` based on a kill by an
## enemy of `enemy_type`. Returns the spawned powerup node, or null if
## the drop roll fails / the enemy type doesn't drop.
##
## Drop chance: ~25% for fighter and bomber kills. Drones never drop.
## `randf()` is used for the roll; tests should call this many times
## (with a seeded RNG) to assert the rate, or call `Powerup.should_drop`
## directly with a deterministic roll value.
func try_drop_powerup(enemy_type: String, world_position: Vector2) -> Node:
	if enemy_type != "fighter" and enemy_type != "bomber":
		return null
	if not Powerup.should_drop(randf()):
		return null
	return spawn_random_powerup(world_position)


## Spawn a power-up of a random kind at the given position. Returns the
## spawned powerup node (or null on failure). Public so tests and the
## future wave manager can pre-place powerups if they want to.
func spawn_random_powerup(world_position: Vector2) -> Node:
	var kinds: Array = Powerup.all_kinds()
	if kinds.is_empty():
		return null
	var kind_value: int = int(kinds[randi() % kinds.size()])
	return spawn_powerup(kind_value, world_position)


## Spawn a power-up of an explicit kind at the given position. Public
## so tests can construct specific scenarios without dealing with the
## RNG. Returns the spawned powerup node (or null on failure).
func spawn_powerup(kind: int, world_position: Vector2) -> Node:
	if POWERUP_SCENE == null:
		push_warning("Main.spawn_powerup: powerup scene failed to load")
		return null
	var p: Node = POWERUP_SCENE.instantiate()
	if p == null:
		return null
	if p is Node2D:
		(p as Node2D).global_position = world_position
	if p.has_method("setup"):
		p.setup(kind)
	add_child(p)
	return p


## Apply a power-up of the given kind. Called by Powerup._on_body_entered
## once the player has walked into a pickup. Routes instant effects
## (BOMB) here at the scene level, and forwards player-state effects
## to the player via its `apply_powerup` method.
##
## `powerup` is the pickup node (kept for future hooks like a
## pickup-celebration effect); currently unused.
func apply_powerup(kind: int, player_node: Node, _powerup: Node = null) -> void:
	if kind == Powerup.Kind.BOMB:
		_bomb_blast(player_node)
		# BOMB has no per-player state to set; the player just sees the
		# blast. Don't call player.apply_powerup (it's a no-op for BOMB).
		return
	if player_node != null and player_node.has_method("apply_powerup"):
		player_node.apply_powerup(kind, _powerup)


## BOMB: clear all live bullets in the scene and damage every enemy by
## 2 HP. Used by both the BOMB pickup and the future HUD bomb button.
## `origin_player` is kept for future damage-source attribution.
func _bomb_blast(_origin_player: Node = null) -> void:
	# 1) Clear all bullets. Use _release_self so the pool's free list
	# grows correctly (no per-blast allocations).
	for b: Node in get_tree().get_nodes_in_group("bullets"):
		if is_instance_valid(b) and b.has_method("_release_self"):
			b._release_self()
	# 2) Damage all enemies by 2. This may trigger `died` on already-
	# weakened enemies, which scores them through the normal path.
	for e: Node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.has_method("take_damage"):
			e.take_damage(2)


## Signal: player reports a power-up state change. Forward to the HUD
## so the active-powerup label can update.
func _on_player_powerup_changed(kind: int, type_name: String, remaining: float) -> void:
	if hud and hud.has_method("set_active_powerup"):
		hud.set_active_powerup(type_name, remaining)
	# QA checkpoint (fire-and-forget). Failure to find the harness is
	# benign: it just means we're not running under the test harness.
	var harness := get_node_or_null("/root/TestHarness")
	if harness != null and harness.has_method("checkpoint"):
		harness.checkpoint({"event": "powerup_changed", "kind": kind, "name": type_name, "remaining": remaining})


## Count of currently-live enemies (for the StateServer / wave manager).
func get_enemy_count() -> int:
	# Prune stale entries defensively so the count never includes freed nodes.
	var live: Array = []
	for e: Node in _enemies:
		if is_instance_valid(e):
			live.append(e)
	_enemies = live
	return _enemies.size()


func get_game_state() -> Dictionary:
	var player_state: Dictionary = {}
	if player and player.has_method("get_state"):
		player_state = player.get_state()
	var hud_state: Dictionary = {}
	if hud and hud.has_method("get_state"):
		hud_state = hud.get_state()
	# Build the per-enemy state list. Filter out freed nodes defensively.
	var enemy_states: Array = []
	var counts: Dictionary = {"drone": 0, "fighter": 0, "bomber": 0}
	var live_enemies: Array = []
	for e: Node in _enemies:
		if not is_instance_valid(e):
			continue
		live_enemies.append(e)
		if e.has_method("get_state"):
			enemy_states.append(e.get_state())
		var etype: String = ""
		if "enemy_type_name" in e:
			etype = str(e.enemy_type_name).to_lower()
		if etype == "" or not counts.has(etype):
			etype = str(e.name).to_lower()
		if counts.has(etype):
			counts[etype] = int(counts[etype]) + 1
	_enemies = live_enemies
	return {
		"scene": "Main",
		"score": score,
		"wave": wave,
		"high_score": high_score,
		"bombs": bombs,
		"game_over": game_over,
		"player": player_state,
		"hud": hud_state,
		"enemies": enemy_states,
		"enemy_count": enemy_states.size(),
		"enemy_counts_by_type": counts,
	}
