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

var _highest_y: float = 100.0
var player: Node2D

func _ready() -> void:
	randomize()
	player = get_tree().get_first_node_in_group("player")
	_highest_y = 100.0
	for i in range(12):
		_spawn_next()

func _process(_delta: float) -> void:
	if player == null:
		return
	while _highest_y > player.global_position.y - 1000.0:
		_spawn_next()

func _difficulty_level() -> int:
	return int(floor(maxf(-_highest_y, 0.0) / DIFFICULTY_STEP_HEIGHT))

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

func _pick_type() -> int:
	var t := clampf(-_highest_y / 4000.0, 0.0, 1.0)
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
