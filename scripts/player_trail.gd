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
	for i in range(max_fragments):
		var age := _age[i]
		if age >= lifetime:
			continue
		var t := age / lifetime
		var fade := (1.0 - t) * (1.0 - t)
		var r := start_radius * _size[i] * (1.0 - t * 0.65)
		if r <= 0.2:
			continue
		var halo := color * 0.9
		halo.a = fade * 0.30
		draw_circle(_pos[i], r * 1.7, halo)
		var body := color
		body.a = fade * 0.85
		draw_circle(_pos[i], r, body)
