extends Node

## LAN races: up to eight phones on one Wi-Fi network (or on one phone's
## hotspot) climbing the same seeded course at the same moment. Each phone
## simulates only its own player and sends where it is; the others draw it as
## a ghost (see net_rival.gd). Racers never touch, so there is no netcode
## beyond positions -- lag only ever moves a ghost a few pixels. Full design
## and the reasoning behind it: docs/lan-race.md.
##
## An autoload, so the session survives the scene changes between the lobby
## (lan_lobby.tscn) and the race (main.tscn). One phone hosts: an ENet server
## that is also a racer, and the one that decides everything shared -- who is
## in, the distance, the seed, the start time and the finishing order. The
## others send it only what they alone know: ready, where they are, and when
## they finished.
##
## Always processing: Transition and the game-over panel pause the tree, and
## the session has to keep talking through both.

signal peers_changed
signal rooms_changed
## The session is over -- left, kicked, or the host went away. `reason` is
## empty when the player left on their own.
signal session_ended(reason: String)
## The host called the race off before it finished (see _check_hashes).
signal race_aborted(reason: String)
signal rival_state(id: int, t: float, pos: Vector2, score: int, flags: int)
## Someone finished: the rest have until closing_at_ms.
signal closing_started
signal results_ready
## This phone dropped out of the race in progress (backgrounded, or quit).
signal forfeited
## A race item (RaceItems.Item) thrown at this phone by `from`.
signal attacked(from: int, kind: int)
## How an attack went, for everyone: `victim` blocked it or took it.
signal attack_outcome(from: int, victim: int, kind: int, blocked: bool)

enum Role { NONE, HOST, CLIENT }
enum Phase { LOBBY, RACING }

const PORT := 47820
const DISCOVERY_PORT := 47821
## Eight: comfortably inside what a phone hotspot accepts (many allow 8-10
## devices), and as many ghosts as the HUD can tag clearly. The network is
## nowhere near a limit -- the host relays about 15 x n^2 small packets a
## second, ~80 KB/s at eight.
const MAX_PLAYERS := 8
## Bumped on any change to the messages below. Checked in the handshake along
## with the course version and the app version.
const PROTOCOL := 7
const STATE_INTERVAL := 1.0 / 15.0
## From the host pressing START to GO: the start message, the scene change and
## the whole intro (IntroSequence.total_time, with the 3-2-1 over its end) all
## fit inside it. Also the music's cue: the song starts this long before GO.
const START_LEAD_MS := 6000
## How long the field has to finish once the first racer is home.
const FINISH_GRACE_MS := 30000
## A typed address that never answers. ENet's own give-up is far slower.
const CONNECT_TIMEOUT := 6.0
const PING_INTERVAL_LOBBY := 0.5
const PING_INTERVAL_RACE := 2.0
const PING_SAMPLES := 8
## ENet's peer timeout, as (limit, min ms, max ms): a phone that stops
## answering -- backgrounded, out of range -- is dropped within ~10 s.
const PEER_TIMEOUT := [32, 4000, 10000]
## How long a rejected joiner gets to read why before the host hangs up.
const REJECT_GRACE := 2.0
const ANNOUNCE_INTERVAL := 1.0
const ROOM_TTL_MS := 3500
## How much of the course the start-of-race check compares (see
## PlatformSpawner.course_hash). A few hundred slots is a long way up.
const COURSE_CHECK_SLOTS := 200
const FLAG_RESPAWNING := 1
const FLAG_FINISHED := 2
## Race item states (see race_items.gd), so the others can see them on the ghost.
const FLAG_SHIELDED := 4
const FLAG_STUNNED := 8
const FLAG_REVERSED := 16
## A result's time when the racer did not finish.
const DNF := -1.0

const SpawnerScript := preload("res://scripts/platform_spawner.gd")

var role: Role = Role.NONE
var phase: Phase = Phase.LOBBY
## Everyone in the room, this phone included, by peer id:
##   slot   1-8, the host is 1    ready  bool
##   name   theirs (Settings.player_name), or "P<slot>" if they set none
##   color, shape, trail          their character, as their own run dresses it
var peers: Dictionary = {}
var target_index: int = 0
## Item boxes in the race (see race_items.gd). The host's switch.
var items_on: bool = true
## Local clock (Time.get_ticks_msec) of GO.
var start_at_ms: int = 0
## Which of Audio.MUSIC_SETS the race plays. The host's pick, so every phone
## plays the same song.
var music_set: int = 0
## Local clock the race closes at, or 0 while nobody has finished.
var closing_at_ms: int = 0
## The last race's finishing order: [{id, name, color, time}], DNF last.
var results: Array = []
## Rooms heard on the network while browsing, by host address:
##   name, players, max, open, seen (local ms)
var rooms: Dictionary = {}
## Why the last session ended or the last attempt failed, for the lobby.
var last_error: String = ""

var _peer: ENetMultiplayerPeer
## Host clock minus local clock, in ms. 0 on the host.
var _clock_offset: int = 0
## [rtt, offset] pairs; the lowest round trip is the most trustworthy.
var _pings: Array = []
var _ping_wait: float = 0.0
var _connect_wait: float = 0.0
var _state_wait: float = 0.0
var _finished_local: bool = false
var _announcer: PacketPeerUDP
var _announce_wait: float = 0.0
var _listener: PacketPeerUDP

# Host only.
## Everyone who started the race in progress, as their peers entry then, so
## a racer who has since left still has a name on the results.
var _racers: Dictionary = {}
var _finish_times: Dictionary = {}
var _hashes: Dictionary = {}
var _kick_after: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# --- Queries --------------------------------------------------------------

func is_active() -> bool:
	return role != Role.NONE

func is_host() -> bool:
	return role == Role.HOST

## Joined but not yet let in by the host.
func is_connecting() -> bool:
	return role == Role.CLIENT and peers.is_empty()

## A race is starting or under way. What game.gd branches on.
func in_race() -> bool:
	return role != Role.NONE and phase == Phase.RACING

func my_id() -> int:
	return multiplayer.get_unique_id()

## Seconds since GO, on the clock every racer shares. Negative during the
## countdown. Finish times and ghost playback are both on this clock, so they
## compare across phones.
func race_clock() -> float:
	return float(Time.get_ticks_msec() - start_at_ms) / 1000.0

## Seconds left before the race closes, or -1 while nobody has finished.
func closing_left() -> float:
	if closing_at_ms == 0:
		return -1.0
	return maxf(float(closing_at_ms - Time.get_ticks_msec()) / 1000.0, 0.0)

func can_start() -> bool:
	if role != Role.HOST or phase != Phase.LOBBY or peers.size() < 2:
		return false
	for id in peers:
		if id != 1 and not peers[id]["ready"]:
			return false
	return true

## This phone's private IPv4 addresses -- what a friend types to join. Usually
## one; a phone sharing a hotspot while also on Wi-Fi can have two.
func local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for address in IP.get_local_addresses():
		if _is_private_ipv4(address) and not out.has(address):
			out.append(address)
	return out

# --- Session --------------------------------------------------------------

func host() -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS - 1) != OK:
		last_error = "COULDN'T OPEN A ROOM ON THIS PHONE"
		return false
	_peer = peer
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	phase = Phase.LOBBY
	last_error = ""
	_clock_offset = 0
	peers = {1: _my_info(1)}
	peers[1]["ready"] = true
	stop_browsing()
	_announcer = PacketPeerUDP.new()
	_announcer.set_broadcast_enabled(true)
	_announce_wait = 0.0
	peers_changed.emit()
	return true

func join(address: String) -> bool:
	leave()
	address = address.strip_edges()
	if not address.is_valid_ip_address():
		last_error = "THAT'S NOT AN IP ADDRESS"
		return false
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, PORT) != OK:
		last_error = "COULDN'T REACH %s" % address
		return false
	_peer = peer
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	phase = Phase.LOBBY
	last_error = ""
	_pings.clear()
	_clock_offset = 0
	_connect_wait = CONNECT_TIMEOUT
	stop_browsing()
	peers_changed.emit()
	return true

## Ends the session from this side. Also the cleanup for every other way a
## session ends, with `reason` saying which (empty: the player chose to).
func leave(reason: String = "") -> void:
	var was_active := role != Role.NONE
	# Before closing: close() can fire the disconnect signals, which land
	# back here and must find nothing left to do.
	role = Role.NONE
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	phase = Phase.LOBBY
	peers = {}
	results = []
	closing_at_ms = 0
	_finished_local = false
	_racers.clear()
	_finish_times.clear()
	_hashes.clear()
	_kick_after.clear()
	_announcer = null
	if was_active:
		Race.active = false
		Race.course_seed = -1
		Race.shared_target = 0
		last_error = reason
		session_ended.emit(reason)

# --- Lobby ----------------------------------------------------------------

func set_ready(ready: bool) -> void:
	if role == Role.CLIENT and not peers.is_empty():
		_set_ready.rpc_id(1, ready)

func set_target(index: int) -> void:
	if role != Role.HOST or phase != Phase.LOBBY:
		return
	target_index = clampi(index, 0, Race.TARGETS.size() - 1)
	_send_lobby()

func set_items(on: bool) -> void:
	if role != Role.HOST or phase != Phase.LOBBY:
		return
	items_on = on
	_send_lobby()

## Re-sends this phone's name and character. The lobby calls it when the name
## is edited, and game.gd once the run has rolled its skin, which on shuffle
## differs from what the lobby saw.
func send_profile() -> void:
	if role == Role.NONE or peers.is_empty():
		return
	if role == Role.HOST:
		_set_profile(Settings.player_name, Settings.player_color, _my_shape(),
			Settings.trail_enabled)
	else:
		_set_profile.rpc_id(1, Settings.player_name, Settings.player_color, _my_shape(),
			Settings.trail_enabled)

func start_race() -> void:
	if not can_start():
		return
	var course_seed := randi() % 0x7fffffff
	var at := Time.get_ticks_msec() + START_LEAD_MS
	var song := Audio.pick_music_set()
	_racers = peers.duplicate(true)
	_finish_times.clear()
	_hashes.clear()
	for id in peers:
		if id != 1:
			_start.rpc_id(id, course_seed, target_index, at, song, items_on)
	_start(course_seed, target_index, at, song, items_on)

# --- Racing ---------------------------------------------------------------

## Called every frame of the race by game.gd. Sent at STATE_INTERVAL, or at
## once when `now` (a finish or a fall should show straight away).
func send_state(pos: Vector2, score: int, flags: int, delta: float, now: bool = false) -> void:
	if not in_race():
		return
	_state_wait -= delta
	if _state_wait > 0.0 and not now:
		return
	_state_wait = STATE_INTERVAL
	_state.rpc(race_clock(), pos, score, flags)

func report_finish(time: float) -> void:
	if not in_race() or _finished_local:
		return
	_finished_local = true
	if role == Role.HOST:
		_record_finish(1, time)
	else:
		_finished.rpc_id(1, time)

## Drops out of the race in progress: a DNF, and the others race on.
func forfeit() -> void:
	if not in_race() or _finished_local:
		return
	report_finish(DNF)
	forfeited.emit()

func report_course_hash(hash: int) -> void:
	if not in_race():
		return
	if role == Role.HOST:
		_store_hash(1, hash)
	else:
		_course_hash.rpc_id(1, hash)

# --- Race items (docs/lan-items.md) --------------------------------------
#
# The attacker names its targets from the scores it has; the host checks the
# race is on and each target still racing, and passes it on. The target's own
# phone decides the outcome -- shield or hit -- and applies it to its own
# player, then reports back so everyone can see who got whom.

func send_attack(kind: int, targets: Array) -> void:
	if not in_race():
		return
	if role == Role.HOST:
		_relay_attack(1, kind, targets)
	else:
		_attack_request.rpc_id(1, kind, targets)

func report_attack(from: int, kind: int, blocked: bool) -> void:
	if not in_race():
		return
	if role == Role.HOST:
		_send_outcome(from, 1, kind, blocked)
	else:
		_attack_report.rpc_id(1, from, kind, blocked)

# --- Discovery ------------------------------------------------------------

## Listens for rooms announcing themselves (see _announce). False when the
## port is taken -- a second copy of the game on the same computer.
func start_browsing() -> bool:
	if _listener != null:
		return true
	var listener := PacketPeerUDP.new()
	if listener.bind(DISCOVERY_PORT) != OK:
		return false
	_listener = listener
	_set_multicast_lock(true)
	return true

func stop_browsing() -> void:
	if _listener == null:
		return
	_listener.close()
	_listener = null
	_set_multicast_lock(false)
	if not rooms.is_empty():
		rooms.clear()
		rooms_changed.emit()

func is_browsing() -> bool:
	return _listener != null

# --- Frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	_poll_rooms()
	match role:
		Role.HOST:
			_process_host(delta)
		Role.CLIENT:
			_process_client(delta)

func _process_host(delta: float) -> void:
	if phase == Phase.LOBBY:
		_announce_wait -= delta
		if _announce_wait <= 0.0:
			_announce_wait = ANNOUNCE_INTERVAL
			_announce()
	elif closing_at_ms != 0 and Time.get_ticks_msec() >= closing_at_ms:
		_conclude()
	for id in _kick_after.keys():
		_kick_after[id] -= delta
		if _kick_after[id] <= 0.0:
			_kick_after.erase(id)
			if _peer != null:
				_peer.disconnect_peer(id)

func _process_client(delta: float) -> void:
	if peers.is_empty():
		_connect_wait -= delta
		if _connect_wait <= 0.0:
			leave("NO ROOM AT THAT ADDRESS")
		return
	_ping_wait -= delta
	if _ping_wait <= 0.0:
		_ping_wait = PING_INTERVAL_RACE if phase == Phase.RACING else PING_INTERVAL_LOBBY
		_ping.rpc_id(1, Time.get_ticks_msec())

## Backgrounding mid-race is a DNF: the phone stops simulating, and coming
## back to a race that went on without it would be meaningless.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		forfeit()

# --- Connection signals ---------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if role == Role.HOST and _peer != null:
		_set_timeout(_peer.get_peer(id))

func _on_peer_disconnected(id: int) -> void:
	if role != Role.HOST:
		return
	_kick_after.erase(id)
	if not peers.has(id):
		return
	peers.erase(id)
	if phase == Phase.RACING:
		_record_finish(id, DNF)
	_send_lobby()

func _on_connected_to_server() -> void:
	if role != Role.CLIENT:
		return
	_set_timeout(_peer.get_peer(1))
	_hello.rpc_id(1, PROTOCOL, SpawnerScript.COURSE_VERSION, _game_version(),
		Settings.player_name, Settings.player_color, _my_shape(), Settings.trail_enabled)

func _on_connection_failed() -> void:
	if role == Role.CLIENT:
		leave("NO ROOM AT THAT ADDRESS")

func _on_server_disconnected() -> void:
	if role == Role.CLIENT:
		leave("THE HOST LEFT")

# --- Messages -------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _hello(protocol: int, course_version: int, version: String,
		player_name: String, color: Color, shape: int, trail: bool) -> void:
	if role != Role.HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if protocol != PROTOCOL or course_version != SpawnerScript.COURSE_VERSION \
			or version != _game_version():
		reason = "DIFFERENT GAME VERSIONS - UPDATE BOTH PHONES"
	elif phase != Phase.LOBBY:
		reason = "A RACE IS ON - JOIN WHEN IT'S OVER"
	elif peers.size() >= MAX_PLAYERS:
		reason = "THE ROOM IS FULL"
	if reason != "":
		_rejected.rpc_id(id, reason)
		_kick_after[id] = REJECT_GRACE
		return
	var slot := _free_slot()
	peers[id] = {"slot": slot, "name": _room_name(player_name, slot, id), "color": color,
		"shape": shape, "trail": trail, "ready": false}
	_send_lobby()

@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	leave(reason)

@rpc("authority", "call_remote", "reliable")
func _lobby(new_peers: Dictionary, new_target: int, new_items: bool) -> void:
	peers = new_peers
	target_index = new_target
	items_on = new_items
	peers_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _set_ready(ready: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if role != Role.HOST or phase != Phase.LOBBY or not peers.has(id):
		return
	peers[id]["ready"] = ready
	_send_lobby()

@rpc("any_peer", "call_remote", "reliable")
func _set_profile(player_name: String, color: Color, shape: int, trail: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1  # called directly on the host
	if role != Role.HOST or not peers.has(id):
		return
	var info: Dictionary = peers[id]
	info["name"] = _room_name(player_name, int(info["slot"]), id)
	info["color"] = color
	info["shape"] = shape
	info["trail"] = trail
	# Mid-race, keep the results' copy in step, so the placings carry the
	# name the others have been reading on the ghost.
	if _racers.has(id):
		_racers[id]["name"] = info["name"]
	_send_lobby()

@rpc("any_peer", "call_remote", "unreliable")
func _ping(client_ms: int) -> void:
	if role == Role.HOST:
		_pong.rpc_id(multiplayer.get_remote_sender_id(), client_ms, Time.get_ticks_msec())

## NTP's estimate, minus its refinements: the host read its clock halfway
## through the round trip. Of the recent samples the quickest is kept -- a slow
## one spent its extra time queued somewhere, in one direction or the other.
@rpc("authority", "call_remote", "unreliable")
func _pong(client_ms: int, host_ms: int) -> void:
	var now := Time.get_ticks_msec()
	var rtt := now - client_ms
	_pings.append([rtt, host_ms + (rtt >> 1) - now])
	if _pings.size() > PING_SAMPLES:
		_pings.pop_front()
	var best: Array = _pings[0]
	for sample in _pings:
		if sample[0] < best[0]:
			best = sample
	_clock_offset = best[1]

@rpc("authority", "call_remote", "reliable")
func _start(course_seed: int, new_target: int, host_at_ms: int, song: int,
		items: bool) -> void:
	phase = Phase.RACING
	music_set = song
	items_on = items
	target_index = clampi(new_target, 0, Race.TARGETS.size() - 1)
	start_at_ms = host_at_ms - _clock_offset
	closing_at_ms = 0
	results = []
	_finished_local = false
	_state_wait = 0.0
	Race.active = true
	Race.course_seed = course_seed
	Race.shared_target = Race.TARGETS[target_index]
	stop_browsing()
	Transition.change_scene("res://scenes/main.tscn")

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _state(t: float, pos: Vector2, score: int, flags: int) -> void:
	if in_race():
		rival_state.emit(multiplayer.get_remote_sender_id(), t, pos, score, flags)

@rpc("any_peer", "call_remote", "reliable")
func _finished(time: float) -> void:
	if role == Role.HOST:
		_record_finish(multiplayer.get_remote_sender_id(), time)

@rpc("any_peer", "call_remote", "reliable")
func _course_hash(hash: int) -> void:
	if role == Role.HOST:
		_store_hash(multiplayer.get_remote_sender_id(), hash)

@rpc("any_peer", "call_remote", "reliable")
func _attack_request(kind: int, targets: Array) -> void:
	if role == Role.HOST:
		_relay_attack(multiplayer.get_remote_sender_id(), kind, targets)

@rpc("authority", "call_remote", "reliable")
func _attacked(from: int, kind: int) -> void:
	if in_race():
		attacked.emit(from, kind)

@rpc("any_peer", "call_remote", "reliable")
func _attack_report(from: int, kind: int, blocked: bool) -> void:
	if role == Role.HOST:
		_send_outcome(from, multiplayer.get_remote_sender_id(), kind, blocked)

@rpc("authority", "call_remote", "reliable")
func _attack_outcome(from: int, victim: int, kind: int, blocked: bool) -> void:
	if in_race():
		attack_outcome.emit(from, victim, kind, blocked)

@rpc("authority", "call_remote", "reliable")
func _closing(host_at_ms: int) -> void:
	closing_at_ms = host_at_ms - _clock_offset
	closing_started.emit()

@rpc("authority", "call_remote", "reliable")
func _results(order: Array) -> void:
	results = order
	phase = Phase.LOBBY
	closing_at_ms = 0
	results_ready.emit()

@rpc("authority", "call_remote", "reliable")
func _aborted(reason: String) -> void:
	phase = Phase.LOBBY
	closing_at_ms = 0
	results = []
	race_aborted.emit(reason)

# --- Host bookkeeping -----------------------------------------------------

## To everyone let in, and to this phone. Not a plain .rpc(): that would also
## reach a joiner still being turned away.
func _send_lobby() -> void:
	for id in peers:
		if id != 1:
			_lobby.rpc_id(id, peers, target_index, items_on)
	_lobby(peers, target_index, items_on)

func _record_finish(id: int, time: float) -> void:
	if phase != Phase.RACING or not _racers.has(id) or _finish_times.has(id):
		return
	_finish_times[id] = time
	if time >= 0.0 and closing_at_ms == 0:
		var at := Time.get_ticks_msec() + FINISH_GRACE_MS
		for other in peers:
			if other != 1:
				_closing.rpc_id(other, at)
		_closing(at)
	if _finish_times.size() >= _racers.size():
		_conclude()

func _conclude() -> void:
	if phase != Phase.RACING:
		return
	var order: Array = []
	for id in _racers:
		var info: Dictionary = _racers[id]
		order.append({"id": id, "name": info["name"], "color": info["color"],
			"time": float(_finish_times.get(id, DNF))})
	order.sort_custom(_finishes_before)
	for id in peers:
		peers[id]["ready"] = id == 1
	for id in peers:
		if id != 1:
			_results.rpc_id(id, order)
	_results(order)
	_send_lobby()

static func _finishes_before(a: Dictionary, b: Dictionary) -> bool:
	var ta: float = a["time"]
	var tb: float = b["time"]
	if (ta < 0.0) != (tb < 0.0):
		return tb < 0.0
	return ta < tb

## Every phone hashes the start of the course it built; any disagreement means
## the race is not a race, so it is called off rather than run unfairly. Should
## never happen -- the handshake already checked versions and screen width --
## but if it does it is a determinism bug, and logged as one.
func _store_hash(id: int, hash: int) -> void:
	if phase != Phase.RACING:
		return
	_hashes[id] = hash
	if not _hashes.has(1):
		return
	for other in _hashes:
		if _hashes[other] != _hashes[1]:
			push_warning("[lan] course mismatch: host %d, peer %d has %d" % [
				_hashes[1], other, _hashes[other]])
			_abort("THE PHONES BUILT DIFFERENT COURSES")
			return

func _abort(reason: String) -> void:
	for id in peers:
		peers[id]["ready"] = id == 1
		if id != 1:
			_aborted.rpc_id(id, reason)
	_aborted(reason)
	_send_lobby()

func _relay_attack(from: int, kind: int, targets: Array) -> void:
	if phase != Phase.RACING or not items_on or not _racers.has(from):
		return
	for target in targets:
		var id := int(target)
		if id == from or not peers.has(id) or _finish_times.has(id):
			continue
		if id == 1:
			_attacked(from, kind)
		else:
			_attacked.rpc_id(id, from, kind)

func _send_outcome(from: int, victim: int, kind: int, blocked: bool) -> void:
	for id in peers:
		if id != 1:
			_attack_outcome.rpc_id(id, from, victim, kind, blocked)
	_attack_outcome(from, victim, kind, blocked)

func _free_slot() -> int:
	var taken := []
	for id in peers:
		taken.append(peers[id]["slot"])
	for slot in range(1, MAX_PLAYERS + 1):
		if not taken.has(slot):
			return slot
	return MAX_PLAYERS

## A small JSON beacon, broadcast every second while the room is open. Sent to
## the all-ones address and to each interface's own /24 broadcast: a phone
## running a hotspot can route the former out of its mobile data instead. And
## to this machine itself, for several copies of the game on one computer --
## the quickest way to test (Debug > Customize Run Instances).
func _announce() -> void:
	if _announcer == null:
		return
	var message := JSON.stringify({"game": "jetlet", "v": PROTOCOL,
		"name": OS.get_model_name(), "players": peers.size(), "max": MAX_PLAYERS})
	var packet := message.to_utf8_buffer()
	var targets := PackedStringArray(["255.255.255.255", "127.0.0.1"])
	for address in local_addresses():
		var parts := address.split(".")
		targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	for target in targets:
		_announcer.set_dest_address(target, DISCOVERY_PORT)
		_announcer.put_packet(packet)

func _poll_rooms() -> void:
	if _listener == null:
		return
	var now := Time.get_ticks_msec()
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var packet := _listener.get_packet()
		var address := _listener.get_packet_ip()
		var message = JSON.parse_string(packet.get_string_from_utf8())
		if not (message is Dictionary and message.get("game") == "jetlet"
				and int(message.get("v", 0)) == PROTOCOL):
			continue
		var room := {"name": str(message.get("name", "")),
			"players": int(message.get("players", 1)),
			"max": int(message.get("max", MAX_PLAYERS)), "seen": now}
		var known: Dictionary = rooms.get(address, {})
		if known.get("players") != room["players"] or known.get("name") != room["name"]:
			changed = true
		rooms[address] = room
	for address in rooms.keys():
		if now - int(rooms[address]["seen"]) > ROOM_TTL_MS:
			rooms.erase(address)
			changed = true
	if changed:
		rooms_changed.emit()

# --- Helpers --------------------------------------------------------------

func _my_info(slot: int) -> Dictionary:
	return {"slot": slot, "name": _room_name(Settings.player_name, slot, 1),
		"color": Settings.player_color, "shape": _my_shape(),
		"trail": Settings.trail_enabled, "ready": false}

## The name `id` goes by in this room: what they typed, cleaned up the same way
## whoever typed it (Settings.clean_player_name), or their slot if that leaves
## nothing. Two players who picked the same name get their slot added, so the
## tags and placings can tell them apart.
func _room_name(raw: String, slot: int, id: int) -> String:
	var wanted := Settings.clean_player_name(raw)
	if wanted == "":
		return "P%d" % slot
	for other in peers:
		if other != id and peers[other]["name"] == wanted:
			return "%s %d" % [wanted.left(Settings.PLAYER_NAME_MAX - 2).strip_edges(), slot]
	return wanted

func _my_shape() -> int:
	return Player.SKIN_SHAPES.get(Settings.active_player_skin(), PlasmaBlob.Shape.CIRCLE)

func _game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))

func _set_timeout(packet_peer: ENetPacketPeer) -> void:
	if packet_peer != null:
		packet_peer.set_timeout(PEER_TIMEOUT[0], PEER_TIMEOUT[1], PEER_TIMEOUT[2])

static func _is_private_ipv4(address: String) -> bool:
	if not address.is_valid_ip_address() or address.contains(":"):
		return false
	var parts := address.split(".")
	var a := parts[0].to_int()
	var b := parts[1].to_int()
	return a == 10 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31)

## Android drops broadcast packets to save power unless an app holds a
## multicast lock -- the JetletNotify plugin takes one for us. Absent off
## Android, and on a build with an older plugin, which then just hears fewer
## rooms (joining by address still works).
func _set_multicast_lock(on: bool) -> void:
	if not Engine.has_singleton("JetletNotify"):
		return
	var plugin := Engine.get_singleton("JetletNotify")
	var method := "acquireMulticastLock" if on else "releaseMulticastLock"
	if plugin.has_method(method):
		plugin.call(method)
