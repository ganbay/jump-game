extends Area2D
class_name Platform

## Platforms no longer come in fixed, colour-coded types. Each one carries an
## independent set of attributes and any combination is legal -- a platform can
## be a moving, blinking, squishy pane of glass. Zones stamp one extra attribute
## onto every platform inside them (see zone_director.gd), so a platform in a
## zone usually carries two: the one it rolled for itself and the zone's.
enum Attr {
	MOVE_H = 1,
	MOVE_V = 2,
	GLASS = 4,
	INVISIBLE = 8,
	SQUISHY = 16,
}

const BASE_COLOR := Color(0.3, 1.0, 2.2)

## What a glass body is mixed toward, how far, and what it keeps of its fill.
##
## Cold and DARK, which is the opposite of what this did before. The old glass
## cooled toward white, and that read well only because the platform colour was
## then the player's saturated pick -- a green slab going pale was an obvious
## change. Platform colour is a neutral near-white now, tinted per zone (see
## zone_ambience.gd), so mixing toward white moved it by nothing and glass lost
## its tell down to alpha alone.
##
## Going down and blue instead restores it twice over: the pane is plainly
## darker than the solid slabs around it, and the decor's rim, glare and sheen
## -- all drawn bright and near-white -- finally have something to read against.
## That contrast between a dim body and a bright edge is what says "glass"; two
## whites on top of each other never could.
const GLASS_COLOR := Color(0.35, 0.85, 1.25)
const GLASS_BLEND := 0.62
const GLASS_ALPHA := 0.3

## Consts rather than exports so they can be read without holding an instance.
const SQUISH_BOOST := 1.25
const SQUISH_PENALTY := 0.5

## Idle breathing of a squishy platform's cushion, and the damped spring that
## resolves the compression a landing stamps into it. Compression runs 0 (fully
## inflated) to 1 (crushed flat); the slab itself never deforms, only the
## cushion drawn on its surface, which is what makes the motion legible -- the
## dome is small, so the same pixels are a large share of its silhouette.
const SQUISH_IDLE_RATE := 3.2
const SQUISH_IDLE_AMOUNT := 0.5
const SQUISH_STIFFNESS := 190.0
const SQUISH_DAMPING := 11.0

## An invisible platform is solid the entire time -- only its rendering cycles.
## It shows, fades out, stays gone, then fades back -- shown and gone for equal
## stretches of the cycle.
const PHANTOM_VISIBLE_HOLD := 0.7
const PHANTOM_GONE_HOLD := 0.7
const PHANTOM_FADE := 0.2
const PHANTOM_CYCLE := PHANTOM_VISIBLE_HOLD + PHANTOM_GONE_HOLD + PHANTOM_FADE * 2.0

@export_flags("Move H", "Move V", "Glass", "Invisible", "Squishy") var attributes: int = 0
@export var move_speed: float = 110.0
## Peak speed of a vertical sweep, and how far it travels top to bottom. The
## distance is deliberately well under a spawn gap: a taller sweep would carry
## platforms through their neighbours.
@export var move_v_speed: float = 95.0
@export var move_v_distance: float = 120.0
@export var width: float = 90.0

## A platform's boost can be claimed exactly once. Landing here again gives an
## ordinary jump -- but a failed landing never spends it, so a streak broken on
## this platform can still be restarted on this same platform.
var boost_spent: bool = false

## Attributes are fixed once the platform is in the tree, so the flag tests in
## the per-frame paths are resolved to plain bools in _ready.
var _move_h: bool = false
var _move_v: bool = false
var _glass: bool = false
var _invisible: bool = false
var _squishy: bool = false

var _dir: int = 1
var _min_x: float
var _max_x: float
var _home_x: float = 0.0
var _home_y: float = 0.0
var _v_phase: float = 0.0
## The spawner's course_time, which moving platforms are positioned from (see
## drift_x/bob_y). Starts wherever the course clock stood when this was built.
var _clock: float = 0.0
var _motion_set: bool = false
var _v_rate: float = 0.0
var _v_amp: float = 0.0
var _squish_t: float = 0.0
var _phantom_t: float = 0.0
var _impact: float = 0.0
var _impact_vel: float = 0.0
var _broken: bool = false

@onready var visual: RoundedRect = $Visual
## Typed loosely on purpose: platform_decor.gd needs Platform.Attr, and naming
## PlatformDecor back from here would make the two scripts a resolution cycle.
@onready var decor: Node2D = $Decor

func _ready() -> void:
	add_to_group("platforms")
	_move_h = has_attr(Attr.MOVE_H)
	_move_v = has_attr(Attr.MOVE_V)
	_glass = has_attr(Attr.GLASS)
	_invisible = has_attr(Attr.INVISIBLE)
	_squishy = has_attr(Attr.SQUISHY)
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	_apply_width()
	_apply_visual_settings()
	var vw := get_viewport_rect().size.x
	_min_x = width / 2.0
	_max_x = vw - width / 2.0
	_home_x = position.x
	_home_y = position.y
	_v_amp = move_v_distance / 2.0
	_v_rate = move_v_speed / maxf(_v_amp, 1.0)
	if not _motion_set:
		_v_phase = randf() * TAU
		_dir = 1 if randf() < 0.5 else -1
	_apply_motion()
	# Staggered, so a screenful of invisible platforms does not blink in
	# lockstep -- which would look mechanical and, worse, leave the player with
	# no visible platform at all for the whole 1.4s gone phase.
	_phantom_t = randf() * PHANTOM_CYCLE
	# Only moving platforms have anything to do per physics tick, and only
	# squishy or invisible ones animate; the rest would just pay call overhead
	# every frame.
	set_physics_process(_move_h or _move_v)
	set_process(_squishy or _invisible)

func has_attr(attr: Attr) -> bool:
	return attributes & attr != 0

## Called by the spawner before add_child, from the platform's course slot. A
## platform built without it rolls its own and starts its clock at zero.
func set_motion(dir: int, v_phase: float, clock: float) -> void:
	_dir = dir
	_v_phase = v_phase
	_clock = clock
	_motion_set = true

## Where a sideways mover is `t` seconds into the course, bouncing between
## min_x and max_x. Closed form rather than stepped, so the spawner can answer
## the same question for a platform that has no node (see slot_position).
## Unfolds the bounce onto a loop twice the span long: the first half is the
## trip right, the second the trip back.
static func drift_x(x0: float, dir: int, min_x: float, max_x: float, speed: float,
		t: float) -> float:
	var span := maxf(max_x - min_x, 1.0)
	var p0 := x0 - min_x if dir > 0 else 2.0 * span - (x0 - min_x)
	var p := fposmod(p0 + speed * t, 2.0 * span)
	return min_x + p if p < span else min_x + 2.0 * span - p

## A sine rather than a ping-pong, so the slab eases at both ends instead of
## snapping direction under the player's feet.
static func bob_y(home_y: float, phase: float, rate: float, amp: float, t: float) -> float:
	return home_y + sin(phase + rate * t) * amp

func _apply_motion() -> void:
	if _move_h:
		position.x = drift_x(_home_x, _dir, _min_x, _max_x, move_speed, _clock)
	if _move_v:
		position.y = bob_y(_home_y, _v_phase, _v_rate, _v_amp, _clock)

func _apply_visual_settings() -> void:
	if not is_instance_valid(visual):
		return
	var col := Settings.platform_color
	# Glass reads as glass by being see-through and dim, with bright edges the
	# decor draws on top of it. See GLASS_COLOR.
	if _glass:
		col = col.lerp(GLASS_COLOR, GLASS_BLEND)
		col.a = GLASS_ALPHA
	visual.color = col
	# RoundedRect.shine stays off here: its highlight is sized for the player's
	# body and on a slab it paints an off-centre lens taller than the platform.
	# Glass gets a sheen that stays inside its edges, and squishy gets a
	# cushion, both drawn by the decor.
	decor.configure(attributes, Vector2(width, visual.rect_size.y), Settings.platform_color)

func _apply_width() -> void:
	visual.rect_size.x = width
	var collision: CollisionShape2D = $CollisionShape2D
	var shape: RectangleShape2D = collision.shape.duplicate()
	shape.size.x = width
	collision.shape = shape

func _physics_process(delta: float) -> void:
	_clock += delta
	_apply_motion()

## Squishy platforms breathe on their own, so the attribute is readable before
## you touch one, and compress hard when landed on to confirm it. Invisible
## ones cycle their own visibility.
func _process(delta: float) -> void:
	if _squishy:
		# Clamped so a frame hitch cannot push the explicit-Euler spring past
		# its stability limit.
		var d := minf(delta, 0.05)
		_squish_t += d * SQUISH_IDLE_RATE
		_impact_vel += (-SQUISH_STIFFNESS * _impact - SQUISH_DAMPING * _impact_vel) * d
		_impact += _impact_vel * d
		var idle := (sin(_squish_t) * 0.5 + 0.5) * SQUISH_IDLE_AMOUNT
		decor.set_squish(clampf(idle + _impact, 0.0, 1.0))
	if _invisible:
		# Raw delta, not the clamped one: this is a wall-clock cycle, and the
		# hold times are what the player learns to time their jumps against.
		_phantom_t = fmod(_phantom_t + delta, PHANTOM_CYCLE)
		# modulate rather than `visible`, so the fades carry the decor with
		# them and a glass platform keeps its own translucency underneath.
		modulate.a = _phantom_alpha(_phantom_t)

func _phantom_alpha(t: float) -> float:
	if t < PHANTOM_VISIBLE_HOLD:
		return 1.0
	t -= PHANTOM_VISIBLE_HOLD
	if t < PHANTOM_FADE:
		return 1.0 - t / PHANTOM_FADE
	t -= PHANTOM_FADE
	if t < PHANTOM_GONE_HOLD:
		return 0.0
	return (t - PHANTOM_GONE_HOLD) / PHANTOM_FADE

func on_landed(player: Node, _boosted: bool, is_timed: bool) -> void:
	if _squishy:
		# Keyed off the timing rather than off `boosted`, so a perfect landing
		# on a platform whose streak boost is already spent is still rewarded.
		player.velocity.y *= SQUISH_BOOST if is_timed else SQUISH_PENALTY
		_impact = 1.0
		_impact_vel = 0.0
	if _glass:
		_break_apart()

func _break_apart() -> void:
	if _broken:
		return
	_broken = true
	remove_from_group("platforms")
	set_physics_process(false)
	set_process(false)
	var dur := 0.2
	var flat := Vector2(1.25, 0.1)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, dur)
	tw.parallel().tween_property(visual, "scale", flat, dur).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(decor, "scale", flat, dur).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(queue_free)
