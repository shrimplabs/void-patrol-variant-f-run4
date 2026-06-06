extends Node
## Main scene controller. Owns game-wide state (score, wave) and wires the
## Player + HUD together. `get_game_state()` returns the full state dictionary
## used by the StateServer / QA harness / tests.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const HUD_SCENE := preload("res://scenes/hud.tscn")

var score: int = 0
var wave: int = 1
var high_score: int = 0
var bombs: int = 0
var game_over: bool = false

var player: Node = null
var hud: CanvasLayer = null


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


func get_game_state() -> Dictionary:
	var player_state: Dictionary = {}
	if player and player.has_method("get_state"):
		player_state = player.get_state()
	var hud_state: Dictionary = {}
	if hud and hud.has_method("get_state"):
		hud_state = hud.get_state()
	return {
		"scene": "Main",
		"score": score,
		"wave": wave,
		"high_score": high_score,
		"bombs": bombs,
		"game_over": game_over,
		"player": player_state,
		"hud": hud_state,
	}
