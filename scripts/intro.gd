extends Node2D
class_name IntroSequence

## Pre-run cinematic. A giant plasma star fills the bottom of a zoomed-out
## frame; a flare tears off its surface and rockets into space; the camera
## chases the flare in until it resolves into the player and the run begins.
##
## The star is a PlasmaBlob at a huge radius, always the plain plasma sphere
## (regardless of the player's equipped skin shape) in the player's own
## colour, so it reads as the character's own body scaled up -- the player
## reads as a chip off this star. `sun_churn_scale` /
## `sun_drift_scale` / `sun_speed` are turned down from the character's own
## defaults: something this large has to read as massive and mostly stable,
## not as an energetic little cell blown up to huge size.
##
## Driven by a single time accumulator rather than a tween chain, so any moment
## can be evaluated directly. That is what makes the tap-to-skip a one-line jump
## to the end state instead of a pile of tween kills.

signal finished

@export_group("Timing")
@export var sun_time: float = 1.5
@export var flare_time: float = 1.5
@export var zoom_time: float = 1.5

@export_group("Star")
@export var sun_radius: float = 2600.0
## World y of the top of the star. The flare launches from here.
@export var sun_surface_y: float = 2400.0
## The default 32 is tuned for an 18px character; at this radius it would facet.
@export var sun_segments: int = 160
## Below the character's own 3.0 -- something this large should churn like it
## is barely bound by gravity, not fizz like a small hot cell.
@export var sun_speed: float = 0.45
## Multiplier on every band's churn (see PlasmaBlob.CHARACTER_BANDS). The hot
## core band churns hardest of all on the character (2.6) -- left at full
## scale here it reads as a chaotic flicker rather than a huge body's slow
## convection, so it is dialled back without touching the band table itself.
@export var sun_churn_scale: float = 0.15
## Multiplier on every band's drift (off-centre wander). The core wanders
## noticeably on the character; scaled down so the giant version does not
## look like its centre is sliding around.
@export var sun_drift_scale: float = 0.06

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

	_sun.radius = sun_radius
	_sun.segments = sun_segments
	_sun.speed = sun_speed
	_sun.churn_scale = sun_churn_scale
	_sun.drift_scale = sun_drift_scale
	_sun.color = Settings.player_color
	# Always the plain plasma sphere, regardless of the player's equipped skin
	# shape -- a giant star, not a giant heart/flame/star-shaped skin.
	_sun.shape = PlasmaBlob.Shape.CIRCLE
	# PlasmaBlob is bottom-anchored: its centre sits one radius above its origin.
	_sun.global_position = Vector2(_play_pos.x, sun_surface_y + sun_radius * 2.0)

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
