# AgDR-022 — A save is the world's object graph, with its field lists checked

**Status:** accepted
**Date:** 2026-09-13

## Decision

A world's state is the `WorldMap` and everything reachable from it: terrain,
per-use vitality, the per-tile demand census, the two turn-start snapshots, every
agent with its private movement state, every structure and road, the shared
species, the chronicle, the turn and the seed. Only two things are left out, and
each is named with its reason in `WorldSave.NOT_SAVED`: forage, which is still a
pure function of terrain and season (`AgDR-009`'s surviving half), and the turn
report, which is rebuilt by the next turn.

This corrects `AgDR-009`, whose line *"a save is two numbers"* stopped being true
when herds started carrying their position from turn to turn (#9).

`sim/world_save.gd` writes this by hand as versioned JSON. `game/` picks the
filename. A version the code does not know is refused, not migrated.

**The field lists are the constraint later tickets inherit.** `WorldSave.SAVED`
names every script variable of every class in the graph. A test walks a populated
world and fails if any variable on any reachable object is on neither list, or if
a class appears that has no list. Adding state to the world without extending the
save turns the suite red on the day it is added, not the day somebody's save
diverges.

## What was learned doing it

**The demand census is state, not a cache.** It is documented as a running sum of
the agents' demand, but it is maintained by float add-and-subtract, it drifts, and
decisions read the drifted value. Recomputing it on load gives a world that
diverges. It is saved verbatim.

**JSON does not round-trip a double in Godot 4.7.** Six herd populations of
fourteen came back one unit off in the last digit, which was enough to diverge by
turn 650. 32-bit rows survive as plain numbers; 64-bit scalars are written as a
readable number beside their exact bits, and the bits load.

## What was rejected

**Godot's variant text format (`var_to_str`).** Carries `Vector2i` and packed
arrays for free, but it can deserialise objects out of a file and the output
is only readable by something that knows Godot.

**`(seed, inputs)` replay.** Store the seed and the player's ordered placements and
re-run. Tiny files, but loading turn 5,000 costs 5,000 turns, and every rule
change silently changes what an old save means. That's exactly the kind of subtly
wrong world the version check exists to refuse.

**Per-class `to_dict`/`from_dict` methods.** Spreads the format across eight files
and puts I/O in classes whose headers argue that they are pure rules. One file
that knows the format, plus a test that knows the classes, keeps each concern in
one place.

**A reflection-driven serialiser.** It would make the field lists unnecessary,
and would also save things that shouldn't be saved (caches that are real caches,
references that need re-linking) with no one deciding. The lists are the decision,
written down.

## What would make this the wrong call

**The graph stops being a tree of plain objects.** If a later system holds
callables, engine resources, or references that cross between agents (a band
following a herd), the hand-written encoder needs identity tables for each and
the cost of a new field stops being one line.

**Migration becomes necessary.** Once saves are worth keeping across versions,
refusing an unknown version is no longer enough, and a hand-written format with
no schema is the expensive thing to migrate.

**The field-list test gets excused into meaninglessness.** If `NOT_SAVED` grows
entries whose reason is not "a pure function of what is saved", the check is being
routed around, and the round-trip determinism test is the only thing left holding.

## Addendum: what a save may carry, and what the decoder refuses

**Supported map domain.** A save holds at most `WorldGen.DEFAULT_WIDTH *
DEFAULT_HEIGHT` tiles, the one size the game generates (no player-facing control
makes another). `WorldGen.generate()` can build a larger world, but it is outside
the save API: `encode()` now refuses it (`unsaveable()`), as `decode()` always did,
so a file this build writes is a file it reads. Raising the limit is a deliberate
change to `WorldSave.MAX_TILES`, not a side effect of generating a bigger map.

**Decoder rule.** A save is refused when a value crosses a real conversion,
constructor, allocator or bounded-history rule of the running game (32-bit
narrowing, `Vector2i` wrap, ids that the next allocation would reuse, a road below
its laid crew, a demand row that is not the agents' census within float32 drift,
a chronicle longer than its window). It is not refused for balance or product
limits, population caps, or unreachable history; those would be invented here.
