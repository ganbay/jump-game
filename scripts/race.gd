extends Node

## Race mode: the player against a bot that climbs the same course, first to
## the target score wins. An autoload so the choice made on the race screen
## survives the scene change into main.tscn and every restart after it.
##
## `active` is what game.gd branches on. The race screen switches it on and
## the menu's tap-to-play switches it off, so a classic run can never pick up
## race rules from a race played earlier in the session.

## GRANDMASTER is hidden until the player beats MASTER, at any distance (see
## unlock_grandmaster()).
enum Difficulty { NOVICE, APPRENTICE, EXPERT, MASTER, GRANDMASTER }

const DIFFICULTY_NAMES := ["NOVICE", "APPRENTICE", "EXPERT", "MASTER", "GRANDMASTER"]
## The score per second each bot averages over a race. Score is height / 10,
## the same units as the HUD and the game-over SPEED line, so these can be read
## straight against a player's own Stats.average_speed(). Never shown to the
## player. Simulated to land within ~1/s of these at 10,000 (Master drifts
## to just under 100 over 30,000, where the widest gaps slow any climb).
##
## The ceiling, measured the same way with the bot flaring on every landing it
## can: ~128/s over 10,000, ~134 over 20,000, ~146 over 30,000 -- longer races
## allow longer streaks, and streaks compound. GRANDMASTER's 120 therefore sits
## right against the ceiling over the short race, so there it runs at
## GRANDMASTER_SHORT_PACE instead (see pace()).
const PACES := [25.0, 50.0, 75.0, 100.0, 120.0]
const GRANDMASTER_SHORT_PACE := 115.0
## How often the bot fumbles a flare it went for, which breaks its streak the
## way a mistimed tap breaks the player's. Lower bots are sloppier, so they
## lose streaks more and their pace comes in bursts, like a person's.
const FUMBLE_RATES := [0.12, 0.08, 0.05, 0.03, 0.02]
const TARGETS := [10000, 20000, 30000]
## Seconds a fall costs, for either racer, before they are dropped back in.
const RESPAWN_PENALTY := 2.0

## Race mode opens after this many finished casual runs. Counted off
## Stats.games_played, which only casual runs add to -- races are never
## recorded there -- so it can never be raced open.
const UNLOCK_RUNS := 10

## --- Tickets ---
## Every race but a Novice one costs a ticket, charged when it starts (so
## quitting or replaying mid-race still costs one) and refunded on a win.
## Tickets come from good casual runs -- the first of each day to reach
## DAILY_MIN_SCORE pays DAILY_TICKETS, and after that any run reaching
## RUN_MIN_SCORE pays one -- and from an ad for AD_TICKETS. Earning by score
## rather than by run count means tickets reward playing well, not just
## dying quickly; with the free Novice tier, a player with no ads available
## is still never locked out.
const TICKET_CAP := 10
const STARTER_TICKETS := 5
const DAILY_TICKETS := 5
const DAILY_MIN_SCORE := 5000
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

const SAVE_PATH := "user://race.cfg"

var active: bool = false
## Whether the menu's mode picker was last left on RACE rather than CASUAL,
## so the menu reopens on the mode the player was using.
var menu_on_race: bool = false
var difficulty: Difficulty = Difficulty.APPRENTICE
var target_index: int = 0
var grandmaster_unlocked: bool = false
var tickets: int = 0
var _starter_granted: bool = false
## The local date (YYYY-MM-DD) the daily grant was last paid on.
var _last_daily: String = ""
## Unix time the last ad refill was granted. Wall-clock, since the cooldown
## has to survive the app closing -- see ad_cooldown_left for the clock guard.
var _last_ad_unix: int = 0
## Whether the race in progress took a ticket, and so has one to refund.
var _paid: bool = false

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		grandmaster_unlocked = cfg.get_value("unlocks", "grandmaster", false)
		difficulty = clampi(cfg.get_value("race", "difficulty", Difficulty.APPRENTICE),
			0, Difficulty.size() - 1) as Difficulty
		if difficulty == Difficulty.GRANDMASTER and not grandmaster_unlocked:
			difficulty = Difficulty.MASTER
		target_index = clampi(cfg.get_value("race", "target_index", 0), 0, TARGETS.size() - 1)
		menu_on_race = cfg.get_value("menu", "on_race", false)
		tickets = cfg.get_value("tickets", "count", 0)
		_starter_granted = cfg.get_value("tickets", "starter_granted", false)
		_last_daily = cfg.get_value("tickets", "last_daily", "")
		_last_ad_unix = cfg.get_value("tickets", "last_ad", 0)
	# A player who already had the runs before tickets existed gets the starter
	# grant quietly here; one who crosses the line later gets it announced on
	# the game-over screen (see award_casual_run).
	if is_unlocked() and not _starter_granted:
		_starter_granted = true
		tickets = maxi(tickets, STARTER_TICKETS)
		_save_tickets()

func is_unlocked() -> bool:
	return Stats.games_played >= UNLOCK_RUNS

func runs_to_unlock() -> int:
	return maxi(UNLOCK_RUNS - Stats.games_played, 0)

func target() -> int:
	return TARGETS[target_index]

func pace() -> float:
	if difficulty == Difficulty.GRANDMASTER and target_index == 0:
		return GRANDMASTER_SHORT_PACE
	return PACES[difficulty]

## The difficulties the race screen offers: all of them once GRANDMASTER is
## unlocked, every one but it before.
func available_difficulties() -> int:
	return Difficulty.size() if grandmaster_unlocked else Difficulty.GRANDMASTER

## Called on a win. Returns true only on the win that unlocks it, so the
## finish screen announces it once.
func unlock_grandmaster() -> bool:
	if grandmaster_unlocked or difficulty != Difficulty.MASTER:
		return false
	grandmaster_unlocked = true
	var cfg := _load()
	cfg.set_value("unlocks", "grandmaster", true)
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

func set_menu_on_race(on_race: bool) -> void:
	menu_on_race = on_race
	var cfg := _load()
	cfg.set_value("menu", "on_race", on_race)
	cfg.save(SAVE_PATH)

## Fastest winning time for this bot and distance, or 0.0 if never won.
func best_time(for_difficulty: int = difficulty, for_target_index: int = target_index) -> float:
	return _load().get_value("best", _best_key(for_difficulty, for_target_index), 0.0)

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
## player cannot afford it.
func pay_for_race() -> bool:
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

## Called once per finished casual run, after Stats.record_run, with its
## score. What it returns is what the game-over screen tells the player:
##   kind       "locked", "unlocked", "daily", "run", "daily_pending",
##              "run_pending" or "full"
##   gained     tickets actually added
##   runs_left  runs to go until race mode unlocks ("locked" only)
func award_casual_run(score: int) -> Dictionary:
	if not is_unlocked():
		return {"kind": "locked", "gained": 0, "runs_left": runs_to_unlock()}
	if not _starter_granted:
		_starter_granted = true
		return {"kind": "unlocked", "gained": add_tickets(STARTER_TICKETS), "runs_left": 0}
	var today := Time.get_date_string_from_system()
	var daily_open := _last_daily != today
	if is_full():
		# Nothing to hand out, and the daily grant stays unclaimed rather than
		# being spent on a full wallet.
		return {"kind": "full", "gained": 0, "runs_left": 0}
	if daily_open:
		if score < DAILY_MIN_SCORE:
			return {"kind": "daily_pending", "gained": 0, "runs_left": 0}
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

## Every ticket change lands here, so this is the one place that decides
## whether the reminder should be pending.
func _update_ready_notification() -> void:
	if tickets == 0 and ad_cooldown_left() > 0:
		Notify.schedule_at(READY_NOTIFICATION, _last_ad_unix + AD_COOLDOWN,
			READY_TITLE, READY_BODY)
	else:
		Notify.cancel(READY_NOTIFICATION)

func _best_key(for_difficulty: int, for_target_index: int) -> String:
	return "%s_%d" % [DIFFICULTY_NAMES[for_difficulty].to_lower(), TARGETS[for_target_index]]

func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	return cfg
