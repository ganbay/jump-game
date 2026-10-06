extends Control
class_name RaceHistoryPanel

## The races on record (see race_history.gd), newest first, over the race
## screen. Each row wears its mode's tag -- VS AI or LAN, in that mode's
## colour -- and the row of buttons above the list narrows it to one kind. A
## tap on a row opens that race's report (race_report.gd).

const DIM := Color(0.0, 0.0, 0.0, 0.96)
const MAX_WIDTH := 680.0
const TITLE_SIZE := 40
const FILTER_FONT_SIZE := 20
const FILTER_HEIGHT := 52.0
const EMPTY_COLOR := Color(1.0, 1.0, 1.0, 0.6)

## What the list is narrowed to: "" for every race, or a RaceHistory mode.
const FILTERS := ["", RaceHistory.MODE_AI, RaceHistory.MODE_LAN]
const FILTER_NAMES := ["ALL", "VS AI", "LAN"]

var _races: Array = []
var _filter: int = 0
var _filter_buttons: Array[Button] = []
var _list: VBoxContainer
var _empty_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_races = RaceHistory.load_all()
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var title := Label.new()
	title.text = "RACE HISTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_SIZE)
	title.add_theme_color_override("font_color", UiAccent.color())
	_span(title, 0.05, 0.11)
	add_child(title)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 12)
	_span(filters, 0.125, 0.125)
	filters.offset_bottom = FILTER_HEIGHT
	add_child(filters)
	for i in range(FILTERS.size()):
		var button := Button.new()
		button.text = FILTER_NAMES[i]
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", FILTER_FONT_SIZE)
		button.pressed.connect(_on_filter_pressed.bind(i))
		filters.add_child(button)
		_filter_buttons.append(button)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_span(scroll, 0.125, 0.86)
	scroll.offset_top = FILTER_HEIGHT + 16.0
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)

	_empty_label = Label.new()
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", 22)
	_empty_label.add_theme_color_override("font_color", EMPTY_COLOR)
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_span(_empty_label, 0.4, 0.5)
	add_child(_empty_label)

	var close := Button.new()
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 28)
	close.anchor_left = 0.5
	close.anchor_right = 0.5
	close.anchor_top = 0.92
	close.anchor_bottom = 0.92
	close.grow_horizontal = Control.GROW_DIRECTION_BOTH
	close.grow_vertical = Control.GROW_DIRECTION_BOTH
	close.pressed.connect(_on_close_pressed)
	add_child(close)
	UiPlate.action(close)
	_refresh()

## A centred column MAX_WIDTH wide, from `top` to `bottom` of the screen.
func _span(control: Control, top: float, bottom: float) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = top
	control.anchor_bottom = bottom
	var half := minf(get_viewport_rect().size.x - 40.0, MAX_WIDTH) / 2.0
	control.offset_left = -half
	control.offset_right = half
	control.offset_top = 0.0
	control.offset_bottom = 0.0

func _refresh() -> void:
	for i in range(_filter_buttons.size()):
		UiPlate.option(_filter_buttons[i], i == _filter)
	for row in _list.get_children():
		row.queue_free()
	var mode: String = FILTERS[_filter]
	var shown := 0
	for record in _races:
		if mode != "" and record.get("mode", RaceHistory.MODE_AI) != mode:
			continue
		var row := Row.new()
		row.record = record
		row.pressed.connect(_on_row_pressed.bind(record))
		_list.add_child(row)
		shown += 1
	_empty_label.visible = shown == 0
	if _races.is_empty():
		_empty_label.text = "NO RACES YET"
	else:
		_empty_label.text = "NO %s RACES YET" % FILTER_NAMES[_filter]

func _on_filter_pressed(index: int) -> void:
	Audio.play_ui_click()
	_filter = index
	_refresh()

func _on_row_pressed(record: Dictionary) -> void:
	Audio.play_ui_click()
	RaceReport.open(self, record)

func _on_close_pressed() -> void:
	Audio.play_ui_click()
	queue_free()

## One race in the list, drawn over an empty button:
##   [TAG] 2ND OF 8                 3:41.2
##   MASTER   20,000   ITEMS   06 OCT 14:32
class Row extends Button:
	const HEIGHT := 78.0
	const PAD := 16.0
	const HEAD_SIZE := 24
	const SUB_SIZE := 16
	const TAG_SIZE := 15
	const QUIET := Color(1.0, 1.0, 1.0, 0.55)
	const PLAIN := Color(1.0, 1.0, 1.0, 0.92)

	var record: Dictionary = {}

	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0.0, HEIGHT)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiPlate.option(self, false)

	func _draw() -> void:
		var tag := RaceHistory.mode_tag(record)
		var tag_width := RaceReport.FONT.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TAG_SIZE).x \
			+ RaceReport.TAG_PAD.x * 2.0
		var top := 32.0
		RaceReport.draw_tag(self, tag, RaceHistory.mode_color(record), Vector2(PAD, top - 2.0), TAG_SIZE)
		# A win reads in the accent; any other place in plain white.
		var won := RaceHistory.place(record) == 1 \
			and float(RaceHistory.mine(record).get("time", -1.0)) >= 0.0
		draw_string(RaceReport.FONT, Vector2(PAD + tag_width + 12.0, top), RaceHistory.headline(record),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, HEAD_SIZE, UiAccent.color() if won else PLAIN)
		_right(RaceHistory.result(record), top, HEAD_SIZE, PLAIN)
		var bottom := 60.0
		draw_string(RaceReport.FONT, Vector2(PAD, bottom), RaceHistory.summary(record),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, SUB_SIZE, QUIET)
		_right(RaceHistory.date(record), bottom, SUB_SIZE, QUIET)

	func _right(text: String, baseline: float, font_size: int, color: Color) -> void:
		var width := RaceReport.FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		draw_string(RaceReport.FONT, Vector2(size.x - PAD - width, baseline), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
