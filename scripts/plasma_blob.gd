extends Node2D
class_name PlasmaBlob

## A torn-off piece of a star: a wobbling plasma cell drawn as three stacked
## polygons (soft corona, saturated body, blown-out core). The perimeter is
## radius modulated by a few summed sines, so it churns continuously instead of
## sitting still like the solid blob skin does.
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
		pts[i] = centre + Vector2(cos(a), sin(a)) * (radius * scale_mul * breath * (1.0 + wob))
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
