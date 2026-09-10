extends Node
class_name ZoneDirector

## Zones are 2000-score stretches of the climb that force one extra attribute
## onto every platform inside them, on top of whatever each platform rolled for
## itself (see platform.gd).
##
## The run opens with a plain zone, then works through each of the four zones
## alone, then every pair of them, then every triple, and finally all four at
## once. Clearing the four singles is escaping Solar gravity -- the goal the
## game was set up around -- and clearing the last stage is the true ending.
## Both are announced; both leave the choice of stopping or climbing on.

signal zone_changed(stage: int, zone_name: String)
signal milestone_reached(kind: int)

enum Zone { MOVING, GLASS, INVISIBLE, SQUISHY }
enum Milestone { ESCAPE, TRUE_END }

const ZONE_LENGTH := 2000
const ZONE_COUNT := 4
const ZONE_NAMES := ["DRIFT", "GLASS", "PHANTOM", "SQUISH"]
const OPENING_NAME := "OPEN SPACE"
const ALL_ZONES_NAME := "ALL ZONES"

## Stage 0 is the opening, 1-4 the four single zones, 5-10 the six pairs, 11-14
## the four triples and 15 all four at once. Past that the run stays on stage
## 15's content for as long as the player survives.
const ESCAPE_STAGE := 5
const FINAL_STAGE := 15
const TRUE_END_STAGE := FINAL_STAGE + 1

## One zone bitmask (over Zone, not Platform.Attr) per stage.
var _stages: Array[int] = []
var _stage: int = -1
var _fired: int = 0

func _ready() -> void:
	_stages.append(0)
	for size in range(1, ZONE_COUNT + 1):
		var combos: Array[int] = []
		for mask in range(1, 1 << ZONE_COUNT):
			if _popcount(mask) == size:
				combos.append(mask)
		# Shuffled within each block, so which single zone comes first (and
		# which pair follows the singles) differs from run to run, while the
		# one-then-two-then-three ramp stays fixed.
		combos.shuffle()
		_stages.append_array(combos)

## Driven from game.gd with the run's live score.
func update(score: int) -> void:
	var stage := stage_for_score(score)
	if stage == _stage:
		return
	_stage = stage
	zone_changed.emit(stage, zone_name(stage))
	if stage >= TRUE_END_STAGE:
		_fire(Milestone.TRUE_END)
	elif stage >= ESCAPE_STAGE:
		_fire(Milestone.ESCAPE)

func stage_for_score(score: int) -> int:
	return mini(int(score / ZONE_LENGTH), TRUE_END_STAGE)

## The attributes this stretch of the climb forces onto a platform. Rolled per
## platform rather than per stage, because the moving zone picks an axis.
func attrs_for_score(score: int) -> int:
	var mask := _stages[clampi(stage_for_score(score), 0, _stages.size() - 1)]
	var attrs := 0
	if mask & (1 << Zone.MOVING):
		attrs |= Platform.Attr.MOVE_V if randf() < 0.5 else Platform.Attr.MOVE_H
	if mask & (1 << Zone.GLASS):
		attrs |= Platform.Attr.GLASS
	if mask & (1 << Zone.INVISIBLE):
		attrs |= Platform.Attr.INVISIBLE
	if mask & (1 << Zone.SQUISHY):
		attrs |= Platform.Attr.SQUISHY
	return attrs

func zone_name(stage: int) -> String:
	var mask := _stages[clampi(stage, 0, _stages.size() - 1)]
	if mask == 0:
		return OPENING_NAME
	if _popcount(mask) == ZONE_COUNT:
		return ALL_ZONES_NAME
	var parts := PackedStringArray()
	for z in range(ZONE_COUNT):
		if mask & (1 << z):
			parts.append(ZONE_NAMES[z])
	return "%s ZONE" % " + ".join(parts)

func _fire(kind: Milestone) -> void:
	var bit := 1 << kind
	if _fired & bit:
		return
	_fired |= bit
	milestone_reached.emit(kind)

func _popcount(mask: int) -> int:
	var n := 0
	while mask > 0:
		n += mask & 1
		mask >>= 1
	return n
