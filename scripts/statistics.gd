extends Node2D

enum Metric { SCORE, STREAK, SPEED }
enum Period { DAILY, WEEKLY, MONTHLY }

## These stay words rather than glyphs: they pick what the graph is showing,
## and no icon says "streak over the last week" the way the word does. Only the
## state is printed -- what it selects is obvious from the graph underneath.
const METRIC_NAMES := ["SCORE", "FLARE", "SPEED"]
const PERIOD_NAMES := ["DAILY", "WEEKLY", "MONTHLY"]
const DAY_SECONDS := 86400
## The period is a recency window, not a bucket size -- every match inside it
## gets its own point. Bucketing multiple same-day matches down to one point
## per day left nothing to draw a line between after a single test session.
const PERIOD_WINDOW_SECONDS := {
	Period.DAILY: DAY_SECONDS,
	Period.WEEKLY: DAY_SECONDS * 7,
	Period.MONTHLY: DAY_SECONDS * 30,
}
## Caps how many of the most recent matches in the window get plotted, so a
## long history inside e.g. MONTHLY doesn't crowd the points illegibly.
const MAX_POINTS := 40
## The numbers around the graph are tiles -- a big value over a small caption
## -- in two rows: totals above it, speeds (score per second) below.
const TILE_VALUE_FONT_SIZE := 28
const TILE_CAPTION_FONT_SIZE := 13
const TILE_CAPTION_COLOR := Color(1.0, 1.0, 1.0, 0.6)
const TILE_ROW_HEIGHT := 64.0
const TOTALS_ANCHOR_Y := 0.125
const SPEEDS_ANCHOR_Y := 0.82

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var metric_button: Button = $UI/MetricButton
@onready var period_button: Button = $UI/PeriodButton
@onready var graph: LineGraph = $UI/LineGraph
@onready var max_value_label: Label = $UI/MaxValueLabel
@onready var mid_value_label: Label = $UI/MidValueLabel
@onready var range_label: Label = $UI/RangeLabel
@onready var empty_label: Label = $UI/EmptyLabel

var _metric: int = Metric.SCORE
var _period: int = Period.MONTHLY

func _ready() -> void:
	# Before _apply_visual_settings, whose accent walk colours the values.
	_build_tiles()
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	_update_metric_label()
	_update_period_label()
	_refresh_graph()
	IconPop.attach([metric_button, period_button, $UI/BackButton])

func _build_tiles() -> void:
	var totals := _add_tile_row(TOTALS_ANCHOR_Y)
	_add_tile(totals, str(Stats.games_played), "GAMES")
	_add_tile(totals, Stats.format_duration(Stats.total_time), "TIME PLAYED")
	_add_tile(totals, str(int(round(Stats.average_score()))), "AVG SCORE")
	_add_tile(totals, "x%d" % Stats.best_streak_ever, "BEST FLARE")
	# The race tiles are the fastest won AI race at each distance -- the
	# numbers the Play leaderboards rank. A dash until that distance is won.
	var speeds := _add_tile_row(SPEEDS_ANCHOR_Y)
	_add_tile(speeds, Stats.format_speed(Stats.average_speed()), "AVG SPEED")
	_add_tile(speeds, Stats.format_speed(Stats.best_speed), "BEST SPEED")
	for distance in Race.TARGETS:
		var speed := Stats.race_best_speed(distance)
		_add_tile(speeds, Stats.format_speed(speed) if speed > 0.0 else "-",
			"%dK RACE" % (distance / 1000))

func _add_tile_row(anchor_y: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.anchor_left = 0.04
	row.anchor_right = 0.96
	row.anchor_top = anchor_y
	row.anchor_bottom = anchor_y
	row.offset_top = -TILE_ROW_HEIGHT / 2.0
	row.offset_bottom = TILE_ROW_HEIGHT / 2.0
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(row)
	return row

func _add_tile(row: HBoxContainer, value: String, caption: String) -> void:
	var tile := VBoxContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_theme_constant_override("separation", 2)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tile)
	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", TILE_VALUE_FONT_SIZE)
	value_label.add_to_group(UiAccent.GROUP)
	tile.add_child(value_label)
	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.add_theme_font_size_override("font_size", TILE_CAPTION_FONT_SIZE)
	caption_label.add_theme_color_override("font_color", TILE_CAPTION_COLOR)
	tile.add_child(caption_label)

func _apply_visual_settings() -> void:
	Settings.apply_glow(world_environment.environment)
	UiOpacity.apply($UI)
	UiAccent.apply($UI)
	graph.line_color = Settings.background_particle_color
	graph.queue_redraw()

func _on_metric_pressed() -> void:
	Audio.play_ui_click()
	_metric = (_metric + 1) % METRIC_NAMES.size()
	_update_metric_label()
	_refresh_graph()

func _update_metric_label() -> void:
	metric_button.text = METRIC_NAMES[_metric]

func _on_period_pressed() -> void:
	Audio.play_ui_click()
	_period = (_period + 1) % PERIOD_NAMES.size()
	_update_period_label()
	_refresh_graph()

func _update_period_label() -> void:
	period_button.text = PERIOD_NAMES[_period]

## Every match within the period window becomes its own point, oldest to
## newest, capped to the most recent MAX_POINTS -- a real per-match trend line
## rather than a per-day/week/month rollup that can flatten to a single point.
func _refresh_graph() -> void:
	var cutoff: float = Time.get_unix_time_from_system() - float(PERIOD_WINDOW_SECONDS[_period])
	var recent: Array = []
	for run in Stats.runs:
		if int(run.get("timestamp", 0)) < cutoff:
			continue
		# Runs saved before the clock existed have no pace to plot, so SPEED
		# skips them rather than drawing them as a dive to zero.
		if _metric == Metric.SPEED and not Stats.has_speed(run):
			continue
		recent.append(run)
	recent.sort_custom(func(a, b): return a["timestamp"] < b["timestamp"])
	if recent.size() > MAX_POINTS:
		recent = recent.slice(recent.size() - MAX_POINTS)
	var has_data := not recent.is_empty()
	graph.visible = has_data
	max_value_label.visible = has_data
	mid_value_label.visible = has_data
	range_label.visible = has_data
	empty_label.visible = not has_data
	if not has_data:
		return
	var values: Array = []
	for run in recent:
		values.append(_metric_value(run))
	graph.set_values(values)
	var top: float = graph.max_value()
	max_value_label.text = _format_metric_value(top)
	mid_value_label.text = _format_metric_value(top * 0.5)
	range_label.text = "%d MATCH%s   •   LAST %s" % [
		recent.size(),
		"" if recent.size() == 1 else "ES",
		PERIOD_NAMES[_period],
	]

func _metric_value(run: Dictionary) -> float:
	match _metric:
		Metric.STREAK:
			return float(run.get("max_streak", 0))
		Metric.SPEED:
			return Stats.speed_of(run)
		_:
			return float(run.get("score", 0))

func _format_metric_value(value: float) -> String:
	match _metric:
		Metric.STREAK:
			return "x%d" % int(round(value))
		Metric.SPEED:
			return "%s/s" % Stats.format_speed(value)
		_:
			return "%d" % int(round(value))

func _on_back_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/main_menu.tscn")
