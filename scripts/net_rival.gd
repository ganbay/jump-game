extends Rival
class_name NetRival

## A racer on another phone (see lan_race.gd), drawn from the positions it
## sends about 15 times a second. Nothing is simulated here.
##
## Playback runs PLAYBACK_DELAY behind the shared race clock, so there are
## almost always two samples to blend between and the ghost moves smoothly
## rather than in 15 Hz steps. When the next sample is late it carries on along
## its last velocity for up to MAX_EXTRAPOLATION, then holds still.

const PLAYBACK_DELAY := 0.1
const MAX_EXTRAPOLATION := 0.25
const KEEP_SAMPLES := 8
## Falling, then rising this fast a frame later, is a bounce off a platform --
## which is all a landing looks like from here.
const BOUNCE_SPEED := 200.0
const ITEM_FLAGS := LanRace.FLAG_SHIELDED | LanRace.FLAG_STUNNED | LanRace.FLAG_REVERSED

var peer_id: int = 0
## The latest state flags (LanRace.FLAG_*): over the line, and any race item
## running on them, drawn on the ghost (see _draw).
var flags: int = 0
var finished: bool = false

## [t, pos, score, flags], oldest first, t on LanRace.race_clock().
var _samples: Array = []
var _prev_vy: float = 0.0

var _trail: PlayerTrail

## `info` is the peer's LanRace.peers entry. Called before entering the tree:
## the ghost wears the player's own character (see Rival.ghost_core).
func setup(id: int, info: Dictionary) -> void:
	peer_id = id
	ghost_core = false
	_read_profile(info)

## Dresses the ghost and starts playback. It stays out of sight until the
## first sample says where it is. `feet_offset` is how far above the feet the
## player's body (and so its trail) sits -- this ghost's origin is its feet.
func begin(info: Dictionary, feet_offset: float) -> void:
	show_ghost(int(info.get("shape", PlasmaBlob.Shape.CIRCLE)) as PlasmaBlob.Shape)
	visible = false
	_trail = PlayerTrail.new()
	# As on the player: world space, so the fragments stay where they were
	# shed rather than following the ghost around.
	_trail.top_level = true
	_trail.z_index = z_index
	_trail.z_as_relative = false
	_trail.emit_offset = Vector2(0.0, -feet_offset)
	add_child(_trail)
	restyle(info)

## The player's profile can change mid-race: the run rolls a shuffled skin
## after the lobby saw the old one (see LanRace.send_profile).
func restyle(info: Dictionary) -> void:
	_read_profile(info)
	_visual.color = color
	_visual.shape = int(info.get("shape", PlasmaBlob.Shape.CIRCLE)) as PlasmaBlob.Shape
	if _trail != null:
		_trail.color = color
		_trail.shape = _visual.shape
		_trail.set_enabled(bool(info.get("trail", true)))
	queue_redraw()

func _read_profile(info: Dictionary) -> void:
	label = str(info.get("name", "?"))
	color = info.get("color", Color.WHITE)

func push_state(t: float, pos: Vector2, new_score: int, new_flags: int) -> void:
	if not _samples.is_empty() and t <= float(_samples.back()[0]):
		return
	if _samples.is_empty():
		global_position = pos  # no streak across the screen from the origin
	_samples.append([t, pos, new_score, new_flags])
	if _samples.size() > KEEP_SAMPLES:
		_samples.pop_front()
	# The latest score, not the played-back one: the rail and the tags should
	# not trail a tenth of a second behind what is known.
	score = new_score
	var respawning := new_flags & LanRace.FLAG_RESPAWNING != 0
	respawn_left = 1.0 if respawning else 0.0
	finished = finished or new_flags & LanRace.FLAG_FINISHED != 0
	if new_flags != flags:
		flags = new_flags
		queue_redraw()

func _process(delta: float) -> void:
	if not _samples.is_empty():
		var previous := global_position
		global_position = _position_at(LanRace.race_clock() - PLAYBACK_DELAY)
		if delta > 0.0:
			velocity = (global_position - previous) / delta
		if _prev_vy > BOUNCE_SPEED and velocity.y < -BOUNCE_SPEED:
			squash(1.0)
		_prev_vy = velocity.y
		visible = not is_respawning()
	if flags & ITEM_FLAGS != 0:
		queue_redraw()
	super(delta)

## A burst of brightness: this racer just threw something at the player.
func flash() -> void:
	var tw := create_tween()
	modulate = Color(2.5, 2.5, 2.5, 1.0)
	tw.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, GHOST_ALPHA), 0.7)

## Origin is the feet; the body sits about a radius above them.
func _draw() -> void:
	super()
	RaceItems.draw_status(self, Vector2(0.0, -18.0),
		flags & LanRace.FLAG_SHIELDED != 0, flags & LanRace.FLAG_STUNNED != 0,
		flags & LanRace.FLAG_REVERSED != 0, Time.get_ticks_msec() / 1000.0)

func _position_at(t: float) -> Vector2:
	var first: Array = _samples[0]
	if t <= float(first[0]):
		return first[1]
	for i in range(_samples.size() - 1, 0, -1):
		var a: Array = _samples[i - 1]
		var b: Array = _samples[i]
		if t >= float(a[0]) and t <= float(b[0]):
			var span := float(b[0]) - float(a[0])
			var u := (t - float(a[0])) / span if span > 0.0 else 1.0
			return (a[1] as Vector2).lerp(b[1], u)
	# Past the newest sample: carry on along the last known velocity, briefly.
	var last: Array = _samples.back()
	if _samples.size() < 2:
		return last[1]
	var before: Array = _samples[_samples.size() - 2]
	var span := float(last[0]) - float(before[0])
	if span <= 0.0:
		return last[1]
	var heading := ((last[1] as Vector2) - (before[1] as Vector2)) / span
	return (last[1] as Vector2) + heading * minf(t - float(last[0]), MAX_EXTRAPOLATION)
