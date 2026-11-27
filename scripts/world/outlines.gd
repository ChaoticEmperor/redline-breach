extends Node2D
## Draws the black outline along every edge where a wall meets the floor (once, not per tile),
## so walls read as one continuous shape, as objects are outlined and floors are not.

const Level = preload("res://scripts/level.gd")

var cells: Dictionary


func setup(p_cells: Dictionary) -> void:
	cells = p_cells
	queue_redraw()


func _draw() -> void:
	var t := Level.TILE
	for cell in cells:
		if not Level.is_solid(cells[cell]):
			continue
		var o := Vector2(cell) * t
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: String = cells.get(cell + d, "#")
			if Level.is_solid(n):
				continue
			match d:
				Vector2i.LEFT: draw_rect(Rect2(o, Vector2(2, t)), Color.BLACK)
				Vector2i.RIGHT: draw_rect(Rect2(o + Vector2(t - 2, 0), Vector2(2, t)), Color.BLACK)
				Vector2i.UP: draw_rect(Rect2(o, Vector2(t, 2)), Color.BLACK)
				Vector2i.DOWN: draw_rect(Rect2(o + Vector2(0, t - 2), Vector2(t, 2)), Color.BLACK)
