# AgDR-015 — History for trends lives in the sim, as a ledger no rule reads

**Status:** proposed
**Date:** 2026-09-05
**Parent intent:** `world-growth-tone`
**Ticket:** #37

## Decision

A **chronicle** on the world records a season's worth of per-turn readings —
one row per quantity the map wants to show a direction for. It is written at the
end of every turn, after the rules have run. **Nothing inside the turn loop reads
it back.** Deleting it changes no outcome, no fingerprint, and no seed's
behaviour; it would only take the arrows off the panel.

The renderer keeps nothing. Every trend it draws is computed from the chronicle
on the frame it is drawn.

## Why

The ticket asked for trends — "a quantity that is rising reads differently from
one that is falling" — and a trend needs at least two readings. `game/README.md`
forbids the view holding state that would not survive being thrown away, which
rules out the obvious implementation of accumulating readings in the view. So the
history has to come from somewhere else, and there were only two candidates.

**Recomputing was not available.** `AgDR-009` once claimed a world's whole state
is `(seed, turn)`, which would have let anything reconstruct last turn's numbers
on demand and needed no stored history at all. That claim did not survive #9's
nodes, routes and agents, and `AgDR-014` finished it off with per-tile vitality.
A world with agents in it cannot be rewound, so last turn's granary inflow cannot
be recovered from this turn's world. Recomputation is not a worse option here; it
is not an option.

That leaves storing it, and the only place that survives a view being discarded
is the world. The test the ticket asks for is what makes this binding rather than
stylistic: advance a world N turns with one view attached, build a *second* view
that watched none of it, and assert both report identical trends. A view holding
a buffer fails it. That test passes.

**The separation that keeps this honest** is that the chronicle is a *ledger*,
not a *rule*. AC8 says `sim/` gains no rule and may gain queries. A record of
what happened, which nothing consults when deciding what happens next, is not a
rule — and it is checkable, not a matter of intent: if any rule ever reads the
chronicle, the sim stops being a function of its own state and starts being a
function of its own history, and determinism arguments get much harder.

## What was rejected

**A ring buffer in the view.** Simplest by far, and the thing the contract in
`game/README.md` exists to prevent. It would also be wrong in a way that is easy
to miss rather than easy to see: the trends would be correct in the running game
and silently absent for one season after any rebuild of the view — a save load, a
resolution change, a hot reload. The failure mode is "the arrows are missing for
a while", which reads as a bug in the arrows rather than as a design error.

**Deriving trends from a diff against the previous frame.** Ties the readout to
frame rate rather than to turns, so a paused game has no trend and a fast-
forwarded one has a noisy one. The quantities are per-turn; the history should be
too.

**Putting the ledger in `game/` but outside the view** — a long-lived autoload
that survives view rebuilds. This passes the letter of the contract and defeats
its point: the history would then exist in a third place that is neither the
world nor the thing drawing it, and a headless run would have no access to it.
Keeping it on the world means anything that can see the world can see its recent
past, which is what #28's change report will want as well.

## What this costs

The world is no longer stateless with respect to its own past even in principle.
`AgDR-009`'s framing is already gone, but this is the first thing that stores
history *deliberately* rather than as a side effect of simulating something, and
it sets a precedent that wants a boundary: the chronicle is capped at a season
and holds scalars per turn, not events, not per-tile rows. It is a readout
buffer, not a journal.

Saving (#32) now has to decide whether the chronicle is part of a save. It should
probably not be — a loaded game with flat arrows for one season is honest, and
serialising a display buffer to disk is how a save format acquires fields nobody
can delete later.

## What would refute this

**If a rule ever wants to read it.** A mechanic that depends on a trend — a
shortage the citizens notice, a practice that responds to decline — turns this
from a ledger into state the simulation consults, and it should then be modelled
deliberately as something an agent *remembers* rather than reached for out of a
display buffer. That would supersede this record rather than extend it.

**If a season's window turns out to be the wrong one.** The window is
`TURNS_PER_SEASON` because that is the calendar the rest of the game runs on. If
the readable direction of a quantity only appears over years, this stores the
wrong resolution and the fix is a coarser second row, not a longer buffer.

**If the second-view test passes for the wrong reason.** It proves the view holds
no history. It does not prove the view holds no *other* state that matters. If
something view-held later turns out to affect what is drawn, the contract needs a
broader assertion than this one test provides.
