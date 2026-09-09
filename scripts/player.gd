extends CharacterBody2D
class_name Player

signal landed(platform, boosted, streak)

@export var move_speed: float = 900.0
@export var gravity: float = 1600.0
@export var fast_fall_gravity: float = 3600.0
@export var jump_velocity: float = -900.0
@export var boost_jump_velocity: float = -1300.0
@export var boost_move_multiplier: float = 1.4
@export var streak_jump_step: float = 0.1
@export var streak_jump_cap: int = 10
@export var landing_window_ms: int = 140
@export var drag_sensitivity: float = 1.3
@export var tilt_sensitivity: float = 220.0
@export var tilt_deadzone: float = 0.6
@export var invert_tilt: bool = false

var is_holding: bool = false
var is_fast_falling: bool = false
var streak: int = 0
var last_press_ms: int = -999999
var _last_pointer_x: float = 0.0
var _last_platform: Node = null
var _attempted_since_last_landing: bool = false
var _viewport_width: float = 720.0

const FEET_HALF_WIDTH := 20.0
const FEET_HALF_HEIGHT := 5.0
const PLATFORM_HALF_WIDTH := 45.0
const PLATFORM_HALF_HEIGHT := 6.0

const COLOR := Color(0.66295815, 2.299754, 0.0, 1.0)

@onready var feet: Area2D = $Feet
@onready var visual: Node2D = $Visual

func _ready() -> void:
	add_to_group("player")
	# Orientation is locked to portrait, so this never changes mid-run and does
	# not need re-querying every physics frame.
	_viewport_width = get_viewport_rect().size.x
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)

func _apply_visual_settings() -> void:
	visual.color = Settings.player_color

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_set_hold(event.pressed, event.position.x)
	elif event is InputEventScreenTouch:
		_set_hold(event.pressed, event.position.x)
	elif event is InputEventKey and event.keycode == KEY_SPACE and not event.echo:
		_set_hold(event.pressed, get_viewport().get_mouse_position().x)

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

	var speed := move_speed * (boost_move_multiplier if is_fast_falling else 1.0)
	var key_axis := Input.get_axis("ui_left", "ui_right")
	if key_axis != 0.0:
		velocity.x = key_axis * speed
	elif Settings.control_scheme == Settings.ControlScheme.TILT:
		var tilt := Input.get_accelerometer().x * (-1.0 if invert_tilt else 1.0)
		if absf(tilt) < tilt_deadzone:
			velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)
		else:
			velocity.x = clampf(tilt * tilt_sensitivity, -speed, speed)
	elif is_holding:
		var pointer_x := get_viewport().get_mouse_position().x
		var drag_delta := pointer_x - _last_pointer_x
		_last_pointer_x = pointer_x
		velocity.x = clampf((drag_delta * drag_sensitivity) / delta, -speed, speed)
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)

	var prev_feet_y := feet.global_position.y
	move_and_slide()
	_wrap_screen()

	if velocity.y > 0.0:
		_check_landing(prev_feet_y, feet.global_position.y)

func _wrap_screen() -> void:
	if global_position.x < 0.0:
		global_position.x = _viewport_width
	elif global_position.x > _viewport_width:
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
		if absf(feet.global_position.x - area.global_position.x) > _platform_half_width(area) + FEET_HALF_WIDTH:
			continue
		if py < best_y:
			best_y = py
			best_area = area
	if best_area != null:
		_land_on(best_area)

func _platform_half_width(area: Node) -> float:
	return area.width / 2.0 if area is Platform else PLATFORM_HALF_WIDTH

func _land_on(area: Node) -> void:
	var is_timed := Time.get_ticks_msec() - last_press_ms <= landing_window_ms
	if area.has_method("should_land") and not area.should_land(is_timed):
		return
	var counts := is_timed and (not is_instance_valid(_last_platform) or area != _last_platform)
	is_fast_falling = false
	if is_timed:
		if counts:
			streak += 1
	elif _attempted_since_last_landing:
		streak = 0
	_attempted_since_last_landing = false
	velocity.y = _boosted_jump_velocity() if is_timed else jump_velocity
	_last_platform = area
	_play_squash(is_timed)
	Audio.set_streak(streak)
	if area.has_method("on_landed"):
		area.on_landed(self, is_timed)
	landed.emit(area, counts, streak)

func _boosted_jump_velocity() -> float:
	return boost_jump_velocity * (1.0 + streak_jump_step * clampi(streak, 0, streak_jump_cap))

func _play_squash(boosted: bool) -> void:
	var squash := Vector2(1.6, 0.42) if boosted else Vector2(1.45, 0.5)
	var stretch := Vector2(0.55, 1.65) if boosted else Vector2(0.62, 1.5)
	visual.scale = squash
	var tw := create_tween()
	tw.tween_property(visual, "scale", stretch, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
