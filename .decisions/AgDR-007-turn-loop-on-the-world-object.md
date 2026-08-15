# AgDR-007 — The turn loop lives on the world object

**Status:** accepted
**Date:** 2026-08-15

## Decision

`advance_turn()` is a method on `WorldMap`, alongside the grid, the seed, and
the terrain. There is no separate game-state, session, or engine object holding
the clock, and no `Node` anywhere in the turn's path.

Consequences that later tickets inherit:

**Every per-turn system extends this one function.** Seasons, herd movement,
node production and everything after them are called from `WorldMap.advance_turn()`,
not from parallel schedulers. The turn is a single ordered pass over the world.

**Mutable world state lives on the same object as generated world state.** The
map that generation produced and the state the simulation evolves are one thing
with one lifetime. A save is a `WorldMap`.

**The UI has no turn of its own.** `game/main.gd` calls the world's
`advance_turn()` and updates the display from the result. It holds no counter,
no cached turn number, and no branch that could disagree with the world.

## What was rejected

**A separate `Game` / `Session` object owning the clock and holding a `WorldMap`.**
The conventional split, and the one that pays off when there is per-player state
that is not part of the world — a selection, a camera, an undo stack. Rejected
because none of that exists yet and inventing the seam now means guessing where
it goes. Introducing it later is mechanical: the wrapper gets the counter and
delegates. Introducing it now and discovering the line is in the wrong place is
not.

**A `TurnController` node in `game/`.** This is what the ticket's "no parallel
update path" criterion exists to prevent. A turn owned by the scene tree is a
turn that cannot be advanced by a headless test, which makes every simulation
test after this one either a scene test or a liar.

**Signals from the world to the view.** `WorldMap` emitting `turn_advanced` would
let the view subscribe instead of being told. Rejected because signals need
`Object`, and `sim/` is `RefCounted` with a mechanical check standing on it
(`AgDR-001`). The controller calling `refresh()` after `advance_turn()` costs one
line and keeps the boundary one-directional.

## Why this is a constraining decision

Where the turn lives decides where every subsequent system is invoked from and
what a save file is. Moving it after three systems hang off it means rewriting
their entry points and their tests.

## What would make this the wrong call

**If a turn stops being a single synchronous pass.** Anything that wants to
advance incrementally — a turn animating over several frames, background
pathfinding resolving across turns, a stepped debugger over sub-phases — needs a
scheduler with state between calls, and a bare counter on the world is the wrong
shape for it.

**If per-player state grows before per-world state does.** If `game/` starts
accumulating things it must keep in sync with the turn, the rejected `Session`
object was the right seam after all.

The signal to watch: `main.gd` gaining state that has to be reset, migrated, or
reconciled when the turn moves. Today it has none — it re-reads the world. The
first field there that outlives a redraw is the warning.
