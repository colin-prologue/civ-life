# Product intent — the world grows with you

**Slug:** `world-growth-tone`
**Status:** durable. Tickets inherit this with `parent-intent: world-growth-tone`.

This file exists because tone is the thing that erodes quietly. Every individual
tuning decision has a plausible case for making the world a little harsher, a
little tighter, a little more punishing — and a hundred reasonable decisions in
that direction produce a game nobody set out to build. What follows is not
advice. It is the constraint later tickets are checked against.

## The feeling

An **active garden you are tending**, not life carved out of a desert.

The pleasure is watching the world evolve and grow, and being surprised by it.
Not mastery, not survival, not optimisation. A player should finish a session
having *seen something develop*, and the good ending of a long session is "look
what this became", not "I held on".

"Scary" belongs to **scale**, not danger. The world is larger than you, busy
without you, and indifferent to your plans. That is awe, and it survives
alongside a world that will not hurt you much.

## Abundance is the baseline

Most games in this space are scarcity-baseline: resources are tight, and play is
rationing. **This one is abundance-baseline.** Resources are generally
sufficient. The interesting question is what you do with a surplus and where you
point growth, never whether you can afford to eat.

A concrete consequence: if a system needs the player to be short of something in
order to be interesting, that system is wrong for this game. Find the version
that is interesting under plenty.

## Where the tension lives

A game with no fail state still needs choices to matter. The pressure here is
**attention and influence, not survival**.

**Attention.** The world is generous and busy — more is happening than one
player can attend to. You cannot shape everything at once, opportunities appear
faster than you can take them, and the cost of any choice is the other thing you
were not watching. The garden grows whether or not you tend it; tending decides
*what it becomes*.

**Influence** (added 2026-08-15, `AgDR-003`). The player is a faction inside a
larger polity, not its ruler. At your own scale you act directly; at the
polity's scale you can only persuade, invest, and spend standing. You will want
things you cannot simply cause. That is agency without control, and it is a
stronger source of pressure than attention alone — it makes the limits on
forcing change structural rather than a difficulty setting.

Between them, that is the entire source of tension. Neither needs supplementing
with threat.

## Rules

These are hard. A ticket that violates one is wrong even if it is well built.

1. **Structures persist. Flows are what the world disturbs.**
   Bandits interrupt a shipment; they do not burn the granary. A herd tramples a
   season's yield; it does not remove the farm. No world-driven event deletes a
   built structure. Negative outcomes are *absence of growth*, never *loss of
   what was built*.

   **Amended 2026-08-15 (`AgDR-003`): structures change hands rather than being
   destroyed.** Once conquest exists, "yours" is not permanent — but the
   building still stands, now under someone else's name. This is stronger than
   the original rule rather than weaker: the world visibly accumulates built
   history across eras, and ruins and inherited roads are exactly the texture
   this design wants. What is forbidden is *erasure*, not *transfer*.

2. **Soft fail only, and only from sustained mismanagement.**
   A neglected district can be abandoned and revert toward wilderness — which
   reads as the world reclaiming space, and is on-theme. It stays recoverable.
   Reaching that state must require sustained, compounding neglect, never a
   single bad decision or an unlucky season.

3. **Systems have restoring forces.**
   Ecologies and economies pull back toward health after disturbance. Negative
   feedback, not runaway. A population knocked down recovers; a route disrupted
   re-forms. Resilience is the default behaviour of every system here, and it is
   assertable in tests: perturb, run forward, observe return.

4. **Serendipity comes from coupling, never from an event table.**
   Random events read as arbitrary and players learn to ignore them. Surprise
   must come from systems observing each other's state — a herd migrating
   through a farm district making a hunting node viable; a forest quietly
   reaching density and drawing wildlife back; two things placed for unrelated
   reasons turning out to be adjacent at the right season.
   **Prefer making two existing systems read each other over adding a third
   system.**

5. **Destruction is rare and legible.**
   When something is lost it should be uncommon enough to be memorable, and the
   player should be able to tell exactly what happened and why. A loss the
   player cannot explain is a bug in this game regardless of whether the code is
   correct.

6. **Fewer and chunkier, always.** (added 2026-08-15)
   Where a system could be many small granular pieces or few large legible ones,
   choose few. Chunky nodes over many small buildings (`AgDR-002`); discrete
   Understandings over a granular tech tree (`AgDR-004`); a handful of named
   opinion modifiers over thirty stacking ones (`AgDR-005`).

   This was not designed — it emerged, having independently decided three
   separate questions the same way, and it is written down here so the fourth
   one does not go the other way. **Granularity is the thing that converts
   tending into optimising.** A player who can name every input to a decision is
   playing this game; one who has to total up a column is playing a different
   one.

## What would make this intent wrong

Watching is not automatically interesting. If a world with no threat turns out
to be a world with no reason to look at it — growth that reads as numbers
drifting rather than a place developing — then the tension model above is
insufficient and the design needs a genuine source of pressure, not just
abundance and attention.

The signal to watch for: a player who stops advancing turns because nothing they
saw made them curious about the next one. That is the refutation, and it will
show up the first time the world is visible on screen, which is why the renderer
comes early.
