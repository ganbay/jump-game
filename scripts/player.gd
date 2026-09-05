extends CharacterBody2D
class_name Player

signal landed(platform, boosted, streak)

@export var move_speed: float = 900.0
@export var gravity: float = 1600.0
@export var fast_fall_gravity: float = 3600.0
@export var jump_velocity: float = -900.0
@export var boost_jump_velocity: float = -1300.0
@export var boost_move_multiplier: float = 1.4
@export var landing_window_ms: int = 140
@export var drag_sensitivity: float = 1.3

var is_holding: bool = false
var is_fast_falling: bool = false
var streak: int = 0
var last_press_ms: int = -999999
var _last_pointer_x: float = 0.0
var _last_platform: Node = null
var _attempted_since_last_landing: bool = false

const FEET_HALF_WIDTH := 20.0
const FEET_HALF_HEIGHT := 5.0
const PLATFORM_HALF_WIDTH := 45.0
const PLATFORM_HALF_HEIGHT := 6.0

@onready var feet: Area2D = $Feet
@onready var visual: Node2D = $Visual

func _ready() -> void:
	add_to_group("player")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_set_hold(event.pressed, event.position.x)
	elif event is InputEventScreenTouch:
		_set_hold(event.pressed, event.position.x)

func _set_hold(pressed: bool, pointer_x: float) -> void:
	is_holding = pressed
	if pressed:
		last_press_ms = Time.get_ticks_msec()
		_last_pointer_x = pointer_x
		_attempted_since_last_landing = true
	elif velocity.y >= 0.0:
		is_fast_falling = true

func _physics_process(delta: float) -> void:
	var g: float = fast_fall_gravity if is_fast_falling else gravity
	velocity.y += g * delta

	if is_holding:
		var pointer_x := get_viewport().get_mouse_position().x
		var drag_delta := pointer_x - _last_pointer_x
		_last_pointer_x = pointer_x
		var speed := move_speed * (boost_move_multiplier if is_fast_falling else 1.0)
		velocity.x = clampf((drag_delta * drag_sensitivity) / delta, -speed, speed)
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)

	var prev_feet_y := feet.global_position.y
	move_and_slide()
	_wrap_screen()

	if velocity.y > 0.0:
		_check_landing(prev_feet_y, feet.global_position.y)

func _wrap_screen() -> void:
	var vw := get_viewport_rect().size.x
	if global_position.x < 0.0:
		global_position.x = vw
	elif global_position.x > vw:
		global_position.x = 0.0

func _check_landing(prev_y: float, new_y: float) -> void:
	var band := FEET_HALF_HEIGHT + PLATFORM_HALF_HEIGHT
	var best_area: Node = null
	var best_y := INF
	for area in get_tree().get_nodes_in_group("platforms"):
		if not is_instance_valid(area):
			continue
		var py: float = area.global_position.y
		if py < prev_y - band or py > new_y + band:
			continue
		if absf(feet.global_position.x - area.global_position.x) > PLATFORM_HALF_WIDTH + FEET_HALF_WIDTH:
			continue
		if py < best_y:
			best_y = py
			best_area = area
	if best_area != null:
		_land_on(best_area)

func _land_on(area: Node) -> void:
	var is_timed := Time.get_ticks_msec() - last_press_ms <= landing_window_ms
	var counts := is_timed and area != _last_platform
	is_fast_falling = false
	if is_timed:
		if counts:
			streak += 1
	elif _attempted_since_last_landing:
		streak = 0
	_attempted_since_last_landing = false
	velocity.y = boost_jump_velocity if is_timed else jump_velocity
	_last_platform = area
	_play_squash(is_timed)
	if area.has_method("on_landed"):
		area.on_landed(self, is_timed)
	landed.emit(area, counts, streak)

func _play_squash(boosted: bool) -> void:
	var squash := Vector2(1.6, 0.42) if boosted else Vector2(1.45, 0.5)
	var stretch := Vector2(0.55, 1.65) if boosted else Vector2(0.62, 1.5)
	visual.scale = squash
	var tw := create_tween()
	tw.tween_property(visual, "scale", stretch, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
