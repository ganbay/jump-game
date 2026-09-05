extends Area2D
class_name Platform

enum Type { STILL, MOVING, BOOST, ONE_TIME }

@export var type: Type = Type.STILL
@export var move_speed: float = 110.0
@export var move_range: float = 130.0
@export var boost_multiplier: float = 1.5

const HALF_WIDTH := 45.0

var _dir: int = 1
var _min_x: float
var _max_x: float

const COLORS := {
	Type.STILL: Color(0.3, 1.0, 2.2),
	Type.MOVING: Color(2.2, 2.0, 0.3),
	Type.BOOST: Color(0.3, 2.4, 1.0),
	Type.ONE_TIME: Color(2.4, 0.4, 0.5),
}

@onready var visual: RoundedRect = $Visual

func _ready() -> void:
	add_to_group("platforms")
	visual.color = COLORS[type]
	var vw := get_viewport_rect().size.x
	_min_x = clampf(position.x - move_range, HALF_WIDTH, vw - HALF_WIDTH)
	_max_x = clampf(position.x + move_range, HALF_WIDTH, vw - HALF_WIDTH)
	if _min_x > _max_x:
		var mid := (_min_x + _max_x) * 0.5
		_min_x = mid
		_max_x = mid

func _physics_process(delta: float) -> void:
	if type != Type.MOVING:
		return
	position.x += _dir * move_speed * delta
	if position.x > _max_x:
		position.x = _max_x
		_dir = -1
	elif position.x < _min_x:
		position.x = _min_x
		_dir = 1

func on_landed(player: Node, _boosted: bool) -> void:
	if type == Type.BOOST:
		player.velocity.y *= boost_multiplier
	elif type == Type.ONE_TIME:
		_crumble()

func _crumble() -> void:
	remove_from_group("platforms")
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	var tw := create_tween()
	tw.tween_property(visual, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)
