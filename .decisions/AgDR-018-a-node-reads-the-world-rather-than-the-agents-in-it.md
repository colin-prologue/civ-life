# AgDR-018 — A node reads the world, not the agents in it

**Status:** accepted
**Date:** 2026-09-05
**Parent intent:** `world-growth-tone` (rule 4) · extends `AgDR-013` · declines a
split named in `sim/node.gd`

## Decision

Two things, and they are one decision seen from either end.

**A structure whose output depends on the living world gets it by summing the
per-tile census over a disc.** `WorldMap.forage_demand_within(coord, radius)` is
the only new query, and it returns a float. A gathering node multiplies its
ceiling by a saturating function of that float and deposits the result. It never
touches `world.agents`, never calls `world.herds()`, and has no way to find out
what produced the number it read.

This is `AgDR-013` used from the other side. That record made agents report
quantities so the world would not have to ask them what they are; this one makes
a *consumer* of that census, so the census is a two-way interface rather than a
bookkeeping detail of `move_agent`. Anything later that wants to be gatherable —
a fish shoal, a migrating band, a second species — becomes gatherable by
reporting forage demand, with no edit here.

**`CityNode` stays one class with an enum, and the split its own docstring
predicted is declined.** That docstring named the trigger: "the split will be
obvious because `produce()` will have grown a second branch." It has. The split
was not taken anyway, and the reason is that the branch is not the kind of branch
the docstring was worried about. Both arms are one expression that reads a number
off the world and returns it. No kind carries a field another lacks, no kind
carries state, and `Kind` is doing real work as the tag the renderer and the
tests sort by — a subclass split would delete that tag and immediately rebuild it
as `is Granary` at every call site that currently reads `node.kind`.

## Why

Rule 4 of the intent is the load-bearing one: *"Serendipity comes from coupling,
never from an event table… Prefer making two existing systems read each other
over adding a third."* The sim's only coupling before this was negative — a herd
on a road holds a carrier up. A radius read of an existing census is the smallest
positive coupling available, and it required no new simulation: herds already
migrate on a sensed gradient (`AgDR-010`), the census already knows where they
are (`AgDR-013`), and nodes already produce into a store.

The saturating response — `nearby / (nearby + GATHERING_HALF_AT)` — is part of
the decision and not a tuning constant. Proportional yield would make animals
something to want *concentrated*, which turns a migration into a resource to
farm. Saturating keeps the question the node asks at "is anything here", which is
answered by where the node was put and by nothing the player can do afterwards.

## What was rejected

**Splitting `CityNode` into a class per kind.** The honest reading of the
docstring's own trigger. Rejected for the reason above: the branches share their
whole shape, so the split would buy polymorphism over an expression that does not
vary structurally, and cost the enum every call site depends on. **The split
becomes right when a kind needs *inputs*** — a workshop consuming one good to
emit another — or per-kind fields, because that is the point at which `produce()`
stops being one shape.

**Scanning `world.agents` for herds within the radius.** Simpler to write and it
would have passed every behavioural test. Rejected as exactly the kind-check
`AgDR-013` exists to forbid, wearing a radius as a disguise.

**Depletion — the camp taking heads off the herds it gathers from.** Out of scope
by the ticket, and correctly so: grazing pressure is inexpressible in the forage
shape `AgDR-009` fixed, and adding it here would have been a silent amendment to
an accepted record. Asserted against instead — the same seed run 500 turns with
and without camps comes out identical herd for herd.

**Caching the disc sum per radius.** A handful of nodes read nineteen tiles once
a turn. A cache would have to be invalidated on every agent movement in the
world, which is the more expensive thing by a wide margin.

**Siting the camp where the animals are.** `CityGen` places it beside the granary
in the first free direction, consulting nothing. Deliberate: where the camp ends
up being worth having is the world's answer, and a generator that pre-solved it
would remove the only interesting property the kind has.

## What would make this the wrong call

**If a gathering node needs to know *which* animals.** Different yields per
species, or a node that only takes fish, cannot come from one summed float. The
signal is a second parallel census array added purely so a node can tell two
populations apart — at that point the arrays are a type tag spelled badly and
`AgDR-013`'s own stated failure condition has been reached, from here.

**If the measured placement ratio comes back near 1.0.** The whole claim is that
*where* a camp goes matters more than *what tile* it is on. It is measured, not
asserted — `test_gathering.gd` prints the ratio on both standard seeds and fails
below a stated floor. If that number ever collapses, the answer is not to widen
the radius until it looks better; it is that coupling two systems did not by
itself produce the surprise the design is counting on, and rule 4 needs
revisiting rather than this file.

**If the disc read becomes hot.** It is a linear sum over 19 tiles per node per
turn. A city of hundreds of camps, or a radius grown large, changes that
arithmetic and the rejected cache comes back into play.
