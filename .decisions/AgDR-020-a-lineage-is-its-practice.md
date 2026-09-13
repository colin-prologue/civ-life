# AgDR-020 — A lineage is its practice, standing is derived, and people have bodies without interiors

**Status:** accepted
**Ratified:** 2026-09-13 by the owner
**Date:** 2026-09-13
**Parent intent:** `world-growth-tone`
**Amends:** `AgDR-003`, which anticipated standing as a quantity of its own
**Spec:** `docs/superpowers/specs/2026-08-29-early-game-practices-design.md`
**Tickets:** #60, #61, #62

> Number taken from `main` at `cf9b24c`, where `AgDR-019` is the highest. Parallel
> branches can collide on this (civ-life #52); if another record claims 020 first,
> this one renumbers and nothing else changes.

## Decision

Three statements, each load-bearing.

**A lineage is its practice.** Taking up a practice and belonging to that lineage
are the same event. There is no membership roster held apart from who works that
way, and no way to express belonging to one lineage while practising another.

**Standing is derived, never stored.** A lineage's standing *is* the number of
households following its practice, which is the same number as its size. There is
no influence stat, no currency, and nothing to spend. Your practice spreading and
your family growing are one event seen from two sides.

**People have bodies, never interiors.** A person is an `Agent` with a position
and a household. No name, mood, trait, skill, relationship or preference. The
household — five to twelve of them in slice 1 — is the smallest unit that
decides, and it carries only its practice, its members, and what it got last
interval. Apparent individuality is a *rendering* concern, already specced as
`procedural-art` S5: a person can have a gait and a load with `sim/` knowing
neither.

A consequence worth stating so it is not rediscovered as a bug: **"band" is a
word, not an object.** Slice 1 has households and nothing containing them, the
way "the herds" is simply all herds. A band becomes a real object only when there
are two of them to tell apart.

## Why

**It removes a component rather than adding one.** The project's own README
already calls the player "a clan, a house, a lineage of practice". Taken
literally, practice and lineage stop being two things that need reconciling, and
standing stops being a second quantity that has to be kept consistent with
population. One number, read two ways, with no synchronisation to get wrong.

**The reference material says influence is not a currency.** `AgDR-004` names
*Children of Time* as the source of Understandings, and re-reading the series for
where its conflicts arise is what produced this: Understandings are held by
lineages and confer status, and Fabian — who may not lead, may not hold a peer
house, and is not protected by law — changes the civilization anyway by being
demonstrably useful and by getting an Understanding to spread. Influence there is
the spread of a way of doing things. A standing stat would model the residue of
that argument rather than the argument.

**Interiority converts an observational game into triage.** The moment a person
has a mood, the loop becomes "someone is unhappy, go fix them". A colonist having
a breakdown will always outrank a forest quietly reaching density, and the forest
is what this project is about. Manor Lords reached the same granularity from the
other direction — a family is three people assigned as one, and that is its whole
answer to micromanagement.

**Derived standing cannot be farmed, and it is already self-limiting.** It moves
only when households actually change practice, and `AgDR-014` means a practice
becoming universal wears out precisely the ground that practice depends on. The
ceiling on success exists without anyone authoring a penalty.

## What this amends in `AgDR-003`

`AgDR-003` describes the polity scale: influence only, "persuade, invest, trade
knowledge for standing". That presumes standing is a quantity you accumulate and
spend. At band scale there is no polity, no vote and nothing to spend on.

This record does not retract that. It says standing at era zero is a **derived
population share**, and that any later spendable standing has to be built *on
top* of this — a conversion from share into something spendable, stated in its
own record — rather than beside it as a parallel stat. `AgDR-003` is already
marked provisional and remains as written for the civilization era.

## What was rejected

**A separate standing or influence stat.** Two numbers that must agree, an
obvious thing to optimise, and a currency the player totals — tone rule 6. It
also makes "my practice spread" and "my standing rose" two events that can
disagree, which is a bug surface with no compensating expressiveness.

**Individuals with traits, moods or skills.** The management loop above, plus
succession bookkeeping that `AgDR-003` already refuses. Character is available
more cheaply: a household's adoption threshold is derived from a stable hash, so
"the Antlers are stubborn" is a true, observable statement about a household with
no personality field.

**Membership as a roster separate from practice.** It would allow a household to
change practice without changing lineage, which sounds richer and costs a great
deal: defection, loyalty and betrayal arcs the project cannot animate and does
not want, and a second structure to keep consistent with the first.

**A global ranking of practices.** Adoption compares against households a
household was *near* during the interval (FR-6). A leaderboard would make
knowledge non-geographic and remove the reason position matters at all.

## What this costs

- **No secret adherents, no factions inside a lineage, no defection in name
  only.** If that turns out to be the interesting story, this record is what
  blocks it, and it should be amended rather than worked around.
- **Standing can be had, not spent.** Every later verb that spends it needs a new
  decision, and the conversion is not free — a derived share has no natural unit.
- **A household is practice, members and last interval's surplus.** Everything
  that reads as character has to come from position and from hash-derived
  thresholds. If that proves too thin, the fix is more *observable* behaviour,
  not a personality field.

## What would refute this

**If drift never produces a moment.** Membership changing by slow percentage may
read as attrition arithmetic rather than as people choosing. The turn readout
(#46, merged) is what would have to carry it. If a household changing practice
cannot be felt as an event, adoption needs an actual beat — a visible switch —
and the "one number seen from two sides" framing is buying tidiness at the cost
of the thing the design is for.

**If derived standing is unreadable.** If a player cannot tell their lineage is
growing without being shown a number, then "standing is derived" is technically
true and experientially empty, and the readout is carrying a claim the simulation
was supposed to make.

**If three practices collapse to one in play.** FR-3 asserts no practice above
60% of households in steady state, on the standard seeds. If that fails, either
the practices are not differentiated enough or vitality's rotation is too weak to
keep moving the answer — and the honest response is to report the collapse, not
to widen the bound.
