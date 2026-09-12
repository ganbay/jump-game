extends Node

## What has to be earned before a skin can be worn, and what already has been.
##
## Deliberately its own store rather than a field on either neighbour: Settings
## holds the choice a player has made, Stats holds what they have earned, and an
## unlock is neither -- it is permission to make the choice. Coins are not spent
## on any of this -- the currency is disabled here for now (Stats.coins still
## exists, still gets earned and shown, it just isn't a purchase mechanism at
## the moment; that may come back later). Every complex-tier skin instead gates
## on something the player did, read straight off Stats.

const SAVE_PATH := "user://unlocks.cfg"

const SKIN_PREFIX := "skin:"

## What has to be true for a gated skin's Stats flag to flip. RATE and
## PURCHASE both need a player action this class can't perform on its own --
## RATE's is a button that opens the store listing (see customization.gd),
## PURCHASE has no real payment flow wired up yet, so it stays permanently
## locked until one exists.
enum Requirement { RATE, ESCAPE, TRUE_ENDING, PURCHASE }

## id -> requirement. Anything absent is free and always owned -- PLASMA and
## the whole basic tier (PRISM, SQUARE, TRIANGLE, DOME, DIAMOND) fall through
## to that default without needing their own entries.
const REQUIREMENTS := {
	"skin:STAR": Requirement.RATE,
	"skin:FLAME": Requirement.ESCAPE,
	"skin:SPARKLE": Requirement.TRUE_ENDING,
	"skin:HEART": Requirement.PURCHASE,
}

## Used as a set; only the keys matter. Kept for two reasons rather than
## dropped now that nothing charges coins any more: it grandfathers in
## whatever a save already earned under the old coin-purchase system, and it
## is where a real PURCHASE flow would record a completed sale later.
var _owned: Dictionary = {}

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		for id in cfg.get_value("unlocks", "owned", []):
			_owned[id] = true
		return
	# First launch under the unlock system. Whatever the player is already
	# wearing is granted: the whole roster was free before this existed, and
	# taking one back would read as the update having confiscated it.
	_owned[skin_id(Settings.player_skin)] = true
	_save()

## PLASMA is absent from REQUIREMENTS, so the starter skin is free by
## omission rather than by a special case here.
static func skin_id(skin: int) -> String:
	return SKIN_PREFIX + Player.SKIN_NAMES[skin]

## -1 when the skin is free and has no requirement at all.
func requirement_of(id: String) -> int:
	return REQUIREMENTS.get(id, -1)

func is_unlocked(id: String) -> bool:
	if _owned.has(id):
		return true
	match REQUIREMENTS.get(id, -1):
		Requirement.RATE:
			return Stats.rated_game
		Requirement.ESCAPE:
			return Stats.escaped
		Requirement.TRUE_ENDING:
			return Stats.true_ending
		Requirement.PURCHASE:
			return false
		_:
			return true

## Promotes any gated skin whose condition has become true since it was last
## checked into _owned, and returns the ids newly promoted. ESCAPE and
## TRUE_ENDING flip mid-run, far from the customization screen, so without
## this the player would only find out by browsing past the skin some other
## time -- call this on entering that screen to catch and announce it instead.
func claim_newly_unlocked() -> Array[String]:
	var newly: Array[String] = []
	for id in REQUIREMENTS:
		if not _owned.has(id) and is_unlocked(id):
			_owned[id] = true
			newly.append(id)
	if not newly.is_empty():
		_save()
	return newly

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("unlocks", "owned", _owned.keys())
	cfg.save(SAVE_PATH)
