extends Area2D
class_name Platform

enum Type { STILL, MOVING, BOOST, ONE_TIME }

@export var type: Type = Type.STILL
@export var move_speed: float = 110.0
@export var boost_multiplier: float = 1.5
@export var width: float = 90.0

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
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	_apply_visual_settings()
	_apply_width()
	var vw := get_viewport_rect().size.x
	_min_x = width / 2.0
	_max_x = vw - width / 2.0

func _apply_visual_settings() -> void:
	if is_instance_valid(visual):
		visual.color = Settings.get_platform_color(type)

func _apply_width() -> void:
	visual.rect_size.x = width
	var collision: CollisionShape2D = $CollisionShape2D
	var shape: RectangleShape2D = collision.shape.duplicate()
	shape.size.x = width
	collision.shape = shape

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

func should_land(is_timed: bool) -> bool:
	if type == Type.BOOST and not is_timed:
		_crumble()
		return false
	return true

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
