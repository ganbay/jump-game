extends Node2D
class_name StarSurface

## Photosphere detail for the intro's giant star, drawn on top of the PlasmaBlob
## disc that provides the body and limb darkening underneath.
##
## PlasmaBlob alone can only ever make a disc of concentric wobbling rings: the
## churn is radial, so it reads as a blob breathing rather than as a surface. A
## star reads as a star because of what happens *across* the face -- convection
## cells boiling, spots rotating with the body, plasma arcing off the edge --
## and none of that is expressible as a radius-vs-angle function.
##
## Everything here is projected off a unit sphere rather than scattered on a
## flat disc. That is what sells the volume: features foreshorten into slivers
## as they approach the limb and disappear round the back, so the disc reads as
## a ball that is turning instead of a circle with speckles on it.
##
## Bottom-anchored to match PlasmaBlob: the star's centre sits one `radius`
## above this node's origin.

## Matched to the parent blob by IntroSequence.begin().
@export var radius: float = 2600.0:
	set(value):
		radius = value
		queue_redraw()
@export var color: Color = Color(2.6, 1.0, 0.15, 1.0):
	set(value):
		color = value
		queue_redraw()

## Master rate. Everything below is expressed relative to this, so the whole
## surface can be calmed or agitated with one number.
@export var speed: float = 1.0

@export_group("Rotation")
## Radians per second of stellar rotation. Deliberately slow -- this is what
## makes the star read as enormous. A fast spin reads as a beach ball.
@export var rotation_speed: float = 0.045
## Tips the rotation axis out of the screen plane so features track along
## curved paths rather than sliding straight across, which is the other half of
## reading as a sphere.
@export var axis_tilt: float = 0.30

@export_group("Granulation")
## Convection cells. A *giant* star has few, enormous ones -- Betelgeuse has a
## handful covering whole hemispheres -- not the Sun's countless small ones, so
## this stays low and `granule_size` stays large.
@export var granule_count: int = 24
## Cell radius as a fraction of the star's radius.
@export var granule_size: float = 0.30
## How much brighter a cell's crown is than the photosphere under it. Kept low:
## the cells only have to be *visible* against the body, and pushing them bright
## enough to blow out under glow is what turns granulation into a rash of hot
## spots rather than a surface.
@export var granule_bright: float = 0.26
## Darkening of the intergranular lane ringing each cell. The lanes are what
## actually make granulation legible -- without them the cells merge into an
## even wash -- and leaning on them rather than on `granule_bright` is how the
## texture stays readable while the star as a whole gets dimmer.
@export var granule_dark: float = 0.34
## Rate each cell brightens and fades on its own phase, as cells overturn.
@export var granule_flicker: float = 0.38

@export_group("Starspots")
## Cool, dark regions. Two or three is plenty: they are landmarks that make the
## rotation readable, and more than that reads as dirt on the lens.
@export var spot_count: int = 3
@export var spot_size: float = 0.20
@export var spot_darkness: float = 0.40

@export_group("Prominences")
## Loops of plasma arcing off the limb and falling back. These are the single
## most star-specific silhouette cue -- nothing else looks like them.
@export var prominence_count: int = 4
## Apex height as a fraction of the star's radius.
@export var prominence_height: float = 0.17
## Seconds for one loop to rise and fall.
@export var prominence_cycle: float = 6.0
@export var prominence_width: float = 0.022

## Cell outline resolution. Low on purpose -- these are soft blobs seen through
## a lot of atmosphere, not hard-edged shapes.
const _CELL_SEGMENTS := 14
## Steps along a prominence loop's arc.
const _LOOP_STEPS := 14
## Golden angle: spreads Fibonacci-sphere points evenly with no seam or pole
## clustering, so cells cover the disc without visible rows.
const _GOLDEN_ANGLE := 2.399963229728653

## Where granulation stops, as a fraction of the radius. Cells are faded out
## before they reach the limb rather than clipped at it: limb darkening means a
## real star's granulation is invisible in that last rim anyway, and fading
## avoids ever having to clip a cell against a perimeter that is itself
## wobbling under us in the parent node.
const _LIMB_FADE_IN := 0.80
const _LIMB_FADE_OUT := 0.94

var _t: float = 0.0

func _process(delta: float) -> void:
	_t += delta * speed
	queue_redraw()

## Deterministic per-feature noise in [0, 1). Same trick the eruption uses: the
## features must keep their identity frame to frame, so this is hashed off the
## index rather than drawn from randf().
static func _rand(i: int, salt: float) -> float:
	var n := sin(float(i) * 12.9898 + salt * 78.233) * 43758.5453
	return n - floor(n)

## `i`th of `count` points spread evenly over a unit sphere.
static func _sphere_point(i: int, count: int) -> Vector3:
	var y := 1.0 - 2.0 * (float(i) + 0.5) / float(count)
	var r := sqrt(maxf(0.0, 1.0 - y * y))
	var phi := float(i) * _GOLDEN_ANGLE
	return Vector3(cos(phi) * r, y, sin(phi) * r)

## Spins a surface point about the (tilted) rotation axis to where it is now.
func _rotate(p: Vector3) -> Vector3:
	var a := _t * rotation_speed
	var ca := cos(a)
	var sa := sin(a)
	var x := p.x * ca + p.z * sa
	var z := -p.x * sa + p.z * ca
	var ct := cos(axis_tilt)
	var st := sin(axis_tilt)
	return Vector3(x, p.y * ct - z * st, p.y * st + z * ct)

func _draw() -> void:
	var centre := Vector2(0.0, -radius)
	_draw_granulation(centre)
	_draw_spots(centre)
	_draw_prominences(centre)

## One surface cell, as a lane-ringed blob foreshortened onto the sphere.
## `tint`/`alpha` are applied by the caller so granules and spots can share the
## whole projection without sharing a palette.
func _draw_cell(centre: Vector2, p: Vector3, size: float, seed_i: int,
		lane: Color, fill: Color) -> void:
	var q := _rotate(p)
	# q.z > 0 is the near hemisphere. Cells swing round the back rather than
	# vanishing at the edge of the disc, so this is the visibility test.
	if q.z <= 0.0:
		return
	var offset := Vector2(q.x, -q.y)
	var rho := offset.length()
	# Faded out before the rim, and out again as the cell turns away, so
	# nothing ever pops in or out at the limb.
	var edge := 1.0 - smoothstep(_LIMB_FADE_IN, _LIMB_FADE_OUT, rho)
	var facing := smoothstep(0.0, 0.35, q.z)
	var visibility := edge * facing
	if visibility <= 0.01:
		return

	# Radial axis compresses by q.z -- a circle on the sphere projects to an
	# ellipse squashed towards the limb -- while the tangential axis keeps its
	# length. This is the whole reason the disc reads as a ball.
	var radial := offset / rho if rho > 0.001 else Vector2.RIGHT
	var tangent := radial.orthogonal()
	var pos := centre + offset * radius

	var lane_col := lane
	lane_col.a *= visibility
	var fill_col := fill
	fill_col.a *= visibility

	# Lane first, slightly larger, then the cell over it: where two cells
	# overlap, the gap between their fills stays dark and reads as the
	# intergranular network.
	_draw_blob(pos, radial, tangent, size * radius * 1.18, q.z, seed_i, lane_col)
	_draw_blob(pos, radial, tangent, size * radius, q.z, seed_i, fill_col)

func _draw_blob(pos: Vector2, radial: Vector2, tangent: Vector2, size: float,
		squash: float, seed_i: int, col: Color) -> void:
	var pts := PackedVector2Array()
	pts.resize(_CELL_SEGMENTS)
	var phase := _rand(seed_i, 3.7) * TAU
	for i in range(_CELL_SEGMENTS):
		var u := TAU * float(i) / float(_CELL_SEGMENTS)
		# Cells are irregular and slowly reshape; a clean ellipse reads as a
		# printed dot rather than as boiling plasma.
		var warp := 1.0 + 0.22 * sin(u * 3.0 + phase + _t * 0.6) \
			+ 0.12 * sin(u * 5.0 - phase * 1.3 - _t * 0.4)
		var r := size * warp
		pts[i] = pos + radial * (cos(u) * r * squash) + tangent * (sin(u) * r)
	draw_polygon(pts, PackedColorArray([col]))

func _draw_granulation(centre: Vector2) -> void:
	if granule_count <= 0:
		return
	var lane := Color(color.r * 0.35, color.g * 0.30, color.b * 0.25, granule_dark)
	for i in range(granule_count):
		var p := _sphere_point(i, granule_count)
		# Each cell overturns on its own clock, so the face keeps changing
		# without anything sliding across it.
		var pulse := 0.5 + 0.5 * sin(_t * granule_flicker * (0.7 + _rand(i, 1.1) * 0.8) \
			+ _rand(i, 2.3) * TAU)
		var glow := granule_bright * (0.35 + 0.65 * pulse)
		var fill := Color(
			color.r * 0.8 + glow,
			color.g * 0.8 + glow * 0.92,
			color.b * 0.8 + glow * 0.70,
			0.42)
		var size := granule_size * (0.65 + 0.70 * _rand(i, 4.9))
		_draw_cell(centre, p, size, i, lane, fill)

func _draw_spots(centre: Vector2) -> void:
	if spot_count <= 0:
		return
	# Cool regions: darker *and* redder than the photosphere, which is what a
	# lower temperature actually looks like. A grey patch reads as a hole.
	var core := Color(color.r * 0.30, color.g * 0.16, color.b * 0.10, spot_darkness)
	var penumbra := Color(color.r * 0.55, color.g * 0.35, color.b * 0.20, spot_darkness * 0.55)
	for i in range(spot_count):
		# Offset off the granulation's own distribution so spots do not sit
		# concentrically inside cells.
		var p := _sphere_point(i * 5 + 2, maxi(spot_count * 5 + 4, 8))
		var size := spot_size * (0.7 + 0.6 * _rand(i, 7.3))
		_draw_cell(centre, p, size, i + 500, penumbra, core)

## Arcs of plasma lifting off the limb and settling back, each on its own
## rise/fall cycle so the edge is never symmetric.
func _draw_prominences(centre: Vector2) -> void:
	if prominence_count <= 0:
		return
	for i in range(prominence_count):
		# Offset per loop so they do not all breathe together.
		var phase := _t / prominence_cycle + _rand(i, 9.4)
		var strength := sin(PI * (phase - floor(phase)))
		if strength <= 0.02:
			continue
		# Drifts with the rotation, so a loop tracks with the surface it is
		# rooted in instead of hanging in place while the star turns under it.
		var a := TAU * float(i) / float(prominence_count) \
			+ _rand(i, 2.7) * 0.4 + _t * rotation_speed * 0.5
		var span := 0.07 + 0.07 * _rand(i, 4.1)
		var height := prominence_height * (0.55 + 0.75 * _rand(i, 6.8)) * strength
		var width := prominence_width * radius * (0.6 + 0.6 * _rand(i, 8.9))
		var col := Color(color.r * 0.95 + 0.18, color.g * 0.85 + 0.12,
			color.b * 0.8 + 0.06, 0.34 * strength)
		_draw_loop(centre, a, span, height, width, col)

func _draw_loop(centre: Vector2, a: float, span: float, height: float,
		width: float, col: Color) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in range(_LOOP_STEPS + 1):
		var s := float(i) / float(_LOOP_STEPS)
		var ang := a + (s - 0.5) * 2.0 * span
		var dir := Vector2(cos(ang), sin(ang))
		# Rooted below the surface at both feet, arching to `height` above it.
		# pow < 1 lifts the arch away from its feet quickly, which is what makes
		# a loop rather than a low mound.
		var rise := pow(sin(PI * s), 0.7)
		var r := radius * (0.96 + height * rise)
		# Tapered to nothing at the feet so each end melts into the limb.
		var t := width * (0.25 + 0.75 * rise)
		var p := centre + dir * r
		outer.append(p + dir * t * 0.5)
		inner.append(p - dir * t * 0.5)
	inner.reverse()
	outer.append_array(inner)
	draw_polygon(outer, PackedColorArray([col]))
