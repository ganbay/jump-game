extends Node2D

@export var color: Color = Color(1.15, 1.15, 1.2)
@export var particle_count: int = 10
@export var gravity: float = 900.0
@export var lifetime: float = 0.6

var _velocities: Array[Vector2] = []
var _t: float = 0.0

func _ready() -> void:
	for i in range(particle_count):
		var angle := TAU * i / float(particle_count) + randf_range(-0.25, 0.25)
		var dir := Vector2.RIGHT.rotated(angle)
		dir.y -= 0.6
		var speed := randf_range(80.0, 160.0)
		_velocities.append(dir.normalized() * speed)
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
	var radius := 3.5 * fade
	for v in _velocities:
		var pos := v * _t + Vector2(0.0, 0.5 * gravity * _t * _t)
		draw_circle(pos, radius, col)
