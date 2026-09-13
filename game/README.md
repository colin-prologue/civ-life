# game/ — the Godot layer

Scenes, rendering, input, and presentation. A thin client over `sim/`.

This layer reads simulation state and draws it; it does not own world rules. A
rule that lives here instead of in `sim/` is a rule that cannot be tested
headlessly and cannot be reproduced from a seed.

## What is here

`main.tscn` is the project's main scene. It generates a world from a fixed seed,
draws it, moves the clock — a turn at a time with Space, or on its own with `P`,
at a speed set by `[` and `]` — and lets the player build in it: click a tile to
select it, `F` or `G` to put a farm or a granary on it, `R` then a second click
to draw a road between two structures, `Esc` to clear.

- `main.gd` — the controller. Owns a `WorldMap`, forwards input to it, asks the
  view to redraw. `advance_turn()` calls the world's `advance_turn()` and does
  nothing else; the tests drive that same function, so there is no second path a
  turn can travel. It also holds what is selected and what a route is being
  drawn from — session state, not world state: unsaved, unseeded, invisible to
  `sim/`.
- `hex_map_view.gd` — the drawing. Flat-top hexes, one colour per terrain,
  scaled to fit the viewport. Holds no state that would not survive being thrown
  away and rebuilt from the world — the selection outline included, which is
  told to it rather than read out of the world.

## Where placement is decided, which is not here

`game/` works out *which tile was clicked* and nothing else. Whether a structure
may stand there, and whether two structures may be joined, are world rules and
are answered by `CityGen.node_refusal()` and `CityGen.route_refusal()` — asserted
headlessly in `test/test_placement.gd`, with no scene tree anywhere near them.
This layer shows whichever sentence comes back. It does not know what water is.

The refusal travels as prose rather than as a boolean because a first verb that
silently does nothing is indistinguishable from a broken one.

The generator and the player build cities through the same two calls, so there is
one way a city comes into existence rather than a generator's way and a player's
way that drift apart. `test_only_the_one_builder_constructs_a_city` enforces that
by scanning the sources, because "we remembered to reuse it" is exactly the claim
that decays quietly.

Everything the player sees is rebuilt from world state on each turn, rather than
patched where it changed. At this size that costs a few milliseconds, and it
means a later system that alters the map becomes visible without touching the
renderer.

## What is deliberately absent

No camera, no scroll, no zoom. The whole map is still fitted to the window.

Selection and orders used to be on that list and no longer are: the player can
select a tile and place on it. What did not arrive with them is a build menu,
tooltips, tutorial, or any UI beyond the two lines of text at the top; a cost,
a currency, or any constraint on what may be placed — abundance is the baseline
and making building expensive is the wrong first instinct; demolition, moving or
un-placing, because structures persist; pathfinding, road cost or route tiers —
a route is the straight hex run or it is refused; and any third thing to place.
Farm, granary, road. Each simulation ticket that adds something to the world is
expected to make its own addition visible here.

The interaction code is built on the current 2D map view and the 2D-vs-diorama
platform question is **not** settled by its existence. If the diorama wins, this
is discarded — accepted knowingly, because the question the verb unblocks is
worth more than the code that asks it.

**Why auto-advance is here and not filed under convenience.** A year is 24 turns
and a herd covers about a tile a year (`AgDR-010`), so everything this world does
on its own timescale is hundreds of key presses away. A world that can only be
advanced by hand does not get watched long enough to answer the question
`world-growth-tone` says the design rests on — whether it is worth watching at
all. The play button is an instrument for that question.

It is still one path: the timer calls `advance_turn()`, which is the same
function Space calls and the same one the tests drive. `tick(delta)` is split out
from `_process` so the timing can be driven with an explicit delta — a test that
waits for real frames measures the host's frame rate, and under `--headless`
frames arrive far faster than a second, so the interesting cases never fire.

## What the tests cannot tell you

`test/test_hex_map_view.gd` checks that every terrain has a distinct colour, that
hexes tile without gaps, and that a click comes back on the tile it was drawn
over. None of that is evidence the map is *readable*.

`test/test_placement.gd` checks that placement refuses what it should and that
the same seed plus the same ordered inputs reproduce the same world. None of that
is evidence that placing something and watching what happens over the following
turns makes anyone want to place another one.

Both questions need a person to launch the game and look at it, and the second
one is the signal `.switchboard/intents/world-growth-tone.md` says to watch for —
a world nobody is curious about is the refutation of the whole design, and no
assertion will report it.
