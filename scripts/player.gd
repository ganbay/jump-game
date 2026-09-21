extends CharacterBody2D
class_name Player

signal landed(platform, boosted, streak)
## Fired the instant a post-landing mash zeroes the streak, since that happens
## mid-flight rather than at a landing -- callers that only want the "streak
## just failed" moment should not wait for the next `landed` signal.
signal streak_broken

## Selectable character visuals. Every one is the PlasmaBlob cell (see
## plasma_blob.gd) in a different Shape -- same churn, glow and squishy physics,
## just a different silhouette.
##
## Settings persists this enum as a raw int, so entries must not be inserted
## or reordered -- new ones go on the end -- except for the one deliberate
## renumbering below, done while DIAMOND/CRESCENT/COMET were still fresh
## enough that no released save depended on their slots (see Unlocks.gd for
## fixing up an already-equipped index across that renumbering).
##
## PLASMA holds slot 0 as the default, which is also the slot the retired
## solid-body skin used, so a save from that era opens on PLASMA. After it,
## the basic tier (PRISM, SQUARE, TRIANGLE, DOME, DIAMOND) is free; the
## complex tier (STAR, HEART, FLAME, SPARKLE) is gated -- see Unlocks.gd for
## what gates each one.
enum SkinType { PLASMA, PRISM, SQUARE, TRIANGLE, DOME, DIAMOND, STAR, HEART, FLAME, SPARKLE }

## Display names for the settings menu, indexed by SkinType.
const SKIN_NAMES := ["PLASMA", "PRISM", "SQUARE", "TRIANGLE", "DOME", "DIAMOND",
	"STAR", "HEART", "FLAME", "SPARKLE"]

## The PlasmaBlob.Shape each skin draws.
const SKIN_SHAPES := {
	SkinType.PLASMA: PlasmaBlob.Shape.CIRCLE,
	SkinType.PRISM: PlasmaBlob.Shape.PRISM,
	SkinType.SQUARE: PlasmaBlob.Shape.SQUARE,
	SkinType.TRIANGLE: PlasmaBlob.Shape.TRIANGLE,
	SkinType.DOME: PlasmaBlob.Shape.DOME,
	SkinType.DIAMOND: PlasmaBlob.Shape.DIAMOND,
	SkinType.STAR: PlasmaBlob.Shape.STAR,
	SkinType.HEART: PlasmaBlob.Shape.HEART,
	SkinType.FLAME: PlasmaBlob.Shape.FLAME,
	SkinType.SPARKLE: PlasmaBlob.Shape.SPARKLE,
}

@export var move_speed: float = 900.0
@export var gravity: float = 1600.0
@export var jump_velocity: float = -900.0
@export var boost_jump_velocity: float = -1300.0
@export var streak_jump_step: float = 0.1
@export var streak_jump_cap: int = 10
## Every streak point (up to streak_fall_cap) multiplies the fall-time
## multiplier by this -- compounding, so streak 10 lands at
## streak_fall_step^10. Below 1.0 shortens the time to fall, i.e. speeds it up
## (see _streak_fall_multiplier()).
@export var streak_fall_step: float = 0.95
@export var streak_fall_cap: int = 10
## Applies per streak point beyond streak_fall_cap, at a gentler rate so the
## fall doesn't keep compounding at the early pace forever.
@export var streak_fall_step_late: float = 0.99
@export var landing_window_ms: int = 150
## After a landing, a press that both starts and releases inside this window is
## a bare tap thrown right on top of the jump, not a steering hold -- see
## _maybe_fail_post_landing_tap().
@export var post_landing_mash_window_ms: int = 100
## Viewport px the character moves per px of finger travel, before the player's
## sensitivity slider scales it. Both sides of that ratio are viewport pixels --
## drag events are already mapped through the stretch transform -- so 1.0 means
## the character tracks the finger exactly, on a 720p phone and a 1440p one
## alike.
@export var drag_sensitivity: float = 1.0
## How far (viewport px) a touch has to travel before it counts as steering
## rather than a tap. Only steering presses are excused from the mash check in
## _mashed(); a finger that goes down and up in place is a tap.
@export var steer_min_travel: float = 10.0
## How fast the arrow keys ramp horizontal speed. They used to snap straight to
## full move_speed on the first frame, which on a keyboard reads as
## hair-trigger: one tap threw the character across a whole platform.
@export var key_accel: float = 4200.0
@export var tilt_sensitivity: float = 220.0
@export var tilt_deadzone: float = 0.6
@export var invert_tilt: bool = false

@export_group("Squash & Stretch")
## How much the shape stretches per unit of vertical speed.
@export var stretch_per_speed: float = 0.00022
@export var max_stretch: float = 0.34
## How hard the shape compresses on a normal / boosted landing.
@export var land_impulse: float = 1.0
@export var boost_land_impulse: float = 1.3
## Spring that returns the impact squash to rest. Lower damping = bouncier.
@export var squash_stiffness: float = 220.0
@export var squash_damping: float = 14.0
## Sideways lean while moving horizontally. Set to 0 to disable.
@export var lean_per_speed: float = 0.00018
@export var max_lean: float = 0.2
## How far the shape deforms per unit of squash.
@export var squash_deform: float = 0.55

@export_group("Plasma Squish")
## The plasma cell is a fluid body: it deforms further and keeps jiggling
## longer after impact than a solid one would. These scale the base Squash &
## Stretch values above.
@export var plasma_stiffness_scale: float = 0.68
@export var plasma_damping_scale: float = 0.5
@export var plasma_deform_scale: float = 1
@export var plasma_impulse_scale: float = 1.25

@export_group("Solar Wind")
## Triggered every SOLAR_WIND_MILESTONE streak (see game.gd:_on_player_landed).
## solar_wind_launch_mult hits the current jump's velocity immediately and
## once; solar_wind_speed_mult eases move_speed up, holds, and eases back
## down. See enter_solar_wind() for why the launch boost has to be applied
## immediately rather than at some later landing.
@export var solar_wind_duration: float = 2.0
@export var solar_wind_ease_time: float = 0.35
@export var solar_wind_speed_mult: float = 2.0
@export var solar_wind_launch_mult: float = 2.0

var streak: int = 0
var last_press_ms: int = -999999
## The press before `last_press_ms`. A timed landing has to come from one
## deliberate tap, so the window must hold exactly one press. Every press
## refreshes `last_press_ms`, so without this second timestamp a player mashing
## the screen on the way down satisfies the window on every landing and never
## has to time anything -- and in TOUCH mode they are already pressing to
## steer, which made it close to free.
var _prev_press_ms: int = -999999
## Pointers currently held down, keyed by touch index (or MOUSE_POINTER), each
## mapped to the press record _register_press() made for it. Tracked per finger
## so two-handed play works: one thumb holds and steers while the other taps to
## time landings, and lifting the tapping thumb must not end the steering.
var _pointers: Dictionary = {}
## The held pointer that steers, or NO_POINTER. Only the first finger down
## steers; a finger that lands while it is held is the other hand's timing tap.
var _steer_pointer: int = NO_POINTER
## Horizontal drag the steering pointer covered since the last physics tick.
var _steer_dx: float = 0.0
## Presses made while falling during this flight, oldest first. See _mashed().
var _descent_presses: Array[Dictionary] = []
var _attempted_since_last_landing: bool = false
## Timestamp and outcome of the last landing, for _maybe_fail_post_landing_tap().
var _last_land_ms: int = -999999
var _last_land_boosted: bool = false
var _viewport_width: float = 720.0
## Impact compression, 1.0 = fully squashed. Driven as a damped spring rather
## than a tween so repeated landings add to it instead of fighting over
## visual.scale, and so the shape keeps reacting for the whole jump.
var _squash: float = 0.0
var _squash_vel: float = 0.0
var _lean: float = 0.0
## Captured once in _ready() so repeated Solar Wind bursts always ease back to
## the true baseline, not to whatever the last burst left behind.
var _base_move_speed: float = 0.0
var _solar_wind_tween: Tween
const NO_POINTER := -1
## Stands in for a touch index for the real (desktop) mouse.
const MOUSE_POINTER := -100
## Stands in for a touch index for the keyboard's space bar.
const KEY_POINTER := -200
## How far either side of the landing point still counts as over a platform.
## Matched to PlasmaBlob's radius, so the catch ends exactly where the drawn
## silhouette does: the widest skins (STAR's points, SQUARE's corners) reach a
## full radius, so this is the character's real half-width on screen. It used
## to be 20 -- half of the 40x10 FeetShape rectangle, which nothing reads --
## and those 2px bought a sliver where a landing registered on a platform the
## character was visibly clear of.
const FEET_HALF_WIDTH := 18.0
## Vertical slop on the sweep band below, not a half-height of anything drawn:
## the landing point is a point (the blob is bottom-anchored on it), so there
## is no visual extent here to match.
const FEET_HALF_HEIGHT := 5.0
## Fallback half-width for a platform that is not a Platform; real ones report
## their own (see _platform_half_width), since the spawner narrows them with
## difficulty.
const PLATFORM_HALF_WIDTH := 45.0
## Half of Platform's 12px visual, so the surface the character is placed on
## is the top of what is drawn.
const PLATFORM_HALF_HEIGHT := 6.0

const COLOR := Color(0.66295815, 2.299754, 0.0, 1.0)

@onready var feet: Area2D = $Feet
@onready var visual: PlasmaBlob = $PlasmaVisual
@onready var trail: PlayerTrail = $Trail

func _ready() -> void:
	add_to_group("player")
	# Cached rather than re-queried every physics frame. Orientation is locked
	# to portrait so a phone never changes this mid-run, but a resizable window
	# (desktop, editor) and a tablet's wider aspect both do, and screen wrap
	# lands on the wrong edge if the cache goes stale.
	_viewport_width = get_viewport_rect().size.x
	get_viewport().size_changed.connect(_on_viewport_resized)
	_base_move_speed = move_speed
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)

func _on_viewport_resized() -> void:
	_viewport_width = get_viewport_rect().size.x

func _apply_visual_settings() -> void:
	var shape: PlasmaBlob.Shape = SKIN_SHAPES.get(
		Settings.active_player_skin(), PlasmaBlob.Shape.CIRCLE)
	visual.shape = shape
	visual.color = Settings.player_color
	trail.color = Settings.player_color
	trail.shape = shape
	trail.set_enabled(Settings.trail_enabled)

## Streak milestone burst. velocity.y was just set moments ago in _land_on()
## for this exact launch -- boosting it immediately, rather than waiting on
## some future landing's _boosted_jump_velocity() call, is what makes THIS
## jump the one that visibly rockets. Waiting does not work here: at streak
## 10+ a single jump arc already takes longer than the whole burst window (the
## already-capped streak boost alone is a ~3s round trip against gravity), so
## the window would close again before the player ever landed to read a flag.
## move_speed also eases up to double (holds, eases back down); re-triggering
## (another milestone hit before that move_speed ease finishes) kills whatever
## tween is running and starts fresh from the current -- already boosted --
## speed, so back-to-back milestones don't snap, they just extend.
func enter_solar_wind() -> void:
	velocity.y *= solar_wind_launch_mult
	if _solar_wind_tween != null and _solar_wind_tween.is_valid():
		_solar_wind_tween.kill()
	_solar_wind_tween = create_tween()
	_tween_solar_wind_speed(_base_move_speed * solar_wind_speed_mult, Tween.EASE_OUT)
	_solar_wind_tween.tween_interval(
		maxf(solar_wind_duration - solar_wind_ease_time * 2.0, 0.0))
	_solar_wind_tween.tween_callback(_exit_solar_wind)

func _exit_solar_wind() -> void:
	_solar_wind_tween = create_tween()
	_tween_solar_wind_speed(_base_move_speed, Tween.EASE_IN)

func _tween_solar_wind_speed(target: float, ease: Tween.EaseType) -> void:
	_solar_wind_tween.tween_property(self, "move_speed", target, solar_wind_ease_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(ease)

func _unhandled_input(event: InputEvent) -> void:
	# On a touchscreen every touch also arrives a second time as an emulated
	# mouse event (device -1). Letting both through registers each tap twice,
	# which leaves `_prev_press_ms` on the very same timestamp -- so
	# `single_tap` is never true and a timed landing is impossible on mobile.
	# Touches are tracked directly below, so the emulated copies are not needed.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		_set_pointer(event.index, event.pressed)
	elif event is InputEventScreenDrag:
		_drag_pointer(event.index, event.relative.x)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_set_pointer(MOUSE_POINTER, event.pressed)
	elif event is InputEventMouseMotion:
		_drag_pointer(MOUSE_POINTER, event.relative.x)
	elif event is InputEventKey and event.keycode == KEY_SPACE and not event.echo:
		# A key never steers, so the arrow keys' drift survives a timing tap.
		_set_key_pointer(event.pressed)

## Releases that happen while the game is paused never reach _unhandled_input,
## so a finger lifted on the pause screen would otherwise stay "held" -- and
## keep the steering slot -- for the rest of the run.
func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pointers.clear()
		_steer_pointer = NO_POINTER
		_steer_dx = 0.0

## Space has no drag to report travel, and never steers, so it does not need
## the full pointer/_steer_pointer machinery -- but it still needs press/release
## tracked like a held touch, so a long-held space is not judged as a bare tap
## by _maybe_fail_post_landing_tap the instant it goes down.
func _set_key_pointer(pressed: bool) -> void:
	if not pressed:
		if _pointers.has(KEY_POINTER):
			_maybe_fail_post_landing_tap(_pointers[KEY_POINTER], Time.get_ticks_msec())
		_pointers.erase(KEY_POINTER)
		return
	if _pointers.has(KEY_POINTER):
		return
	_pointers[KEY_POINTER] = _register_press(false)

func _set_pointer(id: int, pressed: bool) -> void:
	if not pressed:
		if _pointers.has(id):
			_maybe_fail_post_landing_tap(_pointers[id], Time.get_ticks_msec())
		_pointers.erase(id)
		if id == _steer_pointer:
			_steer_pointer = NO_POINTER
		return
	if _pointers.has(id):
		return
	var steers := (Settings.control_scheme == Settings.ControlScheme.TOUCH
		and _steer_pointer == NO_POINTER)
	if steers:
		_steer_pointer = id
		_steer_dx = 0.0
	_pointers[id] = _register_press(steers)

func _drag_pointer(id: int, dx: float) -> void:
	if not _pointers.has(id):
		return
	_pointers[id]["travel"] += absf(dx)
	if id == _steer_pointer:
		_steer_dx += dx

func _register_press(steers: bool) -> Dictionary:
	var now := Time.get_ticks_msec()
	_prev_press_ms = last_press_ms
	last_press_ms = now
	_attempted_since_last_landing = true
	# `falling` is captured once, at press time, so a press that started
	# mid-fall is still recognisable as a fall press later even after landing
	# clears _descent_presses -- see _mark_pending_fail_presses().
	var press := {"ms": now, "steers": steers, "travel": 0.0, "falling": velocity.y > 0.0}
	if press["falling"]:
		_descent_presses.append(press)
	return press

## A press that both starts and releases inside the post-landing grace window,
## without covering real steering distance, is a bare tap thrown right on top
## of the jump. Steering a small distance and letting go quickly to settle on a
## landing spot is normal play, not mashing -- see steer_min_travel -- so travel
## exempts a press the same way it already does in _mashed(), regardless of how
## briefly it was held; a press still held when the window closes is exempt too,
## since it has not finished being judged yet. Skipped entirely when the landing
## that just happened actually earned a streak point (`boosted`, not just
## `is_timed` -- a landing can be perfectly timed and still not score if the
## platform's boost was already spent, and that still counts as "didn't streak"
## for this check), so the scoring press's own release (which can land just
## after the landing it caused) can never cancel a streak it just won -- and
## skipped when there is no streak left to break, so this can't fire twice for
## the same failure. Fires streak_broken immediately rather than waiting for the
## next landed signal, since this happens mid-flight.
func _maybe_fail_post_landing_tap(press: Dictionary, release_ms: int) -> void:
	if press.has("pending_fail_deadline_ms"):
		_resolve_pending_fail(press, release_ms)
		return
	if _last_land_boosted or streak == 0:
		return
	var press_ms: int = press["ms"]
	if press_ms <= _last_land_ms or press["travel"] >= steer_min_travel:
		return
	if press_ms - _last_land_ms <= post_landing_mash_window_ms \
			and release_ms - _last_land_ms <= post_landing_mash_window_ms:
		streak = 0
		Audio.set_streak(0)
		streak_broken.emit()

## A press that started mid-fall, too early to be the timing tap, but was still
## held (not yet released) at landing -- see _mark_pending_fail_presses(). Its
## fate was deliberately left open at landing: it only breaks the streak if it
## releases within post_landing_mash_window_ms of that landing, same grace
## period as a fresh post-landing tap gets. Held longer than that, it reads as
## an ordinary steering hold into the next jump, not a mash, and is forgiven --
## even though the streak already failed to score at that landing (no new
## point), it is spared the reset. Travel accumulated at any point, even after
## landing, still exempts it, same as everywhere else this is checked.
func _resolve_pending_fail(press: Dictionary, release_ms: int) -> void:
	if streak == 0 or press["travel"] >= steer_min_travel:
		return
	if release_ms <= press["pending_fail_deadline_ms"]:
		streak = 0
		Audio.set_streak(0)
		streak_broken.emit()

## Whether the streak's fate at this landing should wait on a press that is
## still held, rather than being decided right now. Any currently-held press
## that started during this flight (climb or fall) means there is something
## whose outcome is not known yet, so _land_on() must not reset the streak
## immediately -- a press already released by landing time has nothing left to
## wait on, and already failed via the ordinary is_timed/_mashed() path above
## if it was going to.
##
## Among the still-held presses, the ones that (a) started during the fall and
## (b) weren't a steer get tagged with a deadline for _resolve_pending_fail()
## to judge them by once released (see _land_on()'s Rule 2). A held climb press
## is left untagged: it can never fail the streak this way, by rule.
##
## A press that started inside landing_window_ms used to be spared as well, on
## the grounds that it might still be the landing's own scoring press. That was
## wrong, and it was the whole of the "mashing breaks nothing" bug: this only
## runs from the branch where is_timed is already false, so by the time it is
## reached nothing scored and there is no scoring press left to protect. A mash
## that ended with a finger still down at touchdown therefore slipped past
## every check -- disqualified as the timing tap, never tagged here, and then
## rejected by _maybe_fail_post_landing_tap for having started before the
## landing.
func _mark_pending_fail_presses(now: int) -> bool:
	var held := false
	for press: Dictionary in _pointers.values():
		if press["ms"] <= _last_land_ms:
			continue
		held = true
		if not press["falling"]:
			continue
		if press["steers"] and press["travel"] >= steer_min_travel:
			continue
		press["pending_fail_deadline_ms"] = now + post_landing_mash_window_ms
	return held

## Whether a tap on the way down went unanswered by a landing. The window checks
## in _land_on() only look at the last two presses, so tapping steadily a little
## slower than the window passes them on most landings without timing anything.
## Any earlier press during the fall that was not steering is a missed tap, and
## a missed tap breaks the streak even if a later one lands inside the window.
## Presses on the way up are free: nothing can be timed there.
func _mashed() -> bool:
	var count := _descent_presses.size()
	for i in count:
		var press := _descent_presses[i]
		if i == count - 1 and press["ms"] == last_press_ms:
			continue # the timing tap itself
		if not (press["steers"] and press["travel"] >= steer_min_travel):
			return true
	return false

## Streak points below streak_fall_cap each shave streak_fall_step off the
## fall-time multiplier; points beyond it each shave streak_fall_step_late
## instead. E.g. at streak 10: streak_fall_step^10. At streak 20:
## streak_fall_step^10 * streak_fall_step_late^10.
func _streak_fall_multiplier() -> float:
	var capped := mini(streak, streak_fall_cap)
	var extra := maxi(streak - streak_fall_cap, 0)
	return pow(streak_fall_step, capped) * pow(streak_fall_step_late, extra)

func _physics_process(delta: float) -> void:
	# Only the descent gets sped up by streak -- applying it during the rise too
	# would cut the jump's apex short and strand normal jumps short of the next
	# platform.
	var g: float = gravity / _streak_fall_multiplier() if velocity.y >= 0.0 else gravity
	velocity.y += g * delta

	var speed := move_speed
	var key_axis := Input.get_axis("ui_left", "ui_right")
	if key_axis != 0.0:
		velocity.x = move_toward(velocity.x, key_axis * speed, key_accel * delta)
	elif Settings.control_scheme == Settings.ControlScheme.TILT:
		var tilt := Input.get_accelerometer().x * (-1.0 if invert_tilt else 1.0)
		if absf(tilt) < tilt_deadzone:
			velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)
		else:
			velocity.x = clampf(tilt * tilt_sensitivity * Settings.tilt_sensitivity,
				-speed, speed)
	elif _steer_pointer != NO_POINTER:
		# Drag steering tracks the finger 1:1 (times sensitivity): the travel
		# reported since the last tick is turned into exactly that much motion
		# over exactly this tick, so the character keeps up with the finger in
		# both distance and time. move_speed deliberately does NOT cap this --
		# clamping to it is what made a quick flick cover far less ground than
		# a slow drag of the same length. The only limit is a sanity guard of
		# one viewport width per tick, which a real finger cannot exceed.
		var drag_step := _steer_dx * drag_sensitivity * Settings.touch_sensitivity
		velocity.x = clampf(drag_step, -_viewport_width, _viewport_width) / delta
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)
	_steer_dx = 0.0

	var prev_feet_y := feet.global_position.y
	move_and_slide()
	_wrap_screen()

	if velocity.y > 0.0:
		_check_landing(prev_feet_y, feet.global_position.y)

func _wrap_screen() -> void:
	if global_position.x < 0.0:
		global_position.x = _viewport_width
	elif global_position.x > _viewport_width:
		global_position.x = 0.0

func _check_landing(prev_y: float, new_y: float) -> void:
	var band := FEET_HALF_HEIGHT + PLATFORM_HALF_HEIGHT
	var best_area: Node = null
	var best_y := INF
	for area in get_tree().get_nodes_in_group("platforms"):
		if not is_instance_valid(area):
			continue
		var py: float = area.global_position.y
		if py < prev_y - band or py > new_y + band:
			continue
		if absf(feet.global_position.x - area.global_position.x) > _platform_half_width(area) + FEET_HALF_WIDTH:
			continue
		if py < best_y:
			best_y = py
			best_area = area
	if best_area != null:
		_land_on(best_area)

func _platform_half_width(area: Node) -> float:
	return area.width / 2.0 if area is Platform else PLATFORM_HALF_WIDTH

## Puts the character on the surface it just landed on, before anything else
## reacts to the landing.
##
## _check_landing sweeps the feet between the last physics frame's position
## and this one's, which is what stops a fast fall from tunnelling straight
## through a platform -- but detecting the crossing is not the same as being
## at it. The descent gets quicker with every streak point
## (_streak_fall_multiplier), and at streak 10 it runs near 3400 px/s: about
## 56px in one 60Hz tick, against a character 36px tall. So by the time the
## landing resolved, the platform could be anywhere from under the feet to
## above the head -- which is exactly the "it bounced with the platform
## through its middle" report. The bounce was right; only the position was
## wherever the frame happened to stop.
##
## Correcting it costs nothing to look at: the character leaves at 900-2600
## px/s on the very next frame, so a sub-frame snap is invisible, and every
## launch now starts from the surface it is supposed to be launching off.
## Platforms are non-colliding Area2Ds (monitoring and mask both off), so
## moving the body here cannot push it out of anything.
func _snap_to_platform(area: Node) -> void:
	# Read from the node rather than assuming the authored 17px, so moving
	# Feet in the scene moves the contact point with it.
	var feet_offset := feet.global_position.y - global_position.y
	global_position.y = area.global_position.y - PLATFORM_HALF_HEIGHT - feet_offset

func _land_on(area: Node) -> void:
	var now := Time.get_ticks_msec()
	_snap_to_platform(area)
	# Counting presses since the last landing would not work here: steering is
	# press-and-drag, so an ordinary flight already spends two or three presses
	# before the timing tap. What has to be sole is the press inside the window.
	var in_window := now - last_press_ms <= landing_window_ms
	var single_tap := now - _prev_press_ms > landing_window_ms
	# Kept in a local rather than folded straight into is_timed: a mash is
	# proven by presses that have already come and gone, so it still has to be
	# answered below even when a finger is left down across the landing.
	var mashed := _mashed()
	var is_timed := in_window and single_tap and not mashed
	_descent_presses.clear()
	# The boost belongs to the platform, not to "wasn't the last one I touched":
	# a mistimed landing spends nothing, so the next streak can start right here.
	var boosted := is_timed and not _boost_spent(area)
	if is_timed:
		if boosted:
			streak += 1
			_spend_boost(area)
	elif _attempted_since_last_landing:
		# Called first in either case, so a held press still receives its
		# deadline and cannot then be judged a second time on release.
		var held := _mark_pending_fail_presses(now)
		# Deferring to a held press is only right while the landing's verdict
		# is genuinely still open. A mash has already happened -- the taps that
		# proved it were released before touchdown -- so leaving a finger down
		# over the landing must not launder it into a clean slate.
		if mashed or not held:
			streak = 0
	_attempted_since_last_landing = false
	_last_land_ms = now
	_last_land_boosted = boosted
	velocity.y = _boosted_jump_velocity() if boosted else jump_velocity
	_play_squash(boosted)
	Audio.set_streak(streak)
	if area.has_method("on_landed"):
		# is_timed goes along with boosted: a platform that rewards a perfect
		# landing has to see the timing itself, not just whether this landing
		# happened to be the one that claimed the platform's streak boost.
		area.on_landed(self, boosted, is_timed)
	landed.emit(area, boosted, streak)

func _boost_spent(area: Node) -> bool:
	return area is Platform and area.boost_spent

func _spend_boost(area: Node) -> void:
	if area is Platform:
		area.boost_spent = true

func _boosted_jump_velocity() -> float:
	return boost_jump_velocity * (1.0 + streak_jump_step * clampi(streak, 0, streak_jump_cap))

func _play_squash(boosted: bool) -> void:
	# An impact is instantaneous, so set the compression directly and let the
	# spring in _process resolve it.
	_squash = (boost_land_impulse if boosted else land_impulse) * plasma_impulse_scale
	_squash_vel = 0.0

## Visual-only, so it runs at render rate rather than the physics tick.
func _process(delta: float) -> void:
	# Clamped so a frame hitch cannot push the explicit-Euler spring past its
	# stability limit and make the shape explode.
	var d := minf(delta, 0.05)
	# Damped spring pulling the impact squash back to neutral.
	_squash_vel += (-squash_stiffness * plasma_stiffness_scale * _squash
		- squash_damping * plasma_damping_scale * _squash_vel) * d
	_squash += _squash_vel * d

	# Continuous stretch from vertical speed, in either direction: this is what
	# keeps the shape alive during the airtime the old tween left frozen.
	var speed_stretch := clampf(absf(velocity.y) * stretch_per_speed, 0.0, max_stretch)

	var deform := squash_deform * plasma_deform_scale
	visual.scale = Vector2(
		maxf(1.0 + _squash * deform - speed_stretch * 0.5, 0.2),
		maxf(1.0 - _squash * deform + speed_stretch, 0.2)
	)

	var target_lean := clampf(velocity.x * lean_per_speed, -max_lean, max_lean)
	_lean = lerpf(_lean, target_lean, 1.0 - exp(-12.0 * d))
	visual.rotation = _lean
