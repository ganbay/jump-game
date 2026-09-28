# Seeded course — dev log & multiplayer groundwork

Working log for making the climb reproducible from a seed. This is step one of
racing other people: every racer has to climb the same platforms. The plan
after it (LAN race, then maybe online) is at the bottom.

## Log

### 2026-09-28 — seeded course (COURSE_VERSION 1)

**Done**

- `PlatformSpawner` owns its own `RandomNumberGenerator` (`_rng`), seeded in
  `begin(from_y, new_seed := -1)`. A negative seed rolls a fresh one;
  `spawner.course_seed` records which was used. `randomize()` removed from
  `_ready` (Godot 4 seeds the global RNG on startup anyway).
- **Fixed draws per slot.** `_add_slot` always takes exactly 7 draws (gap, x,
  dir, v_phase, moving-axis, natural attribute, phantom phase) before deciding
  anything. Before this, slots under score 1,000 took fewer draws and only
  DRIFT-zone slots took the axis draw. So the draw count depended on
  `score_origin_y`, which settles a little differently every run (it follows
  the intro launch until its apex), and one small nudge reshuffled every
  platform above it.
- `ZoneDirector.reseed(seed)` rebuilds the zone order with a seeded
  Fisher-Yates. `Array.shuffle()` only uses the global RNG.
  `attrs_for_score(score, axis_roll)` now takes its axis roll from the spawner
  instead of calling `randf()`.
- The phantom (invisible) blink is seeded too. `CourseSlot.phantom_phase`
  (0..1) goes through `Platform.set_motion(..., phantom_phase)` and is applied
  against course time. Racers on one seed see a platform vanish at the same
  course time.
- `game.gd` picks the run's seed at intro hand-off:
  `Race.course_seed` if a race set one (>= 0), otherwise `randi()`. It calls
  `zones.reseed()` and then `spawner.begin(..., seed)`, and reports the seed to
  Crashlytics as `course_seed`, so a bug report's course can be replayed.
- `Race.course_seed := -1`, not saved. It's the hook a future LAN or online
  lobby sets before starting. Bot races still roll a fresh course each race.
- `PlatformSpawner.COURSE_VERSION := 1`. Bump it on any change to how a seed
  becomes a course (draw order, gap/width/attribute tuning, zone shuffle, the
  spawner's `@export` values in `main.tscn`). A lobby must refuse to start
  when two devices disagree on it.

**Verified** (headless, generating 40,000 score of course = 2,146 slots):

| check | result |
|---|---|
| same seed twice → identical slots (x, y, attrs, dir, v_phase, phantom) | ✅ |
| different seed → different course | ✅ |
| same seed, `score_origin_y` nudged by 37 px → x/y/dir unchanged | ✅ |
| …attributes that changed with the nudge | 2 of 2,146 slots (zone-boundary platforms, see gap 2) |

Not play-tested yet. Casual and bot races should play exactly as before, just
from a seed.

**Known gaps (for the multiplayer work)**

1. **Screen width.** x is laid out as a fraction of the viewport width
   (`lerpf(edge_margin, width - edge_margin, x_roll)`). Under the `expand`
   stretch, portrait phones are all 720 wide, so phone vs phone matches.
   Tablets and wider aspect ratios get a wider screen, which scales the layout
   and gives sideways movers a longer bounce. Options: fix the course width to
   720 in shared races and centre it, or accept the difference and only allow
   devices of the same width class to race.
2. **Zone-boundary attributes.** Forced zone attributes are chosen by
   `_frontier_score()`, which is measured from the live `score_origin_y`. A
   platform within a few pixels of a 2,000-score boundary can land in
   different zones on two devices (2/2,146 above). Fix for shared races: decide
   zone membership from height above `_origin_y` plus a fixed offset, not the
   live origin. Check that the zone banners still line up.
3. **Clock alignment.** Movers and phantoms are positioned from
   `course_time`, which each device starts at its own intro hand-off. The
   layout doesn't depend on it, but for a fair live race the lobby countdown
   has to start everyone's run together. Race mode should probably also skip
   the intro, or everyone should use the same intro length.
4. **Float determinism across CPUs.** Godot's RNG (PCG32) gives the same
   sequence on every platform, and the course maths is simple lerps.
   ARM and x86 should agree, but it's unconfirmed. The LAN prototype should
   exchange a hash of the first N slots at race start and log any mismatch.
5. **Not seeded, and doesn't need to be:** the race bot's decisions, particles,
   screen shake. They don't affect the course.

## Next steps

The detailed LAN plan (scope, protocol, work breakdown, testing, risks) is in
**`docs/lan-race.md`**. Summary:

1. **Close gaps 2 and 3** (small), then add a `course_hash(n)` helper on the
   spawner for the lobby handshake.
2. **LAN race prototype, two phones:**
   - Host/join using `ENetMultiplayerPeer`, joining by typed IP address first
     (UDP broadcast discovery later, since Android can drop broadcasts without
     a Wi-Fi multicast lock).
   - Handshake: `COURSE_VERSION`, the game version, `course_hash`. Then the
     host sends the seed and target, sets `Race.course_seed`, and runs a synced
     3-2-1.
   - During the race: each phone sends height, score and flags at about 15 Hz
     over unreliable RPC. Rivals are drawn with the bot's ghost rendering,
     via a `NetRival` that reads positions from the network instead of
     simulating them.
   - The host decides finish order. A disconnected player shows as DNF.
3. **Rules to decide:** local races are probably free, and don't count toward
   unlocks or best times.
4. **Later:** swap the transport for a relay server (self-hosted Nakama on a
   ~$10/month VPS) to race online. The seed, lobby, rivals and results screen
   carry over unchanged.
