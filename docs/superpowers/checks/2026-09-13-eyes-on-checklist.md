# What only a person can answer — a play-session checklist

**Date:** 2026-09-13
**Parent intent:** `world-growth-tone`

Every ticket in this project carries acceptance criteria an agent can assert, and
a few it cannot. Those few have been accumulating: they are the judgements about
whether the thing is *good*, and no test in the suite is evidence either way.
This gathers them into one sitting.

Each question below states what a "no" means, because the answer is only useful
if it is allowed to be no. Several of these are refutation clauses of records
already ratified — a no is a finding about the design, and in no case is it a
licence to add scarcity, remove abundance, or tune a constant until the feeling
changes.

## Before you start: one thing cannot be judged yet

**Land wear is invisible in the build.** `AgDR-014` gave every tile a vitality
per use, the whole land-vitality arc (#38, #41, #42) is merged, and the gates say
the world no longer settles — but the only overlay is `forage`, which draws
`forage_data()`: the raw terrain-and-season curve, *unscaled by wear*. Nothing on
screen shows how worn a tile is. `hex_map_view.gd:233` mentions the vitality
overlay only as a comment describing how one would be added.

So **question C1 below cannot be answered honestly today**, and the practices
spec predicted exactly this, calling the overlay "a dependency in practice even
though it is out of scope here — per-practice vitality is invisible without an
overlay, and a system nobody can see is a system nobody can judge."

The overlay registry is data, and the comment already sketches the entry, so this
is a small ticket rather than a feature: **#65**. Worth landing before the
long-run questions are attempted.

## Running it

Open the project in Godot 4 and press play, or from the repo root:

```
godot
```

The main scene is `game/main.tscn`. On screen:

| What | Where |
|---|---|
| The map, with a ring and a label on every tile this turn's report named | centre |
| Totals, and what changed this turn | status line, top |
| Flows over the last several turns | panel, lower right |
| The forage overlay | press `O` to cycle it on and off |

Controls: `click` select a tile · `F` farm · `G` granary · `R` route · `Esc`
clear · `space` one turn · `P` play/pause · `[` and `]` slower/faster · `O`
overlay.

A year is 24 turns and a season is 6, so at the fastest speed a year goes by in a
second or two. Most of these questions want a few minutes of running, not a few
turns.

---

## A. Sit and watch, no input

Put it on play at a middling speed and watch for five minutes without touching
anything.

**A1 — Does a minute of watching answer "what changed, and why?"** (#47 AC12)
A no means the attention marks and the flows panel are decorative: the
information is on screen but not answering the question the ticket was for.

**A2 — Does the map read as a place, or as a dashboard?** (#47 AC13)
The flows panel is the part most likely to be over-reach — five rows in a corner,
and the most instrument-like thing in the build. The overlay and the on-map marks
are the parts that put information *into* the world instead of beside it. A no
here points at the panel first.

**A3 — Is a herd wandering into a camp's range a moment you notice?** (#49 AC11)
Something you would mention to someone, or a number quietly changing. The
measured data is not flattering to the eventful reading: a generated camp's
transitions take the better part of a decade. A no means the coupling is real but
too slow to be a story, and the fix is upstream in how far herds travel rather
than in the camp's constants.

**A4 — the root question: is watching a world grow compelling at all?**
This is `world-growth-tone`'s own refutation, and `AgDR-003` rests on it too. A
no is the most valuable answer in this document and the most expensive: it says
the observational loop needs something the simulation does not currently have,
and that is worth knowing before the social layer is built on top of it.

## B. Build something

Select a tile, place a farm (`F`), place a granary (`G`) elsewhere, draw a route
between them (`R`), then watch what happens.

**B1 — Is watching it interesting enough that you want to place another?**
(#50 AC11) This is the refutation test for the placement verb.

**A confound to separate from the answer**, recorded in #50's PR: at the current
fit a farm is roughly a 6-pixel square on a 1280×720 map. If the answer is no,
ask whether what failed was the tension model or the legibility of a whole-map 2D
view. They are different findings, and only the first should stop the faction
layer.

**B2 — Does a herd standing on your road read as interference you care about?**
A herd in the way delays a carrier and can never sever the route (`MAX_HELD_UP`
is one season). The obstruction share measures 53% against a 60% ceiling, so the
mechanism is definitely firing. The question is whether you notice it happening
without being told.

## C. The long run

**C1 — Does a long run read as land *rotating* — places going quiet and coming
back — rather than as slow decline, or as flicker?** (#42 AC10, and `AgDR-014`'s
third refutation clause)

**Blocked until the vitality overlay exists (#65).** The number to set beside your
judgement when it does: the periodicity gate finds 200 distinct year-states out
of 200 on every seed, and every herd's best reachable ground changed in 34–39 of
40 years.

A no splits two ways, and they have different consequences:
- *It reads as everywhere slowly getting worse.* The restoring force is too weak
  against use. If that cannot be tuned out, abundance and per-tile depletion are
  genuinely in tension — a finding about `world-growth-tone`, not about
  `AgDR-014`.
- *It reads as flicker.* Wear and recovery are moving faster than a season, so
  per-tile memory is the wrong timescale and the effect belongs at region scale.

**C2 — Are the three clocks in proportion?** (`AgDR-014` refutation 2) Season
length is 6 turns, the vitality half-life is 12. Land that wears faster than a
season makes the map twitch; slower than a working lifetime and nobody feels it.
Also blocked on the overlay.

## D. Not buildable yet — record these for when they are

Listed so the questions exist before the work does, and so nobody has to invent
the acceptance test after the fact.

**D1 — Does the city growing read as a place filling up, or a counter
incrementing?** (#29 AC11, in flight) Tone rule 6: if the interesting question
becomes totalling a column, the granularity is wrong.

**D2 — Can you tell two herd species apart by watching, and do you find yourself
wondering which one is coming?** (#53 AC9, drafting) If telling them apart needs
a stat panel, that ticket has failed.

**D3 — Does a household taking up a neighbour's way of living read as a moment?**
(#61 AC15) This is `AgDR-020`'s stated refutation: if adoption reads as attrition
arithmetic, the design needs an actual beat — a visible switch — rather than a
threshold quietly being crossed.

**D4 — Does a long run read as ways of living moving around the map**, rather
than a slow slide into one practice or a flicker between them? (#62 AC10)

**D5 — Is your lineage growing legible without a number?** (`AgDR-020`) Standing
is derived rather than stored — it *is* how many households follow your practice.
If that cannot be felt without a readout quoting it, the claim is technically
true and experientially empty.

---

## Recording the answers

Per question: **yes / no / could not tell**, one sentence of what you actually
saw, and — for a no — which of the two branches above it fell into. "Could not
tell" is a real answer and usually means something is not visible enough yet,
which is a different ticket from the one being questioned.

These belong back on the tickets they came from, so the acceptance criterion gets
closed by evidence rather than by silence.
