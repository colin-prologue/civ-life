# Modular building system — slice 1

**Date:** 2026-08-26
**parent-intent:** `procedural-art`
**Status:** design agreed in conversation; not yet planned or implemented
**Scope:** slice 1 of four. Slices 2–4 are sketched under "The arc" and are
deliberately unspecified — speccing them now would guess at answers slice 1
exists to produce.

## Why this, and why now

The owner's stated priority (2026-08-25) is a **modular building system that
scales and invites tinkering while the design intent is still being
discovered**. Camera work and terrain are explicitly later. The current models
are proof of concept and are not to be treated as a standard worth preserving —
"tons of variants and building styles will be introduced", so the thing under
test is the *vocabulary*, not any specimen it produces.

A second constraint shapes the whole design: the owner is a solo engineer with
little art experience, and wants **AI-assisted exploration** to be a first-class
use case. Those two facts point the same way and away from the obvious design:

- A panel of exported parameters is a poor interface for someone without art
  intuition. You cannot form a hypothesis about a number you have no feel for,
  so tuning degenerates into wiggling values. Discovery happens by **choosing
  between things seen side by side** — which is exactly how every durable
  finding in the `procedural-art` intent's addendum was produced by the Blender
  lab (culture sheets, the seven-date sequence, the season re-grades).
- Agent-driven exploration needs styles that can be **generated, mutated,
  crossbred and diffed programmatically**. Imperative recipe functions resist
  all four. Declarative data supports all four.

So: styles become data, the loop becomes comparison, and `CultureStyle`
parameters are *extracted from* several working styles rather than designed in
advance.

## The ceiling being removed

Current state of `game/diorama/grammar.gd` on `main`:

- Recipes are hardcoded functions (`residential`, `civic`, `stepped`,
  `hero_arch`). A new style means a new function.
- Assembly is hand-arithmetic re-derived per recipe — `x += w * 0.95` in one,
  `y += tier_h` in another. There is no shared notion of stacking or rowing.
- Proportions are loose magic numbers (0.55, 1.08, 0.62, 0.38) scattered inside
  each recipe, so nothing can vary them coherently.
- Colour is baked per part at authoring time, so a culture cannot re-map roles.
- `tag` (`"base"` / `"mid"` / `"upper"` / `"crown"` / `"accent"`) is hand-written
  per part. Every new style must remember to label parts correctly or it
  silently loses ruin and assembly behaviour.

What is worth keeping, and is treated as fixed by this design:

- The parts contract `{kind, xf, params, color, tag, y}` consumed by
  `DioramaGrammar.emit()`.
- Hash-channel determinism (intent reconciliation 1: pure hashes, never
  sequential RNG streams).
- The `mesh_kit` geometry invariants added in #25.
- `sim/` is untouched. This is entirely game-layer interpretation.

## Architecture

### Representation: a style is a tree of five node types

| Node | Meaning |
|---|---|
| `mass` | one primitive (`box` / `tapered` / `prism` / `cone` / `dome`) with a proportion spec |
| `stack` | children bottom-to-top, each sitting on the frame of the one below |
| `row` | children along local X, spaced by an `advance` fraction of the preceding width |
| `ring` | children repeated around a centre (columns, voussoirs) |
| `attach` | a child placed against a named anchor of its parent |

**Slice 1 implements `mass`, `stack` and `row` only.** `ring` and `attach`
arrive in slice 2 with the hero arch.

Two rules carry most of the weight:

**Proportions are ranges, not numbers.** `{"w": [0.55, 1.05]}`, sampled by hash
channel. A scalar is allowed and means a fixed value. As data, a range is
something a future mutation operator can widen, narrow or shift; as a literal
`0.55 + h01(...) * 0.5` buried in a function, it is not.

**Colour is a role, not a value.** `{"role": "plaster"}` resolved through the
style's palette mapping at emit time. Slice 1 ships a single default mapping;
per-culture mappings are slice 4.

### Evaluation: a pure fold returning parts and a frame

```
resolve(node, ctx) -> {parts: Array, frame: Frame}
Frame = {transform: Transform3D, footprint: Vector2, height: float}
```

Each node returns its parts **and** a frame describing the space it occupies.
Parent combinators use children's frames to place the next sibling. That frame
return is what replaces the per-recipe arithmetic: stacking and rowing exist
once.

`ctx` carries the world seed, the building id, the accumulated node-name path,
and the parent frame.

### Determinism: named channels

Channels are derived from **names, not positions**:

```
channel = h01(seed, building_id, hash(node_path_names), hash(purpose))
```

`node_path_names` is the `/`-joined chain of ancestor names, e.g.
`"block/unit/body"`. `purpose` is the field being sampled, e.g. `"w"`.

The rejected alternative is hashing the child *index* path. It is simpler and
it is wrong for this use case: inserting a node shifts every sibling after it,
so adding a porch rearranges the whole town. Named channels mean adding
`"porch"` leaves `"tier1"` untouched, and widening `tier1` does not move
`tier2`. This preserves reconciliation 1 (pure hashes) while surviving editing,
which is the entire point if the system is to be tinkered with.

**Accepted cost:** renaming a node re-rolls that subtree. This is the right
default — a rename is usually a redesign — but it is surprising once, and is
called out in the node docs.

### Tags are derived, never authored

After the fold completes the building's total height is known, so tags fall out
of normalised height plus node kind in a single post-pass:

| Band / kind | Tag |
|---|---|
| bottom 20% of total height | `base` |
| 20%–65% | `mid` |
| above 65% | `upper` |
| `cone` or `prism` whose frame footprint area is under 25% of the largest in the building | `accent` |

Consequence: **every new style inherits ruins and the assembly tween without
its author thinking about decay at all.** This is the property that makes the
system safe to thrash on.

### Where it plugs in

`resolve()` produces exactly the parts `DioramaGrammar.emit()` already consumes.
The resolver is therefore a **second producer for an existing contract**:

- `mesh_kit.gd`, `spike.gd` and `emit()` are not modified in slice 1.
- `DioramaGrammar`'s four recipe functions stay, and `spike.gd` keeps calling
  them. The diorama is unchanged by this slice.
- A style migrates only when its sheet says the tree version is as good.

There is no flag day and no cutover.

## Components

| Unit | Purpose | Depends on |
|---|---|---|
| `game/diorama/compose.gd` (`DioramaCompose`) | node types, `resolve()`, frames, channel derivation, tag post-pass | `DioramaHexKit` |
| `game/diorama/styles.gd` (`DioramaStyles`) | the style library — data literals, starting with `residential` | nothing |
| `game/diorama/lineup.tscn` + `lineup.gd` | specimen sheet: a grid of staged buildings, one camera, one light, `Label3D` captions | `DioramaCompose`, `DioramaGrammar.emit`, `DioramaMeshKit` |

Each is independently testable. `compose.gd` has no rendering dependency at all
and is fully exercised headless.

## The specimen sheet

**The sheet is a scene, not a montage.** N specimens on a grid, one camera, one
directional light, one render — no image compositing step, deterministic by
construction, and it runs on the existing `./capture.sh --scene` added by #24.

Specimens are **staged, not in-situ**: each cell is a building on a neutral pad
with identical camera, light and ground. Judging a building inside the full
valley confounds the building with where it landed.

A lineup is data:

```gdscript
{"rows": {"style": ["residential"]},
 "cols": {"seed": [1, 2, 3, 4, 5, 6]},
 "cell_size": 4.0}
```

Slice 1 only needs the `seed` axis. The `style` and `condition` axes are the
same mechanism and arrive with the styles and the condition filter.

**Known limitation, deliberately accepted:** a neutral stage flatters buildings.
Something with a good silhouette on a pad can disappear at diorama distance
behind two trees. The loop is therefore two-step — specimen sheet to *choose*,
in-situ frame to *confirm* — and slice 1 ships only the first step. It must not
be treated as sufficient evidence that a style works in the valley.

## Functional requirements

Control-flow decisions are stated here rather than deferred to an edge-case
section, because an implementer would otherwise have to invent them.

**FR-1** `resolve()` returns parts identical in shape to those produced by
`DioramaGrammar._part()`: keys `kind`, `xf`, `params`, `color`, `tag`, `y`.

**FR-1a** `y` is the part's centre height in building-local space, derived
from its frame during the same post-pass that assigns tags. No node authors a
`y`, for the same reason no node authors a tag.

**FR-2** A proportion field accepts either a scalar (fixed) or a two-element
array `[lo, hi]` (sampled). `lo > hi` is a programming error: assert, do not
silently swap. An empty or longer array is likewise an assertion failure.

**FR-3** Every node must carry a non-empty `name`. Two siblings under the same
parent sharing a name is an assertion failure — it would collapse their
channels and make them identical, which is never the intent and is otherwise
invisible.

**FR-4** `stack` places child *i+1* directly on top of child *i* using child
*i*'s frame height. Its own frame height is the sum of its children's; its
footprint is the maximum of its children's footprints. Slice 1 has **no setback
parameter**: its only consumer is `stepped`, which arrives in slice 2, and
defining it here would ship an untested feature whose semantics (does it
override the child's own footprint, or scale it?) nothing yet forces us to
decide.

**FR-5** `row` places children along local X. The cursor advances by
`advance` x the preceding child's width — a fraction, so it scales with the
building instead of being an absolute distance. `advance = 1.0` is flush,
`< 1.0` overlaps, `> 1.0` leaves a gap; the current `residential` uses `0.95`,
a deliberate slight overlap so terraced units read as joined. Named `advance`
rather than `gap` because a "gap" of 0.95 would naturally be read as a large
separation and it is the opposite. The row's frame footprint spans from the
first child's near edge to the last child's far edge; its height is the maximum
of its children's.

**FR-6** `row` accepts `count` (scalar or range) with an `of` template, or an
explicit `children` array — not both. `count` resolving to 0 produces zero parts
and a zero frame, which is legal (it is how a style expresses "sometimes
absent") and must not divide by zero downstream.

**FR-7** A `mass` with any dimension resolving to ≤ 0 emits no part and returns
a zero frame. Degenerate geometry is silently dropped by `mesh_kit.add_tri()`
already; dropping it earlier keeps the parts list honest and the tag post-pass
correct.

**FR-8** Tags are assigned in a post-pass over the completed parts list using
the bands in the table above, computed against the building's total height. No
node authors a tag. Every emitted part receives exactly one tag.

**FR-9** Channel derivation is `h01(seed, building_id, hash(path), hash(purpose))`
where `path` is the `/`-joined ancestor name chain. Sampling the same field of
the same node twice returns the same value.

**FR-10** `resolve()` performs no rendering, no scene-tree access, and no I/O.
It runs headless and is deterministic across processes.

**FR-11** The lineup scene builds its grid from a lineup dictionary, captions
each cell with a `Label3D` naming the varied axis value, and uses one camera and
one `DirectionalLight3D` for the whole sheet.

**FR-12** `residential` is expressed as a style tree in `styles.gd` and produces
a building recognisably of the same family as the current function: a row of
one to three units, each a plaster body under a tapered ochre roof. The target
literal, which also serves as the readability bar for the vocabulary — if the
data version is harder to read than the 16 lines of arithmetic it replaces, the
design has failed its own premise:

```gdscript
{"row": {"name": "block", "count": [1, 3], "advance": 0.95, "of":
  {"stack": {"name": "unit", "children": [
    {"mass": {"name": "body", "kind": "box",
              "w": [0.55, 1.05], "d": [0.55, 1.05], "h": [0.60, 1.30],
              "role": "plaster"}},
    {"mass": {"name": "roof", "kind": "tapered", "taper": 0.8,
              "h": 0.22, "oversize": 1.08, "role": "ochre"}}]}}}}
```

`oversize` on a `mass` scales its footprint relative to the frame it sits on,
which is how the roof overhangs its body (the current function's `w * 1.08`).
It defaults to `1.0`.

## Testing

Headless, per the repo's rule that the suite must run without a rendering
context.

- **Determinism:** same style + seed + id → identical parts; asserted by
  comparing full parts arrays, and across two processes via the existing
  `tools/diorama_fingerprint.gd` mechanism if the lineup is added to it.
- **Channel stability:** inserting a new named sibling leaves the existing
  siblings' sampled values unchanged. This is the named-channel promise and is
  the test most likely to catch a regression to index-based hashing.
- **Frame arithmetic:** a `stack`'s frame height equals the sum of its
  children's; a `row`'s footprint spans its children.
- **Tag coverage:** every part has a tag; a building's lowest part is `base` and
  its highest is `upper`; filtering to `condition = 0.5` removes `upper` parts
  before `base` parts.
- **Malformed input:** each of FR-2's and FR-3's assertion cases fails loudly.
- **Zero cases:** `count = 0` and a zero-dimension `mass` produce empty parts
  and zero frames without error.
- **Style parity, structurally rather than numerically:** the tree
  `residential` emits between 2 and 6 parts (one to three units, two parts
  each), alternating body and roof, with a positive total height and every roof
  sitting directly on its own body. Deliberately not a tolerance on part count
  or height against the old function — the two are allowed to diverge, and a
  numeric bound would either be so loose it asserts nothing or so tight it
  freezes a proof-of-concept model the owner has said is disposable.

Existing `mesh_kit` invariants continue to guard everything downstream and are
not duplicated here.

## Done bar for slice 1

- `compose.gd` with `mass`, `stack`, `row`, frames, named channels, tag post-pass
- `residential` expressed as data in `styles.gd`
- lineup scene + spec, producing one PNG via `./capture.sh --scene`
- the tests above, green in `./test.sh`
- one committed seed-lineup frame as evidence
- `spike.gd`, `mesh_kit.gd`, `emit()` and the existing recipes **unmodified**

## Explicitly out of scope

`ring`, `attach`, the remaining three styles, the condition filter, per-culture
palette mappings, `CultureStyle` parameters, mutation and crossbreed operators,
`.tres` resources, anything in-editor, LOD, and any form of parser or DSL. The
representation is GDScript literals; the moment it needs parsing, the design has
gone wrong.

## The arc (not specified here)

2. `ring` + `attach`, porting **`hero_arch` second, not last** — voussoirs
   tangent to an arc are the hardest thing in the current vocabulary, and if
   `ring` cannot express them the design is wrong. Better to learn that in
   slice 2 than after three more styles have been built on it. `civic` and
   `stepped` follow.
3. Condition filter over derived tags → the style × condition sheet.
4. Roles → per-culture palette mappings. One tree, two cultures; the natural
   start of S3, and where the palette/lab-parity work deferred from #25 lands.

## Risks

**The vocabulary may not reach far enough.** Slice 2 is where that surfaces.
Mitigation is ordering — hardest case early — not cleverness.

**Derived tags may not suit every style.** A style whose interesting mass sits
in the bottom 20% would lose it first under a ruin filter. The slice 3 condition
sheet makes this visible; if it bites, tags gain an optional per-node override,
which is a small addition rather than a redesign.

**A second producer is a second thing to keep working.** Until every style has
migrated, `grammar.gd` has both hardcoded recipes and data styles. That is the
price of avoiding a cutover, and it ends when slice 2 completes.

**Concurrency.** Ticket #17 was implemented twice simultaneously by two
sessions, and the collision was caught only because git could not auto-merge it.
Before this is dispatched, decide whether it goes through switchboard or stays
interactive, and check `gh pr list --state open` before starting.
