extends Control
class_name ItemButton

## The race item HUD (see race_items.gd), all drawn in one _draw:
##
## - The item slot in the bottom-right corner, under the right thumb: the box
##   roulette while a pickup rolls, then the item, pulsing until it is used.
##   The tap target is a real Button, so a press on it is taken by the GUI and
##   never reaches the player as a timing tap or the start of a steer.
## - The item's name, popped up over the slot as the roulette lands.
## - Badges beside the slot for effects still running, with what is left.
## - A glow along the top edge as a gate comes within a screen, with a
##   chevron over each box's lane.
## - An attack on its way in, with who threw it ("COMET FROM ALEX"), and
##   under it this phone's own notices ("HIT SAM!").
## - The feed: who got whom, for everyone, a few lines under the score.
##
## E uses the item too, for testing on a desktop.

const FONT := preload("res://fonts/Chillax-Bold.otf")

const SLOT_SIZE := 116.0
const SLOT_MARGIN := 24.0
const SLOT_FILL := Color(0.0, 0.0, 0.0, 0.55)
const ICON_COLOR := Color(1.8, 1.8, 1.8, 1.0)
const ROULETTE_RATE := 14.0
const NAME_TIME := 1.2
const NAME_FONT_SIZE := 24
const BADGE_RADIUS := 22.0
const BADGE_GAP := 14.0
const BADGE_FONT_SIZE := 18
const WARN_HEIGHT := 46.0
const ALERT_Y := 0.34
const ALERT_FONT_SIZE := 34
const NOTICE_FONT_SIZE := 24
const FEED_Y := 0.15
const FEED_FONT_SIZE := 20
const FEED_LINE_HEIGHT := 30.0
const FEED_ICON := 11.0
const FEED_FILL := Color(0.0, 0.0, 0.0, 0.45)

var items: RaceItems
var camera: Camera2D

var _button: Button
var _time: float = 0.0
var _name_left: float = 0.0
var _was_rolling: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_button = Button.new()
	_button.flat = true
	_button.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_button.add_theme_stylebox_override(state, empty)
	_button.anchor_left = 1.0
	_button.anchor_top = 1.0
	_button.anchor_right = 1.0
	_button.anchor_bottom = 1.0
	_button.offset_left = -SLOT_MARGIN - SLOT_SIZE
	_button.offset_top = -SLOT_MARGIN - SLOT_SIZE
	_button.offset_right = -SLOT_MARGIN
	_button.offset_bottom = -SLOT_MARGIN
	_button.button_down.connect(_on_pressed)
	add_child(_button)
	items.changed.connect(_on_items_changed)

## On press, not release: a race is no place to wait for a finger to lift.
func _on_pressed() -> void:
	items.use()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		if items.use():
			get_viewport().set_input_as_handled()

func _on_items_changed() -> void:
	var rolling := items.rolling_left > 0.0
	if _was_rolling and not rolling and items.held != RaceItems.Item.NONE:
		_name_left = NAME_TIME
	_was_rolling = rolling

func _process(delta: float) -> void:
	_time += delta
	_name_left = maxf(_name_left - delta, 0.0)
	queue_redraw()

func _draw() -> void:
	if items == null:
		return
	_draw_gate_warning()
	var rect := _button.get_rect()
	var center := rect.get_center()
	var radius := SLOT_SIZE / 2.0
	var accent := UiAccent.color()
	var holding := items.held != RaceItems.Item.NONE
	var rolling := items.rolling_left > 0.0
	# A held Shield with something on its way in: the one moment to fire it.
	var urgent := items.held == RaceItems.Item.SHIELD and not items.incoming.is_empty()
	var pulse := 1.0 + (0.06 * sin(_time * 6.0) if holding else 0.0)
	if urgent:
		pulse = 1.0 + 0.14 * absf(sin(_time * 16.0))
	draw_circle(center, radius * pulse, SLOT_FILL)
	var ring := accent if holding or rolling else Color(1.0, 1.0, 1.0, 0.3)
	draw_arc(center, radius * pulse - 2.0, 0.0, TAU, 48, ring, 4.0 if holding else 2.0)
	var icon_r := radius * 0.55
	if rolling:
		var spin := int((RaceItems.ROLL_TIME - items.rolling_left) * ROULETTE_RATE)
		var item: RaceItems.Item = RaceItems.ROLLABLE[spin % RaceItems.ROLLABLE.size()]
		RaceItems.draw_icon(self, item, center, icon_r, Color(1.4, 1.4, 1.4, 0.7))
	elif holding:
		RaceItems.draw_icon(self, items.held, center, icon_r * pulse, ICON_COLOR)
	if _name_left > 0.0 and holding:
		var text: String = RaceItems.NAMES[items.held]
		var a := clampf(_name_left / 0.3, 0.0, 1.0)
		var extent := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, NAME_FONT_SIZE)
		var at := Vector2(minf(center.x - extent.x / 2.0, size.x - extent.x - 12.0),
			rect.position.y - 18.0)
		draw_string(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, NAME_FONT_SIZE,
			Color(accent.r, accent.g, accent.b, a))
	_draw_badges(rect)
	_draw_alerts()
	_draw_feed()

## The first attack on its way in, in the colour of whoever threw it, and
## this phone's own notice under it.
func _draw_alerts() -> void:
	var y := size.y * ALERT_Y
	if not items.incoming.is_empty():
		var attack: Dictionary = items.incoming[0]
		var kind: RaceItems.Item = attack["kind"]
		var verb := "REVERSED BY %s"
		if kind == RaceItems.Item.COMET:
			verb = "COMET FROM %s"
		elif kind == RaceItems.Item.SHOCKWAVE:
			verb = "SHOCKWAVE FROM %s"
		var text := verb % RaceItems.racer_name(attack["from"])
		var c := RaceItems.racer_color(attack["from"])
		c.a = 0.6 + 0.4 * absf(sin(_time * 12.0))
		var extent := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ALERT_FONT_SIZE)
		var icon := ALERT_FONT_SIZE * 0.5
		var x := (size.x - extent.x - icon * 2.6) / 2.0
		RaceItems.draw_icon(self, kind, Vector2(x + icon, y - ALERT_FONT_SIZE * 0.35), icon, ICON_COLOR)
		draw_string(FONT, Vector2(x + icon * 2.6, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			ALERT_FONT_SIZE, c)
	if not items.notice.is_empty():
		var text: String = items.notice["text"]
		var c: Color = items.notice["color"]
		c.a = clampf((RaceItems.NOTICE_TIME - float(items.notice["age"])) / 0.3, 0.0, 1.0)
		var extent := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, NOTICE_FONT_SIZE)
		draw_string(FONT, Vector2((size.x - extent.x) / 2.0, y + 44.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, NOTICE_FONT_SIZE, c)

## "ALEX [comet] SAM", each name in its racer's colour; a blocked one shows the
## shield after the victim's name instead of a hit.
func _draw_feed() -> void:
	var y := size.y * FEED_Y
	for i in range(items.feed.size() - 1, -1, -1):
		var line: Dictionary = items.feed[i]
		var a := clampf((RaceItems.FEED_TIME - float(line["age"])) / 0.4, 0.0, 1.0)
		var from := RaceItems.racer_name(line["from"])
		var victim := RaceItems.racer_name(line["victim"])
		var w_from := FONT.get_string_size(from, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FEED_FONT_SIZE).x
		var w_victim := FONT.get_string_size(victim, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FEED_FONT_SIZE).x
		var gap := FEED_ICON * 3.0
		var blocked: bool = line["blocked"]
		var width := w_from + gap + w_victim + (gap if blocked else 0.0)
		var x := (size.x - width) / 2.0
		draw_rect(Rect2(x - 10.0, y - FEED_FONT_SIZE - 2.0, width + 20.0, FEED_LINE_HEIGHT - 2.0),
			Color(FEED_FILL.r, FEED_FILL.g, FEED_FILL.b, FEED_FILL.a * a))
		var from_c := RaceItems.racer_color(line["from"])
		var victim_c := RaceItems.racer_color(line["victim"])
		from_c.a = a
		victim_c.a = a
		var icon_c := Color(ICON_COLOR.r, ICON_COLOR.g, ICON_COLOR.b, a)
		var icon_y := y - FEED_FONT_SIZE * 0.35
		draw_string(FONT, Vector2(x, y), from, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FEED_FONT_SIZE, from_c)
		x += w_from + gap / 2.0
		RaceItems.draw_icon(self, line["kind"], Vector2(x, icon_y), FEED_ICON, icon_c)
		x += gap / 2.0
		draw_string(FONT, Vector2(x, y), victim, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FEED_FONT_SIZE, victim_c)
		if blocked:
			x += w_victim + gap / 2.0
			RaceItems.draw_icon(self, RaceItems.Item.SHIELD, Vector2(x, icon_y), FEED_ICON, icon_c)
		y += FEED_LINE_HEIGHT

## Effects still running, right to left from beside the slot.
func _draw_badges(slot: Rect2) -> void:
	var x := slot.position.x - BADGE_GAP - BADGE_RADIUS
	var y := slot.get_center().y + SLOT_SIZE / 2.0 - BADGE_RADIUS
	var player := items.player
	if player.rocket_left > 0.0:
		_draw_badge(Vector2(x, y), RaceItems.Item.ROCKET,
			player.rocket_left / RaceItems.ROCKET_TIME, "")
		x -= BADGE_RADIUS * 2.0 + BADGE_GAP
	if items.net_left > 0.0:
		_draw_badge(Vector2(x, y), RaceItems.Item.NET, items.net_left / RaceItems.NET_TIME, "")
		x -= BADGE_RADIUS * 2.0 + BADGE_GAP
	if items.shield_left > 0.0:
		_draw_badge(Vector2(x, y), RaceItems.Item.SHIELD,
			items.shield_left / RaceItems.SHIELD_TIME, "")
		x -= BADGE_RADIUS * 2.0 + BADGE_GAP
	if player.reverse_left > 0.0:
		_draw_badge(Vector2(x, y), RaceItems.Item.REVERSE,
			player.reverse_left / RaceItems.REVERSE_TIME, "")
		x -= BADGE_RADIUS * 2.0 + BADGE_GAP
	if player.auto_boosts > 0:
		_draw_badge(Vector2(x, y), RaceItems.Item.SPRING, 1.0, "%d" % player.auto_boosts)

func _draw_badge(center: Vector2, item: RaceItems.Item, left: float, count: String) -> void:
	draw_circle(center, BADGE_RADIUS, SLOT_FILL)
	draw_arc(center, BADGE_RADIUS - 1.5, -PI / 2.0, -PI / 2.0 + TAU * clampf(left, 0.0, 1.0),
		32, UiAccent.color(), 3.0)
	RaceItems.draw_icon(self, item, center, BADGE_RADIUS * 0.6, ICON_COLOR)
	if count != "":
		draw_string(FONT, center + Vector2(BADGE_RADIUS * 0.45, -BADGE_RADIUS * 0.35), count,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, BADGE_FONT_SIZE, ICON_COLOR)

## From a screen above the top edge down to the edge itself the glow builds,
## then hands over to the boxes themselves scrolling into view.
func _draw_gate_warning() -> void:
	if camera == null:
		return
	var gate_y := items.next_gate_y()
	if gate_y == INF:
		return
	var view := get_viewport_rect().size
	var screen_y := gate_y - camera.global_position.y + view.y / 2.0
	if screen_y > 0.0 or screen_y < -view.y:
		return
	var strength := 1.0 - absf(screen_y) / view.y
	for k in range(RaceItems.BOXES_PER_GATE):
		var x := items.box_x(k)
		var c := RaceItems.box_color(_time, k) * 1.6
		c.a = strength * (0.55 + 0.25 * sin(_time * 8.0))
		draw_rect(Rect2(x - 70.0, 0.0, 140.0, 5.0), c)
		draw_polyline(PackedVector2Array([
			Vector2(x - 14.0, WARN_HEIGHT * 0.65), Vector2(x, WARN_HEIGHT * 0.3),
			Vector2(x + 14.0, WARN_HEIGHT * 0.65),
		]), c, 4.0)
