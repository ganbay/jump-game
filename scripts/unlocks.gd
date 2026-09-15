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

## What has to be true for a gated skin's Stats flag to flip. RATE, ADS and
## PURCHASE all need a player action this class can't perform on its own --
## RATE's is a button that opens the store listing (see customization.gd),
## ADS is a button that plays a rewarded ad and comes back through
## record_ad_watched(), and PURCHASE has no real payment flow wired up yet, so
## it stays permanently locked until one exists.
enum Requirement { RATE, ESCAPE, TRUE_ENDING, ADS, PURCHASE }

## id -> requirement. Anything absent is free and always owned -- PLASMA and
## the whole basic tier (PRISM, SQUARE, TRIANGLE, DOME, DIAMOND) fall through
## to that default without needing their own entries.
const REQUIREMENTS := {
	"skin:STAR": Requirement.RATE,
	"skin:FLAME": Requirement.ESCAPE,
	"skin:SPARKLE": Requirement.TRUE_ENDING,
	"skin:HEART": Requirement.ADS,
}

## Rewarded ads that have to be watched through to the end before HEART opens.
const ADS_REQUIRED := 3

## Bumped whenever a skin changes tier in a way that existing saves have to be
## corrected for -- see _migrate().
const SAVE_VERSION := 1

## Skins an older save may hold in _owned that a later version put behind a
## gate, keyed by the version that gated them. HEART was free along with the
## rest of the roster before unlocks existed, so anyone wearing it when
## unlocks.cfg was first written had it granted permanently by the
## grandfathering below -- and _owned is checked ahead of the requirement, so
## the ad gate would never be consulted for them. Taking it back once is what
## makes that gate mean anything.
const REVOKED_AT_VERSION := {
	1: ["skin:HEART"],
}

## Used as a set; only the keys matter. Kept for two reasons rather than
## dropped now that nothing charges coins any more: it grandfathers in
## whatever a save already earned under the old coin-purchase system, and it
## is where a real PURCHASE flow would record a completed sale later.
var _owned: Dictionary = {}

## Progress toward the ADS gate. The other gates read their condition straight
## off Stats, but this one has no gameplay meaning to record there -- it counts
## rewarded ads watched from the customization screen and nothing else -- so it
## is saved here, with the gate it belongs to.
var ads_watched: int = 0

func _ready() -> void:
	var cfg := ConfigFile.new()
	var version: int = 0
	if cfg.load(SAVE_PATH) == OK:
		for id in cfg.get_value("unlocks", "owned", []):
			_owned[id] = true
		ads_watched = cfg.get_value("unlocks", "ads_watched", 0)
		version = cfg.get_value("unlocks", "version", 0)
	else:
		# First launch under the unlock system. Whatever the player is already
		# wearing is granted: the whole roster was free before this existed, and
		# taking one back would read as the update having confiscated it.
		_owned[skin_id(Settings.player_skin)] = true
	# Deliberately also runs for the branch above: a save written before this
	# system existed and one written by an early version of it can both be
	# holding a skin that is now gated, and a fresh unlocks.cfg grandfathering
	# the worn skin is itself one of the ways that happens.
	if version < SAVE_VERSION:
		_migrate(version)

## Walks the save forward one version at a time, so a player skipping several
## updates gets every step applied rather than only the newest.
func _migrate(from_version: int) -> void:
	for version in range(from_version + 1, SAVE_VERSION + 1):
		for id in REVOKED_AT_VERSION.get(version, []):
			_owned.erase(id)
	# Revoking the skin being worn would leave the player in a state the picker
	# cannot produce -- a locked character equipped -- so the starter skin takes
	# over, the same one a fresh save begins on.
	if not is_unlocked(skin_id(Settings.player_skin)):
		Settings.set_player_skin(Player.SkinType.PLASMA)
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
		Requirement.ADS:
			return ads_watched >= ADS_REQUIRED
		Requirement.PURCHASE:
			return false
		_:
			return true

## Banks one fully watched rewarded ad toward the ADS gate. Only a completed
## ad gets here -- a skipped one lands on the dismissal callback instead (see
## Ads.show_rewarded), so nothing is credited for closing the ad early.
## Counting past ADS_REQUIRED would be harmless but pointless, so it stops
## there and the file stops being rewritten on every later ad.
func record_ad_watched() -> void:
	if ads_watched >= ADS_REQUIRED:
		return
	ads_watched += 1
	_save()

## How many more the ADS gate still wants. Drives the progress text on the
## customization screen, so the player can see the counter move after each ad
## rather than watching three and hoping.
func ads_remaining() -> int:
	return maxi(ADS_REQUIRED - ads_watched, 0)

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
	cfg.set_value("unlocks", "ads_watched", ads_watched)
	cfg.set_value("unlocks", "version", SAVE_VERSION)
	cfg.save(SAVE_PATH)
