extends Node2D
class_name FeatureGraphic

## Composes the 1024x500 Play Store feature graphic.
##
## Authored directly in output pixels: this scene has no camera and lives in a
## SubViewport that is exactly 1024x500, so every coordinate below is a pixel of
## the final PNG. feature_graphic_shot.gd owns that viewport, the 1:1 preview
## window and the export; this script owns the picture.
##
## Layout is the standard feature-graphic split -- wordmark holding the left
## half, the whole read of the game on the right: the star's limb along the
## bottom, a chain of platforms climbing away from it, and the character
## mid-flight off the top of that chain. Play may overlay a play button over the
## centre when a promo video is attached, and crops the edges on some surfaces,
## so nothing that has to survive lives in the middle or within ~60px of a side.
##
## The character flies a looping arc rather than sitting posed, so its trail and
## squash-stretch are live rather than faked. `pose_time` is the point in that
## loop the harness freezes on, and that frozen frame is what gets shot -- so
## the loop only exists to produce one good still.

signal pose_reached

@export_group("Palette")
## Forces a fixed palette for the shot, so the graphic does not come out tinted
## by whatever colours this machine happens to have saved. In-memory only --
## Settings' own setters are what write user://settings.cfg, and none of them
## are called here.
@export var force_default_palette: bool = true
@export var character_skin: Player.SkinType = Player.SkinType.PLASMA

## The three body colours, and the reason none of them are the Settings
## defaults they used to be. Same problem and same fix as icon_screenshot.gd,
## which carries the long version of this argument.
##
## The game authors its palette in HDR, with one channel past 1.0 and the rest
## under it -- the player at Color(0.904, 0.748, 2.4), the platforms at
## Color(0.740, 2.2, 0.649). That is fine in play. In a still it splits every
## object in the picture into two disagreeing halves, because the clamp to 8 bits
## and the glow threshold take opposite ends of the same colour:
##
##   * the star's body clamps to (0.904, 0.748, 1.0) and comes out PALE PINK --
##     the blue that made it violet is exactly the channel thrown away;
##   * its halo is whatever cleared the threshold, (0, 0, 1.4), which is PURE
##     BLUE.
##
## Which is why the old graphic is a pink dome sitting inside a blue glow. So
## each colour is carried at the brightness that survives the trip: the game's
## own hue, normalised so its largest channel lands at 1.0 and nothing clips.
## The white-hot cores are unaffected -- they come from the band `white` terms
## below, which are added on top.
@export var body_color: Color = Color(0.52, 0.42, 1.0)
@export var character_color: Color = Color(0.52, 0.42, 1.0)
## Toned down and desaturated from the normalised game green, which at
## Color(0.45, 1.0, 0.40) is a vivid lime: pinned at full green with the other
## two channels low, it was the most saturated thing in a frame that is
## otherwise violet, and pulled the eye off the character. Lifting red and blue
## and dropping green off the ceiling keeps it unmistakably the game's green
## while letting the star and the character carry the picture. Still under 1.0
## on every channel, for the reason the block above gives.
@export var platform_color: Color = Color(0.55, 0.88, 0.56)

## Added to the star's colour to make the eruption hotter than the body it tears
## out of; the core takes it at ERUPTION_CORE_HEAT times the strength. Kept
## near-neutral so the graphic stays one hue, matching the icon -- see
## icon_screenshot.gd for the warm alternative that was tried and rejected.
@export var eruption_heat: Color = Color(0.75, 0.70, 0.30)
const ERUPTION_CORE_HEAT := 2.1

@export_group("Background")
@export var sky_top: Color = Color(0.012, 0.018, 0.062)
@export var sky_bottom: Color = Color(0.043, 0.030, 0.098)
## Bottom-right corner tint, where the star sits -- keeps the glow from stopping
## dead at the blob's edge.
@export var sky_warm: Color = Color(0.105, 0.048, 0.120)
@export var star_count: int = 140
@export var star_seed: int = 7
@export var star_color: Color = Color(0.85, 0.92, 1.3)
@export var star_min_radius: float = 0.5
@export var star_max_radius: float = 2.4

@export_group("Star")
@export var sun_center: Vector2 = Vector2(760.0, 860.0)
@export var sun_radius: float = 470.0
@export var sun_segments: int = 180
@export var sun_speed: float = 0.45
@export var sun_churn_scale: float = 0.15
@export var sun_drift_scale: float = 0.06
## Extra atmosphere painted under the blob, on top of whatever the glow pass
## spreads. 0 turns it off.
## Carries most of the star's atmosphere, rather than the glow pass doing it.
## Deliberate: this is drawn geometry in the star's own colour, so it is
## hue-matched by construction and it only touches the star. Turning the glow
## pass up far enough to do this job instead also blooms the wordmark on the far
## side of the frame, which at 112px bold starts filling in its own counters.
@export var halo_strength: float = 3.8
## How far out the atmosphere reaches, as a multiple of sun_radius. Kept short
## enough that it does not wash out the wordmark on the far side of the frame.
@export var halo_reach: float = 1.6

## Concentric circles the halo is built from. Has to be this many: a handful of
## wide steps reads as hard-edged rings around the star rather than as falloff,
## which is exactly what it looked like at three.
## Raised from 24 once the halo got brighter: the same number of steps that
## read as smooth falloff at the old alpha read as visible concentric rings at
## this one, which is the banding in the blue glow of the previous shot.
const HALO_STEPS := 40
## Per-ring alpha before the falloff weighting. They stack, so the visible
## opacity at the star's edge is roughly HALO_STEPS times this.
const HALO_STEP_ALPHA := 0.024

## PlasmaBlob.CHARACTER_BANDS without its outer corona -- body and core only.
## That corona is one flat-alpha polygon at 1.15x radius, which at gameplay size
## is a soft rim and at this size is a hard-edged blue disc sitting around the
## star. _draw_halo covers the same span with an actual falloff instead, so the
## band is dropped rather than retuned.
##
## Copied rather than shared for the same reason icon_screenshot.gd copies it: a
## promo shot should be able to retune the star without touching the table every
## character in the game draws from.
## The star is built rather than listed, because of how little of it is on
## screen and how finely that sliver has to be graded.
##
## It is centred at (760, 860) with a radius of 470, in a frame 500 tall. Only
## its top cap shows -- from the limb at radius 470 down to radius 360 at the
## bottom edge -- so a band appears at all only if
##
##     860 - 470 * r < 500,   i.e.   r > 0.766
##
## Anything deeper is drawn underneath the picture. That is why a single mid
## band at r = 0.76, which is the right place for one on the icon, left this
## star a flat single-colour dome: its top edge landed at y = 503, three pixels
## past the bottom of the frame.
##
## So the whole limb-to-core gradient has to fit in r = 1.00 .. 0.785, and a
## handful of shells across it does not read as a gradient -- at five, each one
## is a hard-edged polygon about 23px from the next and the star comes out
## visibly ringed. Hence many faint shells instead: enough of them that the
## steps land ~7px apart and blend, with each churning a little harder and
## wandering a little further off-centre than the one outside it, so the
## boundaries stay organic rather than concentric.
const SUN_SHELLS := 30
const SUN_SHELL_INNER_R := 0.762
const SUN_SHELL_ALPHA := 0.13
## Added to the body colour at the innermost visible shell, ramped in from zero
## at the limb. Gentle on purpose: this lands around (0.80, 0.65, 1.0), lighter
## and less saturated but still plainly the same violet. Pushing it further
## turns the bottom of the frame pale pink, which is the exact look the palette
## change was made to get rid of.
const SUN_SHELL_WHITE := Color(0.36, 0.30, 0.14)
## Just under 1.0, so the brightening is spread across the whole visible cap
## rather than banked into the innermost shells. Above 1.0 it is technically a
## better falloff for a sphere, but almost the entire ramp then lands in the
## last 30px before the frame edge and the rest of the star reads flat -- which
## is the complaint this grading exists to answer.
const SUN_SHELL_EASE := 0.85
## Kept for completeness and never seen -- its top edge is 125px below frame.
const SUN_CORE := {
	"r": 0.50, "phase": 2.1, "tint": 1.0, "white": Color(1.3, 1.3, 1.0),
	"a": 0.95, "churn": 2.6, "drift": 0.12,
}

func _build_sun_bands() -> Array:
	var shells: Array = [
		{"r": 1.00, "phase": 0.0, "tint": 1.0, "white": Color(0, 0, 0),
			"a": 1.00, "churn": 1.0, "drift": 0.0},
	]
	for i in range(1, SUN_SHELLS):
		var t := float(i) / float(SUN_SHELLS - 1)
		var lift := pow(t, SUN_SHELL_EASE)
		shells.append({
			"r": lerpf(1.0, SUN_SHELL_INNER_R, t),
			# Stepped per shell so no two churn in sync, which is what stops the
			# stack reading as one shape drawn at several sizes.
			"phase": 0.6 * float(i),
			"tint": 1.0,
			"white": Color(SUN_SHELL_WHITE.r * lift, SUN_SHELL_WHITE.g * lift,
				SUN_SHELL_WHITE.b * lift),
			"a": SUN_SHELL_ALPHA,
			"churn": lerpf(1.0, 1.9, t),
			"drift": lerpf(0.0, 0.03, t),
		})
	shells.append(SUN_CORE)
	return shells

## PlasmaBlob.CHARACTER_BANDS with its single flat corona ramped across three
## fainter rings instead. Same problem the star had and the same fix: one
## flat-alpha polygon at 1.45x radius is a soft rim on a 36px character and a
## lumpy hard-edged blob on a 2.3x one. The three share a phase so they churn
## coherently and read as one glow falling off, not as three shells.
const CHARACTER_BANDS := [
	{"r": 1.62, "phase": 0.9, "tint": 0.7, "white": Color(0, 0, 0), "a": 0.07, "churn": 1.0, "drift": 0.0},
	{"r": 1.40, "phase": 0.9, "tint": 0.7, "white": Color(0, 0, 0), "a": 0.09, "churn": 1.0, "drift": 0.0},
	{"r": 1.20, "phase": 0.9, "tint": 0.8, "white": Color(0, 0, 0), "a": 0.12, "churn": 1.0, "drift": 0.0},
	{"r": 1.00, "phase": 0.0, "tint": 1.0, "white": Color(0, 0, 0), "a": 1.00, "churn": 1.0, "drift": 0.0},
	{"r": 0.76, "phase": 1.3, "tint": 1.0, "white": Color(0.30, 0.25, 0.10), "a": 0.90, "churn": 1.7, "drift": 0.05},
	{"r": 0.50, "phase": 2.1, "tint": 1.0, "white": Color(1.3, 1.3, 1.0), "a": 0.95, "churn": 2.6, "drift": 0.12},
]

@export_group("Flight")
## Where the character is headed. It never arrives during the useful part of
## the loop -- see pose_time -- so this is the arc's aim, not where it is shot.
@export var char_target: Vector2 = Vector2(880.0, 150.0)
## Upward bow at the middle of the climb, so the path curves like a jump instead
## of ruling a straight line to the target.
@export var char_bow: float = 55.0
@export var character_scale: float = 2.3
## The character draws 32 perimeter points in game, which is plenty at ~36px
## across and visibly faceted at this size -- the churn lands on a polygon
## rather than on a curve.
@export var character_segments: int = 96
## Character is inside the star for this long, then climbs, holds at the target,
## then falls back in and the loop seams.
@export var charge_time: float = 0.5
@export var rise_time: float = 0.9
@export var hold_time: float = 0.5
@export var fall_time: float = 0.7
## Where in that loop the harness freezes. Deliberately mid-climb rather than in
## the hold: at the hold the character is stationary, which empties the trail and
## flattens the squash-stretch -- the two things that make the still look like
## motion.
@export var pose_time: float = 1.13

@export_group("Eruption")
@export var eruption_lead: float = 0.35
@export var eruption_fade: float = 0.7
@export var eruption_size: float = 165.0
@export var eruption_spikes: int = 13
@export var eruption_spread: float = 2.3

@export_group("Flare Tail")
@export var tail_length: float = 430.0
@export var tail_width: float = 46.0

@onready var _sun: PlasmaBlob = $Sun
@onready var _player: Player = $Player

var _t: float = 0.0
var _launch: Vector2
var _head: Vector2
var _tail_fade: float = 0.0
var _posed: bool = false

## Parallel arrays, same shape as background_particles.gd keeps its field in --
## rolled once from `star_seed` so the same seed always produces the same sky
## and a re-shot graphic matches the last one.
var _star_pos: PackedVector2Array = PackedVector2Array()
var _star_radius: PackedFloat32Array = PackedFloat32Array()
var _star_alpha: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	if force_default_palette:
		_apply_default_palette()
	_launch = sun_center - Vector2(0.0, sun_radius)
	_setup_sun()
	_setup_character()
	_spawn_stars()
	_apply(0.0)

## The shot should look like a fresh install, not like this machine's save. Set
## on the autoload's plain fields rather than through its setters, which would
## each call _save() and overwrite the real settings file.
func _apply_default_palette() -> void:
	Settings.glow_strength = Settings.GLOW_STRENGTH_DEFAULT
	Settings.player_color = character_color
	Settings.platform_color = platform_color
	Settings.background_particle_color = Settings.PARTICLE_COLOR_DEFAULT
	Settings.player_skin = character_skin
	Settings.trail_enabled = true
	# Children have already run their own _ready by now, so they are holding
	# whatever was loaded off disk -- this is what pulls them onto the defaults.
	Settings.visual_settings_changed.emit()

func _setup_sun() -> void:
	_sun.radius = sun_radius
	_sun.segments = sun_segments
	_sun.speed = sun_speed
	_sun.churn_scale = sun_churn_scale
	_sun.drift_scale = sun_drift_scale
	_sun.color = body_color
	_sun.shape = PlasmaBlob.Shape.CIRCLE
	_sun.bands = _build_sun_bands()
	# PlasmaBlob is bottom-anchored: its centre sits one radius above its
	# origin, so the origin goes a radius below the centre we want.
	_sun.global_position = sun_center + Vector2(0.0, sun_radius)

func _setup_character() -> void:
	_player.scale = Vector2(character_scale, character_scale)
	# Position and velocity are hand-driven in _apply, same as intro.gd and
	# icon_screenshot.gd do -- physics would fight the manual writes. _process
	# stays on: that is what reads `velocity` into the squash-stretch.
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	# The trail is top_level, so it is not carried by the character's scale and
	# would shed body-sized flecks off a 2.6x body.
	_player.visual.segments = character_segments
	_player.visual.bands = CHARACTER_BANDS
	var trail: PlayerTrail = _player.trail
	trail.start_radius *= character_scale
	trail.spread *= character_scale
	trail.scatter *= character_scale

func _spawn_stars() -> void:
	var frame := _frame_size()
	var rng := RandomNumberGenerator.new()
	rng.seed = star_seed
	_star_pos.clear()
	_star_radius.clear()
	_star_alpha.clear()
	for i in range(star_count):
		var p := Vector2(rng.randf() * frame.x, rng.randf() * frame.y)
		# Anything inside the star is painted over by it, so it is only cost.
		if p.distance_to(sun_center) < sun_radius * 1.02:
			continue
		_star_pos.append(p)
		_star_radius.append(rng.randf_range(star_min_radius, star_max_radius))
		_star_alpha.append(rng.randf_range(0.22, 0.95))

func cycle_time() -> float:
	return charge_time + rise_time + hold_time + fall_time

func _process(delta: float) -> void:
	_t = fmod(_t + delta, cycle_time())
	_apply(_t)
	if not _posed and _t >= pose_time:
		_posed = true
		pose_reached.emit()

## Progress along the arc at time `t`: 0 through the charge, eased to 1 by the
## end of the climb, held, then back to 0 by the end of the fall -- so the loop
## seams exactly at t=0/cycle_time().
func _progress(t: float) -> float:
	if t < charge_time:
		return 0.0
	if t < charge_time + rise_time:
		return _smoothstep((t - charge_time) / rise_time)
	if t < charge_time + rise_time + hold_time:
		return 1.0
	return 1.0 - _smoothstep((t - charge_time - rise_time - hold_time) / fall_time)

func _smoothstep(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)

func _position_at(u: float) -> Vector2:
	# Bow peaks at u=0.5 and vanishes at both ends, so it curves the path
	# without moving the launch point or the target.
	return _launch.lerp(char_target, u) + Vector2(0.0, -char_bow) * (4.0 * u * (1.0 - u))

func _apply(t: float) -> void:
	var previous := _player.global_position
	_head = _position_at(_progress(t))
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

func _frame_size() -> Vector2:
	return get_viewport_rect().size

## A parent CanvasItem draws before its children, so everything here lands
## behind the star, the platforms and the character -- which is exactly the
## order it wants: sky, stars, halo, then the eruption showing only where it
## clears the limb, then the tail running under the character.
func _draw() -> void:
	_draw_sky()
	_draw_stars()
	_draw_halo()
	_draw_eruption()
	_draw_tail()

func _draw_sky() -> void:
	var s := _frame_size()
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0.0), s, Vector2(0.0, s.y)]),
		PackedColorArray([sky_top, sky_top, sky_warm, sky_bottom]))

func _draw_stars() -> void:
	for i in range(_star_pos.size()):
		var col := star_color
		col.a = _star_alpha[i]
		draw_circle(_star_pos[i], _star_radius[i], col)

func _draw_halo() -> void:
	if halo_strength <= 0.001:
		return
	var base := _sun.color
	# Widest first, so each subsequent ring stacks on top of the ones outside
	# it and the accumulated opacity curves up towards the star.
	for i in range(HALO_STEPS):
		var t := float(i) / float(HALO_STEPS - 1)
		var col := base * 0.9
		col.a = HALO_STEP_ALPHA * halo_strength * (0.25 + 0.75 * t)
		draw_circle(sun_center, lerpf(sun_radius * halo_reach, sun_radius, t), col)

## The eruption the character is thrown out by, lifted from icon_screenshot.gd
## and re-timed against this loop's charge rather than the intro's clock.
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

	# Lifted just past white rather than far past it: the old constants were
	# sized against an HDR body colour, and against a body that no longer clips
	# they turn the spikes into flat white shards with no hue left in them.
	var tongue := Color(base.r + eruption_heat.r, base.g + eruption_heat.g,
		base.b + eruption_heat.b, 0.80 * strength)
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

	var core := Color(
		base.r + eruption_heat.r * ERUPTION_CORE_HEAT,
		base.g + eruption_heat.g * ERUPTION_CORE_HEAT,
		base.b + eruption_heat.b * ERUPTION_CORE_HEAT, 0.9 * strength)
	draw_circle(_launch, size * 0.26, core)

## Runs back down the flight path to the launch point rather than straight down
## as the icon shot's does: here the climb is a diagonal, and a vertical tail
## would read as a separate object rather than as the path just travelled.
func _draw_tail() -> void:
	if _tail_fade <= 0.001:
		return
	var to_launch := _launch - _head
	var length := minf(tail_length, to_launch.length())
	if length <= 1.0:
		return
	var back := to_launch.normalized()
	var side := back.orthogonal() * (tail_width * 0.5)
	var outer := _sun.color * 0.8
	outer.a = 0.30 * _tail_fade
	draw_polygon(PackedVector2Array([
		_head - side, _head + side, _head + back * length,
	]), PackedColorArray([outer]))
	var inner := Color(_sun.color.r + 0.9, _sun.color.g + 0.9, _sun.color.b + 0.7, 0.85 * _tail_fade)
	draw_polygon(PackedVector2Array([
		_head - side * 0.35, _head + side * 0.35, _head + back * (length * 0.7),
	]), PackedColorArray([inner]))
