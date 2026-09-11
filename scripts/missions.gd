extends Node

## Three missions a day.
##
## The set is a rotating window over TEMPLATES rather than a random draw: every
## template comes round in turn instead of the same two showing up all week, and
## because the window is derived from the date, relaunching the game cannot
## re-roll a hard mission into an easy one.
##
## Difficulty is per template and permanent. Each template remembers how many
## times it has ever been completed and its target is base + step * that count,
## so the missions climb with the player while the payout stays flat -- there is
## no reward curve to balance, only the numbers in the table below.

signal changed
## Carries the finished text so a listener can show it without re-deriving the
## target -- which by then has already climbed to next time's number.
signal completed(id: String, reward: int, text: String)

const SAVE_PATH := "user://missions.cfg"
const REWARD := 200
const DAILY_COUNT := 3

const MORNING_HOUR := 8
const EVENING_HOUR := 20

## Where a mission's number comes from. RUN_* take the best single run of the
## day; DAY_* accumulate across every run played.
enum Kind { RUN_SCORE, RUN_STREAK, RUN_FLARES, RUN_ZONE, DAY_RUNS, DAY_SCORE, DAY_FLARES, DAY_COINS }

## Add to this and the rotation, the scaling, the saving and the screen all pick
## it up untouched -- an id is the only thing anything else knows about.
const TEMPLATES := [
	{"id": "run_score", "kind": Kind.RUN_SCORE, "text": "SCORE %d IN ONE RUN", "base": 800, "step": 400},
	{"id": "day_runs", "kind": Kind.DAY_RUNS, "text": "PLAY %d RUNS TODAY", "base": 3, "step": 1},
	{"id": "run_streak", "kind": Kind.RUN_STREAK, "text": "HIT A STREAK OF %d", "base": 5, "step": 2},
	{"id": "day_flares", "kind": Kind.DAY_FLARES, "text": "FLARE %d TIMES TODAY", "base": 40, "step": 20},
	{"id": "day_score", "kind": Kind.DAY_SCORE, "text": "SCORE %d TODAY IN TOTAL", "base": 3000, "step": 1500},
	{"id": "run_flares", "kind": Kind.RUN_FLARES, "text": "FLARE %d TIMES IN ONE RUN", "base": 15, "step": 8},
	{"id": "run_zone", "kind": Kind.RUN_ZONE, "text": "REACH ZONE %d IN ONE RUN", "base": 3, "step": 1},
	{"id": "day_coins", "kind": Kind.DAY_COINS, "text": "EARN %d COINS TODAY", "base": 120, "step": 60},
]

## id -> lifetime completions. The only permanent state; everything else resets
## with the day.
var _levels: Dictionary = {}
## id -> progress banked by runs that have already finished today. The run in
## progress is held separately in _run and folded in on read, so a mission can
## be seen completing mid-flight without half a run being committed to disk.
var _progress: Dictionary = {}
## id -> the target it was actually cleared at. Not a bare flag: completing a
## mission levels it up immediately, so without this the row would redisplay
## itself as "DONE" against tomorrow's harder number.
var _done: Dictionary = {}
## Live summary of the run in progress, empty between runs.
var _run: Dictionary = {}
## Local date the active set belongs to, as YYYY-MM-DD.
var _day: String = ""
var _day_index: int = 0

func _ready() -> void:
	_load()
	_roll_if_new_day()

## Today's three, as display-ready rows.
func active() -> Array:
	_roll_if_new_day()
	var rows: Array = []
	for template in _todays_templates():
		var id: String = template["id"]
		var done := _done.has(id)
		# A migrated entry has no recorded target; fall back to the live one.
		var cleared := int(_done.get(id, 0))
		var target := cleared if cleared > 0 else target_of(template)
		rows.append({
			"id": id,
			"text": template["text"] % target,
			"target": target,
			"progress": mini(_effective(template), target),
			"done": done,
		})
	return rows

func remaining() -> int:
	var left := 0
	for row in active():
		if not row["done"]:
			left += 1
	return left

func target_of(template: Dictionary) -> int:
	return int(template["base"]) + int(template["step"]) * int(_levels.get(template["id"], 0))

func begin_run() -> void:
	_roll_if_new_day()
	_run = {}

## Called as the run's numbers move, so a mission can announce itself the moment
## it is cleared rather than at the death screen. Cheap enough to call on every
## score tick: it is a handful of dictionary reads over three missions.
func update_run(summary: Dictionary) -> void:
	_run = summary
	_check()

## Commits the run. Pass `finished` so PLAY X RUNS TODAY counts a run when it
## ends rather than the moment it starts.
func end_run(summary: Dictionary) -> void:
	_run = summary
	_check()
	for template in _todays_templates():
		_progress[template["id"]] = _effective(template)
	_run = {}
	_save()
	changed.emit()

## Committed progress with the live run folded in: a run kind takes whichever of
## the two is better, a day kind adds them together.
func _effective(template: Dictionary) -> int:
	var committed := int(_progress.get(template["id"], 0))
	if _run.is_empty():
		return committed
	var live := _value_for(template["kind"], _run)
	return maxi(committed, live) if _is_run_kind(template["kind"]) else committed + live

func _check() -> void:
	var paid := false
	for template in _todays_templates():
		var id: String = template["id"]
		if _done.has(id):
			continue
		var target := target_of(template)
		if _effective(template) < target:
			continue
		_done[id] = target
		_levels[id] = int(_levels.get(id, 0)) + 1
		Stats.award_coins(REWARD)
		completed.emit(id, REWARD, template["text"] % target)
		paid = true
	if paid:
		_reschedule()
		_save()
		changed.emit()

func _is_run_kind(kind: int) -> bool:
	return kind in [Kind.RUN_SCORE, Kind.RUN_STREAK, Kind.RUN_FLARES, Kind.RUN_ZONE]

func _value_for(kind: int, summary: Dictionary) -> int:
	match kind:
		Kind.RUN_SCORE, Kind.DAY_SCORE:
			return summary.get("score", 0)
		Kind.RUN_STREAK:
			return summary.get("max_streak", 0)
		Kind.RUN_FLARES, Kind.DAY_FLARES:
			return summary.get("flares", 0)
		Kind.RUN_ZONE:
			# Stages are 0-based and the HUD prints them 1-based, so the mission
			# text and the banner the player read agree.
			return summary.get("stage", 0) + 1
		Kind.DAY_COINS:
			return summary.get("coins", 0)
		Kind.DAY_RUNS:
			# Only once the run is over, so this cannot complete on the frame a
			# run begins.
			return 1 if summary.get("finished", false) else 0
	return 0

## A window of DAILY_COUNT starting where yesterday's ended, wrapping round.
func _todays_templates() -> Array:
	var out: Array = []
	var start := (_day_index * DAILY_COUNT) % TEMPLATES.size()
	for i in range(DAILY_COUNT):
		out.append(TEMPLATES[(start + i) % TEMPLATES.size()])
	return out

func _roll_if_new_day() -> void:
	var now := Time.get_datetime_dict_from_system()
	var key := "%04d-%02d-%02d" % [now["year"], now["month"], now["day"]]
	if key == _day:
		return
	_day = key
	# Built from the local date so the index advances exactly once per calendar
	# day, whatever the timezone; it is only ever used to pick the window.
	_day_index = int(Time.get_unix_time_from_datetime_string(key) / 86400.0)
	_progress.clear()
	_done.clear()
	_save()
	_reschedule()
	changed.emit()

## The morning nudge always stands. The evening one is only worth sending while
## there is something left to come back for, so it is cancelled the moment the
## third mission lands.
func _reschedule() -> void:
	Notify.schedule_daily(Notify.MORNING, MORNING_HOUR, 0,
		"NEW MISSIONS", "Three fresh missions are waiting. Time to climb.")
	var left := remaining()
	if left > 0:
		Notify.schedule_daily(Notify.EVENING, EVENING_HOUR, 0,
			"MISSIONS ENDING", "You have %d mission%s left today." % [left, "" if left == 1 else "s"])
	else:
		Notify.cancel(Notify.EVENING)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	_levels = cfg.get_value("missions", "levels", {})
	_progress = cfg.get_value("missions", "progress", {})
	_done = cfg.get_value("missions", "done", {})
	# A save from before _done held the cleared target stored plain `true`.
	for id in _done.keys():
		if typeof(_done[id]) != TYPE_INT:
			_done[id] = 0
	_day = cfg.get_value("missions", "day", "")
	_day_index = cfg.get_value("missions", "day_index", 0)

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("missions", "levels", _levels)
	cfg.set_value("missions", "progress", _progress)
	cfg.set_value("missions", "done", _done)
	cfg.set_value("missions", "day", _day)
	cfg.set_value("missions", "day_index", _day_index)
	cfg.save(SAVE_PATH)
