extends Node2D
class_name RaceItems

## Item boxes in a race (see docs/lan-items.md). Owned by game.gd, only when
## ITEM BOXES is on: the host's switch in a LAN race, Race.items_on against
## the AI.
##
## Against the AI (`bots` set) nothing goes over a network: each bot takes
## its own boxes and uses its own items (see race_bot.gd), and an attack --
## the player's at a bot, a bot's at the player, or one bot's at another -- is
## handed across right here, under the bot's id (BOT_ID down).
##
## Gates of boxes sit across the course at fixed scores. Every racer has their
## own copy of every box, so pickups and rolls never go over the network. The
## self items act on this phone's player alone; an attack is a message through
## the host (LanRace.send_attack), and the phone it lands on applies it to its
## own player -- the same rule the race already lives by.
##
## Gates are laid from the score origin, which is the same on every phone (see
## game.gd:_launch_apex_y), at fixed x across the shared course band. No RNG is
## drawn, so the course itself -- and its hash -- is untouched.
##
## Checks run in _physics_process, after the player's own (it is added to the
## tree later), so a crossing is judged on the position physics just produced.

signal changed

## Sent over the network as ints: new items go on the end.
enum Item { NONE, ROCKET, NET, SPRING, SHIELD, COMET, REVERSE, SHOCKWAVE }

const NAMES := {
	Item.ROCKET: "ROCKET",
	Item.NET: "SAFETY NET",
	Item.SPRING: "SPRING SHOES",
	Item.SHIELD: "SHIELD",
	Item.COMET: "COMET",
	Item.REVERSE: "REVERSE",
	Item.SHOCKWAVE: "SHOCKWAVE",
}
## What the box roulette cycles through, and what a roll can land on -- in
## the column order of ODDS.
const ROLLABLE := [Item.ROCKET, Item.NET, Item.SPRING, Item.SHIELD, Item.COMET, Item.REVERSE,
	Item.SHOCKWAVE]
const ATTACKS := [Item.COMET, Item.REVERSE, Item.SHOCKWAVE]
## A field this big is too many for one Comet to matter: it takes out the
## first COMET_TARGETS_BIG of the racers ahead instead of just the leader.
const BIG_FIELD := 8
const COMET_TARGETS_BIG := 2
## The first AI's id in the feed and the warnings, where a LAN racer's is its
## peer id. Peer ids are positive; a field's bots count down from here (see
## RaceBot.bot_id).
const BOT_ID := -1
## The bot's own copy of a gate gives it an item this often: its lane through
## the gate is not simulated, and about nine lanes in ten collect.
const BOT_PICKUP_ODDS := 0.9

## The AIs' names and colours by id, for the static lookups below.
static var bot_names: Dictionary = {}
static var bot_colors: Dictionary = {}

const FONT := preload("res://fonts/Chillax-Bold.otf")

## In score: 1,500 makes ~6 / 13 / 20 gates over the three race distances.
const GATE_EVERY := 1500
## No gate this close to the finish: an item there could never be used.
const GATE_FINISH_CLEARANCE := 500
const BOXES_PER_GATE := 4
## Box centre to character centre, sideways. Boxes are 180 px apart on the
## shared course, so this covers about nine lanes in ten through a gate.
const PICKUP_REACH := 78.0
const BOX_SIZE := 52.0
const BOX_BOB := 6.0
const GATE_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.16)
const POP_TIME := 0.35
## Once a box of a gate is taken, the rest of its row shrinks and fades out
## over this long, so a gate reads as used up rather than still on offer.
const ROW_FADE_TIME := 0.45
## The box roulette. Long enough to read as a spin, short enough not to wait on.
const ROLL_TIME := 0.8

const ROCKET_TIME := 2.0
const ROCKET_SPEED := 1800.0
const NET_TIME := 15.0
## The net hangs this far above the bottom edge of the screen, so the bounce
## is seen rather than happening just out of view.
const NET_INSET := 40.0
## Clears the screen's height from the bottom edge, back up to the platforms.
const NET_BOUNCE_VELOCITY := -2000.0
const NET_COLOR := Color(0.6, 1.8, 2.2, 1.0)
const NET_WARN_TIME := 3.0
const SPRING_LANDINGS := 4
## Spring Shoes' boosted jumps launch this much faster than a timed one --
## about half as high again, since height goes with speed squared.
const SPRING_JUMP_MULT := 1.25
const SHIELD_TIME := 10.0
## From an attack arriving to it landing: the warning, and the window for a
## held Shield to go up in time.
const ATTACK_WARN_TIME := 1.0
const COMET_STUN := 2.0
## A Comet is a homing missile: it comes down over the warning steering
## sideways after its target the whole way, and it always arrives. There is
## no getting out from under it -- only a Shield stops one. The chase is for
## the eye: faster flat out than the character (900 px/s) but slower to turn,
## so it swings wide behind a sharp change of direction and comes back in.
## COMET_HOMING is how hard it steers for a given miss: speed wanted per
## pixel off target.
const COMET_SPEED := 1100.0
const COMET_TURN := 2200.0
const COMET_HOMING := 6.0
## Where it comes in from, to the side of its target.
const COMET_ENTRY_OFFSET := 160.0
const REVERSE_TIME := 4.0
## The Shockwave's stun: shorter than a Comet's, since it lands on everyone
## ahead at once.
const SHOCK_STUN := 1.2
const SHOCK_COLOR := Color(1.5, 2.6, 0.5, 1.0)
## Screen heights a second the wave travels once it is loose -- off the
## thrower, and on past whoever it hit.
const SHOCK_SPEED := 2600.0
const SHOCK_FADE_TIME := 0.5
const SHIELD_COLOR := Color(0.7, 1.6, 2.4, 1.0)
const COMET_COLOR := Color(2.6, 1.2, 0.3, 1.0)
const REVERSE_COLOR := Color(2.2, 0.6, 2.2, 1.0)
## How long a line stays in the feed, and the most lines it shows at once.
const FEED_TIME := 3.0
const FEED_LINES := 3
const NOTICE_TIME := 1.6

## The odds, by how far behind the leader this phone is, in gates
## (GATE_EVERY of score). Rows are [gap, rocket, net, spring, shield, comet,
## reverse, shockwave], interpolated between: the further back, the more it
## leans to the Rocket and the attacks. The leader (gap 0) gets only defence.
##
## These are how likely; available() is whether at all. A roll only ever
## lands on what the racer's place in the field allows.
const ODDS := [
	[0.0, 0.0, 0.4, 0.2, 0.4, 0.0, 0.0, 0.2],
	[0.5, 0.15, 0.15, 0.25, 0.1, 0.15, 0.2, 0.25],
	[1.5, 0.3, 0.05, 0.15, 0.0, 0.25, 0.25, 0.3],
	[3.0, 0.45, 0.0, 0.05, 0.0, 0.3, 0.2, 0.3],
]

## Whether the racer in `place` (1 is the leader) of `racers` can roll `item`
## at all. The one table of who gets what:
##   SPRING SHOES  everyone
##   SAFETY NET    the front half
##   SHIELD        anyone with a racer behind them -- attacks only go forward
##   ROCKET        outside the front quarter, and never the leader
##   COMET         anyone but the leader
##   REVERSE       anyone but the leader
##   SHOCKWAVE     the back quarter of the field, and always the last racer:
##                 the last of 2 or 4, the last two of 8
static func available(item: int, place: int, racers: int) -> bool:
	match item:
		Item.NET:
			return place <= ceili(racers / 2.0)
		Item.SHIELD:
			return place < racers
		Item.ROCKET:
			return place > maxi(1, floori(racers / 4.0))
		Item.COMET, Item.REVERSE:
			return place > 1
		Item.SHOCKWAVE:
			return racers >= 2 and place > racers - maxi(1, floori(racers / 4.0))
	return true

## How many of the racers ahead a Comet thrown in a field of `racers` hits.
static func comet_targets(racers: int) -> int:
	return COMET_TARGETS_BIG if racers >= BIG_FIELD else 1

var player: Player
var camera: Camera2D
var rivals: Array[Rival] = []
## The AIs in a bot race, or empty in a LAN one.
var bots: Array[RaceBot] = []
## Kept up to date by game.gd. What the roll measures the gap from.
var player_score: int = 0

var held: Item = Item.NONE
## Seconds of roulette left, or 0 while not rolling.
var rolling_left: float = 0.0
var net_left: float = 0.0
var shield_left: float = 0.0
## Attacks on their way in: {from, kind, left}, left counting down to impact.
var incoming: Array[Dictionary] = []
## Who got whom, newest last: {from, victim, kind, blocked, age}.
var feed: Array[Dictionary] = []
## A line for this phone alone, under the warning: {text, color, age}, or empty.
var notice: Dictionary = {}
## Every attack's outcome so far, by racer id, for the race report:
## [hits landed, hits taken, attacks blocked].
var tally: Dictionary = {}

var _running: bool = false
var _course_left: float = 0.0
var _course_width: float = 720.0
var _gate_ys: Array[float] = []
var _spent: Array[bool] = []
## Which box of each gate was hit, or -1, so it is not drawn again.
var _taken: Array[int] = []
## _time when each gate's box was taken, for the row's fade-out; -1 if not.
var _taken_at: Array[float] = []
## [position, age] of each box burst still playing.
var _pops: Array = []
## [y it left from, age] of each Shockwave front on its way up the screen.
var _waves: Array = []
var _prev_y: float = 0.0
var _time: float = 0.0
## Each bot's own pass through the gates -- the next gate it has not yet
## risen through, by its place in `bots` -- and the attacks on their way to a
## bot: {from, to, kind, left}.
var _bot_next_gate: Array[int] = []
var _bot_incoming: Array[Dictionary] = []

func _ready() -> void:
	set_physics_process(false)
	LanRace.attacked.connect(_on_attacked)
	LanRace.attack_outcome.connect(_on_attack_outcome)

## At the hand-off, once the score origin is known.
func begin(score_origin_y: float, target: int, course_left: float, course_width: float) -> void:
	_course_left = course_left
	_course_width = course_width
	_gate_ys.clear()
	_spent.clear()
	_taken.clear()
	_taken_at.clear()
	var at := GATE_EVERY
	while at <= target - GATE_FINISH_CLEARANCE:
		# score = height / 10 (see game.gd)
		_gate_ys.append(score_origin_y - float(at) * 10.0)
		_spent.append(false)
		_taken.append(-1)
		_taken_at.append(-1.0)
		at += GATE_EVERY
	_bot_next_gate = []
	_bot_next_gate.resize(bots.size())
	_bot_next_gate.fill(0)
	_bot_incoming.clear()
	bot_names.clear()
	bot_colors.clear()
	for bot in bots:
		bot_names[bot.bot_id] = bot.label
		bot_colors[bot.bot_id] = bot.color
		if bot.attack_requested.get_connections().is_empty():
			bot.attack_requested.connect(_on_bot_attack.bind(bot))
	_prev_y = player.global_position.y
	_running = true
	set_physics_process(true)

## Leaves every bot's boxes untaken for the rest of the race.
func skip_bot_gates() -> void:
	_bot_next_gate.fill(_gate_ys.size())

## Over the line, or out of the race: nothing more to pick up or use.
func stop() -> void:
	_running = false
	held = Item.NONE
	rolling_left = 0.0
	net_left = 0.0
	shield_left = 0.0
	incoming.clear()
	_bot_incoming.clear()
	player.rocket_left = 0.0
	player.auto_boosts = 0
	player.stun_left = 0.0
	player.reverse_left = 0.0
	set_physics_process(false)
	changed.emit()

func can_use() -> bool:
	return _running and held != Item.NONE and rolling_left <= 0.0 \
		and player.is_physics_processing()

func use() -> bool:
	if not can_use():
		return false
	match held:
		Item.ROCKET:
			player.start_rocket(ROCKET_TIME, ROCKET_SPEED)
		Item.NET:
			net_left = NET_TIME
		Item.SPRING:
			player.auto_boosts += SPRING_LANDINGS
			player.auto_boost_mult = SPRING_JUMP_MULT
		Item.SHIELD:
			# Up against what is coming, and off with what already landed.
			shield_left = SHIELD_TIME
			player.stun_left = 0.0
			player.reverse_left = 0.0
		Item.COMET, Item.REVERSE, Item.SHOCKWAVE:
			var ahead := _racers_ahead()
			if ahead.is_empty():
				# Passed them since the roll: kept for when someone is ahead again.
				_notify("NOBODY AHEAD", Color(1.0, 1.0, 1.0, 0.8))
				return false
			# The Comet goes for the front of the race, the Reverse and the
			# Shockwave for everyone ahead.
			if held == Item.COMET:
				ahead.resize(mini(ahead.size(), comet_targets(rivals.size() + 1)))
			elif held == Item.SHOCKWAVE:
				_waves.append([player.global_position.y, 0.0])
			if not bots.is_empty():
				for rival in ahead:
					if rival is RaceBot:
						_bot_incoming.append({"from": LanRace.my_id(), "to": rival,
							"kind": held, "left": ATTACK_WARN_TIME})
			else:
				LanRace.send_attack(held, ahead.map(_id_of))
	Analytics.log_event("race_item_used" if not bots.is_empty() else "lan_item_used",
		{"item": NAMES[held]})
	held = Item.NONE
	Audio.vibrate(25)
	changed.emit()
	return true

## The status flags the others draw on this racer's ghost (LanRace.FLAG_*).
func status_flags() -> int:
	var flags := 0
	if shield_left > 0.0:
		flags |= LanRace.FLAG_SHIELDED
	if player.stun_left > 0.0:
		flags |= LanRace.FLAG_STUNNED
	if player.reverse_left > 0.0:
		flags |= LanRace.FLAG_REVERSED
	return flags

## Rivals still racing who are ahead of this phone, leader first.
func _racers_ahead() -> Array[Rival]:
	var ahead: Array[Rival] = []
	for rival in rivals:
		if _racing(rival) and rival.score > player_score:
			ahead.append(rival)
	ahead.sort_custom(func(a: Rival, b: Rival): return a.score > b.score)
	return ahead

## Still on the course: not over the line yet.
func _racing(rival: Rival) -> bool:
	return is_instance_valid(rival) and not rival.finished

func _id_of(rival: Rival) -> int:
	if rival is NetRival:
		return rival.peer_id
	return rival.bot_id if rival is RaceBot else BOT_ID

## LanRace.peers' name for `id`, YOU for this phone, or the AI's own.
static func racer_name(id: int) -> String:
	if id <= BOT_ID:
		return bot_names.get(id, "AI")
	if id == LanRace.my_id():
		return "YOU"
	return str(LanRace.peers.get(id, {}).get("name", "?"))

static func racer_color(id: int) -> Color:
	if id <= BOT_ID:
		return bot_colors.get(id, Color.WHITE)
	if id == LanRace.my_id():
		return UiAccent.color()
	return LanRace.peers.get(id, {}).get("color", Color.WHITE)

func _notify(text: String, color: Color) -> void:
	notice = {"text": text, "color": color, "age": 0.0}

func _on_attacked(from: int, kind: int) -> void:
	if not _running or kind not in ATTACKS:
		return
	incoming.append({"from": from, "kind": kind, "left": ATTACK_WARN_TIME})
	Audio.vibrate(30)
	for rival in rivals:
		if rival is NetRival and rival.peer_id == from:
			rival.flash()

## A Comet's sideways chase (see COMET_SPEED): its own x and speed, kept on
## the attack. While the character is out of the race it flies straight.
func _steer_comet(attack: Dictionary, delta: float) -> void:
	if not attack.has("x"):
		attack["x"] = player.global_position.x + COMET_ENTRY_OFFSET
		attack["vx"] = 0.0
	var vx: float = attack["vx"]
	if player.is_physics_processing():
		var miss := _wrapped_dx(attack["x"], player.global_position.x)
		var wanted := clampf(miss * COMET_HOMING, -COMET_SPEED, COMET_SPEED)
		vx = move_toward(vx, wanted, COMET_TURN * delta)
	attack["vx"] = vx
	attack["x"] += vx * delta

## Lands an attack: blocked by a raised Shield (which it uses up), or taken.
## Either way the room hears how it went.
##
## Unless there is nobody there to hit: an attack that arrives while this
## phone is sitting out a fall finds nothing, and is simply gone -- no hit, no
## block, no line in the feed.
func _land_attack(attack: Dictionary) -> void:
	if not player.is_physics_processing():
		changed.emit()
		return
	var kind: int = attack["kind"]
	var blocked := shield_left > 0.0
	if blocked:
		shield_left = 0.0
	else:
		match kind:
			Item.COMET:
				player.velocity.y = maxf(player.velocity.y, 0.0)
				player.rocket_left = 0.0
				player.stun_left = COMET_STUN
			Item.REVERSE:
				player.reverse_left = REVERSE_TIME
			Item.SHOCKWAVE:
				player.velocity.y = maxf(player.velocity.y, 0.0)
				player.rocket_left = 0.0
				player.stun_left = maxf(player.stun_left, SHOCK_STUN)
		Audio.vibrate(60)
	if kind == Item.SHOCKWAVE:
		# The front carries on up the screen, through the shield or not.
		_waves.append([player.global_position.y, 0.0])
	_pops.append([player.global_position, 0.0])
	if not bots.is_empty():
		_on_attack_outcome(attack["from"], LanRace.my_id(), kind, blocked)
	else:
		LanRace.report_attack(attack["from"], kind, blocked)
	changed.emit()

## An AI threw something, by the player's own rule: the Comet at the front
## of the racers ahead of it, the Reverse and the Shockwave at all of them.
## This phone gets the same warning a LAN attack does; another AI gets the
## same time to wait.
func _on_bot_attack(kind: int, from: RaceBot) -> void:
	if not _running:
		return
	# Everyone ahead of it, best placed first: [score, the AI or null for
	# this phone]. A tie goes to this phone, as it does for the lead.
	var ahead: Array = []
	if player_score > from.score:
		ahead.append([player_score, null])
	for bot in bots:
		if bot != from and _racing(bot) and bot.score > from.score:
			ahead.append([bot.score, bot])
	ahead.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] > b[0]
		return a[1] == null)
	if kind == Item.COMET:
		ahead.resize(mini(ahead.size(), comet_targets(bots.size() + 1)))
	elif kind == Item.SHOCKWAVE:
		_waves.append([from.global_position.y, 0.0])
	for target in ahead:
		if target[1] == null:
			_on_attacked(from.bot_id, kind)
		else:
			_bot_incoming.append({"from": from.bot_id, "to": target[1], "kind": kind,
				"left": ATTACK_WARN_TIME})

## An attack reaching an AI, after the same warning time.
func _land_on_bot(attack: Dictionary) -> void:
	var bot: RaceBot = attack["to"]
	# Over the line, or sitting out a fall: nobody there to hit.
	if not _racing(bot) or bot.is_respawning():
		return
	var blocked := bot.take_attack(attack["kind"])
	_on_attack_outcome(attack["from"], bot.bot_id, attack["kind"], blocked)

## `id`'s line of `tally`, or zeroes.
func tally_of(id: int) -> Array:
	return tally.get(id, [0, 0, 0])

func _on_attack_outcome(from: int, victim: int, kind: int, blocked: bool) -> void:
	if not tally.has(from):
		tally[from] = [0, 0, 0]
	if not tally.has(victim):
		tally[victim] = [0, 0, 0]
	if blocked:
		tally[victim][2] += 1
	else:
		tally[from][0] += 1
		tally[victim][1] += 1
	feed.append({"from": from, "victim": victim, "kind": kind, "blocked": blocked, "age": 0.0})
	if feed.size() > FEED_LINES:
		feed.pop_front()
	var me := LanRace.my_id()
	if from == me:
		if blocked:
			_notify("BLOCKED BY %s'S SHIELD" % racer_name(victim), racer_color(victim))
		else:
			_notify("HIT %s!" % racer_name(victim), UiAccent.color())
	elif victim == me and blocked:
		_notify("SHIELD BLOCKED %s'S %s" % [racer_name(from), NAMES[kind]], SHIELD_COLOR)

## Where box `index` of a gate sits, across the course band.
func box_x(index: int) -> float:
	return _course_left + _course_width * (float(index) + 0.5) / float(BOXES_PER_GATE)

## The lowest gate not yet passed, or INF. For the warning along the top edge.
func next_gate_y() -> float:
	for i in range(_gate_ys.size()):
		if not _spent[i]:
			return _gate_ys[i]
	return INF

func _physics_process(delta: float) -> void:
	for i in range(bots.size()):
		if _racing(bots[i]):
			_check_bot_gates(i)
	# Respawning: physics is off and the character is parked out of sight.
	# What an attack left on it is the player's own to count down (see
	# player.gd), so with the player stopped it is counted down here instead:
	# sitting out a fall does not put a Reverse on hold.
	if not player.is_physics_processing():
		player.stun_left = maxf(player.stun_left - delta, 0.0)
		player.reverse_left = maxf(player.reverse_left - delta, 0.0)
		_prev_y = player.global_position.y
		return
	var y := player.global_position.y
	_check_gates(_prev_y, y)
	if net_left > 0.0:
		net_left = maxf(net_left - delta, 0.0)
		_check_net()
		if net_left == 0.0:
			changed.emit()
	_prev_y = player.global_position.y

## A gate's boxes stay on offer until one of them is taken: a character that
## went through between two boxes can still take one on the way back down, or
## on its next way up. Crossing the row either way counts. (`_spent` only
## says the gate has been reached, for the warning along the top edge.)
func _check_gates(prev_y: float, y: float) -> void:
	var top := minf(prev_y, y)
	var bottom := maxf(prev_y, y)
	for i in range(_gate_ys.size()):
		var gate_y := _gate_ys[i]
		if gate_y < top or gate_y > bottom:
			continue
		_spent[i] = true
		if _taken[i] >= 0:
			continue
		var nearest := -1
		var nearest_dx := INF
		for k in range(BOXES_PER_GATE):
			var dx := absf(player.global_position.x - box_x(k))
			if dx < nearest_dx:
				nearest_dx = dx
				nearest = k
		if nearest_dx > PICKUP_REACH:
			continue
		_taken[i] = nearest
		_taken_at[i] = _time
		_pops.append([Vector2(box_x(nearest), gate_y), 0.0])
		Audio.vibrate(30)
		if held == Item.NONE and rolling_left <= 0.0:
			Audio.play_ui_click()
			rolling_left = ROLL_TIME
			changed.emit()

## An AI's own copy of every gate: spent the first time it rises through, as
## the player's is, and rolled from how far behind the leader it is.
func _check_bot_gates(index: int) -> void:
	var bot := bots[index]
	var y := bot.global_position.y
	while _bot_next_gate[index] < _gate_ys.size() and y <= _gate_ys[_bot_next_gate[index]]:
		_bot_next_gate[index] += 1
		if bot.held == Item.NONE and randf() < BOT_PICKUP_ODDS:
			_roll_for_bot(bot)
	_roll_for_bot(bot, false)

## Rolls `bot` an item from where it stands in the race -- or, with `give`
## off, only tells it how far ahead the best of the others is.
func _roll_for_bot(bot: RaceBot, give: bool = true) -> void:
	# Everyone else still racing: the best of them, and whether any trails it.
	var top := player_score
	var trailed := player_score < bot.score
	var place := 2 if player_score > bot.score else 1
	for other in bots:
		if other == bot:
			continue
		if other.finished or other.score > bot.score:
			place += 1
		if not _racing(other):
			continue
		top = maxi(top, other.score)
		trailed = trailed or other.score < bot.score
	bot.ahead_score = top
	if not give:
		return
	var gap := float(maxi(top - bot.score, 0)) / float(GATE_EVERY)
	# No Safety Net: the bot's falls are its own simulation's business.
	bot.give_item(_roll_from(gap, top > bot.score, trailed, false, place, bots.size() + 1))

func _check_net() -> void:
	var net_y := camera.global_position.y + get_viewport_rect().size.y / 2.0 - NET_INSET
	var feet_y := player.feet.global_position.y
	if player.velocity.y <= 0.0 or feet_y < net_y:
		return
	player.global_position.y -= feet_y - net_y
	player.velocity.y = NET_BOUNCE_VELOCITY
	net_left = 0.0
	_pops.append([Vector2(player.global_position.x, net_y), 0.0])
	Audio.vibrate(40)
	changed.emit()

func _process(delta: float) -> void:
	_time += delta
	if shield_left > 0.0:
		shield_left = maxf(shield_left - delta, 0.0)
		if shield_left == 0.0:
			changed.emit()
	for attack in incoming:
		attack["left"] -= delta
		if attack["kind"] == Item.COMET:
			_steer_comet(attack, delta)
	while not incoming.is_empty() and incoming[0]["left"] <= 0.0:
		_land_attack(incoming.pop_front())
	for attack in _bot_incoming:
		attack["left"] -= delta
	while not _bot_incoming.is_empty() and _bot_incoming[0]["left"] <= 0.0:
		_land_on_bot(_bot_incoming.pop_front())
	for line in feed:
		line["age"] += delta
	feed = feed.filter(func(line): return line["age"] < FEED_TIME)
	if not notice.is_empty():
		notice["age"] += delta
		if notice["age"] >= NOTICE_TIME:
			notice = {}
	if rolling_left > 0.0:
		rolling_left -= delta
		if rolling_left <= 0.0:
			rolling_left = 0.0
			held = _roll()
			Audio.vibrate(20)
			changed.emit()
	for pop in _pops:
		pop[1] += delta
	_pops = _pops.filter(func(pop): return pop[1] < POP_TIME)
	for wave in _waves:
		wave[1] += delta
	_waves = _waves.filter(func(wave): return wave[1] < SHOCK_FADE_TIME)
	queue_redraw()

func _roll() -> Item:
	var leader := player_score
	for rival in rivals:
		if is_instance_valid(rival):
			leader = maxi(leader, rival.score)
	var ahead := _racers_ahead()
	if not ahead.is_empty():
		leader = ahead[0].score
	var gap := float(leader - player_score) / float(GATE_EVERY)
	# Nobody left to throw at -- everyone ahead is over the line. And attacks
	# only ever go forward, so with nobody racing behind -- 2nd of 2, or last
	# of any field -- nothing can reach this phone for a Shield to block.
	var place := 1
	for rival in rivals:
		if is_instance_valid(rival) and (rival.finished or rival.score > player_score):
			place += 1
	return _roll_from(gap, not ahead.is_empty(), _anyone_behind(), true, place, rivals.size() + 1)

## A roll for a racer `gap` gates behind the leader, in `place` of `racers`.
## Whatever its place rules out (see available()), and whatever it cannot use
## -- an attack with nobody ahead, a Shield with nobody behind, the Net for
## the AI -- gives its share to the rest, in their proportions.
func _roll_from(gap: float, can_attack: bool, can_shield: bool, can_net: bool,
		place: int, racers: int) -> Item:
	var weights: Array = ODDS.back().slice(1)
	for i in range(1, ODDS.size()):
		var lo: Array = ODDS[i - 1]
		var hi: Array = ODDS[i]
		if gap <= hi[0]:
			var u := clampf((gap - lo[0]) / (hi[0] - lo[0]), 0.0, 1.0)
			weights = []
			for w in range(1, lo.size()):
				weights.append(lerpf(lo[w], hi[w], u))
			break
	for i in range(ROLLABLE.size()):
		if not available(ROLLABLE[i], place, racers) or (not can_attack and ROLLABLE[i] in ATTACKS):
			weights[i] = 0.0
	if not can_shield:
		weights[ROLLABLE.find(Item.SHIELD)] = 0.0
	if not can_net:
		weights[ROLLABLE.find(Item.NET)] = 0.0
	var total := 0.0
	for w in weights:
		total += w
	var r := randf() * total
	var last := 0
	for i in range(weights.size()):
		if weights[i] <= 0.0:
			continue
		last = i
		r -= weights[i]
		if r <= 0.0:
			return ROLLABLE[i]
	return ROLLABLE[last]

## A rival still racing who could throw something at this phone.
func _anyone_behind() -> bool:
	for rival in rivals:
		if _racing(rival) and rival.score < player_score:
			return true
	return false

# --- Drawing --------------------------------------------------------------

func _draw() -> void:
	if camera == null:
		return
	var half_h := get_viewport_rect().size.y / 2.0
	var top := camera.global_position.y - half_h - BOX_SIZE
	var bottom := camera.global_position.y + half_h + BOX_SIZE
	for i in range(_gate_ys.size()):
		var gate_y := _gate_ys[i]
		if gate_y < top or gate_y > bottom:
			continue
		var fade := 1.0
		if _taken[i] >= 0:
			fade = 1.0 - (_time - _taken_at[i]) / ROW_FADE_TIME
			if fade <= 0.0:
				continue
			fade = fade * fade * (3.0 - 2.0 * fade)
		_draw_gate_line(gate_y, fade)
		for k in range(BOXES_PER_GATE):
			if _taken[i] != k:
				_draw_box(Vector2(box_x(k), gate_y), k, fade)
	for pop in _pops:
		_draw_pop(pop[0], pop[1] / POP_TIME)
	for wave in _waves:
		_draw_shock_front(wave[0] - SHOCK_SPEED * wave[1], 1.0 - wave[1] / SHOCK_FADE_TIME)
	if not _running:
		return
	if player.rocket_left > 0.0:
		_draw_flame()
	if player.auto_boosts > 0:
		_draw_coil()
	if net_left > 0.0:
		_draw_net(camera.global_position.y + half_h - NET_INSET)
	var body := player.feet.global_position + Vector2(0.0, -18.0)
	draw_status(self, body, shield_left > 0.0, player.stun_left > 0.0,
		player.reverse_left > 0.0, _time, shield_left)
	for attack in incoming:
		var u: float = 1.0 - attack["left"] / ATTACK_WARN_TIME
		if attack["kind"] == Item.COMET:
			# Coming down on its own line, which is chasing the character's
			# -- and pulled the rest of the way in as it lands, so whatever
			# the chase left it short by, it is seen to hit.
			var x: float = attack.get("x", body.x)
			x += _wrapped_dx(x, body.x) * u * u * u
			_draw_falling_comet(Vector2(x, body.y), attack.get("vx", 0.0), u, half_h)
		elif attack["kind"] == Item.SHOCKWAVE:
			# Up from the bottom edge to the player over the warning: on screen
			# from the first frame, and plainly on its way.
			_draw_shock_front(lerpf(camera.global_position.y + half_h - 12.0, body.y, u), 1.0)

## A Shockwave's front at `y`: a bright crackling line the width of the
## course, with the glow it leaves trailing under it.
func _draw_shock_front(y: float, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var left := _course_left
	var right := _course_left + _course_width
	var glow := Color(SHOCK_COLOR.r, SHOCK_COLOR.g, SHOCK_COLOR.b, 0.4 * alpha)
	var clear := Color(SHOCK_COLOR.r, SHOCK_COLOR.g, SHOCK_COLOR.b, 0.0)
	draw_polygon(PackedVector2Array([
		Vector2(left, y), Vector2(right, y), Vector2(right, y + 170.0), Vector2(left, y + 170.0),
	]), PackedColorArray([glow, glow, clear, clear]))
	var front := Color(SHOCK_COLOR.r, SHOCK_COLOR.g, SHOCK_COLOR.b, alpha)
	draw_line(Vector2(left, y), Vector2(right, y), front, 8.0)
	var crackle := PackedVector2Array()
	var steps := 24
	for i in range(steps + 1):
		var jitter := sin(_time * 55.0 + float(i) * 2.4) * 9.0
		crackle.append(Vector2(lerpf(left, right, float(i) / float(steps)), y - 12.0 + jitter))
	draw_polyline(crackle, Color(2.6, 2.6, 2.2, alpha), 3.0)

## Sideways distance across the course band, the short way round its wrap.
func _wrapped_dx(from_x: float, to_x: float) -> float:
	var d := to_x - from_x
	if d > _course_width * 0.5:
		d -= _course_width
	elif d < -_course_width * 0.5:
		d += _course_width
	return d

## A Comet on its way in: down from above the screen to the player's height
## over the warning, on its own line across (`target.x`, see _steer_comet),
## so the warning is something seen coming as well as read. `vx` is how fast
## it is sliding sideways, which is the way its tail leans.
func _draw_falling_comet(target: Vector2, vx: float, u: float, half_h: float) -> void:
	var from_y := camera.global_position.y - half_h - 60.0
	var head := Vector2(target.x, lerpf(from_y, target.y, u * u))
	# Its fall speed at this point of the drop, for the tail to trail along.
	var vy := (target.y - from_y) * 2.0 * u / ATTACK_WARN_TIME
	var back := -Vector2(vx, maxf(vy, 200.0)).normalized()
	draw_colored_polygon(PackedVector2Array([
		head + back.orthogonal() * 12.0, head - back.orthogonal() * 12.0, head + back * 150.0,
	]), Color(COMET_COLOR.r, COMET_COLOR.g, COMET_COLOR.b, 0.5))
	draw_circle(head, 14.0, COMET_COLOR)
	draw_circle(head, 7.0, Color(2.6, 2.4, 1.6, 1.0))

## The item states drawn around a racer's body: this phone's own (from here)
## and a ghost's (from its flags, see NetRival._draw). `shield_left` blinks a
## shield that is about to drop; a ghost's is not known, so it never blinks.
static func draw_status(ci: CanvasItem, body: Vector2, shielded: bool, stunned: bool,
		reversed: bool, t: float, shield_left: float = INF) -> void:
	if shielded:
		var c := SHIELD_COLOR
		c.a = 0.85 if shield_left > 2.0 else 0.35 + 0.5 * (0.5 + 0.5 * cos(t * 14.0))
		ci.draw_arc(body, 34.0, 0.0, TAU, 40, c, 3.0)
		ci.draw_circle(body, 32.0, Color(c.r, c.g, c.b, 0.12))
	if stunned:
		for i in range(3):
			var a := t * 5.0 + TAU * float(i) / 3.0
			var p := body + Vector2(cos(a) * 24.0, -30.0 + sin(a) * 6.0)
			_draw_star(ci, p, 6.0, Color(2.4, 2.2, 0.6, 1.0))
	if reversed:
		for i in range(2):
			var a := -t * 4.0 + PI * float(i)
			ci.draw_arc(body, 28.0, a, a + 1.6, 12, REVERSE_COLOR, 3.0)
			var tip := body + Vector2.from_angle(a) * 28.0
			ci.draw_circle(tip, 4.0, REVERSE_COLOR)

static func _draw_star(ci: CanvasItem, center: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var rr := r if i % 2 == 0 else r * 0.45
		points.append(center + Vector2.from_angle(-PI / 2.0 + TAU * float(i) / 10.0) * rr)
	ci.draw_colored_polygon(points, color)

func _draw_gate_line(y: float, fade: float) -> void:
	var c := GATE_LINE_COLOR
	c.a *= fade
	var x := _course_left
	while x < _course_left + _course_width:
		draw_line(Vector2(x, y), Vector2(minf(x + 18.0, _course_left + _course_width), y),
			c, 2.0)
		x += 30.0

static func box_color(t: float, index: int) -> Color:
	return Color.from_hsv(fposmod(t * 0.25 + float(index) * 0.25, 1.0), 0.65, 1.0)

## `fade` 1 is a box on offer; down to 0 it shrinks and fades with its row.
func _draw_box(center: Vector2, index: int, fade: float = 1.0) -> void:
	center.y += sin(_time * 3.0 + float(index)) * BOX_BOB
	var c := box_color(_time, index)
	var shrink := lerpf(0.4, 1.0, fade)
	var half := BOX_SIZE / 2.0
	draw_set_transform(center, sin(_time * 1.6 + float(index)) * 0.35, Vector2.ONE * shrink)
	var rect := Rect2(-half, -half, BOX_SIZE, BOX_SIZE)
	draw_rect(rect, Color(c.r, c.g, c.b, 0.28 * fade))
	var outline := c * 2.0
	outline.a = fade
	draw_rect(rect, outline, false, 4.0)
	draw_set_transform(Vector2.ZERO)
	var glyph_size := maxi(int(34.0 * shrink), 1)
	var glyph := FONT.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1.0, glyph_size)
	draw_string(FONT, center + Vector2(-glyph.x / 2.0, glyph.y * 0.32), "?",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, glyph_size, Color(2.2, 2.2, 2.2, fade))

func _draw_pop(center: Vector2, u: float) -> void:
	var c := Color(2.0, 2.0, 2.0, 1.0 - u)
	draw_arc(center, lerpf(BOX_SIZE * 0.5, BOX_SIZE * 1.7, u), 0.0, TAU, 32, c, 4.0 * (1.0 - u) + 1.0)
	for s in range(8):
		var dir := Vector2.from_angle(TAU * float(s) / 8.0 + 0.3)
		var a := center + dir * lerpf(BOX_SIZE * 0.4, BOX_SIZE * 1.4, u)
		draw_line(a, a + dir * 10.0 * (1.0 - u), c, 3.0)

func _draw_flame() -> void:
	var feet := player.feet.global_position
	var flicker := sin(_time * 40.0) * 0.5 + 0.5
	var length := 56.0 + flicker * 22.0
	draw_colored_polygon(PackedVector2Array([
		feet + Vector2(-13.0, -4.0), feet + Vector2(13.0, -4.0), feet + Vector2(0.0, length),
	]), Color(2.4, 0.9, 0.2, 0.85))
	draw_colored_polygon(PackedVector2Array([
		feet + Vector2(-6.0, -4.0), feet + Vector2(6.0, -4.0), feet + Vector2(0.0, length * 0.55),
	]), Color(2.6, 2.2, 0.8, 0.95))

func _draw_coil() -> void:
	var feet := player.feet.global_position
	var points := PackedVector2Array()
	for i in range(7):
		points.append(feet + Vector2(-9.0 if i % 2 == 0 else 9.0, 2.0 + i * 2.5))
	draw_polyline(points, Color(2.0, 2.0, 0.6, 0.9), 2.5)

func _draw_net(y: float) -> void:
	var c := NET_COLOR
	# Blinks through its last seconds, so running out is never a surprise.
	if net_left < NET_WARN_TIME:
		c.a = 0.35 + 0.65 * (0.5 + 0.5 * cos(_time * 14.0))
	var left := _course_left + 10.0
	var right := _course_left + _course_width - 10.0
	var points := PackedVector2Array()
	var steps := 24
	for i in range(steps + 1):
		var x := lerpf(left, right, float(i) / float(steps))
		points.append(Vector2(x, y + (5.0 if i % 2 == 0 else -5.0)))
	draw_polyline(points, c, 3.0)
	draw_line(Vector2(left, y - 14.0), Vector2(left, y + 14.0), c, 4.0)
	draw_line(Vector2(right, y - 14.0), Vector2(right, y + 14.0), c, 4.0)

## The item's picture, shared by the button. Lines only, in `color`, within a
## circle of radius `r` around `center`.
static func draw_icon(ci: CanvasItem, item: Item, center: Vector2, r: float, color: Color) -> void:
	match item:
		Item.ROCKET:
			var body := PackedVector2Array([
				center + Vector2(0.0, -r), center + Vector2(r * 0.38, -r * 0.35),
				center + Vector2(r * 0.38, r * 0.45), center + Vector2(-r * 0.38, r * 0.45),
				center + Vector2(-r * 0.38, -r * 0.35), center + Vector2(0.0, -r),
			])
			ci.draw_polyline(body, color, r * 0.12)
			ci.draw_line(center + Vector2(-r * 0.38, r * 0.15), center + Vector2(-r * 0.7, r * 0.55), color, r * 0.12)
			ci.draw_line(center + Vector2(r * 0.38, r * 0.15), center + Vector2(r * 0.7, r * 0.55), color, r * 0.12)
			ci.draw_colored_polygon(PackedVector2Array([
				center + Vector2(-r * 0.22, r * 0.58), center + Vector2(r * 0.22, r * 0.58),
				center + Vector2(0.0, r),
			]), Color(2.4, 0.9, 0.2, color.a))
		Item.NET:
			var points := PackedVector2Array()
			for i in range(9):
				var x := lerpf(-r * 0.85, r * 0.85, float(i) / 8.0)
				points.append(center + Vector2(x, r * 0.1 + (r * 0.14 if i % 2 == 0 else -r * 0.14)))
			ci.draw_polyline(points, color, r * 0.11)
			ci.draw_line(center + Vector2(-r * 0.85, -r * 0.1), center + Vector2(-r * 0.85, r * 0.7), color, r * 0.12)
			ci.draw_line(center + Vector2(r * 0.85, -r * 0.1), center + Vector2(r * 0.85, r * 0.7), color, r * 0.12)
			ci.draw_polyline(PackedVector2Array([
				center + Vector2(-r * 0.3, -r * 0.45), center + Vector2(0.0, -r * 0.8),
				center + Vector2(r * 0.3, -r * 0.45),
			]), color, r * 0.12)
		Item.SPRING:
			var points := PackedVector2Array()
			for i in range(7):
				points.append(center + Vector2(-r * 0.4 if i % 2 == 0 else r * 0.4,
					lerpf(r * 0.75, -r * 0.35, float(i) / 6.0)))
			ci.draw_polyline(points, color, r * 0.12)
			ci.draw_line(center + Vector2(-r * 0.65, -r * 0.55), center + Vector2(r * 0.65, -r * 0.55), color, r * 0.16)
		Item.SHIELD:
			ci.draw_polyline(PackedVector2Array([
				center + Vector2(0.0, -r * 0.85), center + Vector2(r * 0.7, -r * 0.55),
				center + Vector2(r * 0.6, r * 0.2), center + Vector2(0.0, r * 0.85),
				center + Vector2(-r * 0.6, r * 0.2), center + Vector2(-r * 0.7, -r * 0.55),
				center + Vector2(0.0, -r * 0.85),
			]), color, r * 0.12)
		Item.COMET:
			ci.draw_circle(center + Vector2(-r * 0.3, r * 0.3), r * 0.36, COMET_COLOR)
			for i in range(3):
				var off := Vector2(r * 0.22, -r * 0.22) * float(i - 1)
				ci.draw_line(center + Vector2(-r * 0.05, r * 0.05) + off,
					center + Vector2(r * 0.8, -r * 0.8) + off * 0.6, color, r * 0.1)
		Item.SHOCKWAVE:
			# Three fronts on their way up, the lead one widest.
			for i in range(3):
				var half := r * (0.85 - 0.22 * float(i))
				var base := r * (-0.15 + 0.45 * float(i))
				ci.draw_polyline(PackedVector2Array([
					center + Vector2(-half, base), center + Vector2(0.0, base - r * 0.4),
					center + Vector2(half, base)]), color, r * 0.13)
		Item.REVERSE:
			var y := r * 0.35
			ci.draw_line(center + Vector2(-r * 0.8, -y), center + Vector2(r * 0.8, -y), color, r * 0.12)
			ci.draw_polyline(PackedVector2Array([
				center + Vector2(r * 0.45, -y - r * 0.3), center + Vector2(r * 0.8, -y),
				center + Vector2(r * 0.45, -y + r * 0.3)]), color, r * 0.12)
			ci.draw_line(center + Vector2(-r * 0.8, y), center + Vector2(r * 0.8, y), color, r * 0.12)
			ci.draw_polyline(PackedVector2Array([
				center + Vector2(-r * 0.45, y - r * 0.3), center + Vector2(-r * 0.8, y),
				center + Vector2(-r * 0.45, y + r * 0.3)]), color, r * 0.12)
