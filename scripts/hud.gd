extends CanvasLayer
class_name HUD

## Heads-up display: score, wave, lives, shield bar.
## All fields are "placeholders" in the sense that the values are wired in,
## but the displayed text is plain for now (no fancy formatting / icons yet).

@onready var _score_label: Label = $Root/ScoreLabel
@onready var _wave_label: Label = $Root/WaveLabel
@onready var _lives_label: Label = $Root/LivesLabel
@onready var _shield_bar: ProgressBar = $Root/ShieldBar

var score: int = 0
var wave: int = 1
var lives: int = 3
var shield: float = 100.0
var max_shield: float = 100.0


func _ready() -> void:
	# Anchor the root to fill the viewport so children use viewport-relative coords.
	var root := $Root
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_refresh_all()


func set_score(value: int) -> void:
	score = value
	if _score_label:
		_score_label.text = "SCORE: %d" % score


func set_wave(value: int) -> void:
	wave = value
	if _wave_label:
		_wave_label.text = "WAVE: %d" % wave


func set_lives(value: int) -> void:
	lives = value
	if _lives_label:
		_lives_label.text = "LIVES: %d" % lives


func set_shield(value: float, max_value: float) -> void:
	shield = value
	max_shield = max_value
	if _shield_bar:
		_shield_bar.max_value = max_value
		_shield_bar.value = value


func _refresh_all() -> void:
	set_score(score)
	set_wave(wave)
	set_lives(lives)
	set_shield(shield, max_shield)


func get_state() -> Dictionary:
	return {
		"score": score,
		"wave": wave,
		"lives": lives,
		"shield": shield,
		"max_shield": max_shield,
	}
