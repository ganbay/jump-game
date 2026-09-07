extends Node2D

@export var color: Color = Color(1.15, 1.15, 1.2)
@export var particle_count: int = 8
@export var spawn_half_width: float = 40.0
@export var gravity: float = 900.0
@export var lifetime: float = 0.5

var _offsets: Array[Vector2] = []
var _velocities: Array[Vector2] = []
var _t: float = 0.0

func _ready() -> void:
	for i in range(particle_count):
		_offsets.append(Vector2(randf_range(-spawn_half_width, spawn_half_width), 0.0))
		var vx := randf_range(-25.0, 25.0)
		var vy := randf_range(10.0, 50.0)
		_velocities.append(Vector2(vx, vy))
	var tw := create_tween()
	tw.tween_method(_set_progress, 0.0, lifetime, lifetime)
	tw.tween_callback(queue_free)

func _set_progress(t: float) -> void:
	_t = t
	queue_redraw()

func _draw() -> void:
	var fade := 1.0 - (_t / lifetime)
	fade = fade * fade
	var col := color
	col.a = clampf(fade, 0.0, 1.0)
	var radius := 2.5 * fade
	for i in range(_velocities.size()):
		var pos := _offsets[i] + _velocities[i] * _t + Vector2(0.0, 0.5 * gravity * _t * _t)
		draw_circle(pos, radius, col)
