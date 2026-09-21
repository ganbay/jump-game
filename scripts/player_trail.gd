extends Node2D
class_name PlayerTrail

## Sheds fragments of the character behind it, as if bits of its body keep
## tearing off and cooling. Fragments are world-space and independent of the
## player once emitted, so screen-wrapping just drops the trail on both edges
## instead of smearing a streak across the screen.
##
## The node is top_level, so its local space is world space and `_draw` can use
## the emitted global positions directly. State lives in a fixed-size ring of
## packed arrays: no per-fragment nodes, no allocation while running.

@export var emit_interval: float = 0.03
@export var lifetime: float = 0.5
@export var start_radius: float = 10.0
## Fragments are born scattered within the body rather than all at its centre.
@export var spread: float = 9.0
@export var inherit_velocity: float = 0.15
@export var scatter: float = 30.0
## How quickly a fragment sheds its inherited velocity and hangs in place.
@export var damping: float = 3.0
@export var max_fragments: int = 40
## Below this speed nothing is shed, so the trail does not clump at jump apex.
@export var min_emit_speed: float = 40.0

var color: Color = Color.WHITE
## Fragments are drawn as this silhouette (see PlasmaBlob.Shape) instead of a
## plain circle, so a shape skin sheds little copies of its own body. CIRCLE
## draws exactly as before -- the round PLASMA skin is unaffected.
var shape: PlasmaBlob.Shape = PlasmaBlob.Shape.CIRCLE:
	set(value):
		shape = value
		_rebuild_shape_profile()

## Vertices per fragment silhouette, per shape. Sampling is aligned to the
## shape's own rotation (see _rebuild_shape_profile), so these counts are
## chosen to put a sample exactly on every feature: a regular polygon needs
## only its corners, a star needs its tips and its notches. A 5-point star at
## 10 vertices is therefore *exact*, while the same star at an unaligned 16
## lands on none of its tips and shears all five of them off at random
## heights. Shapes built from curves rather than straight runs (heart, flame,
## dome) just need enough samples to stay smooth.
const _SHAPE_SEGMENTS := {
	PlasmaBlob.Shape.TRIANGLE: 12,
	PlasmaBlob.Shape.SQUARE: 8,
	PlasmaBlob.Shape.DIAMOND: 8,
	PlasmaBlob.Shape.PRISM: 12,
	PlasmaBlob.Shape.STAR: 10,
	PlasmaBlob.Shape.SPARKLE: 8,
	PlasmaBlob.Shape.HEART: 24,
	PlasmaBlob.Shape.FLAME: 20,
}
const _DEFAULT_SEGMENTS := 16
## Vertices in the current shape's outline -- _SHAPE_SEGMENTS for `shape`.
var _segments: int = _DEFAULT_SEGMENTS
## Unit outline of `shape`, rebuilt only when the skin changes -- each fragment
## just scales and offsets it instead of re-running PlasmaBlob.shape_radius.
var _shape_profile: PackedVector2Array = PackedVector2Array()

## Every fragment used to cost two polygon commands (halo + body), and on the
## mobile renderer a polygon command does not batch with its neighbours -- a
## full trail was up to 80 separate draw calls a frame. All of them are now
## written into one indexed triangle array and submitted as a single command.
##
## The buffers are allocated once and always submitted whole: the index pattern
## depends only on fragment and segment counts, never on which slots are alive,
## so a dead fragment collapses to a zero-area fan (discarded by the rasteriser
## at no fill cost) instead of forcing the indices to be rebuilt.
const FANS_PER_FRAGMENT := 2
var _tri_indices: PackedInt32Array = PackedInt32Array()
var _tri_points: PackedVector2Array = PackedVector2Array()
var _tri_colors: PackedColorArray = PackedColorArray()

var _pos: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _size: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0
var _accum: float = 0.0
var _player: Node2D
var _enabled: bool = true
var _was_empty: bool = true

func _ready() -> void:
	_player = get_parent() as Node2D
	_pos.resize(max_fragments)
	_vel.resize(max_fragments)
	_age.resize(max_fragments)
	_size.resize(max_fragments)
	_clear()
	_rebuild_shape_profile()

func _rebuild_shape_profile() -> void:
	_segments = _SHAPE_SEGMENTS.get(shape, _DEFAULT_SEGMENTS)
	# Swept from the shape's own zero rather than from absolute zero: every
	# silhouette places its corners and spikes at whole fractions of a turn
	# measured from there, so this is what makes the sample angles land on
	# them. shape_radius re-applies the same rotation internally, so the
	# outline itself comes out in exactly the orientation it always had.
	var rot := PlasmaBlob.shape_rotation(shape)
	_shape_profile.resize(_segments)
	for i in range(_segments):
		var a := TAU * float(i) / float(_segments) - rot
		_shape_profile[i] = Vector2(cos(a), sin(a)) * PlasmaBlob.shape_radius(a, shape)
	_rebuild_triangle_buffers()

## Sizes the shared buffers for the current shape and lays out its index
## pattern. The outline is triangulated once, here, and the result reused by
## every fragment: scaling and translating a polygon cannot invalidate its
## triangulation, so the indices only ever change when the skin does.
func _rebuild_triangle_buffers() -> void:
	var fans := max_fragments * FANS_PER_FRAGMENT
	_tri_points.resize(fans * _segments)
	_tri_colors.resize(fans * _segments)
	# A fan from vertex 0 is only valid for a convex outline -- it webs across
	# the notches of STAR and SPARKLE and the cleft of HEART, which is what
	# draw_polygon's own triangulation was quietly handling before.
	var tri := Geometry2D.triangulate_polygon(_shape_profile)
	if tri.is_empty():
		tri = _fan_indices()
	_tri_indices.resize(fans * tri.size())
	var w := 0
	for f in range(fans):
		var base := f * _segments
		for k in range(tri.size()):
			_tri_indices[w] = base + tri[k]
			w += 1

## Convex fallback, for the case where triangulation fails outright. Every
## silhouette here is a radial function of angle and so cannot self-intersect,
## which means this should be unreachable -- but a shape that failed to
## triangulate would otherwise draw nothing at all.
func _fan_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize((_segments - 2) * 3)
	var w := 0
	for t in range(_segments - 2):
		out[w] = 0
		out[w + 1] = t + 1
		out[w + 2] = t + 2
		w += 3
	return out

func _clear() -> void:
	for i in range(max_fragments):
		_age[i] = lifetime  # anything at or past lifetime counts as a free slot

func set_enabled(value: bool) -> void:
	if value == _enabled:
		return
	_enabled = value
	set_process(value)
	if not value:
		_clear()
		queue_redraw()

func _process(delta: float) -> void:
	var alive := 0
	for i in range(max_fragments):
		if _age[i] >= lifetime:
			continue
		_age[i] += delta
		_pos[i] += _vel[i] * delta
		_vel[i] = _vel[i].lerp(Vector2.ZERO, clampf(damping * delta, 0.0, 1.0))
		alive += 1
	_accum += delta
	if _accum >= emit_interval:
		_accum = 0.0
		if _should_emit():
			_emit()
			alive += 1
	# One last redraw is needed to clear the final fragment, but after that an
	# idle trail should not keep queueing empty draws.
	if alive > 0 or not _was_empty:
		queue_redraw()
	_was_empty = alive == 0

func _should_emit() -> bool:
	return _player != null and _player_velocity().length() >= min_emit_speed

func _player_velocity() -> Vector2:
	return _player.velocity if _player is CharacterBody2D else Vector2.ZERO

func _emit() -> void:
	var i := _next
	_next = (_next + 1) % max_fragments
	_pos[i] = _player.global_position + Vector2(
		randf_range(-spread, spread), randf_range(-spread, spread))
	_vel[i] = _player_velocity() * inherit_velocity + Vector2(
		randf_range(-scatter, scatter), randf_range(-scatter, scatter))
	_age[i] = 0.0
	_size[i] = randf_range(0.55, 1.0)

func _draw() -> void:
	var fan := 0
	for i in range(max_fragments):
		var age := _age[i]
		var t := age / lifetime if age < lifetime else 1.0
		var r := start_radius * _size[i] * (1.0 - t * 0.65)
		if age >= lifetime or r <= 0.2:
			_collapse_fan(fan)
			_collapse_fan(fan + 1)
			fan += FANS_PER_FRAGMENT
			continue
		var fade := (1.0 - t) * (1.0 - t)
		var halo := color * 0.9
		halo.a = fade * 0.30
		var body := color
		body.a = fade * 0.85
		# Halo first, so the body still lands on top of it exactly as it did
		# when these were two separate draw calls.
		_write_fan(fan, _pos[i], r * 1.7, halo)
		_write_fan(fan + 1, _pos[i], r, body)
		fan += FANS_PER_FRAGMENT
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _tri_indices, _tri_points, _tri_colors)

## Lays one fragment's silhouette into its slice of the shared vertex buffer.
## Same math `_draw_shape` used per fragment, minus the per-fragment command.
func _write_fan(fan: int, centre: Vector2, r: float, fragment_color: Color) -> void:
	var base := fan * _segments
	for i in range(_segments):
		_tri_points[base + i] = centre + _shape_profile[i] * r
		_tri_colors[base + i] = fragment_color

func _collapse_fan(fan: int) -> void:
	var base := fan * _segments
	for i in range(_segments):
		_tri_points[base + i] = Vector2.ZERO
		_tri_colors[base + i] = Color.TRANSPARENT
