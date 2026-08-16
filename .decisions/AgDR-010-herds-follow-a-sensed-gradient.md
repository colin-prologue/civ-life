# AgDR-010 — Herds follow a gradient they can sense, not one they can touch

**Status:** accepted
**Date:** 2026-08-15

## Decision

A herd scores every land tile within four hexes by the ration it would get
standing there, discounts each by the walk, picks the best, and takes **one tile
per turn** toward it. It keeps that destination until it arrives or the season
turns.

The ticket assumed the narrower version: choose among the current tile and its
six neighbours. That was implemented first and measured. It does not migrate.

| choice made among | mean distance from start after one year |
|---|---|
| the current tile and its six neighbours | **0.21 tiles** (seed 20260815), 0.14 (seed 987654321) |
| every land tile within four | **1.14 tiles**, 2.00 |

The reason is visible once stated: forage is a per-terrain curve, so a herd in
the interior of a meadow sees six tiles worth exactly what it is standing on,
every turn, all winter — and correctly does not move. Only herds that happened to
be placed on a terrain boundary ever migrated. The one-step version is not a
weaker migration; it is migration that only happens by accident of placement.

Sensing range is on the species (`sense_range`), separate from `move_range`,
which stays at 1. The range decides direction; it does not make anything faster.

## What was rejected

**Widening the step instead of the senses** — letting a herd cross several tiles
a turn. Cheaper to implement and it would move the same number in the table, but
it buys the distance by making animals teleport, and the acceptance criterion
this exists to satisfy is about movement reading as *following something*.

**Smoothing the forage field** — score a neighbour by its own forage plus a
share of its neighbours'. Half the cost of the disc scan, but it only extends
the gradient by one ring: the herd in the middle of the meadow still sees a flat
world, just a slightly blurrier one. It fixes the symptom at the boundary and
not the case that produced the measurement.

**Diffusing a scent field across the whole map each turn.** The general version,
and the one that would make reach a tuning knob rather than a loop bound.
Rejected on cost: it is per-tile work per turn over 1200 tiles, against per-herd
work over 61, and it would have taken the turn loop past the budget that makes
thousand-turn tests writable.

**Re-planning every turn.** Measured at seven times the turn-loop cost of
planning on arrival and on season change, for behaviour that reads as milling
about rather than as going somewhere.

## Why this is a constraining decision

Citizens are the next thing to extend `Agent`, and a citizen walking to a
granary wants a route, not a gradient. This decision says the movement layer's
first tool is **local scoring with a sensing radius**, not pathfinding — so
whoever adds routes is adding a second mechanism beside this one rather than
finding one already there. That is deliberate at this stance (`AgDR-002` warns
that routing has to be boringly reliable, which a gradient is not), but it is a
fork in the road and it is being taken here without the router's requirements in
view.

It also puts a knob on the species that behaviour is sensitive to in a way the
others are not. Growth and consumption move numbers; sensing range decides
whether anything happens at all.

## What would make this the wrong call

**Herds converging.** Every herd sensing the same four-tile neighbourhood of the
same seasonal optimum could pile them onto the same wood every winter, which
would read as a flocking bug rather than as migration. The ration score charges
for crowding, which should push them apart, and observed play does not show it —
but the map is currently 14 herds on 700-odd land tiles, and that is thin
evidence for a rule about competition.

**Four tiles being the number that makes it work.** If migration turns out to be
sensitive to the exact radius — three does nothing, five crosses the map — then
what is being tuned is not an animal's senses but a threshold against the size
of the terrain features the generator happens to make, and the coupling belongs
somewhere it can be seen.

**A reviewer watching it and reading it as drift.** The table above says herds
end the year further from home than they started. It does not say the movement
*looks* like following food, and no measurement in this repository can. That is
AC11 on the ticket, and it is unverified by the agent that wrote this.
