extends Node

const SAVE_PATH := "user://stats.cfg"
## Kept chronological (not a leaderboard) so the stats screen can bucket it by
## day/week/month -- capped so the save file doesn't grow forever.
const RUN_HISTORY_MAX := 500

var runs: Array = []
var games_played: int = 0
var total_score: int = 0
var best_streak_ever: int = 0
## The spendable balance, banked one run at a time. Separate from a lifetime
## total on purpose -- once there is something to spend it on, this is the
## number that goes down.
var coins: int = 0
## Run-spanning milestones from the zone ladder (see zone_director.gd): the
## escape from Solar gravity, and clearing every zone combination after it.
var escaped: bool = false
var true_ending: bool = false
var tutorial_seen: bool = false

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		runs = cfg.get_value("stats", "runs", [])
		games_played = cfg.get_value("stats", "games_played", 0)
		total_score = cfg.get_value("stats", "total_score", 0)
		best_streak_ever = cfg.get_value("stats", "best_streak_ever", 0)
		coins = cfg.get_value("stats", "coins", 0)
		escaped = cfg.get_value("stats", "escaped", false)
		true_ending = cfg.get_value("stats", "true_ending", false)
		tutorial_seen = cfg.get_value("stats", "tutorial_seen", false)

func record_run(score: int, max_streak: int, coins_earned: int = 0) -> void:
	games_played += 1
	total_score += score
	best_streak_ever = maxi(best_streak_ever, max_streak)
	coins += coins_earned
	runs.append({
		"score": score,
		"max_streak": max_streak,
		"coins": coins_earned,
		"timestamp": Time.get_unix_time_from_system(),
	})
	if runs.size() > RUN_HISTORY_MAX:
		runs = runs.slice(runs.size() - RUN_HISTORY_MAX)
	_save()

## Mission payouts and anything else that hands coins over, as opposed to the
## run itself banking them through record_run.
func award_coins(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	_save()

## Returns false and changes nothing when the balance is short, so a caller
## cannot half-complete a purchase. Spending nothing is a success -- a free
## item still counts as bought.
func spend_coins(amount: int) -> bool:
	if amount < 0 or coins < amount:
		return false
	coins -= amount
	_save()
	return true

func mark_escaped() -> void:
	if escaped:
		return
	escaped = true
	_save()

func mark_true_ending() -> void:
	if true_ending:
		return
	true_ending = true
	_save()

func mark_tutorial_seen() -> void:
	if tutorial_seen:
		return
	tutorial_seen = true
	_save()

func average_score() -> float:
	return float(total_score) / games_played if games_played > 0 else 0.0

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "runs", runs)
	cfg.set_value("stats", "games_played", games_played)
	cfg.set_value("stats", "total_score", total_score)
	cfg.set_value("stats", "best_streak_ever", best_streak_ever)
	cfg.set_value("stats", "coins", coins)
	cfg.set_value("stats", "escaped", escaped)
	cfg.set_value("stats", "true_ending", true_ending)
	cfg.set_value("stats", "tutorial_seen", tutorial_seen)
	cfg.save(SAVE_PATH)
