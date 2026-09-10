extends Node

func _plot(shape: PlasmaBlob.Shape) -> void:
	var r := 18.0
	var centre := Vector2(0.0, -r)
	var peak := 0.0
	var lo := INF
	var hi := -INF
	var wide := 0.0
	for i in range(1440):
		var a := TAU * float(i) / 1440.0
		var mul := PlasmaBlob.shape_radius(a, shape)
		peak = maxf(peak, mul)
		var pt: Vector2 = centre + Vector2(cos(a), sin(a)) * r * mul
		lo = minf(lo, pt.y); hi = maxf(hi, pt.y); wide = maxf(wide, absf(pt.x))
	print("%-8s peak %.3f | y %6.1f..%6.1f (h %.1f) | width %.1f" % [
		PlasmaBlob.Shape.keys()[shape], peak, lo, hi, hi - lo, wide * 2.0])
	var grid := []
	for row in range(28):
		var line := ""
		for col in range(45):
			var x := (col - 22) * 1.25
			var y := (row - 27) * 1.85
			var d := Vector2(x, y) - centre
			var lim: float = r * PlasmaBlob.shape_radius(d.angle(), shape)
			line += "#" if d.length() <= lim else ("_" if row == 27 else " ")
		grid.append(line)
	print("\n".join(grid))
	print("")

func _ready() -> void:
	for s in [PlasmaBlob.Shape.HEART, PlasmaBlob.Shape.FLAME, PlasmaBlob.Shape.CIRCLE]:
		_plot(s)
	get_tree().quit()
