extends EndgameOverlay
class_name GameOverOverlay
## GameOverOverlay -- end-of-run screen shown when the player dies.
##
## Inherits all layout / input handling from EndgameOverlay. The only
## differences are the headline text, the prompt text, and the action
## signal (we want `restart_pressed` so main.gd can immediately begin a
## new run on Enter).


func _ready() -> void:
	set_headline("GAME  OVER")
	set_prompt_text("PRESS  ENTER  TO  RESTART")
	super._ready()


func _emit_action() -> void:
	restart_pressed.emit()
