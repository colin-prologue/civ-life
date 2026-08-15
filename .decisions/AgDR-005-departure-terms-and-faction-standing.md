# AgDR-005 — Departure terms and faction standing

**Status:** accepted (shape); thresholds open
**Date:** 2026-08-15
**Parent intent:** `world-growth-tone`
**Resolves:** the open question in `AgDR-003`
**Depends on:** `AgDR-002` (unified agent layer), `AgDR-004` (Understandings)

> **Provisional.** This record describes a layer roughly ten tickets out, and it
> rests on a premise the build has not yet tested: that watching a world grow is
> compelling. That is `world-growth-tone`'s own stated refutation, and it is first
> answerable when the renderer lands. Until then treat this as recorded thinking,
> not settled architecture — cheap to retract, and expected to be revisited.

## Decision

**Voluntary splintering is permitted at any time**, not only at an era turn. Its
cost is **relational, not material**.

The faction you leave forms a negative opinion of you, and that opinion has
consequences on a spectrum — from withheld cooperation up to active attempts to
draw your people back.

### Why relational rather than material

A material penalty — arrive small, arrive poor — **decays**. You rebuild, and
within an era the cost is gone, so nothing stops a player cycling through
polities. A relational cost persists, because the world remembers.

It also satisfies the intent file rather than straining against it. Withheld
cooperation is **absence of help, not loss of a thing**: nobody burns your
granary, they simply stop trading with you. That is intent rule 1 by
construction.

### The consequence spectrum

Escalating, and roughly in this order:

1. **Cooler dealing** — worse terms on trade and resource sharing.
2. **Knowledge withdrawal** — they stop sharing Understandings with you, and
   may decline ones you offer.
3. **Non-cooperation** — they decline to aid you in a hard season, and work
   against your positions at the polity level.
4. **Reclamation** — active attempts to draw your people back to them.
5. **Status reduction** — they campaign against your standing with third
   parties, so the grievance propagates beyond the two of you.

Reclamation is nearly free to build: under `AgDR-002` it is agents choosing to
move toward a puller, on the movement layer that already exists. No new
subsystem. That the escalation ladder needs no new machinery is a third
independent validation of that abstraction.

### Grievance scales with what you took

This is the link that makes departure a real decision rather than a toll.

Per `AgDR-004`, held Understandings travel with you and shared ones stay behind.
So a faction that hoarded leaves **rich and resented**; one that shared
generously leaves **poor and welcome**. The share/hold dilemma now pays out along
three timelines at once:

| | Consequence |
|---|---|
| **Share** | standing now |
| **Hold** | portability later |
| **Hold what they consider communal** | grievance on exit |

The *manner* of departure is therefore a choice in itself: negotiate your leaving
and give something up, or take everything and wear it.

### Standing is faction-scoped and asymmetric

Opinion is held **by factions, not by polities**. A whole polity does not
uniformly resent you — the factions you actually damaged do, others are
indifferent, and some may sympathise (a faction that wanted to leave too). That
gives asymmetric diplomacy, a route back, and potential allies inside a place you
left.

Opinion is also **directional**: A's opinion of B is not B's opinion of A. You
may resent a faction that has genuinely stopped thinking about you.

## Legibility — the itemised breakdown

Standing is displayed as a **stack of named contributions**, each with a sign, a
weight, and where relevant a decay timer. Borrowed directly from the Crusader
Kings opinion-modifier language.

```
Ashmoor Clan — opinion of you: −12
  −25  Splintered from us            (11 years ago, fading)
  −10  Withholds knowledge of bronzeworking
  + 8  Gave aid in the hard winter   (3 years ago)
  +15  Trade partner, two generations
```

The breakdown **is** the explanation. Intent rule 5 requires that a loss be
traceable, and an itemised opinion with named causes satisfies it without a
separate explanation UI.

Two kinds of entry, and the distinction matters:

- **Event modifiers** record something that happened and decay (`Splintered
  from us`).
- **Live-state modifiers** persist exactly as long as the condition holds and
  vanish the moment it changes (`Withholds knowledge of bronzeworking`).

Live-state entries are the more valuable half. They make the opinion panel the
place where the share/hold dilemma is actually *felt* — a player can see that
three factions would warm to them by releasing one Understanding, and see what
releasing it costs, in the same view.

**Borrow the legibility, not the density.** Crusader Kings' opinion system is
also a spreadsheet, and thirty stacking micro-modifiers reward exactly the
optimisation this game rules out. Few modifiers, chunky values, readable at a
glance. A grudge composed of three things you can name beats one composed of
twelve you have to total up. See intent rule 6.

## The three bounds

Without these it curdles into the hostile game the intent file forbids:

1. **Legible** — a player must always be able to trace why a faction is cold to
   them. The breakdown above is the mechanism.
2. **Mendable** — grievances decay, and can be actively repaired through gifts,
   shared knowledge, or aid during hardship. One splinter must not permanently
   poison a relationship; that is a hard fail in slow motion.
3. **Survivable** — leaving must remain a live option. **This is the real risk
   here.** The failure mode is not grudges being too weak; it is grudges severe
   enough that no rational player ever splinters, which kills the mobility loop
   `AgDR-003` rests on and the faction model with it.

## What would make this wrong

**If splintering stops happening.** If playtesting shows players staying put to
avoid the relational cost, bound 3 has been violated and the penalties need to
come down — not the loop redesigned.

**If standing becomes something to optimise.** If players are managing a ledger
of modifiers rather than living with relationships, the density caution was not
heeded and the modifier count needs cutting, not rebalancing.

Early signal: the first playtest where a player considers leaving and talks
themselves out of it. Whether the reason is "that would cost me something real"
or "that would be strictly bad" separates the working version from the broken
one.

## Open

Deliberately unspecified, because inventing them now would be false precision
that a playable build will overturn:

- Decay rates — what "fades" means in years or eras.
- Where reclamation sits on the ladder, and what triggers escalation to it.
- Whether status reduction (5) propagates to factions with no direct
  relationship to either party.
