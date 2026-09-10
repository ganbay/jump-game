extends Node2D

enum Metric { SCORE, STREAK }
enum Period { DAILY, WEEKLY, MONTHLY }

const METRIC_NAMES := ["SCORE", "STREAK"]
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

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var summary_label: Label = $UI/SummaryLabel
@onready var metric_button: Button = $UI/MetricButton
@onready var period_button: Button = $UI/PeriodButton
@onready var graph: LineGraph = $UI/LineGraph
@onready var max_value_label: Label = $UI/MaxValueLabel
@onready var mid_value_label: Label = $UI/MidValueLabel
@onready var range_label: Label = $UI/RangeLabel
@onready var empty_label: Label = $UI/EmptyLabel

var _metric: int = Metric.SCORE
var _period: int = Period.DAILY

func _ready() -> void:
	_apply_visual_settings()
	Settings.visual_settings_changed.connect(_apply_visual_settings)
	summary_label.text = "GAMES PLAYED %d     AVERAGE SCORE %d     BEST STREAK x%d%s" % [
		Stats.games_played,
		int(round(Stats.average_score())),
		Stats.best_streak_ever,
		_badges(),
	]
	_update_metric_label()
	_update_period_label()
	_refresh_graph()

## The two zone-ladder milestones are the only permanent things a player can
## finish, so they get their own line rather than hiding among the run list.
func _badges() -> String:
	var earned := PackedStringArray()
	if Stats.escaped:
		earned.append("ESCAPED SOLAR GRAVITY")
	if Stats.true_ending:
		earned.append("TRUE ENDING")
	return "\n" + "     ".join(earned) if not earned.is_empty() else ""

func _apply_visual_settings() -> void:
	world_environment.environment.glow_intensity = Settings.glow_strength

func _on_metric_pressed() -> void:
	Audio.play_ui_click()
	_metric = Metric.STREAK if _metric == Metric.SCORE else Metric.SCORE
	_update_metric_label()
	_refresh_graph()

func _update_metric_label() -> void:
	metric_button.text = "METRIC: %s" % METRIC_NAMES[_metric]

func _on_period_pressed() -> void:
	Audio.play_ui_click()
	_period = (_period + 1) % PERIOD_NAMES.size()
	_update_period_label()
	_refresh_graph()

func _update_period_label() -> void:
	period_button.text = "PERIOD: %s" % PERIOD_NAMES[_period]

## Every match within the period window becomes its own point, oldest to
## newest, capped to the most recent MAX_POINTS -- a real per-match trend line
## rather than a per-day/week/month rollup that can flatten to a single point.
func _refresh_graph() -> void:
	var cutoff: float = Time.get_unix_time_from_system() - float(PERIOD_WINDOW_SECONDS[_period])
	var recent: Array = []
	for run in Stats.runs:
		if int(run.get("timestamp", 0)) >= cutoff:
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
		values.append(float(run.get("score", 0) if _metric == Metric.SCORE else run.get("max_streak", 0)))
	graph.set_values(values)
	var top: float = graph.max_value()
	max_value_label.text = _format_metric_value(top)
	mid_value_label.text = _format_metric_value(top * 0.5)
	range_label.text = "%d MATCH%s   •   LAST %s" % [
		recent.size(),
		"" if recent.size() == 1 else "ES",
		PERIOD_NAMES[_period],
	]

func _format_metric_value(value: float) -> String:
	return "x%d" % int(round(value)) if _metric == Metric.STREAK else "%d" % int(round(value))

func _on_back_pressed() -> void:
	Audio.play_ui_click()
	Transition.change_scene("res://scenes/main_menu.tscn")
