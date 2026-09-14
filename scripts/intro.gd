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

## Concentric bands, outermost first. Two of them sit outside the disc as the
## corona; the rest are the body, whose fill radii are 100%, 93%, 82%, 62%, 34%
## and 16% of the star.
##
## Tint climbs and white is added inward, which is limb darkening: a real star
## is dimmest at its edge, where you look through more of its atmosphere, and
## white-hot at the centre.
##
## `churn` and `drift` run the *other* way -- highest just under the limb,
## falling to almost nothing at the centre. A star's outer layers are the
## convective ones; the core is the most tightly bound thing in the system and
## should sit dead still. Reversing that is what made the old star read as a
## lava lamp: the brightest, most eye-catching part of it was also the part
## thrashing around and wandering off-centre.
##
## The silhouette band (r = 1.0) is deliberately calmer than the two under it,
## so the boiling shows as churn *inside* the disc rather than as a lumpy
## outline.
##
## Tints and added white are held well below the point where glow blows them
## out. The star has to read as a huge hot body, not as a light source pointed
## at the camera -- and once the middle clips to white the limb darkening that
## gives it its volume stops being visible at all.
const STAR_BANDS := [
	{"r": 1.22, "phase": 3.5, "tint": 0.20, "white": Color(0, 0, 0), "a": 0.07, "churn": 2.00, "drift": 0.008},
	{"r": 1.09, "phase": 2.4, "tint": 0.30, "white": Color(0, 0, 0), "a": 0.11, "churn": 1.60, "drift": 0.005},
	{"r": 1.00, "phase": 0.0, "tint": 0.40, "white": Color(0, 0, 0), "a": 1.0, "churn": 0.70, "drift": 0.000},
	{"r": 0.93, "phase": 0.7, "tint": 0.58, "white": Color(0.02, 0.02, 0.01), "a": 1.0, "churn": 1.20, "drift": 0.004},
	{"r": 0.82, "phase": 1.4, "tint": 0.82, "white": Color(0.06, 0.06, 0.04), "a": 1.0, "churn": 1.00, "drift": 0.002},
	{"r": 0.62, "phase": 2.1, "tint": 1.12, "white": Color(0.18, 0.18, 0.13), "a": 1.0, "churn": 0.35, "drift": 0.000},
	{"r": 0.34, "phase": 2.8, "tint": 1.42, "white": Color(0.42, 0.42, 0.32), "a": 1.0, "churn": 0.12, "drift": 0.000},
	{"r": 0.16, "phase": 3.1, "tint": 1.65, "white": Color(0.72, 0.72, 0.56), "a": 1.0, "churn": 0.04, "drift": 0.000},
]

@export_group("Star")
@export var sun_radius: float = 2600.0
## World y of the top of the star. The flare launches from here.
@export var sun_surface_y: float = 2400.0
## The default 32 is tuned for an 18px character; at this radius it would facet.
@export var sun_segments: int = 160
## Deformation amplitudes, scaled per band by that band's `churn`. Close to the
## character's own tuning: the churn gradient already spends nearly all of its
## range on the outer bands, so pushing these up as well just made the whole
## surface noisy. The core's 0.04 multiplier keeps it still regardless.
@export var sun_wobble: float = 0.030
@export var sun_flare: float = 0.022
## The high-frequency term, and the one that reads as a photosphere rather than
## as a blob: 11 and 17 lobes at this radius are surface texture, not shape.
@export var sun_turbulence: float = 0.028
## Uniform pulse. Stays tiny -- the whole star inflating and deflating reads as
## a bouncing ball, which is the one thing something this large must never do.
@export var sun_breathe: float = 0.005
@export var sun_speed: float = 0.9

@export_group("Star surface")
## Rate of everything StarSurface draws on the face and off the limb.
@export var surface_speed: float = 1.0

@export_group("Eruption")
## A solar flare tears the surface open and throws the character clear of it.
## Peaks exactly on the launch beat, so the character emerges out of the burst.
@export var eruption_lead: float = 0.4
@export var eruption_fade: float = 0.8
@export var eruption_size: float = 950.0
@export var eruption_spikes: int = 13
## Fan width of the tongues of plasma, in radians.
@export var eruption_spread: float = 2.3

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
var _surface: StarSurface
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
	_surface = $Sun/StarSurface
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
	_sun.turbulence = sun_turbulence
	_sun.breathe = sun_breathe
	_sun.speed = sun_speed
	_sun.color = Settings.player_color
	# PlasmaBlob is bottom-anchored: its centre sits one radius above its origin.
	_sun.global_position = Vector2(_play_pos.x, sun_surface_y + sun_radius * 2.0)

	# The surface detail is a child of the blob, so it inherits the transform and
	# only needs to agree on the radius and colour the blob was just given.
	_surface.radius = sun_radius
	_surface.color = _sun.color
	_surface.speed = surface_speed

	_player.global_position = _launch  # so the first frame reports zero velocity
	_t = 0.0
	_running = true
	visible = true
	set_process(true)
	_apply(0.0)

## Fast-forwards through the rest of the cinematic instead of cutting straight
## to the end state -- _apply(t) already supports evaluating any moment
## directly, so animating t up to total_time() is a smooth zoom-ahead rather
## than a jarring jump.
func skip() -> void:
	if not _running:
		return
	_running = false
	set_process(false)
	var tw := create_tween()
	tw.tween_method(_apply, _t, total_time(), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_finish)

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
	_draw_eruption()
	_draw_tail()

## Solar flare at the launch point. Brightness peaks exactly on the launch beat
## while the size keeps growing, so the burst is still opening outward as the
## character clears it rather than already collapsing.
func _draw_eruption() -> void:
	var span := eruption_lead + eruption_fade
	var age := (_t - (sun_time - eruption_lead)) / span
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
		# Deterministic per-tongue variation, so the flare does not reshuffle
		# itself every frame the way per-frame randomness would.
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
