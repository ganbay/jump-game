extends Control
class_name RaceHud

## Race-mode readouts, all drawn in one _draw rather than built from Labels:
##
## - A progress rail down the right edge, start at the bottom and the finish
##   flag at the top, with a dot for each racer. The whole race at a glance.
## - A tag for the bot whenever it is off screen, pinned to the edge it is
##   past, carrying the gap in score: "AI +1,240" means the bot is 1,240
##   ahead. (Players only ever see the bot called "AI".) While it is on
##   screen the ghost carries its own label instead.
## - The respawn countdown after the player falls.
##
## Redrawn only when something it shows has changed, not every frame.

const FONT := preload("res://fonts/Chillax-Bold.otf")

const RAIL_MARGIN_X := 18.0
const RAIL_TOP := 130.0
const RAIL_BOTTOM_MARGIN := 150.0
const RAIL_WIDTH := 3.0
const RAIL_COLOR := Color(1.0, 1.0, 1.0, 0.28)
const DOT_RADIUS := 7.0
const FLAG_SIZE := 14.0

const TAG_FONT_SIZE := 22
const TAG_TOP := 104.0
const TAG_BOTTOM_MARGIN := 70.0
const TAG_EDGE_MARGIN := 80.0
const TAG_PAD := Vector2(12.0, 6.0)
const TAG_FILL := Color(0.0, 0.0, 0.0, 0.55)
const ARROW_SIZE := 9.0

const COUNTDOWN_FONT_SIZE := 44
const COUNTDOWN_Y := 0.42

var player: Node2D
var bot: RaceBot
var camera: Camera2D
var target: int = 10000
var player_score: int = 0
var player_color: Color = Color.WHITE
## Seconds left on the player's own respawn penalty, or 0.
var player_respawn_left: float = 0.0

## What was drawn last, so a frame that would draw the same thing skips it.
var _last_key: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	if bot == null or player == null or camera == null:
		return
	var key := [player_score, bot.score, int(_bot_screen_pos().x), _bot_edge(),
		bot.is_respawning(), ceili(player_respawn_left), player_color, bot.color, size]
	if key == _last_key:
		return
	_last_key = key
	queue_redraw()

func _bot_screen_pos() -> Vector2:
	var half := get_viewport_rect().size / 2.0
	return bot.global_position - camera.global_position + half

## -1 above the screen, 1 below it, 0 on it.
func _bot_edge() -> int:
	var y := _bot_screen_pos().y
	if y < 0.0:
		return -1
	if y > size.y:
		return 1
	return 0

func _draw() -> void:
	if bot == null:
		return
	_draw_rail()
	_draw_bot_tag()
	if player_respawn_left > 0.0:
		_draw_centered("RESPAWN %d" % ceili(player_respawn_left),
			Vector2(size.x / 2.0, size.y * COUNTDOWN_Y), COUNTDOWN_FONT_SIZE, player_color)

func _draw_rail() -> void:
	var x := size.x - RAIL_MARGIN_X
	var top := RAIL_TOP
	var bottom := size.y - RAIL_BOTTOM_MARGIN
	draw_line(Vector2(x, top), Vector2(x, bottom), RAIL_COLOR, RAIL_WIDTH)
	# The finish: a small pennant off the top of the rail.
	draw_colored_polygon(PackedVector2Array([
		Vector2(x, top - FLAG_SIZE), Vector2(x - FLAG_SIZE, top - FLAG_SIZE * 0.5),
		Vector2(x, top)]), Color(1.9, 1.9, 2.0))
	# The bot's dot first, so the player's own is on top when they tie.
	_draw_rail_dot(x, top, bottom, bot.score, bot.color)
	_draw_rail_dot(x, top, bottom, player_score, player_color)

func _draw_rail_dot(x: float, top: float, bottom: float, score: int, color: Color) -> void:
	var t := clampf(float(score) / float(maxi(target, 1)), 0.0, 1.0)
	draw_circle(Vector2(x, lerpf(bottom, top, t)), DOT_RADIUS, color)

func _draw_bot_tag() -> void:
	var edge := _bot_edge()
	if edge == 0 and not bot.is_respawning():
		return
	var gap := bot.score - player_score
	var text := "AI RESPAWN" if bot.is_respawning() else "AI %s%s" % [
		"+" if gap >= 0 else "-", _thousands(absi(gap))]
	var extents := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TAG_FONT_SIZE)
	var arrow_room := ARROW_SIZE * 2.0 + 8.0 if edge != 0 else 0.0
	var box_size := extents + TAG_PAD * 2.0 + Vector2(arrow_room, 0.0)
	var cx := clampf(_bot_screen_pos().x, TAG_EDGE_MARGIN, size.x - TAG_EDGE_MARGIN)
	var top := TAG_TOP if edge <= 0 else size.y - TAG_BOTTOM_MARGIN - box_size.y
	var box := Rect2(Vector2(cx - box_size.x / 2.0, top), box_size)
	var fill := StyleBoxFlat.new()
	fill.bg_color = TAG_FILL
	fill.set_corner_radius_all(10)
	fill.border_color = bot.color
	fill.set_border_width_all(2)
	draw_style_box(fill, box)
	var text_x := box.position.x + TAG_PAD.x
	if edge != 0:
		# Pointing the way the bot is: up when it is above the screen.
		var c := Vector2(box.position.x + TAG_PAD.x + ARROW_SIZE, box.get_center().y)
		var s := ARROW_SIZE * float(edge)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-ARROW_SIZE, -s * 0.6), c + Vector2(ARROW_SIZE, -s * 0.6),
			c + Vector2(0.0, s * 0.8)]), bot.color)
		text_x += arrow_room
	var baseline := box.position.y + TAG_PAD.y + FONT.get_ascent(TAG_FONT_SIZE)
	draw_string(FONT, Vector2(text_x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, TAG_FONT_SIZE, bot.color)

func _draw_centered(text: String, centre: Vector2, font_size: int, color: Color) -> void:
	var extents := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(FONT, centre - Vector2(extents.x / 2.0, -extents.y / 4.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

static func _thousands(value: int) -> String:
	var digits := str(value)
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return digits + out
