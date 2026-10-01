extends Control
class_name RaceHud

## Race-mode readouts, all drawn in one _draw rather than built from Labels:
##
## - A progress rail down the right edge, start at the bottom and the finish
##   flag at the top, with a dot for each racer. The whole race at a glance.
## - A tag for each rival whenever it is off screen, pinned to the edge it is
##   past, carrying the gap in score: "AI +1,240" means that rival is 1,240
##   ahead. Tags on the same edge stack rather than overlap, the closest
##   rivals first and at most MAX_TAGS_PER_EDGE of them; the rest are counted
##   on a "+N MORE" line, so a full LAN room cannot bury the screen. While a
##   rival is on screen its ghost carries its own label instead.
## - The respawn countdown after the player falls.
## - In a LAN race, once someone has finished, how long the rest have left.
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
## Between two tags stacked on the same edge.
const TAG_STACK_GAP := 6.0
const MAX_TAGS_PER_EDGE := 2
const MORE_FONT_SIZE := 18
const MORE_COLOR := Color(1.0, 1.0, 1.0, 0.7)

const COUNTDOWN_FONT_SIZE := 44
const COUNTDOWN_Y := 0.42
const CLOSING_FONT_SIZE := 24
const CLOSING_Y := 0.2
const CLOSING_COLOR := Color(1.4, 1.4, 1.4, 0.9)

var player: Node2D
## Everyone the player is racing (see rival.gd).
var rivals: Array[Rival] = []
var camera: Camera2D
var target: int = 10000
var player_score: int = 0
var player_color: Color = Color.WHITE
## Seconds left on the player's own respawn penalty, or 0.
var player_respawn_left: float = 0.0
## Seconds until a LAN race closes, or below zero while nobody has finished.
var closing_left: float = -1.0

## What was drawn last, so a frame that would draw the same thing skips it.
var _last_key: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	if rivals.is_empty() or player == null or camera == null:
		return
	var key := [player_score, ceili(player_respawn_left), player_color, size, ceili(closing_left)]
	for rival in rivals:
		key.append_array([rival.score, int(_screen_pos(rival).x), _edge(rival),
			rival.is_respawning(), rival.color, rival.label])
	if key == _last_key:
		return
	_last_key = key
	queue_redraw()

func _screen_pos(rival: Rival) -> Vector2:
	var half := get_viewport_rect().size / 2.0
	return rival.global_position - camera.global_position + half

## -1 above the screen, 1 below it, 0 on it.
func _edge(rival: Rival) -> int:
	var y := _screen_pos(rival).y
	if y < 0.0:
		return -1
	if y > size.y:
		return 1
	return 0

func _draw() -> void:
	if rivals.is_empty():
		return
	_draw_rail()
	_draw_rival_tags()
	if player_respawn_left > 0.0:
		_draw_centered("RESPAWN %d" % ceili(player_respawn_left),
			Vector2(size.x / 2.0, size.y * COUNTDOWN_Y), COUNTDOWN_FONT_SIZE, player_color)
	if closing_left >= 0.0:
		_draw_centered("FINISH CLOSES IN %d" % ceili(closing_left),
			Vector2(size.x / 2.0, size.y * CLOSING_Y), CLOSING_FONT_SIZE, CLOSING_COLOR)

func _draw_rail() -> void:
	var x := size.x - RAIL_MARGIN_X
	var top := RAIL_TOP
	var bottom := size.y - RAIL_BOTTOM_MARGIN
	draw_line(Vector2(x, top), Vector2(x, bottom), RAIL_COLOR, RAIL_WIDTH)
	# The finish: a small pennant off the top of the rail.
	draw_colored_polygon(PackedVector2Array([
		Vector2(x, top - FLAG_SIZE), Vector2(x - FLAG_SIZE, top - FLAG_SIZE * 0.5),
		Vector2(x, top)]), Color(1.9, 1.9, 2.0))
	# The rivals' dots first, so the player's own is on top when they tie.
	for rival in rivals:
		_draw_rail_dot(x, top, bottom, rival.score, rival.color)
	_draw_rail_dot(x, top, bottom, player_score, player_color)

func _draw_rail_dot(x: float, top: float, bottom: float, score: int, color: Color) -> void:
	var t := clampf(float(score) / float(maxi(target, 1)), 0.0, 1.0)
	draw_circle(Vector2(x, lerpf(bottom, top, t)), DOT_RADIUS, color)

## Top-edge tags (and a respawning rival's, which has no position worth
## pointing at) stack downward from TAG_TOP; bottom-edge tags stack upward.
## Each edge shows its closest rivals -- the ones the player is actually
## racing -- and counts the rest.
func _draw_rival_tags() -> void:
	var above: Array[Rival] = []
	var below: Array[Rival] = []
	for rival in rivals:
		var edge := _edge(rival)
		if edge == 0 and not rival.is_respawning():
			continue
		if edge > 0:
			below.append(rival)
		else:
			above.append(rival)
	var closest_first := func(a: Rival, b: Rival) -> bool:
		return absi(a.score - player_score) < absi(b.score - player_score)
	above.sort_custom(closest_first)
	below.sort_custom(closest_first)
	var next_top := TAG_TOP
	for i in range(mini(above.size(), MAX_TAGS_PER_EDGE)):
		next_top = _draw_rival_tag(above[i], next_top, true).end.y + TAG_STACK_GAP
	if above.size() > MAX_TAGS_PER_EDGE:
		_draw_more(above.size() - MAX_TAGS_PER_EDGE, next_top, true)
	var next_bottom := size.y - TAG_BOTTOM_MARGIN
	for i in range(mini(below.size(), MAX_TAGS_PER_EDGE)):
		next_bottom = _draw_rival_tag(below[i], next_bottom, false).position.y - TAG_STACK_GAP
	if below.size() > MAX_TAGS_PER_EDGE:
		_draw_more(below.size() - MAX_TAGS_PER_EDGE, next_bottom, false)

## Draws `rival`'s tag hanging down from `y` (`downward`) or standing up on
## it, and returns the box it took.
func _draw_rival_tag(rival: Rival, y: float, downward: bool) -> Rect2:
	var edge := _edge(rival)
	var text := _tag_text(rival)
	var extents := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TAG_FONT_SIZE)
	var arrow_room := ARROW_SIZE * 2.0 + 8.0 if edge != 0 else 0.0
	var box_size := extents + TAG_PAD * 2.0 + Vector2(arrow_room, 0.0)
	var cx := clampf(_screen_pos(rival).x, TAG_EDGE_MARGIN, size.x - TAG_EDGE_MARGIN)
	var top := y if downward else y - box_size.y
	var box := Rect2(Vector2(cx - box_size.x / 2.0, top), box_size)
	_draw_tag(rival, text, edge, box, arrow_room)
	return box

func _draw_more(count: int, y: float, downward: bool) -> void:
	var text := "+%d MORE" % count
	var ascent := FONT.get_ascent(MORE_FONT_SIZE)
	var baseline := y + ascent if downward else y - FONT.get_descent(MORE_FONT_SIZE)
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, MORE_FONT_SIZE).x
	draw_string(FONT, Vector2((size.x - width) / 2.0, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, MORE_FONT_SIZE, MORE_COLOR)

func _tag_text(rival: Rival) -> String:
	if rival.is_respawning():
		return "%s RESPAWN" % rival.label
	var gap := rival.score - player_score
	return "%s %s%s" % [rival.label, "+" if gap >= 0 else "-", _thousands(absi(gap))]

func _draw_tag(rival: Rival, text: String, edge: int, box: Rect2, arrow_room: float) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = TAG_FILL
	fill.set_corner_radius_all(10)
	fill.border_color = rival.color
	fill.set_border_width_all(2)
	draw_style_box(fill, box)
	var text_x := box.position.x + TAG_PAD.x
	if edge != 0:
		# Pointing the way the rival is: up when it is above the screen.
		var c := Vector2(box.position.x + TAG_PAD.x + ARROW_SIZE, box.get_center().y)
		var s := ARROW_SIZE * float(edge)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-ARROW_SIZE, -s * 0.6), c + Vector2(ARROW_SIZE, -s * 0.6),
			c + Vector2(0.0, s * 0.8)]), rival.color)
		text_x += arrow_room
	var baseline := box.position.y + TAG_PAD.y + FONT.get_ascent(TAG_FONT_SIZE)
	draw_string(FONT, Vector2(text_x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, TAG_FONT_SIZE, rival.color)

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
