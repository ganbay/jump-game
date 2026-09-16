extends Node2D

## Composes the 512x512 Play Store icon: the character erupting off the star,
## filling the frame.
##
## Authored directly in output pixels -- no camera, and the SubViewport this
## lives in is exactly 512x512, so every coordinate below is a pixel of the
## final PNG. promo_shot.gd owns that viewport, the 1:1 preview and the export.
##
## An icon is mostly seen at 48px in a grid, which is what every choice here is
## for: one centred subject big enough to survive the downscale, the star's glow
## filling the frame so it does not read as a mostly-black tile, and nothing
## small enough to turn into noise. The platforms this scene used to float
## "for scale" were exactly that noise and are gone. Corners are left clear --
## Play rounds them and drops a shadow, so anything out there is cropped.
##
## The character flies a looping burst rather than sitting posed, so its trail
## and squash-stretch are live rather than faked. `pose_time` is the point in
## that loop the harness freezes on, and that frozen frame is what gets shot.

signal pose_reached

@export_group("Palette")
## Forces a fixed palette, so the icon does not come out tinted by whatever
## colours this machine happens to have saved. In-memory only -- Settings' own
## setters are what write user://settings.cfg, and none of them are called here.
@export var force_default_palette: bool = true
@export var character_skin: Player.SkinType = Player.SkinType.PLASMA

## The body colour of both the star and the character, and the reason this is
## not Settings.PLAYER_COLOR_DEFAULT.
##
## The game authors that default as Color(0.904, 0.748, 2.4) -- HDR, with only
## the blue channel above 1.0. In play that is fine: the character is a small
## bright thing moving fast. In a still it tears the image in two, because the
## two halves of the render disagree about what colour it is:
##
##   * the body is clamped on the way to an 8-bit PNG, to (0.904, 0.748, 1.0).
##     The blue that made it violet is precisely the channel thrown away, so
##     the body comes out PALE PINK;
##   * the glow pass keeps what is *above* the threshold, (0, 0, 1.4), which is
##     PURE BLUE.
##
## One authored colour, two different hues on screen, and neither of them the
## violet that was written down. No choice of HDR colour fixes that -- clipping
## destroys the hue from one end and the threshold destroys it from the other,
## and the only colours that survive both are the ones that clip to white.
##
## So the icon carries the same hue at a brightness that survives the trip to 8
## bits: the game's own colour, normalised so its largest channel lands at 1.0.
## The body is then the violet that was authored, and -- with the Environment's
## glow_bloom raised to glow pixels under the threshold -- the halo is a blurred
## copy of that same violet rather than a different colour entirely.
##
## Nothing is given up by dropping out of HDR here. The white-hot core does not
## come from the body colour at all: it comes from the core band's `white` term
## (see PROMO_BANDS), which is added on top and still blows out exactly as
## before.
@export var body_color: Color = Color(0.52, 0.42, 1.0)

## The character's own colour, kept separate from the star's so the icon can
## decide what the character is: a chip off the same body, which is what the
## game's fiction says and what an identical colour reads as, or something
## escaping it, which a contrasting one reads as. The first is truer; the second
## separates subject from background at 48px, where the two currently merge into
## one bright mass. Same ceiling as body_color and for the same reason -- no
## channel above 1.0, or the body and its halo part company again.
@export var character_color: Color = Color(0.52, 0.42, 1.0)

## Added to the star's colour to make the eruption hotter than the body it tears
## out of. The tongues take this; the core takes it at ERUPTION_CORE_HEAT times
## the strength.
##
## Near-neutral on purpose: lifted enough that the burst reads as hotter than
## the body, but not far enough to introduce a second hue. The icon is one
## violet throughout -- star, character, both halos, the limb, this -- and that
## is a deliberate choice rather than an oversight. A warm burst here (around
## Color(1.45, 0.80, 0.12)) does separate the character from the eruption at
## 48px, where the two otherwise merge into a single bright mass; it was tried
## and rejected, because holding the whole icon to one colour is worth more than
## that separation.
@export var eruption_heat: Color = Color(0.75, 0.70, 0.30)
const ERUPTION_CORE_HEAT := 2.1

@export_group("Background")
@export var sky_top: Color = Color(0.012, 0.018, 0.062)
@export var sky_bottom: Color = Color(0.075, 0.040, 0.130)
## Deliberately few and large. A scatter of small dots is legible at 512 and
## turns into dirt at 48, which is what the old icon did.
@export var star_count: int = 26
@export var star_seed: int = 3
@export var star_color: Color = Color(0.85, 0.92, 1.3)
@export var star_min_radius: float = 1.2
@export var star_max_radius: float = 3.4

@export_group("Star")
@export var sun_center: Vector2 = Vector2(256.0, 680.0)
@export var sun_radius: float = 300.0
@export var sun_segments: int = 200
@export var sun_speed: float = 0.45
@export var sun_churn_scale: float = 0.15
@export var sun_drift_scale: float = 0.06
## Atmosphere under the blob, on top of whatever the glow pass spreads. This is
## what keeps the upper half from reading as dead black at grid size.
@export var halo_strength: float = 1.7
@export var halo_reach: float = 1.9

## Concentric circles the halo is built from. Has to be this many: a handful of
## wide steps reads as hard rings around the star rather than as falloff.
##
## Both halos are drawn geometry in the body's own colour, not glow-pass output,
## which is what makes them hue-matched to the body by construction rather than
## by tuning. That is why they carry most of the atmosphere here: the glow pass
## shifts hue towards whichever channel clears its threshold, and these cannot.
const HALO_STEPS := 28
## Per-ring alpha before the falloff weighting. They stack, so the visible
## opacity at the star's edge is roughly HALO_STEPS times this.
const HALO_STEP_ALPHA := 0.020

## PlasmaBlob.CHARACTER_BANDS without its outer corona -- body and core only,
## and used for both bodies here. That corona is one flat-alpha polygon: a soft
## rim on a 36px character, a hard-edged disc on a 300px star. Ramping it across
## a few more bands only trades one hard edge for three, so both bodies drop it
## entirely and get a drawn halo instead, which can afford as many steps as the
## falloff needs. Copied rather than shared so the icon can retune this without
## touching the table every character in the game draws from.
## The middle band is the icon's own addition. With only a body and a core, a
## body that no longer clips reads as a flat disc with a white hole punched in
## it -- the step from violet straight to blown white happens over one edge.
## This lifts the middle of that range part of the way, so the falloff from
## core to limb is a gradient rather than a boundary.
const PROMO_BANDS := [
	{"r": 1.00, "phase": 0.0, "tint": 1.0, "white": Color(0, 0, 0), "a": 1.00, "churn": 1.0, "drift": 0.0},
	{"r": 0.76, "phase": 1.3, "tint": 1.0, "white": Color(0.30, 0.25, 0.10), "a": 0.90, "churn": 1.7, "drift": 0.05},
	{"r": 0.50, "phase": 2.1, "tint": 1.0, "white": Color(1.3, 1.3, 1.0), "a": 0.95, "churn": 2.6, "drift": 0.12},
]

## The character's own atmosphere, same construction as the star's.
@export_group("Character Glow")
@export var char_halo_strength: float = 1.9
@export var char_halo_reach: float = 3.0
const CHAR_HALO_STEPS := 28
const CHAR_HALO_STEP_ALPHA := 0.020

## A bright line laid along the limb. The star is a flat fill against a dark
## sky, and at 48px a fill with no edge reads as a smudge -- this is what makes
## it read as the edge of something.
@export_group("Limb")
@export var limb_width: float = 7.0
@export var limb_alpha: float = 0.85

@export_group("Flight")
## Straight up: the icon is symmetrical about its centre line, which is what
## holds it together once it is 48px in a grid of other icons.
@export var char_peak_height: float = 170.0
@export var character_scale: float = 2.6
## The character draws 32 perimeter points in game, plenty at ~36px across and
## visibly faceted at this size -- the churn lands on a polygon, not a curve.
@export var character_segments: int = 120
@export var charge_time: float = 0.5
@export var rise_time: float = 0.9
@export var hold_time: float = 0.5
@export var fall_time: float = 0.7
## Where in that loop the harness freezes. Mid-climb rather than in the hold: at
## the hold the character is stationary, which empties the trail and flattens
## the squash-stretch -- the two things that make a still look like motion.
@export var pose_time: float = 1.10

@export_group("Eruption")
@export var eruption_lead: float = 0.35
@export var eruption_fade: float = 1.2
@export var eruption_size: float = 260.0
@export var eruption_spikes: int = 15
@export var eruption_spread: float = 2.6

@export_group("Flare Tail")
@export var tail_length: float = 210.0
@export var tail_width: float = 40.0

@onready var _sun: PlasmaBlob = $Sun
@onready var _player: Player = $Player

var _t: float = 0.0
var _launch: Vector2
var _head: Vector2
var _tail_fade: float = 0.0
var _posed: bool = false

## Parallel arrays, the same shape background_particles.gd keeps its field in --
## rolled once from `star_seed`, so the same seed always produces the same sky
## and a re-shot icon matches the last one.
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

## The icon should look like a fresh install, not like this machine's save. Set
## on the autoload's plain fields rather than through its setters, which would
## each call _save() and overwrite the real settings file.
func _apply_default_palette() -> void:
	Settings.glow_strength = Settings.GLOW_STRENGTH_DEFAULT
	Settings.player_color = character_color
	Settings.platform_color = Settings.PLATFORM_COLOR_DEFAULT
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
	_sun.bands = PROMO_BANDS
	# PlasmaBlob is bottom-anchored: its centre sits one radius above its
	# origin, so the origin goes a radius below the centre we want.
	_sun.global_position = sun_center + Vector2(0.0, sun_radius)

func _setup_character() -> void:
	_player.scale = Vector2(character_scale, character_scale)
	_player.visual.segments = character_segments
	_player.visual.bands = PROMO_BANDS
	# Position and velocity are hand-driven in _apply, same as intro.gd does --
	# physics would fight the manual writes. _process stays on: that is what
	# reads `velocity` into the squash-stretch.
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	# The trail is top_level, so it is not carried by the character's scale and
	# would otherwise shed pinpricks off a 4.8x body.
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
		_star_alpha.append(rng.randf_range(0.30, 0.95))

func cycle_time() -> float:
	return charge_time + rise_time + hold_time + fall_time

func _process(delta: float) -> void:
	_t = fmod(_t + delta, cycle_time())
	_apply(_t)
	if not _posed and _t >= pose_time:
		_posed = true
		pose_reached.emit()

## Height above the launch point at time `t`: 0 through the charge, up to
## char_peak_height by the end of the rise, held flat, then back to 0 by the end
## of the fall -- so the loop seams exactly at t=0/cycle_time().
func _rise(t: float) -> float:
	if t < charge_time:
		return 0.0
	if t < charge_time + rise_time:
		return char_peak_height * _smoothstep((t - charge_time) / rise_time)
	if t < charge_time + rise_time + hold_time:
		return char_peak_height
	return char_peak_height * (1.0 - _smoothstep((t - charge_time - rise_time - hold_time) / fall_time))

func _smoothstep(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)

func _apply(t: float) -> void:
	var previous := _player.global_position
	_head = _launch - Vector2(0.0, _rise(t))
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
## behind the star and the character -- which is the order it wants: sky,
## stars, halo, the limb line, then the eruption showing only where it clears
## the limb, then the tail running under the character.
func _draw() -> void:
	_draw_sky()
	_draw_stars()
	_draw_halo()
	_draw_limb()
	_draw_eruption()
	_draw_character_halo()
	_draw_tail()

func _draw_sky() -> void:
	var s := _frame_size()
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0.0), s, Vector2(0.0, s.y)]),
		PackedColorArray([sky_top, sky_top, sky_bottom, sky_bottom]))

func _draw_stars() -> void:
	for i in range(_star_pos.size()):
		var col := star_color
		col.a = _star_alpha[i]
		draw_circle(_star_pos[i], _star_radius[i], col)

func _draw_halo() -> void:
	if halo_strength <= 0.001:
		return
	var base := _sun.color
	# Widest first, so each ring stacks on the ones outside it and the
	# accumulated opacity curves up towards the star.
	for i in range(HALO_STEPS):
		var t := float(i) / float(HALO_STEPS - 1)
		var col := base * 0.9
		col.a = HALO_STEP_ALPHA * halo_strength * (0.25 + 0.75 * t)
		draw_circle(sun_center, lerpf(sun_radius * halo_reach, sun_radius, t), col)

## Sits just outside sun_radius, not inside it: this script draws behind its own
## children, so a ring within the star's radius is simply painted over by the
## star. Nudged out far enough to clear the churn, which pushes the blob's real
## edge a few pixels either side of sun_radius.
func _draw_limb() -> void:
	if limb_width <= 0.0:
		return
	var base := _sun.color
	var col := Color(base.r + 0.8, base.g + 0.8, base.b + 0.6, limb_alpha)
	draw_arc(sun_center, sun_radius + limb_width * 0.4, 0.0, TAU, 160, col, limb_width, true)

## Drawn after the eruption, so the spikes fade into the character rather than
## ending against its edge.
func _draw_character_halo() -> void:
	if not _player.visible or char_halo_strength <= 0.001:
		return
	var visual: PlasmaBlob = _player.visual
	var radius := visual.radius * character_scale
	# PlasmaBlob is bottom-anchored and sits at an offset inside the player, so
	# its centre is not the player's origin.
	var centre := _head + Vector2(0.0, (visual.position.y - visual.radius) * character_scale)
	var base := Settings.player_color
	for i in range(CHAR_HALO_STEPS):
		var t := float(i) / float(CHAR_HALO_STEPS - 1)
		var col := base * 0.9
		col.a = CHAR_HALO_STEP_ALPHA * char_halo_strength * (0.25 + 0.75 * t)
		draw_circle(centre, lerpf(radius * char_halo_reach, radius, t), col)

## The eruption the character is thrown out by.
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

	# Lifted just past white rather than far past it. The old constants were
	# sized against an HDR body colour; against a body that no longer clips they
	# turned the spikes into flat white shards with no hue left in them at all.
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
		_head + Vector2(-half, 0.0), _head + Vector2(half, 0.0), _head + back * length,
	]), PackedColorArray([outer]))
	var inner := Color(_sun.color.r + 0.9, _sun.color.g + 0.9, _sun.color.b + 0.7, 0.85 * _tail_fade)
	draw_polygon(PackedVector2Array([
		_head + Vector2(-half * 0.35, 0.0), _head + Vector2(half * 0.35, 0.0),
		_head + back * (length * 0.7),
	]), PackedColorArray([inner]))
