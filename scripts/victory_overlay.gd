extends EndgameOverlay
class_name VictoryOverlay
## VictoryOverlay -- end-of-run screen shown when the player defeats
## the boss.
##
## Inherits all layout / input handling from EndgameOverlay. Emits
## `continue_pressed` (not `restart_pressed`) when the player presses
## Enter, so main.gd can route them back to the menu -- where the
## difficulty is incremented -- before they can start a new run.


func _ready() -> void:
	set_headline("VICTORY")
	set_prompt_text("PRESS  ENTER  TO  CONTINUE")
	super._ready()


func _emit_action() -> void:
	continue_pressed.emit()
