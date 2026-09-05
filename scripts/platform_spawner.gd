extends Node2D

@export var platform_scene: PackedScene
@export var screen_width: float = 720.0
@export var min_gap: float = 90.0
@export var max_gap: float = 160.0

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

func _spawn_next() -> void:
	_highest_y -= randf_range(min_gap, max_gap)
	var plat := platform_scene.instantiate()
	plat.position = Vector2(randf_range(50.0, screen_width - 50.0), _highest_y)
	plat.type = _pick_type()
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
