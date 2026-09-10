extends Control
class_name LineGraph

## A minimal hand-drawn trend line -- no plotting library, so it matches the
## rest of the project's habit of drawing its own visuals (see rounded_rect.gd,
## platform_decor.gd) instead of pulling one in.

@export var line_color: Color = Color(0.3, 1.8, 2.4)
@export var point_color: Color = Color(1.6, 2.2, 2.6)
@export var baseline_color: Color = Color(1.0, 1.0, 1.0, 0.15)
@export var line_width: float = 3.0
@export var point_radius: float = 4.0
@export var top_pad: float = 16.0
@export var bottom_pad: float = 16.0
@export var side_pad: float = 10.0

var _values: Array = []

func set_values(values: Array) -> void:
	_values = values
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var base_y := h - bottom_pad
	var top_y := top_pad
	var mid_y := (top_y + base_y) / 2.0
	# Top and mid reference lines, so the labels statistics.gd places beside
	# them (max_value() / max_value() * 0.5) land on something -- a bare
	# number floating next to the graph doesn't read as a scale.
	draw_line(Vector2(0.0, base_y), Vector2(w, base_y), baseline_color, 1.0)
	draw_line(Vector2(0.0, mid_y), Vector2(w, mid_y), baseline_color, 1.0)
	draw_line(Vector2(0.0, top_y), Vector2(w, top_y), baseline_color, 1.0)
	if _values.is_empty():
		return
	if _values.size() == 1:
		draw_circle(Vector2(w * 0.5, base_y - _normalized(_values[0]) * (h - top_pad - bottom_pad)), point_radius, point_color)
		return
	var usable_h := h - top_pad - bottom_pad
	var usable_w := w - side_pad * 2.0
	var step := usable_w / float(_values.size() - 1)
	var points := PackedVector2Array()
	for i in range(_values.size()):
		var x := side_pad + step * i
		var y := base_y - _normalized(_values[i]) * usable_h
		points.append(Vector2(x, y))
	draw_polyline(points, line_color, line_width, true)
	for i in range(points.size()):
		var r := point_radius * (1.4 if i == points.size() - 1 else 1.0)
		draw_circle(points[i], r, point_color)

## The value the top gridline represents. Exposed so statistics.gd can label
## the top and mid reference lines without duplicating this scan.
func max_value() -> float:
	var max_v := 1.0
	for v in _values:
		max_v = maxf(max_v, v)
	return max_v

func _normalized(value: float) -> float:
	return value / max_value()
