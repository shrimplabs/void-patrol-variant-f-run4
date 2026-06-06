extends Node2D
## Simple triangle ship visual for the player. Drawn in code so we don't
## need an imported art asset for this scaffold.

func _draw() -> void:
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
