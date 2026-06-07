extends CanvasLayer
class_name MenuOverlay
## MenuOverlay -- start menu for Void Patrol.
##
## Full-screen overlay shown at boot. Displays the title, the persisted
## high score (if any), and the current difficulty loop count. A pulsing
## "PRESS  ENTER  TO  START" prompt at the bottom.
##
## Listens for the standard "ui_accept" / Enter action (plus Space and
## Start on gamepads) and emits `start_pressed` so main.gd can begin a
## new session.
##
## When hidden via `hide_menu()`, input is ignored so the player's key
## taps don't carry over to gameplay.

signal start_pressed
signal exit_pressed

## The "PRESS  ENTER  TO  START" label. Updated by `_refresh_labels`
## (and again on each `_process` pulse so the prompt blinks).
@onready var _prompt: Label = $Root/Content/Prompt
## The title label ("VOID  PATROL").
@onready var _title: Label = $Root/Content/Title
## The high-score line ("HIGH  SCORE  12345").
@onready var _high_score_label: Label = $Root/Content/HighScore
## The difficulty line ("DIFFICULTY  1" / hidden when difficulty == 0).
@onready var _difficulty_label: Label = $Root/Content/Difficulty

## Cached values used by `_refresh_labels`. Updated by main.gd via
## `set_high_score()` / `set_difficulty()`.
var _high_score: int = 0
var _difficulty: int = 0
## Pulse phase for the prompt blink. 0..1 mapped to alpha 0.3..1.0
## every PROMPT_BLINK_SECONDS. Kept as a member so we can drive it
## from `_process` without allocations.
var _blink_t: float = 0.0
## How long one full blink cycle takes (in seconds).
const PROMPT_BLINK_SECONDS := 1.2
## How long the menu takes to fade IN from invisible to fully
## visible. 0.3s feels intentional without delaying the first
## interaction -- the title is up before the player finishes
## lifting their hand off the previous screen.
const MENU_FADE_IN_SECONDS := 0.3
## How long the menu takes to fade OUT. Slightly shorter than the
## fade-in so the gameplay reveal feels snappy (the player just
## confirmed the start, they want to play).
const MENU_FADE_OUT_SECONDS := 0.2
## Active fade tween for the Root control's modulate.a. Killed on
## any new show/hide so a quick menu->game->menu toggle doesn't
## double-animate. Auto-cleared by Godot when the tween finishes.
var _root_tween: Tween = null


func _ready() -> void:
	# Anchor the root to the full viewport so all children use
	# viewport-relative offsets. PRESET_FULL_RECT = 15.
	var root := $Root
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The dim background ColorRect is the first child so it renders
	# behind the text. mouse_filter=IGNORE so it never blocks clicks.
	var dim := $Root/Dim
	if dim is ColorRect:
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Connect the start button if present (the .tscn wires a Button
	# named "StartButton"). Both keyboard and click paths emit the
	# same signal so main.gd doesn't need to know which triggered it.
	var btn := get_node_or_null("Root/Content/StartButton")
	if btn and btn is Button and not btn.pressed.is_connected(_on_start_button_pressed):
		(btn as Button).pressed.connect(_on_start_button_pressed)
	# Hide the in-scene start button -- we drive the prompt with the
	# label, not a click target. The button is kept in the tree for
	# accessibility (a screen-reader user can still tab to it) but
	# invisible.
	if btn and btn is Button:
		(btn as Button).modulate.a = 0.0
	_refresh_labels()
	# Intro fade-in: start the menu at alpha 0 and tween to 1 so the
	# title appears smoothly when the game boots. Skipped when the
	# Root is already mostly visible (defensive -- e.g. a re-shown
	# overlay that was kept at full alpha in the background).
	if root.modulate.a < 0.999:
		root.modulate.a = 0.0
		if _root_tween != null and _root_tween.is_valid():
			_root_tween.kill()
		_root_tween = create_tween()
		_root_tween.tween_property(root, "modulate:a", 1.0, MENU_FADE_IN_SECONDS)


func _process(delta: float) -> void:
	# Blink the prompt when the menu is visible. Cheap; no allocation.
	if _prompt == null or not visible:
		return
	_blink_t = fposmod(_blink_t + delta, PROMPT_BLINK_SECONDS)
	# Smooth (sin-based) pulse from 0.3 to 1.0 alpha.
	var phase: float = _blink_t / PROMPT_BLINK_SECONDS
	var alpha: float = 0.65 + 0.35 * sin(phase * TAU)
	_prompt.modulate.a = alpha


func _unhandled_input(event: InputEvent) -> void:
	# Only react when the menu is actually visible -- a hidden overlay
	# shouldn't swallow key events meant for gameplay.
	if not visible:
		return
	# ui_accept covers Enter / Space / gamepad Start on the default
	# input map. We also accept the explicit "ui_select" so controllers
	# that map Start to a different action still work.
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		start_pressed.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		exit_pressed.emit()
		get_viewport().set_input_as_handled()


func set_high_score(value: int) -> void:
	_high_score = int(value)
	_refresh_labels()


func set_difficulty(value: int) -> void:
	_difficulty = int(value)
	_refresh_labels()


## Show the menu. If the menu is currently fading out (or fully
## hidden), the Root control snaps to alpha 0 and tweens to 1 over
## MENU_FADE_IN_SECONDS. A re-show on an already-fully-visible
## menu is a no-op (just refreshes the labels).
func show_menu() -> void:
	if _root_tween != null and _root_tween.is_valid():
		_root_tween.kill()
	visible = true
	_refresh_labels()
	var root := $Root
	if root.modulate.a < 0.999:
		root.modulate.a = 0.0
		_root_tween = create_tween()
		_root_tween.tween_property(root, "modulate:a", 1.0, MENU_FADE_IN_SECONDS)


## Hide the menu with a quick fade-out. The CanvasLayer is left
## visible until the tween finishes, then `visible` is cleared so
## the gameplay input reaches the player again. The fade is short
## enough that the delay between "Enter" and "gameplay reacting" is
## not noticeable.
func hide_menu() -> void:
	if _root_tween != null and _root_tween.is_valid():
		_root_tween.kill()
	var root := $Root
	_root_tween = create_tween()
	_root_tween.tween_property(root, "modulate:a", 0.0, MENU_FADE_OUT_SECONDS)
	_root_tween.tween_callback(func() -> void:
		visible = false
	)


func _refresh_labels() -> void:
	if _title:
		_title.text = "VOID  PATROL"
	if _prompt:
		_prompt.text = "PRESS  ENTER  TO  START"
	if _high_score_label:
		if _high_score > 0:
			_high_score_label.text = "HIGH  SCORE  %d" % _high_score
			_high_score_label.visible = true
		else:
			# Hide the line entirely on a fresh save so the menu doesn't
			# show "HIGH SCORE  0" clutter.
			_high_score_label.visible = false
	if _difficulty_label:
		if _difficulty > 0:
			_difficulty_label.text = "DIFFICULTY  %d" % _difficulty
			_difficulty_label.visible = true
		else:
			_difficulty_label.visible = false


func _on_start_button_pressed() -> void:
	start_pressed.emit()
