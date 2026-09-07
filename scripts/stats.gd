extends Node

const SAVE_PATH := "user://stats.cfg"
const TOP_RUNS_MAX := 10

var runs: Array = []
var games_played: int = 0
var total_score: int = 0
var best_streak_ever: int = 0

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		runs = cfg.get_value("stats", "runs", [])
		games_played = cfg.get_value("stats", "games_played", 0)
		total_score = cfg.get_value("stats", "total_score", 0)
		best_streak_ever = cfg.get_value("stats", "best_streak_ever", 0)

func record_run(score: int, max_streak: int) -> void:
	games_played += 1
	total_score += score
	best_streak_ever = maxi(best_streak_ever, max_streak)
	runs.append({
		"score": score,
		"max_streak": max_streak,
		"date": Time.get_date_string_from_system(),
	})
	runs.sort_custom(func(a, b): return a["score"] > b["score"])
	if runs.size() > TOP_RUNS_MAX:
		runs.resize(TOP_RUNS_MAX)
	_save()

func average_score() -> float:
	return float(total_score) / games_played if games_played > 0 else 0.0

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "runs", runs)
	cfg.set_value("stats", "games_played", games_played)
	cfg.set_value("stats", "total_score", total_score)
	cfg.set_value("stats", "best_streak_ever", best_streak_ever)
	cfg.save(SAVE_PATH)
