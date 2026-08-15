# civ-life

A hex-based, turn-based 4X game in the Civilization lineage — city building,
conquest, scientific advancement, cultural advancement, against AI and human
players.

## The twist

Civ's world is essentially inert between your clicks: a board you optimize. Here
the world runs on its own schedule, and the pleasure is watching it develop.

Seasons turn. Animal populations move, thin out, and recover. Forests spread.
None of it waits for you, and none of it is a modifier hanging off a player
action — the simulation is authoritative and the player is a participant in it.

The target feeling is **an active garden you are tending**, not life carved out
of a desert. Closer to the original SimCity than to Civ: equilibrium is not hard
to hold, and the reward is seeing what grows. The world is *scary* in the sense
of being large and indifferent, not dangerous — destruction is rare, never takes
away what you built, and it takes sustained bad planning to make things decline.

Two consequences worth stating up front, because they're easy to tune away:

- **Abundance is the baseline.** Resources are generally sufficient. The
  interesting question is what you do with surplus and where you point growth,
  never whether you can afford to eat.
- **The pressure is attention, not survival.** The world is generous and busy —
  more happens than one player can attend to, and the cost of any choice is the
  thing you weren't watching.

**[`.switchboard/intents/world-growth-tone.md`](.switchboard/intents/world-growth-tone.md)
is the authority on tone and tuning.** It carries the hard rules later work is
checked against; this section is the summary. If the two ever disagree, the
intent file wins and this one is stale.

## The city

A city is not a tile with numbers on it. It is a set of nodes — farms,
granaries, markets — placed on separate hexes and connected by routes, with
citizens physically walking between them. Closer to Caesar and Pharaoh than to
Civ's single-tile city.

The load-bearing part: **citizens, herds, and bands are the same kind of object
on the same movement layer.** The herd wandering through your farm district and
the farmer walking to the granary interact through ordinary co-location, not a
special-case rule — which is what makes the world's activity reach you as
something that happens in a place, rather than as a penalty applied to a number.

See [`.decisions/AgDR-002`](.decisions/AgDR-002-decentralized-city-unified-agents.md),
including the constraint it inherits: routing must be boringly reliable when
nothing is stressing it, or this becomes a layout puzzle.

## Architecture

One rule drives the structure: **the simulation core is the product, and it is
headless.**

- `sim/` — pure, deterministic world simulation. No rendering, no engine types,
  no input. Same seed plus same inputs produces the same world state, always.
  This is where seasons, ecology, populations, and the economy live.
- `game/` — the Godot layer. Renders the hex map, takes input, shows the player
  what the simulation is doing. A thin client over `sim/`.

Two reasons this split is load-bearing rather than tidiness:

1. **The valuable part becomes testable without a human eye.** "Do herds migrate
   toward food and collapse under sustained overhunting" is a check that runs
   headless. "Does the world feel alive" is not, and it is downstream of the
   first one being right.
2. **Determinism is a debugging precondition.** A world this active is not
   debuggable if you cannot reproduce a state from a seed.

Anything in `sim/` that reaches for a Godot node type, wall-clock time, or an
unseeded random source is a bug, not a shortcut.

## Status

Early. The project skeleton and headless test harness are in review; the hex
grid, a minimal renderer, seasons, and the first living population are the
opening tickets, in that order.

The renderer comes early on purpose. This design's value proposition is
observational, and whether a growing world is worth watching is not a question a
test assertion can answer.

## Stack

Godot 4 (GDScript), with the simulation core as plain GDScript classes that hold
no `Node` dependency, run headless, and are tested with GUT.

```
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gexit
```

## How work happens here

This repo is driven by [Switchboard](https://github.com/colin-prologue/switchboard).
Tickets are GitHub issues; agents implement them in isolated workspaces and open
PRs; a reviewer session on a separate model checks the diff before it merges.

The project runs at the **prototype stance**: light process, fast iteration,
verification that stays cheap. It tightens when there's something worth
protecting, not before.

Decisions that would constrain future development get a short record in
`.decisions/`. Ordinary implementation choices don't — the diff is the record.
