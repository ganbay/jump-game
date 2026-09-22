extends RefCounted
class_name ZoneAmbience

## The backdrop each zone climbs through: a background tint, a particle tint,
## and a way for the particle field to move. One entry per zone in
## ZoneDirector.Zone, plus the opening, which is the untinted baseline the game
## has always looked like.
##
## The tints are applied over the neutral white bases in Settings, which is what
## platform and drift colour are now that neither is a player setting. A zone
## multiplies its hue over that base rather than replacing it, so OPEN SPACE --
## which applies no tint -- shows the base as it is, white-ish.
##
## Each zone paints the backdrop as a vertical gradient (see
## shaders/zone_backdrop.gdshader): `bg_top` near-black at the top of the
## screen, `bg_bottom` the zone's colour pooled at the bottom, where the Sun the
## run is escaping still is.
##
## Even the bottom colours stay well under 1.0 on purpose. The platforms, the
## character and the particles are all HDR values above 1.0 and the scene is
## graded for them to bloom against a dark field; a backdrop that crossed the
## glow threshold would bloom too and flatten the whole image into one glare.
## Colour comes from saturation -- a gap between channels -- rather than from
## brightness, which is why these read as coloured at a fraction of the
## luminance the characters and platforms sit at.
##
## That gap has been tuned in both directions. Authored at roughly twice this
## saturation it read as noise rather than atmosphere; pulled down to half of
## it the screen went flat and grey. These sit between the two.

## Stage 0, before any zone is forced. A real profile, and a pickable sky.
const OPENING := -1
## Not a sky at all -- "nothing shown yet", for callers tracking what they last
## displayed. Distinct from OPENING precisely because OPENING is a valid choice:
## a caller starting out has shown nothing, which is not the same as having
## shown open space, and conflating them would bar the opening sky from ever
## being the first one picked.
const NONE := -2

## How a surface's hue relates to the zone's: its own, or the opposite side of
## the wheel. The platforms take whichever the player picked (see
## Settings.platform_complementary); the character always takes ZONE, because it
## belongs to the zone rather than contrasting it.
##
## ZONE platforms stay legible despite sharing the backdrop's hue because they
## do not share its brightness: PLATFORM_TINT keeps their peak channel near the
## neutral base at roughly 2.1, against a backdrop pooling at 0.27 at its very
## brightest. Separation comes from value, not from hue.
enum PaletteMode { ZONE, COMPLEMENT }
const HUE_SHIFT := {
	PaletteMode.ZONE: 0.0,
	PaletteMode.COMPLEMENT: 0.5,
}

## The silhouette a zone's particles are cut to. Every shape is built from the
## same vertex count as the round one (see BackgroundParticles.CIRCLE_SEGMENTS),
## which is what lets one shape morph into the next across a zone change instead
## of popping -- and lets all of them share the one index buffer the field is
## drawn from.
enum Shape {
	ROUND,   ## The baseline dot.
	LENS,    ## Pointed at both ends, so a stretched one reads as a streak.
	SHARD,   ## Five sharp spikes -- crystalline, brittle.
	BLOB,    ## An irregular round, for things that should look grown.
}

## How far a zone pulls the particle field toward its own colour. At 1.0 the
## field simply *is* the zone -- which it can be, now that drift colour is no
## longer a player setting and the base underneath it is neutral white (see
## Settings.PARTICLE_COLOR_NEUTRAL). OPEN SPACE keeps its own weight of 0, so
## the opening stretch drifts white.
##
## Was 0.7 while the colour was still the player's to pick.
const TINT_WEIGHT := 1.0

## How far each surface leans toward the zone's colour.
##
## Platforms take the zone's *complement* rather than the zone's own colour --
## the opposite side of the wheel, at the same saturation and brightness -- so a
## blue zone lays warm amber slabs and a rose zone lays mint ones.
##
## This is the readability argument, not a decorative one. The platforms are the
## one thing the player has to pick out of the scene in the fraction of a second
## before a landing, and a surface sharing the backdrop's hue is the hardest
## possible version of that. Putting them opposite the zone means the thing that
## must be read is the thing furthest from everything around it.
##
## The weight is high: at anything much lower the slabs wash out to off-white
## and the relationship stops being visible at all, which is the failure this
## setting kept landing in. It stops short of 1.0 so the brightest channel keeps
## a little neutral in it and the platforms still read as lit rather than as
## flat colour -- and, with contrast off, so that platforms sharing the zone's
## hue still sit a shade off it rather than exactly on it.
## In OPEN SPACE there is no tint and they show their neutral base.
##
## The character is left nearly alone: it is still the player's own Customize
## choice, and it is what their eye is locked to through every landing.
const PLATFORM_TINT := 0.85
const PLAYER_TINT := 0.12
## The banner names the zone, so it may as well be the colour of it. Safe to
## push hard: it is a caption that appears, says one thing and leaves.
const BANNER_TINT := 0.55
## The menu title. Pushed further still -- it is 128px of text on an otherwise
## near-black upper screen, with nothing near it to clash with.
const TITLE_TINT := 0.6

## Seconds to cross from one zone's backdrop to the next. Matched to the zone
## banner's entrance so the two read as one announcement.
const BLEND_TIME := 1.4

## Per-zone tuning. `speed`, `wobble_amp`, `wobble_freq`, `twinkle_freq` and
## `radius` multiply BackgroundParticles' own constants rather than replacing
## them, so retuning the field as a whole still works from that script.
##
## `flow` is how much of the field abandons its own random heading for the
## common one at `flow_deg` (0 = every particle keeps its own, 1 = the field
## moves as one current). `twinkle_floor` is the dimmest a particle gets: low
## values let it fade nearly out, high values keep it a steady point of light.
##
## The shape controls: `stretch` elongates the silhouette along its own long
## axis (1 = as drawn), `align` turns that axis to follow the particle's heading
## (1 = fully, which is what turns a stretched lens into a motion streak),
## `spin` is self-rotation in radians per second, and `pulse` is how far the
## silhouette squashes and stretches -- 0.45 meaning it swings between about
## 1.45x and 0.55x along one axis while the other takes up the slack.
const PROFILES := {
	OPENING: {
		# Flat black, both stops. The zones each pool a colour at the bottom of
		# the screen; the opening pools nothing, so the gradient collapses to
		# the plain black the game has always started on. It is also the only
		# backdrop with no hue to place the platforms against, which is why
		# they show their neutral base there untinted.
		"bg_top": Color(0.0, 0.0, 0.0),
		"bg_bottom": Color(0.0, 0.0, 0.0),
		# A placeholder. The opening's real colour is the character's, which is
		# chosen at runtime and so cannot live in a const table -- see
		# tint_of() and resolved_profile() below, which substitute it.
		"tint": Color(2.15, 2.08, 2.0), "tint_weight": TINT_WEIGHT,
		"speed": 1.0, "wobble_amp": 1.0, "wobble_freq": 1.0,
		"twinkle_freq": 1.0, "twinkle_floor": 0.35, "radius": 1.0,
		"flow": 0.0, "flow_deg": 90.0,
		"shape": Shape.ROUND, "stretch": 1.0, "align": 0.0,
		"spin": 0.0, "pulse": 0.0,
	},
	# DRIFT -- the platforms slide, so the sky does too. The fastest field by a
	# wide margin, and the only one that moves as a single current: everything
	# tears downward past the player as one, which reads as the climb having
	# pace of its own. Lens-shaped and stretched hard along its own heading, so
	# each particle is a motion streak rather than a dot that happens to move.
	ZoneDirector.Zone.MOVING: {
		"bg_top": Color(0.004, 0.012, 0.035),
		"bg_bottom": Color(0.025, 0.12, 0.27),
		"tint": Color(0.5, 1.75, 3.4), "tint_weight": TINT_WEIGHT,
		"speed": 3.4, "wobble_amp": 0.35, "wobble_freq": 0.7,
		"twinkle_freq": 0.8, "twinkle_floor": 0.5, "radius": 0.85,
		"flow": 0.95, "flow_deg": 76.0,
		"shape": Shape.LENS, "stretch": 3.4, "align": 1.0,
		"spin": 0.0, "pulse": 0.0,
	},
	# GLASS -- brittle and cold. All but frozen in place, spiked, turning almost
	# imperceptibly, and cutting in and out on a hard fast glint that reaches
	# zero: suspended shards catching light rather than drifting dust. The one
	# zone whose field is defined by what it does NOT do.
	#
	# Green rather than the cyan it started as, and not only to break up a
	# palette that had drifted blue. Real glass is green on the edge -- iron in
	# the sand -- and a thick pane seen end-on is the one place that colour
	# shows. It is the most recognisable thing glass does with light.
	ZoneDirector.Zone.GLASS: {
		"bg_top": Color(0.004, 0.022, 0.016),
		"bg_bottom": Color(0.03, 0.19, 0.115),
		"tint": Color(0.83, 2.95, 2.17), "tint_weight": TINT_WEIGHT,
		"speed": 0.22, "wobble_amp": 0.12, "wobble_freq": 0.5,
		"twinkle_freq": 3.4, "twinkle_floor": 0.0, "radius": 0.8,
		"flow": 0.0, "flow_deg": 90.0,
		"shape": Shape.SHARD, "stretch": 1.0, "align": 0.0,
		"spin": 0.35, "pulse": 0.0,
	},
	# PHANTOM -- the platforms are not there, and neither, quite, is the sky.
	# Huge soft shapes swinging on a wide slow arc and fading all the way out
	# and back: the field does the same disappearing act the platforms do, and
	# the sway is big enough that a particle's path stops looking like a line.
	ZoneDirector.Zone.INVISIBLE: {
		"bg_top": Color(0.02, 0.004, 0.035),
		"bg_bottom": Color(0.13, 0.03, 0.27),
		"tint": Color(1.75, 0.6, 3.4), "tint_weight": TINT_WEIGHT,
		"speed": 0.6, "wobble_amp": 3.6, "wobble_freq": 0.35,
		"twinkle_freq": 0.4, "twinkle_floor": 0.0, "radius": 2.1,
		"flow": 0.35, "flow_deg": 265.0,
		"shape": Shape.BLOB, "stretch": 1.0, "align": 0.0,
		"spin": 0.15, "pulse": 0.0,
	},
	# SQUISH -- elastic. Fat droplets squashing and stretching on a fast jitter,
	# which is what the platforms do underfoot. `pulse` is the zone's whole
	# character: the shape is round precisely so the deformation is the thing
	# that reads.
	ZoneDirector.Zone.SQUISHY: {
		"bg_top": Color(0.035, 0.004, 0.022),
		"bg_bottom": Color(0.26, 0.04, 0.145),
		"tint": Color(3.2, 0.65, 1.65), "tint_weight": TINT_WEIGHT,
		"speed": 1.35, "wobble_amp": 2.4, "wobble_freq": 3.4,
		"twinkle_freq": 1.6, "twinkle_floor": 0.55, "radius": 1.35,
		"flow": 0.0, "flow_deg": 90.0,
		"shape": Shape.ROUND, "stretch": 1.0, "align": 0.0,
		"spin": 0.0, "pulse": 0.45,
		# The one zone that pins its own platform hue instead of taking the
		# palette mode's step. A true complement of this rose is mint green,
		# and green is the one hue nothing else in the game wears -- the
		# character palette, the platforms, the drift and the other three
		# backdrops are all blues, violets and roses -- so complementary SQUISH
		# laid slabs that looked like they had wandered in from another game.
		#
		# A short step back instead, which keeps them unmistakably pink like the
		# zone while landing bluer than it. Only consulted in COMPLEMENT mode --
		# with contrast off the platforms take the zone's hue exactly, which for
		# this zone was already the pink that was wanted.
		"platform_hue": -1.0 / 24.0,
	},
}

static func profile(zone: int) -> Dictionary:
	return PROFILES.get(zone, PROFILES[OPENING])

## The colour a zone dresses its platforms and its drift in.
##
## Every zone's is fixed in the table; the opening's is the character's own.
## Open space has no zone identity to wear, so it wears the player's -- which
## is also what keeps Customize connected to a run now that platform and drift
## colour are no longer picked there directly. Their character sets the colour
## of the stretch before the zones take over, and each zone then paints over it.
##
## Taken through UiAccent so it inherits that script's readability floor: a
## colour too dim to carry a heading is also too dim to carry a platform.
static func tint_of(zone: int) -> Color:
	return UiAccent.color() if zone == OPENING else profile(zone)["tint"]

## A profile with anything that cannot be a constant filled in. Only the opening
## needs it, and only for its colour; everything else in the table is static.
static func resolved_profile(zone: int) -> Dictionary:
	var p: Dictionary = profile(zone).duplicate()
	if zone == OPENING:
		p["tint"] = tint_of(zone)
	return p

## Which zone's backdrop a stage wears. A stage forcing two or three zones at
## once has no single look to wear, so it borrows one of the zones it is
## actually made of -- picked fresh each stage, which keeps the back half of the
## run visually varied instead of parking on one combined palette.
##
## `avoid` is the previous stage's pick: dropped from the candidates whenever
## there is another to take, so consecutive stages never open with the backdrop
## already on screen and the change stays legible as a change.
static func pick_zone(mask: int, avoid: int = OPENING) -> int:
	if mask == 0:
		return OPENING
	var present: Array[int] = []
	for z in range(ZoneDirector.ZONE_COUNT):
		if mask & (1 << z):
			present.append(z)
	if present.size() > 1:
		present.erase(avoid)
	return present[randi() % present.size()]

## A `modulate` multiplier that leans whatever it is applied to toward this
## zone's colour: the zone tint normalised so its brightest channel is 1.0, then
## mixed back toward white by `weight`.
##
## Normalising first is what makes this a tint rather than a dimmer. A raw
## multiply by a colour with a dark channel darkens everything it touches, and
## the platforms cannot afford to lose brightness -- they have to stay readable
## against a backdrop that just got more colourful. This leaves the brightest
## channel untouched at every weight and only pulls the others down, so the
## surface shifts hue while holding its peak.
## The same colour turned `turns` around the wheel, keeping its saturation and
## brightness. Hue is scale-invariant and Color computes h/s/v from the raw
## channels, so this works directly on the HDR values the palette is authored
## in -- no tone-mapping down to 0..1 and back.
static func hue_rotated(c: Color, turns: float) -> Color:
	if is_zero_approx(turns):
		return c
	return Color.from_hsv(fposmod(c.h + turns, 1.0), c.s, c.v, c.a)

static func tint_modulate(zone: int, weight: float, mode: int = PaletteMode.ZONE) -> Color:
	var p: Dictionary = profile(zone)
	var shift: float = HUE_SHIFT[mode]
	if zone == OPENING:
		# The opening wears the character's colour, and wears it as it is. The
		# complement of the player's own pick is not their colour any more,
		# whichever way the contrast setting happens to be turned -- and there
		# is no backdrop hue out there to contrast against in the first place.
		shift = 0.0
	elif mode != PaletteMode.ZONE and p.has("platform_hue"):
		# A zone may pin the step its platforms take, overriding the player's
		# palette choice for that zone alone -- see SQUISH's "platform_hue".
		shift = p["platform_hue"]
	var t: Color = hue_rotated(tint_of(zone), shift)
	var peak := maxf(t.r, maxf(t.g, t.b))
	if peak <= 0.0:
		return Color.WHITE
	return Color.WHITE.lerp(Color(t.r / peak, t.g / peak, t.b / peak), weight)

## Blends a colour toward the zone's, for the places that set a colour outright
## rather than multiplying one (see game.gd's zone banner). Both sides are HDR
## values above 1.0, so the result stays bright enough to read as text.
static func tint_toward(base: Color, zone: int, weight: float) -> Color:
	if zone == OPENING:
		return base
	var out: Color = base.lerp(profile(zone)["tint"], weight)
	out.a = base.a
	return out

## Any sky at all, the opening included, for callers with no stage to derive one
## from -- the menu wears one without being in a run.
##
## Separate from pick_zone rather than a flag on it, because the two answer
## different questions. pick_zone must never return OPENING for a stage that has
## zones forced in it: that stage's platforms are glass or moving or blinking,
## and dressing it in the untinted opening sky would be a lie about what the
## player is climbing through. The menu is climbing through nothing, so every
## sky is honest there.
static func pick_any(avoid: int = NONE) -> int:
	var all: Array[int] = [OPENING]
	for z in range(ZoneDirector.ZONE_COUNT):
		all.append(z)
	# A no-op when nothing has been shown yet, which is what NONE is for.
	all.erase(avoid)
	return all[randi() % all.size()]
