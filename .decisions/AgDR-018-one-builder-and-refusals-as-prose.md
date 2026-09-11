# AgDR-018 — One builder for cities, and refusals that travel as prose

**Status:** accepted, provisional
**Ticket:** #27 — one player verb: select a tile, place a node, draw a route

This rests on a premise the build has not yet tested — that watching a world
grow is compelling. #27 is the ticket that makes that premise *answerable*; it
does not answer it. If AC11 comes back "no", the tension model is insufficient
and AgDR-003, AgDR-004 and AgDR-005 rest on a premise that failed.

## What was chosen

**1. There is exactly one way a city comes into existence.** `CityGen.place_node()`
and `CityGen.connect_nodes()` are the only calls that construct a `CityNode`, a
`Route` or a `Citizen`. `CityGen.populate()` — the worldgen city — was rewritten
to go through them rather than to build directly, so the generator is now a
*client* of the player's API rather than a parallel implementation of it.

**2. Placement validity lives in `sim/`, as a pure static function on `CityGen`.**
`node_refusal(world, coord)` and `route_refusal(world, a, b)` answer "may this be
built" with no scene tree, no viewport and no click. `game/` computes which tile
a pixel landed on and asks. It does not know what water is.

**3. A refusal is the sentence, not a boolean or an error code.** The functions
return `String` — empty means allowed, non-empty is the reason, written as the
words the player reads. `can_place_node()` / `can_connect()` are thin wrappers
for callers that only want the yes/no.

## What was rejected

**A boolean `can_place()` plus a separate reason lookup.** Two functions that can
disagree, and the reason table goes stale the first time a new refusal is added
and only half the pair is updated. Returning the reason *is* the check, so they
cannot drift.

**An enum of refusal codes with a translation table in `game/`.** More
ceremony, and it puts a fragment of the placement rule back in the renderer —
the exact boundary AgDR-001 exists to hold. Revisit when there is a second
front-end or a localisation requirement; neither exists.

**Letting `populate()` keep its own construction path.** It was already written
and working, and routing it through the player's calls was strictly more work
for no new feature. Rejected because two paths to the same object is how the
generator's cities and the player's cities quietly acquire different invariants
— and the divergence would surface as a bug in the *simulation*, far from the
placement code that caused it.

**Silent refusal.** A first verb that does nothing when clicked is
indistinguishable from a broken one. This is the single worst failure mode
available to this ticket, which is why the reason is carried rather than dropped.

**A general command/replay system in `sim/` for AC6.** Determinism under ordered
input is proved by a plain array of action dictionaries replayed in a test. A
command layer would be infrastructure for a save format nobody has designed.

## What makes this the wrong call

- **If a second node kind needs a validity rule the current three checks cannot
  express** — a farm that needs adjacent water, a structure with a footprint
  larger than one tile — then `node_refusal()`'s flat signature is wrong and this
  wants a per-kind rule object instead. The current shape assumes validity is a
  property of *the tile*, not of the tile-and-kind pair. Two kinds is not enough
  evidence to know.
- **If refusals ever need to be localised, counted, or reacted to
  programmatically**, prose is the wrong carrier and the enum that was rejected
  above becomes correct. The cheap migration is to keep the function signature
  and change what the constants hold.
- **If the diorama wins the platform question**, the `game/` half of this is
  discarded. The `sim/` half — which is the part this record is about — survives
  that, because it never knew a renderer existed. That asymmetry is the argument
  for the boundary and it is why the interaction code was allowed to be cheap.
- **If `populate()` ever needs to build something the player may not**, routing
  it through the player's calls becomes a straitjacket and it will be tempting to
  add a bypass flag. Adding the bypass is the moment this decision is dead;
  prefer widening what the player may do, or accept two builders knowingly and
  amend this record.

The one-builder claim is enforced mechanically, not by prose: a test scans
`sim/` and `game/` for `CityNode.new(`, `Route.new(` and `Citizen.new(` outside
`city_gen.gd` and fails on a hit. Prose cannot hold this — the next ticket that
wants a structure would write the constructor wherever it happened to be
standing, and "we remembered to reuse it" is exactly the claim that decays
quietly.
