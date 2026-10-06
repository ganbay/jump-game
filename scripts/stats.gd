extends Node

## Emitted after every write to disk, so PlayGames can mirror it to the cloud.
signal saved

const SAVE_PATH := "user://stats.cfg"
## Kept chronological (not a leaderboard) so the stats screen can bucket it by
## day/week/month -- capped so the save file doesn't grow forever.
const RUN_HISTORY_MAX := 500
## Below this a run is treated as untimed rather than absurdly fast: it is
## either a pre-timer save (no "duration" at all) or a death during the first
## instants of play, where score/seconds is noise divided by nearly nothing.
const MIN_TIMED_SECONDS := 0.5

var runs: Array = []
var games_played: int = 0
var total_score: int = 0
var best_streak_ever: int = 0
## Lifetime seconds of actual play (paused time excluded -- see game.gd's
## run_time). Kept alongside total_score so average_speed is a true
## time-weighted average over everything played, not the mean of per-run
## averages, which would let one lucky two-second run dominate.
var total_time: float = 0.0
var best_speed: float = 0.0
## Fastest won AI race per distance, in score per second, keyed by the
## distance (10000, 20000, ...). The local copy of what the Play leaderboards
## hold -- see PlayGames.submit_race_speed, which is sent the same wins.
var race_best_speeds: Dictionary = {}
## The spendable balance, banked one run at a time. Separate from a lifetime
## total on purpose -- once there is something to spend it on, this is the
## number that goes down.
var coins: int = 0
## Run-spanning milestones from the zone ladder (see zone_director.gd): the
## escape from Solar gravity, and clearing every zone combination after it.
var escaped: bool = false
var true_ending: bool = false
var tutorial_seen: bool = false
## Set once the player has followed the store-rating prompt in Customize (see
## Unlocks.gd). Trusts the tap rather than verifying a submitted review --
## there is no cross-platform way to confirm one from inside the app.
var rated_game: bool = false

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		runs = cfg.get_value("stats", "runs", [])
		games_played = cfg.get_value("stats", "games_played", 0)
		total_score = cfg.get_value("stats", "total_score", 0)
		best_streak_ever = cfg.get_value("stats", "best_streak_ever", 0)
		total_time = cfg.get_value("stats", "total_time", 0.0)
		best_speed = cfg.get_value("stats", "best_speed", 0.0)
		race_best_speeds = cfg.get_value("stats", "race_best_speeds", {})
		coins = cfg.get_value("stats", "coins", 0)
		escaped = cfg.get_value("stats", "escaped", false)
		true_ending = cfg.get_value("stats", "true_ending", false)
		tutorial_seen = cfg.get_value("stats", "tutorial_seen", false)
		rated_game = cfg.get_value("stats", "rated_game", false)

## `duration` defaults to 0 so an older call site (or a run somehow finishing
## before the clock started) still records -- it just contributes no speed.
func record_run(score: int, max_streak: int, coins_earned: int = 0, duration: float = 0.0) -> void:
	games_played += 1
	total_score += score
	best_streak_ever = maxi(best_streak_ever, max_streak)
	coins += coins_earned
	total_time += maxf(duration, 0.0)
	var run := {
		"score": score,
		"max_streak": max_streak,
		"coins": coins_earned,
		"duration": duration,
		"timestamp": Time.get_unix_time_from_system(),
	}
	best_speed = maxf(best_speed, speed_of(run))
	runs.append(run)
	if runs.size() > RUN_HISTORY_MAX:
		runs = runs.slice(runs.size() - RUN_HISTORY_MAX)
	_save()

## 0.0 for a distance never won.
func race_best_speed(distance: int) -> float:
	return float(race_best_speeds.get(distance, 0.0))

## A won AI race's speed. Returns whether it beat the record for its distance;
## nothing is written when it did not.
func record_race_speed(distance: int, speed: float) -> bool:
	if speed <= race_best_speed(distance):
		return false
	race_best_speeds[distance] = speed
	_save()
	return true

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

func mark_rated() -> void:
	if rated_game:
		return
	rated_game = true
	_save()

func average_score() -> float:
	return float(total_score) / games_played if games_played > 0 else 0.0

## Score per second of play -- the pace of a run rather than its length. Runs
## saved before the timer existed carry no "duration" and report 0, which is
## also what has_speed() below keys off, so they drop out of speed views
## instead of dragging them to zero.
func speed_of(run: Dictionary) -> float:
	var duration := float(run.get("duration", 0.0))
	return float(run.get("score", 0)) / duration if duration >= MIN_TIMED_SECONDS else 0.0

func has_speed(run: Dictionary) -> bool:
	return float(run.get("duration", 0.0)) >= MIN_TIMED_SECONDS

func average_speed() -> float:
	return float(total_score) / total_time if total_time >= MIN_TIMED_SECONDS else 0.0

## M:SS, growing an hours field only when there is one to show -- a two-minute
## run should not read "0:02:14".
func format_duration(seconds: float) -> String:
	var total := int(round(maxf(seconds, 0.0)))
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]
	return "%d:%02d" % [total / 60, total % 60]

func format_speed(speed: float) -> String:
	return "%.1f" % speed

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "runs", runs)
	cfg.set_value("stats", "games_played", games_played)
	cfg.set_value("stats", "total_score", total_score)
	cfg.set_value("stats", "best_streak_ever", best_streak_ever)
	cfg.set_value("stats", "total_time", total_time)
	cfg.set_value("stats", "best_speed", best_speed)
	cfg.set_value("stats", "race_best_speeds", race_best_speeds)
	cfg.set_value("stats", "coins", coins)
	cfg.set_value("stats", "escaped", escaped)
	cfg.set_value("stats", "true_ending", true_ending)
	cfg.set_value("stats", "tutorial_seen", tutorial_seen)
	cfg.set_value("stats", "rated_game", rated_game)
	cfg.save(SAVE_PATH)
	saved.emit()

## --- Cloud save (see play_games.gd) ----------------------------------------

func cloud_state() -> Dictionary:
	return {
		"runs": runs,
		"games_played": games_played,
		"total_score": total_score,
		"best_streak_ever": best_streak_ever,
		"total_time": total_time,
		"best_speed": best_speed,
		"race_best_speeds": race_best_speeds,
		"coins": coins,
		"escaped": escaped,
		"true_ending": true_ending,
		"tutorial_seen": tutorial_seen,
		"rated_game": rated_game,
	}

## Folds a cloud copy into this device's. The running totals cannot be added
## together -- most of the time the cloud copy *is* this device's own earlier
## save -- so they are taken whole from whichever side has played more, along
## with the run history and balance that belong to them. Records and
## milestones are simply never lost: the better of the two, and any flag
## either side has set.
func merge_cloud(state: Dictionary) -> void:
	if int(state.get("games_played", 0)) > games_played:
		var cloud_runs: Variant = state.get("runs")
		runs = cloud_runs if cloud_runs is Array else []
		games_played = int(state.get("games_played", 0))
		total_score = int(state.get("total_score", 0))
		total_time = float(state.get("total_time", 0.0))
		coins = int(state.get("coins", 0))
	best_streak_ever = maxi(best_streak_ever, int(state.get("best_streak_ever", 0)))
	best_speed = maxf(best_speed, float(state.get("best_speed", 0.0)))
	var cloud_race: Variant = state.get("race_best_speeds")
	if cloud_race is Dictionary:
		for distance in cloud_race:
			race_best_speeds[int(distance)] = maxf(race_best_speed(int(distance)),
				float(cloud_race[distance]))
	escaped = escaped or bool(state.get("escaped", false))
	true_ending = true_ending or bool(state.get("true_ending", false))
	tutorial_seen = tutorial_seen or bool(state.get("tutorial_seen", false))
	rated_game = rated_game or bool(state.get("rated_game", false))
	_save()
