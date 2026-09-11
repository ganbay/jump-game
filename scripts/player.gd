extends CharacterBody2D
class_name Player

signal landed(platform, boosted, streak)

## Selectable character visuals. Every one is the PlasmaBlob cell (see
## plasma_blob.gd) in a different Shape -- same churn, glow and squishy physics,
## just a different silhouette.
##
## Settings persists this enum as a raw int, so entries must not be inserted
## or reordered -- new ones go on the end. PLASMA holds slot 0 as the default,
## which is also the slot the retired solid-body skin used, so a save from that
## era opens on PLASMA.
enum SkinType { PLASMA, DOME, TRIANGLE, SQUARE, PRISM, STAR, HEART, FLAME, SPARKLE }

## Display names for the settings menu, indexed by SkinType.
const SKIN_NAMES := ["PLASMA", "DOME", "TRIANGLE", "SQUARE", "PRISM", "STAR",
	"HEART", "FLAME", "SPARKLE"]

## The PlasmaBlob.Shape each skin draws.
const SKIN_SHAPES := {
	SkinType.PLASMA: PlasmaBlob.Shape.CIRCLE,
	SkinType.DOME: PlasmaBlob.Shape.DOME,
	SkinType.TRIANGLE: PlasmaBlob.Shape.TRIANGLE,
	SkinType.SQUARE: PlasmaBlob.Shape.SQUARE,
	SkinType.PRISM: PlasmaBlob.Shape.PRISM,
	SkinType.STAR: PlasmaBlob.Shape.STAR,
	SkinType.HEART: PlasmaBlob.Shape.HEART,
	SkinType.FLAME: PlasmaBlob.Shape.FLAME,
	SkinType.SPARKLE: PlasmaBlob.Shape.SPARKLE,
}

@export var move_speed: float = 900.0
@export var gravity: float = 1600.0
@export var fast_fall_gravity: float = 3600.0
@export var jump_velocity: float = -900.0
@export var boost_jump_velocity: float = -1300.0
@export var boost_move_multiplier: float = 1.4
@export var streak_jump_step: float = 0.1
@export var streak_jump_cap: int = 10
@export var landing_window_ms: int = 100
@export var drag_sensitivity: float = 1.3
## How fast the arrow keys ramp horizontal speed. They used to snap straight to
## full move_speed on the first frame, which on a keyboard reads as
## hair-trigger: one tap threw the character across a whole platform.
@export var key_accel: float = 4200.0
@export var tilt_sensitivity: float = 220.0
@export var tilt_deadzone: float = 0.6
@export var invert_tilt: bool = false

@export_group("Squash & Stretch")
## How much the shape stretches per unit of vertical speed.
@export var stretch_per_speed: float = 0.00022
@export var max_stretch: float = 0.34
## How hard the shape compresses on a normal / boosted landing.
@export var land_impulse: float = 1.0
@export var boost_land_impulse: float = 1.3
## Spring that returns the impact squash to rest. Lower damping = bouncier.
@export var squash_stiffness: float = 220.0
@export var squash_damping: float = 14.0
## Sideways lean while moving horizontally. Set to 0 to disable.
@export var lean_per_speed: float = 0.00018
@export var max_lean: float = 0.2
## How far the shape deforms per unit of squash.
@export var squash_deform: float = 0.55

@export_group("Plasma Squish")
## The plasma cell is a fluid body: it deforms further and keeps jiggling
## longer after impact than a solid one would. These scale the base Squash &
## Stretch values above.
@export var plasma_stiffness_scale: float = 0.68
@export var plasma_damping_scale: float = 0.5
@export var plasma_deform_scale: float = 1
@export var plasma_impulse_scale: float = 1.25

var is_holding: bool = false
var is_fast_falling: bool = false
var streak: int = 0
var last_press_ms: int = -999999
## The press before `last_press_ms`. A timed landing has to come from one
## deliberate tap, so the window must hold exactly one press. Every press
## refreshes `last_press_ms`, so without this second timestamp a player mashing
## the screen on the way down satisfies the window on every landing and never
## has to time anything -- and in TOUCH mode they are already pressing to
## steer, which made it close to free.
var _prev_press_ms: int = -999999
var _last_pointer_x: float = 0.0
## Whether the hold in progress came from a pointer. A keyboard hold must not
## run the drag branch below: it would read the (stationary) mouse every frame
## and zero the horizontal velocity, so tapping space to time a landing killed
## whatever drift the arrow keys had built up.
var _hold_is_pointer: bool = true
var _attempted_since_last_landing: bool = false
var _viewport_width: float = 720.0
## Impact compression, 1.0 = fully squashed. Driven as a damped spring rather
## than a tween so repeated landings add to it instead of fighting over
## visual.scale, and so the shape keeps reacting for the whole jump.
var _squash: float = 0.0
var _squash_vel: float = 0.0
var _lean: float = 0.0
const FEET_HALF_WIDTH := 20.0
const FEET_HALF_HEIGHT := 5.0
const PLATFORM_HALF_WIDTH := 45.0
const PLATFORM_HALF_HEIGHT := 6.0

const COLOR := Color(0.66295815, 2.299754, 0.0, 1.0)

@onready var feet: Area2D = $Feet
@onready var visual: PlasmaBlob = $PlasmaVisual
@onready var trail: PlayerTrail = $Trail

func _ready() -> void:
	add_to_group("player")
	# Orientation is locked to portrait, so this never changes mid-run and does
	# not need re-querying every physics frame.
	_viewport_width = get_viewport_rect().size.x
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)

func _apply_visual_settings() -> void:
	var shape: PlasmaBlob.Shape = SKIN_SHAPES.get(
		Settings.player_skin, PlasmaBlob.Shape.CIRCLE)
	visual.shape = shape
	visual.color = Settings.player_color
	trail.color = Settings.player_color
	trail.shape = shape
	trail.set_enabled(Settings.trail_enabled)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# On a touchscreen every tap also arrives a second time as an emulated
		# mouse click (device -1). Letting both through pushes the same tap into
		# `last_press_ms` twice, which leaves `_prev_press_ms` sitting on the very
		# same timestamp -- so `single_tap` is never true and a timed landing is
		# impossible on mobile. The emulation stays on: the drag steering below
		# reads the mouse position, which is only fed by it.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_set_hold(event.pressed, event.position.x)
	elif event is InputEventScreenTouch:
		_set_hold(event.pressed, event.position.x)
	elif event is InputEventKey and event.keycode == KEY_SPACE and not event.echo:
		_set_hold(event.pressed, get_viewport().get_mouse_position().x, false)

func _set_hold(pressed: bool, pointer_x: float, from_pointer: bool = true) -> void:
	var was_holding := is_holding
	is_holding = pressed
	if pressed:
		_hold_is_pointer = from_pointer
		_prev_press_ms = last_press_ms
		last_press_ms = Time.get_ticks_msec()
		_last_pointer_x = pointer_x
		_attempted_since_last_landing = true
	elif was_holding and velocity.y >= 0.0:
		# Guarded on was_holding so a release we never saw the press for -- the
		# lift after a tap that skipped the intro -- cannot trigger a fast fall.
		is_fast_falling = true

func _physics_process(delta: float) -> void:
	var g: float = fast_fall_gravity if is_fast_falling else gravity
	velocity.y += g * delta

	var speed := move_speed * (boost_move_multiplier if is_fast_falling else 1.0)
	var key_axis := Input.get_axis("ui_left", "ui_right")
	if key_axis != 0.0:
		velocity.x = move_toward(velocity.x, key_axis * speed, key_accel * delta)
	elif Settings.control_scheme == Settings.ControlScheme.TILT:
		var tilt := Input.get_accelerometer().x * (-1.0 if invert_tilt else 1.0)
		if absf(tilt) < tilt_deadzone:
			velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)
		else:
			velocity.x = clampf(tilt * tilt_sensitivity, -speed, speed)
	elif is_holding and _hold_is_pointer:
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
	var now := Time.get_ticks_msec()
	# Counting presses since the last landing would not work here: steering is
	# press-and-drag, so an ordinary flight already spends two or three presses
	# before the timing tap. What has to be sole is the press inside the window.
	var in_window := now - last_press_ms <= landing_window_ms
	var single_tap := now - _prev_press_ms > landing_window_ms
	var is_timed := in_window and single_tap
	# The boost belongs to the platform, not to "wasn't the last one I touched":
	# a mistimed landing spends nothing, so the next streak can start right here.
	var boosted := is_timed and not _boost_spent(area)
	is_fast_falling = false
	if is_timed:
		if boosted:
			streak += 1
			_spend_boost(area)
	elif _attempted_since_last_landing:
		streak = 0
	_attempted_since_last_landing = false
	velocity.y = _boosted_jump_velocity() if boosted else jump_velocity
	_play_squash(boosted)
	Audio.set_streak(streak)
	if area.has_method("on_landed"):
		# is_timed goes along with boosted: a platform that rewards a perfect
		# landing has to see the timing itself, not just whether this landing
		# happened to be the one that claimed the platform's streak boost.
		area.on_landed(self, boosted, is_timed)
	landed.emit(area, boosted, streak)

func _boost_spent(area: Node) -> bool:
	return area is Platform and area.boost_spent

func _spend_boost(area: Node) -> void:
	if area is Platform:
		area.boost_spent = true

func _boosted_jump_velocity() -> float:
	return boost_jump_velocity * (1.0 + streak_jump_step * clampi(streak, 0, streak_jump_cap))

func _play_squash(boosted: bool) -> void:
	# An impact is instantaneous, so set the compression directly and let the
	# spring in _process resolve it.
	_squash = (boost_land_impulse if boosted else land_impulse) * plasma_impulse_scale
	_squash_vel = 0.0

## Visual-only, so it runs at render rate rather than the physics tick.
func _process(delta: float) -> void:
	# Clamped so a frame hitch cannot push the explicit-Euler spring past its
	# stability limit and make the shape explode.
	var d := minf(delta, 0.05)
	# Damped spring pulling the impact squash back to neutral.
	_squash_vel += (-squash_stiffness * plasma_stiffness_scale * _squash
		- squash_damping * plasma_damping_scale * _squash_vel) * d
	_squash += _squash_vel * d

	# Continuous stretch from vertical speed, in either direction: this is what
	# keeps the shape alive during the airtime the old tween left frozen.
	var speed_stretch := clampf(absf(velocity.y) * stretch_per_speed, 0.0, max_stretch)

	var deform := squash_deform * plasma_deform_scale
	visual.scale = Vector2(
		maxf(1.0 + _squash * deform - speed_stretch * 0.5, 0.2),
		maxf(1.0 - _squash * deform + speed_stretch, 0.2)
	)

	var target_lean := clampf(velocity.x * lean_per_speed, -max_lean, max_lean)
	_lean = lerpf(_lean, target_lean, 1.0 - exp(-12.0 * d))
	visual.rotation = _lean
