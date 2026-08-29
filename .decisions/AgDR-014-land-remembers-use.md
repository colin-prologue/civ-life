# AgDR-014 — Land remembers what was done to it, per use, and never permanently

**Status:** accepted
**Ratified:** 2026-08-29 by the owner
**Date:** 2026-08-29
**Parent intent:** `world-growth-tone`
**Amends:** `AgDR-009`, which denied land any memory at all
**Ticket:** #38

## Decision

Every tile carries a **vitality per use**, not one vitality overall. Working a
tile with a given use draws that use's vitality down; not working it raises that
vitality back toward a ceiling the terrain sets. Recovery is unconditional and
requires no intervention.

Three properties are the decision, and each is load-bearing:

**Per use, not per tile.** Ground worn out by cultivation is still good ground
for grazing. This is what makes rotation a real choice rather than a synonym for
resting — and it is borrowed deliberately from Manor Lords, where soil fertility
is tracked per crop rather than per field. One vitality per tile would collapse
"rotate" and "rest" into the same action.

**Depletion moves the answer; it never removes the question.** A worn tile
changes *where* something is done, never whether it can be done at all. This is
the constraint that keeps the mechanic inside `world-growth-tone`'s abundance
baseline, and it is asserted directly: the count of viable tiles within reach of
any agent never reaches zero, while the *identity* of the best reachable tile
changes repeatedly.

**No absorbing states.** Every vitality has a floor above zero and an
unconditional pull back toward baseline. No sequence of ordinary play produces an
irreversible loss of any tile's capacity.

## Why

Three separate observations turned out to be one missing mechanism.

**Watching the game.** With auto-advance in place, the owner's report was that
farms never deplete, fields never go fallow, and the land never changes. All
three are `AgDR-009` behaving exactly as specified.

**Measuring it.** A probe fingerprinting the world at each year's turn over 60
years found it converging to a fixed annual cycle on three of four seeds — one of
them fully static after year 43. Land with no memory means the forage field
repeats exactly every year, so a deterministic world falls into a limit cycle.
The symptom found by watching and the one found by measuring are the same
decision.

**Designing on top of it.** The practices design needs the best choice at a place
to change over time, or adoption converges and the social layer goes inert.

One mechanism answers all three, and it also does something the design wanted
anyway: a practice becoming universal depletes precisely what that practice
depends on, so **influence becomes self-limiting without anyone authoring a
penalty.**

## What was rejected

**One vitality per tile.** Simpler, and it would deliver fallow. It would not
deliver rotation, because with a single number every use is interchangeable and
resting is the only remedy. The per-use split is small — one flat array per use
— and it is the difference between a garden and a cooldown.

**Exogenous variation instead (weather, or terrain-class change).** Terrain
change is #31 and remains available. It was not chosen first because it is more
machinery for the same result, and because it does not give the design its
self-limiting property — a world that varies on its own makes practice choice
matter *less*, not more, since nothing the band does affects it.

**Manor Lords' absorbing states, explicitly.** Its deer stop regrowing once fully
depleted; its berry bushes, destroyed by logging, never return; its stone does
not come back. Those are permanent losses caused by ordinary play, and they are
where its ebb and flow becomes scarcity pressure. Tone rules 1 and 2 forbid both.
The renewal mechanics are taken; the cliff is not.

**Player-performed restoration** — fertiliser, irrigation, deliberate fallowing
as an order. Recovery being unconditional is what makes this the world's
behaviour rather than a management chore, and it is what keeps the pressure on
attention rather than on upkeep.

## What this costs

`AgDR-009`'s central claim does not survive. That record said a tile's forage is
recomputed from terrain and season with no per-tile state between turns, and that
"a world's whole state is `(seed, turn)`". The second half was already false
after #9 added nodes, routes and agents. This makes the first half false too:
there is now a stock per tile per use, and it must be saved (#32) and
fingerprinted.

What survives of `AgDR-009` is worth stating precisely, because it is most of the
reasoning: forage is still **derived rather than integrated** — the terrain and
season curve still produces the number, and vitality scales it rather than
replacing it. The curve remains the ceiling. There is still no unbounded
accumulator, so the no-drift property the record was written for holds by
construction rather than by clamping.

## What would refute this

**If the world still converges.** The whole justification is that land memory
breaks the limit cycle. If the periodicity probe still settles within 200 years
with vitality active, this bought complexity and no variation, and the honest
next move is exogenous variation via #31 rather than tuning these constants.

**If the three clocks cannot be reconciled.** Season length is 6 turns. If the
depletion and recovery constants that make land *feel* like it rotates are also
constants that make the map flicker within a season, or that take longer than a
player will ever watch, then per-tile memory is the wrong timescale for this
effect and it belongs at region scale instead.

**If it reads as decline rather than rotation.** The mechanic is meant to move
activity around the map. If a long run instead reads as everywhere slowly getting
worse, the restoring force is too weak relative to use, and if it cannot be tuned
out then the abundance baseline and per-tile depletion are genuinely in tension —
which would be a finding about `world-growth-tone`, not about this record.
