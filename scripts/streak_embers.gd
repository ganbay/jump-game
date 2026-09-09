extends Node2D
class_name StreakEmbers

## Embers shedding from under the streak counter, in the same language as the
## character's own trail: fragments that fall away, shrink and cool. Rate and
## size climb with the streak, so a long run visibly drips harder.
##
## Lives in the UI CanvasLayer, so this is screen space -- it does not move with
## the camera. Fixed-size ring of packed arrays: no per-ember nodes, no
## allocation while running.

@export var width: float = 190.0
@export var lifetime: float = 0.95
@export var start_radius: float = 5.0
## Downward pull, so embers accelerate away rather than drifting evenly.
@export var gravity: float = 240.0
@export var sideways: float = 34.0
@export var max_embers: int = 56
## Embers per second at streak 1, and how much each further streak adds.
@export var base_rate: float = 7.0
@export var rate_per_streak: float = 4.5
@export var rate_cap: float = 46.0

var color: Color = Color.WHITE

var _pos: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _size: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0
var _accum: float = 0.0
var _rate: float = 0.0
var _streak: int = 0
var _was_empty: bool = true

func _ready() -> void:
	_pos.resize(max_embers)
	_vel.resize(max_embers)
	_age.resize(max_embers)
	_size.resize(max_embers)
	for i in range(max_embers):
		_age[i] = lifetime  # at or past lifetime means a free slot

## Streak of 0 or 1 shuts the emitter off, matching when the label itself is blank.
func set_streak(streak: int) -> void:
	_streak = streak
	if streak > 1:
		_rate = minf(base_rate + rate_per_streak * float(streak - 1), rate_cap)
	else:
		_rate = 0.0

## A handful thrown at once when the streak ticks up, so the counter punches
## rather than just raising its background rate.
func burst(count: int) -> void:
	for i in range(count):
		_emit()

func _process(delta: float) -> void:
	var alive := 0
	for i in range(max_embers):
		if _age[i] >= lifetime:
			continue
		_age[i] += delta
		_vel[i].y += gravity * delta
		_pos[i] += _vel[i] * delta
		alive += 1
	if _rate > 0.0:
		_accum += delta * _rate
		while _accum >= 1.0:
			_accum -= 1.0
			_emit()
			alive += 1
	else:
		_accum = 0.0
	if alive > 0 or not _was_empty:
		queue_redraw()
	_was_empty = alive == 0

func _emit() -> void:
	var i := _next
	_next = (_next + 1) % max_embers
	_pos[i] = Vector2(randf_range(0.0, width), randf_range(-4.0, 4.0))
	_vel[i] = Vector2(randf_range(-sideways, sideways), randf_range(10.0, 60.0))
	_age[i] = 0.0
	_size[i] = randf_range(0.5, 1.0)

func _draw() -> void:
	for i in range(max_embers):
		var age := _age[i]
		if age >= lifetime:
			continue
		var t := age / lifetime
		var fade := (1.0 - t) * (1.0 - t)
		var r := start_radius * _size[i] * (1.0 - t * 0.6)
		if r <= 0.2:
			continue
		var halo := color * 0.9
		halo.a = fade * 0.28
		draw_circle(_pos[i], r * 1.8, halo)
		var body := color
		body.a = fade * 0.85
		draw_circle(_pos[i], r, body)
