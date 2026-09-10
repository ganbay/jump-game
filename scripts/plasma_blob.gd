extends Node2D
class_name PlasmaBlob

## A torn-off piece of a star: a wobbling plasma cell drawn as three stacked
## polygons (soft corona, saturated body, blown-out core). The perimeter is
## radius modulated by a few summed sines, so it churns continuously instead of
## sitting still.
##
## Drawn bottom-anchored: the shape's centre sits one radius above the node's
## origin, so the node can be placed at the character's feet and a squash tween
## on `scale` deforms it down onto the platform rather than about its middle.

@export var radius: float = 18.0:
	set(value):
		radius = value
		queue_redraw()

@export var color: Color = Color(2.6, 1.0, 0.15, 1.0):
	set(value):
		color = value
		queue_redraw()

## Perimeter points. The outer silhouette is nearly circular now, so faceting
## would show at a low count where the old churn used to hide it.
@export var segments: int = 32

## How far the perimeter deforms, as a fraction of radius. Kept small so the
## cell reads as a round body; the motion lives in the core instead.
@export var wobble: float = 0.05

## Higher-frequency component. A trace of it keeps the edge from looking
## mechanically perfect without breaking the round read.
@export var flare: float = 0.02

## Uniform radius pulse. Scales every point equally, so it keeps the shape
## alive without ever making it non-circular.
@export var breathe: float = 0.03

## High-frequency surface detail, on top of `wobble` / `flare`. Reads as
## granulation boiling on a star's photosphere. Needs enough `segments` to
## resolve 17 lobes; left at 0 for the character, whose 32 would alias.
@export var turbulence: float = 0.0

## Global multipliers over every band's churn / drift. Drop these to calm the
## whole shape at once without editing the band table.
@export var churn_scale: float = 1.0
@export var drift_scale: float = 1.0

## Churn rate. Higher reads as hotter / more agitated.
@export var speed: float = 3.0

## The cell's base silhouette before churn deforms it. CIRCLE is the original
## look; the rest are the same wobbling/glowing bands stretched over a polygon,
## star or dome outline instead, so they read as the same plasma "family."
enum Shape { CIRCLE, TRIANGLE, SQUARE, PRISM, STAR, DOME, HEART, FLAME, SPARKLE }

@export var shape: Shape = Shape.CIRCLE:
	set(value):
		shape = value
		queue_redraw()

## Rotation (radians) applied before the shape profile, so each one lands in
## its most recognizable orientation -- triangle/star pointing up, square/
## prism flat-topped -- rather than however _ngon_radius's own a=0-is-a-vertex
## convention happens to land it.
const _SHAPE_ROTATION := {
	Shape.TRIANGLE: PI / 2.0,
	Shape.SQUARE: PI / 4.0,
	Shape.PRISM: 0.0,
	Shape.STAR: PI / 2.0 + PI / 5.0,
	# _star_radius puts a spike at the middle of each segment, so a quarter
	# turn plus half a segment lands one straight up.
	Shape.SPARKLE: 3.0 * PI / 4.0,
	# DOME, HEART and FLAME are absent on purpose: each is written against
	# absolute up/down, so rotating it would tip it over.
}

## How wide the dome's base is relative to its height. Slightly over 1 so it
## reads as a dome rather than a bullet.
const _DOME_HALF_WIDTH := 1.15

## Heart profile, built as a circle with a wedge notched out of the top, a bump
## raising each lobe and a point pulled out of the bottom. `_HEART_NORM` divides
## out the *tip's* reach specifically, which lands the point exactly on the
## platform: normalising on the profile's peak instead would put the raised
## lobes there and shrink the whole heart to fit. The lobes are then free to
## overshoot a circle's bounds, upward, where nothing has to touch down.
const _HEART_NOTCH := 0.5
const _HEART_NOTCH_SPREAD := 0.85
const _HEART_LOBE := 0.45
const _HEART_LOBE_ANGLE := 0.8
const _HEART_LOBE_SPREAD := 0.55
const _HEART_TIP := 0.25
const _HEART_TIP_SPREAD := 1.15
const _HEART_NORM := 1.0 + _HEART_TIP

## Flame profile. A tip alone was not enough: it left five sixths of the
## outline identical to the plain circle, so the body is tapered towards the
## top as well and only the round bottom is shared. Left unnormalised, so that
## bottom still rests on the platform while the point stands taller than the
## other shapes -- which is what a flame wants.
const _FLAME_TIP := 0.9
const _FLAME_SPREAD := 1.1
## How much the body narrows towards the top, and how abruptly. The exponent
## keeps the taper off the widest point so the silhouette stays smooth there.
const _FLAME_TAPER := 0.45
const _FLAME_TAPER_POWER := 1.5

## Silhouette radius multiplier at angle `a` for the given `shape` (1.0 ==
## circle). Static and shared with PlayerTrail, so trail fragments can be
## drawn as the same silhouette as the body that's shedding them.
static func shape_radius(a: float, shape_type: Shape) -> float:
	var rotated: float = a + _SHAPE_ROTATION.get(shape_type, 0.0)
	match shape_type:
		Shape.TRIANGLE:
			return _ngon_radius(rotated, 3)
		Shape.SQUARE:
			return _ngon_radius(rotated, 4)
		Shape.PRISM:
			return _ngon_radius(rotated, 6)
		Shape.STAR:
			return _star_radius(rotated, 5, 0.5)
		Shape.DOME:
			return _dome_radius(rotated)
		Shape.HEART:
			return _heart_radius(rotated)
		Shape.FLAME:
			return _flame_radius(rotated)
		Shape.SPARKLE:
			return _star_radius(rotated, 4, 0.28)
		_:
			return 1.0

## Regular-polygon radius as a function of angle: 1.0 at each vertex (a=0,
## seg, 2*seg, ...), dipping to cos(seg/2) at each edge midpoint in between.
static func _ngon_radius(a: float, sides: int) -> float:
	var seg := TAU / float(sides)
	var theta := fmod(a, seg)
	if theta < 0.0:
		theta += seg
	theta -= seg / 2.0
	return cos(seg / 2.0) / cos(theta)

## Star radius as a function of angle: 1.0 at each spike tip, `inner_ratio` at
## each notch between spikes, straight-line taper in between.
static func _star_radius(a: float, points: int, inner_ratio: float) -> float:
	var seg := TAU / float(points)
	var theta := fmod(a, seg)
	if theta < 0.0:
		theta += seg
	var tri := 1.0 - absf(theta / seg - 0.5) * 2.0
	return lerpf(inner_ratio, 1.0, tri)

## Dome radius as a function of angle: a half-ellipse with its flat face down.
## The ellipse is centred on that face -- at relative y = +1, which is the
## node's own origin once the shape is bottom-anchored, so the flat side lands
## exactly on the platform -- with a vertical semi-axis of 2, which puts the
## crown at the same height every other shape reaches.
static func _dome_radius(a: float) -> float:
	var s := sin(a)
	var u := cos(a) / _DOME_HALF_WIDTH
	var v := s / 2.0
	var q := u * u + v * v
	# Positive root of the ray/ellipse intersection...
	var r := (v + sqrt(v * v + 3.0 * q)) / (2.0 * q)
	# ...cut off by the flat face for any ray heading downward.
	return minf(r, 1.0 / s) if s > 0.0001 else r

## Heart, on its point. Written against absolute up/down rather than a rotated
## angle, so the lobes stay up and the point stays down.
static func _heart_radius(a: float) -> float:
	var from_up := _angle_from(a, -PI / 2.0)
	var r := 1.0
	# The cleft is a crease and the bottom is a point, so both are spikes; the
	# lobes have to be humps or they come to a corner at their crown.
	r -= _HEART_NOTCH * _spike(from_up, _HEART_NOTCH_SPREAD)
	r += _HEART_LOBE * _hump(absf(from_up - _HEART_LOBE_ANGLE), _HEART_LOBE_SPREAD)
	r += _HEART_TIP * _spike(PI - from_up, _HEART_TIP_SPREAD)
	return r / _HEART_NORM

## Teardrop with the point up: the cell's own churn then reads as the flame
## guttering, which is what the character is meant to be a piece of.
static func _flame_radius(a: float) -> float:
	var from_up := _angle_from(a, -PI / 2.0)
	# cos(from_up) is +1 straight up and negative below the waist, where the
	# body is left alone -- the taper only ever narrows the top.
	var rise := maxf(cos(from_up), 0.0)
	var body := 1.0 - _FLAME_TAPER * pow(rise, _FLAME_TAPER_POWER)
	return body + _FLAME_TIP * _spike(from_up, _FLAME_SPREAD)

## Falls from 1.0 at `x` == 0 to 0.0 at `x` == `spread`, steeply at first and
## levelling off: a point at the centre, and a smooth landing at the outer edge
## so it blends into whatever it is added to instead of leaving a kink there.
static func _spike(x: float, spread: float) -> float:
	var w := maxf(0.0, 1.0 - x / spread)
	return w * w

## A rounded bump: 1.0 at `x` == 0 and 0.0 at `x` == `spread`, flat at both
## ends. This is what keeps a heart's lobes circular -- a linear falloff peaks
## in a corner, which reads as a spike rather than a lobe.
static func _hump(x: float, spread: float) -> float:
	return 0.5 + 0.5 * cos(PI * minf(x / spread, 1.0))

## Unsigned angular distance between `a` and `ref`, in [0, PI].
static func _angle_from(a: float, ref: float) -> float:
	var d := fmod(a - ref + PI, TAU)
	if d < 0.0:
		d += TAU
	return absf(d - PI)

## Concentric bands, outermost first, each drawn as a filled ring on top of the
## last. Fields: `r` radius as a fraction of `radius`; `phase` noise offset so
## bands move out of sync; `tint` multiplier on `color`; `white` added to rgb to
## push a band past white so HDR + glow blow it out; `a` alpha; `churn`
## deformation multiplier; `drift` off-centre wander as a fraction of radius.
const CHARACTER_BANDS := [
	{"r": 1.45, "phase": 0.9, "tint": 0.7, "white": Color(0, 0, 0), "a": 0.22, "churn": 1.0, "drift": 0.0},
	{"r": 1.00, "phase": 0.0, "tint": 1.0, "white": Color(0, 0, 0), "a": 1.00, "churn": 1.0, "drift": 0.0},
	{"r": 0.50, "phase": 2.1, "tint": 1.0, "white": Color(1.3, 1.3, 1.0), "a": 0.95, "churn": 2.6, "drift": 0.12},
]

## Swappable so the same shape can be a 3-layer character cell or a many-banded
## star. Assign before first draw; not mutated in place.
var bands: Array = CHARACTER_BANDS

var _t: float = 0.0

func _process(delta: float) -> void:
	_t += delta * speed
	queue_redraw()

## Builds one ring. `phase` offsets the noise so the layers move out of sync
## with each other; `deform_mul` scales how much this particular ring is
## allowed to distort, which is how the core stays lively inside a calm body.
func _ring(scale_mul: float, phase: float, deform_mul: float, centre: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(segments)
	var breath := 1.0 + sin(_t * 1.3 + phase) * breathe
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		var wob := (
			sin(a * 3.0 + _t * 1.7 + phase) * wobble
			+ sin(a * 5.0 - _t * 2.3 + phase) * wobble * 0.55
			+ sin(a * 7.0 + _t * 1.1 + phase) * flare
			+ sin(a * 11.0 - _t * 3.1 + phase * 1.7) * turbulence
			+ sin(a * 17.0 + _t * 4.3 + phase * 2.3) * turbulence * 0.6
		) * deform_mul
		var shape_mul := shape_radius(a, shape)
		pts[i] = centre + Vector2(cos(a), sin(a)) * (radius * scale_mul * shape_mul * breath * (1.0 + wob))
	return pts

func _draw() -> void:
	var centre := Vector2(0.0, -radius)
	# Outermost first: each band paints over the one beneath it, so the visible
	# thickness of a band is the gap between its radius and the next one in.
	for band in bands:
		var tint: float = band["tint"]
		var white: Color = band["white"]
		var col := Color(
			color.r * tint + white.r,
			color.g * tint + white.g,
			color.b * tint + white.b,
			band["a"])
		var wander: float = band["drift"] * drift_scale
		var c := centre
		if wander != 0.0:
			c += Vector2(sin(_t * 0.9), cos(_t * 0.7)) * radius * wander
		draw_polygon(
			_ring(band["r"], band["phase"], band["churn"] * churn_scale, c),
			PackedColorArray([col]))
