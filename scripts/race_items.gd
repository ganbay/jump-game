extends Node2D
class_name RaceItems

## Item boxes in a race (see docs/lan-items.md). Owned by game.gd, only when
## ITEM BOXES is on: the host's switch in a LAN race, Race.items_on against
## the AI.
##
## Against the AI (`bot` set) nothing goes over a network: the bot takes its
## own boxes and uses its own items (see race_bot.gd), and an attack either
## way is handed across right here, under BOT_ID.
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
enum Item { NONE, ROCKET, NET, SPRING, SHIELD, COMET, REVERSE }

const NAMES := {
	Item.ROCKET: "ROCKET",
	Item.NET: "SAFETY NET",
	Item.SPRING: "SPRING SHOES",
	Item.SHIELD: "SHIELD",
	Item.COMET: "COMET",
	Item.REVERSE: "REVERSE",
}
## What the box roulette cycles through, and what a roll can land on -- in
## the column order of ODDS.
const ROLLABLE := [Item.ROCKET, Item.NET, Item.SPRING, Item.SHIELD, Item.COMET, Item.REVERSE]
const ATTACKS := [Item.COMET, Item.REVERSE]
## The AI's id in the feed and the warnings, where a LAN racer's is its peer
## id. Peer ids are positive.
const BOT_ID := -1
## The bot's own copy of a gate gives it an item this often: its lane through
## the gate is not simulated, and about nine lanes in ten collect.
const BOT_PICKUP_ODDS := 0.9

## The AI's colour, for the static name/colour lookups below.
static var bot_color: Color = Color.WHITE

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
const REVERSE_TIME := 4.0
const SHIELD_COLOR := Color(0.7, 1.6, 2.4, 1.0)
const COMET_COLOR := Color(2.6, 1.2, 0.3, 1.0)
const REVERSE_COLOR := Color(2.2, 0.6, 2.2, 1.0)
## How long a line stays in the feed, and the most lines it shows at once.
const FEED_TIME := 3.0
const FEED_LINES := 3
const NOTICE_TIME := 1.6

## The odds, by how far behind the leader this phone is, in gates
## (GATE_EVERY of score). Rows are [gap, rocket, net, spring, shield, comet,
## reverse], interpolated between: the further back, the more it leans to
## the Rocket and the attacks. The leader (gap 0) gets only defence.
const ODDS := [
	[0.0, 0.0, 0.4, 0.2, 0.4, 0.0, 0.0],
	[0.5, 0.15, 0.15, 0.25, 0.1, 0.15, 0.2],
	[1.5, 0.3, 0.05, 0.15, 0.0, 0.25, 0.25],
	[3.0, 0.45, 0.0, 0.05, 0.0, 0.3, 0.2],
]

var player: Player
var camera: Camera2D
var rivals: Array[Rival] = []
## The AI in a bot race, or null in a LAN one.
var bot: RaceBot
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
var _prev_y: float = 0.0
var _time: float = 0.0
## The bot's own pass through the gates, and this phone's attacks on their
## way to it: {kind, left}.
var _bot_prev_y: float = 0.0
var _bot_spent: Array[bool] = []
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
	_bot_spent = []
	_bot_spent.resize(_gate_ys.size())
	_bot_spent.fill(false)
	_bot_incoming.clear()
	if bot != null:
		bot_color = bot.color
		_bot_prev_y = bot.global_position.y
		if not bot.attack_requested.is_connected(_on_bot_attack):
			bot.attack_requested.connect(_on_bot_attack)
	_prev_y = player.global_position.y
	_running = true
	set_physics_process(true)

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
			shield_left = SHIELD_TIME
		Item.COMET, Item.REVERSE:
			var ahead := _racers_ahead()
			if ahead.is_empty():
				# Passed them since the roll: kept for when someone is ahead again.
				_notify("NOBODY AHEAD", Color(1.0, 1.0, 1.0, 0.8))
				return false
			# The Comet goes for the leader, the Reverse for everyone ahead.
			if bot != null:
				_bot_incoming.append({"kind": held, "left": ATTACK_WARN_TIME})
			else:
				var targets: Array = [_id_of(ahead[0])] if held == Item.COMET \
					else ahead.map(_id_of)
				LanRace.send_attack(held, targets)
	Analytics.log_event("race_item_used" if bot != null else "lan_item_used",
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

## Still on the course: a LAN racer who has not finished, or the AI.
func _racing(rival: Rival) -> bool:
	if not is_instance_valid(rival):
		return false
	return not rival.finished if rival is NetRival else rival is RaceBot

func _id_of(rival: Rival) -> int:
	return rival.peer_id if rival is NetRival else BOT_ID

## LanRace.peers' name for `id`, YOU for this phone, or AI.
static func racer_name(id: int) -> String:
	if id == BOT_ID:
		return "AI"
	if id == LanRace.my_id():
		return "YOU"
	return str(LanRace.peers.get(id, {}).get("name", "?"))

static func racer_color(id: int) -> Color:
	if id == BOT_ID:
		return bot_color
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

## Lands an attack: blocked by a raised Shield (which it uses up), or taken.
## Either way the room hears how it went.
func _land_attack(attack: Dictionary) -> void:
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
		Audio.vibrate(60)
	_pops.append([player.global_position, 0.0])
	if bot != null:
		_on_attack_outcome(attack["from"], LanRace.my_id(), kind, blocked)
	else:
		LanRace.report_attack(attack["from"], kind, blocked)
	changed.emit()

## The AI threw something at this phone: the same warning a LAN attack gets.
func _on_bot_attack(kind: int) -> void:
	_on_attacked(BOT_ID, kind)

## This phone's attack reaching the AI, after the same warning time.
func _land_on_bot(kind: int) -> void:
	if bot == null or not is_instance_valid(bot):
		return
	var blocked := bot.take_attack(kind)
	_on_attack_outcome(LanRace.my_id(), BOT_ID, kind, blocked)

func _on_attack_outcome(from: int, victim: int, kind: int, blocked: bool) -> void:
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
	if bot != null and is_instance_valid(bot):
		_check_bot_gates()
	# Respawning: physics is off and the character is parked out of sight.
	if not player.is_physics_processing():
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

## A gate is spent the first time the character rises through it, box or no
## box -- falling back and rising again does not get a second go.
func _check_gates(prev_y: float, y: float) -> void:
	for i in range(_gate_ys.size()):
		var gate_y := _gate_ys[i]
		if gate_y > prev_y:
			continue
		if gate_y < y:
			break
		if _spent[i]:
			continue
		_spent[i] = true
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

## The AI's own copy of every gate: spent the first time it rises through,
## as the player's is, and rolled from how far behind the player it is.
func _check_bot_gates() -> void:
	bot.player_score = player_score
	var y := bot.global_position.y
	for i in range(_gate_ys.size()):
		var gate_y := _gate_ys[i]
		if gate_y > _bot_prev_y:
			continue
		if gate_y < y:
			break
		if _bot_spent[i]:
			continue
		_bot_spent[i] = true
		if bot.held == Item.NONE and randf() < BOT_PICKUP_ODDS:
			var gap := float(maxi(player_score - bot.score, 0)) / float(GATE_EVERY)
			# No Safety Net: the bot's falls are its own simulation's business.
			bot.give_item(_roll_from(gap, player_score > bot.score,
				player_score < bot.score, false))
	_bot_prev_y = y

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
	while not incoming.is_empty() and incoming[0]["left"] <= 0.0:
		_land_attack(incoming.pop_front())
	for attack in _bot_incoming:
		attack["left"] -= delta
	while not _bot_incoming.is_empty() and _bot_incoming[0]["left"] <= 0.0:
		_land_on_bot(_bot_incoming.pop_front()["kind"])
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
	return _roll_from(gap, not ahead.is_empty(), _anyone_behind(), true)

## A roll for a racer `gap` gates behind the leader. Whatever it cannot use
## -- an attack with nobody ahead, a Shield with nobody behind, the Net for
## the AI -- gives its share to the rest, in their proportions.
func _roll_from(gap: float, can_attack: bool, can_shield: bool, can_net: bool) -> Item:
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
	if not can_attack:
		for i in range(ROLLABLE.size()):
			if ROLLABLE[i] in ATTACKS:
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
		if attack["kind"] == Item.COMET:
			_draw_falling_comet(body, 1.0 - attack["left"] / ATTACK_WARN_TIME, half_h)

## A Comet on its way in: down from above the screen onto the player over the
## warning, so the warning is something seen coming as well as read.
func _draw_falling_comet(target: Vector2, u: float, half_h: float) -> void:
	var from := Vector2(target.x + 160.0, camera.global_position.y - half_h - 60.0)
	var head := from.lerp(target, u * u)
	var back := (from - target).normalized()
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
