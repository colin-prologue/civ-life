# Product intent — procedural art and the rendering layer

**Slug:** `procedural-art`
**Status:** durable. Tickets inherit this with `parent-intent: procedural-art`.

Adapted from an external implementation brief (2026-08) and two art-direction
studies ("The Grown Map", "The Unbroken Thread"), reconciled against this
repo's decisions. Where the original brief and this file disagree, this file
is the version the repo builds against — the divergences are listed
explicitly in "Reconciliations" so they were chosen, not drifted into.

## North star

The map is not a static illustration of the current world. It is a living
record of geography, choices, use, hardship, abandonment, adaptation, and
inheritance. **The renderer should be able to explain every visible mark
from simulation state.**

Core tone (inherits `world-growth-tone`): decay everywhere, doubt nowhere.
Ruins carry evidence of continuity, not finality. Gold is aspiration and
deliberate human action; verdigris is time, inheritance, and adaptation.

This is already true in miniature: the seasons ticket made forage bleach
tile colour, and the season of the world is readable from the map with no
UI. Everything below is that same move, compounded.

## Principles

- **Geometry describes the present.** Terrain fills, coastlines, structures,
  roads, and current vegetation say what exists now.
- **Marks describe memory.** Ghost roads, foundation traces, scars,
  cultivation patterns, patina, silt, and regrowth say what happened before.
- **Density is earned.** A place with 8,000 years of occupation should be
  more visually layered than untouched wilderness. (Bounded by Rule 6 of
  `world-growth-tone` — see Guardrails.)
- **Culture changes the handwriting.** The same simulation event is
  expressed with different shapes, motifs, and line rhythms depending on the
  culture that caused it.
- **Regression transforms; it does not reset.** Hardship damages,
  interrupts, simplifies, redirects, abandons, or repurposes existing
  layers. Old layers remain available to future eras.
- **Nature is an active author.** Water migrates, forests reclaim, sediment
  fills, succession alters the legibility of human marks.

**Do not store "the final look of a hex." Store state and history.**
Rendering is a deterministic interpretation of that state. This is the
existing `game/` contract — the view holds no state that would not survive
being thrown away and rebuilt from the world — extended to deep time.

## Reconciliations with the original brief

These are the deliberate departures. A ticket that follows the original
brief on one of these points is wrong even if it is well built.

1. **Hash channels, not RNG streams.** All visual variation derives from
   pure hashes — `hash(world_seed, coord, channel)`, plus feature id or
   mark index where needed — never from a seeded `RandomNumberGenerator`
   consumed sequentially. RNG streams are draw-order-dependent: adding one
   system reshuffles unrelated art and breaks cross-process fingerprint
   tests. The brief's channel *hierarchy* stands; the mechanism is hashes.

2. **Three layers, not eleven.** The brief's 11-layer node stack and its
   caching/invalidation machinery describe a mature renderer. At 1200 hexes
   under the existing 100 ms advance-and-redraw budget, we start with at
   most three drawing layers — terrain fill, marks, features/debug — and a
   full rebuild every turn. Per-`(seed, coord)` generated-geometry caches
   are allowed because discarding them is always safe. More layers,
   invalidation, MultiMesh, and RenderingServer calls are escalation paths
   taken on measurement, not up front.

3. **Zoom bands are deferred, explicitly.** The game currently has one
   fixed whole-map view — no camera, no scroll, no zoom — by design
   (`game/README.md`). The brief's "world band" *is* the game. Every mark
   must therefore earn its place at true game scale (hexes on the order of
   20 px). Zoom, if it ever arrives, is a design decision to make on its
   own merits; it must not be backed into via the renderer.

4. **Sim owns history; game owns interpretation.** The render snapshot,
   feature lifecycles, and scars are `sim/` data — deterministic, seeded,
   covered by the fingerprint. Generators, recipes, and style live in
   `game/`. Scars obey tone Rule 1: they are marks and transfers, never
   erasure of built structures.

5. **The renderer trails the sim by at most one step.** No layer or
   generator is built for state that does not exist yet — the art lab
   (below) covers experimentation instead. When a sim system lands, the
   ticket that lands it makes it visible, per existing practice.

## The render snapshot

Each hex exposes current state plus compressed historical state, as a
semantic schema — not renderer-specific values. Today that is: terrain,
forage, season, coordinate, seed. It grows roughly toward:

```
HexRenderState
  coord, world_seed
  # geography
  biome/terrain, elevation, moisture, fertility, water/coast edges
  # civilization now
  owner, influence, population, prosperity, infrastructure, conflict
  # accumulated history
  occupation_age, abandonment_age, peak_population_ever,
  cumulative_traffic, cumulative_farming, cumulative_conflict,
  prior_culture_ids
  # persistent authored things
  features: [WorldFeature], scars: [HistoricalScar]

WorldFeature   # road, granary, wall, monument, canal...
  type, culture_id, created_year, last_used_year, use_intensity,
  condition, repair_count, active, geometry, style_seed

HistoricalScar # battle, fire, flood, collapse...
  type, year, intensity, footprint, persistence, caused_by_culture
```

Why feature lifecycles matter: a road from 3,000 years ago must not vanish
because a node was deleted. Its record moves from active road → neglected
road → ghost track → memory trace, and a later culture may reactivate the
same geometry. That is Rule 1 as a data structure.

## The mark vocabulary

Visual richness comes from a small set of reusable generators, not bespoke
assets. Each takes semantic inputs plus a hash channel and emits polygons,
polylines, or small silhouette glyphs:

| Generator | Driven by | Output |
|---|---|---|
| Contours / hachures | elevation, slope | nested polylines; strokes densify with slope |
| Forest stipple | biomass, age, disturbance | tree glyphs, blue-noise spacing |
| Water lines | flow, coast adjacency | sparse dashes and bank lines |
| Field patterns | fertility, farming, culture | furrows, terraces, radial plots, orchards |
| Roads | traffic, age, tech | centerline + width class + ghost underlay |
| Settlement clusters | population, culture | hierarchy of footprint glyphs |
| Monuments | culture, era | high-contrast silhouette from motif grammar |
| Ruin transform | condition, abandonment | segment removal, offsets, exposed foundations |
| Reclamation | moisture, abandonment age | edge-biased moss, roots, canopy patches |
| Patina transform | material, age | palette shift toward verdigris + sparse patches |

Variation rules: stable per-channel hash seeds; jitter position, omission,
scale, and motif choice only inside authored bounds; prefer correlated
variation (nearby marks share orientation and density); quantize important
properties into a few visual states — the map should read like designed
print, not scientific noise; at whole-map scale, omit detail rather than
shrinking it.

## Culture as a style grammar

A culture is a set of shape preferences, not a texture pack: primary axis,
symmetry bias, curvature, taper, monumentality, repetition, setbacks,
road geometry (organic / axial / radial / grid), field geometry, motif set,
gold usage, palettes, ruin profile. One grammar, per-culture parameters —
so the same farm state renders as terraces under one culture and strip
fields under another, and a ruin stays attributable because broken geometry
preserves its ratios. Until factions exist in the sim, culture is two
hardcoded, deliberately opposite style resources used by the art lab.

## Condition, not era

Eras are not global art swaps. A world holds several conditions at once —
one valley flourishing while another lies silent. The local ladder:

wild → settled → growing → peak → stressed → collapsed → silent → returned

Prosperity raises road continuity, hierarchy, gold coverage, and repair.
Hardship raises omission, scars, and interruption — locally, never as
global noise. Abandonment lets vegetation cross old boundaries and moves
ghost-line visibility along a rise-then-fall curve; monuments outlast
domestic fabric. Resettlement attaches new marks to useful old geometry,
and ruins become foundations, quarries, gardens, shrines.

## Color as state

Semantic roles, not decoration: ground/void (quiet dark field), living
terrain (biome greens, earths, water), aspiration (gold/brass — scarce
enough to signal intention), time (verdigris/patina), memory (muted ghost
lines), rupture (rare high-salience accent), renewal (fresh living accent
distinct from patina).

**The reduction test:** any candidate style must survive six flat colors,
no gradients, no transparency, and a minimum feature size of a few
on-screen pixels. If its identity disappears, it is not yet encoded as a
usable procedural rule.

## The art lab

The central approach while the sim is young: a standalone scene
(`res://game/artlab/`) that feeds **synthetic** `HexRenderState` into the
real generators — parameter sweeps over moisture, farming, occupation age,
abandonment, culture, condition. The lab needs no sim support, it is where
every generator is developed and judged, and when the sim later produces a
variable for real, the map inherits everything the lab proved. The lab is
a fake sim; the renderer cannot tell the difference, which is the point.

Two standing rules:

- **True scale first.** Every study renders at game scale (~20 px hexes)
  beside a magnified view. A mark that only works magnified does not ship.
  This is the single most likely place the original brief is wrong, so it
  is tested first, not discovered last.
- **Judged through the capture harness.** Experiments produce pinned
  frames via `tools/capture.gd` / `shot_links.sh`, so art decisions are
  reviewable in tickets the same way behaviour is.

## Experiments, ordered by the assumption they kill

Each is small, answers one question, and leaves reusable infrastructure.
The order is by risk: the earlier an experiment can invalidate the plan,
the earlier it runs.

- **E0 — The legibility ceiling (run first).** Synthetic hexes carrying
  maximum plausible history, rendered at true game scale across the whole
  map. Question: how many historical layers coexist before the map stops
  reading, and which mark types survive at 20 px at all? This can kill or
  reshape most of the vocabulary in a week, which is why it goes first.
- **E1 — One hex, 1,000 lives.** One plains hex under a matrix of
  moisture × farming × occupation age × abandonment × culture. Question:
  do variables compose into authored-looking pictures, or noise?
- **E2 — A road that remembers.** A 20–40 hex route driven by a *scripted*
  traffic timeline (build → peak → abandonment → resettlement preferring
  old alignments). No sim needed — fake history is still history.
  Question: does inheritance read without special-case art?
- **E3 — Two cultures, one valley.** Same geography and population, two
  opposite CultureStyle resources. Question: is culture legible without
  changing the core palette?
- **E4 — Collapse without apocalypse.** Prosperous region, severe hardship
  curve, 500 years of succession. Question: can hardship read as serene
  and consequential rather than grimdark?
- **E5 — Palimpsest.** Three cultures cycled through one site, foundations
  and ghost roads preserved. Question: does the current city visibly sit
  on 4,000 years of decisions?
- **Budget gate (continuous).** The existing 100 ms advance-and-redraw
  test runs against the full mark load from E0 onward. If the map must
  lose marks to meet it, that is a finding to report, not hide.

What the lab cannot de-risk: whether the *real* sim produces state
distributions that compose well — synthetic matrices are uniform, ecology
clusters. That risk stays open until live variables feed the same recipes,
which is why each sim ticket keeps making its own addition visible.

## Vertical slice

Enough to prove the thesis, no more: deterministic hex geometry and hash
channels; four terrain generators (contours, forest stipple, water lines,
fields); three features (road, settlement cluster, monument) with
condition transforms (active → weathered → ruined → reclaimed); two
opposite culture styles; three scars (fire, collapse, flood); a history
snapshot sufficient to retain inactive features; a debug inspector that
shows, for any hex, the exact variables and seeds behind its visual
result.

## Guardrails

- Flat vector shapes first: polygons, polylines, small silhouettes,
  repeated marks. No photorealism, painterly lighting, bloom, or texture
  that carries the style by itself.
- Negative space is intentional. Maximal history does not mean equal
  detail everywhere — and "density is earned" is bounded by Rule 6
  (fewer and chunkier): if accumulated marks make a place harder to *read*,
  the marks are wrong, not the rule. Legibility outranks richness.
- Wild nature stays visually competitive with civilization; the world is
  never just a board underneath cities.
- Ruins imply use, adaptation, or ecological incorporation more often than
  desolation.
- Gold stays scarce enough to signal intention; patina tells time, not
  merely "things are green now."
- Catastrophe breaks patterns; recovery creates new patterns that
  negotiate with what survived.
- Prefer rules derived from variables over unique exceptions. When a
  result feels generic, change the grammar, not the amount of noise.

## Definition of success

If a screenshot is interesting only because the seed happened to make a
pretty arrangement, the system is not done. Success is being able to point
at any visual feature and say: that pattern exists because people farmed
here for 600 years; that faint line is the old imperial road; that green
intrusion is where the district was abandoned after the flood.

The renderer's job is to make history visible.
