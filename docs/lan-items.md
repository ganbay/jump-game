# LAN race items

Mario Kart style item boxes for LAN races (see lan-race.md). Tuned for the
usual room of 2-3 phones; eight is rare and must still work, but is not what
the balance is for.

## Switch

The host picks **ITEMS ON / OFF** in the lobby, under the distance. Default
ON. Sent with the lobby state and again in `start`, so every phone in a race
agrees.

## Gates

- A full-width row of 4 boxes across the course every `GATE_EVERY` score
  (1,500): ~6 / 13 / 20 gates in a 10k / 20k / 30k race. None in the last 500
  before the finish.
- Placed from `score_origin_y`, which is already the same on every phone, at
  fixed x across the shared course band. No RNG, so the course hash is
  untouched.
- Every racer has their own copy of every box: no "who got it first".
- A gate is spent the first time you rise through it. Touching a box with an
  empty slot gives you an item; holding one already, you get nothing.
- Pickup reach is generous (box centre within 78 px of the character), so
  about nine lanes in ten through a gate collect.

**Noticeable:** spinning, bobbing, colour-cycling "?" boxes on a faint gate
line; a glow along the top edge with a chevron over each box's lane as a
gate comes within a screen; a burst and a buzz on pickup.

## Holding and using

- One slot. Pickup runs a ~0.8 s roulette in the item button before landing
  on the item, which also hides that the roll favours whoever is behind.
- **Item button** bottom-right (~110 px). Tap to use. It takes its own
  touches, so it never counts as a timing tap or starts steering. Same in
  TILT and TOUCH.
- While an item's effect runs, the button shows how much is left.

## Items

Rolled on this phone from the gap to the leader (score behind / `GATE_EVERY`):
the further back, the stronger the item. The leader never gets an attack.
Nobody racing behind you (2nd of 2, last of any field) means nothing can
attack you, so Shield is never rolled then; its share goes to the rest.

| Item | Type | Effect | Phase |
|---|---|---|---|
| Rocket | self | 2 s straight up at 1,800 px/s | 1 |
| Safety Net | self | 15 s trampoline along the bottom of the screen; the first fall onto it bounces you back up instead of the 2 s respawn | 1 |
| Spring Shoes | self | Next 4 landings are automatic boosted jumps, launching 1.25x harder (~1.5x the height); streak counts | 1 |
| Shield | self | Blocks the next attack for 10 s; can be fired when the warning shows | 2 |
| Comet | attack | 1st place: upward speed cut, no steering for 2 s | 2 |
| Reverse | attack | Everyone ahead: steering swapped for 4 s | 2 |
| Heavy | attack | Everyone ahead: +30% gravity for 4 s | 3 |
| Wormhole | mixed | See below. Trailing half only | 3 |

### Attacks (phase 2, built)

- One message, `item_hit(kind)`, attacker -> host -> victim. The victim's phone
  applies it to its own player; nothing else changes about the netcode.
- Victim gets a ~1 s warning in the attacker's colour, with their name:
  "COMET FROM ALEX". The attacker's ghost flashes.
- Attacker gets "HIT SAM!" or "BLOCKED BY SAM'S SHIELD".
- Everyone gets a ~3 s feed line under the score: "ALEX [comet] SAM", with a
  shield after the victim if it was blocked.
- A Comet is drawn falling onto the victim through the warning. A held
  Shield makes the item button throb while something is incoming.
- Shield, stun and reverse show on your own character and, through the state
  flags (`LanRace.FLAG_SHIELDED` / `STUNNED` / `REVERSED`), on your ghost.
- Targets are picked on the attacker's phone from the latest scores (Comet:
  the leader; Reverse: everyone ahead), finished racers excluded. With nobody
  ahead the item is kept ("NOBODY AHEAD"), and the roll stops offering
  attacks.

### Wormhole (phase 3)

- Only the trailing half of the field can roll it (2nd of 2, 2nd-3rd of 3,
  5th-8th of 8), and only while someone ahead has not finished.
- **Blue** (lower) opens ~1.5 jumps above the user, offset sideways so it has
  to be steered into. **Red** (upper) opens ~1 jump above the player directly
  ahead, on their line, so they have to steer to dodge it.
- Both ways: blue sends you up to red, red sends you down to blue. Anyone can
  ride them. You come out with a boosted jump's speed, and cannot re-enter
  the portal you just left.
- Each phone places the portal near its own real position (the user's blue,
  the target's red) and the target's phone broadcasts the pair, so nobody gets
  a portal dropped where their ghost was a moment ago.
- Open 25 s, after a 0.5 s opening swirl. Blue closes early once every racer
  is above it; red closes with it.
- Feed: "ALEX OPENED A WORMHOLE", "SAM TOOK THE PORTAL!".

## Code

| What | Where |
|---|---|
| Gates, pickup, roll, effects, world drawing | `scripts/race_items.gd` (`RaceItems`) |
| Item button, roulette, gate warning | `scripts/item_button.gd` (`ItemButton`) |
| Rocket, Spring Shoes, Comet stun, Reverse hooks | `player.gd` (`start_rocket`, `auto_boosts`, `stun_left`, `reverse_left`) |
| Attack messages | `LanRace.send_attack` / `report_attack`, signals `attacked` / `attack_outcome` |
| Status on ghosts | `NetRival.flags`, `RaceItems.draw_status` |
| Net catch, wiring | `game.gd`, the "LAN race" section |
| Switch | `LanRace.items_on`, lobby "ITEMS" button |
