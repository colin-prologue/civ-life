# game/ — the Godot layer

Scenes, rendering, input, and presentation. A thin client over `sim/`.

This layer reads simulation state and draws it; it does not own world rules. A
rule that lives here instead of in `sim/` is a rule that cannot be tested
headlessly and cannot be reproduced from a seed.

## What is here

`main.tscn` is the project's main scene. It generates a world from a fixed seed,
draws it, and advances the turn when you press Space.

- `main.gd` — the controller. Owns a `WorldMap`, forwards input to it, asks the
  view to redraw. `advance_turn()` calls the world's `advance_turn()` and does
  nothing else; the tests drive that same function, so there is no second path a
  turn can travel.
- `hex_map_view.gd` — the drawing. Flat-top hexes, one colour per terrain,
  scaled to fit the viewport. Holds no state that would not survive being thrown
  away and rebuilt from the world.

Everything the player sees is rebuilt from world state on each turn, rather than
patched where it changed. At this size that costs a few milliseconds, and it
means a later system that alters the map becomes visible without touching the
renderer.

## What is deliberately absent

No camera, no scroll, no zoom, no selection, no orders. The whole map is fitted
to the window and the only input is "advance". Each simulation ticket that adds
something to the world is expected to make its own addition visible here.

## What the tests cannot tell you

`test/test_hex_map_view.gd` checks that every terrain has a distinct colour and
that hexes tile without gaps. Neither is evidence the map is *readable*. That
question needs a person to launch the game and look at it, and it is the signal
`.switchboard/intents/world-growth-tone.md` says to watch for — a world nobody
is curious about is the refutation of the whole design, and no assertion will
report it.
