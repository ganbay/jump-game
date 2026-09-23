extends Node2D

@export var platform_scene: PackedScene
## How far from each screen edge a platform's centre may be placed.
@export var edge_margin: float = 50.0
@export var min_gap: float = 90.0
@export var max_gap: float = 160.0
@export var min_gap_cap: float = 150.0
@export var max_gap_cap: float = 240.0
@export var platform_width: float = 90.0
@export var platform_width_min: float = 50.0
@export var gap_step: float = 10.0
@export var width_step: float = 1.0

# 1000 score points = 10000px climbed, since score = height / 10 (see game.gd).
const DIFFICULTY_STEP_HEIGHT := 10000.0

## Headroom above the top of the screen that the spawn frontier keeps. Added to
## half the screen height rather than baked into a single distance, so a taller
## display gets the same margin instead of building platforms nearly in view.
const SPAWN_MARGIN := 360.0

## How far below the bottom of the screen a platform must fall before it is
## freed. The player dies at half a screen + 80px below the camera, so nothing
## past this line is ever reachable or visible again.
const DESPAWN_MARGIN := 200.0

## The attribute a platform rolls naturally, before its zone adds one. Index
## 0 is "no attribute", which stays the most likely outcome throughout -- a
## platform normally carries one attribute, not a pile of them.
const NATURAL_ATTRS := [
	0,
	Platform.Attr.MOVE_H,
	Platform.Attr.MOVE_V,
	Platform.Attr.GLASS,
	Platform.Attr.INVISIBLE,
	Platform.Attr.SQUISHY,
]
const NATURAL_WEIGHTS_START := [0.55, 0.20, 0.05, 0.10, 0.06, 0.05]
const NATURAL_WEIGHTS_END := [0.28, 0.20, 0.14, 0.16, 0.12, 0.10]
const NATURAL_RAMP_HEIGHT := 12000.0

## Every platform the run has placed, as data, lowest first. The nodes are
## only ever built from these, and only near the player -- but a race bot can
## be thousands of pixels away in either direction, so it climbs this list
## rather than the live nodes (see race_bot.gd and ensure_course()). A few
## hundred small objects even on a long climb, so nothing is ever trimmed.
var course: Array[CourseSlot] = []
## Seconds of play since begin(). Moving platforms are positioned from this
## rather than integrated per node, so where one is at any moment is a pure
## function of its slot -- which is what lets the bot land on platforms that
## have no node yet, or no longer have one.
var course_time: float = 0.0

var _highest_y: float = 100.0
## Index into `course` of the next slot to build a node for.
var _next_node: int = 0
var player: Node2D
## Set by game.gd. Platform attributes are chosen from the score a platform
## will be worth when reached, which has to be measured from the same origin
## the HUD counts from or zones would drift out of step with their banners.
var score_origin_y: float = 0.0
var zones: ZoneDirector
## Spawned platforms in the order they were created, i.e. sorted from lowest
## (largest y) to highest, so despawning only ever pops from the front.
var _live: Array[Node2D] = []
var _half_screen_height: float = 640.0
## Both read from the viewport in _ready. Under the project's `expand` stretch
## the base 720x1280 is only a floor: height grows on a tall phone and width
## grows on a tablet, so neither can be a constant.
var _screen_width: float = 720.0
var _spawn_lookahead: float = 1000.0
## Where this run started. Difficulty is measured as distance climbed from here,
## not from world zero -- the intro hands over thousands of pixels up, so an
## absolute reading would open the run at maximum difficulty.
var _origin_y: float = 0.0
## A moving platform's speeds, read off the scene once so the slot maths below
## and the nodes themselves can never disagree about them.
var _h_speed: float = 110.0
var _v_speed: float = 95.0
var _v_amp: float = 60.0

## One platform of the course. `dir` and `v_phase` are rolled here rather than
## by the node, because anything that predicts where the platform will be has
## to know them before the node exists.
class CourseSlot:
	var x: float
	var y: float
	var width: float
	var attributes: int
	var dir: int
	var v_phase: float

	func has_attr(attr: int) -> bool:
		return attributes & attr != 0

func _ready() -> void:
	randomize()
	player = get_tree().get_first_node_in_group("player")
	var view := get_viewport_rect().size
	_screen_width = view.x
	_half_screen_height = view.y / 2.0
	_spawn_lookahead = _half_screen_height + SPAWN_MARGIN
	if platform_scene != null:
		var probe: Platform = platform_scene.instantiate()
		_h_speed = probe.move_speed
		_v_speed = probe.move_v_speed
		_v_amp = probe.move_v_distance / 2.0
		probe.free()
	# Held until the intro finishes; game.gd calls begin().
	set_process(false)
	set_physics_process(false)

## Starts generating from `from_y` upward. game.gd seeds this above the top of
## the screen so the first platform is built off-camera and scrolls into view,
## rather than a batch of them existing before the run has started.
##
## Also a full reset: the trailer throws the field away and calls this again.
func begin(from_y: float) -> void:
	_highest_y = from_y
	_origin_y = from_y
	course.clear()
	_next_node = 0
	course_time = 0.0
	set_process(true)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	course_time += delta

func _climbed() -> float:
	return maxf(_origin_y - _highest_y, 0.0)

## The score the platform now being placed will be worth once it is reached.
func _frontier_score() -> int:
	return int(maxf(score_origin_y - _highest_y, 0.0) / 10.0)

func _process(_delta: float) -> void:
	if player == null:
		return
	var frontier := player.global_position.y - _spawn_lookahead
	ensure_course(frontier)
	# A slot is built once the one below it is under the frontier -- the same
	# rule that used to decide when to spawn, so the first platform past the
	# frontier still exists as a node, as it always has.
	while _next_node < course.size() \
			and (_next_node == 0 or course[_next_node - 1].y > frontier):
		_build(course[_next_node])
		_next_node += 1
	_despawn_below_camera()

## Extends the course, as data only, until it reaches above `top_y`.
func ensure_course(top_y: float) -> void:
	while _highest_y > top_y:
		_add_slot()

## Where a slot's platform is at `time` (course_time). Mirrors what
## platform.gd does with the same numbers, so the two agree to the pixel.
func slot_position(slot: CourseSlot, time: float) -> Vector2:
	var pos := Vector2(slot.x, slot.y)
	if slot.has_attr(Platform.Attr.MOVE_H):
		var half := slot.width / 2.0
		pos.x = Platform.drift_x(slot.x, slot.dir, half, _screen_width - half, _h_speed, time)
	if slot.has_attr(Platform.Attr.MOVE_V):
		pos.y = Platform.bob_y(slot.y, slot.v_phase, _v_speed / maxf(_v_amp, 1.0), _v_amp, time)
	return pos

## Without this, platforms accumulated for the whole run: a few hundred nodes
## by a long climb, each one a live Area2D that the player's landing scan walks
## every physics frame.
func _despawn_below_camera() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var cutoff := cam.global_position.y + _half_screen_height + DESPAWN_MARGIN
	while not _live.is_empty():
		var plat: Node2D = _live[0]
		if is_instance_valid(plat):
			if plat.global_position.y <= cutoff:
				break
			plat.queue_free()
		_live.pop_front()

func _difficulty_level() -> int:
	return int(floor(_climbed() / DIFFICULTY_STEP_HEIGHT))

func _add_slot() -> void:
	var level := _difficulty_level()
	var cur_min_gap := minf(min_gap + gap_step * level, min_gap_cap)
	var cur_max_gap := minf(max_gap + gap_step * level, max_gap_cap)
	_highest_y -= randf_range(cur_min_gap, cur_max_gap)
	var slot := CourseSlot.new()
	slot.x = randf_range(edge_margin, _screen_width - edge_margin)
	slot.y = _highest_y
	slot.attributes = _pick_attributes()
	slot.width = maxf(platform_width - width_step * level, platform_width_min)
	slot.dir = 1 if randf() < 0.5 else -1
	slot.v_phase = randf() * TAU
	course.append(slot)

func _build(slot: CourseSlot) -> void:
	var plat: Platform = platform_scene.instantiate()
	plat.position = Vector2(slot.x, slot.y)
	plat.attributes = slot.attributes
	plat.width = slot.width
	plat.set_motion(slot.dir, slot.v_phase, course_time)
	add_child(plat)
	_live.append(plat)

func _pick_attributes() -> int:
	var score := _frontier_score()
	if score < 1000:
		return 0
	var forced := zones.attrs_for_score(score) if zones != null else 0
	return forced | _roll_natural()

func _roll_natural() -> int:
	var t := clampf(_climbed() / NATURAL_RAMP_HEIGHT, 0.0, 1.0)
	var total := 0.0
	for i in range(NATURAL_ATTRS.size()):
		total += lerpf(NATURAL_WEIGHTS_START[i], NATURAL_WEIGHTS_END[i], t)
	var r := randf() * total
	for i in range(NATURAL_ATTRS.size()):
		r -= lerpf(NATURAL_WEIGHTS_START[i], NATURAL_WEIGHTS_END[i], t)
		if r <= 0.0:
			return NATURAL_ATTRS[i]
	return 0
