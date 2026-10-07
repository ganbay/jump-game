extends Control
class_name RaceGuidePanel

## How a race works, over the race screen or the LAN lobby: two lines for the
## mode it was opened from, then the item boxes -- one row per item, its
## picture (RaceItems.draw_icon, the same one the slot shows) doing most of
## the talking. Opened from the "?" both screens get from add_button(), and by
## itself the first time each mode's screen is entered (Race.guide_seen).
##
## The numbers in the rows are read from RaceItems, so retuning an item there
## rewrites its line here.

const DIM := Color(0.0, 0.0, 0.0, 0.96)
const MAX_WIDTH := 600.0
const TITLE_SIZE := 40
const LINE_SIZE := 20
const NOTE_SIZE := 17
const LINE_COLOR := Color(1.0, 1.0, 1.0, 0.92)
const NOTE_COLOR := Color(1.0, 1.0, 1.0, 0.6)
const HELP_ICON := preload("res://assets/icons/help.svg")
const BUTTON_SIZE := 96.0
const BUTTON_MARGIN := 20.0

const AI_LINES := [
	"BEAT THE AI TO THE FINISH LINE",
	"A RACE COSTS 1 TICKET - NOVICE IS FREE",
]
const LAN_LINES := [
	"EVERYONE JOINS ONE ROOM ON THE SAME WI-FI",
	"THE HOST PICKS THE DISTANCE AND STARTS",
]
const AI_NOTE := "NO RECORDS ARE SET WITH ITEM BOXES ON"
const LAN_NOTE := "THE HOST SWITCHES ITEM BOXES ON OR OFF"

## Which mode's lines lead the panel.
var lan: bool = false

## The "?" in the bottom-right corner of a race screen, level with its back
## button, which opens this panel over `ui`.
static func add_button(ui: Node, for_lan: bool) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.icon = HELP_ICON
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 52)
	button.add_theme_color_override("icon_normal_color", Color(1.5, 1.5, 1.5))
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 0.92
	button.anchor_bottom = 0.92
	button.offset_left = -BUTTON_MARGIN - BUTTON_SIZE
	button.offset_right = -BUTTON_MARGIN
	button.offset_top = -BUTTON_SIZE / 2.0
	button.offset_bottom = BUTTON_SIZE / 2.0
	button.pressed.connect(func() -> void:
		Audio.play_ui_click()
		_open(ui, for_lan))
	ui.add_child(button)
	IconPop.attach([button])
	# Unasked the first time the mode's screen is entered, and from then on
	# only from the button.
	if not Race.guide_seen(for_lan):
		_open(ui, for_lan)
	return button

static func _open(ui: Node, for_lan: bool) -> void:
	var panel := RaceGuidePanel.new()
	panel.lan = for_lan
	ui.add_child(panel)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Race.mark_guide_seen(lan)
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var title := Label.new()
	title.text = "LAN RACE" if lan else "AI RACE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_SIZE)
	title.add_theme_color_override("font_color", UiAccent.color())
	_span(title, 0.05, 0.11)
	add_child(title)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	_span(column, 0.12, 0.86)
	add_child(column)
	for line in (LAN_LINES if lan else AI_LINES):
		_add_line(column, line, LINE_SIZE, LINE_COLOR)
	_add_gap(column)
	_add_line(column, "ITEM BOXES", 26, UiAccent.color())
	_add_line(column, "FLY THROUGH A BOX, THEN TAP THE CORNER SLOT TO USE IT", NOTE_SIZE, NOTE_COLOR)
	for item in RaceItems.ROLLABLE:
		var row := Row.new()
		row.item = item
		row.text = _describe(item)
		column.add_child(row)
	_add_line(column, "THE FURTHER BEHIND YOU ARE, THE BETTER THE ITEM", NOTE_SIZE, NOTE_COLOR)
	_add_line(column, LAN_NOTE if lan else AI_NOTE, NOTE_SIZE, NOTE_COLOR)

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

static func _describe(item: int) -> String:
	match item:
		RaceItems.Item.ROCKET:
			return "BLAST UPWARD FOR %d SECONDS" % int(RaceItems.ROCKET_TIME)
		RaceItems.Item.NET:
			return "CATCHES YOUR FALLS FOR %d SECONDS" % int(RaceItems.NET_TIME)
		RaceItems.Item.SPRING:
			return "YOUR NEXT %d JUMPS GO HIGHER" % RaceItems.SPRING_LANDINGS
		RaceItems.Item.SHIELD:
			return "BLOCKS ONE ATTACK - LASTS %d SECONDS" % int(RaceItems.SHIELD_TIME)
		RaceItems.Item.COMET:
			return "STUNS THE LEADER"
		RaceItems.Item.REVERSE:
			return "SWAPS LEFT AND RIGHT FOR EVERYONE AHEAD"
		RaceItems.Item.SHOCKWAVE:
			return "STUNS EVERYONE AHEAD"
	return ""

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

func _add_line(parent: Control, text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _add_gap(parent: Control) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 14.0)
	parent.add_child(gap)

func _on_close_pressed() -> void:
	Audio.play_ui_click()
	queue_free()

## One item: its picture, its name, and what it does in a line.
##   [icon]  ROCKET
##           BLAST UPWARD FOR 2 SECONDS
class Row extends Control:
	const HEIGHT := 66.0
	const ICON_RADIUS := 22.0
	const TEXT_X := 76.0
	const NAME_SIZE := 22
	const TEXT_SIZE := 17

	var item: int = RaceItems.Item.NONE
	var text: String = ""

	func _ready() -> void:
		custom_minimum_size = Vector2(0.0, HEIGHT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		RaceItems.draw_icon(self, item, Vector2(ICON_RADIUS + 8.0, HEIGHT / 2.0), ICON_RADIUS,
			ItemButton.ICON_COLOR)
		draw_string(RaceItems.FONT, Vector2(TEXT_X, 28.0), RaceItems.NAMES[item],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, NAME_SIZE, UiAccent.color())
		draw_string(get_theme_default_font(), Vector2(TEXT_X, 52.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - TEXT_X, TEXT_SIZE, RaceGuidePanel.LINE_COLOR)
