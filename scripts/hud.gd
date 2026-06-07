extends CanvasLayer
class_name HUD

## Heads-up display: score, wave, lives, shield bar.
## All fields are "placeholders" in the sense that the values are wired in,
## but the displayed text is plain for now (no fancy formatting / icons yet).

const LOW_SHIELD_THRESHOLD := 0.25
const LOW_SHIELD_PULSE_HZ := 4.0

@onready var _score_label: Label = $Root/ScoreLabel
@onready var _wave_label: Label = $Root/WaveLabel
@onready var _lives_label: Label = $Root/LivesLabel
@onready var _shield_bar: ProgressBar = $Root/ShieldBar
# The following four nodes are optional: in the test_hud.gd minimal
# fixture only ScoreLabel/WaveLabel/LivesLabel/ShieldBar exist, so we
# must use get_node_or_null to avoid "Node not found" errors at
# @implicit_ready. All consumers already null-guard these vars.
@onready var _shield_label: Label = get_node_or_null("Root/ShieldLabel")
@onready var _powerup_label: Label = get_node_or_null("Root/PowerupLabel")
@onready var _damage_flash: ColorRect = get_node_or_null("Root/DamageFlash")
@onready var _banner_label: Label = get_node_or_null("Root/BannerLabel")

var score: int = 0
var wave: int = 1
var lives: int = 3
var shield: float = 100.0
var max_shield: float = 100.0
## Currently-displayed active power-up. Empty string = no powerup.
var active_powerup_name: String = ""
## Remaining seconds on the active power-up (0 = instant / expired).
var active_powerup_remaining: float = 0.0

var _flash_tween: Tween = null
var _pulse_tween: Tween = null
var _banner_tween: Tween = null
## Current banner text. Empty string means "no banner visible".
var _banner_text: String = ""


func _ready() -> void:
	# Anchor the root to fill the viewport so children use viewport-relative coords.
	var root := $Root
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Make sure the damage flash starts fully transparent and doesn't intercept clicks.
	if _damage_flash:
		_damage_flash.modulate.a = 0.0
		_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Banner starts hidden (no modulate animation needed; show_banner
	# handles fade-in/fade-out via the tween).
	if _banner_label:
		_banner_label.modulate.a = 0.0
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


## Show a banner with the given text for `duration` seconds. The banner
## fades in over 0.15s, holds for the remainder, then fades out. Used by
## the wave manager for "INCOMING WAVE n" / "WAVE n CLEAR" / "BOSS
## INCOMING". A subsequent call replaces any in-flight banner.
func show_banner(text: String, duration: float = 1.5) -> void:
	if _banner_label == null:
		return
	_banner_text = text
	_banner_label.text = text
	if _banner_tween and _banner_tween.is_running():
		_banner_tween.kill()
	# Snap to fully visible, then fade out at the end of the hold.
	_banner_label.modulate.a = 1.0
	# Reserve 0.35s for the fade-out tail. If the caller asked for a
	# very short duration (< 0.35s) just snap through.
	var hold: float = max(0.05, duration - 0.35)
	_banner_tween = create_tween()
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(_banner_label, "modulate:a", 0.0, 0.35)


## Hide any active banner immediately. Used when the game ends or the
## player loses so the INCOMING banner doesn't linger.
func hide_banner() -> void:
	if _banner_label == null:
		return
	if _banner_tween and _banner_tween.is_running():
		_banner_tween.kill()
	_banner_label.modulate.a = 0.0
	_banner_text = ""


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
	set_active_powerup(active_powerup_name, active_powerup_remaining)


## Set the active power-up label. `name` is the human-readable type
## (e.g. "DOUBLE SHOT"), `remaining` is the seconds left (0 = no timer,
## "" or negative = clear the label). The label lives above the shield
## bar (added in hud.tscn as PowerupLabel).
func set_active_powerup(powerup_name: String, remaining: float) -> void:
	# When the timer runs out (or no name is given), clear BOTH the name
	# and the remaining time. The previous version only cleared the label
	# text, which left `active_powerup_name` stale for queries that read
	# the field directly (e.g. the StateServer / tests / future UI code).
	if powerup_name == "" or remaining <= 0.0:
		active_powerup_name = ""
		active_powerup_remaining = 0.0
		if _powerup_label != null:
			_powerup_label.text = ""
		return
	active_powerup_name = powerup_name
	active_powerup_remaining = remaining
	if _powerup_label != null:
		_powerup_label.text = "%s  %.1fs" % [powerup_name, remaining]
	# Format: "DOUBLE SHOT  12.3s". One decimal place is enough for the
	# "how much longer does this last" UI hint; integer seconds would
	# feel jumpy.
	_powerup_label.text = "%s  %.1fs" % [powerup_name, remaining]


## Continuously update the active power-up's remaining time on screen.
## Called every physics frame from _process; cheap when the label is
## empty (text is already blank and the format pass is skipped).
func _process(_delta: float) -> void:
	if active_powerup_remaining > 0.0 and active_powerup_name != "":
		active_powerup_remaining = max(0.0, active_powerup_remaining - _delta)
		if _powerup_label != null:
			_powerup_label.text = "%s  %.1fs" % [active_powerup_name, active_powerup_remaining]
		if active_powerup_remaining <= 0.0:
			# Countdown reached zero -- clear the label so the UI doesn't
			# show a stale "0.0s" frame.
			if _powerup_label != null:
				_powerup_label.text = ""


func get_state() -> Dictionary:
	return {
		"score": score,
		"wave": wave,
		"lives": lives,
		"shield": shield,
		"max_shield": max_shield,
		"active_powerup_name": active_powerup_name,
		"active_powerup_remaining": active_powerup_remaining,
		"banner_text": _banner_text,
	}
