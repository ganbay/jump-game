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

var _highest_y: float = 100.0
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

func _ready() -> void:
	randomize()
	player = get_tree().get_first_node_in_group("player")
	var view := get_viewport_rect().size
	_screen_width = view.x
	_half_screen_height = view.y / 2.0
	_spawn_lookahead = _half_screen_height + SPAWN_MARGIN
	# Held until the intro finishes; game.gd calls begin().
	set_process(false)

## Starts generating from `from_y` upward. game.gd seeds this above the top of
## the screen so the first platform is built off-camera and scrolls into view,
## rather than a batch of them existing before the run has started.
func begin(from_y: float) -> void:
	_highest_y = from_y
	_origin_y = from_y
	set_process(true)

func _climbed() -> float:
	return maxf(_origin_y - _highest_y, 0.0)

## The score the platform now being placed will be worth once it is reached.
func _frontier_score() -> int:
	return int(maxf(score_origin_y - _highest_y, 0.0) / 10.0)

func _process(_delta: float) -> void:
	if player == null:
		return
	while _highest_y > player.global_position.y - _spawn_lookahead:
		_spawn_next()
	_despawn_below_camera()

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

func _spawn_next() -> void:
	var level := _difficulty_level()
	var cur_min_gap := minf(min_gap + gap_step * level, min_gap_cap)
	var cur_max_gap := minf(max_gap + gap_step * level, max_gap_cap)
	_highest_y -= randf_range(cur_min_gap, cur_max_gap)
	var plat := platform_scene.instantiate()
	plat.position = Vector2(
		randf_range(edge_margin, _screen_width - edge_margin), _highest_y)
	plat.attributes = _pick_attributes()
	plat.width = maxf(platform_width - width_step * level, platform_width_min)
	add_child(plat)
	_live.append(plat)

func _pick_attributes() -> int:
	var forced := zones.attrs_for_score(_frontier_score()) if zones != null else 0
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
