extends Node2D
class_name Rival

## Another racer on the course, as the race screens see it: a translucent ghost
## of the character in the rival's colour with a name over its head, and the
## few numbers RaceHud reads (score, colour, respawning, position). What moves
## it is the subclass's business -- RaceBot simulates a climb of its own; a
## network rival (docs/lan-race.md) plays back what another device sends.
##
## Starts hidden and still. A subclass calls show_ghost() once it is placed.

## Translucent enough to read as a ghost, solid enough to keep its colour.
const GHOST_ALPHA := 0.75
## The character's bands with the white-hot core toned down: that core is what
## makes every skin read as a white dot at a glance, so on a rival it is kept
## faint and the rival colour carries the body.
const GHOST_CORE_WHITE := Color(0.35, 0.35, 0.3)
const LABEL_FONT := preload("res://fonts/Chillax-Bold.otf")
const LABEL_SIZE := 18
const LABEL_LIFT := 52.0
## Off-screen margin inside which the body is still drawn.
const DRAW_MARGIN := 120.0

var velocity: Vector2 = Vector2.ZERO
var score: int = 0
## Seconds left sitting out a fall, or 0 while racing.
var respawn_left: float = 0.0
var color: Color = Color.WHITE
## Over its head and on its HUD tag. A lone bot is only ever called "AI"; in
## a bigger field each one has a name (see game.gd:_setup_race).
var label: String = "AI"
## Over the line. A finished racer is out of everything: no items land on it
## and it is nobody's target.
var finished: bool = false
## For the race report (see race_history.gd): when it crossed the line on
## the race's clock (below zero until it has), how often it fell, the longest
## streak it held, and how many of game.gd's lead samples found it in front.
var finish_time: float = -1.0
var falls: int = 0
var best_streak: int = 0
var led_samples: int = 0
## The AI's look: the white-hot core toned down (GHOST_CORE_WHITE) so its
## colour carries. A LAN rival turns this off before entering the tree and
## wears its player's character exactly as they do.
var ghost_core: bool = true

var _visual: PlasmaBlob
var _squash: float = 0.0
var _squash_vel: float = 0.0

func _ready() -> void:
	z_index = 9
	modulate.a = GHOST_ALPHA
	_visual = PlasmaBlob.new()
	var bands: Array = PlasmaBlob.CHARACTER_BANDS.duplicate(true)
	if ghost_core:
		bands[bands.size() - 1]["white"] = GHOST_CORE_WHITE
	_visual.bands = bands
	add_child(_visual)
	visible = false
	set_process(false)

func is_respawning() -> bool:
	return respawn_left > 0.0

## Dresses the ghost in `color` and `shape` and puts it on screen.
func show_ghost(shape: PlasmaBlob.Shape) -> void:
	_visual.color = color
	_visual.shape = shape
	visible = true
	set_process(true)
	queue_redraw()

## The landing squash. 1.0 for a plain hop, more for a flare.
func squash(amount: float) -> void:
	_squash = amount
	_squash_vel = 0.0

## Visual-only. The body is only drawn while near the screen: PlasmaBlob
## redraws every frame, and a rival can spend most of a race out of view.
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
	var extents := LABEL_FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE)
	draw_string(LABEL_FONT, Vector2(-extents.x / 2.0, -LABEL_LIFT), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, color)
