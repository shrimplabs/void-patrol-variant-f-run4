extends Node

func get_game_state() -> Dictionary:
    return {"scene": get_tree().current_scene.name if get_tree().current_scene else "Main"}
