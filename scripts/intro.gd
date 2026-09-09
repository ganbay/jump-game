extends Node2D
class_name IntroSequence

## Pre-run cinematic. A giant plasma star fills the bottom of a zoomed-out
## frame; a flare tears off its surface and rockets into space; the camera
## chases the flare in until it resolves into the player and the run begins.
##
## The star is a PlasmaBlob at a huge radius, so it is literally the character's
## own shape scaled up -- the player reads as a chip off this star, which is
## also why it takes the player's colour.
##
## Driven by a single time accumulator rather than a tween chain, so any moment
## can be evaluated directly. That is what makes the tap-to-skip a one-line jump
## to the end state instead of a pile of tween kills.

signal finished

@export_group("Timing")
@export var sun_time: float = 1.5
@export var flare_time: float = 1.5
@export var zoom_time: float = 1.5

## Five concentric bands, outermost first. The thicknesses asked for -- 5%, 10%,
## 20%, 40%, 25% of the radius -- sum to the whole disc, so these are the fill
## radii of each band: 100%, 95%, 85%, 65%, 25%.
##
## Tint climbs and white is added inward, which is limb darkening: a real star
## is dimmest at its edge, where you look through more of its atmosphere, and
## white-hot at the centre.
const STAR_BANDS := [
	{"r": 1.00, "phase": 0.0, "tint": 0.40, "white": Color(0, 0, 0), "a": 1.0, "churn": 1.0, "drift": 0.0},
	{"r": 0.95, "phase": 0.7, "tint": 0.70, "white": Color(0.04, 0.04, 0.03), "a": 1.0, "churn": 1.0, "drift": 0.0},
	{"r": 0.85, "phase": 1.4, "tint": 1.10, "white": Color(0.14, 0.14, 0.10), "a": 1.0, "churn": 1.0, "drift": 0.0},
	{"r": 0.65, "phase": 2.1, "tint": 1.70, "white": Color(0.45, 0.45, 0.34), "a": 1.0, "churn": 1.0, "drift": 0.0},
	{"r": 0.25, "phase": 2.8, "tint": 2.20, "white": Color(1.50, 1.50, 1.20), "a": 1.0, "churn": 1.0, "drift": 0.02},
]

@export_group("Star")
@export var sun_radius: float = 2600.0
## World y of the top of the star. The flare launches from here.
@export var sun_surface_y: float = 2400.0
## The default 32 is tuned for an 18px character; at this radius it would facet.
@export var sun_segments: int = 160
## The star's limb should read as a hard circle, so it deforms far less than the
## character does, and churns slowly -- something this large should not look busy.
@export var sun_wobble: float = 0.004
@export var sun_flare: float = 0.0
@export var sun_breathe: float = 0.006
@export var sun_speed: float = 0.6

@export_group("Flight")
## The speed the ejection settles at, and the exact speed the character is
## handed to gameplay still carrying. The flight is defined by this velocity
## profile rather than by end positions, so there is no seam at the handoff:
## the run simply continues the motion the intro was already making.
@export var cruise_speed: float = 2600.0
## Sharpness of the ejection ramp. Higher reaches cruise sooner out of the star.
@export var launch_sharpness: float = 4.0

@export_group("Framing")
@export var start_zoom: float = 0.3
## Camera y for the opening beat, framing the star's edge across the bottom.
@export var open_camera_y: float = 2160.0
## Where the flare sits on screen, in pixels from centre (negative is above), at
## the end of the ejection. It climbs the frame, which is what shows the speed
## while the camera is still too far out for the motion to read on its own.
@export var flare_offset_px: float = -320.0
## Screen offset at the handoff, matching how gameplay frames the character.
@export var handoff_offset_px: float = -20.0

@export_group("Flare")
@export var tail_length: float = 700.0
@export var tail_width: float = 42.0

var _t: float = 0.0
var _running: bool = false
var _camera: Camera2D
var _player: CharacterBody2D
var _sun: PlasmaBlob
var _play_pos: Vector2
var _play_camera: Vector2
var _launch: Vector2
var _head: Vector2
var _tail_fade: float = 0.0
## Screen offset for the opening beat, derived so the star frames exactly as
## `open_camera_y` asks. Every beat then drives the camera the same way.
var _open_offset_px: float = 0.0

func _ready() -> void:
	_sun = $Sun
	visible = false
	set_process(false)

func total_time() -> float:
	return sun_time + flare_time + zoom_time

func begin(camera: Camera2D, player: CharacterBody2D) -> void:
	_camera = camera
	_player = player
	_play_pos = player.global_position
	_play_camera = camera.global_position
	_launch = Vector2(_play_pos.x, sun_surface_y)
	_open_offset_px = (sun_surface_y - open_camera_y) * start_zoom

	_sun.bands = STAR_BANDS
	_sun.radius = sun_radius
	_sun.segments = sun_segments
	_sun.wobble = sun_wobble
	_sun.flare = sun_flare
	_sun.breathe = sun_breathe
	_sun.speed = sun_speed
	_sun.color = Settings.player_color
	# PlasmaBlob is bottom-anchored: its centre sits one radius above its origin.
	_sun.global_position = Vector2(_play_pos.x, sun_surface_y + sun_radius * 2.0)

	_player.global_position = _launch  # so the first frame reports zero velocity
	_t = 0.0
	_running = true
	visible = true
	set_process(true)
	_apply(0.0)

func skip() -> void:
	if _running:
		_finish()

func _process(delta: float) -> void:
	_t += delta
	if _t >= total_time():
		_finish()
		return
	_apply(_t)

## Distance travelled from the launch point by time `t`. Closed form, so the
## trajectory is frame-rate independent and a skip lands exactly where a full
## playthrough would have.
func _travel(t: float) -> float:
	if t <= sun_time:
		return 0.0
	var n := launch_sharpness
	if t < sun_time + flare_time:
		var u := (t - sun_time) / flare_time
		return cruise_speed * flare_time * (u + (pow(1.0 - u, n + 1.0) - 1.0) / (n + 1.0))
	var ejection := cruise_speed * flare_time * (1.0 - 1.0 / (n + 1.0))
	var u3 := clampf((t - sun_time - flare_time) / zoom_time, 0.0, 1.0)
	# Cruise: velocity is already at `cruise_speed` and simply holds, which is
	# why the character is travelling at full speed for the whole zoom.
	return ejection + cruise_speed * zoom_time * u3

func _head_y(t: float) -> float:
	return sun_surface_y - _travel(t)

func _apply(t: float) -> void:
	_head = Vector2(_launch.x, _head_y(t))
	var zoom := start_zoom
	var offset_px := _open_offset_px
	if t < sun_time:
		_player.visible = false
		_tail_fade = 0.0
	elif t < sun_time + flare_time:
		var u := (t - sun_time) / flare_time
		_player.visible = true
		offset_px = lerpf(_open_offset_px, flare_offset_px, u * u * (3.0 - 2.0 * u))
		_tail_fade = clampf(u * 3.0, 0.0, 1.0)
	else:
		var u := (t - sun_time - flare_time) / zoom_time
		var e := u * u * (3.0 - 2.0 * u)
		_player.visible = true
		# Exponential rather than linear: perceived scale is multiplicative, so a
		# straight lerp of the zoom value visibly stalls halfway. Stepping by a
		# constant ratio per unit time is what reads as actually moving closer.
		zoom = start_zoom * pow(1.0 / start_zoom, e)
		offset_px = lerpf(flare_offset_px, handoff_offset_px, e)
		_tail_fade = 1.0 - e
	_camera.zoom = Vector2.ONE * zoom
	_camera.global_position = Vector2(_play_camera.x, _head.y - offset_px / zoom)
	_drive_player(_head)
	queue_redraw()

## Moves the character and synthesises the velocity that motion implies, so the
## squash spring stretches it out and its own trail emits -- both of those read
## from `velocity`, which physics is not updating while the intro owns the player.
func _drive_player(to: Vector2) -> void:
	var previous := _player.global_position
	_player.global_position = to
	var dt := get_process_delta_time()
	if dt > 0.0:
		_player.velocity = (to - previous) / dt

func _finish() -> void:
	_running = false
	set_process(false)
	visible = false
	_camera.zoom = Vector2.ONE
	var end_y := _head_y(total_time())
	_player.global_position = Vector2(_play_pos.x, end_y)
	_camera.global_position = Vector2(_play_camera.x, end_y - handoff_offset_px)
	# Handed over still travelling, at exactly the speed the flight ended on.
	_player.velocity = Vector2(0.0, -cruise_speed)
	_player.visible = true
	finished.emit()
	queue_free()

func _draw() -> void:
	if _tail_fade <= 0.001:
		return
	var length := minf(tail_length, _head.distance_to(_launch))
	if length <= 1.0:
		return
	var back := Vector2(0.0, 1.0)  # the tail points back down toward the star
	var half := tail_width * 0.5
	var outer := _sun.color * 0.8
	outer.a = 0.30 * _tail_fade
	draw_polygon(PackedVector2Array([
		_head + Vector2(-half, 0.0),
		_head + Vector2(half, 0.0),
		_head + back * length,
	]), PackedColorArray([outer]))
	var inner := Color(_sun.color.r + 0.9, _sun.color.g + 0.9, _sun.color.b + 0.7, 0.85 * _tail_fade)
	draw_polygon(PackedVector2Array([
		_head + Vector2(-half * 0.35, 0.0),
		_head + Vector2(half * 0.35, 0.0),
		_head + back * (length * 0.7),
	]), PackedColorArray([inner]))
