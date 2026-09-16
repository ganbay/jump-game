extends Node

## Plays a run of main.tscn by itself, so a trailer segment is real gameplay
## rather than a hand-recorded take. Attached to the Main scene by
## trailer_director.gd; it has no place in a shipped build.
##
## Two jobs, and they are deliberately done through different doors.
##
## STEERING goes through the real input path -- Input.action_press on
## ui_left/ui_right, exactly what a keyboard player presses. player.gd ramps
## that through `key_accel` rather than snapping to full speed, so the
## character drifts across the screen the way a played run does instead of
## tracking targets like a cursor. Nothing about this is faked.
##
## TIMING does not. A perfect landing in player.gd is a press inside
## `landing_window_ms` of touchdown, measured with Time.get_ticks_msec() --
## wall-clock milliseconds. The trailer renders under --fixed-fps with a PNG
## written per frame, so one simulated frame takes ~60ms of wall clock: the
## simulation and the wall clock run at completely different rates and any
## press timed in game-time would land outside a window measured in real time.
## Rather than fight that, this writes player.gd's two press timestamps
## directly every physics frame, which makes the *next* landing -- whenever it
## happens -- read as timed or not, on purpose. Everything downstream of that
## decision is the game's own code: _land_on() runs untouched, so the boost,
## the streak, the coin, the flare, Solar Wind and the camera punch are all
## the real thing.
##
## Runs at a negative physics priority so both of those land before the
## player's own _physics_process reads them in the same tick.

## Cycled per landing: 1 asks for a perfect (timed) landing, 0 for a plain one.
## A plain landing here is a *pass*, not a miss -- `_attempted_since_last_landing`
## is left false, so the streak survives it. Nothing in a trailer should show
## the player failing.
@export var perfect_cycle: PackedInt32Array = PackedInt32Array([1])

## How much of the horizontal distance the bot believes it can cover in the
## time it has. Under 1.0 because move_speed is a ceiling it only reaches after
## `key_accel` has ramped it there, and because a platform picked with zero
## margin is one the drift overshoots.
const REACH_SAFETY := 0.78
## How close the *predicted resting place* has to be to the platform centre
## before the keys are let go. Not the current position: see _steer().
const STOP_EPS := 5.0
## A platform has to be at least this far above the apex-to-feet span to count
## as somewhere to aim, which keeps the bot from re-targeting the platform it
## is standing on during the first frames of a launch.
const MIN_CLIMB := 8.0

## How far below the character miss mode looks for things to avoid. Deep
## enough to cover a whole fall, so the gap it threads is a gap all the way
## down rather than one that closes a screen later.
const MISS_LOOKAHEAD := 1600.0
## Candidate landing positions considered across the screen width in miss mode.
const MISS_SAMPLES := 48
## How much a candidate gap is penalised for being far from where the character
## already is, relative to the clearance it offers. Without it the bot dashes
## across the screen for a marginally wider gap, which reads as a decision
## rather than as a missed jump.
const MISS_TRAVEL_WEIGHT := 0.25

var player: Player
## Set by the director when a segment is torn down, so a scene sliding off
## screen stops driving the global Input state the incoming one reads.
var active: bool = true
## Stop climbing and start looking for somewhere to fall through. The trailer
## has one segment that ends in a death, and a death is better played than
## staged: deleting the platforms under the character would be visible on
## screen, and moving the death margin would kill it in mid-air over a platform
## it was about to land on. So the bot aims at a gap instead of at a platform,
## misses on purpose, and the run ends for the reason a player's would.
var miss_mode: bool = false

var _cycle_index: int = 0
var _want_perfect: bool = true
var _target: Node2D = null
var _width: float = 720.0
var _pressed: StringName = &""

func _ready() -> void:
	# Before the player's own physics, so the timestamps written below are the
	# ones _land_on() reads this same tick.
	process_physics_priority = -100
	# The SubViewport's visible rect, which is the 720x1280 canvas override the
	# director renders the game against -- not the 1080x1920 it rasterises to.
	_width = get_viewport().get_visible_rect().size.x
	_want_perfect = _next_from_cycle()

func begin(target_player: Player) -> void:
	player = target_player
	player.landed.connect(_on_landed)

## Called by the director before the scene is taken out of the tree. Input
## actions are global state, not per-viewport, so a segment that leaves them
## held would steer the next segment's character.
func release() -> void:
	active = false
	_release_keys()

func _exit_tree() -> void:
	_release_keys()

func _physics_process(_delta: float) -> void:
	if not active or player == null or not is_instance_valid(player):
		return
	_write_press_state()
	_steer()

## player.gd's _land_on() asks two questions of these timestamps: was there a
## press inside the landing window (`in_window`), and was it the only one
## (`single_tap`). Writing "pressed right now, and nothing before that" every
## frame answers yes to both on whichever frame the landing turns out to be.
## The inverse -- a press far in the past -- answers no, and leaving
## `_attempted_since_last_landing` false is what stops that reading as a miss
## and resetting the streak.
func _write_press_state() -> void:
	player._prev_press_ms = -999999
	if _want_perfect:
		player.last_press_ms = Time.get_ticks_msec()
		player._attempted_since_last_landing = true
	else:
		player.last_press_ms = -999999
		player._attempted_since_last_landing = false

func _on_landed(_platform: Node, _boosted: bool, _streak: int) -> void:
	_want_perfect = _next_from_cycle()
	# The arc just changed completely, so last flight's target means nothing.
	_target = null

func _next_from_cycle() -> bool:
	if perfect_cycle.is_empty():
		return true
	var value := perfect_cycle[_cycle_index % perfect_cycle.size()]
	_cycle_index += 1
	return value != 0

func _steer() -> void:
	var goal_x := 0.0
	if miss_mode:
		goal_x = _pick_gap_x()
	else:
		var target := _pick_target()
		if target != null:
			_target = target
		if _target == null or not is_instance_valid(_target):
			_release_keys()
			return
		goal_x = _target.global_position.x
	# Steering on the distance left to the target is what a first attempt does,
	# and it misses every time. Releasing the keys does not stop the character:
	# player.gd bleeds horizontal speed off at move_speed * 4, so letting go at
	# full tilt still carries it about 110px further -- wider than the ~70px of
	# platform the feet can actually catch. So what is steered to zero here is
	# not the distance to the platform but the distance the character would
	# *end up* from it if the keys were dropped this frame. When that overshoots,
	# the error flips sign on its own and the controller presses the other way,
	# which is the braking half of the manoeuvre falling out of the same line.
	var dx := _wrapped_dx(player.global_position.x, goal_x)
	var vx := player.velocity.x
	var decel := player.move_speed * 4.0
	var coast := signf(vx) * (vx * vx) / (2.0 * decel)
	var error := dx - coast
	if absf(error) <= STOP_EPS:
		_release_keys()
	else:
		_press(&"ui_right" if error > 0.0 else &"ui_left")

## The character wraps at both screen edges (player.gd:_wrap_screen), so the
## way to a platform can be shorter *through* the edge than across the screen.
## Signed, and always the shorter of the two routes.
func _wrapped_dx(from_x: float, to_x: float) -> float:
	var d := to_x - from_x
	if d > _width * 0.5:
		d -= _width
	elif d < -_width * 0.5:
		d += _width
	return d

## The emptiest column of screen to be in: the x furthest from anything the
## character could still land on, traded off against how far it is from where
## the character already is. Sampled across the width rather than solved for --
## the platforms move, there are rarely more than a handful in range, and a
## sample every 15px is finer than the ~70px of platform it is avoiding.
func _pick_gap_x() -> float:
	var feet_y := player.feet.global_position.y
	var hazards := PackedFloat32Array()
	for node in get_tree().get_nodes_in_group("platforms"):
		if not is_instance_valid(node):
			continue
		var platform := node as Node2D
		if platform == null:
			continue
		var dy := platform.global_position.y - feet_y
		# A little above the feet as well as below: on the way up, the platforms
		# just overhead are the ones about to be fallen back onto.
		if dy < -MIN_CLIMB * 4.0 or dy > MISS_LOOKAHEAD:
			continue
		hazards.append(platform.global_position.x)
	if hazards.is_empty():
		return player.global_position.x
	var best_x := player.global_position.x
	var best_score := -INF
	for i in range(MISS_SAMPLES):
		var x := (float(i) + 0.5) * _width / float(MISS_SAMPLES)
		var clearance := INF
		for hazard_x in hazards:
			clearance = minf(clearance, absf(_wrapped_dx(x, hazard_x)))
		var score := clearance \
			- absf(_wrapped_dx(player.global_position.x, x)) * MISS_TRAVEL_WEIGHT
		if score > best_score:
			best_score = score
			best_x = x
	return best_x

## The highest platform this arc can still both fall onto and reach sideways in
## time. Highest, because landing on the highest reachable platform every time
## is the whole of climbing; reachable, because aiming at one that is not just
## means falling past everything.
func _pick_target() -> Node2D:
	var feet_y := player.feet.global_position.y
	var vy := player.velocity.y
	var g := player.gravity
	# Only the descent is sped up by streak (player.gd:_physics_process), and
	# the descent is the whole of the time available to steer.
	var g_fall: float = g / player._streak_fall_multiplier()
	# Nothing above the apex will ever be touched, so the apex is the ceiling on
	# what counts as a candidate.
	var ceiling := feet_y
	var rise_time := 0.0
	if vy < 0.0:
		rise_time = -vy / g
		ceiling = feet_y - (vy * vy) / (2.0 * g)

	var best: Node2D = null
	var best_y := INF
	var nearest: Node2D = null
	var nearest_cost := INF
	for node in get_tree().get_nodes_in_group("platforms"):
		if not is_instance_valid(node):
			continue
		var platform := node as Node2D
		if platform == null:
			continue
		var py := platform.global_position.y
		if py <= ceiling + MIN_CLIMB:
			continue
		var time_left := rise_time + _fall_time(maxf(py - minf(ceiling, feet_y), 0.0), g_fall)
		if vy >= 0.0:
			if py <= feet_y + MIN_CLIMB:
				continue
			time_left = _descent_time(py - feet_y, vy, g_fall)
		var dx := absf(_wrapped_dx(player.global_position.x, platform.global_position.x))
		var reach := player.move_speed * time_left * REACH_SAFETY
		if dx <= reach:
			if py < best_y:
				best_y = py
				best = platform
		else:
			# Kept only so a hopeless frame still steers somewhere useful rather
			# than letting go of the keys and coasting.
			var cost := dx - reach
			if cost < nearest_cost:
				nearest_cost = cost
				nearest = platform
	return best if best != null else nearest

func _fall_time(distance: float, g_fall: float) -> float:
	return sqrt(2.0 * maxf(distance, 0.0) / g_fall)

## Time for feet already moving downward at `vy` to fall `distance`.
func _descent_time(distance: float, vy: float, g_fall: float) -> float:
	return (-vy + sqrt(vy * vy + 2.0 * g_fall * maxf(distance, 0.0))) / g_fall

func _press(action: StringName) -> void:
	if _pressed == action:
		return
	_release_keys()
	Input.action_press(action)
	_pressed = action

func _release_keys() -> void:
	if _pressed != &"":
		Input.action_release(_pressed)
		_pressed = &""
