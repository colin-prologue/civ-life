# AgDR-009 — Forage is recomputed from terrain and season, not integrated

**Status:** accepted
**Date:** 2026-08-15

## Decision

A tile's forage is a pure function of its terrain and the current season, looked
up from a table and rewritten from scratch on every turn. It is not a stock that
grows and is drawn down. There is no per-tile state between turns: a world on
turn 500 is byte-identical to a world that was generated and advanced to turn
500 by any other route, because the only inputs are the seed and the turn.

Two consequences the next tickets inherit:

**A world's whole state is `(seed, turn)`.** Determinism after a hundred turns
is the same claim as determinism after one, a save is two numbers, and a bug
report is reproducible from a screenshot caption. The no-drift criterion on this
ticket is met by construction rather than by clamping — there is nothing to
accumulate error in.

**Nothing can deplete a tile by eating from it.** A herd standing on a meadow
all winter finds the same forage there on the last turn as on the first. Grazing
pressure, regrowth after being eaten down, and overgrazing are all *not
expressible* in this shape.

## What was rejected

**Forage as a stock with a per-turn regrowth rate toward a seasonal ceiling.**
The conventional ecology model, and the one the herds ticket will probably want:
it makes forage a resource rather than a property, which is what lets a place be
worn out and recover. Rejected here because this ticket's customer needs a
seasonal *signal* to migrate toward, and a stock buys nothing until something
consumes it — while costing per-tile mutable state, a rate constant to tune
blind, and a determinism story that has to be defended over long horizons rather
than being trivially true.

**Per-tile variation from the seed** — a fertility field so two meadows differ.
Rejected as decoration at this point: nothing reads forage yet, so variation
that no system responds to is texture for the eye alone, and the renderer
already distinguishes tiles by terrain.

## Why this is a constraining decision

This is the boundary between "the world has seasons" and "the world has an
ecology". Everything downstream of forage — herd movement, hunting yields,
whether a district can be over-used — is shaped by whether the quantity it reads
has memory. Adding memory later means the value stops being derivable from
`(seed, turn)`, which changes what a save is and retires the cheapest
determinism check the project has.

## What would make this the wrong call

**The herds ticket needing consumption to be interesting.** The moment a herd is
supposed to *reduce* the forage where it stands — and the intent file's
restoring-forces rule suggests it eventually should, since "perturb, run
forward, observe return" needs something to perturb — this shape is done. The
change is mechanical (a per-tile array that is nudged toward the seasonal value
instead of set to it) but it is a one-way door on the state model.

**The seasonal swing reading as a global dimmer.** Forage varies by terrain
*curve*, not by one multiplier, specifically so that where something stands
matters. If in play the four seasons read as the whole map brightening and
dimming together, the per-terrain table is not pulling its weight and the
variation has to come from somewhere else — most likely per-tile state, which is
the same door.

**Scarcity arriving by the back door.** The trough season currently feeds about
a third of what the peak does. That is a swing in what the world offers, not a
statement about whether anything starves — the intent file's abundance rule is a
constraint on the consumer, and the calibration belongs to whichever ticket
first eats. If tuning ever reaches back into this table to make winter *hurt*,
that is the tone erosion `world-growth-tone` exists to catch.
