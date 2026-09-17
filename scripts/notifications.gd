extends Node

## Local notifications, backed by the JetletNotify Android plugin
## (addons/jetlet_notify). Everywhere else -- the editor, desktop, a build
## without the plugin -- every call is a silent no-op.
##
## What it sends: comeback reminders. Every launch and every time the game goes
## to the background, the COMEBACK set below is scheduled again relative to
## *now*, replacing the previous one -- so a player who keeps playing never sees
## them, and one who drifts away gets a nudge after 1, 3 and 7 days.
##
## Permission (Android 13+) is asked once, shortly after the first run ends,
## while the player is idle on the game-over panel. A refusal is final: the
## prompt is never shown again, and Android would stop showing it anyway.

signal permission_result(granted: bool)

## Ids so a scheduled notification can be replaced or cancelled by name.
const MORNING := "missions_morning"
const EVENING := "missions_evening"

## days after the last session -> copy. `%s` in body is the formatted best score.
const COMEBACK := [
	{"id": "comeback_1", "days": 1, "title": "Your best: %s",
		"body": "The sun is still rising. Think you can climb higher?"},
	{"id": "comeback_3", "days": 3, "title": "Jetlet is waiting",
		"body": "Your record of %s is still standing. Time to beat it."},
	{"id": "comeback_7", "days": 7, "title": "Solar escape, anyone?",
		"body": "It has been a week. One quick run -- can you top %s?"},
]
## Same copy for a player with no score yet, where "%s" would read as "0".
const COMEBACK_NO_SCORE := {
	"comeback_1": ["Ready for another run?", "The sun is still rising. See how high you can climb."],
	"comeback_3": ["Jetlet is waiting", "Your jetlet is fuelled up and ready to escape."],
	"comeback_7": ["Solar escape, anyone?", "It has been a week. One quick run?"],
}
## A reminder that lands outside these local hours is moved to FALLBACK_HOUR
## the same day -- nobody wants a game buzzing at 3am.
const QUIET_START_HOUR := 21
const QUIET_END_HOUR := 10
const FALLBACK_HOUR := 18
## Gap between the run ending and the prompt, so the game-over panel has
## popped in and the player has read their score first.
const PERMISSION_DELAY := 1.2

const SAVE_PATH := "user://notify.cfg"
## Owned by game.gd; read here only for the notification copy.
const HIGH_SCORE_PATH := "user://highscore.cfg"

var _plugin: Object = null
var _permission_asked: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.has_singleton("JetletNotify"):
		_plugin = Engine.get_singleton("JetletNotify")
		_plugin.connect("permission_result", _on_permission_result)
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_permission_asked = cfg.get_value("notify", "permission_asked", false)
	schedule_comeback()

func _notification(what: int) -> void:
	# Leaving the app is the moment "last played" is measured from.
	if what == NOTIFICATION_APPLICATION_PAUSED:
		schedule_comeback()

func is_supported() -> bool:
	return _plugin != null

## True once the player has granted permission and has not switched the app's
## notifications off in system settings.
func are_enabled() -> bool:
	return _plugin != null and _plugin.areEnabled()

## Called by game.gd when a run is finalized. Only the first call ever asks.
func request_permission_once() -> void:
	if _plugin == null or _permission_asked:
		return
	_permission_asked = true
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("notify", "permission_asked", true)
	cfg.save(SAVE_PATH)
	await get_tree().create_timer(PERMISSION_DELAY).timeout
	_plugin.requestPermission()

func _on_permission_result(granted: bool) -> void:
	Analytics.log_event("notify_permission", {"granted": int(granted)})
	if granted:
		schedule_comeback()
	permission_result.emit(granted)

## Replaces the pending comeback reminders with a fresh set counted from now.
func schedule_comeback() -> void:
	if _plugin == null:
		return
	var best := _best_score()
	var now := int(Time.get_unix_time_from_system())
	for entry in COMEBACK:
		var id: String = entry["id"]
		var title: String
		var body: String
		if best > 0:
			var shown := _format_score(best)
			title = entry["title"] % shown if "%s" in entry["title"] else entry["title"]
			body = entry["body"] % shown if "%s" in entry["body"] else entry["body"]
		else:
			title = COMEBACK_NO_SCORE[id][0]
			body = COMEBACK_NO_SCORE[id][1]
		_plugin.schedule(id, _out_of_quiet_hours(now + int(entry["days"]) * 86400), title, body, false)

## Schedules `body` to fire at the next occurrence of hour:minute local time and
## every day after, replacing any pending notification with the same id.
func schedule_daily(id: String, hour: int, minute: int, title: String, body: String) -> void:
	if _plugin == null:
		return
	var now := int(Time.get_unix_time_from_system())
	var at := _local_today_at(now, hour, minute)
	if at <= now:
		at += 86400
	_plugin.schedule(id, at, title, body, true)

func cancel(id: String) -> void:
	if _plugin != null:
		_plugin.cancel(id)

## `unix` moved to FALLBACK_HOUR on its local day when it falls in quiet hours.
func _out_of_quiet_hours(unix: int) -> int:
	var hour: int = Time.get_datetime_dict_from_unix_time(unix + _utc_offset_seconds())["hour"]
	if hour >= QUIET_START_HOUR or hour < QUIET_END_HOUR:
		return _local_today_at(unix, FALLBACK_HOUR, 0)
	return unix

## Unix time of hour:minute on the local calendar day containing `unix`.
func _local_today_at(unix: int, hour: int, minute: int) -> int:
	var offset := _utc_offset_seconds()
	var local_midnight := (unix + offset) - posmod(unix + offset, 86400)
	return local_midnight - offset + hour * 3600 + minute * 60

func _utc_offset_seconds() -> int:
	return int(Time.get_time_zone_from_system()["bias"]) * 60

func _best_score() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(HIGH_SCORE_PATH) != OK:
		return 0
	return int(cfg.get_value("scores", "high_score", 0))

## 12345 -> "12,345"
func _format_score(value: int) -> String:
	var digits := str(value)
	var out := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out
