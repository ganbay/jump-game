extends Node2D

## A continuous spray of sparks radiating off the streak plate while a flare
## streak is showing. One persistent instance (see game.gd's _ready) rather
## than a node per landing: burst() just extends how long it keeps sparking,
## so back-to-back flares read as one unbroken spray instead of overlapping
## one-shot bursts, and it keeps going for as long as the plate itself is up.
##
## Each spark spawns at a random point across the plate and flies straight
## outward in a random direction, living just long enough to clear the plate
## before it winks out -- a radiating burst rather than embers falling, so it
## reads the same whether the plate is centred or pushed to the screen's left
## edge (see Settings.ScoreAlign).
##
## Genuinely bloomed, not faked: main.tscn's Environment sets
## background_canvas_max_layer to include $UI's layer, so WorldEnvironment's
## real Glow reaches this node the same as any world sprite -- no manual halo
## rings or additive material needed here.

## Set by game.gd on every punch -- the character's own (undarkened) colour,
## boosted a bit further. See game.gd's _spawn_streak_embers for why this
## can't be the plate's own darkened tint.
@export var color: Color = Color(1.0, 1.0, 1.0, 1.0)
## The plate's current size, so sparks spawn across the whole pill rather
## than from a single point.
@export var plate_size: Vector2 = Vector2(80.0, 40.0)
## Streak strength, already clamped to STREAK_SCALE_CAP by the caller -- more
## sparks, faster and bigger, the longer the streak runs.
@export var tier: int = 0:
	set(value):
		tier = value
		queue_redraw()

## Kept low: PARTICLE_LIFETIME below is long enough now that a high rate would
## pile up too many sparks alive at once. Fewer, slower, longer-lived reads
## calmer than a fast flurry that packs the same total sparks into less time.
const BASE_RATE := 5.0 ## sparks per second at tier 0
const RATE_PER_TIER := 2.5
const BASE_SPEED := 40.0
const SPEED_PER_TIER := 9.0
const BASE_RADIUS := 5.0
const RADIUS_PER_TIER := 0.8
## Long enough that a spark actually clears the plate before it fades, rather
## than dying while still over the background it spawned on.
const PARTICLE_LIFETIME := 0.9
## Floor for each spark's own random brightness (see Spark.base_alpha).
const MIN_ALPHA := 0.35

class Spark:
	var pos: Vector2
	var vel: Vector2
	var radius: float
	## Fixed per spark at spawn, on top of the fade curve -- a flat wash of
	## same-brightness dots reads as one field; each one guttering at its own
	## strength reads as fire.
	var base_alpha: float = 1.0
	var age: float = 0.0

var _sparks: Array[Spark] = []
var _spawn_accum: float = 0.0
## Counts down while sparks are still due; new ones stop spawning at zero but
## whatever is already in flight keeps fading out on its own.
var _emit_time_left: float = 0.0

func _ready() -> void:
	set_process(false)

## Called on every landing that extends the streak. Takes the *longest*
## outstanding request rather than resetting to it, so a burst already mid-
## flight is never cut short by a smaller one -- though in practice every
## caller passes the same show_time + fade_time span.
func burst(hold_seconds: float) -> void:
	_emit_time_left = maxf(_emit_time_left, hold_seconds)
	set_process(true)

func _process(delta: float) -> void:
	if _emit_time_left > 0.0:
		_emit_time_left = maxf(_emit_time_left - delta, 0.0)
		_spawn_accum += delta
		var interval := 1.0 / (BASE_RATE + RATE_PER_TIER * tier)
		while _spawn_accum >= interval:
			_spawn_accum -= interval
			_spawn_one()
	var i := _sparks.size() - 1
	while i >= 0:
		var spark: Spark = _sparks[i]
		spark.age += delta
		spark.pos += spark.vel * delta
		if spark.age >= PARTICLE_LIFETIME:
			_sparks.remove_at(i)
		i -= 1
	queue_redraw()
	# Idles instead of freeing itself: this node is reused for every flare in
	# the run (see game.gd's _ready), not spawned fresh per landing.
	if _emit_time_left <= 0.0 and _sparks.is_empty():
		set_process(false)

func _spawn_one() -> void:
	var speed := BASE_SPEED + SPEED_PER_TIER * tier
	var spark := Spark.new()
	spark.pos = Vector2(
		randf_range(-plate_size.x / 2.0, plate_size.x / 2.0),
		randf_range(-plate_size.y / 2.0, plate_size.y / 2.0))
	spark.vel = Vector2.RIGHT.rotated(randf_range(0.0, TAU)) * speed
	spark.radius = (BASE_RADIUS + RADIUS_PER_TIER * tier) * randf_range(0.75, 1.2)
	spark.base_alpha = randf_range(MIN_ALPHA, 1.0)
	_sparks.append(spark)

func _draw() -> void:
	for spark in _sparks:
		var t: float = spark.age / PARTICLE_LIFETIME
		# sqrt rather than squared: holds most of its brightness through the
		# middle of its life and only drops off sharply right at the end, so
		# it reads as travelling and then winking out, not as fading the
		# whole time it flies outward.
		var fade := sqrt(clampf(1.0 - t, 0.0, 1.0))
		var col := color
		col.a *= fade * spark.base_alpha
		draw_circle(spark.pos, spark.radius * fade, col)
