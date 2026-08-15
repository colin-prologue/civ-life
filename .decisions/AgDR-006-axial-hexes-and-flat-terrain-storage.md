# AgDR-006 — Axial hex coordinates, offset extent, flat terrain storage

**Status:** accepted
**Date:** 2026-08-15

## Decision

Three choices that everything on the map will sit on:

**Hexes are addressed in axial coordinates** — `Vector2i(q, r)`, flat-top
layout. Neighbours are six constant offsets and distance is
`(|dq| + |dq+dr| + |dr|) / 2`. Both are integer arithmetic with no conversion.

**The map's extent is defined in odd-q offset space** (`col`, `row`) and
converted to axial at the boundary. A rectangle in axial space is a rhombus on
screen, which would give a lopsided world; defining the extent in offset space
keeps the map a tidy width × height block while all the arithmetic stays axial.

**Terrain is a flat array indexed by grid position**, not a dictionary keyed by
coordinate. Iteration is row-major over offset space and never depends on a
hash, so two maps compare with a single array equality and the comparison order
is identical on every run and every machine.

## What was rejected

**Cube coordinates** (`q, r, s` with `q + r + s = 0`). Slightly more elegant for
rotation and reflection, and the usual recommendation for line-drawing and
range algorithms. Rejected because the third component is redundant storage that
must be kept consistent, and `Vector2i` is a native Godot type with value
semantics and dictionary-key support that a three-component hex would have to
reimplement. Cube is derivable from axial in one line if an algorithm wants it.

**Offset coordinates as the working system.** Familiar and directly indexable,
but neighbour lookup becomes two different cases depending on column parity —
exactly the kind of arithmetic that is wrong at edges and looks right in the
middle.

**A `Dictionary` keyed by coordinate for terrain.** The obvious shape, and it
tolerates sparse or irregular maps. Rejected because determinism is the point of
this layer: dictionary iteration order is a hash detail, and a comparison or a
checksum that walks it inherits that. A flat array makes "same seed, same map"
a single equality rather than a property that has to be argued about.

## Why this is a constraining decision

Every later system — pathfinding, settlement placement, territory, rendering —
takes coordinates from this layer and stores per-tile data alongside it.
Changing the coordinate system later is not a refactor of `sim/hex_grid.gd`; it
is a rewrite of every caller's spatial reasoning. The flat-array storage
similarly sets the shape of the eventual save format.

## What would make this the wrong call

**If the map stops being a fixed rectangle.** Flat-array storage assumes a
dense, bounded, known-size grid. A world that streams in chunks, grows at the
edges, or is mostly empty would want the dictionary that was just rejected, and
the index arithmetic would become the obstacle rather than the shortcut.

**If rendering pushes back on flat-top.** The layout is currently a headless
abstraction with nothing drawing it. If the art direction wants pointy-top
hexes, the conversion functions change and the axial arithmetic does not — this
is the cheap half of the decision to reverse.

The signal to watch: per-tile data being kept in side dictionaries keyed by
coordinate rather than in parallel arrays. One is a convenience; a pattern means
the flat-array assumption is not paying for itself.
