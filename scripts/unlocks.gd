extends Node

## What currency can buy, and what has already been bought.
##
## Deliberately its own store rather than a field on either neighbour: Settings
## holds the choice a player has made, Stats holds what they have earned, and an
## unlock is neither -- it is permission to make the choice. Keeping it apart is
## also what makes it extensible. An id is an opaque string and nothing in here
## knows what a skin is, so adding trails, platform styles, music sets or
## anything else later is entries in CATALOGUE plus a screen to show them; the
## buying, the balance check and the save file all already work.

signal unlocked(id: String)

const SAVE_PATH := "user://unlocks.cfg"

const SKIN_PREFIX := "skin:"

## id -> price in coins. Anything absent is free and always owned, so a category
## can be added a few entries at a time without stranding the rest of it. Skins
## are priced in tiers rather than flat: the roster is browsed in order, so a
## climbing price is what stops the last one being the obvious first buy.
const CATALOGUE := {
	"skin:DOME": 150,
	"skin:TRIANGLE": 150,
	"skin:SQUARE": 250,
	"skin:PRISM": 250,
	"skin:STAR": 400,
	"skin:HEART": 400,
	"skin:FLAME": 600,
	"skin:SPARKLE": 800,
}

## Used as a set; only the keys matter.
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

## PLASMA is absent from CATALOGUE, so the starter skin is free by omission
## rather than by a special case here.
static func skin_id(skin: int) -> String:
	return SKIN_PREFIX + Player.SKIN_NAMES[skin]

func price_of(id: String) -> int:
	return CATALOGUE.get(id, 0)

func is_unlocked(id: String) -> bool:
	return price_of(id) == 0 or _owned.has(id)

func can_afford(id: String) -> bool:
	return Stats.coins >= price_of(id)

## Buys `id` if it is affordable and not already owned. Returns whether the
## purchase actually happened, so a caller can answer a refusal differently from
## a sale rather than assuming it went through.
func unlock(id: String) -> bool:
	if is_unlocked(id):
		return false
	if not Stats.spend_coins(price_of(id)):
		return false
	_owned[id] = true
	_save()
	unlocked.emit(id)
	return true

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("unlocks", "owned", _owned.keys())
	cfg.save(SAVE_PATH)
