class_name SkillTreeLines
extends Control
## Draws the prerequisite links behind a skill tree grid: one line per
## `requires`/`requires_any` edge, from the prerequisite tile's right edge to
## the dependent tile's left edge (or top-to-bottom within a column). Gold =
## both learned, violet = the path is open (prerequisite learned), dim = not
## reached yet. Positions are read at draw time, so it redraws whenever the
## grid lays out (RosterView connects sort_children -> queue_redraw).

var edges: Array = []   # [[from: Control, to: Control, state: int (0 dim, 1 open, 2 learned)], ...]
const TILE_MID := 30.0   # vertical center of a 60px skill hex (caption below)


func _draw() -> void:
	for e in edges:
		var a: Control = e[0]
		var b: Control = e[1]
		if not is_instance_valid(a) or not is_instance_valid(b):
			continue
		var ra := a.get_global_rect()
		var rb := b.get_global_rect()
		var from: Vector2
		var to: Vector2
		if absf(ra.position.x - rb.position.x) < 4.0:
			from = Vector2(ra.get_center().x, ra.position.y + TILE_MID * 2.0)
			to = Vector2(rb.get_center().x, rb.position.y)
		else:
			from = Vector2(ra.end.x, ra.position.y + TILE_MID)
			to = Vector2(rb.position.x, rb.position.y + TILE_MID)
		from -= global_position
		to -= global_position
		var state: int = e[2]
		var color: Color = Palette.EMBER_BRIGHT if state == 2 else (Palette.VIOLET if state == 1 else Palette.LINE)
		draw_line(from, to, color, 3.0 if state == 2 else 2.0, true)
