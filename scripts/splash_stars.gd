extends Node2D

## The splash's night sky.
##
## Deliberately static. The game's own BackgroundParticles drift, wobble and
## twinkle; none of that belongs on a two-second card that wants to read as a
## printed logo rather than as a scene already in motion. So there is no
## _process here at all -- the field is scattered once in _ready() and drawn
## once, and the only thing that ever changes about it is the modulate the
## splash fades out as the sky goes black.

@export var star_count: int = 90
@export var min_radius: float = 0.5
@export var max_radius: float = 1.7

## Fixed rather than left to the global RNG: this is a brand card, and a sky
## that reshuffled itself every launch would be the one thing on it that is not
## the same twice.
const STAR_SEED := 20250915

## Faint blue-white, and capped well under the wordmark's brightness -- the sky
## is depth behind the logo, not detail competing with it. Both stay at or below
## 1.0 so the scene's glow leaves them alone.
const DIM_COLOR := Color(0.62, 0.70, 0.95)
const BRIGHT_COLOR := Color(0.95, 0.97, 1.0)
const MIN_ALPHA := 0.18
const MAX_ALPHA := 0.75

var _pos: PackedVector2Array = PackedVector2Array()
var _radius: PackedFloat32Array = PackedFloat32Array()
var _color: PackedColorArray = PackedColorArray()

func _ready() -> void:
	_scatter(get_viewport_rect().size)

## Jittered grid rather than plain random placement, the same way
## BackgroundParticles spreads its field: uniform randomness clumps, and on a
## sky this sparse a clump reads as a mistake rather than as a constellation.
func _scatter(size: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	_pos.resize(star_count)
	_radius.resize(star_count)
	_color.resize(star_count)
	var cols := int(maxf(ceil(sqrt(float(star_count) * size.x / size.y)), 1.0))
	var cell := Vector2(size.x / cols, size.y / ceil(float(star_count) / cols))
	for i in range(star_count):
		_pos[i] = Vector2(
			(i % cols) * cell.x + rng.randf() * cell.x,
			(i / cols) * cell.y + rng.randf() * cell.y)
		# One roll drives size, tint and alpha together, so a larger star is
		# also a brighter and whiter one. That covariance is what reads as
		# distance; rolling them independently just looks like noise.
		var depth := rng.randf()
		# Squared, so most of the field lands near min_radius and only a few
		# stars carry any size at all.
		_radius[i] = lerpf(min_radius, max_radius, depth * depth)
		var col := DIM_COLOR.lerp(BRIGHT_COLOR, depth)
		col.a = lerpf(MIN_ALPHA, MAX_ALPHA, depth)
		_color[i] = col

func _draw() -> void:
	for i in range(_pos.size()):
		# Antialiased because these are sub-pixel to a couple of pixels across,
		# where an aliased circle reads as a square speck.
		draw_circle(_pos[i], _radius[i], _color[i], true, -1.0, true)
