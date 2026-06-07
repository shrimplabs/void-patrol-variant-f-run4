extends CanvasLayer
class_name HUD

## Heads-up display: score, wave, lives, shield bar.
## All fields are "placeholders" in the sense that the values are wired in,
## but the displayed text is plain for now (no fancy formatting / icons yet).

const LOW_SHIELD_THRESHOLD := 0.30
const LOW_SHIELD_PULSE_HZ := 4.0

@onready var _score_label: Label = $Root/ScoreLabel
@onready var _wave_label: Label = $Root/WaveLabel
@onready var _lives_label: Label = $Root/LivesLabel
@onready var _shield_bar: ProgressBar = $Root/ShieldBar
@onready var _shield_label: Label = $Root/ShieldLabel
@onready var _damage_flash: ColorRect = $Root/DamageFlash

var score: int = 0
var wave: int = 1
var lives: int = 3
var shield: float = 100.0
var max_shield: float = 100.0

var _flash_tween: Tween = null
var _pulse_tween: Tween = null


func _ready() -> void:
	# Anchor the root to fill the viewport so children use viewport-relative coords.
	var root := $Root
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Make sure the damage flash starts fully transparent and doesn't intercept clicks.
	if _damage_flash:
		_damage_flash.modulate.a = 0.0
		_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_all()


func set_score(value: int) -> void:
	score = value
	if _score_label:
		_score_label.text = "SCORE  %d" % score


func set_wave(value: int) -> void:
	wave = value
	if _wave_label:
		_wave_label.text = "WAVE  %d" % wave


func set_lives(value: int) -> void:
	lives = value
	if _lives_label:
		_lives_label.text = "LIVES  %d" % lives


func set_shield(value: float, max_value: float) -> void:
	shield = value
	max_shield = max_value
	if _shield_bar:
		_shield_bar.max_value = max_value
		_shield_bar.value = value
		# Recolor the bar fill so it visually communicates danger at low shield.
		var ratio: float = 0.0
		if max_value > 0.0:
			ratio = value / max_value
		var style: Variant = _shield_bar.get("theme_override_styles/fill")
		if style is StyleBoxFlat:
			(style as StyleBoxFlat).bg_color = _shield_color(ratio)
	_update_low_shield_pulse()


## Flash the screen red briefly to communicate damage was taken. `amount`
## is informational only (kept in the API for future use such as scaling
## the flash intensity with damage severity).
func flash_damage(_amount: float = 0.0) -> void:
	if _damage_flash == null:
		return
	if _flash_tween and _flash_tween.is_running():
		_flash_tween.kill()
	# Snap to fully visible, then fade out.
	_damage_flash.modulate.a = 0.55
	_flash_tween = create_tween()
	_flash_tween.tween_property(_damage_flash, "modulate:a", 0.0, 0.35)


func _shield_color(ratio: float) -> Color:
	# Green at full shield, yellow around 50%, red below the low-shield threshold.
	if ratio > 0.55:
		return Color(0.30, 0.85, 0.45, 1.0)
	elif ratio > LOW_SHIELD_THRESHOLD:
		return Color(0.95, 0.80, 0.20, 1.0)
	else:
		return Color(0.95, 0.25, 0.20, 1.0)


func _update_low_shield_pulse() -> void:
	if _shield_bar == null:
		return
	var ratio: float = 0.0
	if max_shield > 0.0:
		ratio = shield / max_shield
	if ratio <= LOW_SHIELD_THRESHOLD and ratio > 0.0:
		if _pulse_tween == null or not _pulse_tween.is_running():
			_pulse_tween = create_tween().set_loops()
			_pulse_tween.tween_property(_shield_bar, "modulate:a", 0.4, 1.0 / (LOW_SHIELD_PULSE_HZ * 2.0))
			_pulse_tween.tween_property(_shield_bar, "modulate:a", 1.0, 1.0 / (LOW_SHIELD_PULSE_HZ * 2.0))
	else:
		if _pulse_tween and _pulse_tween.is_running():
			_pulse_tween.kill()
		_shield_bar.modulate.a = 1.0


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
