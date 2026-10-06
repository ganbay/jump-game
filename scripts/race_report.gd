extends Control
class_name RaceReport

## One race, laid out: where this phone placed, what kind of race it was, a
## line per racer in finishing order, and the few things that stood out (see
## RaceHistory.notes). Opened over the finish screen straight after a race,
## and from the history list for an old one -- the same record, the same
## screen.
##
## Everything but the CLOSE button is drawn in one _draw, as the race HUD is:
## a table is columns, and columns are easier placed than laid out.

const FONT := preload("res://fonts/Chillax-Bold.otf")

const DIM := Color(0.0, 0.0, 0.0, 0.96)
const MAX_WIDTH := 680.0
const SIDE_MARGIN := 20.0
const TOP := 0.07
const TITLE_SIZE := 50
const SUMMARY_SIZE := 22
const DATE_SIZE := 16
const HEADER_SIZE := 14
const ROW_SIZE := 20
const ROW_HEIGHT := 44.0
const NOTE_SIZE := 19
const NOTE_HEIGHT := 30.0
const QUIET := Color(1.0, 1.0, 1.0, 0.55)
const PLAIN := Color(1.0, 1.0, 1.0, 0.92)
const RULE := Color(1.0, 1.0, 1.0, 0.14)
const MINE_FILL := Color(1.0, 1.0, 1.0, 0.09)
const TAG_TEXT := Color(0.0, 0.0, 0.0)
const TAG_PAD := Vector2(10.0, 4.0)

## The columns after the racer's name: [heading, record key, centre as a
## fraction of the table's width]. With item boxes on, the item columns take
## the place of the share of the race spent in front -- that one is in the
## notes anyway, and nine columns do not fit a phone.
const COLUMNS_PLAIN := [["TIME", "time", 0.5], ["FALLS", "falls", 0.66],
	["STREAK", "streak", 0.8], ["LED", "led", 0.94]]
const COLUMNS_ITEMS := [["TIME", "time", 0.43], ["FALLS", "falls", 0.57],
	["STREAK", "streak", 0.68], ["HITS", "hits", 0.78], ["TAKEN", "taken", 0.87],
	["BLOCKS", "blocks", 0.96]]
const PLACE_X := 0.0
const NAME_X := 0.1
## The name gives way this far short of the first column's centre.
const NAME_CLEARANCE := 60.0

var record: Dictionary = {}

var _close_button: Button

static func open(parent: Node, new_record: Dictionary) -> RaceReport:
	var report := RaceReport.new()
	report.record = new_record
	parent.add_child(report)
	return report

func _ready() -> void:
	# The finish screen it opens over has the tree paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_close_button = Button.new()
	_close_button.text = "CLOSE"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.add_theme_font_size_override("font_size", 28)
	_close_button.anchor_left = 0.5
	_close_button.anchor_right = 0.5
	_close_button.anchor_top = 0.92
	_close_button.anchor_bottom = 0.92
	_close_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_close_button.grow_vertical = Control.GROW_DIRECTION_BOTH
	_close_button.pressed.connect(_on_close_pressed)
	add_child(_close_button)
	UiPlate.action(_close_button)
	resized.connect(queue_redraw)

func _on_close_pressed() -> void:
	Audio.play_ui_click()
	queue_free()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var width := minf(size.x - SIDE_MARGIN * 2.0, MAX_WIDTH)
	var left := (size.x - width) / 2.0
	var mid := size.x / 2.0
	var y := size.y * TOP + FONT.get_ascent(TITLE_SIZE)
	_text(RaceHistory.headline(record), mid, y, TITLE_SIZE, UiAccent.color(), 0)
	y += 46.0
	_draw_summary(mid, y)
	y += 30.0
	_text(RaceHistory.date(record), mid, y, DATE_SIZE, QUIET, 0)
	y += 44.0
	y = _draw_table(left, width, y)
	y += 34.0
	for line in RaceHistory.notes(record):
		_text(line, mid, y, NOTE_SIZE, PLAIN, 0)
		y += NOTE_HEIGHT

## The mode tag, then what kind of race it was, centred as one line.
func _draw_summary(mid: float, baseline: float) -> void:
	var tag := RaceHistory.mode_tag(record)
	var summary := RaceHistory.summary(record)
	var tag_width := FONT.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, HEADER_SIZE + 2).x \
		+ TAG_PAD.x * 2.0
	var summary_width := FONT.get_string_size(summary, HORIZONTAL_ALIGNMENT_LEFT, -1.0, SUMMARY_SIZE).x
	var gap := 14.0
	var x := mid - (tag_width + gap + summary_width) / 2.0
	draw_tag(self, tag, RaceHistory.mode_color(record), Vector2(x, baseline), HEADER_SIZE + 2)
	_text(summary, x + tag_width + gap, baseline, SUMMARY_SIZE, PLAIN, -1)

## Returns the y under the last row.
func _draw_table(left: float, width: float, top: float) -> float:
	var columns: Array = COLUMNS_ITEMS if record.get("items", false) else COLUMNS_PLAIN
	var y := top
	_text("RACER", left + width * NAME_X, y, HEADER_SIZE, QUIET, -1)
	for column in columns:
		_text(column[0], left + width * float(column[2]), y, HEADER_SIZE, QUIET, 0)
	y += 12.0
	draw_line(Vector2(left, y), Vector2(left + width, y), RULE, 2.0)
	var name_room: float = width * (float(columns[0][2]) - NAME_X) - NAME_CLEARANCE
	var racers: Array = record.get("racers", [])
	var unfinished := false
	for i in range(racers.size()):
		var entry: Dictionary = racers[i]
		var row := Rect2(left - 8.0, y, width + 16.0, ROW_HEIGHT)
		if entry.get("me", false):
			draw_rect(row, MINE_FILL)
		var baseline := y + ROW_HEIGHT / 2.0 + FONT.get_ascent(ROW_SIZE) * 0.38
		var color: Color = entry.get("color", Color.WHITE)
		_text(RaceHistory.ordinal(i + 1), left + width * PLACE_X, baseline, ROW_SIZE, QUIET, -1)
		draw_string(FONT, Vector2(left + width * NAME_X, baseline), str(entry.get("name", "?")),
			HORIZONTAL_ALIGNMENT_LEFT, name_room, ROW_SIZE, color)
		for column in columns:
			var key: String = column[1]
			var cell := _cell(entry, key)
			var dim := key == "time" and float(entry.get("time", -1.0)) < 0.0
			unfinished = unfinished or dim
			_text(cell, left + width * float(column[2]), baseline, ROW_SIZE,
				QUIET if dim or cell == "-" else PLAIN, 0)
		y += ROW_HEIGHT
	draw_line(Vector2(left, y), Vector2(left + width, y), RULE, 2.0)
	if unfinished:
		y += 24.0
		_text("GREY: NEVER CROSSED THE LINE -- THE SCORE THEY REACHED", size.x / 2.0, y,
			HEADER_SIZE, QUIET, 0)
	return y

func _cell(entry: Dictionary, key: String) -> String:
	match key:
		"time":
			var time: float = entry.get("time", -1.0)
			if time >= 0.0:
				return RaceHistory.race_time(time)
			return RaceHistory.thousands(int(entry.get("score", 0)))
		"led":
			var share: float = entry.get("led", 0.0)
			return "%d%%" % roundi(share * 100.0) if share >= 0.005 else "-"
	var value := int(entry.get(key, 0))
	return str(value) if value > 0 else "-"

## `align` -1 starts the text at x, 0 centres it there, 1 ends it there.
func _text(text: String, x: float, baseline: float, font_size: int, color: Color, align: int) -> void:
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var at := x - width * 0.5 * float(align + 1)
	draw_string(FONT, Vector2(at, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

## The mode tag: dark text on a pill of the mode's colour, its text starting
## TAG_PAD.x in from `at` on the given baseline. Shared with the history list.
static func draw_tag(ci: CanvasItem, text: String, color: Color, at: Vector2, font_size: int) -> void:
	var extents := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var ascent := FONT.get_ascent(font_size)
	var pill := StyleBoxFlat.new()
	pill.bg_color = color
	pill.set_corner_radius_all(8)
	ci.draw_style_box(pill, Rect2(at.x, at.y - ascent - TAG_PAD.y,
		extents.x + TAG_PAD.x * 2.0, ascent + FONT.get_descent(font_size) + TAG_PAD.y * 2.0))
	ci.draw_string(FONT, Vector2(at.x + TAG_PAD.x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, font_size, TAG_TEXT)
