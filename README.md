# civ-life

A hex-based, turn-based 4X game in the Civilization lineage — city building,
conquest, scientific advancement, cultural advancement, against AI and human
players.

## The twist

Civ's world is essentially inert between your clicks: a board you optimize. Here
the world runs on its own schedule and you react to it.

Seasons turn. Animal populations move, grow, and collapse. Rivers shift, forests
spread and burn. None of it waits for you, and none of it is a modifier hanging
off a player action — the simulation is authoritative and the player is a
participant in it.

The target feeling is a **lived-in, slightly simplified, scary but maintainable
place where you carve out a niche.** Not a spreadsheet you micro-optimize; a
world you keep up with. If a player's dominant verb is "adjust the slider by 2%",
that's a design failure. If it's "the herds moved south and I have a winter
problem", that's the game.

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

Nothing is built yet. The project skeleton, the test harness, and the first
slice of the world simulation are the opening tickets.

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
