extends Node2D
class_name RoundedRect

@export var rect_size: Vector2 = Vector2(40, 40):
	set(value):
		rect_size = value
		queue_redraw()

@export var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()

@export var corner_radius: float = 8.0:
	set(value):
		corner_radius = value
		queue_redraw()

@export var taper: float = 0.0:
	set(value):
		taper = value
		queue_redraw()

@export var anchor_bottom: bool = false:
	set(value):
		anchor_bottom = value
		queue_redraw()

@export var shine: bool = false:
	set(value):
		shine = value
		queue_redraw()

func _draw() -> void:
	var half := rect_size / 2.0
	var top_y := -rect_size.y if anchor_bottom else -half.y
	var bottom_y := 0.0 if anchor_bottom else half.y
	var top_half_w := half.x * (1.0 - taper)
	var verts := PackedVector2Array([
		Vector2(-top_half_w, top_y),
		Vector2(top_half_w, top_y),
		Vector2(half.x, bottom_y),
		Vector2(-half.x, bottom_y),
	])
	draw_polygon(_rounded_polygon(verts, corner_radius), PackedColorArray([color]))
	if shine:
		var shine_color := Color(
			minf(color.r + 0.6, 3.0),
			minf(color.g + 0.6, 3.0),
			minf(color.b + 0.6, 3.0),
			0.35
		)
		draw_set_transform(Vector2(-top_half_w * 0.4, top_y + rect_size.y * 0.22), 0.0, Vector2(0.85, 0.55))
		draw_circle(Vector2.ZERO, top_half_w * 0.55, shine_color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _rounded_polygon(verts: PackedVector2Array, radius: float, segs: int = 6) -> PackedVector2Array:
	if radius <= 0.0:
		return verts
	var out := PackedVector2Array()
	var n := verts.size()
	for i in range(n):
		var prev: Vector2 = verts[(i - 1 + n) % n]
		var curr: Vector2 = verts[i]
		var nxt: Vector2 = verts[(i + 1) % n]
		var to_prev := prev - curr
		var to_next := nxt - curr
		var len_prev := to_prev.length()
		var len_next := to_next.length()
		if len_prev < 0.001 or len_next < 0.001:
			out.append(curr)
			continue
		var r := minf(radius, minf(len_prev, len_next) * 0.5)
		var p1 := curr + to_prev.normalized() * r
		var p2 := curr + to_next.normalized() * r
		out.append(p1)
		for s in range(1, segs):
			var t := s / float(segs)
			var pt: Vector2 = p1.lerp(curr, t).lerp(curr.lerp(p2, t), t)
			out.append(pt)
		out.append(p2)
	return out
