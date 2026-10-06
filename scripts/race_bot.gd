extends Rival
class_name RaceBot

## The rival in race mode: a ghost that climbs the same course as the player,
## by the same rules, and aims to average Race.pace() score per second.
##
## It is not a second Player. Player reads the global input actions, and it
## lands on platform *nodes* -- which only exist near the camera, while the bot
## is routinely thousands of pixels above or below it. So the bot re-runs
## player.gd's movement against the spawner's course data instead (see
## PlatformSpawner.course / slot_position): the same gravity, jump and streak
## numbers, read off the real Player so a retune there carries over, and the
## same landing sweep. What it never does is touch the world: it claims its own
## flare boosts and breaks its own glass, so racing it changes nothing for the
## player.
##
## PACING. Every landing is a choice between a flare and a plain hop, and the
## choice is what holds the pace. The bot keeps a running "where I should be"
## (pace x time, wobbling slowly so it surges and sags rather than climbing like
## a metronome) and flares more the further behind that it is. A plain hop does
## not break a streak, so a bot that is ahead coasts on small jumps with its
## streak intact, and a bot that is behind cashes it in -- which is exactly
## "keep streaking or take a normal jump". Solar Wind is saved for when it is
## behind: it is worth several seconds of pace in one launch, and spending it
## while already ahead would make the bot lurch away and then idle.
##
## ITEMS. With item boxes on (see race_items.gd, which hands the bot its
## items and carries attacks both ways) the pace would undo every one of them:
## a bot knocked back just flares until it is on its number again, and one
## that rockets ahead coasts until the lead is gone. So while an item's effect
## runs -- its own Rocket or Spring Shoes, or a Comet or Reverse it took --
## the "where I should be" is carried along with where it actually is, and
## whatever the item gained or cost is still there when the effect ends. The
## bot then holds its pace from that new footing.
##
## A FIELD. In a race of more than two (Race.FIELD_SIZES) every bot is handed
## a persona before it starts -- see set_persona(). Left alone, bots launched
## from one point by one rule pick the same platforms and climb as a stack;
## the persona gives each its own pace, its own side of the course, its own
## taste in platforms and its own nerve, so they spread out and trade places.
## A lone bot has none, and climbs exactly as it always did.
##
## Steering and target picking are the trailer autopilot's (see
## trailer/trailer_autopilot.gd for the reasoning behind each piece), driving a
## steering axis here instead of the global input actions.

const REACH_SAFETY := 0.78
const STOP_EPS := 5.0
const MIN_CLIMB := 8.0
## How far below its best height the course index can drop before a slot can
## never matter again -- past the death line plus a vertical mover's swing.
const SLOT_TRAIL := 200.0
## Vertical movers swing this far either side of their slot's y, so every
## scan by slot y is widened by it.
const SLOT_SWING := 80.0
## Course data is generated this far above the bot's apex, so a fast rise
## never outruns it.
const COURSE_LOOKAHEAD := 600.0

## Seconds of lead (or deficit) against the target pace that swing the flare
## odds from even to almost certain. See _flare_odds().
const LEAD_RESPONSE := 0.3
const MIN_FLARE_ODDS := 0.03
const MAX_FLARE_ODDS := 0.98
## Lead beyond which it stops reaching for the highest platform in range and
## takes whichever is closest instead.
const LAZY_LEAD := 1.0
## Solar Wind is only triggered once it is at least this far behind.
const WIND_DEFICIT := 1.0
const WIND_HOLD_ODDS := 0.25
## The slow wobble on the target pace, as fractions of it. Two sines at
## unrelated rates, so the pattern does not visibly repeat within a race.
const MOOD_SLOW := 0.10
const MOOD_FAST := 0.05

## Same numbers as game.gd's revive, for the same reasons.
const REVIVE_LAUNCH_VELOCITY := -1500.0
const REVIVE_SPAWN_LIFT := 40.0
const REVIVE_SAFE_DROP := 240.0

## --- Personas (set_persona) ---
## The quickest bot of a field runs the picked AI's pace and the slowest this
## much under it, the rest evenly between.
const FIELD_PACE_SPREAD := 0.16
## Sideways gap between neighbours off the launch, fanned out either side of
## the player, and the furthest out any of them starts.
const START_GAP := 80.0
const START_MAX_SHIFT := 320.0
## What a platform's sideways distance costs when picking one, in pixels of
## height given up per pixel: from the bot itself (NEAR -- a bot that would
## rather hop than reach) and from its home lane (LANE). Each bot rolls its
## own between these.
const NEAR_BIAS_MIN := 0.0
const NEAR_BIAS_MAX := 0.45
const LANE_BIAS_MIN := 0.15
const LANE_BIAS_MAX := 0.5
## The home lane wanders this far either side of its centre, as a fraction of
## the course width, so a bot is not pinned to one column all race.
const LANE_WANDER := 0.16
## What a platform costs for each other bot of the field already headed for
## it, in pixels of height; each bot rolls its own between these. The course
## is one platform to a row, so "the highest in reach" is the same platform
## for everybody on the same arc -- most of all off the launch, where only a
## few rows are in reach at all. This is what sends them to different ones.
const CROWD_COST_MIN := 110.0
const CROWD_COST_MAX := 260.0
## The furthest off a platform's centre a bot aims, as a fraction of its half
## width -- inside the edge, so a slightly late arrival still lands.
const AIM_LIMIT := 0.7
## A bot gliding rather than darting still moves this much faster than it
## strictly needs to arrive, to cover the time it takes to get up to speed.
const DRIVE_MARGIN := 1.3
## A bot falling behind its pace lets go of its tastes: all there up to
## TASTE_SLACK seconds behind, gone by TASTE_GIVE_UP, when it takes the
## highest platform it can reach as a lone bot always does -- so a persona can
## colour how it climbs without costing it the pace.
const TASTE_SLACK := 0.5
const TASTE_GIVE_UP := 2.0
## Every bot starts seconds behind: the clock runs from the hand-off, and
## score only from the top of the launch. That opening deficit is not a
## reason to climb plainly -- it is where the field most needs to split up --
## so tastes stay whole until the bot is first back on its pace, or this long.
const OPENING_GRACE := 20.0

## How long after getting an item the bot uses it, picked between these. An
## attack waits past it for the player to be ahead.
const ITEM_USE_MIN := 0.8
const ITEM_USE_MAX := 3.5

## The bot wants to throw `kind` (a RaceItems.Item attack) at the player.
signal attack_requested(kind: int)

var streak: int = 0
## Its id in the item feed and warnings (see RaceItems.BOT_ID): -1 down.
var bot_id: int = -1
## The ghost's silhouette, or -1 to pick the one least like the player's.
var shape: int = -1
## The item in its slot (a RaceItems.Item), and the best score among the
## racers it could throw at, for deciding when an attack can be thrown. Both
## kept by RaceItems.
var held: int = RaceItems.Item.NONE
var ahead_score: int = 0
var shield_left: float = 0.0
var stun_left: float = 0.0
var reverse_left: float = 0.0

var _spawner: Node2D
var _active: bool = false
var _elapsed: float = 0.0
## Where the pace says it should be by now, in score.
var _expected: float = 0.0
var _pace: float = 70.0
var _fumble: float = 0.08
var _mood_phase: Vector2 = Vector2.ZERO
# The persona. These defaults are a lone bot's, and the numbers it has always
# climbed by.
var _pace_mult: float = 1.0
var _fumble_mult: float = 1.0
var _lead_response: float = LEAD_RESPONSE
var _reach_safety: float = REACH_SAFETY
var _wind_deficit: float = WIND_DEFICIT
var _mood_slow: float = MOOD_SLOW
var _mood_fast: float = MOOD_FAST
var _mood_rate: Vector2 = Vector2(0.13, 0.41)
var _near_bias: float = 0.0
var _lane_bias: float = 0.0
var _lane_home: float = 0.5
var _lane_rate: float = 0.0
var _lane_phase: float = 0.0
var _start_shift: float = 0.0
var _crowd_cost: float = 0.0
## Where on a platform it lands: how far toward the side it arrives from,
## and how much it scatters, both as fractions of the half width.
var _edge_lean: float = 0.0
var _aim_spread: float = 0.0
## How it gets there: the longest it takes to start steering after a landing,
## and how much of its speed it uses when there is time to spare.
var _reaction: float = 0.0
var _drive: float = 1.0
## The rest of the field, itself included, for telling where they are headed.
var field: Array[RaceBot] = []
# Rolled afresh for each hop (see _roll_hop and _roll_aim).
var _hop_wait: float = 0.0
var _hop_drive: float = 1.0
var _aim_for: int = -1
var _aim_offset: float = 0.0
## How much of its tastes it is acting on right now, 0 to 1 (TASTE_GIVE_UP).
var _taste: float = 0.0
## Whether the opening deficit has been made up yet (see OPENING_GRACE).
var _settled: bool = false
var _lazy: bool = false
var _use_in: float = 0.0
var _rocket_left: float = 0.0
var _auto_boosts: int = 0
## True while an item's effect runs, and the lead it started at -- see ITEMS.
var _in_effect: bool = false
var _effect_lead: float = 0.0
var _status_shown: bool = false
## Highest point reached, as a feet y. The bot's camera, in effect: its score
## and its death line are both measured from here, as the player's are.
var _best_y: float = 0.0
var _death_margin: float = 720.0
var _width: float = 720.0
var _feet_offset: float = 17.0
var _low: int = 0
var _target: int = -1
var _last_slot: int = -1
var _claimed: Dictionary = {}
var _broken: Dictionary = {}

# Copied off the Player in begin().
var _gravity: float
var _jump_velocity: float
var _boost_jump_velocity: float
var _streak_jump_step: float
var _streak_jump_cap: int
var _streak_fall_step: float
var _streak_fall_cap: int
var _streak_fall_step_late: float
var _key_accel: float
var _base_move_speed: float
var _move_speed: float
var _wind_duration: float
var _wind_speed_mult: float
var _wind_launch_mult: float
var _wind_left: float = 0.0

func _ready() -> void:
	super()
	set_physics_process(false)

## Makes this bot one of a field: number `index` of `count`, and the
## `pace_rank`-th quickest of them (0 is the one running the AI's own pace).
## Called before begin(). Everything here is rolled per race, so the same name
## is not the same racer twice.
func set_persona(index: int, count: int, pace_rank: int) -> void:
	_pace_mult = 1.0 - FIELD_PACE_SPREAD * float(pace_rank) / float(maxi(count - 1, 1))
	# Nerve: how sloppy its timing is, how hard it chases a deficit, how far
	# it will reach for a platform, how long it sits on a Solar Wind.
	_fumble_mult = randf_range(0.7, 1.6)
	_lead_response = randf_range(0.2, 0.45)
	_reach_safety = randf_range(0.66, 0.82)
	_wind_deficit = randf_range(0.3, 1.6)
	# Rhythm: how big its surges are and how fast they come round.
	_mood_slow = MOOD_SLOW * randf_range(0.6, 1.8)
	_mood_fast = MOOD_FAST * randf_range(0.6, 1.8)
	_mood_rate = Vector2(randf_range(0.09, 0.19), randf_range(0.3, 0.55))
	# Route: its own lane across the course, and how much it cares.
	_near_bias = randf_range(NEAR_BIAS_MIN, NEAR_BIAS_MAX)
	_lane_bias = randf_range(LANE_BIAS_MIN, LANE_BIAS_MAX)
	_lane_home = (float(index) + 0.5) / float(count)
	_lane_rate = randf_range(0.05, 0.12)
	_lane_phase = randf() * TAU
	_crowd_cost = randf_range(CROWD_COST_MIN, CROWD_COST_MAX)
	# Touch: where on a platform it puts down, and how it moves across to it
	# -- a quick dart and a wait, or a slow glide that arrives just in time.
	_edge_lean = randf_range(0.0, 0.5)
	_aim_spread = randf_range(0.15, 0.5)
	_reaction = randf_range(0.04, 0.22)
	_drive = randf_range(0.55, 1.0)
	_hop_drive = _drive
	# They do not all move off the launch on the same frame, either.
	_hop_wait = randf_range(0.0, 0.35)
	# Off the line: -1, +1, -2, +2 ... gaps either side of the player.
	var step := floorf(float(index) / 2.0) + 1.0
	var gap := minf(START_GAP, START_MAX_SHIFT / ceilf(float(count) / 2.0))
	_start_shift = step * gap * (-1.0 if index % 2 == 0 else 1.0)

## Starts the bot on the player's own launch, from the same point at the same
## speed, so the two leave the intro side by side.
func begin(spawner: Node2D, player: Player, death_margin: float) -> void:
	_spawner = spawner
	_death_margin = death_margin
	_width = get_viewport_rect().size.x
	_pace = Race.pace() * _pace_mult
	_fumble = Race.fumble_rate() * _fumble_mult
	_mood_phase = Vector2(randf() * TAU, randf() * TAU)
	_gravity = player.gravity
	_jump_velocity = player.jump_velocity
	_boost_jump_velocity = player.boost_jump_velocity
	_streak_jump_step = player.streak_jump_step
	_streak_jump_cap = player.streak_jump_cap
	_streak_fall_step = player.streak_fall_step
	_streak_fall_cap = player.streak_fall_cap
	_streak_fall_step_late = player.streak_fall_step_late
	_key_accel = player.key_accel
	_base_move_speed = player.move_speed
	_move_speed = _base_move_speed
	_wind_duration = player.solar_wind_duration
	_wind_speed_mult = player.solar_wind_speed_mult
	_wind_launch_mult = player.solar_wind_launch_mult
	_feet_offset = player.feet.position.y
	global_position = player.feet.global_position
	global_position.x = wrapf(global_position.x + _start_shift, 0.0, _width)
	velocity = player.velocity
	_best_y = global_position.y
	show_ghost(_rival_shape())
	_active = true
	set_physics_process(true)

func stop() -> void:
	_active = false
	set_physics_process(false)

## Over the line: out of the race, and off the course.
func finish() -> void:
	finished = true
	respawn_left = 0.0
	visible = false
	stop()

## A silhouette unlike the player's, even at 18px with the plasma churning
## its edge: a five-point star is spiky where every other skin is round or
## flat-sided, and the square answers the two star skins. (Diamond used to be
## the pick, and churned into something close to the default round cell.)
func _rival_shape() -> PlasmaBlob.Shape:
	if shape >= 0:
		return shape as PlasmaBlob.Shape
	var mine: PlasmaBlob.Shape = Player.SKIN_SHAPES.get(
		Settings.active_player_skin(), PlasmaBlob.Shape.CIRCLE)
	if mine == PlasmaBlob.Shape.STAR or mine == PlasmaBlob.Shape.SPARKLE:
		return PlasmaBlob.Shape.SQUARE
	return PlasmaBlob.Shape.STAR

func _physics_process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	_expected += _pace * _mood() * delta
	_update_items(delta)
	if respawn_left > 0.0:
		respawn_left -= delta
		if respawn_left <= 0.0:
			_respawn()
		return
	_update_wind(delta)
	_hop_wait = maxf(_hop_wait - delta, 0.0)
	_spawner.ensure_course(_apex_y() - COURSE_LOOKAHEAD)
	_advance_low()
	var axis := _steer_axis()
	# A Comet takes the steering away; a Reverse swaps it, as on a player.
	if stun_left > 0.0:
		axis = 0.0
	elif reverse_left > 0.0:
		axis = -axis

	var g := _gravity / _fall_multiplier() if velocity.y >= 0.0 else _gravity
	velocity.y += g * delta
	if _rocket_left > 0.0:
		velocity.y = -RaceItems.ROCKET_SPEED
	if axis != 0.0:
		velocity.x = move_toward(velocity.x, axis * _move_speed, _key_accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, _move_speed * 4.0 * delta)
	var prev_y := global_position.y
	global_position += velocity * delta
	if global_position.x < 0.0:
		global_position.x = _width
	elif global_position.x > _width:
		global_position.x = 0.0
	if velocity.y > 0.0:
		_check_landing(prev_y, global_position.y)

	_best_y = minf(_best_y, global_position.y)
	score = int(maxf(_spawner.score_origin_y - (_best_y - _feet_offset), 0.0) / 10.0)
	if global_position.y > _best_y + _death_margin:
		_fall()

# --- Items ----------------------------------------------------------------

## Into the slot, to be used after a moment -- a person looks at what they
## got before pressing it.
func give_item(item: int) -> void:
	held = item
	_use_in = randf_range(ITEM_USE_MIN, ITEM_USE_MAX)

## An attack landing. Returns whether a raised Shield blocked it.
func take_attack(kind: int) -> bool:
	if shield_left > 0.0:
		shield_left = 0.0
		return true
	match kind:
		RaceItems.Item.COMET:
			velocity.y = maxf(velocity.y, 0.0)
			_rocket_left = 0.0
			stun_left = RaceItems.COMET_STUN
		RaceItems.Item.REVERSE:
			reverse_left = RaceItems.REVERSE_TIME
		RaceItems.Item.SHOCKWAVE:
			velocity.y = maxf(velocity.y, 0.0)
			_rocket_left = 0.0
			stun_left = maxf(stun_left, RaceItems.SHOCK_STUN)
	return false

func _update_items(delta: float) -> void:
	shield_left = maxf(shield_left - delta, 0.0)
	stun_left = maxf(stun_left - delta, 0.0)
	reverse_left = maxf(reverse_left - delta, 0.0)
	_rocket_left = maxf(_rocket_left - delta, 0.0)
	if held != RaceItems.Item.NONE and respawn_left <= 0.0:
		_use_in -= delta
		if _use_in <= 0.0:
			_use_item()
	var effect := stun_left > 0.0 or reverse_left > 0.0 or _rocket_left > 0.0 \
		or _auto_boosts > 0
	if effect and not _in_effect:
		_effect_lead = float(score) - _expected
	_in_effect = effect
	if _in_effect:
		_expected = float(score) - _effect_lead
	# One redraw past the end of it, so the last status is wiped off the ghost.
	var status := shield_left > 0.0 or stun_left > 0.0 or reverse_left > 0.0
	if status or _status_shown:
		queue_redraw()
	_status_shown = status

func _use_item() -> void:
	match held:
		RaceItems.Item.ROCKET:
			_rocket_left = RaceItems.ROCKET_TIME
		RaceItems.Item.SPRING:
			_auto_boosts += RaceItems.SPRING_LANDINGS
		RaceItems.Item.SHIELD:
			# As for the player: also clears what has already landed.
			shield_left = RaceItems.SHIELD_TIME
			stun_left = 0.0
			reverse_left = 0.0
		RaceItems.Item.COMET, RaceItems.Item.REVERSE, RaceItems.Item.SHOCKWAVE:
			# Attacks only go forward: kept until somebody is ahead.
			if ahead_score <= score:
				return
			attack_requested.emit(held)
	held = RaceItems.Item.NONE

## The label, then whatever an item has put on the ghost.
func _draw() -> void:
	super()
	RaceItems.draw_status(self, Vector2(0.0, -18.0), shield_left > 0.0, stun_left > 0.0,
		reverse_left > 0.0, _elapsed, shield_left)

## Slow drift around 1.0, averaging out to it over a race.
func _mood() -> float:
	return 1.0 + _mood_slow * sin(_elapsed * _mood_rate.x + _mood_phase.x) \
		+ _mood_fast * sin(_elapsed * _mood_rate.y + _mood_phase.y)

## Seconds ahead of the pace (negative when behind).
func _lead_seconds() -> float:
	return (float(score) - _expected) / _pace

func _fall_multiplier() -> float:
	var capped := mini(streak, _streak_fall_cap)
	var extra := maxi(streak - _streak_fall_cap, 0)
	return pow(_streak_fall_step, capped) * pow(_streak_fall_step_late, extra)

func _apex_y() -> float:
	if velocity.y >= 0.0:
		return global_position.y
	return global_position.y - velocity.y * velocity.y / (2.0 * _gravity)

## Nothing below the death line can be landed on again, so the scans start
## above it.
func _advance_low() -> void:
	var course: Array = _spawner.course
	var floor_y := _best_y + _death_margin + SLOT_TRAIL
	while _low < course.size() - 1 and course[_low].y > floor_y:
		_low += 1

# --- Steering -------------------------------------------------------------

func _steer_axis() -> float:
	var lead := _lead_seconds()
	_lazy = lead > LAZY_LEAD
	_settled = _settled or lead >= 0.0 or _elapsed > OPENING_GRACE
	_taste = 1.0 if not _settled else clampf(
		(lead + TASTE_GIVE_UP) / (TASTE_GIVE_UP - TASTE_SLACK), 0.0, 1.0)
	var picked := _pick_target()
	if picked >= 0:
		_target = picked
	if _target < 0 or _target >= _spawner.course.size():
		return 0.0
	var eta := _time_to_reach(_spawner.course[_target].y)
	var goal: Vector2 = _spawner.slot_position(_spawner.course[_target], _spawner.course_time + eta)
	# One of a field puts down where it means to, not dead centre, and takes
	# a moment after each landing before it starts across.
	if _target != _aim_for:
		_roll_aim(goal.x)
	goal.x += _aim_offset
	if _hop_wait > 0.0:
		return 0.0
	# Steered on where the bot would coast to if it let go now, not on where
	# it is -- see trailer_autopilot.gd:_steer.
	var dx := _wrapped_dx(global_position.x, goal.x)
	var vx := velocity.x
	var coast := signf(vx) * (vx * vx) / (2.0 * _move_speed * 4.0)
	var error := dx - coast
	if absf(error) <= STOP_EPS:
		return 0.0
	# Flat out, unless this hop is a glide: then no faster than its drive, or
	# than arriving on time takes, whichever is more.
	var throttle := 1.0
	if _hop_drive < 1.0:
		var needed := absf(error) / maxf(eta, 0.05) / _move_speed * DRIVE_MARGIN
		throttle = clampf(maxf(_hop_drive, needed), 0.0, 1.0)
	return throttle if error > 0.0 else -throttle

## Picks the spot on the platform just targeted: leaning to the side the bot
## comes from, as a player who stops steering early lands, plus its scatter.
func _roll_aim(goal_x: float) -> void:
	_aim_for = _target
	_aim_offset = 0.0
	if _aim_spread <= 0.0:
		return
	var half: float = _spawner.course[_target].width / 2.0
	var side := signf(_wrapped_dx(goal_x, global_position.x))
	_aim_offset = half * clampf(side * _edge_lean + randf_range(-1.0, 1.0) * _aim_spread,
		-AIM_LIMIT, AIM_LIMIT)

## How the next hop is moved: rolled around the bot's own habits at each
## landing, and dropped with the rest of its tastes while it is behind.
func _roll_hop() -> void:
	if _reaction <= 0.0:
		return
	_hop_wait = randf_range(0.0, _reaction) * _taste
	_hop_drive = lerpf(1.0, clampf(_drive + randf_range(-0.15, 0.15), 0.45, 1.0), _taste)

## Seconds until the feet, on the current arc, fall back to `py`.
func _time_to_reach(py: float) -> float:
	var vy := velocity.y
	var g_fall := _gravity / _fall_multiplier()
	if vy >= 0.0:
		return _descent_time(maxf(py - global_position.y, 0.0), vy, g_fall)
	var rise_time := -vy / _gravity
	var ceiling := global_position.y - (vy * vy) / (2.0 * _gravity)
	return rise_time + sqrt(2.0 * maxf(py - ceiling, 0.0) / g_fall)

func _descent_time(distance: float, vy: float, g_fall: float) -> float:
	return (-vy + sqrt(vy * vy + 2.0 * g_fall * distance)) / g_fall

## The highest platform this arc can still fall onto and reach sideways in
## time -- or, while comfortably ahead, the nearest one, which is how a player
## who is not pushing climbs. Falls back to the least-unreachable one so a
## hopeless frame still steers somewhere useful.
##
## One of a field ranks "highest" by its own tastes: every pixel a platform
## is off to the side, or off its lane, counts as some height given up (see
## NEAR_BIAS_MIN). Two bots on the same arc then want different platforms.
func _pick_target() -> int:
	var course: Array = _spawner.course
	var now: float = _spawner.course_time
	var feet_y := global_position.y
	var ceiling := _apex_y()
	var best := -1
	var best_score := INF
	var near_cost := _near_bias * _taste
	var lane_cost := _lane_bias * _taste
	var lane_x := _lane_x()
	# How many of the others are headed for each platform.
	var crowd := {}
	var crowd_cost := _crowd_cost * _taste
	if crowd_cost > 0.0:
		for other in field:
			if other != self and other._target >= 0 and not other.finished \
					and not other.is_respawning():
				crowd[other._target] = crowd.get(other._target, 0) + 1
	var nearest := -1
	var nearest_cost := INF
	for i in range(_low, course.size()):
		if _broken.has(i):
			continue
		var slot = course[i]
		if slot.y < ceiling - SLOT_SWING:
			break
		var py: float = _spawner.slot_position(slot, now).y
		if py <= ceiling + MIN_CLIMB:
			continue
		if velocity.y >= 0.0 and py <= feet_y + MIN_CLIMB:
			continue
		var time_left := _time_to_reach(py)
		var px: float = _spawner.slot_position(slot, now + time_left).x
		var dx := absf(_wrapped_dx(global_position.x, px))
		var reach := _move_speed * time_left * _reach_safety
		if dx <= reach:
			var rank := dx
			if not _lazy:
				rank = py + dx * near_cost
				if lane_cost > 0.0:
					rank += absf(_wrapped_dx(lane_x, px)) * lane_cost
			if not crowd.is_empty():
				rank += float(crowd.get(i, 0)) * crowd_cost
			if rank < best_score:
				best_score = rank
				best = i
		elif dx - reach < nearest_cost:
			nearest_cost = dx - reach
			nearest = i
	return best if best >= 0 else nearest

## Where its lane is right now: the home column, wandering slowly.
func _lane_x() -> float:
	var at := _lane_home + LANE_WANDER * sin(_elapsed * _lane_rate + _lane_phase)
	return fposmod(at, 1.0) * _width

func _wrapped_dx(from_x: float, to_x: float) -> float:
	var d := to_x - from_x
	if d > _width * 0.5:
		d -= _width
	elif d < -_width * 0.5:
		d += _width
	return d

# --- Landing --------------------------------------------------------------

## player.gd:_check_landing, against slots instead of nodes.
func _check_landing(prev_y: float, new_y: float) -> void:
	var band := Player.FEET_HALF_HEIGHT + Player.PLATFORM_HALF_HEIGHT
	var course: Array = _spawner.course
	var now: float = _spawner.course_time
	var best := -1
	var best_pos := Vector2.ZERO
	for i in range(_low, course.size()):
		var slot = course[i]
		if slot.y < prev_y - band - SLOT_SWING:
			break
		if _broken.has(i):
			continue
		var pos: Vector2 = _spawner.slot_position(slot, now)
		if pos.y < prev_y - band or pos.y > new_y + band:
			continue
		if absf(global_position.x - pos.x) > slot.width / 2.0 + Player.FEET_HALF_WIDTH:
			continue
		if best < 0 or pos.y < best_pos.y:
			best = i
			best_pos = pos
	if best >= 0:
		_land(best, best_pos)

## player.gd:_land_on, with the tap decided by the pace instead of a finger.
func _land(index: int, pos: Vector2) -> void:
	var slot = _spawner.course[index]
	global_position.y = pos.y - Player.PLATFORM_HALF_HEIGHT
	# Spring Shoes: the next few landings flare themselves, and launch harder.
	var sprung := _auto_boosts > 0 and not _claimed.has(index)
	if sprung:
		_auto_boosts -= 1
	var attempt := sprung or randf() < _flare_odds()
	var is_timed := sprung or (attempt and randf() >= _fumble)
	var boosted := is_timed and not _claimed.has(index)
	if boosted:
		streak += 1
		best_streak = maxi(best_streak, streak)
		_claimed[index] = true
	elif attempt and not is_timed:
		streak = 0
	velocity.y = _boosted_jump_velocity() if boosted else _jump_velocity
	if sprung:
		velocity.y *= RaceItems.SPRING_JUMP_MULT
	if slot.has_attr(Platform.Attr.SQUISHY):
		velocity.y *= Platform.SQUISH_BOOST if is_timed else Platform.SQUISH_PENALTY
	if slot.has_attr(Platform.Attr.GLASS):
		_broken[index] = true
	if boosted and streak > 0 and streak % 10 == 0:
		_enter_wind()
	_last_slot = index
	_target = -1
	_roll_hop()
	squash(1.3 if boosted else 1.0)

## Even odds when on pace, climbing toward certain the further behind it is.
func _flare_odds() -> float:
	var lead := _lead_seconds()
	var odds := clampf(0.5 - lead * _lead_response, MIN_FLARE_ODDS, MAX_FLARE_ODDS)
	# The next flare would be a Solar Wind -- hold it back unless it is needed.
	if streak % 10 == 9 and lead > -_wind_deficit:
		odds *= WIND_HOLD_ODDS
	return odds

func _boosted_jump_velocity() -> float:
	return _boost_jump_velocity * (1.0 + _streak_jump_step * clampi(streak, 0, _streak_jump_cap))

func _enter_wind() -> void:
	velocity.y *= _wind_launch_mult
	_wind_left = _wind_duration
	_move_speed = _base_move_speed * _wind_speed_mult

func _update_wind(delta: float) -> void:
	if _wind_left <= 0.0:
		return
	_wind_left -= delta
	if _wind_left <= 0.0:
		_move_speed = _base_move_speed

# --- Falling --------------------------------------------------------------

func _fall() -> void:
	falls += 1
	respawn_left = Race.RESPAWN_PENALTY
	# The penalty is the price of the fall; a stun does not outlast it.
	stun_left = 0.0
	_rocket_left = 0.0
	streak = 0
	velocity = Vector2.ZERO
	_wind_left = 0.0
	_move_speed = _base_move_speed
	_target = -1
	visible = false

## game.gd:_revive_position, for the bot's own "camera".
func _respawn() -> void:
	respawn_left = 0.0
	var spot := Vector2(_width / 2.0, _best_y + REVIVE_SAFE_DROP)
	if _last_slot >= 0:
		var from_slot: Vector2 = _spawner.slot_position(
			_spawner.course[_last_slot], _spawner.course_time)
		from_slot.y -= Player.PLATFORM_HALF_HEIGHT + REVIVE_SPAWN_LIFT
		if from_slot.y < _best_y + REVIVE_SAFE_DROP:
			spot = from_slot
	global_position = spot
	velocity = Vector2(0.0, REVIVE_LAUNCH_VELOCITY)
	visible = true
