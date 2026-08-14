# AgDR-001 — The simulation core is headless and deterministic

**Status:** accepted (project seed)
**Date:** 2026-08-14

## Decision

The world simulation lives in `sim/` as plain GDScript classes with **no `Node`
dependency, no rendering, and no input handling**. The Godot layer in `game/` is
a client over it. `sim/` runs headless and is tested headless.

The simulation is **deterministic**: the same seed and the same ordered inputs
produce the same world state. No wall-clock time, no unseeded randomness, no
iteration over unordered collections where order affects outcome.

## What was rejected

**Simulation as Godot nodes** — tiles, herds, and cities as `Node2D`s in a scene
tree, with `_process` driving the world. This is the ordinary Godot way and it is
genuinely more convenient early: you get visualization for free and no
serialization boundary to maintain.

It was rejected because it makes the valuable part of this project untestable
without a human watching a screen, and because scene-tree state is difficult to
reproduce from a seed. A world that changes on its own is exactly the kind of
system that needs both.

## Why this is a constraining decision

It sets a boundary that most later code sits on one side of, and moving it later
means rewriting the simulation rather than refactoring it. It also decides how
this project is verified — headless assertions over world state rather than
visual inspection — which shapes every ticket that follows.

## What would make this the wrong call

**If the interesting behaviour turns out to be inseparable from presentation.**
If "feels alive" lives mostly in animation, camera, and audio response rather
than in the underlying model, then a headless core is elaborate machinery around
the part that turns out not to matter, and the serialization boundary is pure
cost.

The early signal to watch: if simulation tickets keep needing to reach into
`game/` for something, the boundary is in the wrong place. One or two is normal;
a pattern is the refutation.
