# AgDR-012 — Agents report quantities; nothing asks them what they are

**Status:** accepted
**Date:** 2026-08-23
**Parent intent:** `world-growth-tone` · confirms `AgDR-002`

## Decision

The per-tile census `WorldMap` keeps is fed by a **method on the base agent that
returns a number** — `Agent.forage_demand()` — rather than by the world checking
what kind of agent it is holding. A herd returns its population. A citizen
returns zero. `add_agent` and `move_agent` add up whatever they are given.

Interaction between the two halves of the game is expressed the same way: a
citizen is held up when the tile it is standing on has non-zero forage demand. It
does not know herds exist.

Kind-checks survive in exactly two places, both queries asked from outside the
turn loop (`WorldMap.herds()`, `WorldMap.citizens()`), used by the renderer and
by tests. No behaviour branches on them.

## Why

`AgDR-002` named its own refutation: "if citizen logic and wildlife logic share a
class but no actual behaviour — every method branching on which kind it is — then
the unification is nominal." Before this ticket the base type was clean but
`WorldMap` was not: `add_agent` and `move_agent` both said `if agent is Herd`.
Adding a second agent kind would have added a second branch to each, and the
third would have added a third.

A reported quantity has none of that shape. A future band or caravan that needs
to be noticed on a tile adds a number, not a branch — and everything that already
reads the census sees it without being told.

## What was rejected

**Enter/exit hooks on the base agent** (`on_entered_tile`, `on_leaving_tile`).
More general, and it would let an agent maintain any per-tile bookkeeping it
liked. Rejected as three virtual methods where one suffices, and because a hook
that mutates the world's private cache is a wider hole than a getter.

**Leaving the kind-checks in `WorldMap`.** Honest against the letter of the
acceptance criterion, which only asks about the base type. Rejected because it
moves the smell one file over and calls the problem solved.

## What would make this the wrong call

**If agents start needing to distinguish each other by kind to behave
correctly.** A citizen that must treat a bandit differently from a cow cannot get
there through one float. The signal is a second, third and fourth quantity being
added to `Agent` purely so somebody can tell them apart — at which point the
quantities are a type tag spelled badly, and an explicit tag with a small closed
set of interaction rules would be the smaller thing.

**If the census stops being additive.** This works because forage demand sums.
Something that needs "is anyone at all standing here" needs a different count,
and adding a second parallel array per question does not scale.

## Note on a constraint found while building this

Deliveries lag the harvest by roughly the time it takes to walk the road, so a
long route puts the granary's year out of phase with the world's — at four steps
the delivery peak inverts against the forage peak entirely. `CityGen.ROUTE_LENGTH`
is short for that reason and it is measured in `test_the_seasons_reach_the_granary`.
Not a decision record of its own yet, but the thing to know before roads become
something the player draws.
