# AgDR-003 — The player is a faction, not a civilization

**Status:** accepted (direction; scoping notes below)
**Date:** 2026-08-15
**Parent intent:** `world-growth-tone`
**Supersedes:** the "one civilization" framing in the project's opening pitch

## Decision

The player is **a faction inside a larger polity** — a clan, a house, a lineage
of practice — never a whole civilization and never a single named individual.
There is no bloodline and no succession bookkeeping; the faction is the unit and
it persists across generations without being modelled person by person.

This has two consequences that do most of the work.

### 1. Two scales of power

| Scale | What the player can do |
|---|---|
| **Your faction** | direct control — place nodes, connect routes, tend |
| **The polity** | influence only — persuade, invest, trade knowledge for standing |

You cannot decree at the polity level. Things you want will happen because you
built standing and spent it, or they will not happen. This makes "your ability
to force change is limited" a structural property rather than a difficulty
setting, and it is the mechanical form of the garden the intent file describes.

Note the split preserves the tactile city-building. At your own scale the game
is still hands-on placement; the political layer sits above it.

### 2. Faction mobility replaces both win and lose conditions

Because the player is always a faction inside something, **being a minor faction
in a large polity is the default state, not the defeat state.** What changes over
a long game is which whole you belong to and how much standing you hold in it.

Two exits, with deliberately asymmetric costs:

- **Splinter** — leave and found your own. *Keep your identity, lose your scale.*
  You arrive small, with a real uphill climb.
- **Absorb** — submit to whoever defeated you. *Keep scale, lose your autonomy.*
  You become a clan **within** them, not their leader.

Neither is a win, so neither is farmable. The choice is the historical dilemma
of a defeated people: flee and remain yourselves, or submit and become part of
them.

**Two constraints make absorption non-exploitable**, and they are the point of
this section rather than details of it:

1. You may only be absorbed by **whoever actually defeated you**. It is never a
   menu, so it can never be used to select the strongest neighbour.
2. Absorption grants **position, not command**. You inherit a large polity's
   context and almost none of its control — a minor house in a big realm, with
   an internal climb ahead of you. Scale becomes nominal rather than usable.

Without both, the loop inverts: a player could deliberately lose to the largest
civilization and inherit it. That perverse incentive is the single most likely
way this design fails, and it fails quietly — players who find it conclude the
game is broken.

### Pacing

Era turns are the natural rhythm for a **voluntary** splinter — a structured
moment where continuing or scattering is a live question. **Defeat** forces the
choice off-schedule. One exit is chosen, one is imposed.

### What happens to a faction you leave

It continues autonomously under AI — it was being run hands-on anyway, so there
is no seam. You can meet your former people again later, thriving or diminished,
and that is one of the strongest payoffs this structure offers. Level-of-detail
simplification when a group is far from the player's attention is the expected
way to afford it.

### Conquest

Retained, but relocated:

- **Ambient from the start** — autonomous groups bump into each other, absorb,
  splinter, and displace. The player witnesses it, and sometimes it happens *to*
  them, which is a pivot rather than a defeat.
- **Directed later** — a late-age verb, unlocked like any other capability. By
  then the world has enough accumulated history for taking something to mean
  something.

## Scoping note — this is direction, not a build order

The full shape (many polities, a full council, deep faction politics) is the
north star. **The smallest version that tests the idea is one polity, the player
plus two AI factions, a handful of Understandings, and one polity-level decision
per era.** Aim the first playable there. Nothing in this record should be read as
license to build the whole system before anything is playable.

Nothing here changes the current ticket sequence: hex grid, renderer, seasons,
herds, and nodes-and-routes are all still needed and still first.

## What would make this the wrong call

**If influence is less satisfying than control.** A player who cannot make things
happen directly may simply feel powerless rather than embedded. The line between
"I am one voice among many in a living world" and "the game ignores me" is
narrow, and it is a felt quality rather than a computable one.

**If re-attachment reads as starting over.** The whole structure depends on the
world persisting meaningfully across a transition. If splintering feels like a
new save rather than a new chapter, the persistence is too thin and the loop has
no arc.

Early signal for both: the first time a player loses a polity-level vote they
cared about. If that reads as interesting, this works. If it reads as pointless,
the two-scale split is wrong.

## Resolved

**Whether the player may voluntarily splinter outside an era turn, and at what
cost** — answered by `AgDR-005`. Yes, at any time, and the cost is *relational
rather than material*: the faction you leave forms a lasting negative opinion,
scaling with what you took. A material cost decays and would not have held the
loop together; a remembered one does.
