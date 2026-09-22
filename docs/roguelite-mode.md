# Roguelite mode — design & implementation plan

Working document for the `rogue-lite-mode` branch. Perk and hazard tables are
authored separately and dropped into the catalogs described in §3/§5.

Scope decisions already made:

- **Ghost / pace rival** — its own mode, planned separately. Not in this plan.
- **Daily missions** (`missions.gd`, `ENABLED := false`) — staying off for now.
- **Cloud leaderboards / async PvP** — not doing. No backend, and the sign-in
  and anti-cheat cost is a project of its own rather than a feature.
- **Permanent stat upgrades across runs** — deliberately rejected. Score is
  height climbed; upgradable base stats would make a run-5 and a run-500 score
  measure different games, and would turn the escape milestones from an
  achievement into a waiting period. Roguelite progression stays run-scoped.

## Already shipped (not part of this plan)

- **`BestLine`** (`scripts/best_line.gd`) — the previous best drawn across the
  world at the height it was reached. World y is `_score_origin_y -
  high_score * 10`, which is exact rather than approximate: score is
  `max_height / 10` from that same origin and the camera tracks the player's
  highest point, so the frame the character crosses the line is the frame the
  score ties the record. Becomes per-mode automatically once `_load_high_score`
  is mode-aware (§6).
- **One-touch intro skip** — `SKIP` fades in on the intro's first frame and a
  press anywhere skips. The button's 0.2s fade-in doubles as the grace period
  against a stray press arriving with the scene.

---

## 0. Gate pacing — why it is not "every 10k"

Measured from a real 76-run save (`user://stats.cfg`):

| | |
|---|---|
| high score | 11,594 |
| best streak | 24 |
| median score | **66** |
| p75 / p90 | 2,045 / 5,255 |
| runs reaching 10,000 | **1 of 76** |
| median duration | 22.6s |
| median pace | 31 score/s |

At one perk per 10,000 score, a developer's own save yields **one extra perk in
76 runs**, and a median run yields none. The draft is the mode, so the gates
have to be front-loaded and escalating instead.

That save is weighted with short test runs, so the median is not a real player
distribution — but even read generously, 10,000 is far too late for gate 1.

Proposed ladder, alternating so every gate is exactly one decision:

| Gate | Score | Type |
|---|---|---|
| 0 | 0 | **PERK** — the opening 1-of-3 |
| 1 | 600 | HAZARD |
| 2 | 1,400 | PERK |
| 3 | 2,400 | HAZARD |
| 4 | 3,600 | PERK |
| 5 | 5,000 | HAZARD |
| 6 | 6,600 | PERK |
| 7 | 8,400 | HAZARD |
| 8 | 10,400 | PERK |
| 9+ | +2,400, +2,800, +3,200 … | alternating |

Against the same data: median run → 1 perk; p75 → 2 perks + 1 hazard;
p90 → 3 + 3; best run → 5 + 4. Kept as one editable table for retuning.

## 1. Mode plumbing

Mode has to survive both the menu → `main.tscn` scene change and
`Transition.reload_scene()`, so it lives in an autoload.

- **New** `scripts/game_mode.gd` → autoload `GameMode`:
  `enum Mode { CLASSIC, ROGUE }`, `var mode`, `is_rogue()`. A restart keeps the
  mode for free, since autoloads survive a reload.
- `main_menu.gd:_play()` gains a mode chip above `PlayZone` that cycles the two
  modes. Costs a `main_menu.tscn` edit and one icon.

## 2. Perks as data

Target: the perk table needs no new code. **New** `scripts/perk_catalog.gd`,
a static const array of entries shaped like:

```gdscript
{
  "id": "wide_stance",
  "name": "WIDE STANCE",
  "desc": "Platforms sit closer together.",
  "icon": "res://assets/icons/....svg",
  "tags": ["spacing"],   # a draft never offers two perks from one family
  "stacks": 2,           # max copies owned
  "weight": 3,           # draft rarity
  "min_gate": 0,         # power perks barred from the opening draft
  "mods": { "min_gap": {"mult": 0.85}, "max_gap": {"mult": 0.85} },
}
```

Anything that is not a number carries an optional `"hook": "<id>"`, resolved by
a `match` in **new** `scripts/perk_hooks.gd`. Hooks stay rare — each one is
hand-written code.

**New** `scripts/run_mods.gd`, a node in `main.tscn` beside `ZoneDirector`,
owns the loadout and **recomputes every stat from its base value on each new
perk** — never incrementally. Incremental application is how multipliers get
double-applied across a mid-run stack.

Draft rules: 3 distinct options, skip anything at its `stacks` limit, skip
families already owned, weight-biased random, `min_gate` respected.

Optional: one rewarded-ad reroll per run. `Ads.show_rewarded` already does
everything needed for it.

## 3. Stat registry

| Stat key | Owner | Mid-run write |
|---|---|---|
| `jump_velocity`, `boost_jump_velocity`, `gravity` | Player | safe (negative — "higher jump" multiplies magnitude) |
| `move_speed` | Player | ⚠️ must go through `_base_move_speed` |
| `streak_jump_step`, `streak_jump_cap`, `streak_fall_step` | Player | safe (`streak_fall_step` compounds — small changes are large) |
| `solar_wind_duration` / `_speed_mult` / `_launch_mult` | Player | safe |
| `min_gap`, `max_gap`, `*_cap`, `platform_width*` | PlatformSpawner | safe (read per spawn) |
| `SOLAR_WIND_STREAK_STEP` | game.gd | ⚠️ const → var |
| `SQUISH_BOOST`, `PHANTOM_*` | Platform | ⚠️ const → var |
| extra revive | game.gd `_revive_used` | safe |

Two prerequisite refactors:

1. `Player` needs `set_base_move_speed(v)`, writing `_base_move_speed` and —
   only when no Solar Wind tween is live — `move_speed` too. Writing
   `move_speed` directly is stomped mid-burst, so the first speed perk would
   otherwise break Solar Wind.
2. The consts above become vars if any perk targets them.

**`landing_window_ms` and the mash rules are off limits to perks.** That window
is the one number the whole game is about; a "+50ms" perk is an auto-pick that
flattens the skill curve and makes rogue scores incomparable. A timing-help
perk should give *feedback* (a pre-landing tick cue), not tolerance.

## 4. Hazards

**New** `scripts/hazard_catalog.gd`, same entry shape, two kinds:

- **Attribute hazards** — add a bit to a permanent forced mask, e.g.
  `{"attrs": Platform.Attr.GLASS}`. Composes with the existing bitmask for free.
- **Stat hazards** — negative mods on the §3 keys: wider gaps, narrower
  platforms, faster phantom blink, higher gravity.

**A chosen hazard has to buy something**, or the rational pick is always the
mildest one and the choice is fake. Doing both:

- a "heat" counter that unlocks stronger perk tiers in later drafts, and
- a visible run-score multiplier.

The multiplier breaks `score == height`. That is acceptable **only** because
rogue mode keeps its own high score record (§6), so the invariant has to hold
within a mode rather than globally.

## 5. New platform attributes

`Platform.Attr` uses 5 of 32 bits. Each new attribute costs three edits: the
enum bit, behaviour in `platform.gd` (`_ready` flag plus
`_process` / `_physics_process` / `on_landed`), and a visual in
`platform_decor.gd`.

⚠️ `platform.gd:_ready()` ends with `set_physics_process(_move_h or _move_v)`
and `set_process(_squishy or _invisible)`. A new animated attribute missing
from those guards silently never animates.

Candidates that suit the timing core: `CRUMBLE` (breaks on the second
landing), `SLIPPERY` (adds horizontal velocity on landing), `SPIKED` (a
mistimed landing kills rather than resetting the streak), `DECOY` (never grants
a boost).

## 6. Separate records — required

- `game.gd:SAVE_PATH` gains a per-mode key (`high_score_rogue`). Classic keeps
  `high_score`, so existing saves are untouched. `BestLine` then shows the
  right record per mode with no further work.
- `Stats.record_run()` gains a `mode` field in the run dict; absent means
  classic. `statistics.gd` / `line_graph.gd` must filter on it, or the two
  modes' histories blend into nonsense.
- **Open decision:** should rogue mode grant `Stats.escaped` /
  `true_ending`? Those gate the FLAME and SPARKLE skins through `Unlocks`.
  Recommendation: **no** — the escape ladder is classic mode's story and its
  own difficulty curve. Rogue earns its own unlocks later if wanted.

## 7. Director and gate timing

**New** `scripts/rogue_director.gd` exposes the surface `PlatformSpawner` and
`game.gd` already use — `attrs_for_score(score)`, `stage_for_score(score)`,
plus a `gate_reached` signal — so nothing downstream changes. Both directors
sit in `main.tscn` and `game.gd` picks one in `_ready()`; `spawner.zones` is
already an injected reference, which makes this nearly free.

**Gates open on a landing, not on a score tick.** `zones.update(score)` runs
inside the score-changed block in `_process`, and pausing there freezes the
character mid-flight at an arbitrary point in the arc. Crossing a threshold
*arms* the gate; `_on_player_landed` opens the panel — the same deferred-pause
pattern `_tutorial_on_landed` already uses.

Exception: gate 0 fires after the intro but **before `spawner.begin()`**, since
spacing perks must be live before the first platform is placed.

## 8. Draft UI

New `UI/DraftPanel` in `main.tscn`: Dim, title, 3 cards, optional reroll.
Reuses `UiPlate.action/quiet`, `IconPop.attach`, a `TWEEN_PAUSE_PROCESS`
pop-in and `_set_hud_visible(false)`.

⚠️ A new `_draft_open` flag has to join **four** existing guard chains that all
currently read `if is_game_over or _milestone_open or _revive_open or
_tutorial_open`: `_unhandled_input`, `_on_pause_pressed`, `_update_tap_cue`,
`_open_boost_tutorial`. Missing one puts the pause menu on top of a draft.

Also needed: a HUD loadout row (perk icons under the score) and the full list
on the pause panel. Build decisions are unmakeable if the build is invisible.

## 9. Phasing

1. **Skeleton, no content** — `GameMode`, menu toggle, `RogueDirector` with two
   gates, `RunMods` with three placeholder perks and two placeholder hazards,
   `DraftPanel`. Goal is the loop running end to end.
2. **Stat registry** plus the `move_speed` and const → var refactors.
3. **The real perk and hazard tables**, dropped in as data.
4. Separate records, HUD loadout row, pause loadout, rogue best on the game
   over panel.
5. New `Platform.Attr` types and their decor visuals.
6. Tuning against real mode-tagged runs.

## 10. Table format for authoring

Per perk: id, display name, one-line description, the stat keys it moves and by
how much (`mult` or `add`), stack limit, family tag, and whether it is barred
from the opening draft.

Per hazard: the same, plus whether it is a new `Platform.Attr` behaviour or a
stat penalty.

Anything that is not a number on that table gets marked and planned as a hook.
