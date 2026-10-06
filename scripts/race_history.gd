extends RefCounted
class_name RaceHistory

## What happened in each finished race -- against the AI or over LAN -- kept
## for the race report (race_report.gd) and the history list
## (race_history_panel.gd). game.gd builds a record when a race ends and
## hands it to add().
##
## A record:
##   when        unix time the race ended
##   mode        MODE_AI or MODE_LAN
##   difficulty  the AI's name (MODE_AI only)
##   target      the distance, in score
##   items       whether item boxes were on
##   racers      one racer() each, in finishing order (see sort_racers)
##
## Kept apart from race.cfg, which is rewritten on every ticket change and
## should stay small. Only what is in a record is shown: the lines under the
## table (notes()) are worked out when it is read, so their wording can change
## without touching what is saved.

const PATH := "user://race_history.cfg"
## The most recent races kept. Older ones drop off the end.
const KEEP := 50

const MODE_AI := "ai"
const MODE_LAN := "lan"
## The tag each kind of race wears, in the list and on the report, and its
## colour -- two hues far apart, so the two kinds are told apart at a glance
## before a word is read.
const MODE_TAGS := {MODE_AI: "VS AI", MODE_LAN: "LAN"}
const MODE_COLORS := {MODE_AI: Color(1.0, 0.72, 0.2), MODE_LAN: Color(0.3, 0.85, 1.0)}

const MONTHS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

## One racer's line in a record. `time` is the finish time, or below zero for
## a racer who never crossed -- then `score` is how far they got. `led` is the
## share of the race they spent in front, 0 to 1.
static func racer(name: String, color: Color, me: bool, time: float, score: int,
		falls: int, streak: int, led: float, item_tally: Array) -> Dictionary:
	return {
		"name": name, "color": color, "me": me, "time": time, "score": score,
		"falls": falls, "streak": streak, "led": led,
		"hits": int(item_tally[0]), "taken": int(item_tally[1]), "blocks": int(item_tally[2]),
	}

## Finishing order: those over the line by time, then the rest by how far
## they got.
static func sort_racers(racers: Array) -> void:
	racers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: float = a["time"]
		var tb: float = b["time"]
		if (ta < 0.0) != (tb < 0.0):
			return tb < 0.0
		if ta >= 0.0:
			return ta < tb
		return int(a["score"]) > int(b["score"]))

## Newest first.
static func load_all() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return []
	var races: Variant = cfg.get_value("history", "races", [])
	return races if races is Array else []

static func add(record: Dictionary) -> void:
	var races := load_all()
	races.push_front(record)
	if races.size() > KEEP:
		races.resize(KEEP)
	var cfg := ConfigFile.new()
	cfg.set_value("history", "races", races)
	cfg.save(PATH)

static func mode_tag(record: Dictionary) -> String:
	return MODE_TAGS.get(record.get("mode", MODE_AI), "VS AI")

static func mode_color(record: Dictionary) -> Color:
	return MODE_COLORS.get(record.get("mode", MODE_AI), Color.WHITE)

## This phone's line in the record, or empty.
static func mine(record: Dictionary) -> Dictionary:
	for entry in record.get("racers", []):
		if entry.get("me", false):
			return entry
	return {}

## This phone's place, from 1, or 0 if it is not in the record.
static func place(record: Dictionary) -> int:
	var racers: Array = record.get("racers", [])
	for i in range(racers.size()):
		if racers[i].get("me", false):
			return i + 1
	return 0

## "2ND OF 8", or "DID NOT FINISH" for a race this phone never crossed.
static func headline(record: Dictionary) -> String:
	var racers: Array = record.get("racers", [])
	var at := place(record)
	if at == 0:
		return "RACE"
	if float(mine(record).get("time", -1.0)) < 0.0 and record.get("mode", MODE_AI) == MODE_LAN:
		return "DID NOT FINISH"
	return "%s OF %d" % [ordinal(at), racers.size()]

## "MASTER  20,000" / "20,000  ITEM BOXES": what kind of race it was, after
## the tag.
static func summary(record: Dictionary) -> String:
	var parts := PackedStringArray()
	if record.get("mode", MODE_AI) == MODE_AI:
		parts.append(str(record.get("difficulty", "")))
	parts.append(thousands(int(record.get("target", 0))))
	if record.get("items", false):
		parts.append("ITEMS")
	return "   ".join(parts)

## This phone's finish time, or how far it got.
static func result(record: Dictionary) -> String:
	var entry := mine(record)
	if entry.is_empty():
		return ""
	var time: float = entry.get("time", -1.0)
	return race_time(time) if time >= 0.0 else thousands(int(entry.get("score", 0)))

## "06 OCT 14:32", local time.
static func date(record: Dictionary) -> String:
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	var at := Time.get_datetime_dict_from_unix_time(int(record.get("when", 0)) + bias * 60)
	return "%02d %s %02d:%02d" % [at["day"], MONTHS[int(at["month"]) - 1], at["hour"], at["minute"]]

## The lines under the table: who won, who led, and whatever else stood out.
## Only what actually happened gets a line.
static func notes(record: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var racers: Array = record.get("racers", [])
	if racers.is_empty():
		return lines
	var winner: Dictionary = racers[0]
	if float(winner["time"]) >= 0.0:
		lines.append("%s WON IN %s" % [winner["name"], race_time(winner["time"])])
	var front := _most(racers, "led")
	if not front.is_empty() and float(front["led"]) >= 0.01:
		lines.append("%s LED %d%% OF THE RACE" % [front["name"], roundi(float(front["led"]) * 100.0)])
	var streaker := _most(racers, "streak")
	if not streaker.is_empty() and int(streaker["streak"]) >= 2:
		lines.append("LONGEST STREAK: %s, %d" % [streaker["name"], streaker["streak"]])
	var faller := _most(racers, "falls")
	if not faller.is_empty() and int(faller["falls"]) > 0:
		var count := int(faller["falls"])
		lines.append("%s FELL %d TIME%s" % [faller["name"], count, "" if count == 1 else "S"])
	if record.get("items", false):
		var hitter := _most(racers, "hits")
		if not hitter.is_empty() and int(hitter["hits"]) > 0:
			var count := int(hitter["hits"])
			lines.append("%s LANDED %d HIT%s" % [hitter["name"], count, "" if count == 1 else "S"])
		var target := _most(racers, "taken")
		if not target.is_empty() and int(target["taken"]) > 0:
			var count := int(target["taken"])
			lines.append("%s TOOK %d HIT%s" % [target["name"], count, "" if count == 1 else "S"])
	return lines

## The racer with the most of `key`, the better-placed one on a tie.
static func _most(racers: Array, key: String) -> Dictionary:
	var best := {}
	for entry in racers:
		if best.is_empty() or float(entry.get(key, 0)) > float(best.get(key, 0)):
			best = entry
	return best

static func ordinal(at: int) -> String:
	match at:
		1:
			return "1ST"
		2:
			return "2ND"
		3:
			return "3RD"
	return "%dTH" % at

## Tenths: races are decided by them.
static func race_time(seconds: float) -> String:
	var t := maxf(seconds, 0.0)
	return "%d:%04.1f" % [int(t / 60.0), fmod(t, 60.0)]

static func thousands(value: int) -> String:
	var digits := str(value)
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return digits + out
