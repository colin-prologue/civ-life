# AgDR-015 — The turn report is derived and bounded, not an event log

**Status:** accepted
**Date:** 2026-09-04
**Ticket:** #28

## Decision

The world produces, every turn, a **turn report**: an ordered list of changes
that crossed a stated threshold, held on `WorldMap.report` and replaced whole by
the next `advance_turn()`.

Three properties, and each one is a decision rather than an implementation
detail:

1. **It is derived.** The report is built by comparing a snapshot taken before
   the turn against the world after it. Nothing in the report is written back to
   the world, nothing accumulates across turns, and the simulation holds no
   state that exists to serve it. The one field added anywhere was making
   `Citizen._held_up` readable — a counter the citizen already kept.

2. **It is bounded, at six entries, and it says when it truncated.** When more
   changes cross a bar than fit, the report sorts by kind priority then by
   magnitude, keeps five, and spends its last slot saying how many it dropped.

3. **Notability is a stated threshold per kind**, not a judgement: a herd
   changing the kind of terrain it stands on, a herd or granary crossing a
   multiple of a step, a carrier's first held-up turn, a season turning. A turn
   that crossed nothing reports nothing.

The two mark-crossing kinds report **the bar that was crossed**, not the step
that crossed it — see "what would make this wrong" below for why that was not
the first answer.

## What was rejected

**An event log the simulation appends to.** Systems would push events as they
happened — the granary announcing a delivery, the herd announcing a move — into
a list the renderer drains. This is the ordinary way and it is cheaper per event
than diffing the world.

It was rejected because it makes the world hold state whose only purpose is
being read. That breaks the property `AgDR-001` rests on in a way that is hard
to see coming: an append-only list is a second source of truth about what
happened, it can disagree with the world, and once anything in `sim/` emits into
it, every later system has to remember to. Diffing cannot forget, and a report
that is thrown away costs the world nothing.

It also quietly answers a question this project has not earned yet. An event log
is the data structure for a history panel and a scrollback, which are explicit
non-goals — the shape of the storage would have argued for the feature.

**A per-turn report with no ceiling.** Rejected against `world-growth-tone` rule
6: fewer and chunkier entries beat a complete log. An unbounded report is the
notification queue the intent names as the failure mode, and the bound is what
forces a drop rule to be stated and tested rather than discovered later as
silent truncation.

## Why this is a constraining decision

It decides where "what happened" lives. Every later system that wants to be
noticeable states a threshold and is compared, rather than emitting. If the
report becomes a log, that inverts: systems start pushing, `sim/` starts holding
presentation state, and the snapshot machinery becomes dead weight around it.

It also fixes the report's shape at three fields — where, what kind, how much.
A change needing a fourth is treated as evidence the world is missing a
variable, not as a reason to widen the record.

## What would make this the wrong call

**If diffing cannot see a change that matters.** Some events are invisible to a
before/after comparison: anything that happens and is undone within one turn, or
anything whose significance is in the path rather than the endpoints. A herd
that crossed a river and came back looks identical to one that never moved. If
those turn out to be the interesting events, the world has to say so as it
happens and the log wins.

**If the bound turns out to be where the information was.** "10 more changes not
shown" on turn 4 of the reference seed is honest, but it is not an instrument. If
what got dropped is repeatedly the thing the player needed, the answer is a
better notion of significance, not a taller list — and if no such notion exists,
that is evidence attention needs a spatial instrument rather than a textual one.

**The near miss, recorded because it was not obvious.** The magnitude field first
held the *difference* across the turn. On a threshold that meant a granary
drifting past a mark reported "took in 0 grain", and five herds crossing five
different marks all reported "grew by 3 head" — five identical lines for five
unrelated events. A threshold report has to name the threshold; the delta is the
uninteresting half. If a later kind of change finds the same field wants to be a
delta again, this shape is under strain.
