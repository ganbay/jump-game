extends Node2D

@export var platform_scene: PackedScene
@export var screen_width: float = 720.0
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

## How far below the bottom of the screen a platform must fall before it is
## freed. The player dies at half a screen + 80px below the camera, so nothing
## past this line is ever reachable or visible again.
const DESPAWN_MARGIN := 200.0

var _highest_y: float = 100.0
var player: Node2D
## Spawned platforms in the order they were created, i.e. sorted from lowest
## (largest y) to highest, so despawning only ever pops from the front.
var _live: Array[Node2D] = []
var _half_screen_height: float = 640.0
## Where this run started. Difficulty is measured as distance climbed from here,
## not from world zero -- the intro hands over thousands of pixels up, so an
## absolute reading would open the run at maximum difficulty.
var _origin_y: float = 0.0

func _ready() -> void:
	randomize()
	player = get_tree().get_first_node_in_group("player")
	_half_screen_height = get_viewport_rect().size.y / 2.0
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

func _process(_delta: float) -> void:
	if player == null:
		return
	while _highest_y > player.global_position.y - 1000.0:
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
	plat.position = Vector2(randf_range(50.0, screen_width - 50.0), _highest_y)
	plat.type = _pick_type()
	plat.width = maxf(platform_width - width_step * level, platform_width_min)
	add_child(plat)
	_live.append(plat)

func _pick_type() -> int:
	var t := clampf(_climbed() / 4000.0, 0.0, 1.0)
	var w_still := lerpf(0.55, 0.25, t)
	var w_moving := lerpf(0.20, 0.35, t)
	var w_boost := lerpf(0.15, 0.15, t)
	var w_one_time := lerpf(0.10, 0.25, t)
	var total := w_still + w_moving + w_boost + w_one_time
	var r := randf() * total
	if r < w_still:
		return 0
	r -= w_still
	if r < w_moving:
		return 1
	r -= w_moving
	if r < w_boost:
		return 2
	return 3
