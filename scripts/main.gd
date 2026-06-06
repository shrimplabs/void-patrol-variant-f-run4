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


func _on_player_shield_changed(current: float, max_value: float) -> void:
	if hud and hud.has_method("set_shield"):
		hud.set_shield(current, max_value)


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
	# Auto-prune when the enemy frees itself (death, off-screen, etc.).
	enemy.tree_exited.connect(_on_enemy_exited.bind(enemy))


func _on_enemy_died(score_value: int) -> void:
	# The score value is the enemy's `score_value` export (drone=10,
	# fighter=25, bomber=50). We add it to the main score; the enemy itself
	# is freed in EnemyBase._die() and pruned from _enemies by
	# _on_enemy_exited when the tree_exited signal fires.
	add_score(int(score_value))


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
