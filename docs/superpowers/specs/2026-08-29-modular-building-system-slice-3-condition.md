# Modular building system — slice 3: condition

**Ticket:** #34. **Parent intent:** `procedural-art`.
**Supersedes:** the "Tags are derived, never authored" section of
`2026-08-26-modular-building-system-design.md`, and that spec's stated
mitigation for the derived-tag risk.

---

## Why this, and why now

The intent's rule is that **ruins are the same buildings** — no separate ruin
assets, no second art pipeline. Condition transforms the generated structure
itself, and a culture's handwriting survives its collapse because the broken
geometry keeps its proportions.

Slice 1 built the input that rule needs: every part carries a tag derived in a
post-pass, so no style author thinks about decay. Slice 3 is the payoff for that
design and the test of whether it was right.

It was not right. This spec replaces the instrument.

It matters now rather than later for the same reason named channels mattered in
slice 1: **it is a change to the parts contract.** Every style authored before
it lands is authored against the old one. With four styles that is cheap; with
twenty it is not. Unlike a `choice` node — additive, retrofittable, no deadline
— this has one.

---

## What slice 1 got wrong, measured

Slice 1 derived four tags from normalised height plus node kind:

| Band / kind | Tag |
|---|---|
| bottom 20% of total height | `base` |
| 20%–65% | `mid` |
| above 65% | `upper` |
| `cone`/`prism` under 25% of the largest footprint | `accent` |

A census over the four migrated styles, 24 seeds each, gives the distribution
that scheme actually produces:

| style | parts | `base` | `mid` | `upper` | `accent` |
|---|---|---|---|---|---|
| residential | 98 | **0.0%** | 54.1% | 45.9% | 0.0% |
| hero_arch | 336 | 7.1% | 64.3% | 21.4% | 7.1% |
| civic | 192 | 12.5% | 12.5% | 12.5% | **62.5%** |
| stepped | 120 | 40.0% | 40.0% | **0.0%** | 20.0% |

Three independent failures, not one:

1. **`residential` has no `base` at all** — zero seeds out of 24. At the
   intent's 0.25 rung ("structural remnants, exposed foundations") it has
   nothing to keep. It does not ruin; it vanishes. This is the failure slice 1's
   own risk section predicted.

2. **`stepped` has no `upper`** — so decay has no *ordering*. Nothing is lost
   first. It goes from whole to gone.

3. **`civic` is 62.5% `accent`** — the sharpest. Its colonnade is five prisms
   with small footprints, so the accent rule claims them. The parts tagged
   *decorative, first to go* are the columns holding the building up. The hall
   survives; its supports are stripped first.

A per-part dump explains (1) and (3). `residential` at seed 42 is a row of two
units of different heights, normalised against the taller:

| role | kind | bottom | top | t (centre) | tag |
|---|---|---|---|---|---|
| plaster | box | 0.00 | 0.63 | 0.21 | `mid` |
| ochre | tapered | 0.63 | 0.85 | 0.50 | `mid` |
| plaster | box | 0.00 | 1.26 | 0.43 | `mid` |
| ochre | tapered | 1.26 | 1.48 | 0.93 | `upper` |

The short unit's **roof** and the tall unit's **load-bearing wall** land in the
same band. Under ordered loss they vanish together.

### The failure is not a bad constant

Measuring each part by its base (`bottom / total`) instead of its centre repairs
all three cases — bodies become `base`, roofs become `mid`/`upper`, `stepped`
gains an `upper` — and it has a real justification: what survives a collapse is
what is still attached to the ground.

It is still the wrong answer, because of `hero_arch`. Its voussoirs sit at
`bottom / total` of 0.34–0.62 — squarely mid-band. Under *any* height scheme, at
low condition you keep the plinth and the piers and the arc is gone. Two stumps.

**Height is orthogonal to structural essentiality, and the flagship style is the
counterexample.** The arc is simultaneously the highest thing in the building and
the most essential. No tuning of a height function reconciles that.

### The mitigation slice 1 named is also wrong

Slice 1 wrote: *"if it bites, tags gain an optional per-node override, which is a
small addition rather than a redesign."*

An override hands every style author responsibility for decay again — the exact
property deriving tags was introduced to remove. It also does not scale: it is a
patch per style, applied by whoever notices, and the census shows the failures
are not exceptional cases but the common one.

---

## Prior art: the lab already ships ruins, and it does not transfer

`tools/blender/civlife_blender/aging.py` has a working `ruin()`. It is close to
the design below and it validates the direction:

```python
need = 0.15 + zn * 0.75              # continuous per-part survival threshold
if   tag == "accent": need = max(need, 0.82)
elif tag == "crown":  need = max(need, 0.68)
elif tag == "base":   need = 0.02
need += (rng.random() - 0.5) * 0.12  # seeded jitter
if condition >= need: survivors.append(p)
```

Two things to take from it, and one trap.

**Take:** a continuous per-part threshold rather than a category, and a seeded
jitter so that two buildings of one style do not ruin identically.

**Take:** the diagnosis. The lab keys `need` on normalised height — the function
shown broken above — and it works there *because authored tags clamp it*.
`architecture.py` writes `"tag": "base"` and `"tag": "crown"` by hand. **The
height function was never load-bearing; the tags were.** Slice 1 removed the
authoring and kept the height function.

**The trap:** in the lab, an arch is *one part*. `P.arch(...)` returns a single
mesh, appended once, tagged `"mid"`, at a low `z`. It survives because it is one
low part. The lab never faced the question. Slice 2 built the arch as a **ring of
nine voussoirs** — which was the entire reason `ring` was added to the
vocabulary.

The composition that made `ring` worth building is exactly what breaks the lab's
flat, height-keyed decay. The lab bought the right image by making the arch
atomic. This slice buys it by making the arch an assembly that decays as a unit —
same image, but it composes.

---

## Architecture

### 1. One number per part, replacing the tag

Each part carries **`need`**: a float in `[0, 1]`, the condition at or above
which it survives. The filter is:

```gdscript
parts.filter(func(p): return effective_condition >= p["need"])
```

`tag` is removed. On the Godot side it is write-only today — `compose.gd` is the
only file that mentions it; nothing in `game/`, `test/` or `tools/` reads it — so
the swap has no blast radius. (`tools/blender/` has its own `tag`, in Python, on
a different part dictionary. The two were never coupled.)

Three acceptance criteria become structural rather than tested-for:

- **AC2, ordered loss.** Filtering on a fixed per-part threshold is monotone *by
  construction*. The nested-subset property cannot be violated by any style.
- **AC3, determinism.** `need` is drawn from the existing hash channels, so it
  inherits the cross-process fingerprint gate unchanged.
- **The assembly tween** (owner decision, 2026-08-23). Sorting by descending
  `need` is the arrival order. One float, both directions of time — which is what
  the intent asked for and what the tag scheme could not give, because tags are a
  four-way partition and assembly needs a total order.

**AC6 is dissolved rather than answered.** The ticket asks for a stated `accent`
rule. There is no `accent` category under this design: a finial is a leaf high in
a stack that drew a high `need`. The reason to state is that the accent rule was
a geometry proxy (`is it pointy and small?`) for a structural question
(`does anything rest on it?`), and it inverted on `civic` because a column is
pointy and small and also load-bearing.

### 2. `need` comes from node type, so nothing is authored

Computed during resolution, on the tree `resolve()` already walks. Each node
receives an inherited **floor** and returns the `need` that whatever rests on it
must respect.

Only nodes that correspond to a physical thing draw. Containers combine.

```
draw(node) = LO + (HI - LO) * channel(seed, id, path, "endure")
```

| node | rule | why |
|---|---|---|
| `mass` | `need = max(floor, draw(node))`; the emitted part carries it | A leaf is a thing. It draws. |
| `stack` | running floor across children in order: child *i* is resolved with the floor set to child *i−1*'s returned `need` | Nothing floats. **The running max up a stack is the load path**, free from the vocabulary — a part can never outlive what it rests on. |
| `row` | every child resolved with the inherited floor, unchanged | Siblings are independent. A terrace loses one house, not the street. |
| `ring` | **cohesive**: one `max(floor, draw(ring))`, imposed on every part in its subtree; children do not draw | Remove one voussoir and an arch collapses. The arc survives or falls whole. |

A container returns the **maximum** `need` over its children — the weakest link,
since the highest `need` is the first to fall, and what rests on the container
fails when any of its supports does.

`LO = 0.10`, `HI = 0.90`. Both are tuning constants and the sheet is what tunes
them.

### 3. What that produces

Worked through `hero_arch` — `stack[plinth, row[west, east], ring[voussoir ×9],
entablature, finial]` — with illustrative draws:

| child | draw | floor in | `need` |
|---|---|---|---|
| plinth | 0.11 | 0.00 | 0.11 |
| piers (row) | west 0.30, east 0.18 | 0.11 | **0.30** (max) |
| span (ring, cohesive) | 0.22 | 0.30 | **0.30** — all nine voussoirs |
| entablature | 0.71 | 0.30 | 0.71 |
| finial | 0.44 | 0.71 | 0.71 |

The arc comes out **exactly as durable as the piers it springs from**. That is
physically true, and it means the Roman-ruin image is guaranteed by the structure
rather than won by a lucky draw:

- **condition 0.50** — plinth, both piers, full arc. Entablature and finial gone.
  A bare arch standing on a plinth.
- **condition 0.25** — plinth and the east pier. The west pier and the arc it
  carried are gone. A standing stump.

The other three:

- **`residential`** — a row of unit stacks. Roof needs its body (stack rule);
  units are mutually independent (row rule). One roofless house beside an intact
  one.
- **`civic`** — the portico is a `row`, so its five columns draw independently:
  **a colonnade with gaps in it.** Note this is the "parts within assemblies"
  behaviour that was considered and declined during design — it arrives free from
  the row rule, without a second level of machinery.
- **`stepped`** — a stack, so a strictly increasing `need` going up. Sheds
  top-down, spire first, and finally has the ordering the census showed it
  lacked.

### 4. The standing-fragment rule

Below the smallest `need` in a building, the filter returns nothing, and the
never-empty fallback would return a single plinth. A bare pad is not a ruin; it
is a foundation, and it reads desolate — against the intent's guardrail that
ruins imply use and adaptation.

The intent's bottom rung is *"footprint **and** a surviving arch or wall."* Two
things.

```gdscript
if condition <= 0.0:
    return []                                              # 0 means gone
effective_condition = maxf(condition, second_smallest_distinct_need)
```

One line, plus a sentinel. The clamp raises condition so that at least the two
most durable levels survive: the footprint, plus one fragment above it. Which
fragment varies by seed, so a field of ruins is not a field of identical stumps.

`condition == 0` is exempt and returns nothing. AC5 is worded "condition **above**
0 always yields at least one part", and the intent's ladder bottoms out at 0.05,
so zero is free to mean *gone* — which is worth having as a sentinel for a
building that has been removed rather than ruined.

It preserves AC2: clamping upward is monotone, and two conditions below the floor
produce identical sets, which are supersets of each other. It makes AC4 true
**per building** rather than true on average.

Degenerate case: a building with one distinct `need` uses the smallest, and all
parts survive.

### 5. Where it plugs in

- `compose.gd` computes `need` during resolution. It remains pure: no rendering,
  no scene tree, no I/O (AC9).
- A new `game/diorama/condition.gd` holds the filter and the fragment rule. It is
  ~20 lines over a flat array and knows nothing about the tree — the tree work
  already happened.
- `lineup.gd` gains a condition axis.
- `spike.gd` and `mesh_kit.gd` are untouched. `emit()` consumes parts that have
  one fewer field and one new one; it reads neither.

---

## Components

| File | Change |
|---|---|
| `game/diorama/compose.gd` | Compute `need` per node type; drop `tag` derivation from `_finish` |
| `game/diorama/condition.gd` | **New.** `filter(parts, condition) -> Array` plus the fragment rule |
| `game/diorama/lineup.gd`, `.tscn` | Condition axis on the specimen sheet |
| `test/test_diorama_condition.gd` | **New.** Monotonicity, cohesion, load path, never-empty |
| `test/test_diorama_compose.gd` | Replace tag assertions with `need` assertions |
| `tools/diorama_compose_fingerprint.gd` | Fold `need` in, so the determinism gate covers it |
| `docs/shots/` | The style × condition sheet |

---

## The style × condition sheet

Per AgDR-008 and AgDR-011: committed under `docs/shots/`, linked by absolute
sha-pinned URL. Four styles down one axis, the intent's five rungs — 1.0, 0.75,
0.5, 0.25, 0.05 — across the other. One camera, one light, one render, one seed
per row so the ladder is legible as decay of *the same building*.

The sheet is the deliverable that answers AC11, and it is the only thing that
can. Everything above is a hypothesis about what will look right.

---

## Testing

Structural properties, asserted directly:

1. **Monotone.** For any style, seed and pair of conditions `c1 < c2`, the
   survivors at `c1` are a subset of those at `c2`. Swept over all four styles ×
   many seeds × the five rungs.
2. **Ring cohesion.** Every part emitted under a `ring` shares one `need`. A
   filter at any condition returns either all of them or none.
3. **Load path.** In a stack, `need` is non-decreasing across children in order.
   No part outlives its support.
4. **Row independence.** Two `row` siblings can have different `need` — asserted
   by finding at least one seed where a `residential` filter leaves one unit
   standing and its neighbour partly gone. (Guards against a change that
   accidentally makes rows cohesive; a passing test that never observes the
   condition is worthless, so this must assert the difference was *found*.)
5. **Never empty** for every condition in `(0, 1]`, and — for any building with
   more than one distinct `need` — never a single part. Exactly empty at
   `condition == 0`.
6. **Determinism**, through the existing cross-process fingerprint gate.
7. **The census does not regress.** The measurement that motivated this spec,
   re-run as a test. Asserting "every style has a part at its own minimum `need`"
   would be vacuous — that is true by definition. The assertion that has teeth is
   **spread**: for each style, over 24 seeds, at least three distinct `need`
   levels, and `max(need) − min(need)` above a stated threshold. That is what
   `stepped` (0% `upper`) and `residential` (0% `base`) would each have failed,
   and it is the property a ladder needs to exist at all.

---

## Done bar

1. `need` replaces `tag`; every acceptance criterion in #34 is met or explicitly
   answered.
2. `./test.sh` exits 0.
3. The style × condition sheet is committed and linked.
4. The PR body states that **AC11 and AC12 are unverified by the agent** — a
   reading of the sheet and a judgment about tone are the owner's.

---

## Explicitly out of scope

- Weathering, patina, or any colour change with condition. Condition selects
  parts; it does not re-grade them. (`aging.py` returns an `age` for material
  weathering — deliberately not ported.)
- Vegetation intrusion, debris, reclamation geometry. `aging.py`'s `debris()` is
  not ported.
- The assembly tween itself. This slice builds the ordering it will run in
  reverse; wiring it to turn advance needs a sim-side arrival to tween from.
- Per-culture palettes (slice 4).
- Any hook to simulation state. Nothing in `sim/` has a condition, and per intent
  reconciliation 3 the renderer trails the sim. The sheet is driven by synthetic
  values.
- `sim/` — untouched.
- A `choice` node for structural variation. Still the largest known gap in the
  vocabulary, still additive and retrofittable, still no deadline.

---

## Risks

**The constants are guesses.** `LO`, `HI`, and the five rungs' spacing are set
from the lab's numbers, not from this vocabulary. The sheet is what tunes them
and it may take two rounds.

**Row independence may look like damage, not decay.** A colonnade with gaps is
the classic ruin; a terrace with one unit missing may read as a rendering bug.
If it does, the fix is to make `row` cohesive by default with independence opted
into — a one-line change to the table above, not a redesign.

**The fragment rule may be too generous at 1.0 → 0.75.** It only clamps at the
bottom of the range, so it should not, but a style whose parts all draw high
would have a high floor and never appear to decay at all. The monotonicity test
will not catch this; the sheet will.

**`need` is a scalar and structure is not.** Two parts with equal `need` fall
together even if they are unrelated. Across four styles that is invisible. It is
the first thing to revisit if ruins start reading as sliced rather than collapsed.

**Concurrency.** #17 was implemented twice at once and the collision was caught
only because git could not auto-merge it. This session holds the main checkout;
a peer session holds `.claude/worktrees/jovial-burnell-e5d8aa`. Check
`gh pr list --state open` before dispatch, and run the suite against the **merge
result on main**, not just the branch.
