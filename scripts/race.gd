extends Node

## Race mode: the player against a bot that climbs the same course, first to
## the target score wins. An autoload so the choice made on the race screen
## survives the scene change into main.tscn and every restart after it.
##
## `active` is what game.gd branches on. The race screen switches it on and
## the menu's tap-to-play switches it off, so a classic run can never pick up
## race rules from a race played earlier in the session.

## Each AI below GRANDMASTER opens off casual play: NOVICE with the first
## finished run, the rest at a casual best score of UNLOCK_SCORES. GRANDMASTER
## is hidden until the player beats MASTER, at any distance (see
## unlock_grandmaster()).
enum Difficulty { NOVICE, APPRENTICE, EXPERT, MASTER, GRANDMASTER }

const DIFFICULTY_NAMES := ["NOVICE", "APPRENTICE", "EXPERT", "MASTER", "GRANDMASTER"]
## The score per second each bot averages over a race. Score is height / 10,
## the same units as the HUD and the game-over SPEED line, so these can be read
## straight against a player's own Stats.average_speed(). Never shown to the
## player. Simulated over a few minutes of race, each lands within ~2/s of
## its number; over a shorter stretch a bot can run 10% off it either way, as
## a Solar Wind burst or a broken streak is caught up or paid back.
##
## The ceiling, measured the same way with the bot flaring on every landing it
## can: ~128/s over 10,000, ~134 over 20,000, ~146 over 30,000 -- longer races
## allow longer streaks, and streaks compound. GRANDMASTER's 120 therefore sits
## right against the ceiling over the short race, so there it runs at
## GRANDMASTER_SHORT_PACE instead (see pace()).
const PACES := [20.0, 40.0, 60.0, 90.0, 120.0]
const GRANDMASTER_SHORT_PACE := 115.0
## How often the bot fumbles a flare it went for, which breaks its streak the
## way a mistimed tap breaks the player's. Lower bots are sloppier, so they
## lose streaks more and their pace comes in bursts, like a person's.
const FUMBLE_RATES := [0.12, 0.08, 0.05, 0.03, 0.02]
const TARGETS := [10000, 20000, 30000]
## How many racers a bot race lines up, the player included. Past two, the
## bots are a field rather than one opponent: the quickest of them runs the
## picked AI's pace and the rest string out behind it (see
## RaceBot.set_persona), so beating the field is beating that AI -- which is
## why best times and the GRANDMASTER unlock are shared across field sizes.
const FIELD_SIZES := [2, 4, 8]
## Seconds a fall costs, for either racer, before they are dropped back in.
const RESPAWN_PENALTY := 2.5

## Race mode -- and with it NOVICE -- opens after this many finished casual
## runs. Counted off Stats.games_played, which only casual runs add to --
## races are never recorded there -- so it can never be raced open.
const UNLOCK_RUNS := 1
## Casual best score that opens each AI, indexed by Difficulty. NOVICE's 0
## means "with race mode itself"; GRANDMASTER's -1 means "not by score".
const UNLOCK_SCORES := [0, 5000, 10000, 20000, -1]

## --- Tickets ---
## Every race but a Novice one costs a ticket, charged when it starts (so
## quitting or replaying mid-race still costs one) and refunded on a win.
## Tickets come from casual runs -- the first of each day pays DAILY_TICKETS
## whatever it scores, and after that any run reaching RUN_MIN_SCORE pays
## one -- and from an ad for AD_TICKETS. The daily grant is a reason to open
## the game each day; the per-run one rewards playing well rather than dying
## quickly. With the free Novice tier, a player with no ads available is
## still never locked out.
const TICKET_CAP := 10
const STARTER_TICKETS := 5
const DAILY_TICKETS := 5
const RUN_MIN_SCORE := 10000
const AD_TICKETS := 5
## One ad refill per this many seconds, shared by every place that offers it.
## A cooldown rather than a daily count: it hands a player a reason to come
## back later instead of a number to burn through in one sitting.
const AD_COOLDOWN := 2 * 3600
## A local reminder for when the cooldown ends -- only while the player is out
## of tickets, the one time it is news. The copy never mentions the ad.
const READY_NOTIFICATION := "race_tickets_ready"
const READY_TITLE := "Ready for a rematch?"
const READY_BODY := "You can top up your race tickets again."
## A daily reminder, at DAILY_HOUR local time, while the daily grant is
## waiting to be claimed -- pushed to the next day once it has been.
const DAILY_NOTIFICATION := "race_daily_tickets"
const DAILY_HOUR := 17
const DAILY_TITLE := "Your daily 5 tickets are ready!"
const DAILY_BODY := "Play one casual run to collect them."

const SAVE_PATH := "user://race.cfg"
## Owned by game.gd; read once here to seed the casual best for an older save.
const HIGH_SCORE_PATH := "user://highscore.cfg"

var active: bool = false
## Which mode the menu's picker was last left on (main_menu.gd's Mode), so
## the menu reopens on the mode the player was using.
var menu_mode: int = 0
var difficulty: Difficulty = Difficulty.NOVICE
var target_index: int = 0
var field_index: int = 0
## Item boxes in bot races (see race_items.gd), picked on the race screen.
## Off by default: a race with items on sets no record -- no best time, no
## speed for Stats or the Play leaderboards -- since a Rocket run is not
## comparable with a clean one. It still counts as a win: beating MASTER with
## items on unlocks GRANDMASTER all the same.
var items_on: bool = false
var grandmaster_unlocked: bool = false
## Best casual score, kept here so the AI unlocks can be read without
## reaching into game.gd. Fed by award_casual_run.
var _best_casual: int = 0
## Difficulties the menu has already announced as unlocked (see
## claim_new_unlocks), so each popup is shown once.
var _announced: Array = []
var tickets: int = 0
var _starter_granted: bool = false
## The local date (YYYY-MM-DD) the daily grant was last paid on.
var _last_daily: String = ""
## Unix time the last ad refill was granted. Wall-clock, since the cooldown
## has to survive the app closing -- see ad_cooldown_left for the clock guard.
var _last_ad_unix: int = 0
## The course the next race is laid out from, or -1 for a fresh roll each
## race (the bot races). Set by whatever sets up a shared race -- the planned
## LAN/online modes -- so every racer climbs the same platforms. Never saved:
## a shared seed belongs to one session. See docs/seeded-course.md.
var course_seed: int = -1
## The distance a shared race (LAN) runs to, or 0 to use target_index. Kept
## apart from target_index so a LAN race never changes, or saves over, the
## distance picked for bot races.
var shared_target: int = 0
## Whether the race in progress took a ticket, and so has one to refund.
var _paid: bool = false

func _ready() -> void:
	var scores := ConfigFile.new()
	if scores.load(HIGH_SCORE_PATH) == OK:
		_best_casual = int(scores.get_value("scores", "high_score", 0))
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		grandmaster_unlocked = cfg.get_value("unlocks", "grandmaster", false)
		difficulty = clampi(cfg.get_value("race", "difficulty", Difficulty.NOVICE),
			0, Difficulty.size() - 1) as Difficulty
		target_index = clampi(cfg.get_value("race", "target_index", 0), 0, TARGETS.size() - 1)
		field_index = clampi(cfg.get_value("race", "field_index", 0), 0, FIELD_SIZES.size() - 1)
		items_on = cfg.get_value("race", "items_on", false)
		# "on_race" is the picker's save from when it only had two modes.
		menu_mode = cfg.get_value("menu", "mode",
			1 if cfg.get_value("menu", "on_race", false) else 0)
		tickets = cfg.get_value("tickets", "count", 0)
		_starter_granted = cfg.get_value("tickets", "starter_granted", false)
		_last_daily = cfg.get_value("tickets", "last_daily", "")
		_last_ad_unix = cfg.get_value("tickets", "last_ad", 0)
	# A save from before the popups existed: what it could already race was
	# already known to the player, so it is marked seen rather than announced.
	if cfg.has_section_key("unlocks", "announced"):
		_announced = cfg.get_value("unlocks", "announced", [])
	elif _starter_granted:
		_announced = range(Difficulty.size()).filter(is_difficulty_unlocked)
		_save_announced()
	# A pick saved before the score gates, or on a tier since gated, falls back
	# to the hardest one open.
	if not is_difficulty_unlocked(difficulty):
		difficulty = highest_unlocked()
	# A player who already had the runs before tickets existed gets the starter
	# grant quietly here; one who crosses the line later gets it announced on
	# the game-over screen (see award_casual_run).
	if is_unlocked() and not _starter_granted:
		_starter_granted = true
		tickets = maxi(tickets, STARTER_TICKETS)
	_save_tickets()
	# Wins from before Stats kept race speeds: the best times here are the
	# only record of them. A no-op once Stats has caught up.
	for i in range(TARGETS.size()):
		Stats.record_race_speed(TARGETS[i], _best_speed_from_times(i))

func is_unlocked() -> bool:
	return Stats.games_played >= UNLOCK_RUNS

func runs_to_unlock() -> int:
	return maxi(UNLOCK_RUNS - Stats.games_played, 0)

func target() -> int:
	return shared_target if shared_target > 0 else TARGETS[target_index]

func pace() -> float:
	if difficulty == Difficulty.GRANDMASTER and target_index == 0:
		return GRANDMASTER_SHORT_PACE
	return PACES[difficulty]

## The difficulties the race screen lists: all of them once GRANDMASTER is
## unlocked, every one but it before. Listed is not the same as open -- see
## is_difficulty_unlocked; the locked ones show what it takes to open them.
func available_difficulties() -> int:
	return Difficulty.size() if grandmaster_unlocked else Difficulty.GRANDMASTER

func is_difficulty_unlocked(for_difficulty: int) -> bool:
	if not is_unlocked():
		return false
	# Beating MASTER proves every tier under it, whatever the casual best.
	if grandmaster_unlocked:
		return true
	var needed: int = UNLOCK_SCORES[for_difficulty]
	return needed >= 0 and _best_casual >= needed

func highest_unlocked() -> Difficulty:
	for i in range(Difficulty.size() - 1, -1, -1):
		if is_difficulty_unlocked(i):
			return i as Difficulty
	return Difficulty.NOVICE

## The casual score that opens `for_difficulty`, -1 when score does not.
func unlock_score(for_difficulty: int) -> int:
	return UNLOCK_SCORES[for_difficulty]

## Unlocked difficulties not yet announced, easiest first, marked announced as
## they are handed over. The menu calls this on entry and pops one up each.
func claim_new_unlocks() -> Array[int]:
	var newly: Array[int] = []
	for i in range(Difficulty.size()):
		if is_difficulty_unlocked(i) and not _announced.has(i):
			_announced.append(i)
			newly.append(i)
	if not newly.is_empty():
		_save_announced()
	return newly

func _save_announced() -> void:
	var cfg := _load()
	cfg.set_value("unlocks", "announced", _announced)
	cfg.save(SAVE_PATH)

## Called on a win. Returns true only on the win that unlocks it, so the
## finish screen announces it once.
func unlock_grandmaster() -> bool:
	if grandmaster_unlocked or difficulty != Difficulty.MASTER:
		return false
	grandmaster_unlocked = true
	# The finish screen announces this one, so the menu does not repeat it.
	# Tiers below it that it opens early (see is_difficulty_unlocked) are
	# left for the menu to announce.
	_announced.append(Difficulty.GRANDMASTER)
	var cfg := _load()
	cfg.set_value("unlocks", "grandmaster", true)
	cfg.set_value("unlocks", "announced", _announced)
	cfg.save(SAVE_PATH)
	return true

func fumble_rate() -> float:
	return FUMBLE_RATES[difficulty]

func difficulty_name() -> String:
	return DIFFICULTY_NAMES[difficulty]

## Saves the pick so the race screen opens on it next time.
func choose(new_difficulty: Difficulty, new_target_index: int) -> void:
	difficulty = new_difficulty
	target_index = new_target_index
	var cfg := _load()
	cfg.set_value("race", "difficulty", difficulty)
	cfg.set_value("race", "target_index", target_index)
	cfg.save(SAVE_PATH)

func bot_count() -> int:
	return FIELD_SIZES[field_index] - 1

func set_field(index: int) -> void:
	field_index = index
	var cfg := _load()
	cfg.set_value("race", "field_index", index)
	cfg.save(SAVE_PATH)

func set_items_on(on: bool) -> void:
	items_on = on
	var cfg := _load()
	cfg.set_value("race", "items_on", on)
	cfg.save(SAVE_PATH)

func set_menu_mode(mode: int) -> void:
	menu_mode = mode
	var cfg := _load()
	cfg.set_value("menu", "mode", mode)
	cfg.save(SAVE_PATH)

## Fastest winning time for this bot and distance, or 0.0 if never won.
func best_time(for_difficulty: int = difficulty, for_target_index: int = target_index) -> float:
	return _load().get_value("best", _best_key(for_difficulty, for_target_index), 0.0)

## The fastest win on record for a distance, across every AI, or 0.0 with no
## win yet. The distance is fixed, so the shortest time is the highest speed.
func _best_speed_from_times(for_target_index: int) -> float:
	var cfg := _load()
	var best := 0.0
	for i in range(DIFFICULTY_NAMES.size()):
		var time: float = cfg.get_value("best", _best_key(i, for_target_index), 0.0)
		if time > 0.0 and (best <= 0.0 or time < best):
			best = time
	return TARGETS[for_target_index] / best if best > 0.0 else 0.0

## Records a win. Returns whether it beat the previous best.
func record_win(time: float) -> bool:
	var cfg := _load()
	var key := _best_key(difficulty, target_index)
	var previous: float = cfg.get_value("best", key, 0.0)
	if previous > 0.0 and time >= previous:
		return false
	cfg.set_value("best", key, time)
	cfg.save(SAVE_PATH)
	return true

# --- Tickets --------------------------------------------------------------

func race_cost(for_difficulty: int = difficulty) -> int:
	return 0 if for_difficulty == Difficulty.NOVICE else 1

func can_start(for_difficulty: int = difficulty) -> bool:
	return tickets >= race_cost(for_difficulty)

## Charges for the race about to start. False, and nothing charged, when the
## player cannot afford it. A LAN race is free: it never comes through here
## (the lobby starts it), and this makes sure no rematch path charges either.
func pay_for_race() -> bool:
	if LanRace.in_race():
		_paid = false
		return true
	if not can_start():
		return false
	var cost := race_cost()
	tickets -= cost
	_paid = cost > 0
	_save_tickets()
	return true

## The winner's refund. Never capped: it only ever hands back what was paid.
func refund_race() -> bool:
	if not _paid:
		return false
	_paid = false
	tickets += 1
	_save_tickets()
	return true

## Adds up to `amount`, stopping at the cap. Returns how many actually landed.
func add_tickets(amount: int) -> int:
	var gained := clampi(amount, 0, maxi(TICKET_CAP - tickets, 0))
	tickets += gained
	_save_tickets()
	return gained

func is_full() -> bool:
	return tickets >= TICKET_CAP

## Seconds until the next ad refill is allowed, 0 when it is.
##
## A clock wound back past the last refill would otherwise read as a negative
## elapsed time -- a cooldown that never ends. Instead the refill is treated
## as having happened just now: a full cooldown from here, never more. Winding
## the clock forward cannot be caught offline; that is accepted, as it is for
## the daily bonus.
func ad_cooldown_left() -> int:
	var now := int(Time.get_unix_time_from_system())
	if now < _last_ad_unix:
		_last_ad_unix = now
		_save_tickets()
	return maxi(AD_COOLDOWN - (now - _last_ad_unix), 0)

## Whether an ad refill may be offered right now (an ad being loaded is the
## caller's to check -- Ads.is_rewarded_ready()).
func can_watch_ad() -> bool:
	return not is_full() and ad_cooldown_left() == 0

## The reward for a watched refill ad. Starts the cooldown only here, once
## the reward is earned: an ad that fails or is closed early costs nothing.
func grant_ad_tickets() -> int:
	_last_ad_unix = int(Time.get_unix_time_from_system())
	return add_tickets(AD_TICKETS)

## Whether the next casual run would pay the daily grant -- what the menu's
## "play casual" line and the daily reminder both key off. A full wallet
## leaves the grant unclaimed, so it is not offered then.
func daily_available() -> bool:
	return is_unlocked() and _last_daily != Time.get_date_string_from_system() \
		and not is_full()

## Called once per finished casual run, after Stats.record_run, with its
## score. What it returns is what the game-over screen tells the player:
##   kind       "locked", "unlocked", "daily", "run", "run_pending" or "full"
##   gained     tickets actually added
##   runs_left  runs to go until race mode unlocks ("locked" only)
func award_casual_run(score: int) -> Dictionary:
	_best_casual = maxi(_best_casual, score)
	if not is_unlocked():
		return {"kind": "locked", "gained": 0, "runs_left": runs_to_unlock()}
	var today := Time.get_date_string_from_system()
	if not _starter_granted:
		# The unlocking run is also that day's daily grant, so a new player
		# starts on DAILY_TICKETS rather than twice that.
		_starter_granted = true
		_last_daily = today
		return {"kind": "unlocked", "gained": add_tickets(DAILY_TICKETS), "runs_left": 0}
	if is_full():
		# Nothing to hand out, and the daily grant stays unclaimed rather than
		# being spent on a full wallet.
		return {"kind": "full", "gained": 0, "runs_left": 0}
	if _last_daily != today:
		_last_daily = today
		return {"kind": "daily", "gained": add_tickets(DAILY_TICKETS), "runs_left": 0}
	if score < RUN_MIN_SCORE:
		return {"kind": "run_pending", "gained": 0, "runs_left": 0}
	return {"kind": "run", "gained": add_tickets(1), "runs_left": 0}

func _save_tickets() -> void:
	var cfg := _load()
	cfg.set_value("tickets", "count", tickets)
	cfg.set_value("tickets", "starter_granted", _starter_granted)
	cfg.set_value("tickets", "last_daily", _last_daily)
	cfg.set_value("tickets", "last_ad", _last_ad_unix)
	cfg.save(SAVE_PATH)
	_update_ready_notification()
	_update_daily_notification()

## Every ticket change lands here, so this is the one place that decides
## whether the reminder should be pending.
func _update_ready_notification() -> void:
	if tickets == 0 and ad_cooldown_left() > 0:
		Notify.schedule_at(READY_NOTIFICATION, _last_ad_unix + AD_COOLDOWN,
			READY_TITLE, READY_BODY)
	else:
		Notify.cancel(READY_NOTIFICATION)

## Repeats daily at DAILY_HOUR from the next day the grant is waiting on: today
## if it is unclaimed and the hour is still ahead, otherwise tomorrow.
## Rescheduled on every ticket change, so claiming pushes it a day on.
func _update_daily_notification() -> void:
	if not is_unlocked() or is_full():
		Notify.cancel(DAILY_NOTIFICATION)
		return
	Notify.schedule_daily(DAILY_NOTIFICATION, DAILY_HOUR, 0, DAILY_TITLE, DAILY_BODY,
		not daily_available())

func _best_key(for_difficulty: int, for_target_index: int) -> String:
	return "%s_%d" % [DIFFICULTY_NAMES[for_difficulty].to_lower(), TARGETS[for_target_index]]

func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	return cfg
