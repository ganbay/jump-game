extends Node2D
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

## Translucent enough to read as a ghost, solid enough to keep its colour.
const GHOST_ALPHA := 0.75
## The character's bands with the white-hot core toned down: that core is what
## makes every skin read as a white dot at a glance, so on the AI it is kept
## faint and the rival colour carries the body.
const GHOST_CORE_WHITE := Color(0.35, 0.35, 0.3)
const LABEL_FONT := preload("res://fonts/Chillax-Bold.otf")
const LABEL_SIZE := 18
const LABEL_LIFT := 52.0
## Off-screen margin inside which the body is still drawn.
const DRAW_MARGIN := 120.0

var velocity: Vector2 = Vector2.ZERO
var streak: int = 0
var score: int = 0
## Seconds left sitting out a fall, or 0 while racing.
var respawn_left: float = 0.0
var color: Color = Color.WHITE

var _spawner: Node2D
var _active: bool = false
var _elapsed: float = 0.0
## Where the pace says it should be by now, in score.
var _expected: float = 0.0
var _pace: float = 70.0
var _fumble: float = 0.08
var _mood_phase: Vector2 = Vector2.ZERO
var _lazy: bool = false
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
var _squash: float = 0.0
var _squash_vel: float = 0.0

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

var _visual: PlasmaBlob

func _ready() -> void:
	z_index = 9
	modulate.a = GHOST_ALPHA
	_visual = PlasmaBlob.new()
	var bands: Array = PlasmaBlob.CHARACTER_BANDS.duplicate(true)
	bands[bands.size() - 1]["white"] = GHOST_CORE_WHITE
	_visual.bands = bands
	add_child(_visual)
	visible = false
	set_physics_process(false)
	set_process(false)

## Starts the bot on the player's own launch, from the same point at the same
## speed, so the two leave the intro side by side.
func begin(spawner: Node2D, player: Player, death_margin: float) -> void:
	_spawner = spawner
	_death_margin = death_margin
	_width = get_viewport_rect().size.x
	_pace = Race.pace()
	_fumble = Race.fumble_rate()
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
	velocity = player.velocity
	_best_y = global_position.y
	_visual.color = color
	_visual.shape = _rival_shape()
	_active = true
	visible = true
	set_physics_process(true)
	set_process(true)
	queue_redraw()

func stop() -> void:
	_active = false
	set_physics_process(false)

func is_respawning() -> bool:
	return respawn_left > 0.0

## A silhouette unlike the player's, even at 18px with the plasma churning
## its edge: a five-point star is spiky where every other skin is round or
## flat-sided, and the square answers the two star skins. (Diamond used to be
## the pick, and churned into something close to the default round cell.)
func _rival_shape() -> PlasmaBlob.Shape:
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
	if respawn_left > 0.0:
		respawn_left -= delta
		if respawn_left <= 0.0:
			_respawn()
		return
	_update_wind(delta)
	_spawner.ensure_course(_apex_y() - COURSE_LOOKAHEAD)
	_advance_low()
	var axis := _steer_axis()

	var g := _gravity / _fall_multiplier() if velocity.y >= 0.0 else _gravity
	velocity.y += g * delta
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

## Slow drift around 1.0, averaging out to it over a race.
func _mood() -> float:
	return 1.0 + MOOD_SLOW * sin(_elapsed * 0.13 + _mood_phase.x) \
		+ MOOD_FAST * sin(_elapsed * 0.41 + _mood_phase.y)

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
	_lazy = _lead_seconds() > LAZY_LEAD
	var picked := _pick_target()
	if picked >= 0:
		_target = picked
	if _target < 0 or _target >= _spawner.course.size():
		return 0.0
	var eta := _time_to_reach(_spawner.course[_target].y)
	var goal: Vector2 = _spawner.slot_position(_spawner.course[_target], _spawner.course_time + eta)
	# Steered on where the bot would coast to if it let go now, not on where
	# it is -- see trailer_autopilot.gd:_steer.
	var dx := _wrapped_dx(global_position.x, goal.x)
	var vx := velocity.x
	var coast := signf(vx) * (vx * vx) / (2.0 * _move_speed * 4.0)
	var error := dx - coast
	if absf(error) <= STOP_EPS:
		return 0.0
	return 1.0 if error > 0.0 else -1.0

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
func _pick_target() -> int:
	var course: Array = _spawner.course
	var now: float = _spawner.course_time
	var feet_y := global_position.y
	var ceiling := _apex_y()
	var best := -1
	var best_score := INF
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
		var reach := _move_speed * time_left * REACH_SAFETY
		if dx <= reach:
			var rank := dx if _lazy else py
			if rank < best_score:
				best_score = rank
				best = i
		elif dx - reach < nearest_cost:
			nearest_cost = dx - reach
			nearest = i
	return best if best >= 0 else nearest

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
	var attempt := randf() < _flare_odds()
	var is_timed := attempt and randf() >= _fumble
	var boosted := is_timed and not _claimed.has(index)
	if boosted:
		streak += 1
		_claimed[index] = true
	elif attempt and not is_timed:
		streak = 0
	velocity.y = _boosted_jump_velocity() if boosted else _jump_velocity
	if slot.has_attr(Platform.Attr.SQUISHY):
		velocity.y *= Platform.SQUISH_BOOST if is_timed else Platform.SQUISH_PENALTY
	if slot.has_attr(Platform.Attr.GLASS):
		_broken[index] = true
	if boosted and streak > 0 and streak % 10 == 0:
		_enter_wind()
	_last_slot = index
	_target = -1
	_squash = 1.3 if boosted else 1.0
	_squash_vel = 0.0

## Even odds when on pace, climbing toward certain the further behind it is.
func _flare_odds() -> float:
	var lead := _lead_seconds()
	var odds := clampf(0.5 - lead * LEAD_RESPONSE, MIN_FLARE_ODDS, MAX_FLARE_ODDS)
	# The next flare would be a Solar Wind -- hold it back unless it is needed.
	if streak % 10 == 9 and lead > -WIND_DEFICIT:
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
	respawn_left = Race.RESPAWN_PENALTY
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

# --- Visuals --------------------------------------------------------------

## Visual-only. The body is only drawn while near the screen: PlasmaBlob
## redraws every frame, and the bot spends most of a race out of view.
func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		var half_h := get_viewport_rect().size.y / 2.0
		var dy := global_position.y - cam.global_position.y
		_visual.visible = absf(dy) < half_h + DRAW_MARGIN
	if not _visual.visible:
		return
	var d := minf(delta, 0.05)
	_squash_vel += (-150.0 * _squash - 7.0 * _squash_vel) * d
	_squash += _squash_vel * d
	var stretch := clampf(absf(velocity.y) * 0.00022, 0.0, 0.34)
	_visual.scale = Vector2(
		maxf(1.0 + _squash * 0.55 - stretch * 0.5, 0.2),
		maxf(1.0 - _squash * 0.55 + stretch, 0.2))

func _draw() -> void:
	var text := "AI"
	var extents := LABEL_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE)
	draw_string(LABEL_FONT, Vector2(-extents.x / 2.0, -LABEL_LIFT), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, color)
