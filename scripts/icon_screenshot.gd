extends Node2D

## Play Store icon shot. A giant plasma star fills the bottom of a zoomed-out
## frame -- the same framing intro.gd opens on -- with the character bursting
## out of it on an endless loop and a couple of huge decorative platforms
## floating nearby for scale. Nothing here is gameplay: the player's position
## and velocity are hand-driven every frame (see _apply), same as intro.gd
## does, purely so this keeps offering fresh moments to screenshot.
##
## Just open and run this scene, let it loop, and grab a screenshot whenever a
## frame looks right -- there is no fixed "best" moment, so nothing here tries
## to land on one.

@export_group("Star")
@export var sun_radius: float = 2600.0
## World y of the top of the star. The flare launches from here.
@export var sun_surface_y: float = 2400.0
@export var sun_segments: int = 160
@export var sun_speed: float = 0.45
@export var sun_churn_scale: float = 0.15
@export var sun_drift_scale: float = 0.06

@export_group("Burst Loop")
## Star sits quiet before each burst -- the character is hidden inside it.
@export var charge_time: float = 0.5
## Eruption fires and the character rises to peak_height above the surface.
@export var rise_time: float = 0.9
## Hangs at the peak -- the character reads clearest here, mid-burst.
@export var hold_time: float = 0.5
## Arcs back down into the star, then the cycle repeats.
@export var fall_time: float = 0.7
@export var peak_height: float = 1300.0

@export_group("Eruption")
@export var eruption_lead: float = 0.35
@export var eruption_fade: float = 0.7
@export var eruption_size: float = 950.0
@export var eruption_spikes: int = 13
@export var eruption_spread: float = 2.3

@export_group("Flare")
@export var tail_length: float = 700.0
@export var tail_width: float = 42.0

## Same three rings as PlasmaBlob.CHARACTER_BANDS, just with the outer corona
## (the faint, dulled-tint band that reads as the star's "outer blue") pulled
## in from 1.45x radius to 1.15x -- a copy so this icon shot can retune it
## without touching the shared table every character uses in gameplay.
const SUN_BANDS := [
	{"r": 1.15, "phase": 0.9, "tint": 0.7, "white": Color(0, 0, 0), "a": 0.22, "churn": 1.0, "drift": 0.0},
	{"r": 1.00, "phase": 0.0, "tint": 1.0, "white": Color(0, 0, 0), "a": 1.00, "churn": 1.0, "drift": 0.0},
	{"r": 0.50, "phase": 2.1, "tint": 1.0, "white": Color(1.3, 1.3, 1.0), "a": 0.95, "churn": 2.6, "drift": 0.12},
]

@onready var _sun: PlasmaBlob = $Sun
@onready var _player: CharacterBody2D = $Player
@onready var _camera: Camera2D = $Camera2D

var _t: float = 0.0
var _launch: Vector2
var _head: Vector2
var _tail_fade: float = 0.0

func _ready() -> void:
	_launch = Vector2(_player.global_position.x, sun_surface_y)

	_sun.radius = sun_radius
	_sun.segments = sun_segments
	_sun.speed = sun_speed
	_sun.churn_scale = sun_churn_scale
	_sun.drift_scale = sun_drift_scale
	_sun.color = Settings.player_color
	_sun.shape = PlasmaBlob.Shape.CIRCLE
	_sun.bands = SUN_BANDS
	# PlasmaBlob is bottom-anchored: its centre sits one radius above its
	# origin, same convention as intro.gd's Sun.
	_sun.global_position = Vector2(_launch.x, sun_surface_y + sun_radius * 2.0)

	# Driven by hand below, same as intro.gd -- physics would otherwise fight
	# the manual position writes.
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)

	_apply(0.0)

func cycle_time() -> float:
	return charge_time + rise_time + hold_time + fall_time

func _process(delta: float) -> void:
	_t = fmod(_t + delta, cycle_time())
	_apply(_t)

## Height above the launch point at time `t` in the cycle: 0 through the
## charge, up to peak_height by the end of the rise, held flat, then back to 0
## by the end of the fall -- so the loop seams perfectly at t=0/cycle_time().
func _rise(t: float) -> float:
	if t < charge_time:
		return 0.0
	if t < charge_time + rise_time:
		var u := (t - charge_time) / rise_time
		return peak_height * (u * u * (3.0 - 2.0 * u))
	if t < charge_time + rise_time + hold_time:
		return peak_height
	var u2 := (t - charge_time - rise_time - hold_time) / fall_time
	return peak_height * (1.0 - u2 * u2 * (3.0 - 2.0 * u2))

func _apply(t: float) -> void:
	var previous := _player.global_position
	_head = Vector2(_launch.x, sun_surface_y - _rise(t))
	_player.global_position = _head
	var dt := get_process_delta_time()
	_player.velocity = (_head - previous) / dt if dt > 0.0 else Vector2.ZERO

	if t < charge_time:
		_player.visible = false
		_tail_fade = 0.0
	elif t < charge_time + rise_time:
		_player.visible = true
		_tail_fade = clampf((t - charge_time) / rise_time * 3.0, 0.0, 1.0)
	elif t < charge_time + rise_time + hold_time:
		_player.visible = true
		_tail_fade = 1.0
	else:
		_player.visible = true
		_tail_fade = 1.0 - (t - charge_time - rise_time - hold_time) / fall_time
	queue_redraw()

func _draw() -> void:
	_draw_eruption()
	_draw_tail()

## Solar flare at the launch point -- lifted straight from intro.gd's eruption,
## just re-timed against this loop's own charge_time/eruption_lead instead of
## the intro's sun_time.
func _draw_eruption() -> void:
	var span := eruption_lead + eruption_fade
	var age := (_t - (charge_time - eruption_lead)) / span
	if age <= 0.0 or age >= 1.0:
		return
	var peak := eruption_lead / span
	var strength: float = age / peak if age < peak else (1.0 - age) / (1.0 - peak)
	strength = clampf(strength, 0.0, 1.0)
	var size := eruption_size * (0.25 + 0.75 * age)
	var base := _sun.color

	var halo := base * 0.9
	halo.a = 0.22 * strength
	draw_circle(_launch, size * 0.62, halo)

	var tongue := Color(base.r * 1.1 + 1.1, base.g * 1.1 + 1.1, base.b * 1.1 + 0.85, 0.80 * strength)
	for i in range(eruption_spikes):
		var f := float(i) / float(maxi(eruption_spikes - 1, 1))
		var a := -PI * 0.5 + (f - 0.5) * eruption_spread
		var n := sin(float(i) * 12.9898) * 43758.5453
		var jitter: float = n - floor(n)
		var length := size * (0.45 + 0.55 * jitter) * (0.86 + 0.14 * sin(_t * 6.0 + float(i)))
		var dir := Vector2(cos(a), sin(a))
		var wide := dir.orthogonal() * size * 0.085 * (0.5 + jitter * 0.5)
		draw_polygon(PackedVector2Array([
			_launch - wide, _launch + wide, _launch + dir * length,
		]), PackedColorArray([tongue]))

	var core := Color(base.r + 1.6, base.g + 1.6, base.b + 1.3, 0.9 * strength)
	draw_circle(_launch, size * 0.26, core)

func _draw_tail() -> void:
	if _tail_fade <= 0.001:
		return
	var length := minf(tail_length, _head.distance_to(_launch))
	if length <= 1.0:
		return
	var back := Vector2(0.0, 1.0)
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
