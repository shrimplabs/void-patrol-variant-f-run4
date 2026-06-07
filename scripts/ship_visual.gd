extends Node2D
## Player ship visual. Loads a textured sprite from res://assets/sprites/player_ship.png
## and draws it centered on the origin. Falls back to a flat-colored polygon
## if the texture is missing (so headless tests still render something).

const SHIP_TEXTURE_PATH := "res://assets/sprites/player_ship.png"

var _texture: Texture2D = null


func _ready() -> void:
	# load() returns null if the file is missing; we'll fall back to a polygon.
	_texture = load(SHIP_TEXTURE_PATH) as Texture2D


func _draw() -> void:
	if _texture != null:
		var sz := _texture.get_size()
		# Center the texture on the Node2D's origin.
		_texture.draw(get_canvas_item(), Vector2(-sz.x * 0.5, -sz.y * 0.5))
		return
	# Fallback: simple cyan triangle, same as the original scaffold.
	var pts := PackedVector2Array([
		Vector2(0, -16),
		Vector2(-12, 12),
		Vector2(0, 6),
		Vector2(12, 12),
	])
	draw_colored_polygon(pts, Color(0.3, 0.8, 1.0, 1.0))
	var outline := PackedVector2Array([
		Vector2(0, -16), Vector2(-12, 12), Vector2(0, 6),
		Vector2(12, 12), Vector2(0, -16),
	])
	draw_polyline(outline, Color(0.9, 1.0, 1.0, 1.0), 2.0)
