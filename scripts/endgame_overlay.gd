extends CanvasLayer
class_name EndgameOverlay
## EndgameOverlay -- shared base for the GAME_OVER and VICTORY screens.
##
## Both screens show a headline ("GAME  OVER" / "VICTORY"), a final-score
## line, a high-score line, and a "PRESS  ENTER" prompt. The differences
## are the headline text and the high-score celebratory line ("NEW
## HIGH  SCORE!" when the just-finished run beat the previous best).
##
## Subclasses set `headline_text` / `prompt_text` in `_ready` and call
## `set_summary(final_score, high_score, is_new_high)` to populate the
## labels. They also wire a `restart_pressed` / `continue_pressed` signal
## back to main.gd.

signal restart_pressed
signal continue_pressed

## The big headline label ("GAME  OVER" / "VICTORY"). Subclasses set this
## in `_ready` before the call to `_refresh_labels`.
@onready var _headline: Label = $Root/Content/Headline
## The final-score line ("SCORE  12345").
@onready var _score_label: Label = $Root/Content/Score
## The high-score line ("HIGH  SCORE  99999" or "NEW  HIGH  SCORE!  99999").
@onready var _high_score_label: Label = $Root/Content/HighScore
## The "PRESS  ENTER  TO  RESTART" / "PRESS  ENTER  TO  CONTINUE" label.
@onready var _prompt: Label = $Root/Content/Prompt

## Headline text set by the subclass. The base class defers to the
## subclass via the headline() virtual.
var _headline_text: String = ""
## Prompt text set by the subclass.
var _prompt_text: String = "PRESS  ENTER  TO  RESTART"
## Cached score values. Updated by set_summary().
var _final_score: int = 0
var _displayed_high_score: int = 0
var _is_new_high: bool = false

## Pulse phase for the prompt blink.
var _blink_t: float = 0.0
## Blink period (seconds). Matches MenuOverlay for visual consistency.
const PROMPT_BLINK_SECONDS := 1.2
## How long the game-over / victory overlay takes to fade in. The
## overlay is shown on a high-stakes moment (player just died or
## just won), so a slightly longer fade than the menu lets the
## player absorb the result before the prompt demands a press.
const OVERLAY_FADE_IN_SECONDS := 0.35
## How long the overlay takes to fade out. Slightly shorter than
## the fade-in -- the player has already chosen, they just want
## the next screen up.
const OVERLAY_FADE_OUT_SECONDS := 0.2
## Active fade tween for the Root control's modulate.a. Killed on
## any new show/hide so a quick game-over->menu->play->game-over
## cycle doesn't double-animate. Auto-cleared by Godot when the
## tween finishes.
var _root_tween: Tween = null


func _ready() -> void:
	# Anchor root to the full viewport. PRESET_FULL_RECT = 15.
	var root := $Root
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The dim ColorRect is the first child, behind the text, and must
	# not intercept clicks.
	var dim := $Root/Dim
	if dim is ColorRect:
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Wire the in-scene restart/continue button (the .tscn wires a
	# Button named "ActionButton"). We keep the button invisible (we
	# drive the prompt with the label) but its pressed signal still
	# fires for accessibility.
	var btn := get_node_or_null("Root/Content/ActionButton")
	if btn and btn is Button and not (btn as Button).pressed.is_connected(_on_action_button_pressed):
		(btn as Button).pressed.connect(_on_action_button_pressed)
	if btn and btn is Button:
		(btn as Button).modulate.a = 0.0
	_refresh_labels()


func _process(delta: float) -> void:
	if _prompt == null or not visible:
		return
	_blink_t = fposmod(_blink_t + delta, PROMPT_BLINK_SECONDS)
	var phase: float = _blink_t / PROMPT_BLINK_SECONDS
	var alpha: float = 0.65 + 0.35 * sin(phase * TAU)
	_prompt.modulate.a = alpha


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Either ui_accept (Enter / Space / gamepad Start) or ui_select
	# triggers the action. The two signals (restart vs continue) are
	# semantic -- subclasses emit the right one.
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		_emit_action()
		get_viewport().set_input_as_handled()
		return


## Set the headline text (e.g. "GAME  OVER" or "VICTORY").
func set_headline(text: String) -> void:
	_headline_text = text
	_refresh_labels()


## Set the prompt text (e.g. "PRESS  ENTER  TO  RESTART" / "PRESS  ENTER  TO  CONTINUE").
func set_prompt_text(text: String) -> void:
	_prompt_text = text
	_refresh_labels()


## Populate the summary block. `is_new_high` triggers the celebratory
## "NEW  HIGH  SCORE!" line and re-tints the high-score label in gold.
func set_summary(final_score: int, high_score: int, is_new_high: bool) -> void:
	_final_score = int(final_score)
	_displayed_high_score = int(high_score)
	_is_new_high = bool(is_new_high)
	_refresh_labels()


## Show the overlay with a fade-in. The Root control snaps to
## alpha 0 and tweens to 1 over OVERLAY_FADE_IN_SECONDS, so the
## result (game over / victory) is revealed gently instead of
## popping in. Public-ish: called from main.gd whenever the session
## transitions to GAME_OVER or VICTORY.
func show_overlay() -> void:
	if _root_tween != null and _root_tween.is_valid():
		_root_tween.kill()
	visible = true
	_refresh_labels()
	var root := $Root
	root.modulate.a = 0.0
	_root_tween = create_tween()
	_root_tween.tween_property(root, "modulate:a", 1.0, OVERLAY_FADE_IN_SECONDS)


## Hide the overlay with a quick fade-out. The CanvasLayer stays
## visible until the tween finishes, then `visible` is cleared so
## the next session can drive input through the gameplay layer
## (or the menu overlay can take over). Called from main.gd on
## restart from game-over, or when the menu is re-shown after
## victory.
func hide_overlay() -> void:
	if _root_tween != null and _root_tween.is_valid():
		_root_tween.kill()
	var root := $Root
	_root_tween = create_tween()
	_root_tween.tween_property(root, "modulate:a", 0.0, OVERLAY_FADE_OUT_SECONDS)
	_root_tween.tween_callback(func() -> void:
		visible = false
	)


func _refresh_labels() -> void:
	if _headline:
		_headline.text = _headline_text
	if _score_label:
		_score_label.text = "SCORE  %d" % _final_score
	if _high_score_label:
		if _is_new_high and _final_score > 0:
			_high_score_label.text = "NEW  HIGH  SCORE!  %d" % _final_score
			# Gold tint for the celebratory line.
			_high_score_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1))
		else:
			_high_score_label.text = "HIGH  SCORE  %d" % _displayed_high_score
			_high_score_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 1))
	if _prompt:
		_prompt.text = _prompt_text


## Virtual: subclasses override to emit the correct action signal.
func _emit_action() -> void:
	# Default to restart_pressed; GameOverOverlay and VictoryOverlay
	# override this to emit the correct signal.
	restart_pressed.emit()


func _on_action_button_pressed() -> void:
	_emit_action()
