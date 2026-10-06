# LAN race — plan

Racing friends on the same Wi-Fi network, or on one phone's hotspot. No server
and no running cost. Builds on the seeded course (`docs/seeded-course.md`):
every phone climbs the same course from a shared seed, simulates only its own
player, and sends its position to the others, who draw it as a ghost.
Racers never interact, so no real netcode is needed. Lag only moves a
ghost a few pixels.

Status: **built, not yet play-tested on phones.** Tasks 0–8 are all in, MVP and
full version. A headless test with two to eight copies of the game on one PC
(`127.0.0.1`) passes the whole flow: handshake, ready, synced start, ghost
states, course-hash check, finish, closing time, results, rematch flags,
discovery, a mid-race quit (DNF), a late joiner turned away, and the host
leaving.

### What was built

| Piece | Where |
|---|---|
| Session, lobby state, clock sync, start, state relay, finish order, discovery, backgrounding | `scripts/lan_race.gd` (autoload `LanRace`) |
| Lobby screen: host / rooms nearby / join by address, then the room | `scripts/lan_lobby.gd`, `scenes/lan_lobby.tscn` |
| Ghost played back from the network, 100 ms behind, with extrapolation | `scripts/net_rival.gd` (`NetRival extends Rival`) |
| Shared ghost visual for the bot and network rivals | `scripts/rival.gd` |
| Race flow: intro on the shared clock with a 3-2-1 over its end, no pause, waiting panel, placings | `game.gd`, the "LAN race" section |
| Entry point: LAN, a third mode on the menu's mode picker | `main_menu.gd` |
| Intro driven by the race clock, so it ends at GO everywhere | `IntroSequence.begin(..., clock)` |
| Same song on every phone, in step | `LanRace.music_set`, `Audio.play_music(set, from)` |
| Distance that doesn't touch the bot race's saved pick | `Race.shared_target` |
| Android multicast lock for discovery | JetletNotify plugin (`acquireMulticastLock` / `releaseMulticastLock`); the AAR's manifest adds `CHANGE_WIFI_MULTICAST_STATE` |

### Decisions taken

- **Entry point:** its own mode on the menu's picker (CASUAL / RACE / LAN),
  not a button on the race screen. Unlike RACE it is never locked: it costs
  no tickets, and a friend's fresh install should be able to join a room.
- **Room size: 8** (`LanRace.MAX_PLAYERS`). The network isn't the limit: the
  host relays about 15 × n² small packets a second, ~80 KB/s at 8. The limits
  are phone hotspots (many cap at 8–10 devices) and how much the HUD can show.
  For 8 players: the lobby lists players in two columns, the HUD shows at most
  2 off-screen tags per edge (closest first) plus a "+N MORE" line, and the
  results list switches to a smaller font past 4 racers. Checked headless with
  8 instances.
- **Names:** typed in the lobby (`Settings.player_name`, saved). Capitals,
  digits and `- _ .`, at most 12 characters. Leaving it empty shows P1–P8 by
  join order. The host keeps names unique by adding the slot ("ALEX 2").
- **Looks:** each ghost wears its player's own customization: skin shape,
  exact colour, full plasma core, and their trail if they have it on. Only a
  light see-through effect (`Rival.GHOST_ALPHA`) marks it as a ghost. The
  profile is re-sent once the run rolls a shuffled skin.
- **Nothing counts.** No tickets, unlocks, best times or stats. The race is
  logged to Analytics only (`lan_race_start`, `lan_race_end`).
- **Screen width:** every LAN race is laid out on a fixed 720 px band
  (`PlatformSpawner.SHARED_WIDTH`, the width of every portrait phone), centred
  on the screen. Platforms bounce inside it, the player wraps at its edges,
  and anything outside it is dimmed. Ghost positions are sent relative to the
  band. So phones, tablets and a landscape desktop window all race the same
  course (checked: same `course_hash` at 720, 1280 and 2275 px). Casual and
  bot runs still use the full screen.
- **Home button = leave the room.** It's a DNF mid-race. The replay button on
  the results panel goes back to the room for a rematch, with a new seed every
  race.
- **Pause** opens the panel over a race that keeps going. Replay is hidden.
- **Backgrounding mid-race = DNF.** In the lobby, ENet's ~10 s timeout drops a
  phone that has gone quiet.

## Scope

**MVP (build first)**

- 2 players, host + 1 joiner.
- Join by typing the host's IP address, shown on the host's lobby screen.
- One race: synced countdown, race, results, back to menu.
- Distance picked by the host. Race is free, and doesn't count toward unlocks
  or best times.

**Full version (after MVP is play-tested)**

- Up to 8 players (was 4; raised after the MVP).
- Rematch button that keeps the lobby together, with a new seed each time.
- Auto-discovery: rooms appear in a list, so nobody types an IP.
- Handling a host leaving, the app being backgrounded, and joining
  mid-countdown.

**Out of scope here:** online play over the internet. That's a later transport
swap (relay server, e.g. self-hosted Nakama). Everything above the transport
layer in this plan carries over to it.

## Architecture

```
LanRace (autoload, PROCESS_MODE_ALWAYS)
  ├─ ENetMultiplayerPeer   host or client
  ├─ lobby state           peers {id: {name, color, ready}}, seed, target
  ├─ RPCs                  handshake, lobby, countdown, state, finish
  └─ signals               peers_changed, countdown_started(start_at),
                           rival_state(id, ...), race_result(order)

lan_lobby.tscn / lan_lobby.gd       HOST / JOIN / IP entry / player list / READY
NetRival (Node2D)                   one per remote player, drawn like the bot's ghost
game.gd                             race flow branches on LanRace.active
race_hud.gd                         rail + tags for N rivals instead of one bot
```

### How it plugs into the existing race code

- `RaceHud` already only reads `bot.score`, `bot.color`,
  `bot.is_respawning()` and `bot.global_position`. Introduce a small shared
  interface: either a `Rival` base class that `RaceBot` and `NetRival` both
  extend, or loosen `bot: RaceBot` to duck typing. Then turn the single `bot`
  into `rivals: Array`.
- `RaceBot` builds its look from a `PlasmaBlob` (`_visual`) with squash on
  landing. Split out the visual part, so `NetRival` reuses it without the AI.
- `game.gd` (`_start_race` around line 1681 and `_on_intro_finished`): when
  `LanRace.active`, skip spawning a `RaceBot` and create one `NetRival` per
  remote peer. `Race.course_seed` comes from the lobby.
- `Race.active` stays the switch for race rules. `LanRace.active` adds
  "rivals are remote, there are no tickets, and the result is a placing".

## Protocol

All messages go through RPCs on the `LanRace` autoload. Unreliable messages
are sent often and a lost one doesn't matter. Reliable ones must arrive.

| Message | Direction | Mode | Payload |
|---|---|---|---|
| `hello` | joiner → host | reliable | protocol, `COURSE_VERSION`, game version, name, colour, skin shape, trail |
| `welcome` / `reject(reason)` | host → joiner | reliable | peer list / "version mismatch", "race in progress", "full" |
| `lobby` | host → all | reliable | peers + ready flags, target distance, item boxes on/off |
| `set_ready(bool)` | any → host | reliable | |
| `set_profile(name, colour, shape, trail)` | any → host | reliable | on a name edit, and from the run once shuffle has rolled the skin |
| `ping` / `pong` | joiner ↔ host | unreliable | clock offset, see *Clock* |
| `start(seed, target, start_at_ms, song, items)` | host → all | reliable | countdown ends at host clock + offset (see *Clock*); `song` indexes `Audio.MUSIC_SETS`; `items` see lan-items.md |
| `course_hash(hash)` | all → host | reliable | `course_hash(200)`, sent at GO. A mismatch aborts with a message |
| `attack_request(kind, targets)` → `attacked(from, kind)` | attacker → host → targets | reliable | race items, see lan-items.md; the host drops it for anyone finished |
| `attack_report(from, kind, blocked)` → `attack_outcome(...)` | victim → host → all | reliable | for the feed and the attacker's "HIT SAM!" |
| `closing(at_ms)` | host → all | reliable | the first finisher is in; the rest have 30 s |
| `state(t, x, y, score, flags)` | any → all | **unreliable, ~15 Hz** | flags: respawning, streak tier, facing. x is needed too, or the ghost can't be drawn |
| `finished(time)` | any → host | reliable | |
| `result(order)` | host → all | reliable | ids in finishing order + times, DNF last |

**Clock.** Each joiner measures its offset from the host's clock with a
couple of ping round-trips during the lobby, and each device starts its
countdown from `start_at` converted to local time. That's accurate to within
tens of milliseconds, which is plenty.

**Smoothing.** A `NetRival` draws about 100 ms in the past, blending between
the last two state messages. If a message is late, it keeps moving on the last
known velocity for up to 250 ms, then holds still.

## Race rules for LAN

- Same target distances as bot races. Same fall rule: a fall costs
  `Race.RESPAWN_PENALTY` seconds, then the player drops back in.
- Finish = reaching the target score. The host orders players by finish time.
  The race ends when everyone has finished, or 30 s after the first finisher,
  when the rest are DNF.
- Quitting or disconnecting = DNF. The others keep racing.
- No tickets, no unlock progress, no best times. It's a social mode.
- Intro skipped: everyone starts from the same hand-off state, so the seeded
  course lines up (seeded-course gap 3).

## Work breakdown & estimate

| # | Task | Size | Depends on |
|---|---|---|---|
| 0 | Close seeded-course gaps 2 (zone boundary from fixed origin) and 3 (synced start, skip intro in races), and add `spawner.course_hash(n)` | S | — |
| 1 | `LanRace` autoload: host/join, handshake, lobby state, clock offset | M (~300–400 lines) | 0 |
| 2 | `lan_lobby` scene: HOST / JOIN, IP entry, show own IP, player list, READY, countdown | M (~300 lines) | 1 |
| 3 | Split `RaceBot` visual → shared ghost; `NetRival` with interpolation | S–M | — |
| 4 | `RaceHud` → N rivals (rail dots + edge tags, labelled by player name instead of "AI") | S | 3 |
| 5 | `game.gd` LAN branch: start on countdown, spawn NetRivals, send state, report finish, placing results screen, no tickets | M | 1, 3, 4 |
| 6 | Menu entry: a third mode on the menu's mode picker ("LAN") or a button on the race screen | S | 2 |
| 7 | Edge cases: backgrounding (`NOTIFICATION_APPLICATION_PAUSED` → DNF or short grace), host leaves, back button, join during countdown | M | 5 |
| 8 | *Full version:* rematch, 8 players, UDP-broadcast discovery (+ Android multicast lock in `addons/jetlet_notify`-style plugin) | M | MVP |

**Total:** roughly 1,200–1,800 lines. MVP = tasks 0–6, about 60% of it. Around
1–2 weeks of calendar time at a relaxed pace, most of it testing and edge
cases.

## Testing

- **On the PC first.** Debug → Customize Run Instances → 2–4 instances. They
  connect over `127.0.0.1` exactly as over LAN, so each iteration takes
  minutes, not an APK export.
- **Save safety:** headless or multi-instance runs share the real user data
  dir. Back it up first, and keep LAN races from writing to Stats or race.cfg
  at all.
- **On phones last:** two phones on home Wi-Fi, then one phone as a hotspot.
  Check backgrounding mid-race, screen lock, and a guest/café network (expect
  "can't connect" there, and check that the message says so).
- **Course check:** log `course_hash` on every device at race start. Any
  mismatch is a bug in seeded-course determinism.

## Risks

- **Race flow, not networking,** is the big risk: countdowns, disconnects and
  pausing are what make it feel broken or solid. Budget for task 7.
- **Networks that block devices from seeing each other** (café, office, some
  school Wi-Fi). Can't be fixed from the app, so show a clear message
  suggesting a hotspot.
- **Android broadcast filtering** — discovery only. The MVP avoids it with IP
  entry.
- **Screen width** (seeded-course gap 1): a phone vs a tablet sees a scaled
  layout. For the MVP, warn or refuse when the width differs, and decide on a
  fixed course width later.
- **Version skew:** two phones on different app builds. The handshake's
  `COURSE_VERSION` + game-version check turns it into a clear message instead
  of a silently different course.

## Open decisions

- Entry point and names: decided (see *Decisions taken*).
- Whether LAN wins should ever count toward anything (an achievement,
  statistics screen entries). Currently nothing does.
